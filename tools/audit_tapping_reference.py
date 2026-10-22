#!/usr/bin/env python3
"""Aggregate audit of the pinned public feature table; never calculates patient norms."""
import argparse
from collections import Counter, defaultdict
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

REVISION = "5889255748fe87838428f1cba25481018740f94e"
EXPECTED_SHA256 = "93d590875d535d9e134d093903d2b15138f06d105e34e5c954be114b188e20b6"
FLAGS = ("CheckDifficult1", "CheckDifficult3", "CheckDifficult4")
FEATURES = ("frequency_mean_trimmed", "amplitude_mean_trimmed", "speed_mean_trimmed",
            "period_mean_trimmed", "period_stdev_trimmed")


def rate_candidate(rows):
    """Descriptive sensitivity analysis, never a deployable patient reference."""
    audit = summarize(rows)
    controls = [r for r in rows if r["diagnosed"] == "no"]

    def distribution(values):
        ordered = sorted(values)
        if not ordered:
            return {"available": False, "observation_count": 0}
        def quantile(p):
            index = (len(ordered)-1)*p
            low = math.floor(index)
            high = math.ceil(index)
            return ordered[low] + (ordered[high]-ordered[low])*(index-low)
        return {"available": True, "observation_count": len(ordered),
                "p05": quantile(.05), "p25": quantile(.25), "median": quantile(.5),
                "p75": quantile(.75), "p95": quantile(.95)}

    subsets = {"all_no_pd_rows": controls,
               "no_expert_difficulty_flags": [r for r in controls if all(r[f] == "FALSE" for f in FLAGS)]}
    hands = {}
    for hand in ("Left", "Right"):
        result = {}
        for name, subset in subsets.items():
            selected = [r for r in subset if r["hand"] == hand]
            grouped = defaultdict(list)
            for row in selected:
                value = float(row["frequency_mean_trimmed"])
                if value <= 0:
                    raise ValueError("nonpositive reference tapping rate")
                grouped[author_group(row["filename"])].append(value)
            result[name] = {
                "recording_weighted": distribution([float(r["frequency_mean_trimmed"]) for r in selected]),
                "filename_group_medians_sensitivity_only": distribution([statistics.median(v) for v in grouped.values()]),
                "filename_group_sizes": dict(Counter(len(v) for v in grouped.values())),
                "independent_participant_count": None}
        hands[hand] = result
    return {"method_version": "roc-tapping-rate-candidate-v1", "feature": "frequency_mean_trimmed",
            "unit": "taps_per_second", "percentile_method": "linear interpolation at (n-1)*p",
            "cohort": audit["control_label"], "hands": hands,
            "patient_display_allowed": False, "healthy_reference_validated": False,
            "limitations": ["Descriptive recording distributions, not screened healthy norms or confidence intervals.",
                            "Filename grouping is unverified; grouping medians are sensitivity analysis, not participant weighting.",
                            "Difficulty-flag exclusion is a sensitivity analysis, not a proven healthy-cohort definition.",
                            "Pooled ages and unknown dominance; not age-adjusted and not daily-median references.",
                            "Camera detector and 30-second versus ten-requested-tap protocol differences remain."]}


def author_group(filename):
    # Re-express the filename grouping rule documented by the pinned author training script.
    parts = filename.split("-")
    if filename.startswith("NIH"):
        return parts[0]
    if len(parts) < 3 or not all(parts):
        raise ValueError("unrecognized filename grouping pattern")
    return parts[-3]


def summarize(rows):
    required = {"filename", "hand", "diagnosed", "age", "gender", "Rating", *FLAGS, *FEATURES}
    if not rows or not required.issubset(rows[0]):
        raise ValueError("missing expected feature/metadata columns")
    for row in rows:
        if row["diagnosed"] not in ("yes", "no") or row["hand"] not in ("Left", "Right"):
            raise ValueError("unknown diagnosis or hand; do not silently select controls")
    controls = [row for row in rows if row["diagnosed"] == "no"]
    for row in controls:
        if not row["filename"] or not row["gender"] or not row["age"].isdigit():
            raise ValueError("missing or invalid demographic metadata")
        if any(row[field] not in ("TRUE", "FALSE") for field in FLAGS):
            raise ValueError("unknown expert difficulty flag")
        for field in FEATURES:
            if not math.isfinite(float(row[field])):
                raise ValueError("missing/nonfinite feature")
    groups = defaultdict(list)
    for row in controls:
        groups[author_group(row["filename"])].append(row)
    return {
        "row_count": len(rows), "control_label": "self-reported no PD diagnosis, not screened healthy",
        "control_rows": len(controls), "control_hands": dict(Counter(r["hand"] for r in controls)),
        "control_unique_file_hand_keys": len({(r["filename"], r["hand"]) for r in controls}),
        "control_author_rule_groups": len(groups),
        "control_group_size_distribution": dict(Counter(len(group) for group in groups.values())),
        "control_groups_with_conflicting_age_or_gender": sum(
            len({(r["age"], r["gender"]) for r in group}) > 1 for group in groups.values()),
        "control_consensus_ratings": dict(Counter(r["Rating"] for r in controls)),
        "control_rows_any_expert_difficulty": sum(any(r[f] == "TRUE" for f in FLAGS) for r in controls),
        "control_row_age_bands_by_hand": {hand: {label: sum(
            r["hand"] == hand and low <= int(r["age"]) <= high for r in controls)
            for label, low, high in (("under_50", 0, 49), ("50_59", 50, 59),
                                     ("60_69", 60, 69), ("70_plus", 70, 200))}
            for hand in ("Left", "Right")},
        "warning": "Filename-derived groups are not verified participants. No reference intervals calculated."
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=Path)
    parser.add_argument("--rate-candidate", action="store_true", help="Research-only descriptive rate sensitivity analysis")
    args = parser.parse_args()
    try:
        data = args.csv.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if digest != EXPECTED_SHA256:
            raise ValueError("input is not the pinned audited CSV; review any new version separately")
        rows = list(csv.DictReader(data.decode("utf-8-sig").splitlines()))
        result = rate_candidate(rows) if args.rate_candidate else summarize(rows)
        print(json.dumps({"revision": REVISION, "source_sha256": digest, **result}, indent=2, allow_nan=False))
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Audit failed: {error}\n")


if __name__ == "__main__":
    main()
