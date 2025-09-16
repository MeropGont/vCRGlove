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
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
