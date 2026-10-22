# Camera Movie And Signal Timing

Implemented 21 October 2026 for new camera-task recordings. This adds optional
timing metadata, not a new recorder, task duration, movement algorithm, healthy
reference band or clinical score. An initial two-recording phone-data check
passed on 21 October; broader repeatability and lifecycle checks remain pending.

## Capture And Mapping

On iOS 18.2+, Apple's [first-buffer recording callback](https://developer.apple.com/documentation/avfoundation/avcapturefileoutputrecordingdelegate/fileoutput(_:didstartrecordingto:startpts:from:))
supplies the timestamp of the first buffer written to the movie, on the capture
session's synchronization clock. Camera sample buffers use that same capture
clock. The current movie is silent, so there is no earlier audio stream defining
the start anchor.

The recorder continues subtracting its `startUptime` from camera sample PTS to
produce each stored sample's `t`. The new code applies that **same subtraction**
to the movie-start source PTS. It does not estimate an offset from callback
arrival time or move the recording's start/stop boundaries.

During the existing background save operation, the first compressed video sample
is read from the finalized movie to establish its actual movie PTS. This reads
one sample, without pixel decoding or a complete video scan. A failure to inspect
timing does not reject a movie or a measurement that could otherwise be saved.
The synchronous track lookup currently uses an Apple-deprecated API on the
serialized save queue; it is not run on the main thread. Modernizing that lookup
must preserve save/snapshot ordering and is not required to interpret the metadata.

The video reference can now contain:

```json
{
  "fileName": "TRIAL-UUID.mov",
  "byteCount": 123456,
  "timing": {
    "version": 1,
    "method": "avcapture-first-buffer-pts-v1",
    "firstFrameTrialTimeSeconds": -0.12,
    "firstFrameMoviePTSSeconds": 0
  }
}
```

For a stored distance/angle sample at `t` seconds:

```text
movie PTS = t - firstFrameTrialTimeSeconds + firstFrameMoviePTSSeconds
```

The example maps trial time zero to movie time 0.12 s. Negative
`firstFrameTrialTimeSeconds` is normal when the movie starts before the
measurement. A negative mapped movie time is outside the movie, not a frame to
clamp to zero. This mapping relates timestamps, not frame indices: processing can
drop camera frames, and frame counts need not be equal.

`MovementVideoTiming.movieTime(forTrialTime:)` implements this conversion and
returns nil for unsupported methods/versions or nonfinite inputs. Exported
JSON retains the version and method so downstream tools can make the same check.

## Ownership, Compatibility And Export

- The timestamp travels with that capture attempt's temporary video. Back/retake,
  discarded drafts and completed delivery clear it alongside the file reference.
  An old attempt cannot attach its timing through the guarded view completion.
- The accepted video reference carries the timing through medication copies,
  automatic checkpoints, manual saving, relaunch and video deletion. Deleting a
  video removes its reference and timing, but not its movement measurements.
- Sessions JSON and the researcher's raw full-data snapshot retain this metadata.
  Existing metrics, sample and angle CSV schemas are unchanged; use sessions JSON
  to retrieve the per-trial video mapping.
- Existing recordings are not realigned, estimated or rewritten. Older video
  references decode with absent timing. Watch/synthetic recordings gain no timing.
- On iOS 17 through 18.1, the old callback remains usable for recording but has no
  precise source-start PTS. Timing stays absent. The same fallback applies if any
  required timestamp or the finalized movie's first sample cannot be read.
- Absent metadata does not mean zero offset. No prior recordings acquire a
  synchronization claim retrospectively.

## Validation Boundary

The software anchor is implemented and the initial phone-data check below found
agreement with visible closing phases. Further real-device replay must check
stability through early Stop, retake and relaunch. It does not validate landmark
accuracy, anatomical angle, shutter/exposure timing, healthy controls or changes
of hand orientation. The [initial video review](TAPPING_VIDEO_VALIDATION.md) remains
relevant; its older clips cannot demonstrate this newly captured metadata.

Expected checks:

1. Install the new Xcode build and record one finger-tapping and one opening/closing
   take with the palm facing the camera, including an early Stop if convenient.
2. Export sessions JSON and the matching movies. Confirm each new camera trial on
   iOS 18.2+ has `video.timing` with the expected version/method.
3. Compare mapped sample times with actual movie presentation times, not inferred
   frame indices. Annotate visible events independently before inspecting peaks.
4. Retake and relaunch. Confirm metadata follows the new accepted movie, while
   original historical trials remain without fabricated timing.
5. Keep healthy references disabled until camera/protocol validation is sufficient.

## Software Verification

The complete simulator unit suite passed: 234 test methods, 302 executions with
parameterized cases, zero failures/skips. Four new methods cover signed/invalid
anchors, legacy/JSON decoding, copies/exports, a playable generated movie saved
with timing, a full-data snapshot and unreadable-timing fallback. Existing tests
also verify recording timers, camera/Watch isolation, saving, retries and deletion.
All 38 offline research-tool regressions passed after the model addition.

Three focused simulator UI tests passed with zero failures/skips: bilingual
private-video save/playback/relaunch, retake retaining the previous saved video,
and failed-video-save recovery with explicit measurement-only saving. Their
result bundle is `/tmp/vcr-video-timing-ui-20261021.xcresult`. They exercise the
existing generated-video UI path, not the real-camera first-buffer callback.

Unit result: `/tmp/vcr-video-timing-unit-20261021.xcresult`, Xcode 26.5, iPhone 17e
simulator / iOS 26.5. The real-camera timestamp callback is not exercised by these
simulated fixtures. Neither a physical-device alignment test nor a healthy
comparison was performed during implementation.

## Initial Phone-Data Review (21 October 2026)

The user supplied new right-hand tapping and opening/closing movies with the
matching sessions JSON and three CSV exports. Review was read-only for app code,
source recordings and exported measurements. Private frames and review outputs
stay outside Git, with source/annotation hashes. No fresh app tests were required
for this data-only follow-up.

- All 57 trial rows, 30,942 signal samples and 6,287 angle entries in the CSVs
  agreed with the JSON for identities, context, task/hand/source, dates/start
  uptime, medication fields, sample times/values, validity/units/version and
  movement metrics. Derived medication intervals agree within the sub-second
  precision omitted by ISO-8601 JSON dates; this is not a video timing tolerance.
- Both new movies decoded completely: 902 frames and 30.067 s each, with filenames
  and byte counts matching the trial references. The mapping's first movie PTS
  agreed with the decoded first PTS (zero), without fitting an offset.
- Movie-start offsets were -0.062848 s for tapping and -0.061406 s for
  opening/closing. All retained sample times mapped inside their movies.
- Tapping retained 898 distance/angle entries, with no missing angles or distance
  gaps above 0.2 s. Opening/closing retained 881 distance entries and one 0.3 s
  gap around movie 13.13-13.43 s, consistent with another hand entering the view.
  This does not establish camera handedness accuracy or a storage failure.
- Full-rate video frames in 5-7 s and 25-27 s windows were inspected before the
  per-frame signal arrays. Sixteen tapping closing phases and ten interior
  closed-fist phases were marked as approximate intervals, excluding ambiguous
  fist boundary closures. All 26 intervals matched a raw-distance trough within
  the visual interval or about one additional frame. No temporal offset was
  optimized. These are development observations, not complete clinical repetitions
  or a full-take cycle-count validation.
- A fixed review-only trough detector used four-sample minimum spacing and
  prominence 10% of the signal's 95th-minus-5th percentile range. It is not the app
  analyzer and found extra small troughs in the fist signal; matched events alone
  are not detector specificity evidence. The largest excursion outside a marked
  visual interval was 34.1 ms, including movie timestamp quantization.
- Across all 240 inspected video frames, nearest mapped sample PTS differed by
  less than 0.8 ms. This supports timestamp consistency in these windows. It is
  **not** a sub-millisecond claim about physical movement, shutter timing or
  landmark accuracy. Visual annotations were approximate at 30 fps.

This is a successful initial check of the implemented timing anchor. Both clips
were full-duration right-hand takes from one tester; early Stop/retake/relaunch,
left-hand and cross-device repeatability remain unchecked physically. Healthy
reference bands remain unimplemented. The candidate angle-feature calculator can
process the new tapping take; its nominal frame clock and the 30 s versus ten-tap
protocol distinction still need explicit matching before comparing controls.

The earlier manual landmark illustration correction is recorded in the
[initial video review](TAPPING_VIDEO_VALIDATION.md); it is not app algorithm evidence.

The 50 selected author-derived feature values also matched the hash-pinned source
exactly for this new tapping trial. Its trimmed rate/angle/speed were about
4.009/s, 38.16 degrees and 277.18 degrees/s under that method's definitions.
These are separate offline research values, not patient reference limits or
replacements for the app's distance metrics. Raw images show the tester's face;
this check did not implement masking, anonymization or video-storage consent.
