//
//  vCRGloveApp.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.08.25.
//

import SwiftUI
import ObjectiveC

#if os(iOS) && canImport(bhaptics_ios)
import bhaptics_ios
#endif

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .english: return "English"
        case .german:  return "Deutsch"
        }
    }
}

enum AppFontSize: String, CaseIterable, Identifiable {
    case small, standard, large, extraLarge

    var id: String { rawValue }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small:       return .small
        case .standard:    return .large
        case .large:       return .xxLarge
        case .extraLarge:  return .accessibility3
        }
    }

    var displayName: String {
        switch self {
        case .small:      return "Small"
        case .standard:   return "Standard"
        case .large:      return "Large"
        case .extraLarge: return "Extra Large"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "en") ?? .english {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    @Published var fontSize: AppFontSize = AppFontSize(rawValue: UserDefaults.standard.string(forKey: "appFontSize") ?? "standard") ?? .standard {
        didSet { UserDefaults.standard.set(fontSize.rawValue, forKey: "appFontSize") }
    }
}

/// Translate a string at runtime through the Bundle swizzle.
/// Use this when a string is stored in a variable rather than a literal.
func L10n(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// In-app dictionary for the English ↔ German language switch. The Bundle
/// swizzle below intercepts `NSLocalizedString`/`LocalizedStringKey` lookups.
/// The key is the source string currently shown in the code.
let Translations: [String: [String: String]] = [
    // MainTabView
    "vCR": ["de": "vCR"],
    "Research": ["de": "Forschung"],
    "Movement": ["de": "Bewegung"],
    "Journal": ["de": "Tagebuch"],
    "Settings": ["de": "Einstellungen"],

    // SettingsView
    "Profile": ["de": "Profil"],
    "Language": ["de": "Sprache"],
    "Font Size": ["de": "Schriftgröße"],
    "vCR Settings": ["de": "vCR Einstellungen"],
    "Reminders": ["de": "Erinnerungen"],
    "Privacy & Data": ["de": "Datenschutz & Daten"],
    "Instructions": ["de": "Anleitungen"],
    "Research Mode": ["de": "Forschungsmodus"],
    "Need Help?": ["de": "Hilfe nötig?"],
    "Troubleshooting": ["de": "Fehlerbehebung"],
    "Incorrect password": ["de": "Falsches Passwort"],
    "Default duration": ["de": "Standarddauer"],
    "Glove status and last connection time will go here.": ["de": "Handschuhstatus und letzte Verbindung werden hier angezeigt."],
    "Avatar selection will go here.": ["de": "Avatar-Auswahl wird hier angezeigt."],
    "vCR reminders": ["de": "vCR-Erinnerungen"],
    "Journal reminders": ["de": "Tagebuch-Erinnerungen"],
    "Task reminders": ["de": "Aufgaben-Erinnerungen"],
    "Quiet hours": ["de": "Ruhezeiten"],
    "Stored data": ["de": "Gespeicherte Daten"],
    "Permissions": ["de": "Berechtigungen"],
    "Storage status": ["de": "Speicherstatus"],
    "Backup status": ["de": "Backup-Status"],
    "Gloves": ["de": "Handschuhe"],
    "vCR session": ["de": "vCR-Sitzung"],
    "Journal": ["de": "Tagebuch"],
    "Future movement tasks": ["de": "Zukünftige Bewegungsaufgaben"],
    "Study start date": ["de": "Studienstartdatum"],
    "Patient notes": ["de": "Patientennotizen"],
    "Movement task export": ["de": "Bewegungsaufgaben exportieren"],
    "Export logs": ["de": "Protokolle exportieren"],
    "Sync data": ["de": "Daten synchronisieren"],
    "Storage size": ["de": "Speichergröße"],
    "Latest backup": ["de": "Letztes Backup"],
    "Bluetooth diagnostics": ["de": "Bluetooth-Diagnose"],
    "App version": ["de": "App-Version"],
    "Device version": ["de": "Geräteversion"],
    "Please contact support and briefly describe what was not working.": ["de": "Bitte kontaktieren Sie den Support und beschreiben Sie kurz, was nicht funktioniert hat."],
    "If the steps above did not solve the issue, contact ICNS support.": ["de": "Wenn die obigen Schritte das Problem nicht gelöst haben, kontaktieren Sie den ICNS-Support."],
    "ICNS": ["de": "ICNS"],

    // MovementTaskView single / flow
    "Task": ["de": "Aufgabe"],
    "Movement": ["de": "Bewegung"],
    "Hand": ["de": "Hand"],
    "Left": ["de": "Links"],
    "Right": ["de": "Rechts"],
    "Sensor": ["de": "Sensor"],
    "Calibration": ["de": "Kalibrierung"],
    "This task uses the front camera to track your hand. No video is stored — only movement measurements.": ["de": "Diese Aufgabe nutzt die Frontkamera, um Ihre Hand zu verfolgen. Es wird kein Video gespeichert – nur Bewegungsmesswerte."],
    "Wear the watch on the tested arm and keep the vCRGlove watch app open during the recording.": ["de": "Tragen Sie die Uhr am getesteten Arm und halten Sie die vCRGlove Watch-App während der Aufnahme geöffnet."],
    "Hand scale calibrated": ["de": "Handgröße kalibriert"],
    "Recalibrate": ["de": "Neu kalibrieren"],
    "Calibrate hand size": ["de": "Handgröße kalibrieren"],
    "Start": ["de": "Start"],
    "Stop": ["de": "Stopp"],
    "Analysing movement…": ["de": "Bewegung wird analysiert…"],
    "Recording…": ["de": "Aufnahme…"],
    "Waiting for signal…": ["de": "Warte auf Signal…"],
    "Keep your whole hand in the frame!": ["de": "Halten Sie die ganze Hand im Bild!"],
    "Trial": ["de": "Versuch"],
    "Metrics": ["de": "Kennzahlen"],
    "These values describe this recording only. They are not a clinical rating.": ["de": "Diese Werte beschreiben nur diese Aufnahme. Sie sind keine klinische Bewertung."],
    "Movement quality (heuristic)": ["de": "Bewegungsqualität (heuristisch)"],
    "Heuristic 0–1 index for personal trends — not a validated UPDRS score.": ["de": "Heuristischer 0–1-Index für persönliche Trends – kein validierter UPDRS-Wert."],
    "Trends": ["de": "Trends"],
    "Movement Test": ["de": "Bewegungstest"],
    "Movement Session": ["de": "Bewegungssitzung"],
    "We will guide you through 6 short hand recordings. It takes about 2 minutes.": ["de": "Wir führen Sie durch 6 kurze Handaufnahmen. Es dauert etwa 2 Minuten."],
    "Hand scale not yet calibrated. Calibrate once for more accurate measurements.": ["de": "Handgröße noch nicht kalibriert. Kalibrieren Sie einmal für genauere Messungen."],
    "When is this measurement?": ["de": "Wann ist diese Messung?"],
    "Pick the context once. All 6 recordings of this session will be tagged the same way.": ["de": "Wählen Sie den Kontext einmal aus. Alle 6 Aufnahmen dieser Sitzung werden gleich gekennzeichnet."],
    "Bitte führen Sie die Bewegung so schnell und so weit wie möglich aus.": ["de": "Bitte führen Sie die Bewegung so schnell und so weit wie möglich aus.", "en": "Please perform the movement as fast and as far as possible."],
    "Hold your hand in front of the camera so it fills the frame.": ["de": "Halten Sie Ihre Hand vor die Kamera, sodass sie das Bild ausfüllt."],
    "Wear the watch on your \(step.side.rawValue) arm and keep the watch app open.": ["de": "Tragen Sie die Uhr am \(step.side.rawValue) Arm und halten Sie die Watch-App geöffnet."],
    "Start Recording": ["de": "Aufnahme starten"],
    "Skip this measurement": ["de": "Diese Messung überspringen"],
    "All done!": ["de": "Fertig!"],
    "\(trials.count) recordings are ready to be saved as one session.": ["de": "\(trials.count) Aufnahmen können als eine Sitzung gespeichert werden."],
    "Save Session": ["de": "Sitzung speichern"],
    "Hand calibration": ["de": "Handkalibrierung"],
    "Hold your hand steady in front of the camera for 2 seconds.": ["de": "Halten Sie die Hand 2 Sekunden lang ruhig vor der Kamera."],
    "Calibrating…": ["de": "Kalibriere…"],
    "Done": ["de": "Fertig"],
    "Starting camera…": ["de": "Kamera wird gestartet…"],
    "Coming soon": ["de": "Demnächst verfügbar"],
    "Instruction video for \(taskType.displayName)": ["de": "Anleitungsvideo für \(taskType.displayName)"],

    // OnboardingView
    "Überspringen": ["de": "Überspringen", "en": "Skip"],
    "Weiter": ["de": "Weiter", "en": "Continue"],
    "App starten": ["de": "App starten", "en": "Start app"],
    "Willkommen bei vCRGlove": ["de": "Willkommen bei vCRGlove", "en": "Welcome to vCRGlove"],
    "Diese App hilft Ihnen, Ihre Bewegungen und Ihr Befinden rund um die vCR-Therapie zu dokumentieren. Alles geschieht Schritt für Schritt.": ["de": "Diese App hilft Ihnen, Ihre Bewegungen und Ihr Befinden rund um die vCR-Therapie zu dokumentieren. Alles geschieht Schritt für Schritt.", "en": "This app helps you document your movements and well-being around vCR therapy. Everything happens step by step."],
    "1. Tägliches Journal": ["de": "1. Tägliches Journal", "en": "1. Daily Journal"],
    "Jeden Tag können Sie einchecken: Stimmung, Symptome, Medikamente und Notizen. Das Journal hilft Ihnen und Ihrem Arzt, Verläufe zu erkennen.": ["de": "Jeden Tag können Sie einchecken: Stimmung, Symptome, Medikamente und Notizen. Das Journal hilft Ihnen und Ihrem Arzt, Verläufe zu erkennen.", "en": "Every day you can check in: mood, symptoms, medications and notes. The journal helps you and your doctor recognize trends."],
    "2. vCR-Sitzungen": ["de": "2. vCR-Sitzungen", "en": "2. vCR Sessions"],
    "Unter „vCR“ starten Sie Ihre Vibrations-Therapie. Die App leitet Sie durch die Sitzung und merkt sich, wann Sie eine Behandlung hatten.": ["de": "Unter „vCR“ starten Sie Ihre Vibrations-Therapie. Die App leitet Sie durch die Sitzung und merkt sich, wann Sie eine Behandlung hatten.", "en": "Under “vCR” you start your vibration therapy. The app guides you through the session and remembers when you had a treatment."],
    "3. Bewegungstests": ["de": "3. Bewegungstests", "en": "3. Movement Tests"],
    "Unter „Movement“ finden Sie geführte Tests: Finger-Tippen, Hand öffnen/schließen und Unterarm drehen. Jeder Test dauert 30 Sekunden. Führen Sie die Bewegung so schnell und so weit wie möglich aus.": ["de": "Unter „Movement“ finden Sie geführte Tests: Finger-Tippen, Hand öffnen/schließen und Unterarm drehen. Jeder Test dauert 30 Sekunden. Führen Sie die Bewegung so schnell und so weit wie möglich aus.", "en": "Under “Movement” you will find guided tests: finger tapping, hand opening/closing and forearm rotation. Each test takes 30 seconds. Perform the movement as fast and as far as possible."],
    "So funktioniert die Aufnahme": ["de": "So funktioniert die Aufnahme", "en": "How Recording Works"],
    "Wählen Sie den passenden Kontext (z. B. vor oder nach der vCR-Sitzung), drücken Sie Start und folgen Sie der Anleitung. Für manche Tests wird die Kamera verwendet, für andere die Apple Watch.": ["de": "Wählen Sie den passenden Kontext (z. B. vor oder nach der vCR-Sitzung), drücken Sie Start und folgen Sie der Anleitung. Für manche Tests wird die Kamera verwendet, für andere die Apple Watch.", "en": "Select the appropriate context (e.g., before or after the vCR session), press Start and follow the instructions. Some tests use the camera, others the Apple Watch."],
    "4. Kalender": ["de": "4. Kalender", "en": "4. Calendar"],
    "Im Kalender sehen Sie auf einen Blick, an welchen Tagen Sie ein Journal geschrieben oder einen Bewegungstest gemacht haben. Ein dunkelgrüner Kreis bedeutet: An diesem Tag gibt es Messdaten.": ["de": "Im Kalender sehen Sie auf einen Blick, an welchen Tagen Sie ein Journal geschrieben oder einen Bewegungstest gemacht haben. Ein dunkelgrüner Kreis bedeutet: An diesem Tag gibt es Messdaten.", "en": "In the calendar you can see at a glance on which days you wrote a journal or did a movement test. A dark green circle means: There is measurement data on this day."],
    "5. Einstellungen & Export": ["de": "5. Einstellungen & Export", "en": "5. Settings & Export"],
    "Unter „Settings“ tragen Sie Ihre Patienten-ID ein und können Ihre Daten sicher exportieren. Ihre Daten werden pseudonymisiert gespeichert.": ["de": "Unter „Settings“ tragen Sie Ihre Patienten-ID ein und können Ihre Daten sicher exportieren. Ihre Daten werden pseudonymisiert gespeichert.", "en": "Under “Settings” you enter your patient ID and can export your data securely. Your data is stored pseudonymized."],
    "Bereit?": ["de": "Bereit?", "en": "Ready?"],
    "Drücken Sie auf „App starten“. Sie können dieses Tutorial nicht erneut ansehen, aber alle Funktionen finden Sie jederzeit in den einzelnen Tabs.": ["de": "Drücken Sie auf „App starten“. Sie können dieses Tutorial nicht erneut ansehen, aber alle Funktionen finden Sie jederzeit in den einzelnen Tabs.", "en": "Press “Start app”. You cannot view this tutorial again, but you can find all functions in the individual tabs at any time."],

    // JournalHomeView
    "Journal": ["de": "Tagebuch"],
    "Track daily symptoms, mood, and notes around your vCR sessions.": ["de": "Verfolgen Sie tägliche Symptome, Stimmung und Notizen zu Ihren vCR-Sitzungen."],
    "Daily Check-In": ["de": "Tägliche Abfrage"],
    "How are you today?": ["de": "Wie geht es Ihnen heute?"],
    "OPEN TODAY'S LOG": ["de": "HEUTIGEN EINTRAG ÖFFNEN"],
    "Last check-in": ["de": "Letzter Eintrag"],
    "Your most recent check-in will appear here.": ["de": "Ihr letzter Eintrag wird hier angezeigt."],

    // Movement task instructions
    "Tap your index finger on your thumb as fast and as big as possible.": ["de": "Tippen Sie mit dem Zeigefinger auf den Daumen so schnell und so groß wie möglich."],
    "Open and close your fist as fast and as fully as possible.": ["de": "Öffnen und schließen Sie die Faust so schnell und so weit wie möglich."],
    "Rotate your forearm palm-up / palm-down as fast and as fully as possible.": ["de": "Drehen Sie den Unterarm Handfläche-oben / Handfläche-unten so schnell und so weit wie möglich."],

    // Movement task display names / context
    "Finger Tapping": ["de": "Finger-Tapping"],
    "Hand Open/Close": ["de": "Hand öffnen/schließen"],
    "Pronation/Supination": ["de": "Pronation/Supination"],
    "Cancel": ["de": "Abbrechen"],
    "Result": ["de": "Ergebnis"],
    "Save": ["de": "Speichern"],
    "Use & Finish": ["de": "Übernehmen & Beenden"],
    "Use & Continue": ["de": "Übernehmen & Weiter"],
    "Discard": ["de": "Verwerfen"],
    "Retake": ["de": "Wiederholen"],

    // Hand side helpers
    "Left hand": ["de": "Linke Hand"],
    "Right hand": ["de": "Rechte Hand"],
    "Wear the watch on your left arm and keep the watch app open.": ["de": "Tragen Sie die Uhr am linken Arm und halten Sie die Watch-App geöffnet."],
    "Wear the watch on your right arm and keep the watch app open.": ["de": "Tragen Sie die Uhr am rechten Arm und halten Sie die Watch-App geöffnet."],

    // Recording context labels
    "Baseline (before any stimulation)": ["de": "Baseline (vor jeder Stimulation)"],
    "Before session": ["de": "Vor der Sitzung"],
    "After session": ["de": "Nach der Sitzung"],
    "Not specified": ["de": "Nicht angegeben"],
    "Baseline": ["de": "Baseline"],
    "Before stimulation": ["de": "Vor der Stimulation"],
    "After stimulation": ["de": "Nach der Stimulation"],
    "No stimulation yet today": ["de": "Heute noch keine Stimulation"],
    "Before your vCR / medication session": ["de": "Vor Ihrer vCR-/Medikamenten-Sitzung"],
    "After your vCR / medication session": ["de": "Nach Ihrer vCR-/Medikamenten-Sitzung"],
    "Use when none of the above applies": ["de": "Verwenden, wenn nichts anderes zutrifft"],
    "Step %d of %d": ["de": "Schritt %d von %d"],
    "%d / %d repetitions": ["de": "%d / %d Wiederholungen"],
    "%.1f / %.0f s": ["de": "%.1f / %.0f s"],
    "%d recordings are ready to be saved as one session.": ["de": "%d Aufnahmen können als eine Sitzung gespeichert werden."],
    "Recordings": ["de": "Aufnahmen"],

    // Body side
    "Left": ["de": "Links"],
    "Right": ["de": "Rechts"],
    "left": ["de": "linke"],
    "right": ["de": "rechte"],

    // Setup / form
    "Task": ["de": "Aufgabe"],
    "Protocol": ["de": "Protokoll"],
    "Context": ["de": "Kontext"],
    "Calibration": ["de": "Kalibrierung"],
    "Sensor": ["de": "Sensor"],
    "Movement": ["de": "Bewegung"],
    "Hand": ["de": "Hand"],
    "Relative to stimulation": ["de": "Relativ zur Stimulation"],
    "Stop after": ["de": "Stoppen nach"],
    "10 repetitions": ["de": "10 Wiederholungen"],
    "This task uses the front camera to track your hand. No video is stored — only movement measurements.": ["de": "Diese Aufgabe verwendet die Frontkamera, um Ihre Hand zu verfolgen. Es wird kein Video gespeichert — nur Bewegungsmessungen."],
    "Wear the watch on the tested arm and keep the vCRGlove watch app open during the recording.": ["de": "Tragen Sie die Uhr am getesteten Arm und halten Sie die vCRGlove Watch-App während der Aufnahme geöffnet."],
    "Hand scale calibrated": ["de": "Handmaßstab kalibriert"],
    "Recalibrate": ["de": "Neu kalibrieren"],
    "Calibrate hand size": ["de": "Handgröße kalibrieren"],
    "Start": ["de": "Start"],

    // Countdown / recording
    "Analysing movement…": ["de": "Bewegung wird analysiert…"],
    "Recording…": ["de": "Aufnahme läuft…"],
    "Place your %@ hand here": ["de": "Halten Sie Ihre %@ Hand hierher"],

    // Result
    "Trial": ["de": "Messung"],
    "Metrics": ["de": "Kennzahlen"],
    "These values describe this recording only. They are not a clinical rating.": ["de": "Diese Werte beschreiben nur diese Aufnahme. Sie sind keine klinische Bewertung."],
    "Movement quality (heuristic)": ["de": "Bewegungsqualität (heuristisch)"],
    "Heuristic 0–1 index for personal trends — not a validated UPDRS score.": ["de": "Heuristischer 0–1-Index für persönliche Trends — kein validierter UPDRS-Score."],
    "Speed": ["de": "Geschwindigkeit"],
    "Amplitude": ["de": "Amplitude"],
    "Mean amplitude": ["de": "Mittlere Amplitude"],
    "Cycles": ["de": "Zyklen"],
    "%.2f Hz": ["de": "%.2f Hz"],
    "%.3f": ["de": "%.3f"],
    "%.3f /cycle": ["de": "%.3f /Zyklus"],
    "%.2f": ["de": "%.2f"],
    "%.2f s": ["de": "%.2f s"],

    // Session flow
    "Movement Test": ["de": "Bewegungstest"],
    "Movement Session": ["de": "Bewegungssitzung"],
    "We will guide you through 6 short hand recordings. It takes about 2 minutes.": ["de": "Wir führen Sie durch 6 kurze Handaufnahmen. Es dauert etwa 2 Minuten."],
    "Tap index finger on thumb": ["de": "Zeigefinger auf Daumen tippen"],
    "Open and close your fist": ["de": "Faust öffnen und schließen"],
    "Rotate forearm palm-up / palm-down": ["de": "Unterarm Handfläche-oben/unten drehen"],
    "When is this measurement?": ["de": "Wann ist diese Messung?"],
    "Pick the context once. All 6 recordings of this session will be tagged the same way.": ["de": "Wählen Sie den Kontext einmal. Alle 6 Aufnahmen dieser Sitzung werden gleich markiert."],
    "Please perform the movement as fast and as far as possible.": ["de": "Bitte führen Sie die Bewegung so schnell und so weit wie möglich aus."],
    "Hold your hand in front of the camera so it fills the frame.": ["de": "Halten Sie Ihre Hand vor die Kamera, sodass sie das Bild ausfüllt."],
    "Skip this measurement": ["de": "Diese Messung überspringen"],

    // Summary
    "All done!": ["de": "Fertig!"],
    "Save Session": ["de": "Sitzung speichern"],
    "Start over": ["de": "Neu starten"],

    // Placeholder / calibration
    "Instruction video for %@": ["de": "Anleitungsvideo für %@"],
    "Coming soon": ["de": "Demnächst verfügbar"],
    "Hand calibration": ["de": "Handkalibrierung"],
    "Hold your hand steady in front of the camera for 2 seconds.": ["de": "Halten Sie Ihre Hand 2 Sekunden ruhig vor die Kamera."],
    "Calibrating…": ["de": "Kalibriere…"],
    "Done": ["de": "Fertig"],
    "Starting camera…": ["de": "Kamera wird gestartet…"],

    // Camera / watch hints
    "Watch connected — receiving motion": ["de": "Uhr verbunden — Bewegung empfangen"],
    "Waiting for watch… open the watch app": ["de": "Warte auf Uhr… öffnen Sie die Watch-App"],
    "Keep your whole hand in the frame!": ["de": "Halten Sie die ganze Hand im Bild!"],
    "Waiting for signal…": ["de": "Warte auf Signal…"],

    // Glove status
    "Ready": ["de": "Bereit"],
    "Detected": ["de": "Erkannt"],
    "Disconnected": ["de": "Getrennt"],
    "Not detected": ["de": "Nicht erkannt"],
    "Stimulating": ["de": "Stimulation läuft"],

    // MovementTrendView
    "Amplitude decrement": ["de": "Amplitudenabfall"],
    "Rhythm variability": ["de": "Rhythmusvariabilität"],
    "Onset latency": ["de": "Anflutzeit"],
    "Quality index": ["de": "Qualitätsindex"],
    "%@ over time": ["de": "%@ über die Zeit"],
    "Higher values indicate faster/larger movement.": ["de": "Höhere Werte bedeuten schnellere oder größere Bewegungen."],
    "Lower values indicate steadier movement.": ["de": "Niedrigere Werte bedeuten gleichmäßigere Bewegungen."],
    "No recordings yet": ["de": "Noch keine Aufnahmen"],
    "Unspecified": ["de": "Nicht angegeben"],

    // Journal / log views
    "Daily Check-In": ["de": "Tägliche Abfrage"],
    "How are you today?": ["de": "Wie geht es Ihnen heute?"],
    "Overall symptom intensity": ["de": "Gesamtsymptomstärke"],
    "Which symptoms are present?": ["de": "Welche Symptome sind vorhanden?"],
    "Save Check-In": ["de": "Check-In speichern"],
    "Check-In": ["de": "Check-In"],
    "Medication": ["de": "Medikation"],
    "Time": ["de": "Uhrzeit"],
    "What happened?": ["de": "Was ist passiert?"],
    "How are you right now?": ["de": "Wie geht es Ihnen gerade?"],
    "Anything that may affect it?": ["de": "Etwas, das es beeinflussen könnte?"],
    "Optional note": ["de": "Optionale Notiz"],
    "Save Medication Log": ["de": "Medikation speichern"],
    "Symptom Episode": ["de": "Symptom-Episode"],
    "Medication state": ["de": "Medikamentenstatus"],
    "Add details": ["de": "Details hinzufügen"],
    "Save Symptom Episode": ["de": "Symptom-Episode speichern"],
    "Symptom": ["de": "Symptom"],

    // Mood and severity
    "Very Bad": ["de": "Sehr schlecht"],
    "Bad": ["de": "Schlecht"],
    "Neutral": ["de": "Neutral"],
    "Good": ["de": "Gut"],
    "Very Good": ["de": "Sehr gut"],
    "Not present": ["de": "Nicht vorhanden"],
    "Mild": ["de": "Mild"],
    "Moderate": ["de": "Mäßig"],
    "Severe": ["de": "Schwer"],

    // Symptoms
    "Tremor": ["de": "Tremor"],
    "Stiffness": ["de": "Steifigkeit"],
    "Slowness": ["de": "Langsamkeit"],
    "Freezing": ["de": "Freezing"],
    "Balance": ["de": "Gleichgewicht"],
    "Swallowing": ["de": "Schlucken"],
    "Cramps": ["de": "Krämpfe"],
    "Fatigue": ["de": "Müdigkeit"],
    "Sleep": ["de": "Schlaf"],
    "Concentration": ["de": "Konzentration"],
    "Low Mood": ["de": "Niedergeschlagenheit"],
    "Anxiety": ["de": "Angst"],
    "Dizziness": ["de": "Schwindel"],
    "Pain": ["de": "Schmerzen"],
    "Walking difficulty": ["de": "Schwierigkeiten beim Gehen"],
    "Balance problems": ["de": "Gleichgewichtsprobleme"],
    "Dyskinesia": ["de": "Dyskinesie"],

    // Medication / motor states
    "Took usual medication": ["de": "Medikamente wie üblich eingenommen"],
    "Took medication late": ["de": "Medikamente verspätet eingenommen"],
    "Missed medication": ["de": "Medikamente vergessen"],
    "Took extra/rescue medication": ["de": "Extra-/Rettungsmedikament eingenommen"],
    "ON / medication working": ["de": "ON / Medikament wirkt"],
    "OFF / symptoms are back": ["de": "OFF / Symptome sind zurück"],
    "Dyskinesia / too much movement": ["de": "Dyskinesie / zu viel Bewegung"],
    "Not sure": ["de": "Unsicher"],

    // Medication factors
    "With food": ["de": "Mit Essen"],
    "High-protein meal": ["de": "Eiweißreiche Mahlzeit"],
    "Stress": ["de": "Stress"],
    "Poor sleep": ["de": "Schlechter Schlaf"],
    "Constipation": ["de": "Verstopfung"],
    "Exercise/activity": ["de": "Bewegung/Aktivität"],

    // Symptom episode types
    "OFF episode": ["de": "OFF-Phase"],
    "Fall / near fall": ["de": "Sturz / beinahe gestürzt"],
    "Tremor episode": ["de": "Tremor-Episode"],
    "Anxiety / panic": ["de": "Angst / Panik"],
    "Device issue": ["de": "Geräteproblem"],
]

// MARK: - Bundle swizzling for in-app language switch

extension Bundle {
    private static var _language: String?

    static var currentLanguage: String {
        get { _language ?? AppSettings.shared.language.rawValue }
        set { _language = newValue }
    }

    @objc dynamic func vcr_localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let translation = Translations[key]?[Bundle.currentLanguage] {
            return translation
        }
        return self.vcr_localizedString(forKey: key, value: value, table: tableName)
    }

    static func swizzleLocalization() {
        let originalSelector = #selector(Bundle.localizedString(forKey:value:table:))
        let swizzledSelector = #selector(Bundle.vcr_localizedString(forKey:value:table:))
        guard let originalMethod = class_getInstanceMethod(Bundle.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(Bundle.self, swizzledSelector) else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }
}

enum Haptics {
    static func play(_ pattern: String) {
        #if os(iOS) && canImport(bhaptics_ios)
        // real bHaptics calls here
        #else
        // watchOS: no-op
        #endif
    }
}


@main
struct vCRGloveApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @StateObject private var appSettings = AppSettings.shared

    init() {
        Bundle.swizzleLocalization()
        _ = PhoneWC.shared

        if let url = EventStore.shared.fileURL() {
            print("Event log file:", url.path)
        }

        // ── UKE Backend Upload ────────────────────────────────────────────────
        // Replace the URL and API key with the values provided by the UKE backend
        // team before distributing the app to patients.
        // Set to nil / remove these two lines to disable automatic upload.
        // For local testing use "http://localhost:8000".
        // For production replace with the UKE server URL and real API key.
        if let backendURL = URL(string: "http://localhost:8000") {
            SessionUploader.shared.configure(baseURL: backendURL,
                                             apiKey: "REPLACE_WITH_UKE_API_KEY")
        }
        // ─────────────────────────────────────────────────────────────────────
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasSeenOnboarding {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            }
            .environment(\.dynamicTypeSize, appSettings.fontSize.dynamicTypeSize)
            .id(appSettings.language)
        }
    }
}
