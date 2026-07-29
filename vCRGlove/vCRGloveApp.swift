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

/// In-app dictionary for the English → German language switch. The Bundle
/// swizzle below intercepts every `NSLocalizedString`/`LocalizedStringKey`
/// lookup and checks here first. The key is the original English string.
let Translations: [String: [String: String]] = [:]

// MARK: - Bundle swizzling for in-app language switch

import ObjectiveC

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
