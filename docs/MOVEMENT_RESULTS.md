# Movement Results

21 October addition: a separate [native tapping-angle summary](NATIVE_TAPPING_ANGLES.md)
appears after camera finger-tapping recordings. It does not replace the existing
metrics or add angle values to these distance-based daily trend series. Healthy
reference ranges remain unimplemented.

## Implemented View

Results offers rate, movement size and rhythm variability for each camera task
and hand. Watch rate/rhythm remain separate; its rotation-rate amplitude is not
presented as spatial movement size. More details contains pauses and, for camera
tasks, amplitude change per repetition. No clinical composite, normal range or
MDS-UPDRS rating is calculated.

The information button explains the selected metric and comparison limits.
The main chart keeps only a short median/clinical-score caption, including at
large text sizes. When no line is possible, a data-dependent explanation
identifies a one-day, study-ID, method, context, protocol or capture boundary
instead of only asking for more measurements.

Each point is a daily median of matching complete recordings, using the trial
start date in the current local calendar. Before stimulation, after stimulation
and no stimulation planned have distinct colours, symbols and line styles.
Lines join measured days without smoothing, extrapolation or treatment-effect
claims. Historical Baseline and unspecified context remain grey, unconnected
observations. Context is reported, not verified stimulation exposure.

Tap a day for its medians, counts, ranges and contributing-recording link.
VoiceOver provides a Latest day action. Recording history is a separate link,
newest first, initially 50 rows with further batches of 50. The Data shortcut
opens measurement export and private-video management. No long history list or
duplicate generic recording-details block occupies the main results page.

## Comparability

The stimulation filter omits the obsolete Baseline choice. Historical baseline
records remain readable and available under All stimulation timings; their
context is never reinterpreted as no stimulation planned.

Date/context/medication filters act **before** daily aggregation. Participant ID,
task, hand, source, effective measurement method and stop protocol remain separate. A
30-second test never shares a line with a 15-second or ten-repetition test.
Medication filters describe reported elapsed time, not medication ON/OFF state.
All medication timings can mix dose timings; narrow the hour window when needed.

Timed recordings contribute to normal daily medians and lines once they contain
10 seconds of continuous usable tracking and a known elapsed duration of at
least that length. A 0.1-second timestamp tolerance accommodates the final frame.
Finishing the planned timer is not required: a usable 10-second take from a
30-second task joins the same series as a completed take. This is an app
eligibility rule, not a clinically validated duration threshold. No new filters
or short-recording categories are introduced. Existing metric-specific signal
and repetition evidence is still required; slow movement is not rejected by a
new speed threshold.

Current gap-aware camera analysis (including compatible historical signals
projected through it) can contribute despite tracking loss elsewhere if it has
that usable continuous stretch. Missing intervals are not filled, and genuine
observed pauses remain in the analysis. Other methods retain their gap warning
because their saved metrics may bridge missing observations. All metrics still
describe the recorded signal; the app does not select only the fastest segment.

Older camera duration tests
with both `recordedDurationSeconds` and `measurementVersion` absent have a narrow
display-only fallback: ordered finite signal samples must support analysis, have
no existing 2-second gap warning, end within 0.5 seconds of the requested target
and span at least target minus 0.5 seconds. Those records can contribute to
historical daily medians and lines. The chart/day summary labels estimated
durations; history shows the approximate value from the final sample timestamp.
This is evidence of signal coverage, not proof of the elapsed capture time or
recording quality. No stored record, version, metric, ID or export is rewritten.
An explicit invalid/short duration is never replaced by an estimate. New-version,
Watch, synthetic and repetition-test recordings cannot use this fallback.

Repetition tests require their target count and a known positive duration.
These are protocol checks, not clinical performance thresholds. Below-minimum,
unresolved-duration and otherwise unusable recordings remain separate observations
and do not contribute to usable-test medians. Missing values never become
zeros. An intervening recorded day with unusable input breaks that line; days
without any recording are not invented.

Historical full-duration rate/rhythm values can form their own lines. Known
live-palm camera analysis v1/v2 signals are reanalysed with the current v3
detector for display only, allowing compatible recordings to share a line.
Current v3 recordings retain their saved metrics. Unknown/unversioned methods,
Watch and synthetic sources are not reinterpreted. Old size values remain in
their original units, not relabelled as palm lengths. Saved metrics, versions,
raw samples and exports are unchanged.

Different study IDs never share a line; missing IDs also remain individual
observations. Changing the researcher-configured ID affects future recordings,
not historical ownership. No automatic aliases or device-based identity merging
are used. An explicit exception is available in unlocked researcher settings
for a TEAM ID: **Link earlier test recordings** snapshots the existing unassigned
test-session and trial IDs after confirmation that they belong to the researcher. These
local display links do not include future takes (even within an old session) or overwrite
assigned identities. They persist independently of future ID changes and can
be removed without changing stored data. The researcher must apply this action
on the phone after installing the build; developer-side approval alone does not
change phone preferences. This is not a participant-enrolment or ownership
correction tool. Historical acquisition-method boundaries still apply.

The **Why some points are separate** sheet explains remaining ID,
method, context, protocol and recording-coverage boundaries even when other
lines are visible. Selected days/history also show the relevant reason.
Uncertain/incomplete points use a faded context colour, not an unknown-context
colour. The main patient chart keeps the context legend, a separation-info link
when needed, and a brief clinical disclaimer. Reanalysis/duration-estimation
notes and unavailable-result counts are available through the existing metric
info button, not as stacked grey footnotes. History retains per-recording
provenance, including display-linked earlier tests.

## Metric Definitions

- Rate: existing event-based cycles per second, labelled taps/repetitions per
  second. It is not a movement-velocity measurement or good/bad threshold.
- Movement size: mean peak-to-peak excursion of the camera's scalar, divided by
  live wrist-to-middle-MCP length. Values are relative palm lengths, not cm.
  Camera angle, hand pose, occlusion and tracking still affect interpretation.
- Rhythm variability: interval CV multiplied by 100. Lower means more even
  intervals, not necessarily improved health. A real zero remains valid.
- Pauses: intervals exceeding twice the recording's median interval, not a
  diagnosis of freezing. Signal gaps are flagged separately.
- Amplitude change: existing mean-normalized amplitude slope per cycle.
  Negative means declining amplitude; it does not establish fatigue or severity.

Older stored signals/metrics remain unchanged. New camera analysis is gap-aware:
rate, rhythm and pauses use only intervals observed within continuous segments,
and amplitude/decrement do not bridge missing observations. Disconnected single
events do not produce a misleading zero rhythm value. Compatible live-palm
versions share current display analysis; unknown capture methods remain separate.
Neither old nor new live-palm size data are hidden merely because of a version
change. See the precise continuity and
aggregation rules in [Data formats](DATA_FORMATS.md#metrics-and-missing-data).

Camera analysis v3 follows local rises/falls rather than fixed signal levels,
retaining the same robust excursion-band width. This addresses missed cycles
when the signal's closed-hand baseline changes. Rate/rhythm/pauses remain
descriptive detector outputs, not confirmed movements or clinical scores.
Video-reviewed segments support the specific correction; broader accuracy and
new-build device validation remain pending. Existing stored records are not
rewritten; compatible display-only reanalysis is described above.

Camera signals use live palm normalization and aspect-correct image distances instead
of a saved image-space calibration denominator. Calibration remains available
for positioning/readiness guidance. At least three visible fingertips are still
needed for opening/closing; changing visibility can affect the signal.

The optional trial `measurementVersion` records the signal/analyzer definition;
see [Data formats](DATA_FORMATS.md). Velocity and validated composites remain
separate research tasks, not implied by this display.

## Validation Status

Synthetic geometry and aggregation tests check scale/aspect/mirror invariance,
medians, context/protocol/version isolation, missingness, filtering, local dates
and backward compatibility. Simulator UI checks cover English/German, large
text, selected-day navigation and filters. These do not validate physical hand
tracking, perspective invariance, clinical accuracy or Watch hardware. Complete
the physical checks in the [testing checklist](../Testing/vCRGlove_testing_checklist.md).

The duration fallback has regression cases for historical multi-day lines,
estimated/measured daily medians, late-start/short/gapped/malformed signals,
explicit-duration precedence and unchanged serialization. Raw export checks
must remain local; no real recordings or participant identifiers belong in Git.
