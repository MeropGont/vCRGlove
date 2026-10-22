# ROC-HCI Tapping Feature Subset

Implemented 19 October 2026 after approval of the reference-method bridging task.
This is offline research software. It does not change camera capture, timers,
gap-aware app analysis, saved metrics, task navigation, exports inside the app,
or patient plots. Healthy-reference bands and clinical scores remain unimplemented.

## What Is Matched

The candidate is [Islam et al., npj Digital Medicine (2023)](https://doi.org/10.1038/s41746-023-00905-9).
Our existing angle geometry uses the same wrist/thumb-tip/index-tip definition.
The new tool separately reproduces selected **angle-processing and feature
definitions** from the [pinned author source](https://github.com/ROC-HCI/finger-tapping-severity/blob/5889255748fe87838428f1cba25481018740f94e/feature_extraction.py).
It does not reproduce MediaPipe landmark capture or the complete ML pipeline.

Method ID: `roc-hci-angle-feature-subset-v1`.

| Output | Definition |
| --- | --- |
| Period | Adjacent opening-peak frame differences multiplied by nominal frame duration |
| Mean rate | Mean of reciprocal periods, not reciprocal of mean period |
| Amplitude | Angle at each opening peak, not peak-to-peak excursion |
| Speed | Absolute adjacent-frame angle difference divided by nominal frame duration |
| Statistics | Mean, median, min, max, IQR and population SD for each of the above |
| Versions | Longest valid segment, then a separate first/last-opening-peak-trimmed segment |
| Peak count | Opening peaks in each selected segment, not a whole-session tap count |

These are 50 columns matching names in the released feature table. A separate
population-SD period CV is included as an explicitly labelled extension when at
least two periods exist; it is not a released reference-table column. No wrist
features, entropy, decrement model, freeze score or severity classifier is claimed.

The selected algorithm retains the author's cubic missing-frame interpolation,
sequential updates, longest-segment selection, peak height/spacing rules, closure
threshold below 10 degrees and first/last peak trimming. Comments in the original
peak routine do not fully match its executable code; this implementation follows
the pinned executable definitions. There is no additional low-pass smoothing of
valid angle frames in this subset.

## Important Gap And Timing Limits

The author's sequential interpolation can fill long missing runs. This is not
our app's gap-aware analyzer and must not silently replace it. Reports count
missing/interpolated frames, expose selected frame ranges, and warn about tracking
loss over 0.2 seconds. Cubic interpolation outside the physical angle range is
rejected, not clamped into a plausible result.

One stored value per processed camera frame is required, with null for missing
landmarks; zero degrees remains valid. The nominal clock follows the author's
duration/frame-count formula, here using recorded elapsed time and stored angle
frame count. That is not independent verification of video frame count or timing.
Timestamp gaps/irregularity over 10% of that clock (with a 2 ms floor), missing
elapsed time, or more than three nominal frames of uncovered boundary time are
rejected. These are engineering guards, not validated clinical quality thresholds.
No frames are silently inserted or time-shifted to make an export pass.

Flat, insufficient, open-only or numerically unsupported signals return an explicit
unavailable reason and null features. The CSV keeps its feature columns with blank
unavailable values. It never turns failure into a healthy zero.

No best-performing ten taps are selected. The author's segment rules are applied
to the supplied take, retaining its requested protocol in metadata. A 30 s app
instruction remains different from ten requested taps. All outputs therefore keep
`reference_comparison_eligible` false until capture/protocol/reference review is
complete, even when numerical parity succeeds.

## Run And Verify

Use a separate Python environment; nothing is installed into Xcode or the app:

```zsh
python3 -m venv --system-site-packages /tmp/vcr-roc-runtime
/tmp/vcr-roc-runtime/bin/python3 -m pip install -r tools/requirements-roc.txt
```

Obtain the pinned original `feature_extraction.py` from the linked author source
and keep it outside the repository. Its SHA-256 must be
`ebe91bfce1ef3da72b4d27168d6d969639c66d5d2dd7310378b1c70df6f2c9a6`.

```zsh
/tmp/vcr-roc-runtime/bin/python3 tools/verify_roc_tapping_features.py \
  /private/path/feature_extraction.py
/tmp/vcr-roc-runtime/bin/python3 tools/extract_roc_tapping_features.py \
  /private/path/sessions.json --author-source /private/path/feature_extraction.py \
  --output /private/path/new-research-review
/tmp/vcr-roc-runtime/bin/python3 -m unittest discover -s tools -p 'test_*.py' -v
```

JSON session arrays and JSONL are supported. Older trials without stored angles
are skipped, not reconstructed. Existing output directories and repository-local
outputs are refused. The tool reads only, checks source bytes before publishing,
and writes private owner-only JSON/CSV/PDF reports. No upload occurs. Temporary
directories are not backups; use approved storage for retained research records.

`features.json` includes original private trial/session IDs, method/runtime/source
hashes, segment and peak indices, data-quality evidence and per-trial oracle checks.
`features.csv` is the separate feature table. `review.pdf` is a readable summary.
These are not additions to the patient's app storage or normal app exports.

The verification oracle accepts only the pinned source hash and loads selected
definitions, not the original imports, video/ML pipeline or pickle inputs. Required
numerical imports are supplied explicitly, including `iqr`, missing from the
upstream import block. Adapted routines retain the author's MIT attribution in
`tools/licenses/ROC-HCI-MIT.txt`. Dependency versions are recorded; agreement under
this runtime is not proof of reproducing every value in the historic CSV.

## Evidence And Remaining Work

Fifteen synthetic cases span three rates, missing edges, short missing runs, long
gaps and changing amplitude. All 750 feature comparisons matched the selected
author routines exactly. Five supported real trials also matched all 50 selected
features exactly. One of six supplied stress-test recordings was unavailable
because cubic interpolation exceeded 180 degrees. This is an algorithm guard,
not evidence that the participant physically performed an impossible motion.

Thirty offline regression tests passed, including 15 new feature/edge-case tests
and the existing table audit and paired-channel tests. An initial periodic fixture
assumed exact 2 Hz despite frame-quantized peaks; it was replaced with a cycle
period of exactly 16 frames. The interpolation rejection fixture was corrected
to use a deterministic overshooting gap. Production thresholds were not relaxed
to make those tests pass. No app unit/UI suite or new physical recording was run.

The [initial independent video check](TAPPING_VIDEO_VALIDATION.md) on 21 October
found a movie/signal synchronization limit and missed author-derived peaks in an
edge-on view. This is development evidence, not completed accuracy validation.
Broader video/landmark validation, a protocol-matched comparison and control
identity clarification remain. The additional [2026 camera healthy cohort](https://www.nature.com/articles/s41531-026-01316-9)
and [Maremmani hand-task cohort](https://pmc.ncbi.nlm.nih.gov/articles/PMC9541466/)
are validation targets, not implemented thresholds. See the
[reference assessment](HEALTHY_REFERENCE_ASSESSMENT.md) for the healthy data plan.
