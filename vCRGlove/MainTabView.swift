//
//  MainTabView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var gloveVM = GloveVM()
    @AppStorage("showResearchTab") private var showResearchTab = false
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
        TabView {
            NavigationStack {
                PatientVCRView(vm: gloveVM)
            }
            .tabItem {
                Label(L10n("vCR"), systemImage: "waveform.path.ecg")
            }

            if showResearchTab {
                NavigationStack {
                    VCRView(vm: gloveVM)
                }
                .tabItem {
                    Label(L10n("Research"), systemImage: "slider.horizontal.3")
                }
            }

            NavigationStack {
                MovementPlaceholderView()
            }
            .tabItem {
                Label(L10n("Movement"), systemImage: "hand.tap.fill")
            }

            NavigationStack {
                JournalHomeView()
            }
            .tabItem {
                Label(L10n("Journal"), systemImage: "book.fill")
            }

            NavigationStack {
                SettingsView(vm: gloveVM)
            }
            .tabItem {
                Label(L10n("Settings"), systemImage: "gearshape.fill")
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            gloveVM.handleScenePhaseChange(newPhase)
        }
    }
}

private struct MovementPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)

            Text(L10n("Movement tasks are being reviewed."))
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
