import copy
import math
from pathlib import Path
import tempfile
import unittest

import numpy as np

import roc_tapping_features as roc
from verify_roc_tapping_features import load_oracle
from extract_roc_tapping_features import run_trial


def periodic(count=300, fps=30, rate=2):
    return [30 * (1 - math.cos(2 * math.pi * rate * i / fps)) for i in range(count)]


class ROCTests(unittest.TestCase):
    def test_known_periodic_features(self):
        signal = periodic(count=320, rate=1.875)
        result = roc.extract_features(signal, 320 / 30)
        values = result["features"]
        self.assertAlmostEqual(values["frequency_mean_trimmed"], 1.875)
        self.assertAlmostEqual(values["period_mean_trimmed"], 16 / 30)
        self.assertAlmostEqual(values["amplitude_mean_trimmed"], 60)
        self.assertEqual(result["missing_input_frames"], 0)
        self.assertEqual(result["interpolated_frame_count"], 0)

    def test_zero_angles_are_not_missing(self):
        result = roc.extract_features(periodic(), 10)
        self.assertIn(0, periodic())
        self.assertEqual(result["missing_input_frames"], 0)

    def test_short_missing_runs_are_counted_not_hidden(self):
        signal = periodic()
        signal[101] = None
        result = roc.extract_features(signal, 10)
        self.assertEqual(result["missing_input_frames"], 1)
        self.assertEqual(result["interpolated_frame_count"], 1)

    def test_long_missing_run_selects_one_segment(self):
        signal = periodic(600)
        signal[150:210] = [None] * 60
        result = roc.extract_features(signal, 20)
        self.assertGreater(result["selected_frame_range"][0], 150)
        self.assertLessEqual(result["selected_frame_range"][0], 210)
        self.assertEqual(result["selected_frame_range"][1], 600)
        self.assertTrue(all(i >= result["selected_frame_range"][0] for i in result["opening_peak_frame_indices"]))

    def test_input_unchanged(self):
        signal = periodic()
        signal[22] = None
        original = copy.deepcopy(signal)
        roc.extract_features(signal, 10)
        self.assertEqual(signal, original)

    def test_flat_short_and_open_only_are_unavailable(self):
        for signal in ([None] * 300, [0] * 300, [50] * 300, periodic(20),
                       [v + 30 for v in periodic()]):
            with self.subTest(length=len(signal)), self.assertRaises(roc.Unavailable):
                roc.extract_features(signal, len(signal) / 30)

    def test_invalid_values_and_duration(self):
        for value in (-1, 181, float("nan"), float("inf"), True, "30"):
            signal = periodic()
            signal[100] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                roc.extract_features(signal, 10)
        for duration in (0, -1, float("nan"), True, None, 1e-320):
            with self.subTest(duration=duration), self.assertRaises(ValueError):
                roc.extract_features(periodic(), duration)

    def test_longest_segment_uses_first_tie(self):
        self.assertEqual(roc.longest_valid_segment(np.asarray([-1, 1, 2, -1, 3, 4, -1])), (1, 3))

    def test_statistics_population_sd_and_reciprocal_rate(self):
        self.assertEqual(roc.statistics(np.asarray([1, 3]))["stdev"], 1)
        periods = np.asarray([0.2, 0.4])
        self.assertAlmostEqual(roc.statistics(1 / periods)["mean"], 3.75)
        self.assertNotAlmostEqual(roc.statistics(1 / periods)["mean"], 1 / np.mean(periods))

    def test_trimming_removes_first_and_last_peak(self):
        result = roc.extract_features(periodic(), 10)
        self.assertEqual(result["trimmed_opening_peak_frame_indices"], result["opening_peak_frame_indices"][1:-1])
        self.assertEqual(result["features"]["num_peaks_trimmed"], result["features"]["num_peaks_denoised"] - 2)

    def test_framing_rejects_clock_gaps_or_missing_duration(self):
        samples = [{"t": i / 30, "degrees": value} for i, value in enumerate(periodic())]
        self.assertEqual(roc.frame_input(samples, 10), periodic())
        for bad in (samples[5:], samples[:-5], samples[:150] + samples[151:]):
            with self.subTest(length=len(bad)), self.assertRaises(roc.Unavailable):
                roc.frame_input(bad, 10)
        for duration in (None, 0, float("nan")):
            with self.assertRaises(roc.Unavailable):
                roc.frame_input(samples, duration)

    def test_oracle_refuses_unpinned_source(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "untrusted.py"
            path.write_text("raise RuntimeError('must not execute')")
            with self.assertRaisesRegex(ValueError, "pinned SHA"):
                load_oracle(path)

    def test_run_trial_missing_duration_never_returns_zero_features(self):
        trial = {"fingerTappingAngle": {"samples": [{"t": i / 30, "degrees": value}
                 for i, value in enumerate(periodic())]}}
        result = run_trial(trial)
        self.assertEqual(result["status"], "unavailable")
        self.assertIsNone(result["features"])
        self.assertFalse(result["reference_comparison_eligible"])

    def test_long_gap_warnings_and_original_input_preserved(self):
        signal = periodic(600)
        signal[150:210] = [None] * 60
        trial = {"recordedDurationSeconds": 20, "fingerTappingAngle": {"samples": [
            {"t": i / 30, "degrees": value} for i, value in enumerate(signal)]}}
        original = copy.deepcopy(trial)
        result = run_trial(trial)
        self.assertEqual(result["status"], "computed_for_research")
        self.assertEqual(result["maximum_missing_run_frames"], 60)
        self.assertEqual(result["maximum_missing_run_nominal_seconds"], 2)
        self.assertTrue(result["warnings"])
        self.assertIsNone(result["author_kernel_parity"])
        self.assertFalse(result["reference_comparison_eligible"])
        self.assertEqual(original, trial)

    def test_out_of_range_interpolation_is_not_clamped(self):
        signal = periodic(600)
        signal[107:207] = [None] * 100
        with self.assertRaisesRegex(roc.Unavailable, "interpolation_out_of_range"):
            roc.extract_features(signal, 20)


if __name__ == "__main__":
    unittest.main()
