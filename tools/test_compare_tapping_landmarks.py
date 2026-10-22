import copy
import math
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
from types import SimpleNamespace

import compare_tapping_landmarks as review


class PairedLandmarkTests(unittest.TestCase):
    def window_fixture(self):
        samples = [{"t": i/60, "degrees": 20-20*math.cos(4*math.pi*i/60)} for i in range(600)]
        pairs = [{"trial_seconds": s["t"], "vision_degrees": s["degrees"],
                  "mediapipe_degrees": s["degrees"], "difference_degrees": 0,
                  "timestamp_error_seconds": 0, "reason": "paired"} for s in samples]
        segment = {"selectionVersion": "vision-first-ten-consecutive-complete-taps-v1",
                   "sourceAngleVersion": review.ANGLE_VERSION,
                   "detectorVersion": "vision-angle-timestamp-gap-aware-v1",
                   "completedTapCount": 10, "firstSampleIndex": 15,
                   "endSampleIndexExclusive": 316, "startTrialTimeSeconds": .25,
                   "endTrialTimeSeconds": 5.25, "openingPeakTimes": [.25+i*.5 for i in range(11)]}
        return samples, pairs, segment

    def test_fixed_window_preserves_boundaries_and_actual_time_speed(self):
        samples, pairs, segment = self.window_fixture()
        before = copy.deepcopy((samples, pairs, segment))
        result = review.fixed_window_agreement(samples, pairs, segment)
        self.assertEqual(result["source_sample_range"], [15, 316])
        self.assertEqual(result["elapsed_seconds"], 5)
        self.assertEqual(result["same_window_actual_time_mean_absolute_speed"]["relative_difference_percent"], 0)
        self.assertTrue(all(f["difference"] == 0 for f in result["author_kernel"]["features"].values()))
        self.assertEqual((samples, pairs, segment), before)

    def test_fixed_window_missing_pair_never_bridges_or_restarts(self):
        samples, pairs, segment = self.window_fixture()
        pairs[100].update(mediapipe_degrees=None, difference_degrees=None, reason="no_hand")
        result = review.fixed_window_agreement(samples, pairs, segment)
        self.assertFalse(result["same_window_actual_time_mean_absolute_speed"]["available"])
        common = result["common_observed_interval_mean_absolute_speed"]
        self.assertEqual(common["adjacent_interval_count"], 298)
        self.assertAlmostEqual(common["window_time_fraction"], 298/300)
        self.assertEqual(common["relative_difference_percent"], 0)
        self.assertFalse(common["interpolation"])
        self.assertEqual(result["source_sample_range"], [15, 316])
        self.assertFalse(result["healthy_reference_eligible"])

    def test_fixed_window_rejects_unknown_contract_and_misaligned_samples(self):
        samples, pairs, segment = self.window_fixture()
        self.assertFalse(review.fixed_window_agreement(samples, pairs, None)["available"])
        for field, value in (("completedTapCount", 9), ("firstSampleIndex", -1),
                             ("selectionVersion", "future"), ("endTrialTimeSeconds", 6)):
            invalid = {**segment, field: value}
            with self.assertRaises(ValueError):
                review.fixed_window_agreement(samples, pairs, invalid)
        pairs[20]["trial_seconds"] += .001
        with self.assertRaises(ValueError):
            review.fixed_window_agreement(samples, pairs, segment)

    def test_display_orientation_is_explicit_and_recorded(self):
        cv = SimpleNamespace(CAP_PROP_ORIENTATION_META=1, CAP_PROP_ORIENTATION_AUTO=2,
                             CAP_PROP_FRAME_WIDTH=3, CAP_PROP_FRAME_HEIGHT=4)
        capture = Mock()
        values = {1: 90, 2: 0, 3: 720, 4: 1280}
        capture.get.side_effect = values.get
        capture.set.side_effect = lambda key, value: values.update({key: value}) or True
        capture.getBackendName.return_value = "FFMPEG"
        result = review.display_orientation(capture, cv)
        self.assertEqual(result["display_dimensions"], [720, 1280])
        self.assertEqual(result["orientation_metadata_degrees"], 90)
        capture.set.assert_called_once_with(2, 1)
        values[1] = 45
        with self.assertRaises(ValueError):
            review.display_orientation(capture, cv)
        values[1] = 90
        capture.set.side_effect = lambda key, value: False
        with self.assertRaises(ValueError):
            review.display_orientation(capture, cv)

    def frame(self, time, degrees=0, index=0):
        return {"movie_seconds": time, "frame_index": index, "degrees": degrees,
                "integer_pixel_degrees": degrees, "reason": "detected" if degrees is not None else "no_hand"}

    def timing(self):
        return {"firstFrameTrialTimeSeconds": -.06, "firstFrameMoviePTSSeconds": 0}

    def test_aspect_correct_angles_and_zero(self):
        self.assertAlmostEqual(review.angle([[.5,.5],[.6,.5],[.5,.7]], 720, 1280), 90)
        self.assertAlmostEqual(review.angle([[.5,.5],[.6,.5],[.6,.5]], 720, 1280), 0)
        self.assertAlmostEqual(review.angle([[.5,.5],[.4,.5],[.6,.5]], 720, 1280), 180)
        expected = math.degrees(math.atan2(.1*1280, .1*720))
        self.assertAlmostEqual(review.angle([[.5,.5],[.6,.5],[.6,.6]], 720, 1280), expected)

    def test_geometry_rejects_missing_nonfinite_and_degenerate(self):
        for points in ([[.5,.5],[.5,.5],[.6,.6]], [[.5,.5],[2,.5],[.6,.6]],
                       [[.5,.5],[.6,math.nan],[.6,.6]], [[.5,.5]]):
            self.assertIsNone(review.angle(points, 720, 1280))
        self.assertIsNone(review.angle([[0,0],[.5,0],[0,.5]], 0, 720))

    def test_pixel_quantization_is_separate(self):
        points = [[.513,.512],[.611,.513],[.623,.631]]
        floating = review.angle(points, 720, 1280)
        quantized = review.angle(points, 720, 1280, integer_pixels=True)
        self.assertNotEqual(floating, quantized)
        self.assertLess(abs(floating-quantized), 1)

    def test_signed_capture_offset_and_true_zero_are_preserved(self):
        result = review.pair_frames([{"t": .04, "degrees": 0}], [self.frame(.1, 0)], self.timing())
        self.assertEqual(result[0]["reason"], "paired")
        self.assertEqual(result[0]["difference_degrees"], 0)
        self.assertAlmostEqual(result[0]["mapped_movie_seconds"], .1)

    def test_no_signal_fitted_offset_or_interpolation(self):
        result = review.pair_frames([{"t": 1, "degrees": 20}], [self.frame(.1, 20)], self.timing())
        self.assertEqual(result[0]["reason"], "no_nearby_frame")
        self.assertIsNone(result[0]["difference_degrees"])

    def test_missing_channels_do_not_become_zero(self):
        samples = [{"t": .04, "degrees": None}, {"t": .08, "degrees": 0}]
        frames = [self.frame(.1, 0), self.frame(.14, None, 1)]
        pairs = review.pair_frames(samples, frames, self.timing())
        self.assertEqual([p["reason"] for p in pairs], ["vision_missing", "no_hand"])
        self.assertEqual(review.summary(pairs)["paired_frames"], 0)

    def test_frames_are_not_reused(self):
        samples = [{"t": .04, "degrees": 10}, {"t": .041, "degrees": 20}]
        pairs = review.pair_frames(samples, [self.frame(.1, 10)], self.timing())
        self.assertEqual(pairs[1]["reason"], "frame_already_paired")

    def test_invalid_decoded_clocks_and_loose_tolerance_fail(self):
        for frames in ([], [self.frame(math.nan)], [self.frame(1), self.frame(1)],
                       [self.frame(1), self.frame(.5)]):
            with self.assertRaises(ValueError):
                review.pair_frames([], frames, self.timing())
        with self.assertRaises(ValueError):
            review.pair_frames([], [self.frame(0)], self.timing(), tolerance=.1)

    def test_statistics_describe_signed_frame_differences_not_norms(self):
        pairs = [{"reason": "paired", "difference_degrees": d, "timestamp_error_seconds": .001}
                 for d in (-2, 0, 2)]
        result = review.summary(pairs)
        self.assertEqual(result["mean_difference_degrees"], 0)
        self.assertEqual(result["median_absolute_difference_degrees"], 2)
        self.assertEqual(result["p95_absolute_difference_degrees"], 2)
        self.assertNotIn("healthy_reference_interval", result)

    def test_unknown_contracts_and_video_reference_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            video = Path(directory) / "trial.mov"
            video.write_bytes(b"test")
            trial = {"taskType": "3.4", "source": "camera", "fingerTappingAngle": {
                "measurementVersion": review.ANGLE_VERSION, "unit": "degrees",
                "timeReference": "seconds_since_trial_start", "samples": [{"t": 0, "degrees": 0}]},
                "video": {"fileName": video.name, "byteCount": 4, "timing": {
                    "version": 1, "method": review.TIMING_METHOD, **self.timing()}}}
            review.validate_trial(trial, video)
            for group, field, value in (("video", "byteCount", 5), ("video", "fileName", "other.mov"),
                                        ("fingerTappingAngle", "unit", "radians")):
                invalid = copy.deepcopy(trial)
                invalid[group][field] = value
                with self.assertRaises(ValueError):
                    review.validate_trial(invalid, video)
            invalid = copy.deepcopy(trial)
            invalid["video"]["timing"]["method"] = "unknown"
            with self.assertRaises(ValueError):
                review.validate_trial(invalid, video)

    def test_identical_channels_match_all_fifty_author_features(self):
        samples = [{"t": i/30, "degrees": 30-30*math.cos(2*math.pi*i/15)} for i in range(600)]
        pairs = [{"mediapipe_degrees": s["degrees"]} for s in samples]
        result = review.feature_agreement(samples, pairs, 20)
        self.assertTrue(result["available"])
        self.assertEqual(len(result["features"]), 50)
        self.assertTrue(all(v["difference"] == 0 for v in result["features"].values()))
        self.assertFalse(result["healthy_reference_eligible"])

    def test_irregular_timing_and_flat_signals_leave_features_unavailable(self):
        for samples in ([{"t": i/30, "degrees": 0} for i in range(600)],
                        [{"t": 1+i/30, "degrees": 30-30*math.cos(2*math.pi*i/15)} for i in range(600)]):
            result = review.feature_agreement(samples, [{"mediapipe_degrees": s["degrees"]} for s in samples], 20)
            self.assertFalse(result["available"])
            self.assertNotIn("features", result)


if __name__ == "__main__":
    unittest.main()
