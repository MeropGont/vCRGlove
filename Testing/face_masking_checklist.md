# New Camera Video Face Masking

Scope: new physical-camera finger-tapping and hand open/close movies only.
Software implementation is not proof of detector accuracy or anonymity.

## Focused Software Checks

22 October: five masking tests and 20 storage/information tests passed across
focused runs. Masking pixel tests use controlled detections; Apple Vision could
not initialize inference on the simulator. Real face detection is not verified
by these results. No new camera UI or physical-device pass is claimed.

- [x] Rectangles expand, clip correctly and reject invalid coordinates.
- [x] Multiple masks cover their intended pixels and persist through brief misses.
- [x] No-face processing retains frames, timestamps, silent playback and orientation.
- [x] Detector errors/cancellation remove drafts and never publish the raw movie.
- [x] New processing metadata survives saving/JSON; older references still decode.
- [x] Existing save/delete/replacement tests and information-content tests still pass.
- [x] Early measurement checkpoint accepts a later video without duplicate
      sessions/trials or changed samples.

## Physical Phone Checks (Pending)

- [ ] Both camera tasks, both hands: finish, automatic save, playback, relaunch/export.
- [ ] Frontal, side-on, partial, moving and multiple faces; enter and leave frame.
- [ ] Masks remain correctly placed with front-camera mirroring and phone rotation.
- [ ] Hand-only scene remains useful; hand overlapping a face can be covered.
- [ ] Short/empty Stop, Retake and back during finishing keep earlier saved takes.
- [ ] Time a full 30-second recording; check finishing delay and device warmth.
- [ ] Interrupt/background/lock/terminate during processing, then relaunch: no raw
      draft reaches playback or export; abandoned workspace is cleaned.
- [ ] Low storage or encoding failure retains measurements and reports no video.
- [ ] Older videos remain unchanged; explain detection limitations before study use.

## Version 2 Follow-Up

- [x] Six focused masking tests passed: tighter bounds, no rectangle trails, duplicate
      detections, separate faces, two-second gap/expiry, half-turn coordinates,
      pixels, timing, orientation, failures and optional version metadata.
- [x] Read-only review of the supplied processed phone movie: oversized stepped
      masks and missed upside-down/cropped ending confirmed.
- [x] Native macOS tracking probe follows a manually seeded partial-face region
      through three visible ending frames. This is not end-to-end iPhone proof.
- [ ] Fresh iPhone recording: lean in/out, tilt head, crop the face at the top
      edge, then move sideways during the final two seconds. Review frame by
      frame for any exposed face and check the hand remains useful to review.
- [ ] Check added processing time from the second orientation and gap tracking.
- [x] Overhead follow-up: six focused masking tests pass, including native-buffer
      pass-through, rendered/rotated frames, timing and failure cleanup. Native
      detector-request/context reuse returns the same boxes on a ten-frame local
      processed-video probe; this does not establish iPhone speed or coverage.
- [ ] Send a new recording and its `[VIDEO] Masking v3` timing line. Compare phone
      saving delay and inspect the opening frames for any missed face parts.

## Version 3 Opening Coverage

- New phone export confirmed opening exposure before detection; user reported
  saving took at least ten seconds on that build.
- Short opening look-ahead/backward tracking implemented, capped at 1.25 seconds
  and 90 small previews, with detection reuse rather than another full pass.
- [x] Seven focused masking tests passed: delayed first detection covers prior frames without changing
      timestamps, plus existing masking/orientation/failure regressions.
- [ ] Fresh phone video: inspect the first second and ending; measure processing
      time with the v3 console line. Simulator tests do not verify real faces.

Do not mark physical checks complete from synthetic or simulator tests.

## Deferred Preparation

- [x] 26 focused storage/masking tests passed: accepting a measurement returns while video
      processing is blocked; jobs are serial and later tasks remain intact.
- [x] Late attachments do not resurrect retaken trials; stale checkpoints retain
      ready videos; failures retain measurements without publishing originals.
- [x] English/German UI passed: summary has no playback action; Data opens ready videos
      with existing share/delete controls.
- [ ] Phone: stop and immediately continue to the next task; verify the prior
      movie becomes ready in Data and recording rhythm/tracking remains stable.
- [ ] Brief background/lock and expiration: no unprocessed draft becomes playable;
      measurements survive. Force-quit during preparation: no resumability claim.

## Version 4 Edge Coverage

- [x] Read-only new-export inspection: eye exposed around 18-22 seconds and near
      the ending. Native macOS detector returned no face in the 18-second frame
      for upright, upside-down and sideways orientations.
- [x] 28 focused masking/storage tests passed: edge guards survive long misses on all four edges;
      fresh compact detections replace larger masks; confirmed interior faces
      clear guards and expire normally. Existing masking/storage tests still pass.
- [ ] Fresh iPhone capture: keep a partial face at the edge for at least five
      seconds, move out/back, and review the whole movie. Check hand usefulness
      and that task progression remains unblocked. No detector guarantee claimed.

## Version 5 Continuity And Appearance

- [x] Read-only review: latest export has stale edge regions at multiple positions
      and uncovered opening facial detail. Existing masks cannot be removed from
      the supplied processed movie to reconstruct an original for validation.
- [x] Focused tests: high-confidence continuation reuses one track without merging
      another face; uncertain guards remain. Expand immediately/shrink smoothly.
- [x] Pixel checks: rounded charcoal masks remain fully opaque over every corner
      of the protective rectangle. Late first edge detection covers the opening
      beyond the previous 1.25-second limit, without timestamp changes.
- [x] 33 focused masking/storage tests passed. Renderer-only simulator probe:
      30 rectangular frames 11.900 s, rounded 13.472 s, including first-use setup.
      This is not iPhone latency or a full-pipeline performance comparison.
- [ ] Fresh phone: repeat fast side-to-side movement, move out/back, keep a partial
      face at the edge, and inspect all opening frames. Compare v5 processing time
      and check that hand movement remains reviewable. Native tracking and speed
      are not verified by injected simulator detections/predictions.

## Version 6 Unified Outlines

- [x] Read-only new-export inspection confirmed adjacent/overlapping retained
      coverage and a narrow gap between regions around 11 seconds.
- [x] Geometry regression: coalescing covers every original rectangle, removes
      duplicate drawing, joins bounded narrow gaps, and retains isolated guards.
- [x] 34 focused tests passed on the final code: rounded-corner opacity, opening
      coverage, rendering probe and deferred storage safety.
- [ ] Fresh phone: compare mask outlines during the same side-to-side movement;
      isolated uncertain coverage may remain. Check hand usefulness and v6 timing.

## Version 7 Hand-Focused Output

41 focused video/storage/personal-comparison tests passed; native phone framing
and privacy checks below remain unverified.

- [x] Crop bounds are padded, outward-rounded and rejected when absent/excessive.
- [x] Encoded dimensions/timestamps are correct; outside guards are omitted while
      faces inside the crop stay masked. Crop metadata round-trips; old references
      still decode. Missing crops retain measurements with no full-frame fallback.
- [ ] Physical phone: both hands/tasks, wrist/fingertips fully visible, no mirroring
      mismatch, no-hand/short Stop, wide motion and face entering the crop. Review
      all frames and time preparation; do not infer privacy safety from unit tests.
