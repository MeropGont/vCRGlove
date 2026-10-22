# Development Guide

Implementation reviewed 15 October 2026. See the [documentation index](README.md) for feature details and pending decisions.

## Setup and Signing

1. Open `vCRGlove.xcodeproj`. The local bHaptics package is included in `Vendor/bhaptics-ios-0.2.0`; demonstration assets are bundled in `vCRGlove/Resources/hand_videos`.
2. Select the `vCRGlove` scheme. The deployment targets are iOS 17 and watchOS 10. Check Apple's [Xcode compatibility matrix](https://developer.apple.com/xcode/system-requirements) for the Mac, Xcode and device combination. Deployment minimum, bundled SDK and physical-device support are separate constraints.
3. Use the authorized ICNS team with automatic signing. Current team ID: `X62VCFT697`. Phone bundle ID: `de.uke.icns.vcrglove`; companion: `de.uke.icns.vcrglove.watchkitapp`. Keep these identifiers when updating the existing app. Do not create new IDs to resolve a launch error.
4. Check each app and test target's Signing & Capabilities. Enable only capabilities required by its code/entitlements. Camera/Bluetooth privacy descriptions and background modes are not a reason to select unrelated Developer Portal services.
5. Run the iPhone app on a physical phone for camera and glove checks. Watch development can be tested separately on a compatible Mac/device pair. A successful iPhone run does not establish Watch debugging support.

Do not commit certificates, profiles, private keys or personal Xcode workspace settings. Current identity values are configuration, not secrets. Access and signing authority still belong to the development team.

## Code Map

Paths below are relative to the repository root.

| Responsibility | Main files |
| --- | --- |
| Launch, language and tab order | `vCRGlove/vCRGloveApp.swift`, `vCRGlove/MainTabView.swift` |
| Glove control and patient sessions | `vCRGlove/GloveVM.swift`, `vCRGlove/PatientVCRView.swift` |
| Researcher controls and stimulation profile | `vCRGlove/ResearchTools.swift`, `vCRGlove/StimulationProfile.swift` |
| Movement flow, demo and capture | `vCRGlove/MovementTaskView.swift`, `vCRGlove/MovementDemonstrationView.swift`, `vCRGlove/VisionHandPoseCapture.swift` |
| Samples, calculations and models | `vCRGlove/TrialRecorder.swift`, `vCRGlove/MovementAnalyzer.swift`, `vCRGlove/MovementModels.swift` |
| Movement persistence, video and export | `vCRGlove/TaskSessionStore.swift`, `vCRGlove/TaskSessionExporter.swift`, `vCRGlove/MovementExportView.swift` |
| Researcher full-data ZIP | `vCRGlove/FullDataExporter.swift`, raw snapshots in journal/task/event stores |
| Movement results | `vCRGlove/MovementTrendView.swift` |
| Journal screens and persistence | `vCRGlove/JournalHomeView.swift`, `vCRGlove/DailyCheckInView.swift`, `vCRGlove/JournalStore.swift`, `vCRGlove/JournalModels.swift` |
| Settings, study information and support | `vCRGlove/SettingsView.swift`, `vCRGlove/Localizable.xcstrings` |
| Event logging | `vCRGlove/EventStore.swift`, shared `Logger` in `vCRGlove/ResearchTools.swift` |
| Watch transport and capture | `vCRGlove/PhoneWC.swift`, `vCRGlove/WatchMotionCapture.swift`, `vCRGloveWatch Watch App/MotionService.swift` |
| Upload prototype | `vCRGlove/SessionUploader.swift` |
| Tests | `vCRGloveTests/`, `vCRGloveUITests/` |

Tab order is always vCR, Journal, Movement, Settings. Researcher unlock never adds a tab; the old `showResearchTab` preference is ignored. English/German strings belong in `vCRGlove/Localizable.xcstrings`; `L10n` looks them up using the in-app language choice. Do not restore a separate translation dictionary.

Language refresh retains the selected tab and General route in app-owned state above `.id(appSettings.language)`. It stays in Settings > General; relaunch starts normally. Profile shows the study ID only; avatar customization is deferred.

Research study-ID edits are staged until Save. Changing an assigned ID requires
confirmation; an assigned ID cannot be cleared. Cancel/back leaves it unchanged.
Only future recordings use a confirmed new ID; historical records are never
relabelled or automatically merged. Optional usernames remain deferred and must
not become research identity keys. Profile's ID remains read-only.

For a TEAM ID, unlocked Research Admin offers an explicit, reversible display
link for the researcher's own earlier unassigned tests. Confirming snapshots
existing session/trial UUIDs only; it never automatically links future tests or
assigned identities. `movementTrendIdentityLinks` stores the local JSON mapping
in app preferences. Results observes it, while session stores and JSON/CSV
exports retain original IDs. The full research archive includes the mapping in
`study-settings.plist` for provenance. Do not bundle real session IDs or enable
automatic `unset` aliases for participants.

## Behaviour to Preserve

- Patient stimulation offers 4 hours or two 2-hour sessions. One disconnected glove does not end stimulation on the other; losing both interrupts the session. Verify actual hardware behaviour, not just the displayed state.
- The idle timer is disabled during active stimulation. Inactive scene transitions are logged; background transitions also show a timing warning and request a finite background-task grace period. This does not guarantee foreground priority or uninterrupted stimulation when locked/backgrounded.
- Camera tasks use a fixed 30-second research interval, with early Stop. Missing hand tracking leaves gaps in the signal; it does not pause the recording clock. Capture feedback and analysable movement are different checks.
- A completed guided take is checkpointed locally before continuing. Retake preserves the old take until the replacement is saved. An unfinished draft can still be discarded; exact navigation restoration after process termination is not implemented.
- Stimulation context is selected for the session; medication timing is confirmed at the start and attached to each trial. Missing/unsure context must not become a negative answer or a medication ON/OFF classification.
- Journal check-in now asks mood and activity impact. Medication, symptom episodes and notes have separate log entry points and editing. Existing answers/unknown fields are preserved; reminder schedules and PDQ-8 are not implemented by this redesign stage.
- Private movies are silent and are not automatically placed in Photos. Review [save and export limits](DATA_FORMATS.md) before changing storage or sharing.
- The primary Settings order is Profile, General, Instructions, vCR Settings, Reminders, Data, Information about the study. General groups the existing language and text-size preferences; Profile no longer contains text size and the separate globe shortcut is removed. Text-size choices use full-width rows for readable large-text labels. Existing saved preferences are unchanged. Info is read-only; Contact is its last topic and contains contact details only. Devices and app contains the factual storage/video explanation formerly under Privacy & Data. The legal notice remains separate and unchanged. Reading these pages is not consent. See [source and review boundaries](STUDY_INFORMATION.md).

### Shared vCR and Researcher Controls

Settings ends with a discreet Study team entry below Contact/Help. Unlock exposes Study setup & logs in Settings and a collapsible Stimulation parameters panel on the existing vCR page. The patient view has no parameter sliders or logs when locked. `VCRView.swift` was removed; its shared logger and log panel now live in `ResearchTools.swift`.

Researchers set left/right SDK amplitude (0-100), cycle frequency (0.5-2.5 Hz) and either shuffled single-finger or legacy all-fingers-together stimulation. Both retain four slots per cycle and 100 ms pulses. Shuffled uses SDK motor indices 0-3 once each in random order; simultaneous drives the existing 20-element motor array on every slot, not just once per cycle. The upper frequency limit prevents scheduled 100 ms pulses overlapping; it is a software constraint, not clinical validation or a recommended treatment range.

Save is explicit and is rejected while running, paused or checking fingers. The saved profile survives restart and is used by patient Start, the five-motor startup check, idle test buzz, resume and a joining glove. Fresh installations retain the previous 70/70 amplitude, 1.5 Hz shuffled preset until staff save another profile. Staff must set and verify each patient's amplitudes in person before handover; there is no new mandatory setup gate or automatic calibration.

Each session snapshots the profile. Locking controls does not reset it or change stimulation. The app owns the controller above the language-dependent view identity, so changing language does not replace it. Stop/Pause invalidate scheduled slots; stale pulse-off callbacks cannot switch off a newer pulse. Stop during the startup check cancels its asynchronous continuation. A glove disconnection during the startup check stops the patient session and asks for a fresh Start rather than silently skipping the check. A corrupt/unsupported stored profile blocks stimulation until staff review and save it; defaults are not silently substituted for delivery.

Staff Settings retains patient ID/study metadata, the visible log, verbose BLE diagnostics and event-log sharing/clearing. Share all recorded data now prepares one ZIP containing raw journal, stimulation/app events, task signals/metrics, saved movies and study settings, with a checksum manifest. It opens the native share sheet without automatic upload or source deletion. Export is disabled during active/paused/startup stimulation. This is a manual export, not a verified backup or consent-based research transfer; see [Data formats](DATA_FORMATS.md#researcher-full-data-zip).

Unlock is in memory and starts locked on relaunch. The existing hard-coded password remains a convenience UI gate, not secure authentication or proof of researcher identity. Do not describe it as a security boundary. Saved profiles are local configuration, not a signed prescription or a complete study audit trail.

## Run Tests

In Terminal, from the repository root, first inspect the available simulators:

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
```

Choose an installed iPhone simulator and replace `SIMULATOR_UDID` below. `DEVELOPER_DIR` selects the full Xcode app for this command only; adjust its path if Xcode is installed elsewhere.

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vCRGlove.xcodeproj -scheme vCRGloveTests \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -derivedDataPath /tmp/vcr-unit-derived
```

For the focused Journal UI flows:

```zsh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vCRGlove.xcodeproj -scheme vCRGloveUITests \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -only-testing:vCRGloveUITests/vCRGloveUITests/testJournalTwoQuestionsAndSavedLogShortcutsEnglishGerman \
  -only-testing:vCRGloveUITests/vCRGloveUITests/testJournalEmptyShortcutDoesNotCreateCheckInEnglishGerman \
  -only-testing:vCRGloveUITests/vCRGloveUITests/testJournalFailedSaveKeepsCheckInAnswersEnglishGerman \
  -only-testing:vCRGloveUITests/vCRGloveUITests/testJournalCheckInCanBeEditedAndSurvivesRelaunchEnglishGerman \
  -only-testing:vCRGloveUITests/vCRGloveUITests/testJournalMedicationAndSymptomEditsEnglishGerman \
  -only-testing:vCRGloveUITests/vCRGloveUITests/testJournalSelectedDayAndFutureDateEnglishGermanLargeText \
  -derivedDataPath /tmp/vcr-ui-derived
```

Use the test target's launch harness and synthetic fixtures, not patient files. Record the commit, toolchain, destination, command and result bundle with each verification. Do not run competing test jobs against the same simulator.

For the bilingual study-information navigation and long-text check, use the UI test selector `testStudyInformationAndSupportEnglishGermanLargeText` in the same UI test class. It visits all six topics, the institutional support address and factual app-video storage text; German uses the largest app text size.

`testGeneralSettingsGroupsLanguageAndTextSizeEnglishGerman` covers placement, font choices, persistence and ID-only Profile. `testLanguageSwitchStaysInGeneralEnglishGermanLargeText` covers repeated switches, selected tab and Back at normal/extra-large sizes.

The focused researcher UI selector is `testResearchControlsShareVCRPersistAndRelockEnglishGerman`. It checks the fixed four tabs, unlock placement/password rejection, per-hand edits, pattern selection, persistence and relocking in English and large German text. `testResearchPatternMenuWrapsAndSelectsEnglishGermanLargeText` checks the wrapping pattern menu and Save; `testLanguageChangeRetainsSharedResearchController` checks controller retention through a language change. `StimulationProfileTests` uses isolated settings and injected motor/event outputs, without physical glove commands.

Full-device export checks use `FullDataExportTests`, `FullDataArchiveTests` and UI selector `testResearchFullDataShareEnglishGerman`. ZIP fixtures contain synthetic data only. Verify extracted file hashes, raw unknown/malformed records, missing-video notices, credential exclusion, empty-device export and temporary-copy cleanup. Do not use patient archives as test attachments.

## Validation Limits and Open Work

Simulator tests cover calculations, compatibility, save failures and UI flows. They do not validate camera tracking accuracy, glove timing, long-duration operation, Watch orientation/streaming, physical file protection or clinical usefulness. Use the [physical checklist](../Testing/vCRGlove_testing_checklist.md) and approved non-patient fixtures before study deployment.

The 14 October Journal work passed 135 unit tests and six distinct focused UI flows across runs, including English/German and large text. Those results belong to that working snapshot, not future releases. Physical review is pending; the existing symptom grid needs particular attention at the largest text size.

The 15 October Settings-refinement snapshot passed 139 unit tests and one focused English/German UI test on the iPhone 17e iOS 26.5 simulator, including menu order, contact-only navigation, relocated data text, separate troubleshooting and the largest German app text size. The retained German privacy copy was separately compared with Word. Results and source boundaries are recorded in [Study information](STUDY_INFORMATION.md); institutional review and physical reading checks remain pending.

The later 15 October shared-vCR snapshot passed 154 Swift Testing tests (plus the existing XCTest rendering test). Three focused UI checks passed across targeted runs: researcher configuration/persistence/relocking, the wrapping English/German pattern menu, and controller retention through a language change. The largest German app text size was included. An unsigned generic-iPhone Release build also succeeded with Xcode 26.5. This does not verify signing, installation, physical amplitudes, motor mapping or pulse timing; those remain bench/device checks before patient handover.

The subsequent full-data export snapshot passed 160 Swift Testing tests plus four XCTest checks. The final English/German UI flow passed, including largest German app text, share-sheet cancellation and a second export. The synthetic ZIP was independently extracted and all six manifest checksums verified, including raw records, a movie, study settings and the archive README. Missing-video reporting, failure cleanup, queued saves, credential exclusion and interrupted-export cleanup were checked; the simulator contained no leftover ZIP after dismissal. An unsigned generic-iPhone Release build succeeded. A real-phone export/AirDrop, large-volume storage-pressure check and recipient-side verification remain physical checks.

Daily trends now use filtered medians with protocol/version/context isolation. New camera signals use live palm/aspect normalization; historical samples are not rewritten. See [Results](MOVEMENT_RESULTS.md) for eligibility, units and remaining physical validation.

Outstanding decisions include reflection weekdays/reminders, licensed PDQ-8 content, Apple Health integration, validated task-specific composites, formal privacy/retention and consent-based research transfer. Documentation does not approve or implement them. Backend configuration is disabled at launch, but explicit session Finish can enqueue measurements locally; do not enable uploads without reviewing that queue and the full data contract.
