# Movement Scores And Patient Trends

Research reviewed 13 October 2026. No new clinical score has been implemented.

## Recommendation For Discussion

Combine metrics within one task recording into a task-specific, interpretable
estimate of clinician-rated hand-movement impairment. Keep finger tapping and
hand opening/closing separate for each hand; never sum tasks or hands. A task
model can be applied to either hand while retaining separate outputs. These tasks cannot assess all Parkinson
symptoms or replace the full MDS-UPDRS motor examination.

Heye et al. provides a direct example of a within-tapping composite of speed,
amplitude and rhythm. For reusable implementation, the strongest practical
benchmarks are Islam et al.'s public tapping feature pipeline and LightGBM model
and Zarrat Ehsan et al.'s newer, clinically grouped distance-based features.
Morinan et al.'s ordinal, task-specific approach is relevant for opening/closing.
This is an engineering recommendation, reflecting modality
fit, interpretability, evaluation design and available code. Neither approach is
already validated for vCRGlove, and there is no universally best formula.

## Primary Studies

### Heye et al., Journal of the Neurological Sciences, 2024

[Validation of computer vision technology for analyzing bradykinesia in outpatient clinic videos of people with Parkinson's disease](https://pubmed.ncbi.nlm.nih.gov/39476714/)

31 people with PD and 49 controls; three raters, with 20 paired ON/OFF videos.
The study combines finger-tapping speed, amplitude and rhythm into a composite
bradykinesia measure. Computer-vision bradykinesia correlated with MDS-UPDRS
ratings (Spearman R = 0.740). This directly matches the requested within-task
combination, not a sum across tasks/hands. It does not validate opening/closing
or our 30-second home recordings. Correlation is not interchangeable with
agreement or longitudinal responsiveness.

The accessible primary abstract confirms the composite but not its exact formula
and weights. Obtain full methods/code from the authors before reproducing it;
do not infer weights from the reported correlations.

### Islam et al., npj Digital Medicine, 2023

[Using AI to measure Parkinson's disease severity at home](https://pmc.ncbi.nlm.nih.gov/articles/PMC10444879/)

Webcam finger tapping from 250 participants (172 with PD, 78 controls).
Interpretable features cover speed, amplitude, rhythm and hesitations. A LightGBM
regressor predicts clinician-rated tapping severity. Leave-one-patient-out
evaluation gave mean absolute error 0.58 points on the 0-4 scale. Code and
extracted features/ratings are public, but raw videos are not.

Important limitation: performance varies with severity; 63% of reference-zero
recordings were classified as one. The average error is not a guarantee for an
individual patient or a different camera/protocol. This is our most practical
starting reference for the camera tapping task.

### Morinan et al., npj Parkinson's Disease, 2023

[Computer vision quantification of whole-body Parkinsonian bradykinesia using a large multi-site population](https://www.nature.com/articles/s41531-023-00454-8)

628 patients, 1,156 assessments, 10,823 ratings across five sites. Kinematic
features feed task-specific ordinal random forests. Predicted ratings for five
limb tasks, both sides, form a 0-40 bradykinesia composite. Composite agreement was
ICC 0.74; individual-item balanced accuracy was 45%. The methods describe
stratified 10-fold evaluation. Multi-site sampling is not the same as an
independent prospective external validation.

Relevant here for its task-specific combination of kinematic metrics, including
hand opening/closing. Its ten-item total is outside our agreed scope. The reported
ICC 0.74 is for that total, not evidence of equal accuracy for an individual hand
or task. Raw data are not openly available; model access/licensing
need investigation.

### Zarrat Ehsan et al., npj Parkinson's Disease, 2026

[Interpretable and granular video-based quantification of motor characteristics from the finger-tapping test](https://pubmed.ncbi.nlm.nih.gov/41794807/)

4,073 tapping videos from 446 people with PD. Separates hypokinesia, bradykinesia,
sequence effect and hesitation/halts into interpretable features and evaluates
clinical-rating prediction. The authors explicitly identify responsiveness to
treatment and progression as further work.

A useful current feature-design reference, not yet a proven longitudinal endpoint
or a highly cited older benchmark. Tapping findings cannot automatically be
transferred to opening/closing.

Its classifiers combine metrics into three severity groups (0-1, 2, 3-4), not
five individual scores. Nested patient-level evaluation gave 56.44% accuracy;
an independent 11-person dataset gave 59.09% for LightGBM. Those results do not
justify a clinical score in our app. Public author code is available at
[VideoBased-PD-Biomarkers](https://github.com/AI-for-Parkinson-Lab/VideoBased-PD-Biomarkers);
check component/model licenses. This is a promising interpretable feature
benchmark alongside Islam, not evidence that any one formula universally wins.

## Proposed Development Path

These are engineering/research proposals, not validated clinical rules:

1. Agree the target with the movement-disorders team: item-level 0-4 estimates
   or a continuous digital measure. Do not label either a clinical score until
   independently validated and appropriately approved.
2. Validate existing signal, repetition detection and calibration. Rate is not
   opening/closing velocity. Derivatives need timestamps, calibrated units,
   smoothing and explicit missing-frame handling.
3. Extract velocity, amplitude, rhythm, decrement and hesitation features. Select
   useful, non-redundant features rather than requiring every available metric.
   Do not
   give capture quality a symptom-severity weight or convert missing signal to
   zero/maximal severity.
4. Obtain paired app recordings and blinded clinician ratings, preferably from
   multiple raters. Our 30-second tasks and continuing demonstrations differ
   from clinical administration; assess fatigue and imitation effects.
5. Compare a simple ordinal model with boosted trees. Group all recordings from
   each patient in one split. Perform feature selection/tuning inside training
   folds, then evaluate separate patients and ideally another site.
6. Assess agreement, absolute error, severity-level calibration, test-retest
   reliability and sensitivity to rated changes. Correlation alone is not enough.
   Account for medication/stimulation timing, device, hand and severity.
7. Version models and preserve observations/context/raw signals. Combine metrics
   only within each task and hand; do not introduce a cross-task or bilateral
   total. Keep capture adequacy separate from motor impairment.

## Trends: Implemented 16 October 2026

Approved view: daily median points connected separately by stimulation context.
Date/context/medication filters act before aggregation. Each daily point should
show count/range and link to the original recordings in history.

Keep task, hand and capture method separate. Unknown stimulation stays separate
from known before/after/no-stimulation conditions. Medication timestamps cannot
establish medication ON/OFF state. Unrestricted medication filters can still mix
dose timings within a daily summary; show that clearly and allow a narrower
time-since-dose range for comparisons.

Connecting observations describes recorded change, not a treatment effect or
disease progression. Do not smooth across unavailable measurements or discard
slow/small movements as bad capture. Duration, capture gaps and calibration or
protocol differences need explicit handling before estimating a slope or
claiming clinically meaningful change.

The user approved implementation. One day in a context shows its value without
an invented trend or extrapolation. Protocol/version differences and incomplete
recordings are handled explicitly; see [implemented results](MOVEMENT_RESULTS.md).
Velocity estimation and clinical composites remain research, not implemented scores.
