//
//  MainTabView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct MainTabView: View {
    enum Tab: Hashable {
        case vcr, journal, movement, settings
    }

    @ObservedObject var gloveVM: GloveVM
    @Binding var selectedTab: Tab
    @Binding var settingsPath: [SettingsRoute]
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PatientVCRView(vm: gloveVM)
            }
            .tabItem {
                Label(L10n("vCR"), systemImage: "waveform.path.ecg")
            }
            .tag(Tab.vcr)

            NavigationStack {
                JournalHomeView()
            }
            .tabItem {
                Label(L10n("Journal"), systemImage: "book.fill")
            }
            .tag(Tab.journal)

            NavigationStack {
                MovementSessionFlowView()
            }
            .tabItem {
                Label(L10n("Movement"), systemImage: "hand.tap.fill")
            }
            .tag(Tab.movement)

            NavigationStack(path: $settingsPath) {
                SettingsView(vm: gloveVM)
            }
            .tabItem {
                Label(L10n("Settings"), systemImage: "gearshape.fill")
            }
            .tag(Tab.settings)
        }
        .environment(\.studyExportBlocked, gloveVM.hasStimulationSession)
        .environment(\.routineAcknowledgementsAllowed, selectedTab == .journal && !gloveVM.hasStimulationSession)
        .onChange(of: scenePhase) { _, newPhase in
            gloveVM.handleScenePhaseChange(newPhase)
            if newPhase == .active { ReminderScheduler.scheduleFromStoredSettings() }
        }
    }
}
