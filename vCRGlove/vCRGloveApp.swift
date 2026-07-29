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
