# Project Handoff Brief — vCRGlove Movement Task Module

> Self-contained brief for an AI coding agent (Devin) to continue development.
> Everything needed to work on the task is below; no external chat context required.
> Repo: `github.com/MeropGont/vCRGlove` (private/institutional, ICNS @ UKE). Work on branch `feature/movement-task-module`.

---

## 1. Project context

`vCRGlove` is an iOS + watchOS research app (SwiftUI) developed in the ICNS group at University Medical Center Hamburg-Eppendorf (UKE). It drives **vibrotactile Coordinated Reset (vCR) stimulation** via bHaptics TactGlove DK2 gloves (Bluetooth) for Parkinson's disease (PD) patients, and includes a Journal module for daily symptom tracking and an Apple Watch companion that records CoreMotion data.

**Clinical background (short):** In PD, neurons in the basal ganglia over-synchronize in the beta band (13–30 Hz), driving motor symptoms. Coordinated Reset delivers short, phase-shifted stimuli to desynchronize this activity. The glove applies this non-invasively via fingertip vibration. Effects are reported both acutely and cumulatively over weeks/months.

## 2. The task

Build an **MDS-UPDRS-inspired movement task module** (already listed as a roadmap item in the repo README) that records and quantitatively evaluates the *quality* of three upper-limb bradykinesia movements. Two goals:
1. **Patient-facing:** let the user see their own progress over time (with/without the glove).
2. **Clinic-facing:** produce exportable raw data + metrics for studies.

### The three movements (MDS-UPDRS-III items)
- **3.4 Finger tapping** — index finger taps thumb 10× as fast and large as possible.
- **3.5 Hand movements** — open/close fist 10× as fast and large as possible.
- **3.6 Pronation/supination** — forearm rotation.

### Key insight that shapes the whole design
All three UPDRS items use the **same five scoring criteria**: speed, amplitude, hesitations, interruptions, amplitude decrement. So we do **not** build three scoring logics — we build **one sensor-independent pipeline** that turns a 1-D movement signal into five metrics. Only the signal *source* differs per task:
- 3.4 & 3.5 → **iPhone camera + Vision** (`VNDetectHumanHandPoseRequest`); metric per frame = a distance (thumb–index, or fingertip-to-palm).
- 3.6 → **Apple Watch CoreMotion** (`rotationRate` around the forearm axis); the watch gyroscope captures rotation directly and robustly.

Mapping of UPDRS criterion → computed feature:
| UPDRS criterion | Feature |
| --- | --- |
| Speed | Cycle frequency (Hz), peak speed per cycle |
| Amplitude | Peak-to-peak per cycle (normalized) |
| Hesitations | Onset latency, mean inter-cycle interval |
| Interruptions ("freezing") | Count of abnormally long gaps |
| Amplitude decrement | Slope of amplitude over the repetitions (sequence effect) |
Plus **rhythm variability** (coefficient of variation of cycle durations).

> Important: show the patient the **continuous trends**, not a guessed 0–4 UPDRS score. A guessed score implies accuracy that isn't validated. Validation against expert UPDRS rating is a separate, later step.

## 3. Existing codebase — what to reuse

The repo is already a substantial app. Relevant existing pieces and how the new module attaches:

| Area | Existing file | Reuse for the module |
| --- | --- | --- |
| Watch motion | `vCRGloveWatch Watch App/MotionService.swift` (CoreMotion, ~50 Hz, CSV, **only `userAcceleration`**) | Base for 3.6; **must be extended to record `rotationRate`** |
| Watch→Phone transfer | `WatchConnectivityManager.swift` (`transferFile`) + `vCRGlove/PhoneWC.swift` (receives, logs) | Channel for task recordings + metadata |
| Persistence pattern | `vCRGlove/JournalStore.swift` (singleton, Codable, JSON) | Style template for the new store (module uses JSONL) |
| App-wide logging | `vCRGlove/EventStore.swift` — `append(type:tag:message:details:)` writing `Documents/vcr/logs/events.jsonl` | Write task events to the shared timeline |
| Navigation | `vCRGlove/MainTabView.swift` (Tabs: vCR / Research / Journal / Settings) | Add an entry point for the movement test |
| Data-model style | `vCRGlove/JournalModels.swift` (Codable enums/structs) | Style template for the new models |

**Conventions to follow (match the repo):**
- Stores are `final class ... : ObservableObject`, singletons via `static let shared`, `@Published private(set)` state.
- Models are `Codable` structs/enums; enums use `String` raw values.
- Persistence lives under `Documents/vcr/...`; logging goes through `EventStore.shared`.
- File-sharing is enabled in `Info.plist` so data can be pulled off-device for analysis.

## 4. What is already built (this batch — on `feature/movement-task-module`)

Five new Swift files form the **sensor-independent core**, fully testable in the Simulator with no hardware. Place them in a new group/folder `vCRGlove/MovementTask/` and add to the `vCRGlove` target.

1. **`MovementModels.swift`** — `MovementTaskType` (`3.4`/`3.5`/`3.6` raw values), `SignalSource` (camera/watchMotion/synthetic), `BodySide`, `StimulationContext` (baseline/preStim/postStim), `StopCondition` (**supports BOTH** fixed reps and fixed duration via `StopMode`), `TimestampedSample` (`t` seconds-since-start, `value`), `MovementMetrics` (cycleCount, frequencyHz, meanAmplitude, amplitudeDecrementSlope, rhythmCV, pauseCount, onsetLatencySec, qualityIndex), `Trial`, `MovementSession`.

2. **`MovementAnalyzer.swift`** — sensor-independent pipeline: smooth → detect peaks/troughs (window-based prominence) → segment cycles → compute all metrics via helpers (`linearSlope`, `coefficientOfVariation`, `countPauses`). Pure Foundation, no side effects. `qualityIndex` is a heuristic 0…1 for UI only (explicitly **not** a validated score).

3. **`SyntheticSignalGenerator.swift`** — generates fake signals (decaying sinusoid + noise + jitter + injected pauses) with presets `.healthy` and `.parkinsonian`, plus a deterministic seeded PRNG. Lets the whole stack be developed/tested without camera/watch/glove.

4. **`TrialRecorder.swift`** — sensor-agnostic. A capture source calls `ingest(value:at:)` per sample; the recorder auto-stops after N cycles (reps mode, live-counted via the analyzer) or after a fixed duration, then emits a finished `Trial` via `onComplete`.

5. **`TaskSessionStore.swift`** — JSONL persistence (append-only, one session per line) at `Documents/vcr/tasks/sessions.jsonl`, mirroring `JournalStore`. Logs via `EventStore`. Provides `history(task:side:)` returning `[(date, metrics)]` sorted oldest-first — ready to feed Swift Charts.

**Verification already done:** the analyzer logic was ported to Python and tested on synthetic signals. Results separate cleanly and are clinically plausible:
- healthy-like: ~4.5 Hz, rhythm CV 0.035, no decrement, 0 pauses;
- parkinsonian-like: ~1.5 Hz, rhythm CV 0.48, decrement −0.11, 3 pauses.
A bug was fixed in the process: peak prominence measured against only the two immediate neighbours finds almost no peaks at 60 Hz sampling → changed to **window-based prominence** (walk left/right to the next reversal).

**Data flow (assembled):**
```
capture source ──ingest(value:at:)──▶ TrialRecorder ──Trial──▶ TaskSessionStore (JSONL)
   (Vision / Watch / Synthetic)            │                          │
                                     MovementAnalyzer            history(task:side:) ──▶ Swift Charts
                                     → MovementMetrics
```

## 5. Remaining work (prioritized tasks for Devin)

> Devin can write all of this, but **cannot build/run iOS or test on device** (no Xcode/Simulator/hardware in Devin's cloud env). Produce clean, compilable Swift on the feature branch as commits/PRs; the human runs the Simulator/device tests in Xcode. For camera/CoreMotion code, write it correctly per Apple docs and clearly flag that it needs on-device verification.

### Task A — Integrate & smoke-test the core (human-in-loop; Devin can prep)
- Ensure the five files compile against the existing target (imports, access levels).
- Add a lightweight unit test (XCTest) that runs `SyntheticSignalGenerator(.parkinsonian)` → `MovementAnalyzer().analyze(...)` and asserts: `frequencyHz < 3`, `rhythmCV > 0.2`, `amplitudeDecrementSlope < 0`, `pauseCount >= 1`; and for `.healthy`: `frequencyHz > 3.5`, `rhythmCV < 0.1`.
- **Acceptance:** tests pass in Xcode; no compiler warnings in the new files.

### Task B — `VisionHandPoseCapture` (camera; for 3.4 & 3.5)
- New class wrapping `AVCaptureSession` (front or rear camera) + `VNDetectHumanHandPoseRequest`.
- Per frame, compute the task metric and call `recorder.ingest(value:at:)` with `systemUptime` as the monotonic time:
  - 3.4 finger tapping → euclidean distance between thumb-tip and index-tip landmarks.
  - 3.5 hand open/close → mean distance of the five fingertips to the hand centroid (or hand bounding-box area).
- **Normalize** by hand size (e.g. wrist-to-middle-MCP distance) so the metric is scale/distance-independent.
- Run Vision requests off the main thread; publish nothing heavy on main.
- **Acceptance:** compiles; documented that it requires a real device + camera-usage `Info.plist` key (`NSCameraUsageDescription`); ideally a preview/debug overlay of detected landmarks.

### Task C — Extend `MotionService` for 3.6 (Apple Watch)
- Currently records only `userAcceleration`. Add `rotationRate` (and optionally attitude) capture.
- Provide a path that feeds the forearm-rotation signal into a `TrialRecorder` (either compute on-watch and send values, or stream raw samples to the phone via `WatchConnectivityManager` and analyze there — pick one and document it).
- **Acceptance:** compiles for the watchOS target; documented as needing on-device test.

### Task D — Recording flow UI (SwiftUI)
- A view: pick task (3.4/3.5/3.6) → pick side (L/R) → pick `StopCondition` (reps vs duration) → countdown → live progress (elapsed / `liveCycleCount`) → result screen showing the `MovementMetrics`.
- Wire it to `TrialRecorder` and save via `TaskSessionStore`. Add an entry point in `MainTabView` (new tab or a button in an existing view).
- **Acceptance:** works in the Simulator using `SignalSource.synthetic` as a stand-in source (so it's testable without hardware).

### Task E — Patient trend view (SwiftUI + Swift Charts)
- Use `TaskSessionStore.history(task:side:)` to plot one chosen metric over time, marking `StimulationContext` (pre/post) — a clear before/after visualization.
- **Acceptance:** renders in the Simulator from seeded/sample sessions.

### Task F — Shared timeline & export
- Record a **sync offset** at session start so Phone/Watch/camera timestamps align (the Watch uses device uptime, not wall-clock; without an offset the sources drift). Log session start/stop through `EventStore`.
- Add CSV/JSON export of sessions for the clinic (README lists export tooling as open).
- **Acceptance:** compiles; export produces a well-formed file under `Documents/vcr/tasks/`.

## 6. Constraints & gotchas

- **Simulator can't do Bluetooth, camera, or real CoreMotion.** UI, models, analyzer, store, and the synthetic source are fully testable in the Simulator; anything touching real sensors needs a physical iPhone (+ Apple Watch).
- **Timestamps:** the Watch's `dm.timestamp` is device uptime, not wall-clock. Always normalize to seconds-since-start (as `TimestampedSample.t` already does) and capture a sync offset for cross-device alignment.
- **Privacy/ethics:** patient IDs must be **pseudonymized** (never real names). Video is sensitive — Vision runs on-device, keep it that way; don't add cloud upload without lab/ethics sign-off. Clarify data storage (local vs. study server such as REDCap) with the lab.
- **qualityIndex is a heuristic**, not a UPDRS score. Don't present it as a clinical rating.
- **License:** "all rights reserved", ICNS/UKE internal research code.
- **Standardization decision made:** support **both** stop conditions (10 reps and fixed duration) — already modeled in `StopCondition`.

## 7. Definition of done for the module (overall)
- All three tasks recordable end-to-end on a real device, each producing a `MovementSession` with `Trial`s and `MovementMetrics`.
- Patient can view per-metric trends with pre/post markers.
- Clinic can export raw + metrics.
- Core analysis covered by unit tests against synthetic signals.
- (Later, out of scope here) metrics validated against expert MDS-UPDRS ratings before any 0–4 approximation is shown.

---

*Prepared as a handoff for continued development. The five scaffold files referenced in §4 accompany this brief.*
