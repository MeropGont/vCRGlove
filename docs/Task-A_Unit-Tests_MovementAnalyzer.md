# Movement Task Module — Task A: Unit-Tests der Analyse-Pipeline

> **Status:** ✅ Abgeschlossen — alle Tests bestanden (7. Juli 2026)
> **Datei:** `vCRGloveTests/MovementAnalyzerTests.swift`
> **Framework:** Swift Testing (`import Testing`, `#expect`) — konsistent mit dem bestehenden Test-Target
> **Branch/Umgebung:** lokal, iPhone-17-Simulator (iOS 26.2), Xcode-Schema `vCRGloveTests`

---

## Zweck

Task A des Movement-Task-Moduls (MDS-UPDRS-inspirierte Bewegungstests, Items 3.4/3.5/3.6) sichert den **sensor-unabhängigen Kern** der Analyse ab, bevor UI und echte Sensorquellen (Kamera, Apple Watch) daraufgesetzt werden:

```
SyntheticSignalGenerator ──▶ MovementAnalyzer ──▶ MovementMetrics
     (Fake-Signale)          (Peak-Detektion,      (5 UPDRS-Kriterien
                              Zyklus-Segmentierung)  + Rhythmus-CV)
```

Die Tests laufen **komplett im Simulator** — keine Kamera, keine Watch, kein Glove nötig. Der `SyntheticSignalGenerator` erzeugt deterministische Signale (seeded PRNG) mit zwei Presets:

| Preset | Frequenz | Decrement | Jitter | Pausen |
|---|---|---|---|---|
| `.healthy` | 4.5 Hz | 1 %/s | 3 % | keine |
| `.parkinsonian` | 2.2 Hz | 12 %/s | 18 % | 1 (bei 3.5 s) |

---

## Die 6 Tests im Detail

### 1. `healthySignalMetrics`
Prüft, dass ein gesundes Signal plausible Metriken liefert.

| Assertion | Klinische Bedeutung |
|---|---|
| `frequencyHz > 3.5` | Schnelles, gesundes Tapping |
| `rhythmCV < 0.1` | Gleichmäßiger Rhythmus |
| `pauseCount == 0` | Kein „Freezing" |
| `cycleCount > 10` | 8 s bei ~4.5 Hz → viele Zyklen erkannt |
| `meanAmplitude > 0` | Amplitude wird gemessen |

### 2. `parkinsonianSignalMetrics`
Prüft, dass ein bradykinetisches Signal korrekt charakterisiert wird.

| Assertion | Klinische Bedeutung (UPDRS-Kriterium) |
|---|---|
| `frequencyHz < 3` | Verlangsamung (Speed) |
| `rhythmCV > 0.2` | Unregelmäßiger Rhythmus (Hesitations) |
| `amplitudeDecrementSlope < 0` | Amplituden-Abnahme (Sequence Effect) |
| `pauseCount >= 1` | Injizierte Pause wird als Interruption erkannt |

### 3. `profilesSeparateCleanly`
Vergleicht beide Profile direkt (mit anderem Seed als Tests 1/2, um Seed-Abhängigkeit auszuschließen):
- Gesund ist **schneller** (`frequencyHz`)
- Gesund ist **rhythmischer** (`rhythmCV`)
- Gesund hat den **höheren `qualityIndex`**

→ Kernanforderung: die Pipeline trennt die beiden Populationen sauber.

### 4. `generatorIsDeterministic`
Gleicher Seed → bitidentisches Signal. Grundlage für reproduzierbare Tests und Debugging.

### 5. `emptyAndTinyInputsReturnEmptyMetrics`
Edge Case: leerer Input und Signale mit < 4 Samples liefern `MovementMetrics.empty` statt zu crashen oder Unsinn zu rechnen.

### 6. `flatSignalYieldsNoCycles`
Edge Case: ein konstantes Signal (Hand in Ruhe) erzeugt **keine Phantom-Zyklen** — `cycleCount == 0`, `frequencyHz == 0`, `pauseCount == 0`. Wichtig, weil die Peak-Detektion mit relativer Prominenz arbeitet (Anteil der Signalspanne) und bei reinem Rauschen nicht anschlagen darf.

---

## Ergebnis

- **12/12 Test-Läufe grün** (der Testplan führt jede Suite doppelt aus)
- **Keine Compiler-Warnungen** in den fünf Modul-Dateien (`MovementModels`, `MovementAnalyzer`, `SyntheticSignalGenerator`, `TrialRecorder`, `TaskSessionStore`)
- Zwei vorbestehende, modul-fremde Warnungen im Projekt: leere `NSBluetoothAlwaysUsageDescription` / `NSBluetoothPeripheralUsageDescription` in der `Info.plist`

## Tests selbst ausführen

In Xcode: `⌘U` mit Schema `vCRGloveTests`, oder im Terminal:

```bash
xcodebuild test -project vCRGlove.xcodeproj \
  -scheme vCRGloveTests \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:vCRGloveTests/MovementAnalyzerTests
```

## Einordnung & nächste Schritte

- Diese Tests validieren die **technische Korrektheit** der Pipeline gegen synthetische Signale — **nicht** die klinische Validität gegen echte UPDRS-Ratings (separater, späterer Schritt).
- Der `qualityIndex` ist eine Heuristik (0…1) für UI-Trends, **kein validierter UPDRS-Score**.
- Nächste Tasks: B (Kamera/Vision für 3.4 & 3.5), C (Watch-Gyroskop für 3.6), D (Aufnahme-UI), E (Trend-Charts), F (Sync & Export).
