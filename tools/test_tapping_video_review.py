import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image
from tapping_video_review import load_frames, marked_angle, summarize_marks


class VideoReviewTests(unittest.TestCase):
    def setUp(self):
        self.frame = {"file": "frame-0000.png", "width": 100, "height": 200, "pts_seconds": 0.0}
        self.points = {"wrist": [10, 10], "thumb_tip": [10, 90], "index_tip": [90, 10]}

    def test_pixel_geometry_no_second_aspect_correction(self):
        self.assertAlmostEqual(marked_angle(self.frame, self.points), 90)

    def test_reflection_and_translation(self):
        reflected = {k: [99 - x, y + 20] for k, (x, y) in self.points.items()}
        self.assertEqual(marked_angle(self.frame, reflected), 90)

    def test_zero_is_valid(self):
        self.points["index_tip"] = [10, 100]
        self.assertEqual(marked_angle(self.frame, self.points), 0)

    def test_invalid_landmarks_rejected(self):
        for point in ([10, 10], [-1, 10], [float("nan"), 10], [True, 10], [100, 10]):
            with self.subTest(point=point), self.assertRaises(ValueError):
                marked_angle(self.frame, dict(self.points, thumb_tip=point))

    def test_marks_keep_uncertainty_and_do_not_claim_sync(self):
        mark = {"file": self.frame["file"], "observation": "visible", "points": self.points,
                "pixel_uncertainty": 5}
        annotation = {"reviewer": "test", "blinded_to_signal": True, "frames": [mark]}
        result = summarize_marks({"frames": [self.frame]}, annotation)
        self.assertFalse(result["signal_video_synchronization_verified"])
        self.assertEqual(result["frames"][0]["angle_degrees"], 90)
        annotation["blinded_to_signal"] = False
        with self.assertRaises(ValueError):
            summarize_marks({"frames": [self.frame]}, annotation)

    def test_duplicate_unknown_and_uncertain_marks_rejected(self):
        base = {"file": self.frame["file"], "observation": "visible", "points": self.points,
                "pixel_uncertainty": 5}
        for marks in ([base, base], [dict(base, file="unknown.png")], [dict(base, pixel_uncertainty=0)]):
            with self.subTest(marks=marks), self.assertRaises(ValueError):
                summarize_marks({"frames": [self.frame]},
                                {"reviewer": "test", "blinded_to_signal": True, "frames": marks})

    def test_manifest_integrity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            Image.new("RGB", (100, 200)).save(root / self.frame["file"])
            path = root / "frames.json"
            def load(frames):
                path.write_text(json.dumps({"format_version": 1, "frames": frames}))
                return load_frames(path)
            self.assertEqual(len(load([self.frame])["frames"]), 1)
            for frames in ([], [self.frame, self.frame], [dict(self.frame, file="../bad.png")],
                           [dict(self.frame, width=99)], [dict(self.frame, pts_seconds=-1)]):
                with self.subTest(frames=frames), self.assertRaises(ValueError):
                    load(frames)

    def test_visible_events_are_not_a_duration_divided_count(self):
        data = {"frames": [dict(self.frame, file=f"frame-{i:04d}.png", pts_seconds=i * 0.1)
                           for i in range(8)]}
        annotation = {"reviewer": "test", "blinded_to_signal": True, "frames": [],
                      "closing_phase_frame_indices": [1, 3, 5]}
        result = summarize_marks(data, annotation)
        self.assertAlmostEqual(result["visible_closing_phase_rate_hz"], 5)
        for events in ([3, 1], [1, 1], [8], [True]):
            with self.subTest(events=events), self.assertRaises(ValueError):
                summarize_marks(data, dict(annotation, closing_phase_frame_indices=events))
        self.assertIsNone(summarize_marks(data, dict(annotation, closing_phase_frame_indices=[]))
                          ["visible_closing_phase_rate_hz"])


if __name__ == "__main__":
    unittest.main()
