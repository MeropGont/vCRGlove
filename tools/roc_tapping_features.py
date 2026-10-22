"""Research-only ROC-HCI angle feature subset; no camera inference or patient scoring.

Adapted from feature_extraction.py at ROC-HCI/finger-tapping-severity revision
5889255748fe87838428f1cba25481018740f94e. Copyright (c) 2025 ROC-HCI.
MIT licence and attribution: licenses/ROC-HCI-MIT.txt.
"""
from collections.abc import Sequence
import math

import numpy as np
import pandas as pd
from scipy.signal import find_peaks
from scipy.stats import iqr

METHOD_VERSION = "roc-hci-angle-feature-subset-v1"
AUTHOR_REVISION = "5889255748fe87838428f1cba25481018740f94e"
AUTHOR_SHA256 = "ebe91bfce1ef3da72b4d27168d6d969639c66d5d2dd7310378b1c70df6f2c9a6"
FEATURE_COLUMNS = tuple(
    f"{family}_{statistic}_{stage}" for stage in ("denoised", "trimmed")
    for family in ("period", "frequency", "amplitude", "speed")
    for statistic in ("median", "quartile_range", "mean", "min", "max", "stdev")
) + ("num_peaks_denoised", "num_peaks_trimmed")


class Unavailable(ValueError):
    """A valid input for which the author-derived feature kernel has insufficient evidence."""


def denoise(raw):
    """Retain the author's cubic interpolation, slice boundaries and sequential updates."""
    values = list(raw)
    interpolated = pd.Series([np.nan if v == -1 else v for v in values], dtype=float)
    interpolated = interpolated.interpolate(method="polynomial", order=3)
    interpolated[interpolated < 0] = -1.0
    window = threshold = 3
    for index in range(len(values)):
        if values[index] != -1:
            continue
        if index >= window:
            before = values[index - window:index - 1]
        else:
            before = values[0:index - 1]
            before = [-1.0] * max(0, window - len(before)) + before
        if index < len(values) - window:
            after = values[index + 1:index + window]
        else:
            after = values[index + 1:]
            after += [-1.0] * max(0, window - len(after))
        if sum(v == -1 for v in before + [-1.0] + after) <= threshold:
            values[index] = interpolated.iloc[index]
            if np.isnan(values[index]):
                values[index] = -1.0
    return np.asarray(values, dtype=float)


def custom_peaks(values, distance):
    peaks, _ = find_peaks(values, distance=int(distance))
    count = len(peaks)
    middle = values[peaks[math.floor((count - 1) / 4):math.floor(3 * (count - 1) / 4)]]
    if len(middle) == 0:
        raise Unavailable("too_few_candidate_peaks")
    height = math.floor(float(np.percentile(middle, 80)) / 2)
    return find_peaks(values, distance=int(distance), height=height)[0]


def longest_valid_segment(values):
    best_start, best_end, start = -1, -1, -1
    best_length = 0
    for index, value in enumerate(values):
        if value == -1:
            start = -1
        elif start == -1:
            start = index
        elif index - start + 1 > best_length:
            best_start, best_end, best_length = start, index + 1, index - start + 1
    if best_start < 0:
        raise Unavailable("no_continuous_segment")
    return best_start, best_end


def statistics(values):
    if not len(values):
        raise Unavailable("empty_feature_series")
    return {"median": float(np.median(values)), "quartile_range": float(iqr(values)),
            "mean": float(np.mean(values)), "min": float(np.min(values)),
            "max": float(np.max(values)), "stdev": float(np.std(values, ddof=0))}


def extract_features(angles: Sequence, duration_seconds: float):
    """One value per frame, None for unavailable. Caller must establish uniform timing.

    Mirrors the selected author's angle operations on supported inputs. Defensive
    rejection replaces upstream exceptions, not their feature definitions.
    """
    if isinstance(duration_seconds, bool) or not isinstance(duration_seconds, (int, float)):
        raise ValueError("duration must be a finite positive number")
    if not math.isfinite(duration_seconds) or duration_seconds <= 0:
        raise ValueError("duration must be a finite positive number")
    raw = []
    for value in angles:
        if value is None:
            raw.append(-1.0)
        elif (isinstance(value, bool) or not isinstance(value, (int, float, np.integer, np.floating))
              or not np.isfinite(value) or not 0 <= value <= 180):
            raise ValueError("angle must be None or finite degrees in 0...180; zero is valid")
        else:
            raw.append(float(value))
    if len(raw) < 8 or sum(v != -1 for v in raw) < 4:
        raise Unavailable("too_few_frames")
    frame_seconds = duration_seconds / len(raw)
    if frame_seconds <= 0 or 0.15 / frame_seconds > np.iinfo(np.int32).max:
        raise Unavailable("unsupported_frame_clock")
    separation = int(0.15 / frame_seconds)
    if separation < 1:
        raise Unavailable("frame_rate_below_supported_peak_spacing")
    processed = denoise(raw)
    if not np.all(np.isfinite(processed)) or np.any(processed > 180):
        raise Unavailable("interpolation_out_of_range")
    start, end = longest_valid_segment(processed)
    signal = processed[start:end]
    peaks = custom_peaks(signal, separation)
    # The author computes bottoms even though the resulting list is not used later.
    custom_peaks(180 - signal, separation)
    if not len(peaks):
        raise Unavailable("no_opening_peaks")
    accepted = [int(peaks[0])]
    for previous, following in zip(peaks, peaks[1:]):
        if np.min(signal[previous:following]) < 10.0:
            accepted.append(int(following))
    peaks = np.asarray(accepted, dtype=int)
    if len(peaks) < 4:
        raise Unavailable("too_few_closed_cycles_for_trimming")
    trim_start, trim_end = int(peaks[1]), int(peaks[-2]) + 1
    trimmed = signal[trim_start:trim_end]
    trimmed_peaks = peaks[1:-1] - peaks[1]
    features, support = {}, {}
    for label, values, indices in (("denoised", signal, peaks), ("trimmed", trimmed, trimmed_peaks)):
        periods = np.diff(indices) * frame_seconds
        series = {"period": periods, "frequency": 1 / periods,
                  "amplitude": values[indices], "speed": np.abs(np.diff(values) / frame_seconds)}
        for family, vector in series.items():
            for statistic, value in statistics(vector).items():
                features[f"{family}_{statistic}_{label}"] = value
        features[f"num_peaks_{label}"] = len(indices)
        # This derived CV is an extension, not a column in the released feature table.
        support[label] = {"period_count": len(periods), "speed_difference_count": len(values) - 1,
                          "period_cv_population": float(np.std(periods) / np.mean(periods)) if len(periods) >= 2 else None}
    if set(features) != set(FEATURE_COLUMNS):
        raise AssertionError("feature schema mismatch")
    return {"method_version": METHOD_VERSION, "frame_seconds": frame_seconds,
            "input_frame_count": len(raw), "missing_input_frames": raw.count(-1.0),
            "interpolated_frame_count": int(sum(a == -1 and b != -1 for a, b in zip(raw, processed))),
            "selected_frame_range": [start, end], "trimmed_frame_range": [start + trim_start, start + trim_end],
            "opening_peak_frame_indices": (peaks + start).tolist(),
            "trimmed_opening_peak_frame_indices": (trimmed_peaks + start + trim_start).tolist(),
            "features": features, "support": support}


def frame_input(samples, duration):
    """Reject dropped/irregular frame timing instead of silently compressing gaps."""
    from review_tapping_angles import finite, validate_samples
    validate_samples(samples, angle=True)
    if not finite(duration) or duration <= 0:
        raise Unavailable("elapsed_duration_missing_or_invalid")
    if len(samples) < 8:
        raise Unavailable("too_few_frames")
    step = duration / len(samples)
    tolerance = max(0.002, step * 0.10)
    times = [item["t"] for item in samples]
    if (times[0] > 3 * step or times[-1] < duration - 3 * step or times[-1] > duration
            or any(abs((b - a) - step) > tolerance for a, b in zip(times, times[1:]))):
        raise Unavailable("irregular_or_incomplete_frame_timing")
    return [item.get("degrees") for item in samples]
