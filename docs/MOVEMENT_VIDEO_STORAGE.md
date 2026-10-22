# Private Movement Videos

Implemented 8 October 2026. Physical-camera verification remains pending.

## Current Behaviour

- Camera tasks (finger tapping and hand opening/closing) record a silent movie alongside the existing raw signal. Calibration, Watch motion and simulator tasks do not record patient video.
- In the guided session, each completed take is saved locally with its movie before the user continues. Save & Continue and Save & Finish reuse that checkpoint rather than creating duplicates. Automatic saving never requests upload; explicit Finish retains the existing upload behavior.
- Retake keeps the saved take until its replacement is saved successfully. Replacing a take removes only the previous video for that task/hand, after the measurement write succeeds. Back during an unfinished recording still discards its temporary draft.
- Opening a video, Trends, or another tab preserves the current session page, including its summary. Relaunch loads recordings from disk; restoring the exact in-progress navigation page after process termination is not implemented.
- Saved videos can be reviewed from the session summary or in Settings > Data > Recorded videos. The Data page shows one folder row and the video count instead of the whole video list; measurement exports remain on the Data page. Results also has a Data shortcut. Open a video normally; its player has Share and Delete actions. Playback does not export the file. Sharing opens the system share sheet only after an explicit tap. Shared copies leave the app's protection and should go only to approved study destinations.
- No Photos authorization, automatic Photos saving or binary video upload is performed. Optional patient-approved Photos export is a separate pending step.

## Storage And Failures

Manual deletion added 13 October 2026. Long-press a video and choose Select videos,
or use the Select toolbar action, then select any number of videos. Selection
reveals Share, Delete and Done actions; there is no fixed last-three shortcut.
Batch sharing passes validated, non-empty private file URLs to the native share
sheet without generating extra archive copies. Supported destinations depend on
the installed sharing extensions. A ZIP package with data/manifest remains future
export work, not a requirement for native multiple-video sharing.

Deletion requires confirmation, whether from playback or multi-selection. Only
selected private files are removed; measurements, raw
samples, recording times and medication/stimulation context remain. Copies already
shared to Photos, Files or another recipient are outside this operation. The app
cannot revoke arbitrary recipient copies. Future optional Photos export would
need explicit authorization and retained asset identifiers before a separate
Photos deletion action could be offered; it must not promise deletion everywhere.
Apple's normal Photos deletion keeps items in Recently Deleted for up to 30 days;
patients can separately remove them there. See [Apple's deletion guidance](https://support.apple.com/en-ie/104967)
and [PhotoKit deletion requests](https://developer.apple.com/documentation/photos/phassetchangerequest/deleteassets(_:)).

Deletion is serialized with session saving. A `videoDeletedAt` marker is kept in
the JSONL trial object so an older in-memory session checkpoint cannot reintroduce
its video reference. Existing model decoding ignores that optional metadata.
New retakes use new UUIDs and can save a new movie normally. Selected missing
files allow metadata cleanup; unsafe references and file errors remain failures.
Unknown JSON fields and unrelated lines are preserved by the deletion operation.

File removal precedes atomic metadata cleanup. If metadata writing fails after
removal, the video remains removed and the UI asks the user to retry cleanup.
Partial file failures retain their references and are reported, not silently
treated as success. This removes in-app files, not a forensic secure-wipe guarantee.

Videos live in Application Support/vcr/tasks/videos, outside Documents and Files sharing. Filenames contain only the trial UUID. Trial JSONL includes an optional relative video reference and byte count; existing recordings without that field still load. Task, hand, recording time, stimulation context and medication remain linked through the trial record, not embedded identifying movie metadata.

The Recorded videos folder screen is UI organisation only. It does not move,
compress or delete existing files and does not reduce their storage size.
Long-press selection and batch share/delete remain inside this screen.

New iOS 18.2+ camera recordings also retain optional
[movie/signal timing metadata](MOVEMENT_VIDEO_TIMING.md) in that reference. It
maps sample times to movie presentation times without estimating callback delay.
Older recordings and unavailable timing remain readable without an inferred
offset. Removing the video removes its reference and timing together.

The app copies the movie first, then atomically writes the accepted session JSONL. If that fails, the new private copy is removed and the temporary clip remains available for retry. The result screen stays open. Save without video is an explicit fallback, not a silent omission. A camera movie failure still allows the raw measurement to be saved and shows a concise notice.

Video files request complete iOS Data Protection and are excluded from automatic device backup pending an institute-approved backup policy. This is local storage, not backup. Removing the app, wiping app data or losing the phone can lose videos. Offloading and reinstall behaviour must be checked on disposable test data before relying on it.

Existing JSON/CSV exports contain measurement data, not movie bytes. Verified video-plus-data export, retention limits, crash-orphan recovery and backup status remain DATA-002/DATA-003 work. A process termination between movie copy and JSONL commit can leave an unreferenced private movie; automatic reconciliation is not implemented here.

## Verification

Automated tests cover backward-compatible decoding, ID linkage, replacement isolation, failed JSON/disk writes, retry, missing/empty video, duplicate-file protection, draft cleanup and silent-movie playback. Batch-sharing tests reject missing files, deduplicate selections and check that no extra copies appear. Simulator UI tests exercise bilingual save/playback, relaunch, Retake and explicit measurement-only fallback using generated non-patient movies, plus long-press selection, batch sharing and confirmed/cancelled deletion.

On iPhone, record both camera tasks and hands. Check the automatic-save notice, open View recording, return to the summary, relaunch and reopen from Movement Export. Verify Retake retains the previous saved take until its replacement succeeds, the 30-second timer and hand-loss guidance remain unchanged, no Photos prompt appears, and clips are upright. Test low storage, background interruption and locked-device protection before wider patient testing. Simulator checks do not validate the physical camera or hardware Data Protection.
