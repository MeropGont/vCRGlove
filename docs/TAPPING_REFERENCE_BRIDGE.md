# Tapping Reference Bridge

21 October 2026. Implemented work is separate from pending scientific adoption.

## Implemented In The App

Full 30-second recording and existing patient results remain unchanged. New
camera tapping trials can save a separate first-ten-complete-tap source window.
It retains sample indices, times and method versions, not duplicated raw data.
Missing or insufficient tracking leaves it unavailable without blocking saving.
See [native selection rules](NATIVE_TAPPING_ANGLES.md#first-ten-complete-taps)
and [saved fields](DATA_FORMATS.md#first-ten-tap-comparison-window).

Accepted sessions accumulate in the local store. Recording history provides
individual review. Data exports include all saved sessions; a researcher-only
per-session selection/export browser is not implemented.

## Local Research Comparison

`tools/compare_tapping_landmarks.py` compares saved live Vision angles with
MediaPipe detection on the corresponding private movie. This tool is not an
iPhone dependency and uploads nothing. Install its separate pinned Python
requirements from `tools/requirements-landmark-validation.txt`; do not replace
the original ROC-HCI environment or add MediaPipe to the iOS target.

```zsh
python tools/compare_tapping_landmarks.py sessions.json clip.mov \
  --trial TRIAL_UUID --output /tmp/new-private-comparison-directory
```

Method `vision-mediapipe-paired-angle-v2` requires a supported saved movie timing
anchor, matching filename/bytes and increasing real decoder presentation times.
Movie display orientation is explicitly enabled and checked before detection;
unknown orientation or a decoder unable to apply it is rejected. Nearest-frame
pairing is one-to-one within 18 ms, with no signal-fitted offset or interpolation.
Missing values remain missing. Detector confidence, model/code/source hashes,
dimensions, versions and signed frame differences are recorded in private output.
Reports and participant frames must remain outside Git.

The main angle uses floating, aspect-correct wrist/thumb-tip/index-tip pixels;
integer-pixel angles are an additional sensitivity channel. Exactly one hand and
hand-label confidence >0.9 are required. The label is not independent anatomical
side verification. MediaPipe 0.10.21 is newer than the study's historical pipeline.
Movie compression and detector effects cannot be disentangled here.

The report separately runs both channels through the same pinned author-derived
50-feature kernel. Unlike frame pairing and native app analysis, that kernel
retains its documented missing-data interpolation and segment trimming. Inspect
selected/trimmed ranges and interpolation counts: different ranges confound a
feature-to-feature comparison. Frame-level descriptive difference bounds are not
independent-person confidence intervals or clinical acceptance limits.

Initial landscape-input exploratory runs were superseded by explicit portrait
display-orientation runs. Do not use the old runs as final orientation-controlled
evidence. Two test clips from one person are not population validation.

### Current Verification

Two supplied 21 October tapping movies were decoded completely (902 frames each)
and paired to their 898 saved angle entries using capture anchors, with maximum
timestamp error below 0.834 ms. In the earlier/later clips respectively, 860/894
frames had confident paired detections. Median absolute angle differences were
1.52/1.94 degrees; 95th-percentile absolute differences were 4.52/3.84 degrees.
These are descriptive agreement results, not accuracy against ground truth.

In the later clip, the common author-kernel trimmed range matched, but mean
angular speed was about 12% lower with MediaPipe. In the earlier clip, additional
missing MediaPipe detections changed the selected range, so its whole-recording
feature comparison is additionally confounded. No conversion factor is inferred.

Software verification: 243 native methods / 311 executions, 51 offline tests and
three bilingual simulator UI regressions passed. Native replay reproduced the
latest saved full-recording summary exactly. Physical verification of newly
saved first-ten metadata and broader independent cycle validation remain pending.

## Remaining Before Healthy Bands

### Fixed Ten-Cycle Check (21 October)

The next research-only step compared the exact native-selected first-ten window
in both timestamp-paired clips, without changing app results or source exports.
The reusable `fixed_window_agreement` helper validates the saved segment contract,
indices, eleven peak times and sample/pair alignment. New exports containing the
segment receive this comparison automatically in the local research report;
older test exports were reviewed with the native Swift selector's read-only output.

Each window had one uncertain MediaPipe frame. Full-window unfilled speed is
therefore unavailable, while comparison over identical observed adjacent
intervals covers 97.2%/97.0% of window time, without bridging or interpolation.
MediaPipe mean absolute angular speed was 9.1%/10.9% lower on that common support.
Median absolute angle differences were 1.68/1.74 degrees (earlier/later clips).

The author kernel's trimmed rates were 4.196 versus 4.209 taps/s in the earlier
clip and 4.643 versus 4.643 in the later one. The earlier trimmed ranges and peak
counts differed, so those rates are not evidence of identical detected cycles.
The later trimmed ranges/counts matched, but speed still differed by 12.7% and
mean opening angle by about 1.95 degrees. That author-kernel comparison includes
one interpolated MediaPipe frame per window, reported separately from the
noninterpolated common-support calculation.

Sixteen focused research-tool tests passed, including identical-input parity,
missing-pair handling and rejection of stale/misaligned segment metadata.
This makes rate a stronger initial reference candidate than angular speed, not
a validated healthy band or a basis for a conversion factor. The windows were
selected by Vision, are from one tester and retain the 30-second pacing mismatch.

### Public Rate Candidate (21 October)

The pinned public CSV can now be summarized reproducibly with:

```zsh
python tools/audit_tapping_reference.py public-feature-table.csv --rate-candidate
```

This research-only option verifies the pinned table hash and reports separate
hands, with all no-PD-labelled rows as the descriptive starting set. Excluding
any expert difficulty flag and aggregating filename-group medians are separate
sensitivity analyses, not silently adopted clinical exclusions or verified
participant weighting. Eight audit tests passed. No app code or patient charts
changed, and no raw reference rows were bundled.

| Hand | All rows | Median taps/s | Descriptive 5th-95th percentiles | Unflagged rows | Unflagged median |
| --- | --- | --- | --- | --- | --- |
| Left | 78 | 3.915 | 2.631-5.062 | 57 | 3.916 |
| Right | 78 | 4.050 | 2.474-5.087 | 57 | 4.050 |

Filename-group medians produce 76 groups per hand (55 unflagged), with medians
3.915/4.056 overall and 3.916/4.051 unflagged. Thus central rates are stable under
these choices, although the right-hand upper tail changes with quality filtering
(95th percentile 5.087 versus 4.790 taps/s). Counts are recordings/groups, not
verified independent people. Quantiles use linear interpolation at `(n-1)*p`.

These results support a possible clearly labelled *reference-study comparison*
for tapping rate, not a healthy/abnormal verdict, an age-adjusted norm, a confidence
interval or an efficacy claim. A future app implementation must use the separately
matched first-ten rate rather than compare ordinary full-session/daily-median
chart values directly with this table. No further video collection is needed to
produce this candidate; protocol and population limitations remain explicit.

### Neutral In-App Study Context

Implemented after explicit approval on 21 October: the finger-tapping recording
result includes a neutral study-context section. It shows the mean reciprocal
interval rate across the native first ten complete detected cycles and the
same-hand study median (left 3.9151882425, right 4.05034882 taps/s). These are
all no-PD-labelled recording medians from the pinned table above, not clinician-
screened healthy thresholds. No percentile, score, colour band, direction of
improvement or percent-of-normal is shown. Ordinary trend values are unchanged.

The info sheet identifies the study and 78 recordings per hand, links to the
paper, and explains camera/detector, duration and age-adjustment limitations.
The native ten-cycle rate is not the complete historical author kernel: event
selection and boundary trimming differ. Shared units and reciprocal-interval
arithmetic do not establish interchangeability. Display is study context only.

The same section is now permanently accessible on Movement > Results/Trends,
below the plot for finger tapping. It shows the latest usable ten-tap comparison
among the selected hand and active period/stimulation/medication filters, with
the source recording's date and time. A newer unusable recording does not erase
the previous available comparison; its older date remains explicit. Selection
does not depend on availability of the currently plotted distance-based metric.
Changing hand updates both the recording and same-hand study median. Other tasks
do not show a tapping reference. This adds no line/band to the existing trend.

22 October verification: the permanent Results comparison passed its bilingual
UI test, including both hand values, recording date and info-sheet dismissal.
The sheet is owned by the page, not a virtualized Form section. The separate
unavailable-comparison/save-controls test also passed with an explicit font
setting, avoiding inherited simulator preferences. The native selection/filter
suite previously passed 246 methods / 314 executions; presentation fixes do not
change those calculations. Physical phone review remains pending.

Compatible legacy angle recordings obtain the first-ten value by display-only
replay. A saved segment must match the current selector exactly; unknown/stale
metadata remains unavailable. Too few cycles or tracking loss does not hide
ordinary results, block saving or prompt a mandatory retake. No raw reference
rows, extra recording data or modified storage schema are added by this view.

Verification checklist for this stage:
- [x] Unit tests: 245 methods / 313 executions, no failures. Both hand medians, first-ten-only calculation, unchanged tail/copies,
  legacy replay and refusal of unknown selection/insufficient/wrong-source data.
- [x] Two focused UI tests passed. Bilingual large-text UI: both values, source explanation dismissal and reachable
  save/retake controls; separate insufficient-data UI check.
- [ ] Physical check pending: view a new and a compatible historical tapping result
  on the phone. Confirm that only study context, not healthy/abnormal feedback,
  appears and that normal saving/recording flow is unchanged.

### Personal Movement Feedback (22 October)

The main Results page now places feedback below Filters. "Your movement pattern"
shows the latest usable matching recording and its rate, rhythm variability and
relative movement size (where supported). Tapping also shows descriptive angular
speed when its angle summary has accepted cycles. No fist angular velocity,
clinical composite or predicted UPDRS rating is inferred.

Personal typical values use daily medians from up to seven prior matching
recording days, excluding the latest recording day. Days, not individual takes,
receive equal weight. Identity/context/source/method/protocol and reported
medication status must match; the active period and medication-time filters
also apply. The existing trend-usability rules govern comparison eligibility;
short usable takes are not newly excluded from the plots. Missing dimensions
remain unavailable instead of zero. Existing stored metrics are not rewritten.

A neutral dashed personal-typical line can appear on a single comparable
rate/rhythm/size series. It is not shown across mixed contexts/methods/identities
or standalone/uncertain series. There is no healthy band, improvement label or
statistical-significance assertion. Numerical differences are descriptive only.

"Compare with research recordings" is now an optional separate page below the
personal profile. Its source and limitations stay behind its info button. The
personal info sheet explains measures and matching, rather than filling the
main page with warnings. Watch profiles use existing rate/rhythm only; no new
Watch acquisition or reference method is introduced.

- [x] Two focused calculation tests passed: daily weighting, context/medication
  separation, seven-day history limits, absent data and separate angular speed.
- [x] One bilingual UI scenario passed: English/German profile, hand switching,
  personal typical values and optional research navigation.
- [ ] Physical phone layout and interaction review.

### Remaining External-Reference Validation

Paused by user on 22 October 2026. The current descriptive personal profile and
optional per-hand study rate median remain available. Future work is tracked in
MOV-015 (richer healthy and PD reference distributions) and MOV-045 (separate
task/hand MDS-UPDRS-related scoring and meaningful change). Neither validated
PD severity estimates nor clinical improvement thresholds are implemented.

- Compare the same approved first-ten window across detectors and visually verify
  each detected cycle on multiple recordings, hands and camera views.
- Resolve detector/encoding effects, particularly for angular speed; small angle
  differences do not establish speed interchangeability.
- Confirm participant grouping, intended dataset use, quality exclusions and
  applicability of the public no-PD-labelled reference population.
- Assess the remaining protocol difference: ten requested taps versus the first
  ten observed cycles during a task expected to last 30 seconds.
- Agree and validate participant-level reference methods before patient feedback.

The target remains the [Islam et al. 2023 method](https://doi.org/10.1038/s41746-023-00905-9),
not a validated healthy standard for our app. No healthy band, composite clinical
score, hand-opening reference or diagnostic interpretation is enabled here.
