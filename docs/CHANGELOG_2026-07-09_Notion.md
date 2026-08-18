## 2026-07-09 · Movement Task Module: Watch-Integration für 3.6 (Task C) + Positionierungs-Schablone

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: iOS-Build kompiliert & Tests grün; **Watch-Build und End-to-End-Test am echten Gerätepaar ausstehend** (watchOS-SDK auf dem Mac nicht installiert — Build via Xcode)

Kontext: Task 3.6 (Pronation/Supination) soll mit der Apple Watch gemessen werden — dieselbe Analyse-Pipeline wie Kamera/Synthetik. Zusätzlich: Positionierungs-Schablone im Kamerabild für 3.4/3.5.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGloveWatch Watch App/MotionService.swift` | MOD | Live-Streaming-Modus: 50 Hz `rotationRate.x` (Unterarm-Achse), 16er-Batches an das iPhone |
| `vCRGloveWatch Watch App/WatchConnectivityManager.swift` | MOD | `sendMotionBatch`; empfängt `startMotionStream`/`stopMotionStream` vom iPhone |
| `vCRGloveWatch Watch App/WatchContentView.swift` | MOD | Zeigt „Streaming to iPhone…"-Status |
| `vCRGlove/PhoneWC.swift` | MOD | Routet Motion-Batches in die Capture-Pipeline (nicht ins Handshake-Log); sendet Start/Stop-Kommandos; `isWatchReachable` |
| `vCRGlove/WatchMotionCapture.swift` | NEW | Signalquelle analog `VisionHandPoseCapture`: Clock-Rebasing (Watch-Uptime → Phone-Uptime), `isReceiving`-Status mit Stale-Erkennung (1 s) |
| `vCRGlove/MovementTaskView.swift` | MOD | „Apple Watch / Simulated"-Picker bei 3.6; Watch-Status-Hint + Live-Chart in Countdown/Recording; `HandGuideOverlay` (Schablone) für 3.4/3.5 |

Design-Entscheidungen:
- **Steuerung vom iPhone:** Die Watch-App muss nur offen sein — Start/Stop des Streams kommt als WCSession-Message vom iPhone. Kein Bedienschritt an der Watch pro Trial.
- **Signal:** `rotationRate.x` (rad/s um die Unterarm-Achse). Ein voller Pron/Sup-Zyklus = eine positive Rotationswelle → die Hysterese-Zählung zählt 1 Count pro Zyklus. Falls in der Praxis doppelt/halb: auf Winkel-Integration umstellen.
- **Zeitbasis:** Watch stempelt in eigener Uptime; `WatchMotionCapture` rebased auf die Phone-Uptime beim ersten Batch (relative Abstände bleiben exakt; Batch-Latenz-Jitter irrelevant).
- **Batching:** 16 Samples/Message (~0,3 s bei 50 Hz) — hält WCSession stabil, Chart fühlt sich live an. `sendMessage` statt Queue: veraltete Samples sind im Live-Trial wertlos.
- **Schablone (`HandGuideOverlay`):** Gestrichelte Zielzone + task-spezifische Hand-Silhouette (`hand.pinch` bei 3.4, gespreizte Hand bei 3.5). Orange + „Place your hand here" solange Hand fehlt/zu nah/zu fern/abgeschnitten; grün + transparent, sobald die Position stimmt (Kriterien: `isHandVisible`, `!isHandClipped`, `handScale` 0.06–0.20).

Verifikation:
- iOS-Build erfolgreich (iPhone-17-Simulator); alle 16 Unit-Tests grün.
- Watch-Target konnte lokal nicht gebaut werden (watchOS-SDK fehlt auf dem Mac) — Build/Deploy über Xcode nötig.

Offene Punkte:
- [ ] **End-to-End-Test iPhone + Watch** (Olivia): Watch-App öffnen → 3.6 mit Source „Apple Watch" → Live-Chart zeigt Wellen beim Unterarmdrehen? 10 bewusste Zyklen korrekt gezählt?
- [ ] Zyklen-Zählung bei 3.6 validieren (positive Lobes vs. volle Zyklen — ggf. Winkel-Integration).
- [ ] Schablonen-Zone ggf. an reale Nutzung anpassen (Größe/Position).

---

## 2026-07-09 · MovementAnalyzer: Hysterese-Zyklenzählung (Fix für 3.5) + Randerkennung mit Sofort-Warnung

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: alle 16 Unit-Tests grün; Fingertapping am Gerät von Olivia validiert, 3.5-Nachtest ausstehend

Kontext: Nach dem Off-by-one-Fix stimmte die Zählung bei 3.4 (Finger Tapping), bei 3.5 (Hand Open/Close) aber gar nicht — obwohl die Live-Kurve die Bewegung korrekt zeigte. Ursachen: (a) Plateaus (Hand ganz offen/zu) mit Wacklern und Faust-Verdeckungsrauschen narren die Peak-Prominenz-Erkennung; (b) Finger, die knapp über den Bildrand ragen, lassen Vision die Joints verlieren → stillschweigend keine Samples.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGlove/MovementAnalyzer.swift` | MOD | Zyklen-Segmentierung komplett auf Hysterese (Schmitt-Trigger) umgestellt; Peak-/Trough-Detektion entfernt |
| `vCRGlove/SyntheticSignalGenerator.swift` | MOD | Bugfix Testsignal: „Freezing"-Pause friert am letzten Wert ein statt auf festen Mittelwert zu springen (der Sprung zählte selbst als Zyklus) |
| `vCRGlove/VisionHandPoseCapture.swift` | MOD | `isHandClipped`: task-relevante Joints < 4 % vom Bildrand, oder Handgelenk sichtbar aber alle Fingerspitzen fehlen; 0,6 s Hold gegen Flackern |
| `vCRGlove/MovementTaskView.swift` | MOD | `ClippedWarningOverlay`: roter Rahmen + Banner + haptisches Warning-Feedback, sobald Finger den Bildrand verlassen |

Design-Entscheidungen:
- **Hysterese statt Peak-Prominenz:** Ein Zyklus zählt nur, wenn das Signal von unter 25 % auf über 45 % des robusten Wertebereichs (5.–95. Perzentil) steigt. Plateau-Wackler durchqueren das Band nie komplett → können nie doppelt zählen. Band bewusst im unteren Bereich, damit Zyklen mit Amplituden-Decrement (Sequence Effect) noch gezählt werden.
- **Amplitude pro Zyklus** = max−min des Segments zwischen zwei Zyklus-Events; Frequenz = Intervalle zwischen Events; Pausen = Event-Lücken > 2× Median.
- **Diagnose über Standalone-Skript** (Generator + Analyzer außerhalb Xcode kompiliert): zeigte, dass der synthetische Pausen-Sprung als Event zählte und die Pause dadurch als 0,68-s-Lücke statt 1,05 s erschien → Generator-Fix, kein Test-Aufweichen.
- **Randerkennung vor der Signal-Extraktion:** Warnung greift genau in dem Moment, wo sonst stillschweigend Samples ausfallen. Haptik zusätzlich zum Visuellen, weil der Blick beim Test oft auf der Hand liegt.

Verifikation:
- Alle 16 Unit-Tests grün (Analyzer-Tests decken healthy/parkinsonian/flach/leer/Determinismus ab; parkinsonian nun mit realistischerem Freezing).
- Fingertapping am echten iPhone von Olivia bestätigt (exakte Zählung); Randerkennungs-Befund von Olivia reproduziert und adressiert.

Offene Punkte:
- [ ] **3.5 am Gerät nachtesten** (Olivia): 10 bewusste Open/Close-Zyklen, auch mit Pausen — Zählung exakt? Rand-Warnung erscheint sofort?
- [ ] Validierungsprotokoll für übrige Metriken (Metronom für Frequenz/Rhythmus, bewusste Pausen, absichtliches Decrement, verzögerter Start) — Anleitung liegt vor.
