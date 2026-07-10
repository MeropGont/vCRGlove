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
    init() {
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
            MainTabView()
        }
    }
}
