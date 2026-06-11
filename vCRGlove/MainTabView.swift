//
//  MainTabView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var gloveVM = GloveVM()
    @StateObject private var mappStore = ParkinsonMetadataStore.shared
    @AppStorage("showResearchTab") private var showResearchTab = false
    @AppStorage("patientID") private var patientID = ""
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.auto.rawValue
    @AppStorage("researchSettingsUnlocked") private var researchSettingsUnlocked = false
    @AppStorage("researchAutoLockEnabled") private var researchAutoLockEnabled = true
    @AppStorage("researchAutoLockDeadline") private var researchAutoLockDeadlineTimestamp = 0.0
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
        TimelineView(.periodic(from: Foundation.Date.now, by: 10)) { context in
            TabView {
                NavigationStack {
                    PatientVCRView(vm: gloveVM)
                }
                .tabItem {
                    Label("vCR", systemImage: "waveform.path.ecg")
                }

                if showResearchTab {
                    NavigationStack {
                        VCRView(vm: gloveVM)
                    }
                    .tabItem {
                        Label("Research", systemImage: "slider.horizontal.3")
                    }
                }

                NavigationStack {
                    JournalHomeView()
                }
                .tabItem {
                    Label("Journal", systemImage: "book.fill")
                }

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .badge(settingsTabBadge(at: context.date))
            }
        }
        .onAppear {
            syncPatientID()
        }
        .onChange(of: scenePhase) { _, newPhase in
            gloveVM.handleScenePhaseChange(newPhase)
        }
        .onChange(of: mappStore.activePatient?.id?.numericId()) { _, _ in
            syncPatientID()
        }
        .fullScreenCover(isPresented: needsPatientBinding) {
            NavigationStack {
                ProfileSettingsView(patientID: $patientID, requiresActivePatient: true)
            }
            .interactiveDismissDisabled(true)
        }
        .preferredColorScheme(AppAppearanceMode(rawValue: appearanceMode)?.colorScheme)
    }

    private var needsPatientBinding: Binding<Bool> {
        Binding(
            get: { mappStore.activePatient == nil },
            set: { _ in }
        )
    }

    private func settingsTabBadge(at date: Foundation.Date) -> String? {
        ResearchModeAccess.remainingMinutesBadge(
            unlocked: researchSettingsUnlocked,
            autoLockEnabled: researchAutoLockEnabled,
            autoLockDeadlineTimestamp: researchAutoLockDeadlineTimestamp,
            at: date
        )
    }

    private func syncPatientID() {
        patientID = mappStore.activePatient?.displayID ?? ""
    }
}

