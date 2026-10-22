#!/usr/bin/env python3
"""Offline paired-channel review. No app writes, network calls, reference scores or video inference."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path
import shutil
import statistics
import subprocess
import tempfile
import uuid
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
ANGLE_VERSION = "vision-thumb-wrist-index-angle-aspect-v1"
GAP_SECONDS = 0.2
PAIR_TOLERANCE_SECONDS = 0.000001
EVENT_TOLERANCE_SECONDS = 0.1


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate_samples(samples, angle=False):
    if not isinstance(samples, list):
        raise ValueError("samples must be an array")
    previous = -1.0
    for item in samples:
        if not isinstance(item, dict):
            raise ValueError("sample must be an object")
        t = item.get("t")
        value = item.get("degrees" if angle else "value")
        if not finite(t) or t < 0 or t <= previous:
            raise ValueError("timestamps must be finite, nonnegative and strictly increasing")
        if value is None and angle:
            pass
        elif not finite(value) or (angle and not 0 <= value <= 180):
            raise ValueError("invalid signal value (angle must be null or 0...180 degrees)")
        previous = t


def split_segments(samples, angle=False):
    validate_samples(samples, angle)
    groups, current = [], []
    for item in samples:
        value = item.get("degrees" if angle else "value")
        if value is None or (current and item["t"] - current[-1][0] > GAP_SECONDS):
            if current:
                groups.append(current)
            current = []
        if value is not None:
            current.append((item["t"], value))
    if current:
        groups.append(current)
    return groups


def percentile(values, fraction):
    if not values:
        return None
    ordered = sorted(values)
    at = (len(ordered) - 1) * fraction
    lo, hi = math.floor(at), math.ceil(at)
    return ordered[lo] + (ordered[hi] - ordered[lo]) * (at - lo)


def paired_values(distance, angles):
    # Both channels originate in the same callback; do not interpolate or shift them to improve agreement.
    pairs = []
    i = 0
    for angle in angles:
        while i < len(distance) and distance[i]["t"] < angle["t"] - PAIR_TOLERANCE_SECONDS:
            i += 1
        if (angle.get("degrees") is not None and i < len(distance)
                and abs(distance[i]["t"] - angle["t"]) <= PAIR_TOLERANCE_SECONDS):
            pairs.append((angle["t"], distance[i]["value"], angle["degrees"]))
    return pairs


def correlation(pairs):
    if len(pairs) < 3:
        return None
    x, y = [p[1] for p in pairs], [p[2] for p in pairs]
    mx, my = statistics.mean(x), statistics.mean(y)
    xx = sum((v - mx) ** 2 for v in x)
    yy = sum((v - my) ** 2 for v in y)
    if xx == 0 or yy == 0:
        return None
    return max(-1.0, min(1.0, sum((a - mx) * (b - my) for a, b in zip(x, y)) / math.sqrt(xx * yy)))


def match_events(first, second):
    # Chronological one-to-one matching, fixed tolerance; no alignment search.
    i = j = 0
    errors = []
    while i < len(first) and j < len(second):
        delta = second[j] - first[i]
        if abs(delta) <= EVENT_TOLERANCE_SECONDS + 1e-12:
            errors.append(abs(delta))
            i += 1
            j += 1
        elif delta < 0:
            j += 1
        else:
            i += 1
    return {"matched": len(errors), "distance_unmatched": len(first) - len(errors),
            "angle_unmatched": len(second) - len(errors),
            "median_absolute_seconds": statistics.median(errors) if errors else None}


def angle_features(samples):
    segments = split_segments(samples, angle=True)
    values = [value for segment in segments for _, value in segment]
    speeds = [(b[1] - a[1]) / (b[0] - a[0]) for segment in segments for a, b in zip(segment, segment[1:])]
    return {"valid_frames": len(values), "total_frames": len(samples),
            "tracked_seconds": sum(s[-1][0] - s[0][0] for s in segments),
            "longest_segment_seconds": max((s[-1][0] - s[0][0] for s in segments), default=0),
            "segment_count": len(segments), "angle_p05_degrees": percentile(values, 0.05),
            "angle_p95_degrees": percentile(values, 0.95),
            "raw_absolute_velocity_median_deg_s": percentile([abs(v) for v in speeds], 0.5),
            "raw_absolute_velocity_p95_deg_s": percentile([abs(v) for v in speeds], 0.95)}


def read_sessions(path):
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".jsonl":
        return [json.loads(line) for line in text.splitlines() if line.strip()]
    result = json.loads(text)
    if not isinstance(result, list):
        raise ValueError("expected exported session JSON array or JSONL")
    return result


def collect_trials(sessions):
    selected, skipped, seen_sessions, seen_trials = [], [], set(), set()
    for session in sessions:
        if not isinstance(session, dict):
            raise ValueError("session must be an object")
        if not isinstance(session.get("id"), str):
            raise ValueError("session identity must be a UUID string")
        session_id = str(uuid.UUID(session["id"]))
        if session_id in seen_sessions:
            raise ValueError("missing or duplicate session identity")
        seen_sessions.add(session_id)
        if not isinstance(session.get("trials", []), list):
            raise ValueError("trials must be an array")
        for trial in session.get("trials", []):
            if not isinstance(trial, dict):
                raise ValueError("trial must be an object")
            if not isinstance(trial.get("id"), str):
                raise ValueError("trial identity must be a UUID string")
            trial_id = str(uuid.UUID(trial["id"]))
            if trial_id in seen_trials:
                raise ValueError("missing or duplicate trial identity")
            seen_trials.add(trial_id)
            if trial.get("taskType") != "3.4" or trial.get("source") != "camera":
                continue
            payload = trial.get("fingerTappingAngle")
            if payload is None:
                skipped.append({"trial_id": trial["id"], "reason": "No stored angle channel; not reconstructed."})
                continue
            if (not isinstance(payload, dict) or payload.get("measurementVersion") != ANGLE_VERSION or payload.get("unit") != "degrees"
                    or payload.get("timeReference") != "seconds_since_trial_start"):
                raise ValueError("unsupported angle version, units or time reference")
            if trial.get("side") not in ("left", "right"):
                raise ValueError("unknown hand")
            validate_samples(trial.get("samples"))
            validate_samples(payload.get("samples"), angle=True)
            selected.append((session, trial))
    return selected, skipped


def run_analyzer(selected):
    with tempfile.TemporaryDirectory(prefix="vcr-angle-compiler-") as temporary:
        directory = Path(temporary)
        shutil.copyfile(ROOT / "tools/tapping_angle_bridge.swift", directory / "main.swift")
        binary = directory / "analyze"
        subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(directory / "module-cache"),
                        str(ROOT / "vCRGlove/MovementModels.swift"),
                        str(ROOT / "vCRGlove/MovementAnalyzer.swift"), str(directory / "main.swift"),
                        "-o", str(binary)], check=True, capture_output=True, text=True)
        inputs = []
        for index, (_, trial) in enumerate(selected, 1):
            key = f"T{index:02d}"
            inputs.append({"key": key + ":distance", "samples": trial["samples"]})
            inputs.append({"key": key + ":angle", "samples": [
                {"t": item["t"], "value": item["degrees"]} for item in trial["fingerTappingAngle"]["samples"]
                if item.get("degrees") is not None]})
        completed = subprocess.run([str(binary)], input=json.dumps(inputs, allow_nan=False),
                                   check=True, capture_output=True, text=True)
        results = json.loads(completed.stdout)
        if any(item["maximumSampleGapSeconds"] != GAP_SECONDS for item in results):
            raise ValueError("app continuity configuration changed; update offline plot/velocity rules first")
        return {item["key"]: item for item in results}


def video_status(trial, directory):
    reference = trial.get("video")
    if not reference or directory is None:
        return "Not checked; no independent video accuracy/synchronization claim."
    name = reference.get("fileName")
    if name != str(uuid.UUID(trial["id"])).upper() + ".mov":
        raise ValueError("unexpected video reference")
    path = directory / name
    if path.is_symlink() or not path.is_file():
        return "Referenced video missing (or symbolic link); not verified."
    if path.stat().st_size != reference.get("byteCount"):
        return "Video byte count differs; not verified."
    return "Referenced file/byte count match. Video timing offset and landmark accuracy are not independently validated."


def format_value(value):
    return "unavailable" if value is None else f"{value:.3f}"


def signal_plot(samples, title, angle=False):
    # ReportLab's standard scientific line-plot component; each gap is a separate series.
    from reportlab.graphics.charts.lineplots import LinePlot
    from reportlab.graphics.shapes import Drawing, String
    from reportlab.lib.colors import HexColor
    segments = split_segments(samples, angle)
    drawing = Drawing(490, 150)
    drawing.add(String(42, 137, title, fontName="Helvetica", fontSize=10))
    valid = [group for group in segments if len(group) >= 2]
    if valid:
        plot = LinePlot()
        plot.x, plot.y, plot.width, plot.height = 42, 25, 430, 100
        plot.data = valid
        plot.xValueAxis.valueMin = 0
        plot.xValueAxis.valueMax = max(1, max(p[0] for group in valid for p in group))
        plot.xValueAxis.labelTextFormat = "%.0f"
        plot.yValueAxis.labelTextFormat = "%.1f"
        for index in range(len(valid)):
            plot.lines[index].strokeColor = HexColor("#087f8c" if angle else "#2864a0")
            plot.lines[index].strokeWidth = 0.8
        drawing.add(plot)
    drawing.add(String(242, 5, "Time since recording start (s)", fontSize=8))
    return drawing


def write_pdf(path, report, selected):
    from reportlab.lib import colors
    from reportlab.lib.styles import getSampleStyleSheet
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle
    styles = getSampleStyleSheet()
    story = []

    def paragraph(text, style="BodyText"):
        story.append(Paragraph(escape(text), styles[style]))

    paragraph("Tapping angle: paired-channel review", "Title")
    paragraph("OFFLINE RESEARCH REVIEW - NOT PATIENT FEEDBACK", "Heading2")
    paragraph(f"{len(selected)} camera tapping trials with stored angles; {len(report['skipped'])} older trials without angles skipped.")
    paragraph("These are repeated tests from the supplied export, not independent healthy controls. No normal range, clinical score or external normative band is calculated.")
    paragraph("What is compared", "Heading2")
    paragraph("The same current Swift camera analyzer is run on the stored distance and angle channels. Units differ: palm-normalized distance versus projected degrees. Correlation and event agreement are engineering diagnostics, not clinical validation.")
    paragraph("Missing angle frames stay missing. Plots and raw velocity break at missing frames. The existing analyzer retains its 0.2-second continuity convention, so shorter missing runs may still be bridged in its event metrics. No interpolation or alignment search is performed.")
    paragraph("Published method: compatibility boundary", "Heading2")
    paragraph(f"Islam et al.; pinned code revision {report['reference']['revision']}. Code licence: MIT; no author code was copied or executed. This review is NOT a reproduction of that pipeline.")
    paragraph("Paper: https://doi.org/10.1038/s41746-023-00905-9")
    paragraph("Code: https://github.com/ROC-HCI/finger-tapping-severity (feature_extraction.py)")
    for difference in report["reference"]["differences"]:
        paragraph("- " + difference)
    paragraph("Next gate", "Heading2")
    paragraph("Independent video/cycle annotations, camera-view repeatability and external dataset/protocol permission review are still required. Healthy-reference feedback remains disabled in the app.")
    for item, (_, trial) in zip(report["trials"], selected):
        story.append(PageBreak())
        paragraph(f"{item['key']} - {trial['side'].title()} hand - {trial.get('startedAt', '')}", "Heading1")
        paragraph(item["video_status"])
        story.append(signal_plot(trial["samples"], "Distance (relative palm lengths)"))
        story.append(signal_plot(trial["fingerTappingAngle"]["samples"], "Projected aperture (degrees)", angle=True))
        rows = [["Feature", "Distance replay", "Angle experiment"]]
        for label, field, minimum in [("Cycles detected", "cycleCount", 0), ("Rate (cycles/s)", "frequencyHz", 1),
                                      ("Rhythm CV", "rhythmCV", 2), ("Mean excursion (different units)", "meanAmplitude", 1)]:
            values = []
            for channel in ("distance_current", "angle_experiment"):
                result = item[channel]
                values.append(format_value(result["metrics"][field]) if result["intervalCount"] >= minimum else "unavailable")
            rows.append([label] + values)
        table = Table(rows, colWidths=[230, 115, 115], hAlign="LEFT")
        table.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e9edf0")),
                                   ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                                   ("FONTSIZE", (0, 0), (-1, -1), 9), ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
        story.extend([table, Spacer(1, 8)])
        features = item["angle_features"]
        paragraph(f"Angle frames: {features['valid_frames']}/{features['total_frames']}; tracked {features['tracked_seconds']:.2f} s; longest continuous segment {features['longest_segment_seconds']:.2f} s.")
        paragraph(f"Paired-frame correlation: {format_value(item['paired_correlation'])}; event matches within 100 ms: {item['event_agreement']['matched']} (distance unmatched {item['event_agreement']['distance_unmatched']}, angle unmatched {item['event_agreement']['angle_unmatched']}).")
        paragraph(f"Raw absolute angular velocity median / 95th percentile: {format_value(features['raw_absolute_velocity_median_deg_s'])} / {format_value(features['raw_absolute_velocity_p95_deg_s'])} degrees/s. Unsmoothed and tracking-sensitive; not a validated clinical velocity endpoint.")
    def footer(canvas, document):
        canvas.saveState()
        canvas.setFont("Helvetica", 8)
        canvas.drawString(48, 22, "Private engineering review - not clinical feedback")
        canvas.drawRightString(547, 22, str(document.page))
        canvas.restoreState()

    SimpleDocTemplate(str(path), pagesize=(595.28, 841.89), leftMargin=48, rightMargin=48,
                      topMargin=42, bottomMargin=42).build(story, onFirstPage=footer, onLaterPages=footer)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", type=Path)
    parser.add_argument("--output", required=True, type=Path, help="New PRIVATE directory outside the repository")
    parser.add_argument("--videos-dir", type=Path, help="Optional approved video directory; only names/bytes are checked")
    args = parser.parse_args()
    source = args.sessions.resolve()
    destination = args.output.resolve()
    if destination == ROOT or ROOT in destination.parents or destination.exists():
        parser.error("choose a new output directory outside the repository")
    if not destination.parent.is_dir():
        parser.error("output parent must exist")
    original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    try:
        selected, skipped = collect_trials(read_sessions(source))
        if not selected:
            raise ValueError("no supported stored tapping-angle trials; legacy angles are not inferred")
        results = run_analyzer(selected)
        reference = json.loads((ROOT / "tools/tapping_reference_method.json").read_text())
        hashes = {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest() for name in
                  ("vCRGlove/MovementModels.swift", "vCRGlove/MovementAnalyzer.swift", "tools/tapping_angle_bridge.swift",
                   "tools/review_tapping_angles.py", "tools/tapping_reference_method.json")}
        report = {"format_version": 1, "source_sha256": original_hash, "source_files": hashes,
                  "analysis_configuration": {"maximum_gap_seconds": GAP_SECONDS,
                      "pair_tolerance_seconds": PAIR_TOLERANCE_SECONDS,
                      "event_tolerance_seconds": EVENT_TOLERANCE_SECONDS,
                      "angle_measurement_version": ANGLE_VERSION},
                  "reference": reference, "skipped": skipped, "trials": []}
        for index, (session, trial) in enumerate(selected, 1):
            key = f"T{index:02d}"
            pairs = paired_values(trial["samples"], trial["fingerTappingAngle"]["samples"])
            distance, angle = results[key + ":distance"], results[key + ":angle"]
            report["trials"].append({"key": key, "session_id": session["id"], "trial_id": trial["id"],
                "side": trial["side"], "started_at": trial.get("startedAt"),
                "stored_measurement_version": trial.get("measurementVersion"), "stored_metrics": trial["metrics"],
                "distance_current": distance, "angle_experiment": angle,
                "angle_features": angle_features(trial["fingerTappingAngle"]["samples"]),
                "paired_frames": len(pairs), "paired_correlation": correlation(pairs),
                "event_agreement": match_events(distance["cycleEventTimes"], angle["cycleEventTimes"]),
                "video_status": video_status(trial, args.videos_dir)})
        if hashlib.sha256(source.read_bytes()).hexdigest() != original_hash:
            raise ValueError("source changed during review; no report published")
        with tempfile.TemporaryDirectory(prefix=".vcr-angle-report-", dir=destination.parent) as temporary:
            output = Path(temporary) / "report"
            output.mkdir(mode=0o700)
            (output / "review.json").write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
            with (output / "features.csv").open("w", newline="") as handle:
                fields = ["key", "side", "started_at", "paired_frames", "paired_correlation"]
                fields += list(report["trials"][0]["angle_features"])
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                for item in report["trials"]:
                    writer.writerow({**{k: item[k] for k in fields if k in item}, **item["angle_features"]})
            write_pdf(output / "review.pdf", report, selected)
            if hashlib.sha256(source.read_bytes()).hexdigest() != original_hash or destination.exists():
                raise ValueError("source or output changed during report generation; no report published")
            for path in output.iterdir():
                path.chmod(0o600)
            output.rename(destination)
        print(f"Reviewed {len(selected)} trials. Private report: {destination / 'review.pdf'}")
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        detail = error.stderr[-1500:] if isinstance(error, subprocess.CalledProcessError) and error.stderr else str(error)
        parser.exit(1, f"Review failed: {detail}\n")


if __name__ == "__main__":
    main()
