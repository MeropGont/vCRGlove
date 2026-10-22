#!/usr/bin/env python3
"""Export a separate author-derived angle feature subset; never write app records or norms."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import tempfile

import numpy as np
import pandas as pd
import scipy

from review_tapping_angles import ROOT, collect_trials, finite, read_sessions
from roc_tapping_features import AUTHOR_REVISION, AUTHOR_SHA256, FEATURE_COLUMNS, METHOD_VERSION, Unavailable, extract_features, frame_input
from verify_roc_tapping_features import compare, load_oracle, self_check


def run_trial(trial, oracle=None):
    payload = trial["fingerTappingAngle"]
    duration = trial.get("recordedDurationSeconds")
    samples = payload["samples"]
    current = longest = 0
    for item in samples:
        current = current + 1 if item.get("degrees") is None else 0
        longest = max(longest, current)
    evidence = {"input_frame_count": len(samples),
                "missing_input_frames": sum(item.get("degrees") is None for item in samples),
                "maximum_missing_run_frames": longest,
                "maximum_missing_run_nominal_seconds": longest * duration / len(samples)
                    if len(samples) and finite(duration) and duration > 0 else None}
    try:
        values = frame_input(samples, duration)
        result = extract_features(values, duration)
    except Unavailable as error:
        return {"status": "unavailable", "reason": str(error), "features": None, **evidence,
                "reference_comparison_eligible": False}
    parity = compare(oracle, values, duration, result) if oracle is not None else None
    warnings = []
    if evidence["maximum_missing_run_nominal_seconds"] > 0.2:
        warnings.append("Tracking loss exceeds 0.2 s; author interpolation/segment selection differs from app gap handling.")
    if result["interpolated_frame_count"]:
        warnings.append("Missing frames were interpolated by the author routine; inspect gaps independently.")
    return {"status": "computed_for_research", **evidence, **result, "warnings": warnings, "author_kernel_parity": parity,
            "elapsed_seconds": duration, "first_sample_seconds": payload["samples"][0]["t"],
            "last_sample_seconds": payload["samples"][-1]["t"],
            "frame_clock": "elapsed_seconds / processed_angle_frame_count; video frame count not independently verified",
            "reference_comparison_eligible": False}


def write_pdf(path, report):
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, KeepTogether
    from xml.sax.saxutils import escape
    styles = getSampleStyleSheet()
    story = []
    def paragraph(text, style="BodyText"):
        story.append(Paragraph(escape(text), styles[style]))
    paragraph("Tapping: author-derived feature review", "Title")
    paragraph("Offline research only. App records and patient plots are unchanged.")
    paragraph("The selected angle-processing kernel follows the pinned ROC-HCI code. This does not reproduce MediaPipe landmark capture, prove camera accuracy or establish a healthy reference range.")
    check = report["synthetic_author_check"]
    paragraph(f"Pinned-source verification: {check['synthetic_case_count']} synthetic cases, {check['feature_comparisons']} numerical feature comparisons; maximum absolute difference {check['maximum_absolute_error']:.3g}." if check else "Author-source parity was not checked in this run.")
    paragraph("Features", "Heading2")
    rows = [["Trial / hand", "Peaks*", "Rate / s", "Angle / deg", "Speed / deg/s", "Period CV**"]]
    for trial in report["trials"]:
        result = trial["result"]
        if result["features"] is None:
            rows.append([trial["key"] + " / " + trial["side"], "Unavailable", "-", "-", "-", "-"])
        else:
            features = result["features"]
            cv = result["support"]["trimmed"]["period_cv_population"]
            rows.append([trial["key"] + " / " + trial["side"], str(features["num_peaks_trimmed"]),
                         f"{features['frequency_mean_trimmed']:.2f}", f"{features['amplitude_mean_trimmed']:.2f}",
                         f"{features['speed_mean_trimmed']:.2f}", "-" if cv is None else f"{cv:.3f}"])
    table = Table(rows, colWidths=[88, 62, 62, 78, 92, 84], hAlign="LEFT", repeatRows=1)
    table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e9edf0")),
                              ("FONTSIZE", (0, 0), (-1, -1), 8), ("BOTTOMPADDING", (0, 0), (-1, -1), 7)]))
    story.extend([table, Spacer(1, 10)])
    paragraph("* Opening peaks after selecting the longest valid segment and trimming first/last peaks. Not full-session tap counts. ** Derived population-SD period CV; not a released reference-table column.")
    paragraph("Rate averages reciprocal cycle periods. Angle averages opening-peak angles, not excursion. Speed averages absolute adjacent-frame angular differences using the author's nominal frame clock. None replaces the app's existing metrics.")
    paragraph("Per-trial evidence", "Heading2")
    for trial in report["trials"]:
        group_start = len(story)
        result = trial["result"]
        paragraph(f"{trial['key']} - {trial['side']} - {trial['started_at']}", "Heading3")
        if result["features"] is None:
            paragraph("Unavailable: " + result["reason"])
            story[group_start:] = [KeepTogether(story[group_start:])]
            continue
        start, end = result["selected_frame_range"]
        parity = result["author_kernel_parity"]
        paragraph(f"Selected frames [{start}, {end}); missing input frames {result['missing_input_frames']}; interpolated frames {result['interpolated_frame_count']}." +
                  (f" All {parity['verified_feature_count']} selected features matched the author kernel." if parity else " No per-trial author check."))
        for warning in result["warnings"]:
            paragraph(warning)
        story[group_start:] = [KeepTogether(story[group_start:])]
    paragraph("Remaining compatibility checks", "Heading2")
    paragraph("These are longer app recordings, not the original ten-tap protocol. No best-ten-tap selection, healthy percentile, diagnosis or UPDRS prediction is calculated. Vision versus MediaPipe, pose effects, independent video annotations and control-person mapping remain separate checks.")
    paragraph("Source: Islam et al., npj Digital Medicine (2023), https://doi.org/10.1038/s41746-023-00905-9. Code revision: " + AUTHOR_REVISION + ". MIT licence; selected code adapted with attribution.")
    def footer(canvas, document):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.drawString(48, 22, "Private research review - not patient or clinical feedback")
        canvas.drawRightString(547, 22, str(document.page))
        canvas.restoreState()
    SimpleDocTemplate(str(path), pagesize=(595.28, 841.89), leftMargin=48, rightMargin=48,
                      topMargin=40, bottomMargin=42).build(story, onFirstPage=footer, onLaterPages=footer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", type=Path)
    parser.add_argument("--output", required=True, type=Path, help="New private directory outside Git")
    parser.add_argument("--author-source", type=Path, help="Optional pinned original source for numerical parity checks")
    args = parser.parse_args()
    destination = args.output.resolve()
    if destination == ROOT or ROOT in destination.parents or destination.exists() or not destination.parent.is_dir():
        parser.error("choose a new directory outside the repository, with an existing parent")
    try:
        original = args.sessions.read_bytes()
        selected, skipped = collect_trials(read_sessions(args.sessions))
        if not selected:
            raise ValueError("no supported stored tapping angles; legacy angles are not reconstructed")
        oracle = load_oracle(args.author_source) if args.author_source else None
        report = {"format_version": 1, "method_version": METHOD_VERSION,
                  "source_sha256": hashlib.sha256(original).hexdigest(),
                  "author_revision": AUTHOR_REVISION, "author_source_sha256": AUTHOR_SHA256,
                  "runtime": {"numpy": np.__version__, "pandas": pd.__version__, "scipy": scipy.__version__},
                  "implementation_hashes": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in (
                      "tools/roc_tapping_features.py", "tools/extract_roc_tapping_features.py",
                      "tools/verify_roc_tapping_features.py", "tools/review_tapping_angles.py")},
                  "synthetic_author_check": self_check(oracle) if oracle else None,
                  "full_external_pipeline_reproduced": False, "healthy_reference_validated": False,
                  "skipped_legacy_trials": skipped, "trials": []}
        for index, (session, trial) in enumerate(selected, 1):
            report["trials"].append({"key": f"T{index:02d}", "session_id": session["id"], "trial_id": trial["id"],
                "side": trial["side"], "started_at": trial.get("startedAt", ""),
                "angle_measurement_version": trial["fingerTappingAngle"]["measurementVersion"],
                "requested_protocol": trial.get("stopCondition"), "result": run_trial(trial, oracle)})
        with tempfile.TemporaryDirectory(prefix=".vcr-roc-report-", dir=destination.parent) as temporary:
            output = Path(temporary) / "report"
            output.mkdir(mode=0o700)
            (output / "features.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
            features = sorted(FEATURE_COLUMNS)
            with (output / "features.csv").open("w", newline="") as handle:
                fields = ["key", "side", "started_at", "status", "reason", "reference_comparison_eligible"] + features
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                for trial in report["trials"]:
                    result = trial["result"]
                    writer.writerow({"key": trial["key"], "side": trial["side"], "started_at": trial["started_at"],
                        "status": result["status"], "reason": result.get("reason", ""),
                        "reference_comparison_eligible": False, **(result["features"] or {})})
            write_pdf(output / "review.pdf", report)
            if args.sessions.read_bytes() != original or destination.exists():
                raise ValueError("source or destination changed; report not published")
            for path in output.iterdir():
                path.chmod(0o600)
            output.rename(destination)
        count = sum(trial["result"]["features"] is not None for trial in report["trials"])
        print(f"Computed {count}/{len(selected)} research trials. Report: {destination / 'review.pdf'}")
    except (ValueError, KeyError, TypeError, OSError, AssertionError) as error:
        parser.exit(1, f"Extraction failed: {error}\n")


if __name__ == "__main__":
    main()
