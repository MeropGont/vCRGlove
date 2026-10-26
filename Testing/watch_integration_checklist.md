# Watch Integration Checks

## Software Checks

26 October 2026: Watch simulator build and unsigned physical-device architecture
build passed using this Mac's Xcode 26.5. The final iPhone simulator run passed
all 37 tests across `WatchStreamReliabilityTests`, `TrialRecorderTests` and
`TaskSessionExporterTests`. Plist/catalog validation and `git diff --check` passed.
The initial test build required a Swift Testing macro syntax correction; the
final source passed. No Xcode 27, physical Watch or paired-device validation is
claimed. Final result: `/tmp/vcr-watch-final-20261026.xcresult`.

- Shared wire protocol: wrong trial/version, legacy packets, empty/malformed
  arrays, non-finite values, duplicate/out-of-order sequences and timestamps.
- Command ordering: cancelled start, duplicate start, busy stream and late Stop
  from an earlier recording.
- Mock capture: valid-sample readiness, one completion, startup deadline, Stop
  before data, restart/late callbacks, stop during a batch, relative spacing and
  receipt anchoring. These are in-memory tests, not Watch Connectivity delivery.
- Existing recorder deadline/empty-feed and local save/export regression tests.
- Watch build and generated plist: `WKBackgroundModes` is an array containing
  `self-care`; companion bundle identifier remains the iPhone app identifier.

## Physical Checks: Not Yet Verified

Use matching phone and Watch builds. Do not uninstall either app merely to fix
pairing; export important test data before any destructive troubleshooting.

1. On the Air, verify Xcode signing, trusted paired iPhone, Developer Mode and
   successful installation of the Watch app. Record the exact OS/Xcode versions.
2. Open the Watch app while the phone is on the task instructions. Confirm the
   ready state and Start update without navigating away. Start one task; confirm
   countdown begins only after motion arrives and no startup wait is indefinite.
3. Complete 30 seconds. Confirm both apps stop and the trial is saved locally
   with the intended participant, task, hand, duration, medication and timestamps.
4. Repeat for each wrist, following the instruction to move the Watch to the
   tested arm. Inspect raw rotation trace, sign, axis and cycle count against
   observed movements; no accuracy claim follows from a successful connection.
5. Stop early and rapidly return/restart. Confirm no orphaned stream, old samples,
   duplicate trial or accidental countdown from a cancelled attempt.
6. Lower the wrist/dim the display; then separately press the crown/leave the
   Watch app. Verify supported frontmost behaviour and visible missing-signal
   state if streaming ends. Self-care is not unrestricted background runtime.
7. Disconnect during startup and mid-recording, then reconnect. Confirm bounded
   startup, the phone's duration deadline and no samples assigned to another trial.
   Lost live data are not recoverable in this stage. Verify the orphan-stop limit
   and that a delayed queued Stop does not stop a new stream.
8. Attempt manual Record/Stream controls during phone control: neither may
   override the stream. Confirm ordinary standalone diagnostic recording still
   starts/stops; its Send/import workflow remains outside this stage.
9. Export the session and sample CSV, then relaunch the phone app. Check stored
   trial identity and sample spacing/coverage; a saved trial is not proof of a
   complete or scientifically usable recording.

## Deferred

Durable Watch-side rotation recording/recovery, final-batch reconciliation,
Watch-specific gap-aware analysis, precise cross-device time synchronisation,
sensor-axis validation and the diagnostic CSV import path remain separate work.
