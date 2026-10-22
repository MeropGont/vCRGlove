# Finger-Tapping Angle: Compatibility Audit

Reviewed 16 October 2026 on `codex/finger-tapping-angle`.

Status: stages 1-3 software work complete; stage 4 offline comparison workflow
and initial six-trial review complete on 19 October. Stage 5 candidate assessment
is complete; dataset adoption remains unresolved. An initial two-clip video
review was completed on 21 October; broader accuracy/synchronization validation
remains pending. See [video findings](TAPPING_VIDEO_VALIDATION.md).
An additive [in-app angle summary](NATIVE_TAPPING_ANGLES.md) was implemented on
21 October after approval. No clinical score or reference band is implemented.
Further reference-feedback stages need approval. This standalone note
is linked from the handbook; data-format and physical-checklist chapters describe
the new channel and are used to regenerate the PDF.

## Staged Work

1. Complete: inspect capture, models, recorder, export boundaries and external
   methods; specify the measurement and validation gates.
2. Complete: pure angle helper and focused geometry tests, verified in the full
   unit-test run. Stage 3 connects it to capture, not patient results.
3. Software checks complete: optional, separately versioned angle capture/storage,
   compatibility, export and lifecycle tests. Physical camera checks pending.
4. Implemented: offline comparison of co-captured distance/angle channels from
   approved exports, with associated video file/byte checks. Independent video
   landmark/cycle accuracy and synchronization validation remain pending.
5. Assessment complete, adoption unresolved: see [dataset/protocol assessment](HEALTHY_REFERENCE_ASSESSMENT.md).
   Public controls are not ready-made app norms; mapping, protocol bridging,
   independent validation and intended-use clarification remain pending.
6. Pending approval and validation: design patient reference feedback. Do not
   display external reference limits or inferred UPDRS scores before this gate.

## Follow-On: Author-Derived Offline Feature Subset (19 October)

The separately approved [ROC-HCI feature subset](ROC_TAPPING_FEATURES.md) now
implements the selected angle-processing definitions without replacing any app
analysis. Fifteen synthetic cases yielded exact agreement on 750 numerical
features; five supported real trials matched all 50 selected features each. One
stress-test trial was rejected because cubic interpolation exceeded 180 degrees.
The author algorithm can bridge long missing runs; reports expose this behavior,
and the app's gap-aware analysis remains unchanged. Thirty offline tests passed.
No healthy band or clinical score is implemented; independent camera/protocol
validation and control-person mapping remain pending.

## Stage 4: Offline Paired-Channel Review (19 October)

The [reproducible review workflow](TAPPING_ANGLE_REVIEW.md) compiles the actual
Swift models/analyzer into a tools-only CLI. It compares stored distance and
projected aperture without changing app capture, saved metrics or patient results.
The external author implementation is pinned to revision
`5889255748fe87838428f1cba25481018740f94e`; preprocessing, timing and amplitude
definitions are explicitly different. This is not an external-pipeline replication.

Six supplied tapping trials (three per hand) were reviewed. Paired-frame
correlations were 0.9745-0.9904. Distance/angle cycle counts were respectively
109/108, 104/103, 121/120, 131/131, 83/80 and 77/77. The last two had unmatched
events in both channels and deserve independent video annotation. Matching video
names/byte counts were found for all six. Older 23 tapping trials without an angle
channel were skipped, not reconstructed. Private reports, identifiers and media
remain outside Git.

Ten focused regression tests passed, including compilation/replay of the actual
Swift analyzer on synthetic periodic, gapped and empty signals. Tests also cover
zero versus missing angles, timestamp validity, contracts/identity, no-interpolation
pairing, one-to-one event matching and safe video-file checks. Source export SHA-256
is checked before publishing a report. There was no new app code or app UI change,
so the app unit/UI suites were not rerun for this tools-only stage.

These channels share landmarks and are not independent ground truth. No healthy
cohort, normative range or clinical velocity endpoint has been validated. Stage 5
dataset/protocol assessment is documented separately; patient bands stay deferred.

## Pre-Stage-3 Baseline: Verified By Code Inspection

| Boundary | Existing behaviour | Implication |
| --- | --- | --- |
| `VisionHandPoseCapture.swift` | One Vision hand observation; wrist, middle MCP and thumb/index tips are available for tapping. Joint confidence minimum is 0.2. | No second live hand detector is necessary to calculate an angle. |
| `CameraMovementSignal` in `MovementModels.swift` | Thumb-index tip distance divided by live wrist-middle-MCP distance; x coordinates are corrected using image width/height. | Preserve this signal and its version unchanged. |
| Camera callback | `onSample(value,time)` currently carries one scalar and a frame presentation timestamp. It is invoked from the video delegate queue despite its main-queue documentation comment. | Do not add a main-thread assumption. The recorder already serializes ingestion. |
| Recording | `TrialRecorder` normalizes timestamps to recording start; both standalone and guided task flows wire its callback separately. | Both flows need coverage when adding another channel. |
| Analysis | Moving-average smoothing and hysteresis cycle detection; amplitude is segment maximum minus minimum. | Running this analyzer on angles would not reproduce external features automatically. |
| Persistence | `Trial.samples` contains one scalar stream; video and medication helpers reconstruct the trial. | A new optional payload must survive both copy helpers, saves and exports. |
| Timing | Both camera task flows select 30 seconds, with early Stop and tracking gaps rather than clock pauses. | Angle capture must not alter countdown, Stop, duration, saving or Retake. |
| Existing tests | Camera geometry invariance, legacy decoding, version preservation, recorder stopping and exports have test coverage in the repository. | These are regression targets, not proof of a newly added channel. Tests were inspected, not rerun in stage 1. |

The current capture selects the first detected hand, not a verified anatomical
side. A trial's side is supplied by the task flow. Treat that distinction as a
validation issue; do not silently change hand selection during the angle-helper
stage. Reflection-invariant geometry does not verify that the correct hand was
performed.

## External Method: What Matches And What Does Not

The [Islam et al. paper](https://doi.org/10.1038/s41746-023-00905-9)
defines the projected thumb-tip/wrist/index-tip angle, with the wrist as vertex.
It uses angular peaks for amplitude, unlike our peak-to-peak distance amplitude.
The cohort includes 78 controls; this does not establish app-compatible norms.

The [author implementation](https://github.com/ROC-HCI/finger-tapping-severity/blob/main/feature_extraction.py)
uses MediaPipe, integer pixel coordinates, a normalized dot product and inverse
cosine. It includes hand-label filtering, missing-frame processing, segment
trimming, custom peaks and a nominal per-frame duration. Our Vision confidence
values and timestamp-based sampling are not interchangeable with those choices.
The [repository](https://github.com/ROC-HCI/finger-tapping-severity) provides
extracted features and code, not a raw-video reference cohort. Pin its revision
and check relevant licenses before adopting code or data. Exact task-duration,
repetition and demonstration compatibility remain to be verified before using
reference values.

## Angle Contract: Implemented In Stage 2

`FingerTappingAngle.degrees` lives beside `CameraMovementSignal` in
`MovementModels.swift`. Stage 3 adds a capture caller, not a results caller. Its geometry tests live
in `FingerTappingAngleTests` in `vCRGloveTests.swift`.

For Vision-normalized points W (wrist), T (thumb tip), I (index tip), first
restore image proportions using the actual processed buffer's width/height:

```text
r = imageWidth / imageHeight
u = ((T.x - W.x) * r, T.y - W.y)
v = ((I.x - W.x) * r, I.y - W.y)
angleDegrees = atan2(abs(u.x*v.y - u.y*v.x), u.x*v.x + u.y*v.y) * 180 / pi
```

This returns an unsigned angle from 0 through 180 degrees without needing palm
length. `atan2` avoids division by vector lengths and inverse-cosine rounding
outside its domain. Reject non-finite coordinates, invalid image proportions
and zero-length wrist-to-tip vectors. A genuinely closed tap can be zero and
must not be treated as missing. The helper has no near-zero movement cutoff:
each nonzero vector is independently rescaled by its largest absolute component
before cross/dot products, avoiding squared-length overflow and underflow.
Non-finite intermediate arithmetic and vectors that collapse to zero at machine
precision return missing. Landmark confidence and camera adequacy remain capture
concerns for stage 3, not geometry-derived symptom thresholds.

Use floating-point geometry rather than copying integer-pixel rounding. Record
this as an intentional implementation difference. This is a 2-D projected
aperture angle, not a 3-D anatomical joint angle. It is invariant to uniform
image scaling, translation, in-plane rotation and mirroring, not to out-of-plane
hand rotation, perspective or landmark errors.

## Capture And Storage Boundaries: Implemented In Stage 3

- Keep existing distance samples, metrics, measurement version, live rhythm,
  patient plots and Watch/hand-opening behaviour unchanged.
- For tapping only, calculate both signals from the same observation and frame
  timestamp. Missing angle landmarks must not suppress an otherwise valid
  existing distance sample. Keep angle validity separate from distance validity.
- Store an optional auxiliary payload with explicit degrees, extraction version
  and timestamp convention. Do not put angles in the existing distance samples.
- Retain unavailable processed frames as timestamped entries with missing
  degrees; dropped/unprocessed frames leave time gaps. Do not fill gaps with zero, join velocity
  calculations across gaps or equate absent tracking with impaired movement.
- Snapshot the auxiliary buffer on the recorder queue before background analysis.
  Preserve it through medication/video copies, acceptance, Retake and export.
- Old trials must decode without the new payload. Old distance samples cannot be
  converted uniquely to angles. Reprocessing an available video produces a new
  derived artifact with provenance, not a replacement for the original record.
- Do not save additional videos, upload recordings, request new permissions or
  import clinical models as a side effect of adding the channel.

## Acceptance Checklist

Software checks are recorded below. Physical and external-reference checks remain
pending; passing software tests is not clinical validation.

### Stage 2: Pure Geometry (Passed)

- Known angles: 0, 30, 60, 90 and 180 degrees; near-parallel and opposite vectors.
- Scale, translation, arbitrary in-plane rotation, reflection and thumb/index
  interchange preserve the unsigned angle.
- Equivalent pixel geometry encoded in portrait, square and landscape normalized
  coordinates returns the same result after aspect correction.
- Invalid proportions, NaN/infinity and degenerate vectors return missing;
  touching fingertips with nonzero wrist vectors return a valid zero.
- Existing distance-normalization fixtures remain unchanged and pass.

### Stage 3: Integration And Compatibility (Software Checks Passed)

- Both task-entry paths capture aligned auxiliary timestamps and exclude
  pre-start, post-stop and late callbacks, including immediate Stop and Retake.
- Missing angle data does not change existing samples, metrics or completion.
- Legacy decode and new encode/decode; medication/video copies; save/reload;
  JSON and explicit auxiliary export; full-device archive; video deletion.
- Watch and hand-opening trials have no tapping-angle payload.
- Storage failure preserves the existing recoverable recording flow.

### Stages 4-6: Research And Physical Checks

- Inspect plots over real left/right tapping videos at different distances,
  orientations and lighting; annotate missed landmarks and false cycle events.
- Verify frame orientation and dimensions against video pixels on a real phone.
- Compare feature definitions, preprocessing, trimming and actual timestamps
  against the pinned external implementation; report deliberate differences.
- Establish capture agreement and repeatability before comparing population
  distributions. Do not treat agreement between two algorithms as clinical
  validation or use the same person's repeated videos as independent controls.
- Verify protocol, age/hand coverage, control definition, data-use permissions
  and uncertainty before adding any healthy reference interval.

## Stage 1 Verification Record

Read-only code inspection and external source review completed. Only this
development note was added. No app build, simulator run, physical capture,
clinical validation or population comparison is claimed for this stage.

## Stage 2 Verification Record

16 October 2026, working changes on `codex/finger-tapping-angle`, based on
`af59dae`. Xcode 26.5 (17F42), iPhone 17e simulator, iOS 26.5, x86_64.

```zsh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vCRGlove.xcodeproj -scheme vCRGloveTests \
  -destination 'platform=iOS Simulator,id=9EDA26B4-DE00-43CE-8398-20CB4E6F267E' \
  -derivedDataPath /tmp/vcr-angle-stage2-derived \
  -resultBundlePath /tmp/vcr-angle-stage2-tests.xcresult \
  -parallel-testing-enabled NO -quiet
```

Result: Passed; Xcode reports 194 tests, zero failures and zero skipped tests
(258 executions including parameterized cases). `FingerTappingAngleTests`
passed all eight test methods / 20 argument-expanded cases. Its transform test
checks 120 geometric transformations in both tip orders, 240 evaluations total.
The existing `CameraMovementNormalizationTests` also passed unchanged.

`git diff --check` passed. Source search confirms no capture, recorder or UI
caller for the new helper. Existing distance samples, metrics, measurement
versions and Codable fields were not edited. The helper is deliberately not
wired into recordings; it does not yet generate angle data on the phone.

No physical camera, reference-cohort comparison or clinical validation was run.
Next approval gate: stage 3 auxiliary capture/storage and its compatibility
tests. The shared handbook's source chapters were not changed in this stage.

## Stage 3 Implementation

`VisionHandPoseCapture.onFrame` delivers the existing scalar and auxiliary angle
together on the video queue, using one observation and timestamp. Both task
flows feed the paired frame into `TrialRecorder.ingestCameraFrame`; the existing
scalar callback still drives the live signal monitor. Recording opts into angle
storage only for camera finger tapping. Start/Stop boundaries apply to both
signals on one serial queue, and completed angle buffers are snapshotted before
analysis. The auxiliary channel never drives repetition detection or metrics.

`Trial.fingerTappingAngle` is optional for legacy decoding. Version, degree units
and trial-relative time metadata accompany its frame samples. Trial copy helpers
retain the payload. Existing JSONL saving, Retake and video deletion retain it
without a storage migration. Full JSON and raw full-device snapshots include it.
The separate angle CSV action in Settings > Data appears only when a channel
exists; existing CSV schemas and patient results remain unchanged.

Software verification evidence is recorded below. Physical camera
checks, external-pipeline comparison and healthy-reference validation remain
pending. No new video retention, permissions, network or consent handling was
added.

### Stage 3 Unit Verification

Final working snapshot, 16 October 2026, Xcode 26.5 (17F42), iPhone 17e simulator,
iOS 26.5, x86_64. Same command as stage 2, with result bundle
`/tmp/vcr-angle-stage3-final-tests.xcresult` and the same derived-data directory:
203 tests passed, zero failures/skips (267 executions including parameterized
cases). The preceding run passed 202 tests; the final run includes the added
manual-Stop/late-frame check.

Checks include paired timestamps and final-frame retention, unavailable/invalid
angles versus real zero, unchanged distance analysis, pre-start/post-duration
and post-Stop exclusion, empty/angle-only takes, source/task opt-in, buffer reset,
legacy decode, JSON round-trip, copy helpers, save/reload, full-export snapshots,
video deletion, separate CSV units/missing values and unchanged old CSV schemas.
The existing Retake/save-error/video-storage fixtures now also carry angles.
`git diff --check` and targeted English/German catalog validation passed.

UI verification is recorded below. Hardware callback/orientation correctness,
real recording accuracy, tracking sensitivity and effect on camera performance
remain physical checks; no synthetic fixture proves these properties.

### Stage 3 UI Follow-Up: 19 October 2026

The 16 October UI run passed manual Stop (before/after signal) and private-video
Retake preservation. Its export test failed on a filename accessibility query,
not CSV generation. The filename was exposed with a different element type;
the largest German text size also required scrolling before the filename existed
in the accessibility tree.

Added stable accessibility identifiers to the existing filename and Share
controls without changing their appearance or actions. The export test now uses
those identifiers and explicitly scrolls to the generated file.

The focused rerun passed on the same iPhone 17e / iOS 26.5 simulator with Xcode
26.5: English at standard size and German at extra-large size, hidden export
action without angle records, visible localized action with angle fixtures,
file generation and the system share sheet. Result bundle:
`/tmp/vcr-angle-stage3-export-ui-verified-20261019.xcresult`.
Earlier failed/interrupted export runs are not counted as passes. The complete
unit suite was not rerun for accessibility identifiers and test-only changes;
the saved 203-test passing result was verified instead.

Handbook source-fingerprint verification passed. The PDF is explicitly marked
binary in `.gitattributes`, and `git diff --check` passes without PDF whitespace
noise. This follow-up changes no handbook source chapter, so no additional PDF
regeneration is required. No new algorithm stage was started.

### Physical Export Sanity Check And Gap-Aware Follow-Up: 19 October 2026

Two supplied 30-second tapping recordings had 898 angle-frame entries each.
Videos matched stored filenames/byte counts. Available angle values/timestamps
matched JSON and CSV; missing runs (about 2.5 and 4 seconds) were blank/invalid,
not fabricated zeros, and aligned with sampled hand-out video frames. This is
pipeline evidence, not accuracy validation under changing hand orientation.
No participant data or videos were added to the repository.

The check exposed a separate existing distance-analyzer issue: cycle intervals
crossed tracking gaps and inflated rhythm variability. The user approved a
gap-aware camera-analysis follow-up. It preserves raw signals, angle definition,
recording timing and Watch behavior; new camera trials use a new analysis version.
Old stored metrics are not rewritten. See [metric rules](DATA_FORMATS.md#metrics-and-missing-data).
Local replay through the actual Swift analyzer changed right/left rhythm CV
from 1.196/1.402 to 0.175/0.156, with rates 4.054/4.008 repetitions per second
and observed pause counts 1/0. These are stress-test outputs, not clinical norms.

Final verification: 213 unit tests passed, no failures/skips, using Xcode 26.5
and iPhone 17e / iOS 26.5 (x86_64). Result bundle:
`/tmp/vcr-gap-awareness-verified-tests.xcresult`. Tests cover camera/Watch routing,
visible pauses, gap reset, short dropouts, within-segment decrement, fragmented
metric availability and old/new live-palm version isolation. The initial run
exposed older 2 Hz trend fixtures; these now use realistic 30 Hz camera samples.
A subsequent test-only macro compile error was corrected before the final run.
Neither earlier run is counted as passing. Handbook source-fingerprint and
visual checks of affected pages passed; `git diff --check` passed. The backlog
MOV-007 note was updated without changing its In progress status or other cells.

External-pipeline comparison remains a separate approval checkpoint. A new-build
physical check of tapping and opening/closing with missing tracking and visible
stationary-hand intervals remains pending.

### Camera Cycle-Detection Follow-Up: 19 October 2026

The next four supplied recordings reproduced all stored v2 metrics and matched
JSON/CSV/movie references. Close video inspection exposed missed cycles despite
available samples: changing trough levels did not cross the detector's fixed
reset level. In particular, right opening/closing had a false long interval
around 6.8-9.2 seconds, and left tapping around 13.7-14.5 seconds.

The user approved a camera-only local-excursion correction. V3 follows local
extrema using the existing robust hysteresis-band width; segments start unarmed
and require a fall before the first rise event. It retains smoothing, gap
splitting, minimum spacing and original-valued amplitude/decrement calculations.
The v2 configuration remains available for older display prerequisites. Watch,
raw samples, angles, recording timing and stored older metrics are unchanged.

| Approximate video interval | Manually reviewed movement | V3 events |
| --- | --- | --- |
| Right opening/closing, 6.8-9.2 s | Seven opening excursions, including one partial opening | 7 |
| Left tapping, 13.7-14.5 s | Four taps | 4 |
| Left opening/closing, 10-12 s | Four cycles | 4 |

These are short development checks, not blinded full-video annotations, exact
video/signal synchronization, verified complete clinical repetitions or cohort
validation. Media/raw data and extracted images remain outside the repository.

Replaying the four complete signals with V3 produced tapping event counts
121/131 (right/left), versus 116/114 stored with V2; opening/closing counts
76/78, versus 67/78. Right opening/closing pause flags fell from four to two:
the remaining late intervals align with visible holds. Left tapping's false
mid-recording pause was removed. Changed numbers reflect a different detector,
not improvement in movement or proof that every event is correct. A signal
below the excursion tolerance or an incorrect landmark can still be missed.

New-build physical checks remain pending. External-reference comparison and
clinical scoring have not been started.

Final software evidence: 218 unit tests passed, no failures/skips, Xcode 26.5,
iPhone 17e / iOS 26.5 (x86_64), result bundle
`/tmp/vcr-local-cycle-verified-tests.xcresult`. Coverage includes baseline drift,
small movements at 0.3/1/5 Hz, amplitude decline, scale/offset invariance,
plateau wobble, real holds, tracking gaps and all three camera-version groups.
The first run passed 217/218; a steady gap fixture exposed an initial partial-rise
event. Starting each segment unarmed corrected it without relaxing the test's
rhythm tolerance. The reviewed video-window counts also passed using the final
Swift analyzer. Handbook fingerprint/layout and `git diff --check` passed.
MOV-007 remains In progress with its note updated; broader real-recording and
clinical validation is not marked complete.

## Compatible Historical Trends and Identity Safeguards (19 October)

This follow-up supersedes the earlier all-version separation rule for Results
only. Known live-palm camera analysis v1/v2 signals receive a transient current
v3 analysis; current v3 values remain stored values. Unknown capture methods,
Watch/synthetic sources and different/missing study IDs stay separate. Original
trials, metrics, versions, angles, video references and exports are unchanged.
No historical IDs were linked or relabelled. Remaining boundaries are explained
in Results even when some lines already exist. Research ID edits require Save;
changing an assigned ID requires confirmation and cannot clear it.

Software evidence: 223 unit tests passed on iPhone 17e / iOS 26.5, Xcode 26.5,
including byte-identical session serialization before/after display projection,
allowlisted historical compatibility, unknown/source exclusion, empty/flat
signals, missing identity and explanations alongside existing lines. Result:
`/tmp/vcr-consistent-trends-unit.xcresult`. Focused English/German screen checks
and physical-device review are recorded separately; no clinical validation is
claimed by these software checks.

Focused UI evidence: trend reanalysis notes, original-value labels and concurrent
ID/method explanations passed in English and German (German extra-large text),
`/tmp/vcr-trend-id-final-ui.xcresult`. The German heading was shortened after
visual review. The English ID workflow completed save, unsaved-edit discard,
cancel, confirm and relaunch assertions in the combined run
`/tmp/vcr-study-id-final-verified-ui.xcresult`; that run subsequently failed in
German test navigation, not ID assertions. After replacing generic scrolling
and disambiguating nested alert accessibility nodes, the separate German
workflow passed in `/tmp/vcr-study-id-german-ui.xcresult`. Earlier UI attempts
failed on test navigation/selectors; these bundles are not claimed as wholly
passing suites. No full UI suite or physical-device test was run for this stage.
The workbook's MOV-041 note was updated without changing its Needs verification
status, other cells, formatting or manually maintained statuses. The handbook
was regenerated, its fingerprint checked and affected pages visually reviewed.

## Minimum Usable Takes Contribute to Trends (19 October)

At the user's request, timed takes no longer need to finish the planned timer
to contribute. Eligibility requires ten seconds of continuous tracked signal
and known elapsed time, allowing 0.1 seconds for frame boundaries. Eligible takes
use normal points, daily medians and lines; no short-take category or filter was
added. Current gap-aware camera results can qualify despite tracking loss
elsewhere; unknown/legacy methods retain gap exclusion. Metric-specific evidence,
identity, task/hand, context and requested-protocol boundaries remain. Saved
metrics/records and the analyzer are unchanged. This is a pragmatic display
cutoff, not a validated clinical threshold or an equivalence claim for tests of
different actual duration. Baseline was also removed from the filter without
deleting or reinterpreting historical records.

All 227 unit tests passed (including parameterized runs) in
`/tmp/vcr-minimum-usable-trends-verified.xcresult`. Tests cover early ten-second
takes joining normal medians/lines for rate, size and rhythm, insufficient and
fragmented tracking, usable stretches around gaps, legacy exclusions and
unchanged serialization. An initial attempt did not compile because of test
macro/type-inference expressions; those were simplified before the passing run.
No additional UI or physical-device test was run. Workbook MOV-041 remains Needs
verification; only its note changed, preserving formatting and manual statuses.
Handbook source/fingerprint and rendered pages were checked.

## Earlier Unassigned Tests and Patient-Facing Notes (19 October)

The user confirmed that the earlier unassigned recordings were their own and
approved display-only linking. Review of the provided export established that
the earlier identity was the `unset` placeholder, not a second assigned study
ID. Missing identity was therefore a principal remaining source of faded points;
the ten-second eligibility rule already applied retrospectively.

Unlocked Research Admin now offers a TEAM-only, explicit confirmation action
for earlier unassigned tests. It snapshots session and trial UUIDs into local
preferences; later sessions/takes and assigned identities remain untouched.
Links are removable, never silently retargeted after an ID change, and labelled
in optional history. The full archive includes their provenance in the study
settings snapshot. No real identifiers were bundled and no phone preferences
were changed remotely: the researcher must install and apply the action once
on the phone. Raw session storage and normal JSON/CSV exports keep original IDs.

A local Swift harness mechanically assembled the actual current model, analyzer
and summary sources and replayed the supplied export. Right-tapping rate/rhythm
went from one matching multi-day line to three: earlier before/after-stimulation
series recovered, while newer capture methods remained distinct. Serialization
before/after and original source bytes matched. Other task/hand series were not
combined across methods. Private source media/data and generated harnesses stay
outside Git.

The main patient plot no longer stacks reanalysis, estimated-duration,
unavailable-count and daily-median footnotes. The context legend, separation
link and brief clinical disclaimer remain; optional metric info/history retain
details. English/German screen checks passed, including extra-large German text,
in `/tmp/vcr-clean-patient-trends-ui.xcresult`; screenshots were reviewed.
All 230 unit tests passed in `/tmp/vcr-scoped-test-links-final-unit.xcresult`.
Coverage includes identity-link round-tripping, no automatic future/assigned
relabeling (including a new take in a linked old session), invalid targets,
reversibility and original-record preservation. An initial link fixture omitted
its stimulation context and correctly failed to form a line; the fixture was
corrected without changing production context rules. Research-action interaction
and persistence on the actual phone remain manual checks, not claimed simulator
coverage. MOV-041 remains Needs verification with its note updated, preserving
workbook formatting/manual statuses. Handbook sources, fingerprint and rendered
pages were checked.
