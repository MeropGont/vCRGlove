//
//  MainTabView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                VCRView()
            }
            .tabItem {
                Label("vCR", systemImage: "waveform.path.ecg")
            }

            NavigationStack {
                JournalHomeView()
            }
            .tabItem {
                Label("Journal", systemImage: "book.fill")
            }
        }
    }
}
