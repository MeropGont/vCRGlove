# Data Formats and Exports

Implementation reviewed 16 October 2026. This describes current files and manual exports, not an approved research-transfer policy or a verified backup service. Source models and serializers are linked below; there is no single global schema version.

## Files and Time Formats

All locations are relative to the iPhone app container.

| Data | Location | Format and timestamps |
| --- | --- | --- |
| Stimulation/app events | `Documents/vcr/logs/events.jsonl` | One JSON object per line; `ts` is ISO-8601 with fractional seconds |
| Journal | `Documents/vcr/journal/journal_entries.json` | JSON array; dates use Foundation's default numeric seconds since 2001-01-01 UTC, not Unix seconds |
| Movement sessions | `Documents/vcr/tasks/sessions.jsonl` | One session per line; dates use the JSON encoder's ISO-8601 strategy |
| Private camera recordings | `Application Support/vcr/tasks/videos/<trial UUID>.mov` | Silent movie linked by trial metadata |
| Generated movement exports | `Documents/vcr/tasks/exports/` | Separate JSON/CSV files generated on request |

Settings, completion counters, calibration and the dormant upload queue also use UserDefaults. They are not all included in measurement exports. Preserve time zones when analysing data: wall-clock recording times identify the event, while local calendar dates group it for the UI. Export filenames are not authoritative recording timestamps.

## Events

[EventStore.swift](../vCRGlove/EventStore.swift) writes `ts`, `type`, `tag`, `message` and optional `details` (string-to-string values). Writes are serialized. Events describe the app's actions/state and reported interruptions; they do not independently measure physical motor timing or delivered stimulation dose.

### Stimulation Configuration

`vcrStimulationProfile.v1` is one JSON-encoded Data value in UserDefaults, defined by [StimulationProfile.swift](../vCRGlove/StimulationProfile.swift). Fields are `version` (1), `leftAmplitude`, `rightAmplitude`, `frequency` (cycles/second), and `pattern` (`shuffled` or `simultaneous`). SDK amplitudes are not calibrated physical units. Pulse length remains 100 ms, with four slots per cycle. A missing profile retains previous defaults; an unreadable, invalid or unsupported profile blocks stimulation pending staff review.

The JSONL `stimulation_profile_saved` event includes the new profile and `previous_` values; `stimulation_started` includes the session snapshot, `position`, `effectiveAmplitude` and `durationSeconds`, also on resume/join. `finger_check_started`, `finger_check_cancelled`, `research_unlocked` and `research_locked` record relevant app actions. All parameter detail values are strings. These events do not identify/authenticate an experimenter or prove hardware delivery. A new glove/resume uses the same snapshot as the active session; locking controls leaves the saved profile unchanged. Existing free-text `app_event` records remain compatible. Measurement JSON/CSV exports do not contain this configuration or the stimulation log; the researcher full-data ZIP does.

## Journal

[JournalModels.swift](../vCRGlove/JournalModels.swift) and [JournalStore.swift](../vCRGlove/JournalStore.swift) define entries with a UUID, event `date`, `type`, optional answers and optional `createdAt`/`updatedAt`. Types are `dailyCheckIn`, `medication`, `symptom`, `note`, `stimulation`, and a reserved `pdq8` case. The reserved case does not mean a PDQ-8 questionnaire is available.

New two-question check-ins have `checkInVersion: 3`, mood and activity impact. Older check-in versions and medication/symptom fields remain readable; an edit does not manufacture missing historical timestamps or silently upgrade their version. Medication entries can include name, dose, event, motor state, factors and a note. Symptom episodes and notes remain separate records.

Journal edits preserve IDs, original creation times and unknown stored JSON fields. Writes are atomic. Unreadable storage or duplicate IDs prevent overwriting the journal; a failed save must leave the user's answers available for retry. Optional/absent answers are not equivalent to "none", "not at all" or zero.

## Movement Sessions and Trials

The contract is [MovementModels.swift](../vCRGlove/MovementModels.swift); persistence is [TaskSessionStore.swift](../vCRGlove/TaskSessionStore.swift).

| Level | Main fields |
| --- | --- |
| Session | `id`, `patientId`, `date`, `stimulationContext`, `trials` |
| Trial | `id`, `taskType`, `side`, `source`, `stopCondition`, `startedAt`, optional `startUptime`, `samples`, `metrics`, optional `medicationTiming`, `recordedDurationSeconds`, `video`, `measurementVersion`, `fingerTappingAngle`, `fingerTappingAngleMetrics`, `fingerTappingReferenceSegment` |
| Sample | `t` (seconds relative to trial start), `value` (task/source-specific signal) |
| Video reference | Relative `fileName`, `byteCount`, optional `timing`; no movie bytes in JSON |

Task codes `3.4`, `3.5`, `3.6` identify finger tapping, hand opening/closing and pronation/supination. They are reference identifiers, not assigned MDS-UPDRS ratings. Hands are `left`/`right`; sources are `camera`, `watchMotion`, `synthetic`. Never pool these as interchangeable measurements.

Camera signals are normalized landmark distances: thumb-to-index distance for tapping, and mean fingertip-to-palm-centre distance for opening/closing, divided by hand scale. They are not millimetres. Watch capture uses forearm-axis rotation rate in radians/second; physical orientation still needs validation. Sample times use a monotonic clock rebased to the recording start. Watch rebasing preserves sample spacing but does not establish zero transport delay or precise absolute cross-device synchronization. `recordedDurationSeconds`, when present, is elapsed recording time, distinct from the last detected sample time.

New trials optionally store `measurementVersion`: camera `camera-live-palm-aspect-v2-analysis-v3-local-excursions`, Watch `watch-rotation-rate-v1-analysis-v1`. Earlier live-palm camera recordings retain `camera-live-palm-aspect-v2-analysis-v1` or `camera-live-palm-aspect-v2-analysis-v2-gap-aware`. Synthetic/unversioned and historical trials may omit it. Camera v2 divides aspect-correct distances by the live frame's wrist-to-middle-MCP length; previous code could use a saved image-space scale. Do not rescale historical values or pool versions. Medication/video copies and JSON export retain the field. Metrics CSV appends `measurement_version` after the original 28 columns; blank means unversioned, not the current method. Raw-sample CSV remains unchanged and can join by trial ID. Calibration remains a positioning/readiness aid, not a physical length measurement.

### Context

- New stimulation choices: `preStim`, `postStim`, `noStimPlanned`. Historical `baseline` and `unspecified` remain readable; never relabel them as no stimulation today. These are reported categories, not verified dose/timing.
- Medication status: `takenAt`, `noneToday`, `unsure`; absence means unanswered/legacy. `takenAt` and `confirmedAt` are timestamps. Optional journal ID/name/dose retain their source meaning. Do not infer medication ON/OFF or intake from a reminder.
- Use `Trial.startedAt` for each recording's timestamp, rather than the encompassing session date.

### Auxiliary Finger-Tapping Angle

New camera finger-tapping trials optionally include `fingerTappingAngle`, separate
from the unchanged distance `samples`, `metrics` and `measurementVersion`.
The auxiliary object contains `measurementVersion`:
`vision-thumb-wrist-index-angle-aspect-v1`, `unit`: `degrees`, `timeReference`:
`seconds_since_trial_start`, and `samples`: objects with `t` and optional
`degrees`. Missing/null `degrees` means the processed frame had unavailable
landmarks/geometry, not zero movement. Zero degrees is a valid measured aperture.
An empty auxiliary array means capture was enabled but no in-window frames were
received. A missing auxiliary object means no angle channel was recorded, as on
older trials, Watch tasks and hand opening/closing.

The unsigned 2-D thumb-tip/wrist/index-tip angle uses the wrist as vertex and
corrects normalized x coordinates by the processed image width/height. It is
not a 3-D joint angle or a clinical score. It does not replace the distance
signal or feed patient plots, live rhythm, stopping rules or existing metrics.
Angles and available distance values from a frame use exactly the same relative
timestamp. Angle samples may exist without distance samples when palm-scale
landmarks are missing. Entirely dropped/unprocessed frames appear only as time
gaps; unavailable processed frames retain an entry. No interpolation is applied.

Medication/video copies, accepted saves, Retake replacement and video deletion
retain the auxiliary channel. JSON export includes it; the full-data ZIP retains
it inside raw `tasks/sessions.jsonl`. The separate angle CSV includes IDs,
task/side, `t_sec`, `angle_degrees`, `angle_valid`, `measurement_version`, `unit`
and `time_reference`. `angle_valid` means an angle was calculable, not that task
performance, hand identity or clinical interpretability was verified. Missing
angles have a blank value and `false`; zero has `0.0` and `true`.

Settings > Data offers the bilingual angle CSV action only when an auxiliary
recording exists. Existing raw-sample and metrics CSV columns are unchanged.
An enabled take with no received frames exports an angle header with no rows.
Historical distances cannot uniquely reconstruct angles; video reprocessing and
external healthy-reference comparisons remain separate stages. See the
[implementation stages and evidence](FINGER_TAPPING_ANGLE_AUDIT.md).

### Metrics and Missing Data

Results eligibility accepts timed takes with at least 10 seconds of continuous
tracking and known elapsed time (0.1-second frame-boundary tolerance); the planned
timer need not finish. Matching early-stopped takes contribute to the normal
daily median and trend line. Gap-aware camera values can qualify despite missing
tracking elsewhere; other methods retain their gap exclusion. This display rule
does not change saved metrics, elapsed time, task targets or export fields.

An optional local `movementTrendIdentityLinks` preference stores explicit
session-UUID-to-TEAM-ID display mappings with explicit trial-UUID sets for
confirmed earlier unassigned tests.
No mapping is created automatically. Original session/trial JSON and CSV keep
their saved IDs; the research archive includes the mapping as JSON-encoded Data
in `study-settings.plist`. Mappings apply only while the original session is
unassigned, never to other assigned identities or newly created session UUIDs.

Stored metrics are `cycleCount`, `frequencyHz`, `meanAmplitude`, `amplitudeDecrementSlope`, `rhythmCV`, `pauseCount`, `onsetLatencySec`, `qualityIndex`. The last is an unvalidated heuristic retained for compatibility and hidden from patient results. Rate is displayed as taps/repetitions per second; rhythm variability is interval CV multiplied by 100.

From 19 October 2026, new camera analysis splits samples when consecutive valid
timestamps are more than 0.2 seconds apart. This is a continuity tolerance, not a
clinical threshold; the separate two-second UI warning remains unchanged.
Smoothing and cycle detection restart in each segment with at least four samples.
Rate is the count of within-segment cycle intervals divided by their summed time;
rhythm and pauses use only those intervals. A visible stationary hand still
produces samples, so an observed pause is not removed as tracking loss. With gaps,
amplitudes use only event-to-event cycles; decrement pools within-segment
mean-normalized slopes, weighted by the number of amplitude comparisons. Neither
amplitude nor decrement bridges missing observations. Results require actual
within-segment evidence, not just cycles scattered across disconnected fragments.
Onset retains its existing first-observation-relative definition; initial unseen
movement cannot be inferred. No interpolation, saved-data migration or automatic
recalculation of older stored metrics is performed. Watch/synthetic analysis and the
auxiliary angle measurement definition are unchanged.

Camera analysis v3 also replaces fixed low/high signal levels with local-extremum
directional hysteresis. A rise of 20% of the segment's smoothed 5th-to-95th
percentile range records an event after a fall of that excursion. Each segment
starts unarmed, so an initial partial rise is not accepted as a cycle. The
existing 0.12-second minimum event spacing remains unchanged.
The excursion equals the earlier high-minus-low band width, but its anchor
follows the local extremum, so baseline drift need not hide a repetition.
Smoothing, gap boundaries, raw distances and auxiliary angles are unchanged;
amplitude and decrement are not normalized to a moving local range. The former
gap-aware detector remains available for v2 prerequisites. Results explicitly
project known live-palm camera v1/v2 raw signals through v3 for comparable trends;
current v3 results use their saved metrics. This transient projection is not
serialized and never changes a trial's stored version, metrics, raw channels or
JSON/CSV exports. Unknown or unversioned capture methods, Watch and synthetic
sources are not projected. Different or missing study IDs remain separate.

Local excursions are signal events, not verified complete clinical repetitions.
Motion below the excursion tolerance, landmark errors, drift/jumps and rapid
movement near the sampling limit can still affect counts. A long detected
interval is not proof of a physical pause or freezing. See the limited video
checks in [the validation record](FINGER_TAPPING_ANGLE_AUDIT.md).

An empty/short/gapped signal can still be saved. Stored numbers alone do not prove an analysable recording; apply the current display-validity checks and keep unavailable values separate from real zeros. These metrics do not establish normality, clinical severity or treatment effects; see [Results](MOVEMENT_RESULTS.md).

### Saving and Video Deletion

New camera videos on iOS 18.2+ can retain `video.timing`: version 1, method
`avcapture-first-buffer-pts-v1`, `firstFrameTrialTimeSeconds` and
`firstFrameMoviePTSSeconds`. Map a sample at `t` to movie PTS with
`t - firstFrameTrialTimeSeconds + firstFrameMoviePTSSeconds`. Signed offsets are
preserved; absent timing is not zero. Older recordings, older iOS callbacks and
failed timing inspection retain no inferred anchor. Sessions JSON and full-data
snapshots include it; existing CSV schemas stay unchanged. See
[movie/signal timing](MOVEMENT_VIDEO_TIMING.md) for the contract and pending
physical verification.

Each completed guided take is saved without requiring all six task/hand combinations. Re-saving the same session updates its line by UUID. Retake replaces the existing task/hand only after the new save succeeds; session files are therefore not an append-only audit trail of every discarded take.

Private movie copy and atomic session write are coordinated. Failed saves retain the temporary draft for retry; measurement-only saving is explicit. A crash between movie copy and metadata commit can leave an orphan movie, so automatic recovery and verified backup are still pending.

Deleting a video keeps the trial, samples and metrics, removes its reference and records a raw JSON `videoDeletedAt` tombstone. This prevents a stale session checkpoint restoring the reference. Copies already shared elsewhere are not removed. Deletion preserves unknown JSON fields and unrelated lines. Ordinary session upserts preserve unrelated lines and deletion tombstones, but do not guarantee retention of every unknown field in the rewritten session. Preserve raw originals for research migrations.

Movies request complete iOS file protection and are excluded from automatic backup. App removal/device loss can lose data. This is file deletion, not a forensic secure-wipe guarantee. See [Video storage](MOVEMENT_VIDEO_STORAGE.md).

## Export Coverage

[TaskSessionExporter.swift](../vCRGlove/TaskSessionExporter.swift) produces:

| Export | Contents | Does not contain |
| --- | --- | --- |
| Sessions JSON | Pretty-printed array of decoded sessions, trials, signals, metrics and video references | Video bytes, event log, journal, UserDefaults, unknown raw JSON fields/tombstones |
| Metrics CSV | One row per trial, IDs/context/timestamps, calculated metrics and medication fields | Raw samples, movie bytes, journal/events |
| Samples CSV | `session_id`, `trial_id`, `task`, `side`, `t_sec`, `value` | Metrics, medication details, movie bytes, journal/events |
| Finger-tapping angle CSV | One row per processed angle frame, explicit degrees/validity/version/time reference; joins by session/trial ID | Distance metrics, inferred clinical scores, healthy limits or movie bytes |
| Video sharing | Explicitly selected private movie files | A complete data manifest or automatic research upload |
| Researcher full-data ZIP | Raw journal, events/Watch handshake log, sessions JSONL, all retained task movies, allowlisted study settings and file manifest | Unsaved drafts, live recordings, previous generated exports, credentials or automatic upload |

The metrics CSV currently uses the last sample time for `duration_sec`, or zero for no samples. It does not use `recordedDurationSeconds`; do not treat that column as elapsed recording time when tracking was interrupted. JSON retains the elapsed field when available.

The trend display can estimate duration for older, unversioned camera duration tests whose elapsed field is absent and whose signal covers approximately the full requested test without a gap warning. This estimate is labelled in Results/history and never fills the missing JSON field or changes CSV values. Explicit short/invalid durations are not overridden; incompatible measurement methods and participant IDs remain separate. See [Results](MOVEMENT_RESULTS.md#comparability) for the exact display rules.

The separate movement JSON/CSV exports are generated from decoded records, not a byte-for-byte archival copy of storage. Malformed lines omitted during loading are not recovered into those exports. Verify expected session/trial counts, timestamps and video matches after copying, before deleting any originals.

### Researcher Full-Data ZIP

Unlock Study team, open Study setup & logs, then tap Share all recorded data. [FullDataExporter.swift](../vCRGlove/FullDataExporter.swift) prepares one ZIP and opens the system share sheet; the operator chooses the destination. No data is automatically sent or deleted. Export is unavailable during an active, paused or starting stimulation session to avoid competing with stimulation timing.

The ZIP's `vCRGlove-data` folder contains `README.txt`, `journal/journal_entries.json`, `logs/events.jsonl`, optional `logs/handshake.jsonl`, `tasks/sessions.jsonl`, `tasks/videos/`, `study-settings.plist` and `manifest.json`. Raw storage is copied without model decoding/re-encoding, preserving unknown fields, deletion tombstones and malformed historical lines. All retained UUID-named task movies are included, including orphaned files; bundled demonstrations and unaccepted temporary takes are not.

The settings property list includes patient/study metadata, the encoded stimulation profile, hand calibration, session completion preferences, app/reminder preferences and dormant pending upload data. Data-valued preferences appear as base64 in the XML plist; their original encoded contents are preserved. It is an explicit allowlist, not a dump of all UserDefaults or credentials. Missing settings are not fabricated.

Manifest format 1 records the UTC export interval, original time zone, app version, relative file paths, byte counts and SHA-256 checksums, excluding the manifest itself. Absent stores are listed rather than invented. Missing referenced movies are listed separately and prompt a warning before sharing. An unreadable file aborts preparation; originals remain unchanged. Store snapshots wait behind queued writes; they are sequential, not a globally atomic transaction. Unsaved or concurrently started recordings are not promised in that snapshot.

Video copying and ZIP/checksum work run off the main thread. Temporary share copies request complete file protection and backup exclusion, are removed after share dismissal/failure, and interrupted-export copies are cleared on next launch. Originals remain in their existing stores. File protection is not ZIP password encryption: the shared ZIP contains sensitive data and requires an approved destination. Sharing completion does not prove recipient receipt or a verified backup; backup confirmation, restore/recovery and consent-based transfer remain separate work.

## Offline Angle Comparison

### In-App Angle Summary

New camera tapping trials also save optional `fingerTappingAngleMetrics` with
`calculationVersion` (`vision-angle-timestamp-gap-aware-v1`), `intervalCount`,
`openingPeakCount`, `trackedSeconds`, and optional `meanOpeningAngleDegrees`,
`meanAbsoluteAngularSpeedDegreesPerSecond`, `meanRateHz`, `periodCV`.
Absent metric values mean unavailable, not zero. See the
[native calculation contract](NATIVE_TAPPING_ANGLES.md). JSON/JSONL and full-data
exports preserve the field; existing CSV schemas and distance metrics are
unchanged. Historical angle summaries are display-only, not a stored migration.

### First-Ten-Tap Comparison Window

New tapping trials can additionally save `fingerTappingReferenceSegment`:
`selectionVersion` (`vision-first-ten-consecutive-complete-taps-v1`),
`sourceAngleVersion`, `detectorVersion`, `completedTapCount` (10),
`firstSampleIndex`, `endSampleIndexExclusive` (zero-based half-open indices into
the full angle array), `startTrialTimeSeconds`, `endTrialTimeSeconds`, and
`openingPeakTimes` (eleven trial-relative seconds). See the
[selection contract](NATIVE_TAPPING_ANGLES.md#first-ten-complete-taps).
It identifies a comparison segment without trimming the saved 30-second trial.
Absent means unavailable/not recorded, not zero taps or a failed overall task.
Medication/video copies, JSON/JSONL and full-data exports retain it; existing
CSV schemas are unchanged. No legacy migration or healthy band is implied.

### Offline Research Tool

Research-only angle comparison is available through the
[offline review tool](TAPPING_ANGLE_REVIEW.md). It reads exported sessions without
writing app records, preserves stored metrics alongside current replay results,
and keeps reports outside Git. It does not infer missing legacy angles or provide
healthy ranges. Associated video file/byte checks are not independent accuracy
or synchronization validation.

## Upload Boundary

There is no configured backend at app launch. Explicit session Finish still calls [SessionUploader.swift](../vCRGlove/SessionUploader.swift); without configuration it queues encoded measurements locally in UserDefaults (`vcr.uploader.pending`). Per-take automatic checkpoints do not request upload. This prototype transfers neither video bytes nor journal/event files, and the bundled server does not yet preserve the complete medication/video contract.

Do not enable or flush that queue until endpoint security, consent, identity, deduplication and field completeness are reviewed. A successful HTTP response alone is not a verified backup. See [backend reference](../BACKEND_INTEGRATION.md).
