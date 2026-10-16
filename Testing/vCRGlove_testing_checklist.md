# vCRGlove Testing Checklist

Use this checklist when testing the vCRGlove app on study iPhones with bHaptics TactGlove DK2 gloves. Record the phone model, iOS version, app commit/tag, glove IDs, glove battery levels, date/time, and tester initials for every test session.

Reviewed 15 October 2026. Use disposable non-patient data and approved bench/study procedures. Record each check as pass, fail or deferred with evidence; this checklist does not mean the checks have been performed. See the [development guide](../docs/DEVELOPMENT_GUIDE.md) for simulator coverage and the [release checklist](../docs/RELEASE_CHECKLIST.md) for distribution.

## Test Session Metadata

- Tester:
- Date:
- iPhone model:
- iOS version:
- App branch/tag/commit:
- Installed version/build and installation source (Xcode/TestFlight):
- Xcode/macOS (if testing locally):
- Watch model/watchOS and companion version, if tested:
- Left glove ID:
- Right glove ID:
- Starting left glove battery:
- Starting right glove battery:
- Notes:

## 1. App Launch and Navigation

1. Launch the app from a fresh closed state.
2. Confirm the patient tab order is vCR, Journal, Movement, Settings.
3. Open Settings.
4. Unlock Research Mode with the current research password.
5. Confirm there are still exactly four tabs, in the same order.
6. Open the existing vCR tab and expand Stimulation parameters.
7. Lock researcher controls in Settings and confirm the parameter panel disappears. Relaunch: editing stays locked, saved parameters remain.

Expected result: one vCR tab for patients and staff. The discreet Study team unlock entry is below Contact/Help. No old visibility preference can restore another tab.

## 2. Patient Glove Scanning and Pairing

1. Turn both gloves off.
2. Open the patient vCR tab.
3. Press Scan for Gloves.
4. Confirm both glove cards remain gray/disconnected.
5. Turn on only the left glove.
6. Press Scan for Gloves again.
7. Confirm only the left glove becomes ready.
8. Turn off the left glove and turn on only the right glove.
9. Press Scan for Gloves again.
10. Confirm only the right glove becomes ready.
11. Turn on both gloves.
12. Press Scan for Gloves.
13. Confirm both gloves become ready.

Expected result: no stale or nonexistent glove should appear as ready. Left and right status must never be mixed.

## 3. Patient Test Buzz Behavior

1. With one glove ready and no stimulation running, tap the glove icon.
2. Confirm the corresponding physical glove buzzes briefly.
3. Start a vCR session.
4. Tap the glove icon during stimulation.
5. Confirm no extra test buzz occurs during stimulation.

Expected result: test buzz uses that hand's saved amplitude and works only when the glove is ready and no session (including paused/startup) is in progress.

## 4. Patient vCR Start, Pause, Resume, and Stop

1. Connect at least one glove.
2. Press Start vCR.
3. Confirm stimulation starts on all ready gloves.
4. Confirm the timer, progress bar, and running status appear.
5. Press Pause.
6. Confirm stimulation pauses on all active gloves.
7. Press Resume.
8. Confirm stimulation resumes.
9. Hold the Stop control until it completes.
10. Confirm stimulation stops and the UI returns to ready state.

Expected result: start, pause, resume, and hold-to-stop are clear, responsive, and do not crash the app.

## 5. Adding a Second Glove During Stimulation

1. Turn on and connect only one glove.
2. Start vCR stimulation.
3. While stimulation continues, turn on the second glove.
4. Press Scan for Gloves if needed.
5. Confirm the second glove connects.
6. Confirm the second glove automatically joins stimulation with the remaining time.
7. Repeat while the session is paused:
   - Start with one glove.
   - Pause the session.
   - Connect the second glove.
   - Confirm the second glove joins in paused state.
   - Resume and confirm both gloves stimulate.

Expected result: adding a second glove must not interrupt the first glove.

## 6. Glove Disconnection During Stimulation

1. Start stimulation with both gloves.
2. Turn off or disconnect one glove.
3. Confirm stimulation continues on the remaining glove.
4. Turn the disconnected glove back on.
5. Confirm it can rejoin stimulation.
6. Repeat the test but disconnect both gloves.
7. Confirm the session is marked interrupted because no active gloves remain.

Expected result: one lost glove should not end the whole session; zero active gloves should interrupt the session and log the reason.

## 7. Full 4-Hour vCR Session Completion

1. Start with both gloves charged sufficiently.
2. Start the default 4-hour vCR session.
3. Keep the app open for the full session.
4. Avoid touching the phone except to confirm the app remains visible.
5. At session end, confirm stimulation stops automatically.
6. Confirm the patient sees a completion message.
7. Confirm the calendar/day status updates as expected.
8. Export or inspect logs and confirm the session start and completion were recorded.

Expected result: full 4-hour stimulation completes without stutter, crash, premature stop, or missing completion message.

## 8. Two-Session Daily Use Scenario

The 2 x 2 hour plan is available in Settings. Record the selected plan and use the approved test procedure; do not change clinical session durations for convenience.

1. Select 2 x 2 hours and run the first session.
2. Confirm the app does not show full-day completion after only the first 2-hour session.
3. Run the second 2-hour session.
4. Confirm completion appears only after both sessions are finished.

Expected result: daily completion should reflect the configured daily stimulation plan.

## 9. Background and Foreground Timing Compromise

1. Start stimulation with at least one glove.
2. Press the Home button or swipe to leave the app briefly.
3. Return after 2-5 seconds.
4. Confirm the app logs that timing may have been compromised.
5. Repeat with longer background durations:
   - 10 seconds
   - 30 seconds
   - 2 minutes
6. Try these background scenarios:
   - Open another app.
   - Lock the screen.
   - Receive a notification.
   - Open Control Center.
   - Answer or dismiss a call if safe to test.
7. Record whether stimulation continues, stutters, pauses, or stops.

Expected result: inactive transitions are logged; entering background also shows a timing warning and requests a finite grace period. Neither guarantees uninterrupted hardware timing. Document actual glove behaviour, warning text and timestamps separately for each scenario.

## 10. Stability and Crash Stress Testing

1. Rapidly switch between vCR, Journal, Movement and Settings tabs during no stimulation.
2. Repeat during active stimulation.
3. Rapidly start and stop scanning.
4. Connect and disconnect gloves repeatedly.
5. Unlock/lock researcher controls in Settings; the tab count and active stimulation must not change.
6. Open Journal while stimulation is running.
7. Add a daily check-in while stimulation is running.
8. Add medication, symptom, and note entries while stimulation is running.
9. Leave the app idle for at least 30 minutes with no stimulation.
10. Leave the app idle for at least 30 minutes during stimulation.

Expected result: no crashes, no UI freezes, no unexpected stimulation stop unless explicitly caused by disconnection/background constraints.

## 11. Research Mode Testing

1. Unlock Research Mode from Settings.
2. Open the existing vCR tab and expand Stimulation parameters. No log should appear on this page.
3. With the approved bench procedure, set distinct left/right amplitudes, cycle frequency and pattern; press Save. Merely editing must not affect saved values.
4. Lock controls and relaunch. Confirm editing starts locked. Unlock and verify saved values, without an extra tab.
5. Start with real gloves. Check each hand's startup check, idle buzz and active amplitude against the intended configuration and motor mapping. Do not infer delivery from the displayed percentage.
6. Confirm controls cannot save during startup, running or paused states. Locking controls must not alter stimulation.
7. Pause/resume, disconnect/reconnect one glove and add a second glove; all must retain the original session profile and remaining duration.
8. Hold Stop during the finger check. Confirm every motor stops and stimulation cannot restart a few seconds later. Disconnect a glove during that check and confirm a fresh Start is required.
9. Repeat Stop/Pause at different points in a cycle; no queued pulse may fire after stopping/pausing. Check timing on both gloves, including the 2.5 Hz boundary with 100 ms pulses.
10. Test both patterns under the approved protocol: shuffled motors 0-3 once per cycle; legacy simultaneous array on each of four slots per cycle. Verify physical finger mapping and delivered pulse durations with suitable hardware measurement.
11. Open Study setup & logs in Settings. Inspect/share the event log: saved profile changes include old/new values; start/resume/join records include effective per-hand amplitude, frequency, pattern and duration. The visible log must not flood with repetitive raw BLE snapshots.
12. Test invalid/corrupt configuration only in isolated fixtures: delivery must remain blocked until staff save a valid profile. Recheck 4-hour and 2+2-hour completion separately.

Expected result: saved staff configuration is consistently applied, cannot change mid-session, and is not reset by patient Start. Simulations are not evidence of clinical safety, hardware timing or secure authentication; the existing password remains a basic UI gate.

## 12. Journal and Daily Data

1. Open Journal.
2. Select today in the calendar.
3. Complete the mood/activity-impact check-in. Confirm answers are in severity order and saving shows today's check-in status.
4. Edit the check-in, then use its Medication/Log symptoms shortcuts. Filled answers must save before navigation; an empty shortcut must not create a check-in.
5. Add and edit a medication event. Non-usual doses reveal an optional note; changing the answer must not silently discard typed notes or imply a dose was taken.
6. Add and edit a symptom episode and a note using the direct Journal dashboard links.
7. Start and stop or complete a vCR session.
8. Return to Journal and confirm all entry types appear for the day.
9. Restart the app and confirm entries/edits persist without duplicates. Check a past day and future-date restrictions. Repeat in English/German and at the largest app text size; inspect symptom choices and all save buttons.
10. Copy the app's Documents data via an approved method and inspect `vcr/logs/events.jsonl` and `vcr/journal/journal_entries.json`. Preserve originals. Journal dates use Foundation's numeric reference-date encoding; see [Data formats](../docs/DATA_FORMATS.md).

Expected result: entered data and edits persist, shortcuts do not lose answers, and old entries retain their meaning. Reflection schedules, medication reminders and PDQ-8 are pending features, not acceptance requirements for the current build.

## 13. Battery and Low-Battery Behavior

1. Connect both gloves with high battery.
2. Confirm battery/ready status appears correctly if available.
3. Test with a low-battery glove when available.
4. Confirm low battery is visibly communicated.
5. Confirm stimulation is not started accidentally on a disconnected or empty-battery glove.

Expected result: low battery should be clear to the user and should not be confused with disconnection.

## 14. Data Review After Testing

After each test session:

1. Copy app files using the approved workflow. Share private videos separately from Settings > Data; movement JSON/CSV does not contain movie bytes.
2. Save logs together with the test metadata.
3. Note any timing compromise warnings.
4. Note any Bluetooth connection failures.
5. Note any crashes, including approximate time and preceding action.
6. Note whether the physical glove behavior matched the app UI.
7. Verify copied session/trial counts, recording times and video linkage before deleting any original. Separate movement exports omit journal/events and movie bytes; the researcher ZIP includes all retained app study data but does not verify recipient receipt or backup. See [Data formats](../docs/DATA_FORMATS.md#export-coverage).

### Full-device export from researcher settings

1. Unlock Study team and open Study setup & logs. Check Share all recorded data is visible in English/German, including large text, and absent from locked patient settings.
2. Export a known non-patient fixture containing journal, stimulation logs, movement samples, saved movies and study settings. The share sheet must offer one ZIP. Cancel once, then export again; no originals may change.
3. Extract the ZIP on the receiving computer. Verify all file sizes and SHA-256 values against `manifest.json`, movie playback, journal dates (seconds since 2001) and trial ISO-8601 timestamps. Check raw legacy fields and deletion markers remain intact.
4. Check empty data stores and old references to missing movies. Missing movies must produce a warning and a manifest list, not silently claim a complete video set. Never include passwords or bundled demonstration clips.
5. Confirm preparation is unavailable during starting, active and paused stimulation. Test a larger set of videos for storage-pressure/error handling and an unlocked physical phone for protected-file sharing.
6. Dismiss the share sheet and confirm temporary export copies are removed. Interrupt preparation/relaunch and confirm cleanup; saved original movies and measurements must remain. Receipt/backup validation is separate from the share-sheet action.

Recommended issue note format:

```text
Date/time:
Tester:
Phone/iOS:
App commit/tag:
Glove side and ID:
Steps to reproduce:
Expected behavior:
Observed behavior:
Logs/screenshots:
Severity:
```

## 15. Movement Recording and Results Smoke Test

1. Calibrate on the physical iPhone and confirm the hand-size result and concise positioning feedback. A calibration suggestion must not block recording.
2. Record finger tapping and hand opening/closing for each hand. Confirm task/side titles, correct silent demo, countdown, camera framing, accessible Stop/Skip controls and live rhythm. Demo playback must start with recording.
3. Stop immediately, then after a few seconds, and complete a full timed recording. Each case must leave the recording state and offer clear next actions, even with no analysable signal.
4. Briefly move the hand out of frame. Check guidance, signal gaps and the continuing 30-second clock. Missing data must not appear as fabricated zero movement.
5. Open a saved recording, return, change tabs and relaunch. Saved trials/movies must remain available without finishing every task in the set. An unfinished draft and navigation restoration are separate behaviours.
6. Retake one task/hand. The old saved take must remain until its replacement saves successfully; unrelated takes remain unchanged.
7. Check per-trial timestamps and the chosen stimulation/medication context. Unknown context must remain unknown. Confirm medication is not repeatedly asked on every task page.
8. In Results, switch task/hand, rate/size/rhythm and filters. On two or more comparable days, check daily-median lines separated by context. Repeat a test on one day: count/range must update, without creating extra longitudinal observations. Tap the day and open its recordings. Check the metric info button, More details and paginated history. No clinical score, normal range or treatment-effect claim is implied.
9. Verify exported measurement data against saved recordings. Review `duration_sec` versus elapsed recording duration when signal was missing, as documented in [Data formats](../docs/DATA_FORMATS.md).
10. Test Watch pronation/supination only on a supported physical pair. If unavailable, mark it deferred and verify that the error and Skip action remain reachable; do not infer Watch success from camera-task tests.

Expected result: completed takes survive navigation/relaunch, Stop never leaves the user stuck, and unavailable analysis does not discard a recording. Record hardware accuracy/timing observations separately from software checks.

### New Trend and Camera Checks (Physical Validation Pending)

- Record the same movement at two comfortable camera distances, keeping the same hand plane. Review raw normalized signal and size against video; the synthetic geometry test is not physical accuracy validation. Repeat with each hand, changed lighting and the normal vertical pose.
- Recalibrate and repeat. New size should not depend on the saved image-space calibration scale. Check camera angle, visible-finger changes and missing/occluded joints for artifacts; do not claim perspective invariance.
- Compare full, early-stop, tracking-gap and older unknown-duration records. Older unversioned camera duration tests with absent elapsed time may join a historical line only when finite ordered samples cover the full requested duration (end and span within the documented 0.5-second tolerance), without a gap warning. Confirm the estimated-duration label in the chart/day summary and history. Short/late-start/gapped signals and explicit short/invalid durations must stay separate; no record/export is rewritten.
- Review right-hand finger tapping across the older October test dates: when all dates/timings are selected, the comparable before-stimulation and after-stimulation historical segments should connect. The newer measurement method and newly assigned study ID must remain separate. This physical-device/export review remains pending even after software regression tests pass.
- With no line, verify the explanation matches the data: only one day, different study IDs/methods/protocols, unmatched stimulation timings, or incomplete capture. Check English/German and the largest supported text size; do not infer a motor-performance failure from a missing line.
- Check historical rate/rhythm lines separately from new methods; historical size remains in history with an older-scale label. Do not expect old and new values to join.
- Apply 7/30/90-day and reported medication-hour filters before aggregation. Verify selected-day counts against original trials, not session dates. Unknown medication/context must never mean no medication/stimulation.
- Review English/German layouts at standard and largest text sizes, VoiceOver day selection, legends and reachable history/filter controls. Test after midnight/time-zone changes and on a supported physical Watch pair when available.

## 16. Private Videos and Sharing Smoke Test

1. Record on the physical camera; verify silent, upright videos and correct task/hand linkage in Settings > Data.
2. Open a video, return and share explicitly to an approved test destination. Confirm no automatic Photos copy or Photos permission prompt appears.
3. Select multiple videos using long press/Select, then test Share and cancel Delete. Cancellation must leave all selected files unchanged.
4. Confirm deletion using disposable clips only. The selected videos disappear while their movement samples, metrics and context remain. Other videos are unaffected.
5. Relaunch and confirm a deleted reference does not reappear. A previously shared copy remains outside the app's deletion control.
6. Check low-storage/write failures and locked/background behaviour using a controlled test setup. Do not delete live data or fill a study phone to force failure.

Expected result: sharing/deletion is explicit, failure notices preserve retry options, and measurement retention is independent of video retention. Physical file protection, long-term storage, recovery and verified backup require separate evidence.

## 17. Study Information and App Privacy

1. Confirm the primary Settings order: Profile, General, Instructions, vCR Settings, Reminders, Data, Information about the study. General contains language and text size; neither the old Profile text-size selector nor the globe shortcut remains. Change every text size and language, then relaunch and verify the choices are retained. The old Privacy & Data entry must be absent. Visit each Info topic; Contact must be last. There must be no consent switch, permission prompt or upload action.
2. Repeat in English/German and at the largest app text size. Switching language in General must keep that page and the Settings tab open, translate the page immediately and preserve Back navigation. Profile must show the study ID without avatar placeholders or icon-selection wording. Read the full privacy notice through its version footer; text must wrap and remain scrollable above the tab bar.
3. Compare the retained German privacy text with the current Word source identified in [Study information](../docs/STUDY_INFORMATION.md). Only the explicitly approved lab-video paragraph is omitted; all rights, exceptions, legal contacts and definitions remain.
4. Open Contact directly. Confirm existing phone/email links and the W36 institutional address, without a troubleshooting picker, conditional help introduction or Still Need Help? heading. Personal names must not appear on general study/contact pages; legal privacy contacts retain their names. Verify the separate troubleshooting route still works.
5. Open Devices and app and verify that all relocated data/video text matches actual local capture, backup exclusion, sharing and deletion behaviour. Reading the page must not change recording preferences or count as consent.
6. Obtain institutional review of the adapted notice and English legal translation before patient deployment. App-video consent coverage, opt-out and withdrawal handling remain separate pending work.

Expected result: concise study guidance and complete retained legal wording are available offline in both languages. The Info section does not replace study consent or implement future privacy controls.
