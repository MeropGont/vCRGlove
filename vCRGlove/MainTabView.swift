//
//  MainTabView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var gloveVM = GloveVM()

    var body: some View {
        TabView {
            NavigationStack {
                PatientVCRView(vm: gloveVM)
            }
            .tabItem {
                Label("vCR", systemImage: "waveform.path.ecg")
            }

            NavigationStack {
                VCRView(vm: gloveVM)
            }
            .tabItem {
                Label("Research", systemImage: "slider.horizontal.3")
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
