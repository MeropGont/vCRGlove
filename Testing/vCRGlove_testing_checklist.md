# vCRGlove Testing Checklist

Use this checklist when testing the vCRGlove app on study iPhones with bHaptics TactGlove DK2 gloves. Record the phone model, iOS version, app commit/tag, glove IDs, glove battery levels, date/time, and tester initials for every test session.

## Test Session Metadata

- Tester:
- Date:
- iPhone model:
- iOS version:
- App branch/tag/commit:
- Left glove ID:
- Right glove ID:
- Starting left glove battery:
- Starting right glove battery:
- Notes:

## 1. App Launch and Navigation

1. Launch the app from a fresh closed state.
2. Confirm the visible patient tabs are:
   - vCR
   - Journal
   - Settings
3. Open Settings.
4. Unlock Research Mode with the current research password.
5. Enable the Research tab.
6. Confirm the Research tab appears and opens without delay or crash.
7. Disable the Research tab again and confirm it disappears.

Expected result: app launches cleanly, Settings works, and Research visibility can be toggled only after unlock.

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

Expected result: test buzz works only when the glove is ready and stimulation is not running.

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

This is a planned workflow test for the future 2 x 2 hour option.

1. Run a 2-hour session if/when the option is available.
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

Expected result: any background exposure during active stimulation is logged and shown as a warning. Timing irregularity must be documented.

## 10. Stability and Crash Stress Testing

1. Rapidly switch between vCR, Journal, Settings, and Research tabs during no stimulation.
2. Repeat during active stimulation.
3. Rapidly start and stop scanning.
4. Connect and disconnect gloves repeatedly.
5. Toggle Research tab visibility in Settings.
6. Open Journal while stimulation is running.
7. Add a daily check-in while stimulation is running.
8. Add medication, symptom, and note entries while stimulation is running.
9. Leave the app idle for at least 30 minutes with no stimulation.
10. Leave the app idle for at least 30 minutes during stimulation.

Expected result: no crashes, no UI freezes, no unexpected stimulation stop unless explicitly caused by disconnection/background constraints.

## 11. Research Mode Testing

1. Unlock Research Mode from Settings.
2. Open Research tab.
3. Confirm scan, glove cards, disconnect/reconnect, stimulation parameters, and logs are visible.
4. Use Refresh Scan without clearing history.
5. Use Clear History & Fresh Scan.
6. Confirm each glove can disconnect and reconnect separately.
7. Change manual stimulation parameters.
8. Start stimulation in manual mode.
9. Stop stimulation.
10. Enable vCR preset and confirm manual controls are disabled or clearly marked.
11. Start stimulation in vCR preset mode.
12. Confirm the visible log shows useful events but does not flood with repetitive raw Bluetooth messages.

Expected result: Research mode should be clear enough for experimenters and should not interfere with patient-mode behavior.

## 12. Journal and Daily Data

1. Open Journal.
2. Select today in the calendar.
3. Add a daily check-in.
4. Add a medication event.
5. Add a symptom episode.
6. Add a note.
7. Start and stop or complete a vCR session.
8. Return to Journal and confirm all entry types appear for the day.
9. Restart the app and confirm entries persist.
10. Copy the app data from the phone and inspect:
    - `vcr/logs/events.jsonl`
    - `vcr/journal/journal_entries.json`

Expected result: all entries are saved, readable, timestamped, and recoverable from the phone.

## 13. Battery and Low-Battery Behavior

1. Connect both gloves with high battery.
2. Confirm battery/ready status appears correctly if available.
3. Test with a low-battery glove when available.
4. Confirm low battery is visibly communicated.
5. Confirm stimulation is not started accidentally on a disconnected or empty-battery glove.

Expected result: low battery should be clear to the user and should not be confused with disconnection.

## 14. Data Review After Testing

After each test session:

1. Copy app files from the phone.
2. Save logs together with the test metadata.
3. Note any timing compromise warnings.
4. Note any Bluetooth connection failures.
5. Note any crashes, including approximate time and preceding action.
6. Note whether the physical glove behavior matched the app UI.

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

