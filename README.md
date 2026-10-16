# vCRGlove

iPhone and Apple Watch research app for **vibrotactile Coordinated Reset (vCR) stimulation**, hand-movement recordings, and Parkinson's symptom journaling.

Developed at the **Institute for Computational Neuroscience (ICNS), University Medical Center Hamburg-Eppendorf (UKE)**.

**Status:** active research development. Movement measurements are not validated clinical ratings, and the app does not assign MDS-UPDRS scores.

## Current Features

### Stimulation
- Bluetooth scanning and left/right connection management for **bHaptics TactGlove DK2**.
- Patient session controls, including pause/resume and hold-to-stop, with connection and interruption feedback.
- Continued stimulation with one connected glove; automatic interruption when both disconnect.
- One vCR tab with saved per-hand amplitudes, cycle frequency and pattern controls after researcher unlock; staff Settings contains the logs.

### Movement Tasks
- Finger tapping and hand opening/closing for each hand, captured with the iPhone camera.
- Pronation/supination using live motion data from the Apple Watch companion.
- Guided hand-size calibration, silent demonstration videos for camera tasks, preparation countdown, and live tracking feedback.
- Timed 30-second research recordings, with early stopping and retake options.
- Automatic local saving of completed recordings in the guided session flow, without requiring every task to be finished.
- Recording timestamps, stimulation context, and patient-reported medication timing.

### Results and Data
- Daily-median trends for rate, camera movement size and rhythm variability, separated by task, hand, context and measurement method.
- Tap a day for counts/ranges and its recordings; pauses and amplitude change are under More details.
- Date, stimulation-context, and medication-context filters, plus a separate recording history.
- Measurement export and private-video playback, sharing, and deletion, including multi-video selection.
- Researcher-only full-data ZIP sharing: journal, stimulation logs, raw movement records, saved videos and study settings, with a checksum manifest.
- Unavailable measurements are shown as unavailable rather than plotted as zero.

### Journal and Settings
- Calendar with an entry legend and a daily timeline.
- Quick check-in for mood and the effect of Parkinson's on usual activities.
- Direct medication, symptom-episode and note logs, with editing and local persistence.
- English/German interface using one string catalog, with an in-app language selector.
- Text-size settings, instructions, and troubleshooting guidance.
- Bilingual study information and data-protection notice, plus factual private-video storage information.

## Getting Started

Deployment targets are **iOS 17+** and **watchOS 10+**. Use an Xcode version that supports the operating systems installed on your test devices.

1. Clone the repository and open `vCRGlove.xcodeproj` in Xcode.
2. Select the `vCRGlove` scheme and configure Signing & Capabilities for your authorized development team.
3. Build and run on a physical iPhone for camera and Bluetooth testing.
4. Turn on the TactGlove DK2 gloves and scan for them inside the app.
5. Install the Watch companion for pronation/supination testing. The Watch is not required for iPhone camera tasks or glove control.

The bHaptics SDK is included as a local Swift package at `Vendor/bhaptics-ios-0.2.0`. Bundled demonstration videos are in `vCRGlove/Resources/hand_videos`; no separate download is needed.

Simulator tests can check interface and software behaviour, but do not replace physical camera, glove, and Watch testing.

## Storage and Privacy

Data is stored inside the app's container on the iPhone:

| Data | Location |
| --- | --- |
| Stimulation and app events | `Documents/vcr/logs/events.jsonl` |
| Journal entries | `Documents/vcr/journal/journal_entries.json` |
| Movement sessions and signals | `Documents/vcr/tasks/sessions.jsonl` |
| Recorded camera-task videos | `Application Support/vcr/tasks/videos/` |

Camera-task videos are silent and are not automatically saved to Photos. Video storage requests iOS file protection and is excluded from automatic backup. **Local storage is not a backup:** deleting the app or losing the device can lose recordings.

Use **Settings > Data** to review, share, or delete recorded videos. Deleting a video keeps its movement measurements and does not delete copies previously shared elsewhere. JSON/CSV measurement exports do not contain video files. Researchers can unlock **Study team > Study setup & logs > Share all recorded data** to share one ZIP including all retained task movies and study records. Sharing is manual, contains sensitive data and does not verify recipient receipt or backup.

Backend upload code exists but is not configured at app launch. It is not yet a completed consent-based research-sharing workflow, and that upload path does not transfer video files. Settings includes study information and the adapted privacy notice; institutional review and additional patient controls remain pending. See [source and consent boundaries](docs/STUDY_INFORMATION.md).

## Next Priorities

- Review study/privacy wording and complete consent controls, including a choice not to store videos.
- Validate camera measurements, new velocity metrics and task-specific composite scores against recordings and clinical ratings.
- Add configurable journal reflection days/reminders and streak feedback. PDQ-8 remains planned, subject to permissions and study requirements.
- Verify recipient-side backup and recovery and agree consent-based transfers; the manual researcher ZIP is not an automatic upload or verified backup service.
- Complete long-duration stimulation, reconnect, storage, and physical Watch validation.

## Documentation

Start with the [documentation index](docs/README.md) for setup, code ownership, data formats, feature references and known limitations.

- [Release and Git checklist](docs/RELEASE_CHECKLIST.md)
- [Physical-device testing checklist](Testing/vCRGlove_testing_checklist.md)

## Research Background

vCR research investigates whether patterned fingertip stimulation can support desynchronization of abnormal neuronal activity. Relevant publications include:

- Popovych, O. V., & Tass, P. A. (2012). [Desynchronizing electrical and sensory coordinated reset neuromodulation](https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2012.00058/full). *Frontiers in Human Neuroscience*, 6:58.
- Pfeifer, K. J., et al. (2021). [Coordinated Reset Vibrotactile Stimulation Induces Sustained Cumulative Benefits in Parkinson's Disease](https://pmc.ncbi.nlm.nih.gov/articles/PMC8055937/). *Frontiers in Physiology*, 12:624317.

These publications inform the research direction; they do not validate this app, its glove implementation, or its movement scores.

## License

This project is part of ongoing research at ICNS, UKE. Licensing terms are under review; **all rights reserved** for now. Please contact the authors for research collaboration inquiries.
