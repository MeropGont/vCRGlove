# Data Formats and Exports

Implementation reviewed 15 October 2026. This describes current files and manual exports, not an approved research-transfer policy or a verified backup service. Source models and serializers are linked below; there is no single global schema version.

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
| Trial | `id`, `taskType`, `side`, `source`, `stopCondition`, `startedAt`, optional `startUptime`, `samples`, `metrics`, optional `medicationTiming`, `recordedDurationSeconds`, `video` |
| Sample | `t` (seconds relative to trial start), `value` (task/source-specific signal) |
| Video reference | Relative `fileName` and `byteCount`; no movie bytes in JSON |

Task codes `3.4`, `3.5`, `3.6` identify finger tapping, hand opening/closing and pronation/supination. They are reference identifiers, not assigned MDS-UPDRS ratings. Hands are `left`/`right`; sources are `camera`, `watchMotion`, `synthetic`. Never pool these as interchangeable measurements.

Camera signals are normalized landmark distances: thumb-to-index distance for tapping, and mean fingertip-to-palm-centre distance for opening/closing, divided by hand scale. They are not millimetres. Watch capture uses forearm-axis rotation rate in radians/second; physical orientation still needs validation. Sample times use a monotonic clock rebased to the recording start. Watch rebasing preserves sample spacing but does not establish zero transport delay or precise absolute cross-device synchronization. `recordedDurationSeconds`, when present, is elapsed recording time, distinct from the last detected sample time.

New trials optionally store `measurementVersion`: camera `camera-live-palm-aspect-v2-analysis-v1`, Watch `watch-rotation-rate-v1-analysis-v1`. Synthetic/unversioned and historical trials may omit it. Camera v2 divides aspect-correct distances by the live frame's wrist-to-middle-MCP length; previous code could use a saved image-space scale. Do not rescale historical values or pool versions. Medication/video copies and JSON export retain the field. Metrics CSV appends `measurement_version` after the original 28 columns; blank means unversioned, not the current method. Raw-sample CSV remains unchanged and can join by trial ID. Calibration remains a positioning/readiness aid, not a physical length measurement.

### Context

- New stimulation choices: `preStim`, `postStim`, `noStimPlanned`. Historical `baseline` and `unspecified` remain readable; never relabel them as no stimulation today. These are reported categories, not verified dose/timing.
- Medication status: `takenAt`, `noneToday`, `unsure`; absence means unanswered/legacy. `takenAt` and `confirmedAt` are timestamps. Optional journal ID/name/dose retain their source meaning. Do not infer medication ON/OFF or intake from a reminder.
- Use `Trial.startedAt` for each recording's timestamp, rather than the encompassing session date.

### Metrics and Missing Data

Stored metrics are `cycleCount`, `frequencyHz`, `meanAmplitude`, `amplitudeDecrementSlope`, `rhythmCV`, `pauseCount`, `onsetLatencySec`, `qualityIndex`. The last is an unvalidated heuristic retained for compatibility and hidden from patient results. Rate is displayed as taps/repetitions per second; rhythm variability is interval CV multiplied by 100.

An empty/short/gapped signal can still be saved. Stored numbers alone do not prove an analysable recording; apply the current display-validity checks and keep unavailable values separate from real zeros. Do not interpret these metrics as normal ranges, clinical severity scores or treatment effects. See [Results](MOVEMENT_RESULTS.md).

### Saving and Video Deletion

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
| Video sharing | Explicitly selected private movie files | A complete data manifest or automatic research upload |
| Researcher full-data ZIP | Raw journal, events/Watch handshake log, sessions JSONL, all retained task movies, allowlisted study settings and file manifest | Unsaved drafts, live recordings, previous generated exports, credentials or automatic upload |

The metrics CSV currently uses the last sample time for `duration_sec`, or zero for no samples. It does not use `recordedDurationSeconds`; do not treat that column as elapsed recording time when tracking was interrupted. JSON retains the elapsed field when available.

The trend display can estimate duration for older, unversioned camera duration tests whose elapsed field is absent and whose signal covers approximately the full requested test without a gap warning. This estimate is labelled in Results/history and never fills the missing JSON field or changes CSV values. Explicit short/invalid durations are not overridden; measurement versions and participant IDs remain separate. See [Results](MOVEMENT_RESULTS.md#comparability) for the exact display rules.

The separate movement JSON/CSV exports are generated from decoded records, not a byte-for-byte archival copy of storage. Malformed lines omitted during loading are not recovered into those exports. Verify expected session/trial counts, timestamps and video matches after copying, before deleting any originals.

### Researcher Full-Data ZIP

Unlock Study team, open Study setup & logs, then tap Share all recorded data. [FullDataExporter.swift](../vCRGlove/FullDataExporter.swift) prepares one ZIP and opens the system share sheet; the operator chooses the destination. No data is automatically sent or deleted. Export is unavailable during an active, paused or starting stimulation session to avoid competing with stimulation timing.

The ZIP's `vCRGlove-data` folder contains `README.txt`, `journal/journal_entries.json`, `logs/events.jsonl`, optional `logs/handshake.jsonl`, `tasks/sessions.jsonl`, `tasks/videos/`, `study-settings.plist` and `manifest.json`. Raw storage is copied without model decoding/re-encoding, preserving unknown fields, deletion tombstones and malformed historical lines. All retained UUID-named task movies are included, including orphaned files; bundled demonstrations and unaccepted temporary takes are not.

The settings property list includes patient/study metadata, the encoded stimulation profile, hand calibration, session completion preferences, app/reminder preferences and dormant pending upload data. Data-valued preferences appear as base64 in the XML plist; their original encoded contents are preserved. It is an explicit allowlist, not a dump of all UserDefaults or credentials. Missing settings are not fabricated.

Manifest format 1 records the UTC export interval, original time zone, app version, relative file paths, byte counts and SHA-256 checksums, excluding the manifest itself. Absent stores are listed rather than invented. Missing referenced movies are listed separately and prompt a warning before sharing. An unreadable file aborts preparation; originals remain unchanged. Store snapshots wait behind queued writes; they are sequential, not a globally atomic transaction. Unsaved or concurrently started recordings are not promised in that snapshot.

Video copying and ZIP/checksum work run off the main thread. Temporary share copies request complete file protection and backup exclusion, are removed after share dismissal/failure, and interrupted-export copies are cleared on next launch. Originals remain in their existing stores. File protection is not ZIP password encryption: the shared ZIP contains sensitive data and requires an approved destination. Sharing completion does not prove recipient receipt or a verified backup; backup confirmation, restore/recovery and consent-based transfer remain separate work.

## Upload Boundary

There is no configured backend at app launch. Explicit session Finish still calls [SessionUploader.swift](../vCRGlove/SessionUploader.swift); without configuration it queues encoded measurements locally in UserDefaults (`vcr.uploader.pending`). Per-take automatic checkpoints do not request upload. This prototype transfers neither video bytes nor journal/event files, and the bundled server does not yet preserve the complete medication/video contract.

Do not enable or flush that queue until endpoint security, consent, identity, deduplication and field completeness are reviewed. A successful HTTP response alone is not a verified backup. See [backend reference](../BACKEND_INTEGRATION.md).
