//
//  ResearchSettingsView.swift
//  vCRGlove
//
//  Created by Alexander Wiederhold on 05/06/2026.
//

import SwiftUI
import UIKit
import Foundation
import ParkinsonMetadata

// ---------------------------------------------------------------------
// MARK: Research Settings UI
// ---------------------------------------------------------------------
struct ResearchSettingsView: View {
    let patientID: String

    @AppStorage("patientID") private var storedPatientID = ""
    @AppStorage("showResearchTab") private var showResearchTab = false
    @AppStorage("researchSettingsUnlocked") private var persistedResearchUnlocked = false
    @AppStorage("researchAutoLockEnabled") private var autoLockEnabled = true
    @AppStorage("researchTabAutoTurnOff") private var researchTabAutoTurnOff = true
    @AppStorage("researchAutoLockMinutes") private var autoLockMinutes = 30
    @AppStorage("researchAutoLockDeadline") private var autoLockDeadlineTimestamp = 0.0
    @AppStorage("researchSuccessfulLoginCount") private var successfulLoginCount = 0
    @AppStorage("researchFailedLoginCount") private var failedLoginCount = 0
    @StateObject private var vm = ExportSettingsViewModel()
    @State private var sharePackage: ExportSharePackage?
    @State private var researchPassword = ""
    @State private var researchUnlocked = false
    @State private var passwordError = false
    @State private var autoLockDeadline: Foundation.Date?
    @State private var autoLockTask: Task<Void, Never>?

    private let researchPasswordValue = "vcr2026"
    private let autoLockOptions = [1, 5, 10, 15, 30, 60]

    var body: some View {
        List {
            Section("Research Mode") {
                if researchUnlocked {
                    Toggle("Auto-lock", isOn: $autoLockEnabled)

                    if autoLockEnabled {
                        Picker("Auto-lock after", selection: $autoLockMinutes) {
                            ForEach(autoLockOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }

                        TimelineView(.periodic(from: Foundation.Date.now, by: 1)) { context in
                            Text(remainingAutoLockText(at: context.date))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("Auto-lock is off.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(role: .destructive) {
                        lockResearchMode()
                    } label: {
                        Label("Lock Now", systemImage: "lock.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 10))
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } else {
                    SecureField("Password", text: $researchPassword)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                        .onSubmit(unlockResearchMode)

                    Button("Unlock Research Mode") {
                        unlockResearchMode()
                    }

                    if passwordError {
                        Text("Incorrect password")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if researchUnlocked {
                Section("General") {
                    Toggle("Show Research Tab", isOn: $showResearchTab)

                    if showResearchTab {
                        Toggle("Auto-turn-off", isOn: $researchTabAutoTurnOff)
                    }

                    NavigationLink {
                        ProfileSettingsView(patientID: $storedPatientID)
                    } label: {
                        SettingsRow(icon: "person.crop.circle", color: .purple, title: "Profile", subtitle: "Pseudonym in Study, Soarian Case ID, and patient details")
                    }

                    NavigationLink {
                        ResearchStudiesView()
                    } label: {
                        SettingsRow(icon: "doc.text.magnifyingglass", color: .orange, title: "Studies", subtitle: "Study design, cohorts, and identifier schemes")
                    }

                    NavigationLink {
                        ResearchAdminSettingsView(patientID: patientID)
                    } label: {
                        SettingsRow(icon: "slider.horizontal.3", color: .indigo, title: "Research Admin", subtitle: "Logs, exports, backup, and study notes")
                    }
                }

                Section("Export") {
                    Button {
                        vm.prepareDatabaseExport()
                    } label: {
                        Label("Export Database", systemImage: "square.and.arrow.up")
                    }
                    .disabled(vm.isPreparing)

                    if vm.isPreparing {
                        ProgressView("Preparing export...")
                    }

                    if let errorMessage = vm.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .navigationTitle("Research")
        .sheet(item: $sharePackage, onDismiss: vm.cleanupPreparedExport) { package in
            if ProcessInfo.processInfo.isiOSAppOnMac {
                DocumentExportPicker(urls: package.urls) {
                    vm.cleanupPreparedExport()
                    sharePackage = nil
                }
            } else {
                ActivityView(activityItems: package.urls) {
                    vm.cleanupPreparedExport()
                    sharePackage = nil
                }
            }
        }
        .onChange(of: vm.preparedExport) { _, preparedExport in
            guard let preparedExport else { return }
            sharePackage = ExportSharePackage(urls: preparedExport)
        }
        .onAppear {
            restoreResearchUnlockState()
        }
        .onChange(of: autoLockEnabled) { _, isEnabled in
            if isEnabled {
                scheduleAutoLock(resetDeadline: true)
            } else {
                scheduleAutoLock()
            }
            saveResearchSettingsEvent(reason: "auto_lock_changed")
        }
        .onChange(of: autoLockMinutes) { _, _ in
            scheduleAutoLock(resetDeadline: true)
            saveResearchSettingsEvent(reason: "auto_lock_minutes_changed")
        }
        .onChange(of: showResearchTab) { _, _ in
            saveResearchSettingsEvent(reason: "show_research_tab_changed")
        }
        .onChange(of: researchTabAutoTurnOff) { _, _ in
            saveResearchSettingsEvent(reason: "research_tab_auto_turn_off_changed")
        }
        .onDisappear {
            autoLockTask?.cancel()
        }
    }

    private func unlockResearchMode() {
        guard researchPassword == researchPasswordValue else {
            failedLoginCount += 1
            passwordError = true
            saveResearchSettingsEvent(
                reason: "research_unlock_failed",
                researchUnlockFailed: true,
                failedLoggedInAttempts: UInt32(clamping: failedLoginCount)
            )
            print("[Research] Unlock failed")
            return
        }

        successfulLoginCount += 1
        researchUnlocked = true
        persistedResearchUnlocked = true
        passwordError = false
        researchPassword = ""
        scheduleAutoLock(resetDeadline: true)
        saveResearchSettingsEvent(
            reason: "research_unlocked",
            researchUnlocked: true,
            successfullyLoggedIn: true,
            failedLoggedInAttempts: UInt32(clamping: failedLoginCount)
        )
        print("[Research] Research settings unlocked")
    }

    private func lockResearchMode(autoLocked: Bool = false, recordEvent: Bool = true) {
        researchUnlocked = false
        persistedResearchUnlocked = false
        passwordError = false
        researchPassword = ""
        autoLockDeadline = nil
        autoLockDeadlineTimestamp = 0
        if researchTabAutoTurnOff {
            showResearchTab = false
        }
        autoLockTask?.cancel()
        autoLockTask = nil
        sharePackage = nil
        vm.cleanupPreparedExport()
        if recordEvent {
            saveResearchSettingsEvent(
                reason: autoLocked ? "research_auto_locked" : "research_locked",
                researchLocked: !autoLocked,
                researchAutoLocked: autoLocked
            )
        }
        print("[Research] Research settings locked")
    }

    private func restoreResearchUnlockState() {
        guard persistedResearchUnlocked else {
            lockResearchMode(recordEvent: false)
            return
        }

        researchUnlocked = true
        passwordError = false
        researchPassword = ""

        guard autoLockEnabled else {
            autoLockDeadline = nil
            autoLockDeadlineTimestamp = 0
            return
        }

        guard autoLockDeadlineTimestamp > 0 else {
            scheduleAutoLock(resetDeadline: true)
            return
        }

        let deadline = Foundation.Date(timeIntervalSince1970: autoLockDeadlineTimestamp)
        guard deadline > Foundation.Date() else {
            lockResearchMode(autoLocked: true)
            return
        }

        autoLockDeadline = deadline
        scheduleAutoLock(until: deadline)
        print("[Research] Research settings unlock restored")
    }

    private func scheduleAutoLock(resetDeadline: Bool = false) {
        autoLockTask?.cancel()
        autoLockTask = nil

        guard researchUnlocked, autoLockEnabled else {
            autoLockDeadline = nil
            autoLockDeadlineTimestamp = 0
            return
        }

        if resetDeadline || autoLockDeadline == nil {
            let deadline = Foundation.Date().addingTimeInterval(TimeInterval(autoLockMinutes * 60))
            autoLockDeadline = deadline
            autoLockDeadlineTimestamp = deadline.timeIntervalSince1970
        }

        guard let autoLockDeadline else { return }
        scheduleAutoLock(until: autoLockDeadline)
    }

    private func scheduleAutoLock(until deadline: Foundation.Date) {
        autoLockTask?.cancel()

        autoLockTask = Task {
            let duration = UInt64(max(deadline.timeIntervalSinceNow, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: duration)

            guard !Task.isCancelled else { return }
            await MainActor.run {
                lockResearchMode(autoLocked: true)
            }
        }
    }

    private func saveResearchSettingsEvent(
        reason: String,
        researchUnlocked: Bool? = nil,
        researchLocked: Bool? = nil,
        researchAutoLocked: Bool? = nil,
        researchUnlockFailed: Bool? = nil,
        successfullyLoggedIn: Bool? = nil,
        failedLoggedInAttempts: UInt32? = nil
    ) {
        ParkinsonMetadataStore.shared.saveVcrSettingsEvent(
            reason: reason,
            showResearchTab: showResearchTab,
            researchUnlocked: researchUnlocked,
            researchLocked: researchLocked,
            researchAutoLocked: researchAutoLocked,
            researchUnlockFailed: researchUnlockFailed,
            successfullyLoggedIn: successfullyLoggedIn,
            failedLoggedInAttempts: failedLoggedInAttempts,
            details: [
                "autoLockEnabled": String(autoLockEnabled),
                "autoLockMinutes": String(autoLockMinutes),
                "failedLoginCount": String(failedLoginCount),
                "reason": reason,
                "researchTabAutoTurnOff": String(researchTabAutoTurnOff),
                "successfulLoginCount": String(successfulLoginCount)
            ]
        )
    }

    private func remainingAutoLockText(at date: Foundation.Date) -> String {
        guard let autoLockDeadline else {
            return "Auto-lock timer is not running."
        }

        let remainingSeconds = max(Int(autoLockDeadline.timeIntervalSince(date).rounded(FloatingPointRoundingRule.up)), 0)
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "Locks again in %d:%02d", minutes, seconds)
    }
}

private struct ExportSharePackage: Identifiable {
    let id = UUID()
    let urls: [URL]
}

@MainActor
private final class ExportSettingsViewModel: ObservableObject {
    @Published var isPreparing = false
    @Published var errorMessage: String?
    @Published var preparedExport: [URL]?

    func prepareDatabaseExport() {
        isPreparing = true
        errorMessage = nil

        do {
            cleanupPreparedExport()
            preparedExport = try ParkinsonMetadataStore.shared.makeDatabaseExportCopy()
            print("[Export] Database export prepared")
        } catch {
            errorMessage = "Could not prepare database export: \(error.localizedDescription)"
            print("[Export] Database export failed: \(error)")
        }

        isPreparing = false
    }

    func cleanupPreparedExport() {
        guard let preparedExport else { return }
        ParkinsonMetadataStore.shared.cleanupDatabaseExport(urls: preparedExport)
        self.preparedExport = nil
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct DocumentExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        controller.delegate = context.coordinator
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete()
        }
    }
}

// ---------------------------------------------------------------------
// MARK: Previously existing Research Admin View -- TODO
// ---------------------------------------------------------------------
private struct ResearchAdminSettingsView: View {
    let patientID: String

    var body: some View {
        List {
            Section("Study") {
                Text("ID: \(patientID.isEmpty ? "Not set" : patientID)")
                Text("Study start date")
                Text("Patient notes")
            }

            Section("Data") {
                Text("Export logs")
                Text("Sync data")
                Text("Storage size")
                Text("Latest backup")
            }

            Section("Diagnostics") {
                Text("Bluetooth diagnostics")
                Text("App version")
                Text("Device version")
            }
        }
        .navigationTitle("Research Admin")
    }
}
