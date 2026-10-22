# Tapping Video Validation

Initial independent visual development review: 21 October 2026. No app code,
stored recordings, patient metrics or reference bands were changed. This is a
small developer review, not a completed clinical or cohort validation.

## What Was Checked

The latest supplied right/left finger-tapping movies were matched to their stored
trial filenames and byte counts. Both decoded completely. Upright frames were
sampled at 2 fps for the first 29 seconds, then every frame in the same 16-18 s
interval was inspected for both hands. This interval was selected from the video
overview, before looking at the corresponding angle samples and peak arrays.
Overall previous analysis reports were already known to the reviewer; this was
not a blinded study or an independent second-rater assessment.

Raw clips, frame images, annotations and reports remain outside Git in private
temporary review directories. They include sensitive image content and are not
backups. Movie SHA-256 values, source presentation times and annotation hashes
are retained in those reports. Original source files were not edited.

| Check | Right | Left |
| --- | --- | --- |
| Decoded movie frames | 902 | 902 |
| Movie duration | 30.067 s | 30.067 s |
| Stored angle entries | 898 | 899 |
| Recorded task duration | 30 s | 30 s |
| Visible closing phases, 16-18 s | 8 | 8 apparent phases |
| Author-derived opening peaks, nominal signal interval 16-18 s | 8 | 3 |

Closing phases were visually estimated to roughly one frame on the right and two
on the left. The left hand turns edge-on around 16.8 s, obscuring contact. These
are apparent closing excursions, not eight verified complete clinical taps.
Opening peaks and closing phases are different events. Counts over these nearby
windows are descriptive and must not be reported as event sensitivity or timing
error without verified synchronization and consistent event definitions.

## Findings

1. **Stored and movie clocks are not exactly aligned.** Sample count is not movie
   frame count. Code inspection shows the task clock starts after the movie-start
   callback, but a shared movie presentation-time/task-uptime anchor is not saved.
   Unequal counts alone do not establish dropped frames or data loss. Do not
   subtract framewise angles, fit a favorable offset or claim millisecond accuracy.
2. **View changes require further validation.** The left hand visibly turns
   edge-on, obscuring thumb/index contact. Correction on 21 October: the earlier
   four manual-coordinate illustrations are withdrawn as angular evidence. The
   right-hand markup selected a non-index digit; wrist placement was also
   uncertain. Those illustrative angles must not be used to assess app accuracy
   or healthy ranges. This markup error was in the offline review, not the app's
   labelled Vision joint selection. No angle-error statistic is calculated.
3. **Author-code parity is not capture accuracy.** In the left interval, many
   visible movements do not become author-derived opening peaks as the view turns.
   The development review therefore does not justify patient-facing healthy angle
   or velocity ranges. It does not establish which particular capture/peak rule is
   responsible or that the app's existing distance-based rate has the same failure.
4. **Tracking gaps remain separate from visible movement.** The right overview
   includes no hand at sampled movie times 13.0, 13.5 and 14.0 s, followed by return
   at 14.5 s. This is not an exact entry/exit annotation. Author interpolation is
   still not acceptable evidence that motion was observed during missing tracking.

## Reusable Review Tools

The tools are read-only, local and separate from the app. Compile on a Mac with
the Xcode toolchain and an absolute source path:

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc \
  -module-cache-path /tmp/vcr-video-review-module-cache \
  "$PWD/tools/review_tapping_video.swift" -o /tmp/vcr-review-tapping-video
/tmp/vcr-review-tapping-video /private/path/trial.mov \
  /private/path/new-frame-directory 16 18 30
python3 tools/tapping_video_review.py /private/path/new-frame-directory/frames.json \
  --output /private/path/new-contact-sheet-directory
python3 -m unittest discover -s tools -p 'test_tapping_video_review.py' -v
```

Native decoding may need normal macOS media-service access; a sandbox decoder
failure must not be classified as a corrupt source movie. The extractor refuses
existing outputs and repository-local output directories, applies the movie's
display transform, records actual presentation times and uses owner-only file
permissions. It samples real decoded frames without duplicating across gaps.

An optional `--crop LEFT TOP RIGHT BOTTOM` affects contact sheets only, never the
original video or annotation coordinates. `--annotations marks.json` summarizes
manually recorded image landmarks and closing phases. No stored signals are
accepted as input to the annotation tool. The review JSON explicitly leaves
healthy-reference and synchronization validation false. Empty annotations are
not converted into zero-rate results.

Annotation format:

```json
{
  "reviewer": "Reviewer and date",
  "blinded_to_signal": true,
  "review_notes": "State uncertainty, occlusion and any prior knowledge.",
  "closing_phase_frame_indices": [4, 12, 20],
  "frames": [
    {
      "file": "frame-0000.png",
      "observation": "Visible opening; wrist approximate",
      "pixel_uncertainty": 15,
      "points": {
        "wrist": [230, 450],
        "thumb_tip": [460, 446],
        "index_tip": [350, 711]
      }
    }
  ]
}
```

The example coordinates are image pixels, not normalized Vision coordinates.
Annotation uncertainty is a reviewer estimate, not a confidence interval. Review
reports do not silently align clocks, infer unseen contact or produce a clinical
rating. Closing-phase rate uses intervals between marked phases, not count divided
by the enclosing clip duration. It is not the author's mean-reciprocal estimator.

## Next Approval Gate

The initial video check is complete; general measurement validation is not.
The subsequently approved [movie/signal timing metadata](MOVEMENT_VIDEO_TIMING.md)
is implemented for new iOS 18.2+ recordings, preserving old exports. It still
requires a device check. Then repeat a short,
palm-facing capture with clearly visible contacts and independent annotations
before deciding which angle features support a descriptive healthy comparison.
This recommendation does not authorize changing the task duration, camera
algorithm, gap handling or patient display. External control identity and protocol
matching remain separate outstanding checks.

## Verification Record

- All 38 offline regression tests passed, including eight new review-tool tests
  and the existing reference-table, author-feature and Swift paired-channel tests.
- Native Swift extractor compiled with the Xcode toolchain. Final error handling
  refused existing outputs, invalid arguments/rates and repository-local outputs
  without overwriting files. Native video decoding and contact-sheet generation
  were exercised on the supplied clips.
- The default command-line compiler initially selected an incompatible SDK/cache;
  the explicit Xcode toolchain and temporary module cache resolved compilation.
  Native video decoding required macOS media-service access outside the sandbox.
  Neither failed attempt is counted as successful video validation.
- No iOS app build, app unit/UI suite, new physical recording, second-rater
  annotation or healthy-cohort comparison was performed in this tools-only stage.
