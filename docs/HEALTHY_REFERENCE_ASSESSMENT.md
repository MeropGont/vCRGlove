# Healthy References: Dataset And Protocol Assessment

Reviewed 19 October 2026. Stage 5 assessment complete; candidate adoption,
independent accuracy validation and patient reference bands are not approved or
implemented. This is a feasibility review, not a systematic review or clinical norm.

## Recommendation

21 October implementation update: a separate first-ten-complete-tap window is
now saved alongside new full-length tapping trials. Paired Vision/MediaPipe
research tooling records timestamp and display-orientation provenance. See
[reference bridge status and remaining gates](TAPPING_REFERENCE_BRIDGE.md).
Neither change establishes interchangeability with the reference population.

Continue with the Islam/ROC-HCI tapping method as an **offline comparison target**,
not a ready-made healthy standard. Its public feature table is useful, but our
measurement pipeline and recording duration are not interchangeable with it.
Resolve participant grouping and intended data use with the authors before
constructing any participant-weighted reference distribution.

In parallel, consider an appropriately approved local control study using the
actual app. That would address the phone, camera-view and duration mismatch and
eventually support hand opening/closing too. This review does not authorize new
participant recruitment or changes to the study protocol.

## Candidate Datasets

### 1. Islam / ROC-HCI: Best Starting Method, Not Ready For Patient Bands

The [2023 paper](https://doi.org/10.1038/s41746-023-00905-9) reports 250 people,
including 78 reporting no PD diagnosis. The task requests ten taps per hand, with
webcam recording at 30 frames/s. Raw videos are not publicly shared; extracted
features and ratings are available. Absence of a self-reported PD diagnosis is
not a clinically screened healthy population. [Full article](https://pmc.ncbi.nlm.nih.gov/articles/PMC10444879/).

The [public repository](https://github.com/ROC-HCI/finger-tapping-severity) has an
MIT licence. It provides feature tables and code, not an explicit patient-reference
deployment agreement. Record the licence/attribution and obtain clarification of
the intended data use and participant mapping before adopting reference values.
No participant-level table or external feature code is bundled with the app.
A separately attributed MIT [offline feature subset](ROC_TAPPING_FEATURES.md) is
now implemented in research tooling, not the iOS target.

**Direct audit of the pinned CSV**, not counts inferred from the paper:

| Check | Result |
| --- | --- |
| All rows / no-PD-labelled rows | 489 / 156 |
| No-PD rows by hand | 78 left, 78 right |
| Unique filename-and-hand keys | 156; no duplicate keys |
| Any expert difficulty flag | 42 of 156 no-PD rows |
| Consensus ratings in no-PD rows | 0: 69; 1: 57; 2: 27; 3: 3 |
| Ages per hand | Under 50: 22; 50-59: 14; 60-69: 30; 70+: 12 |
| Author filename-grouping rule | 76 groups: 74 with two rows, two with four |

The grouping rule does not recover 78 distinct people from the 156 control-hand
rows. This may reflect repeated recordings or identifier collisions; it is not
proof of either. Demographic agreement within groups does not resolve identity.
Request the authoritative mapping; do not invent independent participant counts,
merge groups automatically or treat both hands as separate people.

The selected five feature columns are finite in all no-PD rows. Finite values do
not establish correct movement execution. A rating above zero is not a diagnosis;
neither selecting all no-PD rows nor retaining only rating-zero rows establishes
a representative healthy distribution. Define exclusions before inspecting
patient comparisons, and report the resulting independent-person counts.

### 2. HUBU-FIS: Useful Raw-Video Validation Candidate

[Version 1, DOI 10.5281/zenodo.17738775](https://zenodo.org/records/17738775)
contains 234 left/right tapping videos from controls and people with PD, plus a
filename/UPDRS table. The archive is about 10.8 GB; record metadata declares
CC BY 4.0. The public description does not establish independent control counts,
age/dominance coverage, repeat structure or exact duration/instructions. Do not
equate UPDRS zero with healthy control membership. No movies were downloaded.

The linked [analysis repository](https://github.com/arelraptor/UBU-PD-FT-Assessment)
uses MediaPipe and has an Apache-2.0 code licence. Its two-column rating format
alone cannot establish a demographic normative cohort. Request participant-level
metadata and task details before deciding on a download or normative use.
[CC BY](https://creativecommons.org/licenses/by/4.0/) requires attribution and
change disclosure; privacy/personality rights may still matter. Open licensing
alone is not approval of our proposed clinical use.

### 3. FastEval: Potential Collaboration, Restricted Access

[FastEval Parkinsonism, 2024](https://doi.org/10.1038/s41746-024-01022-x)
uses 840 videos from 186 people, including 47 healthy controls, with MediaPipe
features and a different inference pipeline. Its data statement requires an
approved proposal and institutional permission for de-identified data; raw clips
are not publicly accessible. [Full article](https://pmc.ncbi.nlm.nih.gov/articles/PMC10853559/).
This is a collaboration candidate, not an immediately downloadable reference.
Score-zero summary statistics must not be relabelled as healthy norms.

### Additional Healthy Benchmarks Selected After Follow-Up Search

The user confirmed the healthy-control goal; a reference cohort's absence of PD
is appropriate, not a reason to reject it. The remaining questions are how the
controls were characterized and whether measurements/protocols are comparable.

The [2026 camera study](https://www.nature.com/articles/s41531-026-01316-9)
includes 30 healthy controls, median age 66, and uses wrist/thumb/index landmarks
at 30 fps. It records at least 12 s and analyzes seconds 2-12. Its healthy tapping
angle, velocity, frequency and variability summaries are relevant external
benchmarks; individual data require a reasonable request, and code is not public.
This is an additional comparison target, not an already reproduced algorithm.

[Maremmani et al. (2022)](https://pmc.ncbi.nlm.nih.gov/articles/PMC9541466/)
includes 50 healthy controls, mean age 65.5, performing both thumb-index tapping
and hand opening/closing, bilaterally, with repeated 10 s recordings. Published
tables provide healthy counts, amplitude and opening/closing speed summaries.
Further aggregated data can be requested. Finger-mounted inertial sensors measure
different angular quantities from our camera, so rate is a more immediate
comparison target than transferring sensor velocity thresholds.

## Why The Existing App Cannot Use Those Numbers Directly

| Boundary | Current app | Candidate target / implication |
| --- | --- | --- |
| Protocol | Up to 30 s, early Stop, gaps | Ten taps in Islam; duration-dependent features need a matched window |
| Rate | Number of usable intervals / sum of intervals | Author mean frequency averages reciprocal intervals; generally not the same |
| Movement size | Palm-normalized distance excursion | Author angular amplitude uses opening-peak angles, not excursion |
| Angular speed | Exploratory raw absolute velocity median/p95 | Author mean absolute derivative after denoising and trimming |
| Rhythm | Interval CV from current gap-aware events | Need matched event selection, gap policy and variance convention |
| Capture | Vision, actual timestamps, projected aperture | MediaPipe, different filtering and frame timing; shared units are insufficient |
| Chart summary | Daily medians of matching recordings | A single-trial reference distribution is not automatically a daily-median reference |

The rate/amplitude/speed distinctions were verified in the pinned author code
and our current Swift analyzer. For example, intervals 0.2/0.4 s produce an
average reciprocal rate of 3.75/s but an inverse-average-interval rate of 3.33/s.
An identical-looking unit does not make the estimators interchangeable.

The 83-person [age-related tapping study](https://pmc.ncbi.nlm.nih.gov/articles/PMC9028619/)
supports considering age, but its index-finger gyrosensor, 250 Hz acquisition and
15 s task measure a different angular quantity from projected thumb-wrist-index
aperture. Do not transfer its speed limits into the camera plot.

[StrivePD's documented Watch measures](https://help.strive.group/hc/en-us/articles/19944525788685-Tremor-Dyskinesia)
concern tremor/dyskinesia, not a verified public healthy cohort for our camera
tasks. A future partnership needs task-matched data and explicit access terms;
StrivePD availability alone supplies neither. The Maremmani study above is now
the selected clinical benchmark for the fist task; no Watch-specific reference
has been adopted.

## Implementation And Remaining Steps

1. Ask ROC-HCI authors for the control-person mapping, repeated-visit/dominance
   information, quality exclusions and intended use of derived reference summaries.
   Ask HUBU-FIS for equivalent metadata and its exact acquisition protocol.
2. Implemented: a separately versioned [offline feature subset](ROC_TAPPING_FEATURES.md)
   matches peak amplitudes, absolute angular speed and period/rate statistics with
   the pinned selected author routines. App metrics are untouched. This verifies
   feature-kernel arithmetic, not historic CSV reproduction or camera accuracy.
3. Propose a fixed ten-tap comparison segment within the existing recording,
   rather than selecting the best-performing segment. This only partially
   addresses protocol mismatch: a 30 s instruction may change initial pacing.
   Do not change patient recording instructions without approval.
4. Independently annotate videos and compare Vision/MediaPipe results on the same
   clips. Assess absolute bias, limits of agreement and test-retest variation,
   including hand angle, age, camera/device and impairment. Correlation alone
   cannot establish interchangeable measurement.
5. Only after compatibility and governance review, estimate per-task/per-hand
   reference distributions with participant-level weighting. Account for age and
   dominance where data support it; sparse groups should remain unavailable.
   Report sensitivity to exclusions and uncertainty, not just a single cutoff.

For a future shaded plot band, use an explicitly defined distribution/reference
interval for individuals, **not the confidence interval of a group mean**. NIST
distinguishes [mean confidence intervals](https://itl.nist.gov/div898/handbook/prc/section1/prc14.htm)
from [prediction intervals](https://www.itl.nist.gov/div898/handbook/pmd/section5/pmd512.htm).
The percentile coverage, covariates and patient wording still need agreement.
Do not label a value good/bad, infer diagnosis or suggest stimulation efficacy
from an unvalidated comparison. Personal longitudinal trends remain available.

## Reproduce The Table Audit

Pinned revision: `5889255748fe87838428f1cba25481018740f94e`.
[Feature table](https://github.com/ROC-HCI/finger-tapping-severity/blob/5889255748fe87838428f1cba25481018740f94e/fingertapping_features_severity_diagnosis_June13_2023.csv).
[Author grouping rule](https://github.com/ROC-HCI/finger-tapping-severity/blob/5889255748fe87838428f1cba25481018740f94e/model_training.py).
CSV SHA-256: `93d590875d535d9e134d093903d2b15138f06d105e34e5c954be114b188e20b6`.
Store downloaded participant-level data outside Git in appropriate storage.

```zsh
python3 tools/audit_tapping_reference.py /private/path/public-feature-table.csv
python3 -m unittest discover -s tools -p test_audit_tapping_reference.py -v
```

The audit reads only, verifies the pinned hash, reports aggregate counts and
refuses unknown labels/nonfinite control features. Five synthetic tests passed.
An initial draft over-validated unrelated PD metadata and rejected the NIH naming
variant; both were corrected before the successful pinned-data run. No normative
percentiles, patient values or clinical scores were calculated. No app source
changed, so app/unit/UI suites were not rerun for this research-only stage.
