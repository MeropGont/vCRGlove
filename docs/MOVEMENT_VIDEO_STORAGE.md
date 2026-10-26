# Private Movement Videos

Implemented 8 October 2026. Physical-camera verification remains pending.

## Current Behaviour

- Camera tasks (finger tapping and hand opening/closing) can record a silent movie alongside the existing raw signal. Calibration, Watch motion and simulator tasks do not record patient video.
- Settings > Data has one participant-controlled **Save task videos** switch, on by default to preserve existing behaviour. Its persisted value is sampled at the start of each take in both recording flows. Off means no temporary movie or video-processing job is created; live preview, tracking, angles, measurements and automatic guided saving continue. It does not remove existing videos or cancel preparation of already accepted recordings. Re-enable for future takes; no research unlock is required. This storage preference is not research consent.
- The exported current-settings snapshot includes `saveMovementVideos` when explicitly set. `trial_started` events record `videoRequested` for real recording flows; this does not assert successful video creation. Older events lack that field. Trial schemas and historical data are unchanged.
- Preference checks and outstanding physical-camera checks: [video-storage choice checklist](../Testing/video_storage_preference_checklist.md).
- In the guided session, each completed measurement is saved locally before the user continues. Video preparation no longer blocks the next task: an app-owned serial queue masks the movie and attaches it to that saved take later. Save & Continue and Save & Finish reuse the measurement checkpoint rather than creating duplicates. Automatic saving never requests upload; explicit Finish retains the existing upload behavior.
- Retake keeps the saved take until its replacement is saved successfully. Replacing a take removes only the previous video for that task/hand, after the measurement write succeeds. Back during an unfinished recording still discards its temporary draft.
- Opening a video, Trends, or another tab preserves the current session page, including its summary. Relaunch loads recordings from disk; restoring the exact in-progress navigation page after process termination is not implemented.
- Saved videos can be reviewed in Settings > Data > Recorded videos, not from the session summary. Pending movies show a preparing status; they cannot be played or shared. Ready movies appear automatically. The Data page shows one folder row and the ready-video count instead of the whole video list; measurement exports remain on the Data page. Results also has a Data shortcut. Open a ready video normally; its player has Share and Delete actions. Playback does not export the file. Sharing opens the system share sheet only after an explicit tap. Shared copies leave the app's protection and should go only to approved study destinations.
- No Photos authorization, automatic Photos saving or binary video upload is performed. Optional patient-approved Photos export is a separate pending step.

## Face Masking (22 October 2026)

New physical-camera movies pass through `MovementFaceMasker` after capture stops
and acceptance/checkpointing, before playback or sharing is possible. Live hand
tracking, angle samples and movement metrics are unchanged. Capture finalization
returns a private unprocessed draft promptly; the store moves it to a new owned
temporary URL before the recording view clears its draft. It commits the
measurement first, then runs one utility-priority processing job at a time,
independently of task navigation. The single-task flow still requires acceptance;
the guided flow checkpoints automatically. The task preview says finishing, not
starting camera, while hardware stops.

Completed movies attach by session/trial ID to the latest on-disk session on the
serial I/O queue. Later tasks are preserved; a discarded/replaced take cannot be
resurrected. Stale flow checkpoints retain newly attached movies and respect
deletion markers. Failed processing leaves the measurement and shows video
unavailability in Data. The summary has no View recording action and points to
Settings > Data instead.

This is deferred processing inside the running app, not an unlimited iOS
background service. Keep the app open (any tab/task) until videos are ready. A
limited iOS background task permits brief app switching; expiration cancels the
active job and removes queued drafts. Force-quitting/termination does not resume
jobs: abandoned private drafts are removed at next startup, while committed
measurements remain. Processing statuses are in-memory, not a durable job log.
Disk-write failures remain failures, not a backup guarantee. Phone checks must
verify tracking/recording performance while the preceding video is processed.

The processor normalizes the movie orientation, checks upright and upside-down
face views in every decoded frame using Apple Vision, and overlays opaque dark
rectangles. Version 2 expands each region by 12% per edge (at least 12 pixels)
and clips it to the image. Spatial matching keeps one current region per face,
rather than accumulating a trail of previous rectangles. Duplicate detections
from the two orientations are combined.

During a detection gap, an on-device object tracker follows the last detected
face region. If tracking confidence is below 0.3, its last region is retained.
Fresh face detection must reconfirm active tracking within two seconds; this bounds
drift onto hands or background. Version 4 retains the last confirmed edge-face
region even after this limit (see below). The threshold is a tracking policy, not a
validated privacy confidence score. Multiple faces remain separate. Masks can
obscure a hand that overlaps a detected face; the
original measurement signal remains available, but the saved video cannot reveal
those covered pixels for later manual review.

Only the processed, silent movie reaches the normal acceptance flow. Frame
presentation timestamps are retained; the existing source-timestamp timing
metadata is reused. New processed references carry optional
`faceMaskingVersion: 7`; version 1 used 25% padding and a half-second rectangle
trail. Older references may omit the version; existing recordings are not changed.
This field records processing, not successful detection of every face.

Raw capture and processing drafts use a dedicated temporary directory requesting
complete file protection and backup exclusion. The raw draft is deleted when
processing succeeds, fails or is cancelled; partial output is removed on failure.
Interrupted drafts are cleared on the next app launch. A successful result is not
published if removing the original fails. Filesystem deletion failures cannot be
guaranteed away; the protected temporary workspace may remain until cleanup can
run. This is not forensic secure erasure. Existing saved/shared videos are not
processed retroactively.

Decode, detection, encoding and cancellation failures never fall back to saving
the original. The ordinary video-unavailable notice remains and measurement
autosaving continues without a movie. No cloud service, identity recognition or
new consent action is introduced. The factual Devices and app explanation is
updated in English and German; the legal notice is unchanged.

Face detection can miss profiles, partial or moving faces. Hair, clothing,
backgrounds and other identifiers remain. This reduces risk; it does not make
videos anonymous or replace consent, storage choices or institutional review.
Physical verification is required before relying on this for study recordings.
See [face-masking checks](../Testing/face_masking_checklist.md).

The supplied processed phone clip exposed a missed upside-down, cropped face at
the ending and unnecessarily large stepped masks. Local inspection found that
rotating the final frame alone still did not yield a face detection. A manually
seeded native tracking probe followed the visible region across three ending
frames on macOS. This isolates tracking only: the supplied movie already has
black masks, so it cannot validate the full new pipeline on its original pixels.
A fresh unmasked capture must pass through the current version on iPhone for that check.

Performance follow-up retains both orientation checks on every frame and the
same mask geometry/tracking policy. Each movie now reuses its two Vision requests
and shares the rendering CIContext with the image handlers. A failed tracking
seed is not recomputed from the identical source image until a new face detection
provides a new seed. Fully checked, unmasked frames bypass compositing only when
their original buffer is already upright and exactly matches the output size.
Rotated or masked frames still use the normal render path.

The `[VIDEO] Masking v7` console line reports total processing, detection and
tracking seconds plus frame/direct-buffer counts, without identity or file paths.
Six focused masking tests pass. A small macOS detector-only probe on ten sampled
processed-video frames returned identical boxes (0.46 s before, 0.43 s with
request/context reuse); it is not an iPhone latency or accuracy validation.
The newer phone export confirmed visible face parts before the first detection;
the user reported at least ten seconds of saving delay on that build. Version 3
looks ahead at most 1.25 seconds (90 frames maximum), stopping at the first face
detection, then tracks its regions backwards over the opening frames. Independent
previews have a longest side of at most 320 pixels; full-resolution detection
results are cached for the normal pass. Only this short prefix is decoded twice,
not the full movie. Frames retain their original timestamps. If no face is found
within this window, no opening mask is inferred. Tracking can still miss a moving
face; this is not guaranteed coverage. The earlier performance optimizations are
retained, but latency and opening coverage require a fresh phone recording.

### Version 4: Partial Faces At The Edge (23 October)

The new supplied export shows an exposed eye around 18-22 seconds and again near
the ending, after the earlier edge mask disappears. Native macOS Vision returned
no face for the exposed 18-second frame in any of four orientations. This supports
a cropped-face detection gap; the processed export cannot reproduce the original
phone detector's complete history.

When a confirmed face box lies within the greater of 3% of the frame dimension
or the existing 12% face margin from an edge, its region extends to that edge.
After two seconds without confirmation, object tracking stops as before, but this
fixed edge guard remains for the rest of the movie rather than disappearing.
Fresh matching detections replace it with the current compact region; a fresh
matching face away from the edge clears the guard. Interior faces still expire
after two seconds. This does not accumulate old large rectangles or add inference
passes; deferred preparation and the usual mask padding remain unchanged.

An empty edge can remain masked after the person leaves. A face moving outside
the retained region or never detected at all can still be missed. This is a
conservative coverage policy, not validated anonymization. Existing movies are
not changed; fresh iPhone capture is required to verify this adjustment.

### Version 5: Continuity And Appearance (23 October)

The next processed export showed lingering edge guards at several positions and
uncovered facial detail before the first mask. Opening look-ahead now stops at
the first detected face or eight seconds / 480 frames, whichever comes first.
Independent previews have a longest side of 160 pixels (at most about 47 MiB
of RGBA preview pixels at the cap, before framework overhead). Full-resolution
detections are reused by the encoding pass; no additional face-detection pass is
added. Only the bounded opening prefix is decoded twice. Backward tracking still
uses the two-second confirmation window and edge fallback; this is not guaranteed
coverage of every opening frame, particularly if the first detection is later.

When a new detection does not match a very recent track (at most 0.5 seconds),
the existing object tracker gets one high-confidence continuation opportunity
before creating another face track. Reassociation requires confidence at least
0.7, an area ratio between 0.5 and 2, and center displacement at most 0.75 of the
prior maximum dimension. Confirmed detections then update the associated guard.
These are conservative heuristics, not identity recognition or validated privacy
confidence scores. Independent faces stay separate; uncertain older edge guards
remain covered rather than being discarded by a no-face timeout. Some lingering
coverage therefore remains intentional. Tracking adds work only in these
reassociation cases; it is not another neural face detector.

Each current region expands immediately when needed and shrinks with a 0.10-second
time constant, resetting directly after a gap of at least 0.4 seconds. Smoothed
bounds always contain the current required region. The rendered mask is opaque
charcoal; rounded outer corners are added 4-12 pixels outside the protective
rectangle. No existing protective corner is rounded away, blurred or made
transparent. No old rectangle list is rendered as a trail.

Deferred video preparation, timing, retention, exports and existing files are
unchanged. Synthetic pixel/geometry and storage checks do not establish native
tracker accuracy or phone latency. A fresh capture and v5 timing line are needed
to verify the opening, fast movement, multi-person scenes and processing cost.
The 33 focused masking/storage tests passed. A renderer-only simulator probe
of 30 frames took 11.900 seconds for rectangular and 13.472 seconds for rounded
masks, including first-use setup. This shows extra rendering cost, not a measured
iPhone or full-pipeline slowdown; phone performance remains unverified.

### Version 6: Unified Mask Outlines (23 October)

The supplied follow-up shows a retained edge guard beside the current moving
mask, including a small gap around the sampled 11-second frame. This is not proof
that the protected region can safely be discarded in every recording.

Before rendering, overlapping or nearly touching protective rectangles can share
one rounded outline. A merge requires intersection after expanding each box by
12 pixels (a gap of at most 24 pixels), and its envelope must add no more than
25% area over that pair's exact union. These are per-merge limits, not a global
area bound. Every input rectangle remains fully contained in rendered coverage;
isolated guards are retained and widely separated regions are not joined. Face
tracks themselves are not merged or deleted by this display simplification.

Charcoal is slightly lighter (RGB 0.08, full opacity) and outer corner radii are
8-14 pixels, still entirely outside the protective rectangle. This reduces
stepped seams without cutting into coverage, adding a face detector or applying
blur/fades. Coalescing can reduce the number of rendered masks, at the cost of
covering a little more background. Timing, deferred preparation and saved files
are unchanged. A genuinely isolated uncertain rectangle can still linger; removing
it safely requires stronger motion/absence evidence, not a cosmetic timeout.

### Version 7: Hand-Focused Saved Videos (23 October)

User-approved change: saved camera movies now use one stable crop enclosing the
tracked hand across the recording. Live preview, guides, measurement/angle
calculations and original sample coordinates remain unchanged. Existing hand
observations provide the region: at least ten frames with a confident wrist and
six visible joints. The union is padded by 20% per axis (at least 4% of the frame),
clipped to the source, and rejected if it exceeds 70% of the frame area. These
are framing heuristics, not validated privacy confidence thresholds.

The upright normalized crop accounts for the movie/analysis mirroring difference
and rounds pixel boundaries outward to even dimensions for encoding. No new hand
detector runs. Face detection/tracking still operates on the full upright source;
only protective regions intersecting the hand crop are rendered. The output is
cropped and translated without changing sample timestamps. This removes masks
and identifying background outside the crop rather than retiring uncertain face
tracks. Faces entering the hand area can still be missed or remain masked; this
is not guaranteed face removal or anonymity.

No reliable hand region means no new video, not a full-frame fallback; the
measurement remains saved. Crop ownership follows the private draft and deferred
queue job, with `normalizedSourceCrop` stored in the video reference (requested
normalized bounds before outward pixel rounding). Older references decode with
no crop metadata. Existing movies are not reprocessed. All other private-storage,
failure, deletion and sharing behavior is unchanged.

Fresh iPhone checks are required for both tasks/hands, front-camera mirroring,
clipped fingertips, hand motion across the frame, face intrusion into the hand
area, no-hand recordings and video/measurement timing. Factual app-video copy is
updated outside the unchanged legal notice.

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
