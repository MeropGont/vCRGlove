"""Synthetic regression checks; no patient data or external reference cohort."""
import copy
import math
from pathlib import Path
import tempfile
import unittest
import uuid

import review_tapping_angles as review


def fixture():
    return [{"id": str(uuid.uuid4()), "trials": [{
        "id": str(uuid.uuid4()), "taskType": "3.4", "source": "camera", "side": "right",
        "samples": [{"t": 0, "value": 0.2}, {"t": 0.1, "value": 0.7}],
        "fingerTappingAngle": {"measurementVersion": review.ANGLE_VERSION,
            "unit": "degrees", "timeReference": "seconds_since_trial_start",
            "samples": [{"t": 0, "degrees": 0}, {"t": 0.1, "degrees": None}]}}]}]


class ReviewTests(unittest.TestCase):
    def test_zero_is_valid_and_null_is_missing(self):
        samples = fixture()[0]["trials"][0]["fingerTappingAngle"]["samples"]
        review.validate_samples(samples, True)
        self.assertEqual(review.angle_features(samples)["valid_frames"], 1)
        self.assertEqual(review.angle_features(samples)["angle_p05_degrees"], 0)

    def test_invalid_samples_rejected(self):
        for samples in ([{"t": -1, "value": 1}], [{"t": True, "value": 1}],
                        [{"t": 0, "value": float("nan")}], [{"t": 0, "value": True}],
                        [{"t": 0, "value": 1}, {"t": 0, "value": 2}],
                        [{"t": 1, "value": 1}, {"t": 0, "value": 2}]):
            with self.subTest(samples=samples), self.assertRaises(ValueError):
                review.validate_samples(samples)
        for value in (-1, 181, float("inf")):
            with self.subTest(value=value), self.assertRaises(ValueError):
                review.validate_samples([{"t": 0, "degrees": value}], True)

    def test_velocity_uses_actual_time_and_never_crosses_missing_or_gap(self):
        samples = [{"t": 0, "degrees": 0}, {"t": 0.1, "degrees": 10},
                   {"t": 0.15, "degrees": None}, {"t": 0.2, "degrees": 80},
                   {"t": 0.6, "degrees": 0}, {"t": 0.65, "degrees": 10}]
        features = review.angle_features(samples)
        self.assertEqual(features["segment_count"], 3)
        self.assertAlmostEqual(features["tracked_seconds"], 0.15)
        self.assertAlmostEqual(features["raw_absolute_velocity_median_deg_s"], 150)

    def test_pairing_never_interpolates(self):
        distance = [{"t": 0, "value": 2}, {"t": 0.1, "value": 4}]
        angles = [{"t": 0, "degrees": 0}, {"t": 0.05, "degrees": 20},
                  {"t": 0.1, "degrees": None}]
        self.assertEqual(review.paired_values(distance, angles), [(0, 2, 0)])
        self.assertIsNone(review.correlation([(0, 1, 2)] * 3))
        self.assertAlmostEqual(review.correlation([(0, 1, 2), (1, 2, 4), (2, 3, 6)]), 1)

    def test_event_matching_is_one_to_one_and_inclusive(self):
        matched = review.match_events([1, 2, 3], [1.1, 1.11, 2.5])
        self.assertEqual(matched["matched"], 1)
        self.assertEqual(matched["distance_unmatched"], 2)
        self.assertEqual(matched["angle_unmatched"], 2)

    def test_supported_contract_and_legacy_skip(self):
        data = fixture()
        self.assertEqual(len(review.collect_trials(data)[0]), 1)
        for field in ("measurementVersion", "unit", "timeReference"):
            bad = copy.deepcopy(data)
            bad[0]["trials"][0]["fingerTappingAngle"][field] = "unsupported"
            with self.subTest(field=field), self.assertRaises(ValueError):
                review.collect_trials(bad)
        del data[0]["trials"][0]["fingerTappingAngle"]
        selected, skipped = review.collect_trials(data)
        self.assertFalse(selected)
        self.assertEqual(len(skipped), 1)

    def test_other_task_or_source_not_compared(self):
        for field, value in (("taskType", "3.5"), ("source", "watch")):
            data = fixture()
            data[0]["trials"][0][field] = value
            self.assertEqual(review.collect_trials(data), ([], []))

    def test_identity_validation_and_normalized_duplicates(self):
        data = fixture()
        duplicate = copy.deepcopy(data[0])
        duplicate["id"] = duplicate["id"].upper()
        with self.assertRaises(ValueError):
            review.collect_trials(data + [duplicate])
        data[0]["trials"].append(copy.deepcopy(data[0]["trials"][0]))
        with self.assertRaises(ValueError):
            review.collect_trials(data)
        for value in (None, 42, "invalid"):
            bad = fixture()
            bad[0]["id"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                review.collect_trials(bad)

    def test_video_matching_is_not_accuracy_validation(self):
        trial = fixture()[0]["trials"][0]
        name = trial["id"].upper() + ".mov"
        trial["video"] = {"fileName": name, "byteCount": 3}
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            path = directory / name
            path.write_bytes(b"abc")
            self.assertIn("not independently validated", review.video_status(trial, directory))
            trial["video"]["byteCount"] = 4
            self.assertIn("differs", review.video_status(trial, directory))
            path.unlink()
            path.symlink_to(directory / "missing.mov")
            self.assertIn("not verified", review.video_status(trial, directory))
            trial["video"]["fileName"] = "../unsafe.mov"
            with self.assertRaises(ValueError):
                review.video_status(trial, directory)

    def test_actual_swift_engine_periodic_empty_and_gaps(self):
        trial = fixture()[0]["trials"][0]
        times = [i / 30 for i in range(300) if not 100 <= i < 130]
        trial["samples"] = [{"t": t, "value": 1 + 0.5 * math.sin(4 * math.pi * t)} for t in times]
        trial["fingerTappingAngle"]["samples"] = [
            {"t": t, "degrees": 30 + 15 * math.sin(4 * math.pi * t)} for t in times]
        empty = copy.deepcopy(trial)
        empty["samples"] = []
        empty["fingerTappingAngle"]["samples"] = [{"t": 0, "degrees": None}]
        result = review.run_analyzer([({}, trial), ({}, empty)])
        distance, angle = result["T01:distance"], result["T01:angle"]
        self.assertEqual(distance["metrics"]["cycleCount"], angle["metrics"]["cycleCount"])
        self.assertGreater(distance["metrics"]["cycleCount"], 10)
        self.assertAlmostEqual(distance["metrics"]["frequencyHz"], 2, delta=0.15)
        self.assertEqual(distance["intervalCount"], distance["metrics"]["cycleCount"] - 2)
        self.assertEqual(result["T02:angle"]["metrics"]["cycleCount"], 0)


if __name__ == "__main__":
    unittest.main()
