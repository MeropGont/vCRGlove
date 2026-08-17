## 2026-07-08 · Movement Task Module: Kamera-Erfassung via Vision Hand Pose (Task B)

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: kompiliert (Simulator + Geräte-Compile ok; **Verifikation am echten iPhone ausstehend** — Simulator hat keine Kamera)

Kontext: Tasks 3.4 (Finger Tapping) und 3.5 (Hand Open/Close) sollen mit der iPhone-Frontkamera gemessen werden. Apples Vision-Framework liefert Hand-Landmarken pro Frame; daraus wird ein 1-D-Signal berechnet, das in denselben `TrialRecorder` fließt wie die synthetische Quelle. Task B aus dem Handoff-Brief.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGlove/VisionHandPoseCapture.swift` | NEW | AVCaptureSession (Frontkamera) + `VNDetectHumanHandPoseRequest` → normalisierter Skalar pro Frame; Permission-Handling, `isHandVisible`-Status |
| `vCRGlove/MovementTaskView.swift` | MOD | Quellen-Picker (Camera/Simulated) für 3.4/3.5, Kamera-Preview in Countdown + Recording, „Hand detected"-Hinweis, Fehleranzeige |
| `vCRGlove/Info.plist` | MOD | `NSCameraUsageDescription` (inkl. Hinweis: kein Video wird gespeichert) |

Design-Entscheidungen:
- **Signalberechnung:** 3.4 = Abstand Daumen-/Zeigefingerspitze; 3.5 = mittlerer Abstand der 5 Fingerspitzen zum Handzentrum (Mitte Handgelenk↔Mittelfinger-MCP). Beides **normalisiert durch die Handgröße** (Handgelenk↔MCP) → unabhängig vom Kameraabstand.
- **Zeitbasis:** Frame-Timestamps (CMSampleBuffer PTS, Host-Clock) sind direkt kompatibel mit `systemUptime` — der Sync-Anker aus Task F greift ohne Zusatzaufwand.
- **Robustheit:** Joint-Confidence-Gating (≥ 0.3); 3.5 toleriert bis zu 2 verdeckte Finger; kein Sample bei nicht erkannter Hand (Lücken statt Müll); `alwaysDiscardsLateVideoFrames` gegen Analyse-Stau; VGA-Preset (reicht für Hand-Pose, schont Akku/Wärme).
- **Kamera-Warm-up im Countdown:** Die Session startet schon beim 3-2-1, damit die Kamera-Anlaufzeit nicht die Onset-Latency verfälscht; Preview + „Hold your hand in front of the camera"-Hinweis helfen bei der Positionierung.
- **Datenschutz:** Es wird nie Video gespeichert — nur die berechneten Skalare; so auch in der Permission-Beschreibung kommuniziert.
- Der Quellen-Picker erscheint nur bei 3.4/3.5 (3.6 wartet auf die Watch, Task C); „Simulated" bleibt für Simulator/Demos verfügbar.

Verifikation:
- Simulator-Build erfolgreich, keine Warnungen in den neuen/geänderten Dateien; App im Simulator installiert (Kamera-Pfad zeigt dort sauber die Fehlermeldung „No camera available").
- Geräte-Compile erfolgreich (Abbruch nur beim Signing — Provisioning läuft über Xcode mit Account, nicht über CLI).

Offene Punkte:
- [ ] **Test am echten iPhone** (Olivia): Permission-Dialog, Preview, Hand-Erkennung, 3.4 und 3.5 je L/R, plausible Metriken vs. Selbsteinschätzung.
- [ ] Ggf. Tuning: `minProminenceFraction`/Smoothing für echtes Kamerarauschen (bisher nur an synthetischen Signalen kalibriert).
- [ ] Orientierungs-Handling (`.up`) ist für Portrait ausgelegt — bei Landscape-Nutzung prüfen.
- [ ] Task C: Watch-Gyroskop für 3.6.

---

## 2026-07-07 · Movement Task Module: Zeit-Sync-Anker & Klinik-Export (Task F)

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: kompiliert, Export per Unit-Tests verifiziert (Simulator-Durchklick durch Olivia ausstehend)

Kontext: Die Klinik braucht Rohdaten + Metriken als Dateien; außerdem müssen Phone-/Watch-/Kamera-Zeitstempel später alignierbar sein (die Watch stempelt in Geräte-Uptime, nicht Wanduhrzeit). Task F aus dem Handoff-Brief.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGlove/TaskSessionExporter.swift` | NEW | Export: JSON (volle Sessions), CSV metrics (1 Zeile/Trial), CSV samples (1 Zeile/Rohsample) → `Documents/vcr/tasks/exports/`, EventStore-Log |
| `vCRGlove/MovementExportView.swift` | NEW | Export-Screen: Datenübersicht, 3 Export-Buttons, ShareLink (AirDrop/Mail), Fehleranzeige |
| `vCRGlove/MovementModels.swift` | MOD | `Trial.startUptime: Double?` — Sync-Anker (systemUptime bei Trial-Start) neben `startedAt` (Wanduhr) |
| `vCRGlove/TrialRecorder.swift` | MOD | Befüllt `startUptime` beim Abschluss des Trials |
| `vCRGlove/MovementTaskView.swift` | MOD | `trial_completed`-Log via EventStore (Start wurde schon geloggt) |
| `vCRGlove/SettingsView.swift` | MOD | Einstiegspunkt „Movement task export" in Research Admin → Data |
| `vCRGloveTests/TaskSessionExporterTests.swift` | NEW | 5 Tests: JSON-Roundtrip, CSV-Form (Header/Spalten/Zeilenzahl), leerer Export wirft Fehler, Legacy-Decoding ohne `startUptime` |

Design-Entscheidungen:
- Sync-Anker pro Trial statt pro Session: jedes Gerät bekommt sein eigenes Paar (Wanduhr, Uptime) — beim Anschluss der Watch (Task C) reicht deren eigener Anker zum Alignment; kein Offset-Austausch-Protokoll nötig.
- `startUptime` ist optional → bestehende JSONL-Aufnahmen dekodieren weiter (per Test abgesichert).
- Zwei CSVs statt einem: `metrics-*.csv` als klinische Haupttabelle (1 Zeile/Trial, alle 5 UPDRS-Kriterien + Metadaten), `samples-*.csv` für Signal-Reanalyse in R/Python. Dateinamen mit Zeitstempel, kein Überschreiben.
- Export-Ordner unter `Documents/` → per Files-App erreichbar (File-Sharing ist im Info.plist aktiv); zusätzlich ShareLink für direkten Versand.
- Einstiegspunkt bewusst im passwortgeschützten Research-Admin-Bereich, nicht im Patient:innen-UI.

Verifikation:
- Alle 14 Unit-Tests grün (5 neue Export-Tests + alle bestehenden).
- Build ohne Warnungen in den neuen/geänderten Dateien; App im Simulator installiert.

Offene Punkte:
- [ ] Simulator-Durchklick: Settings → Research Admin → Movement task export → alle 3 Exporte + ShareLink prüfen.
- [ ] Uhr-Drift zwischen Geräten wird durch den Anker nicht korrigiert (nur Uptime↔Wanduhr-Mapping) — für Task C ggf. NTP-artige Prüfung erwägen.
- [ ] Klärung mit dem Labor: lokale Ablage vs. Studienserver (REDCap) — Export ist bewusst nur lokal/on-device.

---

## 2026-07-07 · Movement Task Module: Trend-View mit Swift Charts (Task E)

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: kompiliert (Simulator-Durchklick durch Olivia ausstehend)

Kontext: Patient:innen sollen ihre Entwicklung über die Zeit sehen — pro Task/Hand/Metrik, mit farblicher Markierung des Stimulationskontexts (Vorher/Nachher-Vergleich). Task E aus dem Handoff-Brief; bewusst kontinuierliche Trends statt eines geratenen UPDRS-Scores.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGlove/MovementTrendView.swift` | NEW | Trend-Chart (Swift Charts): Task/Hand/Metrik wählbar, Punkte nach `StimulationContext` gefärbt; DEBUG-Seeder für 14 Tage Beispieldaten |
| `vCRGlove/TaskSessionStore.swift` | MOD | `history(task:side:)` liefert jetzt auch den `StimulationContext` pro Datenpunkt (wurde für Pre/Post-Markierung gebraucht) |
| `vCRGlove/MovementTaskView.swift` | MOD | Toolbar-Button „Trends" als Einstiegspunkt |

Design-Entscheidungen:
- `TrendMetric`-Enum kapselt alle 7 Metriken (Name, Einheit, Zugriff, „höher = besser?") — der Chart-Code bleibt metrik-agnostisch.
- Graue Verbindungslinie + farbige Punkte (Baseline grau, Pre orange, Post grün) — der Pre/Post-Effekt ist auf einen Blick sichtbar.
- Empty State via `ContentUnavailableView` mit Hinweis, wie man Daten aufnimmt.
- Beispieldaten-Seeder nur unter `#if DEBUG`: generiert 14 Tage Pre/Post-Paare mit gradueller Verbesserung + akutem Post-Stim-Effekt (via `SyntheticSignalGenerator` + echter Analyse, keine hartkodierten Metriken); `patientId: "sample"`.

Verifikation:
- Build erfolgreich (iPhone-17-Simulator, iOS 26.2), keine Warnungen in den geänderten Dateien; App im Simulator installiert.

Offene Punkte:
- [ ] Simulator-Durchklick: Seeder ausführen → Chart prüfen (Pre/Post-Trennung sichtbar? Metrik-Wechsel ok?).
- [ ] Seed-Daten landen in der echten `sessions.jsonl` — für Studien-Builds ist der Seeder per DEBUG-Flag ausgeschlossen, ggf. später Lösch-Funktion für `patientId == "sample"`.
- [ ] Task F: CSV/JSON-Export + Zeit-Sync-Offset.

---

## 2026-07-07 · TrialRecorder: Sicherheits-Timeout im Reps-Modus (Fix)

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: im Simulator getestet

Kontext: Beim Simulator-Test stockte das Parkinson-Preset oft bei ~8/10 Reps. Ursache: das simulierte Amplituden-Decrement (12 %/s) drückt späte Zyklen unter die Peak-Erkennungsschwelle (15 % Prominenz) — klinisch korrekt (Sequence Effect: der Patient *schafft* keine 10 Reps), aber der Recorder wartete endlos und die Aufnahme hing bis zum manuellen Stop. Relevant auch für echte Patient:innen.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGlove/TrialRecorder.swift` | MOD | Sicherheits-Timeout (30 s) im `.repetitions`-Modus; Teilaufnahme wird normal ausgewertet |
| `vCRGloveTests/TrialRecorderTests.swift` | NEW | 3 Tests: Timeout greift bei unerreichbarem Ziel, 10-Reps-Stopp intakt, Duration-Stopp intakt |

Design-Entscheidungen:
- Timeout als statische Konstante `repetitionsSafetyTimeoutSec = 30` mit Doku-Kommentar — bewusst großzügig, damit langsame, aber vollständige Durchläufe nicht abgeschnitten werden.
- Kein neues UI: Nach dem Timeout erscheint der normale Ergebnisbildschirm mit der Teilaufnahme (weniger als 10 Zyklen ist selbst ein klinisch relevanter Befund).

Verifikation:
- Alle Tests grün (inkl. der 6 bestehenden Analyzer-Tests); Verhalten im Simulator bestätigt: Parkinson-Preset endet jetzt automatisch statt zu hängen.

Offene Punkte:
- [ ] keine

---

## 2026-07-07 · Movement Task Module: Unit-Tests der Analyse-Pipeline (Task A)

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: im Simulator getestet

Kontext: Der sensor-unabhängige Kern des Movement-Task-Moduls (MDS-UPDRS-Items 3.4/3.5/3.6) — `SyntheticSignalGenerator` → `MovementAnalyzer` → `MovementMetrics` — soll abgesichert sein, bevor UI und echte Sensorquellen (Kamera, Watch) daraufgesetzt werden. Task A aus dem Handoff-Brief.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGloveTests/MovementAnalyzerTests.swift` | NEW | 6 Tests: healthy-/parkinsonian-Metriken, Profil-Trennung, Determinismus, Edge Cases (leer/flach) |

Design-Entscheidungen:
- Swift Testing (`import Testing`, `#expect`) statt XCTest — konsistent mit dem bestehenden `vCRGloveTests`-Target (der Handoff-Brief nannte XCTest, das Repo nutzt aber Swift Testing).
- Keine Projektdatei-Änderung nötig: Xcode-Projekt nutzt filesystem-synchronisierte Gruppen (objectVersion 77), neue Dateien im Testordner werden automatisch Teil des Targets.
- Assertions folgen den Schwellwerten aus dem Handoff-Brief (§5 Task A): healthy > 3.5 Hz / CV < 0.1; parkinsonian < 3 Hz / CV > 0.2 / Slope < 0 / ≥ 1 Pause.
- Zusätzlich zum Brief: Separations-Test mit anderem Seed, Determinismus-Test, Edge-Case-Tests (leerer Input, flaches Signal → keine Phantom-Zyklen).

Verifikation:
- `xcodebuild test` (Schema `vCRGloveTests`, iPhone-17-Simulator, iOS 26.2): alle 6 Tests bestanden (Testplan führt sie doppelt aus → 12/12 grün).
- Build ohne Warnungen in den fünf Modul-Dateien.

Offene Punkte:
- [ ] Vorbestehende, modul-fremde Warnungen: leere `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription` in der `Info.plist`.
- [ ] Das Schema `vCRGlove` ist nicht für die Test-Action konfiguriert — Tests laufen nur über das Schema `vCRGloveTests`.

---

## 2026-07-07 · Movement Task Module: Aufnahme-Flow-UI (Task D)

Branch: main (lokal, uncommitted — kein Git-Commit gewünscht)  ·  Status: kompiliert (Simulator-Durchklick durch Olivia ausstehend)

Kontext: Patient:innen brauchen einen geführten Ablauf zum Aufnehmen eines Bewegungstests. Der Flow ist mit synthetischer Signalquelle vollständig im Simulator testbar; Kamera (Task B) und Watch (Task C) docken später an denselben `TrialRecorder` an, ohne dass der Flow sich ändert.

Dateien:
| Datei | Typ (NEW/MOD/DEL) | Zweck |
| --- | --- | --- |
| `vCRGlove/SyntheticCaptureSource.swift` | NEW | Spielt synthetisches Signal in Echtzeit (60 Hz Timer) in den `TrialRecorder`; Presets Healthy-like / Parkinsonian-like |
| `vCRGlove/MovementTaskView.swift` | NEW | Kompletter Flow: Setup → Countdown → Recording (Live-Fortschritt) → Result (Metriken, Save/Discard) |
| `vCRGlove/MainTabView.swift` | MOD | Neuer Tab „Movement" (SF Symbol `hand.tap.fill`) zwischen vCR und Journal |

Design-Entscheidungen:
- Flow als Phasen-State-Machine (`setup / countdown / recording / result`) in einer View — flacher Datei-Stil wie im restlichen Repo.
- Setup bietet beide Stoppbedingungen (10 Reps / 15 s) und den `StimulationContext` (Baseline/Pre/Post) an — Grundlage für die Vorher/Nachher-Trends in Task E.
- `patientID` wird aus dem bestehenden `@AppStorage("patientID")` der Settings übernommen (Fallback `"unset"`) — keine neue ID-Verwaltung, pseudonymisiert.
- Ergebnis zeigt die 7 kontinuierlichen Metriken; der Quality-Index als Gauge mit explizitem Disclaimer „not a validated UPDRS score" (Vorgabe aus dem Brief).
- Signal-Preset-Auswahl (healthy/parkinsonian) bewusst sichtbar im Setup, mit Footer-Hinweis, dass aktuell simuliert wird — verschwindet, sobald echte Quellen (B/C) da sind.
- Speichern erzeugt eine `MovementSession` mit einem Trial → `TaskSessionStore` (JSONL) + EventStore-Log; Trial-Start wird ebenfalls geloggt (`trial_started`).
- Aufräumen bei Tab-Wechsel: `onDisappear` stoppt Timer und Capture-Source.

Verifikation:
- `xcodebuild build` (Schema `vCRGlove`, iPhone-17-Simulator, iOS 26.2): Build erfolgreich, keine Warnungen in den neuen Dateien (angezeigte Warnungen sind vorbestehend in `GloveVM`/`VCRView`/`PatientVCRView`/`Info.plist`).
- Unit-Tests aus Task A weiterhin grün (Kern unverändert).

Offene Punkte:
- [ ] Manueller Simulator-Durchklick: beide Presets, beide Stopp-Modi, Save → Session landet in `Documents/vcr/tasks/sessions.jsonl`.
- [ ] Reps-Modus: Live-Zyklenzählung reanalysiert bei jedem Sample den ganzen Puffer — bei langen Aufnahmen ggf. drosseln (aktuell unkritisch bei ≤ 60 s).
- [ ] Task E: Trend-View aus `TaskSessionStore.history(task:side:)`.
- [ ] Tasks B/C: echte Signalquellen (Vision-Kamera, Watch-Gyroskop) an denselben Flow anschließen.
