"""Local Vision/MediaPipe angle agreement check; never generates healthy limits."""
import argparse
from bisect import bisect_left
from collections import Counter
import csv
import hashlib
import json
import math
from pathlib import Path
import statistics

METHOD = "vision-mediapipe-paired-angle-v2"
ANGLE_VERSION = "vision-thumb-wrist-index-angle-aspect-v1"
TIMING_METHOD = "avcapture-first-buffer-pts-v1"


def finite(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def angle(points, width, height, integer_pixels=False):
    if not finite(width) or not finite(height) or min(width, height) <= 0:
        return None
    if len(points) != 3 or any(len(p) != 2 or not all(finite(v) and 0 <= v <= 1 for v in p) for p in points):
        return None
    pixels = [[p[0] * width, p[1] * height] for p in points]
    if integer_pixels:
        pixels = [[int(v) for v in p] for p in pixels]
    wrist, thumb, index = pixels
    u = [thumb[i] - wrist[i] for i in (0, 1)]
    v = [index[i] - wrist[i] for i in (0, 1)]
    if min(math.hypot(*u), math.hypot(*v)) <= 1e-9:
        return None
    # atan2 is numerically stable at closure. Pixel rounding is a separate sensitivity check.
    return math.degrees(math.atan2(abs(u[0]*v[1] - u[1]*v[0]), u[0]*v[0] + u[1]*v[1]))


def validate_trial(trial, video):
    if trial.get("taskType") != "3.4" or trial.get("source") != "camera":
        raise ValueError("Only camera finger-tapping trials have a comparable angle channel")
    channel = trial.get("fingerTappingAngle", {})
    if (channel.get("measurementVersion") != ANGLE_VERSION or channel.get("unit") != "degrees"
            or channel.get("timeReference") != "seconds_since_trial_start"):
        raise ValueError("Missing or unknown angle channel contract")
    reference = trial.get("video", {})
    if reference.get("fileName") != video.name or reference.get("byteCount") != video.stat().st_size:
        raise ValueError("Video does not match the saved reference")
    timing = reference.get("timing", {})
    if timing.get("version") != 1 or timing.get("method") != TIMING_METHOD:
        raise ValueError("Missing supported capture timing anchor; never fit an offset from the signals")
    for field in ("firstFrameTrialTimeSeconds", "firstFrameMoviePTSSeconds"):
        if not finite(timing.get(field)):
            raise ValueError("Invalid capture timing anchor")
    previous = -math.inf
    for sample in channel.get("samples", []):
        t, value = sample.get("t"), sample.get("degrees")
        if not finite(t) or t < 0 or t <= previous:
            raise ValueError("Angle timestamps must be finite and strictly increasing")
        if value is not None and (not finite(value) or not 0 <= value <= 180):
            raise ValueError("Invalid angle; absence must be explicit, not a fabricated zero")
        previous = t
    return channel, timing


def pair_frames(samples, frames, timing, tolerance=0.018):
    times = [f["movie_seconds"] for f in frames]
    if not times or any(not finite(t) or t < 0 for t in times) or any(b <= a for a, b in zip(times, times[1:])):
        raise ValueError("Decoded frame times must be finite and strictly increasing")
    if not finite(tolerance) or not 0 < tolerance <= 0.018:
        raise ValueError("Pairing tolerance cannot exceed 18 ms")
    pairs = []
    used = set()
    for sample in samples:
        movie_time = (sample["t"] - timing["firstFrameTrialTimeSeconds"]
                      + timing["firstFrameMoviePTSSeconds"])
        position = bisect_left(times, movie_time)
        candidates = range(max(0, position - 1), min(len(times), position + 1))
        index = min(candidates, key=lambda i: abs(times[i] - movie_time))
        delta = times[index] - movie_time
        row = {"trial_seconds": sample["t"], "mapped_movie_seconds": movie_time,
               "vision_degrees": sample.get("degrees"), "frame_index": None,
               "timestamp_error_seconds": None, "mediapipe_degrees": None,
               "mediapipe_integer_pixel_degrees": None, "difference_degrees": None}
        if abs(delta) > tolerance:
            row["reason"] = "no_nearby_frame"
        elif index in used:
            row["reason"] = "frame_already_paired"
        else:
            used.add(index)
            frame = frames[index]
            row.update(frame_index=frame["frame_index"], timestamp_error_seconds=delta,
                       mediapipe_degrees=frame["degrees"],
                       mediapipe_integer_pixel_degrees=frame["integer_pixel_degrees"])
            if sample.get("degrees") is None:
                row["reason"] = "vision_missing"
            elif frame["degrees"] is None:
                row["reason"] = frame["reason"]
            else:
                row.update(reason="paired", difference_degrees=frame["degrees"] - sample["degrees"])
        pairs.append(row)
    return pairs


def summary(pairs):
    values = [r["difference_degrees"] for r in pairs if r["reason"] == "paired"]
    result = {"angle_entries": len(pairs), "paired_frames": len(values),
              "reasons": dict(Counter(r["reason"] for r in pairs))}
    if not values:
        return result
    mean = statistics.mean(values)
    sd = statistics.pstdev(values)
    ordered = sorted(abs(v) for v in values)
    p95 = ordered[math.ceil(.95 * len(ordered)) - 1]
    result.update(mean_difference_degrees=mean, median_absolute_difference_degrees=statistics.median(ordered),
                  p95_absolute_difference_degrees=p95,
                  descriptive_frame_difference_bounds_degrees=[mean-1.96*sd, mean+1.96*sd],
                  maximum_timestamp_error_seconds=max(abs(r["timestamp_error_seconds"])
                      for r in pairs if r["reason"] == "paired"))
    return result


def feature_agreement(samples, pairs, duration):
    """Hold the feature kernel/clock constant to expose landmark-pipeline differences."""
    from roc_tapping_features import METHOD_VERSION, Unavailable, extract_features, frame_input
    import numpy as np
    import pandas as pd
    import scipy
    result = {"method_version": METHOD_VERSION,
              "clock": "shared trial-frame grid with author nominal duration/frame-count clock",
              "runtime": {"numpy": np.__version__, "pandas": pd.__version__, "scipy": scipy.__version__},
              "healthy_reference_eligible": False}
    try:
        vision = extract_features(frame_input(samples, duration), duration)
        mediapipe = extract_features([p["mediapipe_degrees"] for p in pairs], duration)
    except Unavailable as error:
        return {**result, "available": False, "reason": str(error)}
    result.update(available=True,
        interpolation_counts={"vision": vision["interpolated_frame_count"], "mediapipe": mediapipe["interpolated_frame_count"]},
        selected_frame_ranges={"vision": vision["selected_frame_range"], "mediapipe": mediapipe["selected_frame_range"]},
        trimmed_frame_ranges={"vision": vision["trimmed_frame_range"], "mediapipe": mediapipe["trimmed_frame_range"]},
        same_selected_segment=vision["selected_frame_range"] == mediapipe["selected_frame_range"],
        features={key: {"vision": value, "mediapipe": mediapipe["features"][key],
                        "difference": mediapipe["features"][key]-value} for key, value in vision["features"].items()})
    return result


def fixed_window_agreement(samples, pairs, segment):
    """Compare one native-selected ten-cycle window without selecting a later stretch."""
    if segment is None:
        return {"available": False, "reason": "first_ten_segment_not_saved"}
    if (segment.get("selectionVersion") != "vision-first-ten-consecutive-complete-taps-v1"
            or segment.get("sourceAngleVersion") != ANGLE_VERSION
            or segment.get("detectorVersion") != "vision-angle-timestamp-gap-aware-v1"
            or segment.get("completedTapCount") != 10):
        raise ValueError("Unsupported first-ten segment contract")
    start, end = segment.get("firstSampleIndex"), segment.get("endSampleIndexExclusive")
    if (type(start) is not int or type(end) is not int or not 0 <= start < end <= len(samples)
            or len(pairs) != len(samples)):
        raise ValueError("Invalid first-ten sample indices")
    window, matched = samples[start:end], pairs[start:end]
    times = [s["t"] for s in window]
    peaks = segment.get("openingPeakTimes", [])
    if (len(times) < 3 or any(not finite(t) for t in times)
            or any(b <= a or b-a > .2 for a, b in zip(times, times[1:]))
            or any(s.get("degrees") is None for s in window)
            or segment.get("startTrialTimeSeconds") != times[0]
            or segment.get("endTrialTimeSeconds") != times[-1]
            or len(peaks) != 11 or peaks[0] != times[0] or peaks[-1] != times[-1]
            or any(not finite(t) or t not in times for t in peaks)
            or any(b-a < .15 for a, b in zip(peaks, peaks[1:]))
            or any(p.get("trial_seconds") != s["t"] or p.get("vision_degrees") != s.get("degrees")
                   for s, p in zip(window, matched))):
        raise ValueError("First-ten window does not match original samples and paired clock")
    result = {"available": True, "selection_version": segment["selectionVersion"],
              "source_sample_range": [start, end], "completed_native_cycles": 10,
              "elapsed_seconds": times[-1]-times[0], "frame_count": len(window),
              "agreement": summary(matched), "healthy_reference_eligible": False,
              "selection_pipeline": "native Vision; fixed boundaries also used for MediaPipe"}
    complete = all(p["reason"] == "paired" for p in matched)
    speed = {"available": complete, "interpolation": False}
    if complete:
        def mean_speed(values):
            return sum(abs(b-a) for a, b in zip(values, values[1:])) / result["elapsed_seconds"]
        v = mean_speed([s["degrees"] for s in window])
        m = mean_speed([p["mediapipe_degrees"] for p in matched])
        speed.update(vision_degrees_per_second=v, mediapipe_degrees_per_second=m,
                     relative_difference_percent=100*(m-v)/v if v else None)
    else:
        speed["reason"] = "missing_paired_frames_in_fixed_window"
    result["same_window_actual_time_mean_absolute_speed"] = speed
    edges = [i for i in range(1, len(window))
             if matched[i-1]["reason"] == matched[i]["reason"] == "paired"]
    tracked = sum(times[i]-times[i-1] for i in edges)
    common = {"available": bool(edges), "observed_seconds": tracked,
              "window_time_fraction": tracked/result["elapsed_seconds"],
              "adjacent_interval_count": len(edges), "interpolation": False,
              "scope": "identical observed adjacent intervals only; not entire window"}
    if edges:
        v = sum(abs(window[i]["degrees"]-window[i-1]["degrees"]) for i in edges)/tracked
        m = sum(abs(matched[i]["mediapipe_degrees"]-matched[i-1]["mediapipe_degrees"]) for i in edges)/tracked
        common.update(vision_degrees_per_second=v, mediapipe_degrees_per_second=m,
                      relative_difference_percent=100*(m-v)/v if v else None)
    result["common_observed_interval_mean_absolute_speed"] = common
    # The separate historical kernel uses duration / frame count. Rebase only
    # its time origin and preserve the observed frame period, including one
    # final frame interval; do not pass the full trial's 30-second duration.
    nominal_duration = result["elapsed_seconds"] * len(window) / (len(window)-1)
    rebased = [{"t": s["t"]-times[0], "degrees": s["degrees"]} for s in window]
    result["author_kernel"] = feature_agreement(rebased, matched, nominal_duration)
    result["author_kernel"]["input_clock_note"] = "window mean observed frame period; not full-trial duration"
    return result


def display_orientation(capture, cv2):
    orientation = capture.get(cv2.CAP_PROP_ORIENTATION_META)
    if not finite(orientation) or orientation not in (0, 90, 180, 270):
        raise ValueError("Unsupported video orientation")
    # Apply the movie transform once, before detection, as in displayed playback.
    if not capture.set(cv2.CAP_PROP_ORIENTATION_AUTO, 1) or capture.get(cv2.CAP_PROP_ORIENTATION_AUTO) != 1:
        raise ValueError("Decoder cannot apply the movie display orientation")
    size = (int(capture.get(cv2.CAP_PROP_FRAME_WIDTH)), int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT)))
    if min(size) <= 0:
        raise ValueError("Invalid display dimensions")
    return {"backend": capture.getBackendName(), "orientation_auto": 1,
            "orientation_metadata_degrees": orientation, "display_dimensions": list(size)}


def extract_frames(video):
    import cv2
    import mediapipe as mp
    import numpy as np
    if mp.__version__ != "0.10.21":
        raise ValueError("Use pinned mediapipe 0.10.21; review model changes separately")
    capture = cv2.VideoCapture(str(video))
    if not capture.isOpened():
        raise ValueError("Cannot open video")
    frames = []
    sizes = set()
    declared_frames = int(capture.get(cv2.CAP_PROP_FRAME_COUNT))
    try:
        decoder = display_orientation(capture, cv2)
        expected_size = tuple(decoder["display_dimensions"])
        with mp.solutions.hands.Hands(static_image_mode=False, max_num_hands=2, model_complexity=1,
                                     min_detection_confidence=.5, min_tracking_confidence=.5) as detector:
            while True:
                ok, image = capture.read()
                if not ok:
                    break
                time = capture.get(cv2.CAP_PROP_POS_MSEC) / 1000
                if not finite(time) or time < 0 or (frames and time <= frames[-1]["movie_seconds"]):
                    raise ValueError("Decoder did not provide usable timestamps; no frame-index fallback")
                height, width = image.shape[:2]
                if (width, height) != expected_size:
                    raise ValueError("Decoded image dimensions disagree with display orientation")
                sizes.add((width, height))
                result = detector.process(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
                landmarks = result.multi_hand_landmarks or []
                row = {"frame_index": len(frames), "movie_seconds": time, "degrees": None,
                       "integer_pixel_degrees": None, "reason": "no_hand", "hand_label": None,
                       "hand_label_confidence": None, "hand_count": len(landmarks)}
                row.update({f"{name}_{axis}": None for name in ("wrist", "thumb", "index") for axis in ("x", "y")})
                if len(landmarks) > 1:
                    row["reason"] = "multiple_hands"
                elif len(landmarks) == 1:
                    classification = result.multi_handedness[0].classification[0]
                    row.update(hand_label=classification.label, hand_label_confidence=classification.score)
                    if classification.score <= .9:
                        row["reason"] = "uncertain_hand_label"
                    else:
                        points = [[landmarks[0].landmark[i].x, landmarks[0].landmark[i].y] for i in (0, 4, 8)]
                        row.update({f"{name}_{axis}": points[i][j] for i, name in enumerate(("wrist", "thumb", "index"))
                                    for j, axis in enumerate(("x", "y"))})
                        row["degrees"] = angle(points, width, height)
                        row["integer_pixel_degrees"] = angle(points, width, height, integer_pixels=True)
                        row["reason"] = "detected" if row["degrees"] is not None else "invalid_geometry"
                frames.append(row)
    finally:
        capture.release()
    if not frames or len(frames) != declared_frames or len(sizes) != 1:
        raise ValueError("Decoded frame count/dimensions incomplete or inconsistent")
    model_root = Path(mp.__file__).parent / "modules"
    hashes = {str(p.relative_to(model_root)): hashlib.sha256(p.read_bytes()).hexdigest()
              for folder in ("hand_landmark", "palm_detection") for p in sorted((model_root / folder).glob("*.tflite"))}
    if not hashes:
        raise ValueError("Cannot record detector model provenance")
    return frames, {"mediapipe": mp.__version__, "opencv": cv2.__version__, "numpy": np.__version__,
                    "decoder": decoder, "options": {"static_image_mode": False, "max_num_hands": 2,
                        "model_complexity": 1, "min_detection_confidence": .5,
                        "min_tracking_confidence": .5, "minimum_hand_label_confidence_exclusive": .9},
                    "model_sha256": hashes, "frame_count": len(frames), "dimensions": list(next(iter(sizes))),
                    "first_movie_seconds": frames[0]["movie_seconds"], "last_movie_seconds": frames[-1]["movie_seconds"],
                    "hand_label_counts": dict(Counter(f["hand_label"] for f in frames)),
                    "detection_reasons": dict(Counter(f["reason"] for f in frames))}


def run(sessions_path, video, trial_id, output):
    repo = Path(__file__).resolve().parent.parent
    sessions_path, video, output = (p.resolve() for p in (sessions_path, video, output))
    if output.exists() or output == repo or repo in output.parents or not output.parent.is_dir():
        raise ValueError("Output must be a new directory outside the repository")
    original_sessions = sessions_path.read_bytes()
    video_hash = hashlib.sha256(video.read_bytes()).hexdigest()
    matches = [t for s in json.loads(original_sessions) for t in s["trials"] if t["id"] == trial_id]
    if len(matches) != 1:
        raise ValueError("Select one unique saved trial ID")
    trial = matches[0]
    channel, timing = validate_trial(trial, video)
    frames, provenance = extract_frames(video)
    if abs(provenance["first_movie_seconds"] - timing["firstFrameMoviePTSSeconds"]) > .001:
        raise ValueError("Decoder first PTS disagrees with saved movie timing")
    pairs = pair_frames(channel["samples"], frames, timing)
    if sessions_path.read_bytes() != original_sessions or hashlib.sha256(video.read_bytes()).hexdigest() != video_hash:
        raise ValueError("Source changed during review")
    report = {"method_version": METHOD, "trial_id": trial_id, "task_side_metadata": trial["side"],
              "source_sha256": {"sessions": hashlib.sha256(original_sessions).hexdigest(), "video": video_hash},
              "tool_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "detector": provenance, "pairing_tolerance_seconds": .018, "agreement": summary(pairs),
              "same_kernel_feature_comparison": feature_agreement(channel["samples"], pairs, trial.get("recordedDurationSeconds")),
              "first_ten_comparison": fixed_window_agreement(channel["samples"], pairs, trial.get("fingerTappingReferenceSegment")),
              "hand_selection": "exactly one detected hand with label confidence >0.9; no side reversal or anatomical verification",
              "historical_reference_pipeline_reproduced": False, "healthy_reference_validated": False,
              "limitations": ["Newer MediaPipe than the 2023 study; not historical feature-table reproduction.",
                  "Compressed movie versus live camera frames; detector and encoding effects are not separated.",
                  "Frame-level descriptive bounds, not independent-person limits or clinical acceptance thresholds.",
                  "No offset fitting or interpolation in frame pairing; the separate author feature kernel retains its documented interpolation.",
                  "No participant reference limits or clinical score."]}
    output.mkdir(mode=0o700)
    for name, rows in (("mediapipe_frames.csv", frames), ("paired_angles.csv", pairs)):
        path = output / name
        with path.open("w", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=list(rows[0]) if rows else ["trial_seconds"])
            writer.writeheader()
            writer.writerows(rows)
        path.chmod(0o600)
    path = output / "report.json"
    path.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    path.chmod(0o600)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sessions", type=Path)
    parser.add_argument("video", type=Path)
    parser.add_argument("--trial", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(run(args.sessions, args.video, args.trial, args.output), indent=2, allow_nan=False))
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, f"Paired landmark review failed: {error}\n")
