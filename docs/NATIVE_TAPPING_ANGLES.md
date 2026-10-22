# In-App Tapping Angle Measurements

Implemented 21 October 2026. This adds measurements alongside the existing
distance-based results. It does not change recording duration, camera geometry,
distance analysis, trend eligibility or healthy-reference comparisons.

## Where They Appear

The finger-tapping recording result has a separate bilingual **Tapping angles**
section. It shows opening angle (degrees), mean absolute angular speed
(degrees/second), angle-based tapping rate (taps/second) and interval variability
(CV displayed as a percentage). Unavailable results are not shown as zero.
These are projected camera-view angles, not anatomical joint angles or scores.
Hand position, perspective and tracking noise affect them.

## Calculation Contract

`FingerTappingAngleAnalyzer` accepts only the known auxiliary angle version,
degree units and trial-relative timestamps. Calculation version:
`vision-angle-timestamp-gap-aware-v1`.

- Timestamps must be finite, nonnegative and strictly increasing; otherwise the
  summary is unavailable. Input order is never silently sorted.
- Missing/nonfinite/out-of-range angles break segments. Zero degrees is valid.
  Timestamp gaps greater than 0.2 seconds also break segments. No interpolation,
  smoothing or connection across segments is performed.
- Within each segment, a five-degree reversal identifies an opening peak. Two
  successive peaks form an accepted interval only if separated by at least
  0.15 seconds with an intervening angle at or below 10 degrees. These are
  algorithmic detection rules, not clinical thresholds. Small or incompletely
  closed movements may lack cycle-derived values; their raw signal is retained.
- Opening angle is the arithmetic mean of unique peak angles participating in
  accepted intervals. It is not normalized distance or peak-to-peak excursion.
- Angular speed is total absolute adjacent-sample angular travel divided by
  tracked duration, across segments with at least three samples. It is
  time-weighted, includes tracked stationary periods, excludes missing time and
  is not maximum opening velocity. Tracking jitter can increase it.
- Tapping rate is mean reciprocal accepted interval duration. Rhythm CV is
  population standard deviation of interval durations divided by their mean.
  Both need at least two accepted intervals. Neither bridges missing tracking.
- Evidence includes accepted interval/unique peak counts and tracked seconds.
  Tracked seconds is not necessarily the entire recording duration.

The reversal, closure and spacing rules need independent accuracy validation.
The algorithm can miss valid movements; unavailable is not proof of incorrect
performance. No healthy/abnormal cutoffs or reference ranges are provided.

## Relation To The Reference Work

The [offline ROC-HCI kernel](ROC_TAPPING_FEATURES.md) remains a separate method.
This native version deliberately uses actual timestamps and does not reproduce
the author's missing-data interpolation, nominal frame clock or boundary-peak
trimming. Definitions and extraction therefore differ despite common units.
Do not compare these values directly with published control percentiles or the
offline feature table. Protocol/detector alignment and independent validation
are still required before adding healthy-reference feedback.

## Saving And Compatibility

### First Ten Complete Taps

Added 21 October after explicit approval: camera tapping trials also save an
optional `fingerTappingReferenceSegment`. This is a separately versioned source
window, not new patient results or a replacement for the full recording.
Recording remains 30 seconds and all existing analyses retain the full signal.

Selection version `vision-first-ten-consecutive-complete-taps-v1` uses the same
five-degree reversal, 150 ms spacing and <=10-degree closure rules as the native
summary. It takes ten successive complete opening-to-opening cycles (eleven
opening peaks) from the first tracked segment. Leading missing frames and an
initial incomplete movement are excluded. A missing angle or gap >0.2 seconds
ends the segment; an interrupted candidate sequence is not restarted later to
find a better stretch. No interpolation or joining across loss is allowed.
This conservative eligibility applies only to the comparison window, not normal
saving, patient results or trend eligibility.

The object stores zero-based half-open sample indices into the original angle
array, trial-relative start/end times, eleven peak times, count and selection,
angle-source and detector versions. It does not duplicate samples. Too few
complete cycles leaves the field absent; the original recording saves normally.
Legacy recordings are not rewritten. JSON/JSONL/full-data exports preserve the
field; CSV schemas remain unchanged.

This approximates the reference study's tap count, not its entire protocol.
Performing ten taps while expecting a 30-second task can differ from instructions
to perform only ten taps. See the [reference bridge](TAPPING_REFERENCE_BRIDGE.md).

New camera finger-tapping trials save optional `fingerTappingAngleMetrics` with
their original signals and existing metrics. The field survives medication/video
reference copies, JSON/JSONL saves and JSON/full-data exports. Existing CSV schemas
remain unchanged; CSV does not yet contain these summary fields.

Older recordings with compatible angle samples can obtain a display-only summary
on their recording result screen. The stored record is not rewritten. Older
recordings without angles, Watch trials and hand-opening/closing have no tapping
angle summary. An unknown saved calculation version is not silently reinterpreted.
Daily trend plots continue to use the existing distance-based measurements.

## Verification And Device Check

The final simulator unit suite passed 239 methods (307 executions), no failures/skips.
New tests cover known periodic angles, timestamp-rate scaling, missing-frame and
long-gap separation, flat/zero/open-only signals, invalid clocks, JSON round trips,
legacy decoding and preservation through Trial copies. Existing distance tests
remain unchanged. Recorder integration, accepted-recording snapshots and JSON
exports retain the new summary, while existing CSV schemas remain unchanged.
The native calculator also processed all seven tapping-angle
trials in the supplied 21 October export without modifying source files.

For its newest continuous right-hand recording: 117 accepted intervals, 118
opening peaks, 29.901 tracked seconds, mean opening angle 37.699 degrees, mean
absolute angular speed 276.402 degrees/second, mean reciprocal-interval rate
4.043/second and period CV 0.1611. These are reproducibility examples, not
accuracy validation or healthy reference values. No participant files are in Git.

The new result-screen UI test passed in English and German at the largest app
text size; screenshots were inspected. A section identifier initially shadowed
child row identifiers; it was removed and the focused test passed on rerun.
The existing bilingual video save/playback/share/delete/relaunch regression also
passed. These simulator checks are not physical camera validation.

Physical verification remains: record both hands, test early Stop/retake, confirm
the angle section and exported JSON after relaunch, and visually validate peak
detection with the movie/signal timing anchors. Healthy bands remain pending.
