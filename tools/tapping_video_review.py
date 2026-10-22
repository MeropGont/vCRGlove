#!/usr/bin/env python3
"""Make blinded video contact sheets and summarize manually marked image landmarks.

No signal/model input: visual observations cannot be adjusted to fit stored peaks.
All coordinates refer to the original, upright extracted frame, not the thumbnail.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil

from PIL import Image, ImageDraw, ImageFont


def number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def load_frames(path):
    data = json.loads(path.read_text())
    frames = data["frames"]
    if data.get("format_version") != 1 or not frames:
        raise ValueError("Unsupported or empty frame manifest")
    previous = -math.inf
    for frame in frames:
        name = frame["file"]
        if Path(name).name != name or not name.endswith(".png"):
            raise ValueError("Frame must be a local PNG basename")
        file = path.parent / name
        t = frame["pts_seconds"]
        if file.is_symlink() or not file.is_file() or not number(t) or t < 0 or t <= previous:
            raise ValueError("Invalid frame file or nonmonotonic presentation time")
        with Image.open(file) as im:
            if im.size != (frame["width"], frame["height"]):
                raise ValueError("Frame dimensions differ from manifest")
        previous = t
    return data


def marked_angle(frame, points):
    coordinates = []
    for key in ("wrist", "thumb_tip", "index_tip"):
        point = points[key]
        if (not isinstance(point, list) or len(point) != 2 or
                not all(number(x) for x in point) or
                not 0 <= point[0] < frame["width"] or not 0 <= point[1] < frame["height"]):
            raise ValueError("Landmark must be an in-frame pixel coordinate")
        coordinates.append(point)
    wrist, thumb, index = coordinates
    u = [thumb[i] - wrist[i] for i in range(2)]
    v = [index[i] - wrist[i] for i in range(2)]
    if math.hypot(*u) == 0 or math.hypot(*v) == 0:
        raise ValueError("Coincident wrist and fingertip")
    return math.degrees(math.atan2(abs(u[0] * v[1] - u[1] * v[0]), u[0] * v[0] + u[1] * v[1]))


def summarize_marks(data, annotations):
    if not annotations.get("reviewer") or annotations.get("blinded_to_signal") is not True:
        raise ValueError("Record reviewer and independent, signal-blinded review")
    lookup = {f["file"]: f for f in data["frames"]}
    seen = set()
    rows = []
    for mark in annotations["frames"]:
        name = mark["file"]
        if name in seen or name not in lookup:
            raise ValueError("Unknown or duplicate annotated frame")
        seen.add(name)
        frame = lookup[name]
        row = {"file": name, "pts_seconds": frame["pts_seconds"], "observation": mark["observation"]}
        if "points" in mark:
            if not number(mark.get("pixel_uncertainty")) or mark["pixel_uncertainty"] <= 0:
                raise ValueError("Manual landmarks need positive pixel uncertainty")
            row.update(angle_degrees=marked_angle(frame, mark["points"]),
                       pixel_uncertainty=mark["pixel_uncertainty"], points=mark["points"])
        rows.append(row)
    events = annotations.get("closing_phase_frame_indices", [])
    if (any(not isinstance(i, int) or isinstance(i, bool) or not 0 <= i < len(data["frames"])
            for i in events) or events != sorted(set(events))):
        raise ValueError("Closing-phase frame indices must be unique, ordered and in range")
    times = [data["frames"][i]["pts_seconds"] for i in events]
    result = {"reviewer": annotations["reviewer"], "blinded_to_signal": True,
            "signal_video_synchronization_verified": False,
            "independent_clinical_validation": False, "frames": rows,
            "closing_phase_frame_indices": events, "closing_phase_video_times": times,
            "review_notes": annotations.get("review_notes", "")}
    if len(times) >= 2:
        result["visible_closing_phase_rate_hz"] = (len(times) - 1) / (times[-1] - times[0])
    else:
        result["visible_closing_phase_rate_hz"] = None
    return result


def make_sheets(data, source, directory, crop=None):
    font = ImageFont.load_default(size=18)
    # Presentation times are shown without landmarks, signals or detected peaks.
    for first in range(0, len(data["frames"]), 24):
        page = Image.new("RGB", (1440, 4 * 340), "white")
        draw = ImageDraw.Draw(page)
        for slot, frame in enumerate(data["frames"][first:first + 24]):
            x, y = slot % 6 * 240, slot // 6 * 340
            with Image.open(source / frame["file"]) as image:
                image = image.convert("RGB")
                if crop:
                    image = image.crop(crop)
                image.thumbnail((240, 300))
                page.paste(image, (x + (240 - image.width) // 2, y + 32))
            draw.text((x + 5, y + 5), f"#{first + slot:03d}  {frame['pts_seconds']:.3f}s", fill="black", font=font)
        path = directory / f"sheet-{first // 24 + 1:02d}.jpg"
        page.save(path, quality=95)
        path.chmod(0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--annotations", type=Path)
    parser.add_argument("--crop", type=int, nargs=4, metavar=("LEFT", "TOP", "RIGHT", "BOTTOM"),
                        help="Contact sheets only; annotations always use original-frame coordinates")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = args.manifest.resolve()
    out = args.output.resolve()
    repo = Path(__file__).resolve().parent.parent
    if out == repo or repo in out.parents or out.exists() or not out.parent.is_dir():
        parser.error("Output must be a new directory outside the repository with an existing parent")
    data = load_frames(manifest)
    if args.crop:
        left, top, right, bottom = args.crop
        if not all(0 <= left < right <= f["width"] and 0 <= top < bottom <= f["height"]
                   for f in data["frames"]):
            parser.error("Crop must fit every original frame")
    annotation_data = json.loads(args.annotations.read_text()) if args.annotations else None
    summary = summarize_marks(data, annotation_data) if annotation_data is not None else None
    out.mkdir(mode=0o700)
    try:
        make_sheets(data, manifest.parent, out, args.crop)
        result = {"manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
                  "video_sha256": data.get("video_sha256"), "manual_review": summary,
                  "contact_sheet_crop": args.crop,
                  "healthy_reference_validated": False}
        if args.annotations:
            result["annotations_sha256"] = hashlib.sha256(args.annotations.read_bytes()).hexdigest()
        report = out / "review.json"
        report.write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
        report.chmod(0o600)
    except Exception:
        shutil.rmtree(out)
        raise
    print(f"Review: {out}")


if __name__ == "__main__":
    main()
