//
//  MainTabView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var gloveVM = GloveVM()
    @StateObject private var mappStore = MappStorageStore.shared
    @AppStorage("showResearchTab") private var showResearchTab = false
    @AppStorage("patientID") private var patientID = ""
    @Environment(\.scenePhase) private var scenePhase


    var body: some View {
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
    }

    private var needsPatientBinding: Binding<Bool> {
        Binding(
            get: { mappStore.activePatient == nil },
            set: { _ in }
        )
    }

    private func syncPatientID() {
        patientID = mappStore.activePatient?.displayID ?? ""
    }
}

