# vCRGlove

iPhone and Apple Watch research app for **vibrotactile Coordinated Reset (vCR) stimulation**, hand-movement recordings, and Parkinson's symptom journaling.

Developed at the **Institute for Computational Neuroscience (ICNS), University Medical Center Hamburg-Eppendorf (UKE)**.

**Status:** active research development. Movement measurements are not validated clinical ratings, and the app does not assign MDS-UPDRS scores.

## Current Features

### Stimulation
- Bluetooth scanning and left/right connection management for **bHaptics TactGlove DK2**.
- Patient session controls, including pause/resume and hold-to-stop, with connection and interruption feedback.
- Continued stimulation with one connected glove; automatic interruption when both disconnect.
- Research-mode stimulation parameters and local event logging.

### Movement Tasks
- Finger tapping and hand opening/closing for each hand, captured with the iPhone camera.
- Pronation/supination using live motion data from the Apple Watch companion.
- Guided hand-size calibration, silent demonstration videos for camera tasks, preparation countdown, and live tracking feedback.
- Timed 30-second research recordings, with early stopping and retake options.
- Automatic local saving of completed recordings in the guided session flow, without requiring every task to be finished.
- Recording timestamps, stimulation context, and patient-reported medication timing.

### Results and Data
- Rate and rhythm-variability plots over time, separated by task, hand, and capture source.
- Date, stimulation-context, and medication-context filters, plus a separate recording history.
- Measurement export and private-video playback, sharing, and deletion, including multi-video selection.
- Unavailable measurements are shown as unavailable rather than plotted as zero.

### Journal and Settings
- Calendar with an entry legend and a daily timeline.
- Mood and symptom check-ins, symptom episodes, medication events, and optional notes.
- English/German interface using one string catalog, with an in-app language selector.
- Text-size settings, instructions, and troubleshooting guidance.

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

Use **Settings > Data** to review, share, or delete recorded videos. Deleting a video keeps its movement measurements and does not delete copies previously shared elsewhere. JSON/CSV measurement exports do not contain video files; videos must be shared separately.

Backend upload code exists but is not configured at app launch. It is not yet a completed consent-based research-sharing workflow, and that upload path does not transfer video files. Formal privacy information and additional patient controls remain planned work.

## Next Priorities

- Complete privacy information and consent controls, including a choice not to store videos.
- Improve multi-day trends and validate additional movement metrics and task-specific composite scores.
- Simplify journal check-ins, strengthen saving/editing, and add streak feedback. PDQ-8 remains planned, subject to permissions and study requirements.
- Add a combined research-data export and a verified backup workflow before introducing consent-based transfers.
- Complete long-duration stimulation, reconnect, storage, and physical Watch validation.

## Documentation

- [Movement demonstrations and recording layout](docs/MOVEMENT_DEMONSTRATIONS.md)
- [Recording plots and context filters](docs/MOVEMENT_RESULTS.md)
- [Video storage, export, and deletion](docs/MOVEMENT_VIDEO_STORAGE.md)
- [Movement composite-score research and proposals](docs/MOVEMENT_COMPOSITE_RESEARCH.md)
- [Journal review and proposed redesign](docs/JOURNAL_REVIEW_PROPOSAL.md)

## Research Background

vCR research investigates whether patterned fingertip stimulation can support desynchronization of abnormal neuronal activity. Relevant publications include:

- Popovych, O. V., & Tass, P. A. (2012). [Desynchronizing electrical and sensory coordinated reset neuromodulation](https://www.frontiersin.org/journals/human-neuroscience/articles/10.3389/fnhum.2012.00058/full). *Frontiers in Human Neuroscience*, 6:58.
- Pfeifer, K. J., et al. (2021). [Coordinated Reset Vibrotactile Stimulation Induces Sustained Cumulative Benefits in Parkinson's Disease](https://pmc.ncbi.nlm.nih.gov/articles/PMC8055937/). *Frontiers in Physiology*, 12:624317.

These publications inform the research direction; they do not validate this app, its glove implementation, or its movement scores.

## License

This project is part of ongoing research at ICNS, UKE. Licensing terms are under review; **all rights reserved** for now. Please contact the authors for research collaboration inquiries.
