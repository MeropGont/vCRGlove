"""Run only hash-pinned author angle routines as an offline verification oracle."""
import ast
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
from statistics import median

import numpy as np
import pandas as pd
from scipy.signal import find_peaks
from scipy.stats import iqr

from roc_tapping_features import AUTHOR_SHA256


def load_oracle(path):
    data = Path(path).read_bytes()
    if hashlib.sha256(data).hexdigest() != AUTHOR_SHA256:
        raise ValueError("author source does not match pinned SHA-256; refusing execution")
    tree = ast.parse(data)
    names = {"denoise", "custom_peaks", "custom_bottoms", "get_stats", "angular_amplitude_entropy", "Signal"}
    nodes = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.ClassDef)) and node.name in names]
    if {node.name for node in nodes} != names:
        raise ValueError("pinned author definitions missing")
    # No original imports, module-level calls, video/ML code, pickle loading or network access.
    namespace = {"np": np, "pd": pd, "find_peaks": find_peaks, "iqr": iqr,
                 "median": median, "fft": np.fft.fft}
    exec(compile(ast.Module(body=nodes, type_ignores=[]), str(path), "exec"), namespace)
    return namespace


def compare(oracle, angles, duration, result):
    raw = np.asarray([-1.0 if value is None else value for value in angles])
    with contextlib.redirect_stdout(io.StringIO()):
        signal = oracle["Signal"](raw, np.zeros((len(raw), 2)), len(raw), duration)
    expected = {}
    for label, values, peaks, periods, speed in (
            ("denoised", signal.denoised_signal, signal.peaks_denoised, signal.periods_denoised, signal.speed_denoised),
            ("trimmed", signal.trimmed_signal, signal.peaks_trimmed, signal.periods_trimmed, signal.speed_trimmed)):
        for family, vector in {"period": periods, "frequency": 1 / np.asarray(periods),
                               "amplitude": values[np.asarray(peaks)], "speed": np.abs(speed)}.items():
            expected.update({f"{family}_{statistic}_{label}": float(value)
                             for statistic, value in oracle["get_stats"](vector).items()})
        expected[f"num_peaks_{label}"] = len(peaks)
    if expected.keys() != result["features"].keys():
        raise AssertionError("feature columns differ from author subset")
    errors = []
    for key, value in expected.items():
        actual = result["features"][key]
        if not np.isclose(value, actual, rtol=1e-10, atol=1e-10):
            raise AssertionError(f"author parity failed for {key}: {actual} versus {value}")
        errors.append(abs(actual - value))
    np.testing.assert_array_equal(np.asarray(signal.peaks_denoised),
                                  np.asarray(result["opening_peak_frame_indices"]) - result["selected_frame_range"][0])
    return {"verified_feature_count": len(expected), "maximum_absolute_error": max(errors, default=0),
            "relative_tolerance": 1e-10, "absolute_tolerance": 1e-10}


def self_check(oracle):
    from roc_tapping_features import extract_features
    checks = []
    for rate in (0.8, 2.0, 3.8):
        time = np.arange(600) / 30
        base = (30 * (1 - np.cos(2 * np.pi * rate * time))).tolist()
        for case in ("continuous", "one_missing", "long_gap", "missing_edges", "changing_amplitude"):
            signal = list(base)
            if case == "one_missing":
                signal[111] = None
            elif case == "long_gap":
                signal[150:210] = [None] * 60
            elif case == "missing_edges":
                signal[:15] = signal[-15:] = [None] * 15
            elif case == "changing_amplitude":
                signal = (np.asarray(base) * (0.75 + 0.2 * np.cos(time / 3))).tolist()
            parity = compare(oracle, signal, 20, extract_features(signal, 20))
            checks.append({"case": case, "rate": rate, **parity})
    return {"synthetic_case_count": len(checks),
            "feature_comparisons": sum(c["verified_feature_count"] for c in checks),
            "maximum_absolute_error": max(c["maximum_absolute_error"] for c in checks)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("author_source", type=Path)
    args = parser.parse_args()
    print(json.dumps(self_check(load_oracle(args.author_source)), indent=2))
