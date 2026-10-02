//
//  vCRGloveApp.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.08.25.
//

import SwiftUI

#if os(iOS) && canImport(bhaptics_ios)
import bhaptics_ios
#endif

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case german = "de"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .english: return L10n("English")
        case .german:  return L10n("Deutsch")
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
        case .small:      return L10n("Small")
        case .standard:   return L10n("Standard")
        case .large:      return L10n("Large")
        case .extraLarge: return L10n("Extra Large")
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
    let language = AppSettings.shared.language.rawValue

    guard
        let path = Bundle.main.path(forResource: language, ofType: "lproj"),
        let languageBundle = Bundle(path: path)
    else {
        return key
    }

    return languageBundle.localizedString(
        forKey: key,
        value: key,
        table: nil
    )
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
        _ = PhoneWC.shared

        if let url = EventStore.shared.fileURL() {
            print("Event log file:", url.path)
        }

        ReminderScheduler.scheduleFromStoredSettings()

        // Backend upload is present in the merged files, but disabled until the
        // backend module is deliberately added to the Xcode target.
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(\.locale, Locale(identifier: appSettings.language.rawValue))
                .environment(\.dynamicTypeSize, appSettings.fontSize.dynamicTypeSize)
            .id(appSettings.language)
        }
    }
}
