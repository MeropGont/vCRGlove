# Movement Results

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

Date/context/medication filters act **before** daily aggregation. Participant ID,
task, hand, source, measurement version and stop protocol remain separate. A
30-second test never shares a line with a 15-second or ten-repetition test.
Medication filters describe reported elapsed time, not medication ON/OFF state.
All medication timings can mix dose timings; narrow the hour window when needed.

Completed duration tests normally require actual duration within 0.5 seconds of
their target, allowing timer scheduling tolerance. Older camera duration tests
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
These are protocol checks, not clinical performance thresholds. Short,
unresolved-duration and signal-gapped recordings remain separate observations
and do not contribute to complete-test medians. Missing values never become
zeros. An intervening recorded day with unusable input breaks that line; days
without any recording are not invented.

Historical full-duration rate/rhythm values can form their own lines. New
measurement methods never join those lines. Old size values remain visible in
history in their original units, not relabelled as palm lengths.

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

The analyzer's formulas and old raw signals/metrics are unchanged. New camera
signals use live palm normalization and aspect-correct image distances instead
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
