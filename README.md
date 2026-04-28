# vCRGlove

iOS and Apple Watch research app for **vibrotactile Coordinated Reset (vCR) stimulation** and daily Parkinson's disease (PD) symptom tracking.

The iPhone app connects to **bHaptics TactGlove DK2** gloves, delivers configurable fingertip vibration patterns, and provides a Journal module for daily check-ins, symptom episodes, medication events, and notes. The Apple Watch companion app records motion data for future tremor/activity analysis.

Developed within the **ICNS group at University Medical Center Hamburg-Eppendorf (UKE)**.

## Background

**Coordinated Reset (CR) stimulation** was first proposed by *Peter A. Tass and colleagues* as a neuromodulation method to desynchronize abnormally synchronized neuronal activity.  
In Parkinson’s disease, such abnormal synchronization has been linked to motor symptoms such as tremor, rigidity, and bradykinesia.  
The CR concept has been adapted to **vibrotactile stimulation (vCR)**, where mechanical pulses delivered to the fingertips aim to induce desynchronization in sensorimotor networks.  

See:  
- Tass, P.A. et al. (2012). *Coordinated reset neuromodulation of pathological synchronization in Parkinson's disease.* Frontiers in Systems Neuroscience.  
- Pfeifer, K.J. et al. (2021). *Vibrotactile coordinated reset stimulation for Parkinson’s disease: Proof of concept.* Annals of Neurology.  

This app explores how **consumer hardware** (bHaptics TactGlove + iPhone + Apple Watch) can support a **home-friendly, closed-loop research setup** combining stimulation delivery, patient-reported diary data, and wearable motion signals.

---

## Features

### vCR stimulation
- Connects to **bHaptics TactGlove DK2** via Bluetooth using the official bHaptics iOS SDK.
- Scans, pairs, and manages left/right glove connections.
- Provides manual vibration controls for amplitude, frequency, pulse length, stimulation duration, and number of active fingers per cycle.
- Includes a vCR mode using randomized, desynchronizing multi-finger bursts inspired by Tass and Pfeifer publications.
- Logs major stimulation and connection events.

### Journal and daily log
- Calendar-based Journal home for selecting days and reviewing entries.
- Daily Log page for each selected date.
- Daily Check-In for mood, overall symptom intensity, and symptom selection.
- Symptom Episode logging for OFF periods, tremor, freezing, dyskinesia, and other symptom changes.
- Medication logging focused on patient-friendly event types:
  - usual medication
  - late medication
  - missed medication
  - extra/rescue medication
- Medication context fields for ON/OFF state, dyskinesia, and factors such as food, protein, stress, poor sleep, constipation, and activity.
- Free-text notes for unusual events or clinically relevant observations.
- Day timeline summarizing saved check-ins, symptoms, medication events, and notes.

### Apple Watch companion
- Records Apple Watch motion data using CoreMotion.
- Shows simple live RMS motion feedback.
- Exports motion recordings to the iPhone through WatchConnectivity.

### Local data
- App event logs are written under the app Documents directory:
  - `vcr/logs/events.jsonl`
  - `vcr/logs/handshake.jsonl`
- Journal entries are currently stored locally as:
  - `vcr/journal/journal_entries.json`
- File sharing is enabled in `Info.plist` so app data can be copied from the phone for inspection and analysis.

---

## Getting Started
1. Clone this repo.  
2. Open `vCRGlove.xcodeproj` in Xcode (>= 15).  
3. Build & run on iPhone with iOS 17+.  
4. Requires **bHaptics iOS SDK** (included via Swift Package Manager).  
5. Pair TactGlove DK2 via the app interface.  
6. Optional: install the Apple Watch companion app for motion recording and WatchConnectivity testing.

---

## Roadmap
- Migrate Journal storage from a single JSON array to append-only JSONL for longer studies.
- Add export tooling for journal, stimulation, and watch-motion datasets.
- Add editing or replacement behavior for one-per-day Daily Check-In entries.
- Add medication profile templates while keeping daily logging patient-friendly.
- Integrate Apple Watch motion data into the Journal timeline.
- Add summary/insight views for symptoms, OFF periods, medication timing, and stimulation sessions.
- Continue UI simplification and accessibility improvements for patient use.

---

## License
This project is part of ongoing research at **ICNS, University Medical Center Hamburg-Eppendorf (UKE)**.  
Licensing terms are under review. For now: **all rights reserved**.  
Please contact the authors for research collaboration inquiries.  
