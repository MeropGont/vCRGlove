# vCRGlove

iOS app to connect **bHaptics TactGlove DK2** (gaming gloves) to deliver **vibrotactile Coordinated Reset (vCR) stimulation** in the context of Parkinson’s disease (PD) research.  
Developed within the **ICNS group at University Medical Center Hamburg-Eppendorf (UKE)**.

## Background

**Coordinated Reset (CR) stimulation** was first proposed by *Peter A. Tass and colleagues* as a neuromodulation method to desynchronize abnormally synchronized neuronal activity.  
In Parkinson’s disease, such abnormal synchronization has been linked to motor symptoms such as tremor, rigidity, and bradykinesia.  
The CR concept has been adapted to **vibrotactile stimulation (vCR)**, where mechanical pulses delivered to the fingertips aim to induce desynchronization in sensorimotor networks.  

See:  
- Tass, P.A. et al. (2012). *Coordinated reset neuromodulation of pathological synchronization in Parkinson's disease.* Frontiers in Systems Neuroscience.  
- Pfeifer, K.J. et al. (2021). *Vibrotactile coordinated reset stimulation for Parkinson’s disease: Proof of concept.* Annals of Neurology.  

Our app explores how **consumer hardware** (bHaptics TactGlove + iPhone) can implement such stimulation in a **home-friendly, closed-loop research setup**.

---

## Features
- Connects to **bHaptics TactGlove DK2** via Bluetooth (using official bHaptics iOS SDK).
- Scans, pairs, and manages left/right glove connections.
- **Awakening buzz**: quick test vibration for each glove.
- **Long vibration protocols**: constant / pulsed / intermittent stimulation with adjustable timer.
- **vCR protocol**: randomized, desynchronizing multi-finger bursts inspired by Tass & Pfeifer publications.
- Logging of major events (connection, stimulation start/stop, errors).

---

## Getting Started
1. Clone this repo.  
2. Open `vCRGlove.xcodeproj` in Xcode (>= 15).  
3. Build & run on iPhone with iOS 17+.  
4. Requires **bHaptics iOS SDK** (included via Swift Package Manager).  
5. Pair TactGlove DK2 via the app interface.  

---

## Roadmap
- UI simplification (inline buzz button per glove, global controls).  
- Sliders for pulse duration and amplitude (continuous adjustment).  
- Unified global timer for all stimulation modes.  
- Optimized logs (errors + key events only, patient-friendly output).  
- Integration with Apple Watch for symptom tracking (future closed-loop setup).  

---

## License
This project is part of ongoing research at **ICNS, University Medical Center Hamburg-Eppendorf (UKE)**.  
Licensing terms are under review. For now: **all rights reserved**.  
Please contact the authors for research collaboration inquiries.  
