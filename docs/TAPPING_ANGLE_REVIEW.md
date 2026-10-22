# Offline Tapping-Angle Review

Implemented 19 October 2026. Research tooling only; no patient-facing angle
metric, healthy band, UPDRS score or change to app recording/analysis.

## Run

Use a Python environment with ReportLab and Xcode command-line tools. The bundled
workspace Python includes ReportLab. Run from the repository root:

```zsh
python3 tools/review_tapping_angles.py /approved/path/sessions.json \
  --videos-dir /approved/path/videos \
  --output /private/path/new-angle-review
python3 -m unittest discover -s tools -p test_review_tapping_angles.py -v
```

Choose a new private output directory outside this repository, with an existing
parent. Existing directories are refused. The optional video directory is only
used to check canonical UUID filenames and byte counts; movies are never copied,
decoded or uploaded. JSON arrays and session-per-line JSONL are supported.
No network requests occur. Compiler temporary files are removed after each run.

## Outputs And Definitions

- `review.pdf`: one overview and one page per supported trial, including signal
  plots, current distance replay and experimental angle-derived features.
- `review.json`: source SHA-256, script/Swift/reference metadata hashes, thresholds,
  stored-versus-replayed metrics, event times, pairing results and private trial
  identities. Do not commit this file or treat it as anonymized.
- `features.csv`: per-trial angle coverage, aperture percentiles and exploratory
  raw angular velocity. No control population is inferred from repeated trials.

Supported input is camera task 3.4 with angle version
`vision-thumb-wrist-index-angle-aspect-v1`, degrees and seconds since trial start.
Unknown contracts, invalid identities or unordered/nonfinite samples fail rather
than silently mixing methods. Older tapping trials lacking angles are listed as
skipped. Zero degrees is valid; null is missing.

The Swift bridge compiles the actual `MovementModels.swift` and
`MovementAnalyzer.swift`. Its small UI/journal dependency stubs are unused by
measurement logic. Both channels use the same current `.camera` detector. Angle
results are experimental: using the distance detector on angle values does not
reproduce a published angle pipeline.

Frame pairing allows only 1 microsecond timestamp tolerance; it never interpolates
or searches for a time shift. Pearson correlation uses valid paired frames. Event
agreement is chronological one-to-one matching within 100 ms, not a statistical
accuracy measure. Repeated frames from one trial are not independent participants.

Plots and raw angular velocity break at explicit null frames or gaps over 0.2 s.
Raw velocity is adjacent angle difference divided by actual timestamp difference,
reported as absolute median/p95. It is unsmoothed, noise-sensitive and unvalidated.
The existing Swift detector instead retains its current 0.2 s continuity rule:
short null runs can be bridged after missing angles are omitted. This deliberate
difference is stated in the report. Single-point segments have no plotted line.
Tracked time sums continuous segment spans, not the full recording timer.

The tool refuses a changed source export before publishing, creates files with
owner-only permissions and does not overwrite earlier reports. These protections
are not institutional storage approval or encryption. Use approved storage and
retention practices; temporary report directories are not backups.

## External Reference Boundary

[Islam et al., npj Digital Medicine (2023)](https://doi.org/10.1038/s41746-023-00905-9)
provides the candidate wrist-vertex angle method. The
[author code](https://github.com/ROC-HCI/finger-tapping-severity/blob/5889255748fe87838428f1cba25481018740f94e/feature_extraction.py)
is pinned in `tools/tapping_reference_method.json` (MIT code licence). No author
implementation was copied or executed in that initial paired-channel stage.
A subsequent [separate ROC-HCI feature subset](ROC_TAPPING_FEATURES.md) is now
implemented with MIT attribution and pinned-source numerical verification.
Code licensing does not establish dataset
permission or suitability for patient reference feedback.

Important differences: Vision versus MediaPipe, task-side metadata versus verified
hand labels, float/aspect-correct atan2 versus integer-pixel acos, interpolation
and longest-segment selection, selected-peak trimming, custom peak rules and
nominal frame timing. Author angular amplitude uses opening-peak values; the app
reports peak-to-peak excursion. Do not compare these amplitudes as identical.

## Verification And Next Gate

Ten synthetic tests passed, including a compiled actual-analyzer integration test.
Initial six-trial engineering review found strong paired-channel correlation and
cycle-count differences of zero to three. Associated video filenames and byte
counts matched, but video timing offsets and actual landmark/cycle accuracy have
not been independently established. No new app tests were needed for tools-only
changes; prior app test results remain separate evidence.

Next: independently annotate discrepant clips, establish camera-view repeatability,
and assess external healthy cohort features, protocol and data-use permissions.
No patient reference bands until those validation gates and a separately approved
feedback design are satisfied.
