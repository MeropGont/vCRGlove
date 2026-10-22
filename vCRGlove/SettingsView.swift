//
//  SettingsView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 11.05.26.
//

import SwiftUI
import UIKit
import UserNotifications

enum SettingsRoute: Hashable {
    case general
}

struct SettingsView: View {
    @ObservedObject var vm: GloveVM
    @AppStorage("patientID") private var patientID = ""

    @State private var showResearchUnlock = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProfileSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "person.crop.circle", color: .purple, title: "Profile", subtitle: "ID")
                }
                .accessibilityIdentifier("settingsProfile")

                NavigationLink(value: SettingsRoute.general) {
                    SettingsRow(icon: "gearshape", color: .gray, title: "settings.general.title", subtitle: "settings.general.subtitle")
                }
                .accessibilityIdentifier("settingsGeneral")

                NavigationLink {
                    InstructionsSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "book.closed", color: .teal, title: L10n("Instructions"), subtitle: L10n("Gloves, vCR, journal, and troubleshooting"))
                }
                .accessibilityIdentifier("settingsInstructions")

                NavigationLink {
                    VCRSettingsView(vm: vm)
                } label: {
                    SettingsRow(icon: "waveform.path.ecg", color: .blue, title: L10n("vCR Settings"), subtitle: L10n("Duration, gloves, and session preferences"))
                }
                .accessibilityIdentifier("settingsVCR")

                NavigationLink {
                    ReminderSettingsView()
                } label: {
                    SettingsRow(icon: "bell.badge", color: .orange, title: L10n("Reminders"), subtitle: L10n("vCR, journal, and task notifications"))
                }
                .accessibilityIdentifier("settingsReminders")

                NavigationLink {
                    MovementExportView()
                } label: {
                    SettingsRow(
                        icon: "figure.hand.cycling",
                        color: .purple,
                        title: "Data",
                        subtitle: "Movement measurements and videos"
                    )
                }
                .accessibilityIdentifier("settingsData")

                NavigationLink {
                    StudyInformationSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "info.circle", color: .teal, title: L10n("study.info.title"), subtitle: L10n("study.info.subtitle"))
                }
                .accessibilityIdentifier("settingsStudyInformation")
            }

            Section {
                NavigationLink {
                    SupportSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "questionmark.circle", color: .pink, title: L10n("Need Help?"), subtitle: L10n("Contact ICNS support"))
                }
                .accessibilityIdentifier("settingsSupport")
            }

            Section {
                if vm.researchUnlocked {
                    NavigationLink {
                        ResearchAdminSettingsView(vm: vm, patientID: $patientID)
                    } label: {
                        Label(L10n("research.tools"), systemImage: "slider.horizontal.3")
                    }
                    .accessibilityIdentifier("researchTools")

                    Button {
                        vm.lockResearch()
                    } label: {
                        Label(L10n("research.lock"), systemImage: "lock")
                    }
                    .accessibilityIdentifier("researchLock")
                } else {
                    Button(L10n("research.staff")) { showResearchUnlock = true }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("researchUnlockEntry")
                }
            }
        }
        .navigationTitle(L10n("Settings"))
        .navigationDestination(for: SettingsRoute.self) { route in
            switch route {
            case .general:
                GeneralSettingsView()
            }
        }
        .sheet(isPresented: $showResearchUnlock) {
            ResearchUnlockView(vm: vm)
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n(title))
                    .font(.headline)

                Text(L10n(subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VCRSettingsView: View {
    @ObservedObject var vm: GloveVM
    @AppStorage("vcrSessionPlan") private var vcrSessionPlan = "fourHours"

    private var leftGlove: HDevice? {
        vm.devices.first { $0.isLeftGlove && $0.isReadyForStimulation }
    }

    private var rightGlove: HDevice? {
        vm.devices.first { $0.isRightGlove && $0.isReadyForStimulation }
    }

    var body: some View {
        List {
            Section(L10n("Session Plan")) {
                Picker(L10n("Default vCR plan"), selection: $vcrSessionPlan) {
                    Text(L10n("4 hours once")).tag("fourHours")
                    Text(L10n("2 hours + 2 hours")).tag("twoByTwo")
                }
                .pickerStyle(.inline)

                Text(L10n(vcrSessionPlan == "fourHours"
                          ? "Patients complete one 4-hour vCR session per day."
                          : "Patients complete two separate 2-hour vCR sessions per day."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n("Gloves")) {
                gloveRow(title: "Left glove", glove: leftGlove)
                gloveRow(title: "Right glove", glove: rightGlove)

                Button(L10n(vm.scanning ? "Stop Scan" : "Scan for Gloves")) {
                    if vm.scanning {
                        vm.stopScan()
                    } else {
                        vm.startScan()
                    }
                }
            }
        }
        .navigationTitle(L10n("vCR Settings"))
    }

    private func gloveRow(title: String, glove: HDevice?) -> some View {
        HStack {
            Text(L10n(title))

            Spacer()

            if let glove {
                if let battery = glove.battery {
                    Text("\(battery)%")
                        .foregroundStyle(battery <= 10 ? .red : .secondary)
                }

                Text(glove.connectionStatusText)
                    .foregroundStyle(glove.isReadyForStimulation ? .green : .secondary)
            } else {
                Text("Not detected")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileSettingsView: View {
    let patientID: String

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n("ID"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(patientID.isEmpty ? L10n("Not set") : patientID)
                        .font(.headline)
                        .foregroundStyle(patientID.isEmpty ? .secondary : .primary)
                        .accessibilityIdentifier("profileStudyID")
                }

                Text(L10n("This ID is set by the research team."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n("Profile"))
    }
}

private struct GeneralSettingsView: View {
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section(L10n("Language")) {
                Picker(L10n("Language"), selection: $appSettings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settingsLanguagePicker")
            }

            Section(L10n("Font Size")) {
                Picker(L10n("Font Size"), selection: $appSettings.fontSize) {
                    ForEach(AppFontSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("settingsFontSizePicker")
            }
        }
        .navigationTitle(L10n("settings.general.title"))
    }
}

private struct ResearchAdminSettingsView: View {
    @ObservedObject var vm: GloveVM
    @ObservedObject private var movementStore = TaskSessionStore.shared
    @Binding var patientID: String
    @AppStorage("movementTrendIdentityLinks") private var identityLinksData = Data()

    @AppStorage("studyStartDate") private var studyStartDateString = ""
    @AppStorage("debugVerboseBLELogging") private var debugVerboseBLELogging = false
    @AppStorage("patientStudyNotes") private var patientStudyNotes = ""
    @AppStorage("deviceAssignmentNotes") private var deviceAssignmentNotes = ""
    @AppStorage("protocolNotes") private var protocolNotes = ""

    @State private var saveMessage: String?
    @State private var diagnosticsRefreshDate = Date()
    @State private var diagnosticsMessage: String?
    @State private var showClearAllLogsConfirmation = false
    @State private var exportPreparation: UUID?
    @State private var isPreparingExport = false
    @State private var exportPackage: FullDataExporter.Package?
    @State private var sharingPackage: FullDataExporter.Package?
    @State private var showExportError = false
    @State private var showMissingExportVideos = false
    @State private var studyIDDraft: String?
    @State private var showStudyIDConfirmation = false
    @State private var showTestLinkConfirmation = false
    @State private var pendingTestLinks: MovementTrendIdentityLinks?
    @FocusState private var studyIDFocused: Bool

    private var proposedStudyID: String {
        (studyIDDraft ?? patientID).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validStudyID: Bool {
        !proposedStudyID.isEmpty || patientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var identityLinks: MovementTrendIdentityLinks { MovementTrendIdentityLinks(data: identityLinksData) }

    private var studyStartDate: Binding<Date> {
        Binding(
            get: {
                if let date = Self.dateOnlyFormatter.date(from: studyStartDateString) {
                    return date
                }

                if let oldTimestamp = Double(studyStartDateString), oldTimestamp > 0 {
                    return Date(timeIntervalSince1970: oldTimestamp)
                }

                return Date()
            },
            set: {
                studyStartDateString = Self.dateOnlyFormatter.string(from: $0)
            }
        )
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        List {
            Section {
                Button {
                    isPreparingExport = true
                    exportPreparation = UUID()
                } label: {
                    Label(L10n("research.export.share"), systemImage: "square.and.arrow.up")
                }
                .disabled(isPreparingExport || vm.hasStimulationSession || !vm.researchUnlocked)
                .accessibilityIdentifier("researchShareAllData")
                if isPreparingExport {
                    ProgressView(L10n("research.export.preparing"))
                        .accessibilityIdentifier("researchExportProgress")
                }
            } header: {
                Text(L10n("research.export.title"))
            } footer: {
                Text(L10n(vm.hasStimulationSession ? "research.export.stop" : "research.export.explanation"))
            }

            if MovementTrendIdentityLinks.isTeamID(patientID) {
                Section {
                    Button {
                        var links = identityLinks
                        links.linkUnassignedTests(movementStore.sessions, to: patientID)
                        pendingTestLinks = links
                        showTestLinkConfirmation = true
                    } label: {
                        Label(L10n("Link earlier test recordings"), systemImage: "link")
                    }
                    .disabled(!vm.researchUnlocked || !movementStore.sessions.contains(where: identityLinks.canLink))
                    .accessibilityIdentifier("researchLinkEarlierTests")
                    if !identityLinks.sessions.isEmpty {
                        Button {
                            identityLinksData = Data()
                            EventStore.shared.append(type: "admin_action", tag: "Research", message: "Test display links removed")
                        } label: {
                            Label(L10n("Remove test display links"), systemImage: "arrow.uturn.backward")
                        }
                        .disabled(!vm.researchUnlocked)
                        .accessibilityIdentifier("researchRemoveTestLinks")
                    }
                } footer: {
                    Text(L10n("Only for your own earlier unassigned tests. Changes trend display, not saved data."))
                }
            }

            Section("Study") {
                TextField(L10n("Study ID"), text: Binding(
                    get: { studyIDDraft ?? patientID }, set: { studyIDDraft = $0 }))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($studyIDFocused)
                    .submitLabel(.done)
                    .onSubmit { studyIDFocused = false }
                    .accessibilityIdentifier("researchStudyID")
                if !validStudyID {
                    Text(L10n("A study ID cannot be cleared once assigned."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                DatePicker("Study start date", selection: studyStartDate, displayedComponents: .date)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Patient notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $patientStudyNotes)
                        .frame(minHeight: 90)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Device assignment notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $deviceAssignmentNotes)
                        .frame(minHeight: 90)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Protocol notes")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $protocolNotes)
                        .frame(minHeight: 90)
                }

                Button {
                    if proposedStudyID != patientID && !patientID.isEmpty {
                        showStudyIDConfirmation = true
                    } else {
                        saveStudyMetadata()
                    }
                } label: {
                    Label("Save Study Metadata", systemImage: "checkmark.circle")
                }
                .disabled(!validStudyID || !vm.researchUnlocked)
                .accessibilityIdentifier("researchSaveMetadata")

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section(L10n("Logs")) {
                LogsPanel(logger: Logger.shared)
                    .frame(height: 260)
            }

            Section("Diagnostics") {
                infoRow("App version", appVersionText)
                infoRow("iOS version", UIDevice.current.systemVersion)
                infoRow("Device", UIDevice.current.model)

                infoRow("Event log", eventLogPathText)
                infoRow("Event log size", fileSizeText(for: EventStore.shared.fileURL()))
                infoRow("Last log update", lastModifiedText(for: EventStore.shared.fileURL()))
                infoRow("App documents size", documentsSizeText)
                Toggle("Verbose BLE debug logging", isOn: $debugVerboseBLELogging)

                Text("Verbose BLE logging saves raw bHaptics device snapshots and should only be enabled temporarily during debugging.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    diagnosticsRefreshDate = Date()
                    diagnosticsMessage = "Diagnostics refreshed"
                    Logger.shared.log("Diagnostics", "Research diagnostics refreshed")
                } label: {
                    Label("Refresh Diagnostics", systemImage: "arrow.clockwise")
                }

                Button {
                    Logger.shared.clear()
                    diagnosticsMessage = "Visible log cleared"
                } label: {
                    Label("Clear Visible Log", systemImage: "text.badge.xmark")
                }

                if let logURL = EventStore.shared.fileURL() {
                    ShareLink(item: logURL) {
                        Label("Share Event Log", systemImage: "square.and.arrow.up")
                    }
                }

                Button(role: .destructive) {
                    showClearAllLogsConfirmation = true
                } label: {
                    Label("Clear Event Log File", systemImage: "trash")
                }

                if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Research Admin")
        .alert(L10n("Change study ID?"), isPresented: $showStudyIDConfirmation) {
            Button(L10n("Change ID")) { saveStudyMetadata() }
                .accessibilityIdentifier("researchConfirmStudyID")
            Button(L10n("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n("New recordings will use the new ID. Saved recordings keep their original IDs and stay separate."))
        }
        .alert(L10n("Link your earlier tests?"), isPresented: $showTestLinkConfirmation) {
            Button(L10n("Link test recordings")) {
                guard vm.researchUnlocked, MovementTrendIdentityLinks.isTeamID(patientID),
                      let links = pendingTestLinks, let data = try? JSONEncoder().encode(links) else { return }
                identityLinksData = data
                pendingTestLinks = nil
                EventStore.shared.append(type: "admin_metadata", tag: "Research", message: "Test display links saved",
                    details: ["linkedSessions": String(links.sessions.count), "displayStudyID": patientID])
            }
            .accessibilityIdentifier("researchConfirmTestLinks")
            Button(L10n("Cancel"), role: .cancel) { pendingTestLinks = nil }
        } message: {
            Text(L10n("Confirm these unassigned recordings are your own tests. Only trend display changes. Saved data stays unchanged."))
        }
        .task(id: exportPreparation) {
            guard exportPreparation != nil else { return }
            defer { isPreparingExport = false; exportPreparation = nil }
            do {
                let prepared = try await FullDataExporter.prepare()
                exportPackage = prepared
                if prepared.missingVideoCount > 0 { showMissingExportVideos = true }
                else { sharingPackage = prepared }
                EventStore.shared.append(type: "admin_action", tag: "Research", message: "Full data export prepared")
            } catch {
                if !Task.isCancelled { showExportError = true }
            }
        }
        .sheet(item: $sharingPackage, onDismiss: cleanUpExport) { package in
            FullDataShareSheet(url: package.archive) { sharingPackage = nil }
        }
        .alert(L10n("research.export.missing.title"), isPresented: $showMissingExportVideos) {
            Button(L10n("Share…")) { sharingPackage = exportPackage }
            Button(L10n("Cancel"), role: .cancel) { cleanUpExport() }
        } message: {
            Text(L10n("research.export.missing.message"))
        }
        .alert(L10n("research.export.failed"), isPresented: $showExportError) {
            Button(L10n("OK"), role: .cancel) {}
        } message: {
            Text(L10n("research.export.retry"))
        }
        .onDisappear { if sharingPackage == nil { cleanUpExport() } }
        .confirmationDialog(
            "Clear event log file?",
            isPresented: $showClearAllLogsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Event Log File", role: .destructive) {
                EventStore.shared.clearEventLog(patientID: patientID)
                diagnosticsRefreshDate = Date()
                diagnosticsMessage = "Event log file cleared"
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the JSONL event log on this phone and starts a new log with an audit entry.")
        }
    }

    private func cleanUpExport() {
        exportPackage?.remove()
        exportPackage = nil
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }

    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        return "\(version) (\(build))"
    }

    private var eventLogPathText: String {
        EventStore.shared.fileURL()?.path ?? "Not available"
    }

    private var documentsSizeText: String {
        do {
            let url = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

            let bytes = folderSize(at: url)
            return formattedBytes(bytes)
        } catch {
            return "Not available"
        }
    }

    private func fileSizeText(for url: URL?) -> String {
        guard let url else { return "Not available" }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let bytes = attributes[.size] as? Int64 ?? 0
            return formattedBytes(bytes)
        } catch {
            return "Not found"
        }
    }

    private func lastModifiedText(for url: URL?) -> String {
        guard let url else { return "Not available" }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let date = attributes[.modificationDate] as? Date else {
                return "Unknown"
            }

            return date.formatted(date: .abbreviated, time: .shortened)
        } catch {
            return "Not found"
        }
    }

    private func folderSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            total += Int64(values?.fileSize ?? 0)
        }

        return total
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func saveStudyMetadata() {
        guard validStudyID, vm.researchUnlocked else { return }
        let previousID = patientID
        patientID = proposedStudyID
        studyIDDraft = nil
        let startDate = Self.dateOnlyFormatter.string(from: studyStartDate.wrappedValue)

        EventStore.shared.append(
            type: "admin_metadata",
            tag: "Research",
            message: "Study metadata saved",
            details: [
                "patientID": patientID,
                "previousPatientID": previousID,
                "studyIDChanged": String(previousID != patientID),
                "studyStartDate": startDate,
                "hasPatientNotes": String(!patientStudyNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                "hasDeviceAssignmentNotes": String(!deviceAssignmentNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
                "hasProtocolNotes": String(!protocolNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ]
        )

        saveMessage = "Saved locally"
    }
}

private struct ReminderSettingsView: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false

    @AppStorage("vcrReminderEnabled") private var vcrReminderEnabled = true
    @AppStorage("vcrReminderHour") private var vcrReminderHour = 9
    @AppStorage("vcrReminderMinute") private var vcrReminderMinute = 0

    @AppStorage("journalReminderEnabled") private var journalReminderEnabled = true
    @AppStorage("journalReminderHour") private var journalReminderHour = 18
    @AppStorage("journalReminderMinute") private var journalReminderMinute = 0
    @AppStorage("journalReminderWeekdays") private var journalReminderWeekdays = "2,4,6"

    @AppStorage("taskReminderEnabled") private var taskReminderEnabled = true
    @AppStorage("taskReminderHour") private var taskReminderHour = 18
    @AppStorage("taskReminderMinute") private var taskReminderMinute = 0
    @AppStorage("taskReminderWeekdays") private var taskReminderWeekdays = "3,5"

    @AppStorage("quietHoursEnabled") private var quietHoursEnabled = true
    @AppStorage("quietStartHour") private var quietStartHour = 21
    @AppStorage("quietEndHour") private var quietEndHour = 8

    @State private var permissionText = "Checking..."
    @State private var statusMessage: LocalizedStringKey?

    private let weekdayOptions: [(value: Int, label: LocalizedStringKey)] = [
        (2, "Mon"),
        (3, "Tue"),
        (4, "Wed"),
        (5, "Thu"),
        (6, "Fri"),
        (7, "Sat"),
        (1, "Sun")
    ]

    var body: some View {
        List {
            Section("Notification Permission") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(permissionText)
                        .foregroundStyle(.secondary)
                }

                if !notificationsEnabled {
                    Button("Allow Notifications") {
                        requestPermission()
                    }

                    Text("Allow notifications before changing reminder settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Open iPhone Notification Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            Section("vCR Reminder") {
                Toggle("Daily vCR reminder", isOn: $vcrReminderEnabled)

                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: { dateFrom(hour: vcrReminderHour, minute: vcrReminderMinute) },
                        set: { updateTime($0, hour: &vcrReminderHour, minute: &vcrReminderMinute) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!vcrReminderEnabled)
            }
            .disabled(!notificationsEnabled)
            .opacity(notificationsEnabled ? 1 : 0.45)

            Section("Journal Reminders") {
                Toggle("Journal reminders", isOn: $journalReminderEnabled)

                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: { dateFrom(hour: journalReminderHour, minute: journalReminderMinute) },
                        set: { updateTime($0, hour: &journalReminderHour, minute: &journalReminderMinute) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!journalReminderEnabled)

                weekdayPicker(selection: $journalReminderWeekdays)
                    .disabled(!journalReminderEnabled)
            }
            .disabled(!notificationsEnabled)
            .opacity(notificationsEnabled ? 1 : 0.45)

            Section("Task Reminders") {
                Toggle("Task reminders", isOn: $taskReminderEnabled)

                DatePicker(
                    "Reminder time",
                    selection: Binding(
                        get: { dateFrom(hour: taskReminderHour, minute: taskReminderMinute) },
                        set: { updateTime($0, hour: &taskReminderHour, minute: &taskReminderMinute) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .disabled(!taskReminderEnabled)

                weekdayPicker(selection: $taskReminderWeekdays)
                    .disabled(!taskReminderEnabled)
            }
            .disabled(!notificationsEnabled)
            .opacity(notificationsEnabled ? 1 : 0.45)

            Section("Quiet Hours") {
                Toggle("Use quiet hours", isOn: $quietHoursEnabled)

                Stepper("Start: \(quietStartHour):00", value: $quietStartHour, in: 0...23)
                    .disabled(!quietHoursEnabled)

                Stepper("End: \(quietEndHour):00", value: $quietEndHour, in: 0...23)
                    .disabled(!quietHoursEnabled)

                Text("Journal and task reminders inside quiet hours are moved to the quiet-hours end time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!notificationsEnabled)
            .opacity(notificationsEnabled ? 1 : 0.45)

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Reminders")
        .onAppear {
            refreshPermissionStatus()
        }
        .onChange(of: vcrReminderEnabled) { _, _ in scheduleIfAllowed() }
        .onChange(of: journalReminderEnabled) { _, _ in scheduleIfAllowed() }
        .onChange(of: journalReminderWeekdays) { _, _ in scheduleIfAllowed() }
        .onChange(of: taskReminderEnabled) { _, _ in scheduleIfAllowed() }
        .onChange(of: taskReminderWeekdays) { _, _ in scheduleIfAllowed() }
        .onChange(of: quietHoursEnabled) { _, _ in scheduleIfAllowed() }
        .onChange(of: quietStartHour) { _, _ in scheduleIfAllowed() }
        .onChange(of: quietEndHour) { _, _ in scheduleIfAllowed() }
    }

    private func weekdayPicker(selection: Binding<String>) -> some View {
        HStack(spacing: 6) {
            ForEach(weekdayOptions, id: \.value) { weekday in
                let isSelected = selectedWeekdays(from: selection.wrappedValue).contains(weekday.value)

                Button {
                    toggleWeekday(weekday.value, in: selection)
                } label: {
                    Text(weekday.label)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                notificationsEnabled = granted
                refreshPermissionStatus()

                if granted {
                    scheduleIfAllowed(showMessage: true)
                }
            }
        }
    }

    private func refreshPermissionStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    permissionText = "Allowed"
                    notificationsEnabled = true
                    scheduleIfAllowed(showMessage: false)
                case .denied:
                    permissionText = "Not allowed"
                    notificationsEnabled = false
                case .notDetermined:
                    permissionText = "Not asked yet"
                    notificationsEnabled = false
                @unknown default:
                    permissionText = "Unknown"
                    notificationsEnabled = false
                }
            }
        }
    }

    private func scheduleIfAllowed(showMessage: Bool = true) {
        guard notificationsEnabled else {
            return
        }

        ReminderScheduler.schedule(
            vcrEnabled: vcrReminderEnabled,
            vcrHour: vcrReminderHour,
            vcrMinute: vcrReminderMinute,
            journalEnabled: journalReminderEnabled,
            journalHour: journalReminderHour,
            journalMinute: journalReminderMinute,
            journalWeekdays: selectedWeekdays(from: journalReminderWeekdays),
            taskEnabled: taskReminderEnabled,
            taskHour: taskReminderHour,
            taskMinute: taskReminderMinute,
            taskWeekdays: selectedWeekdays(from: taskReminderWeekdays),
            quietHoursEnabled: quietHoursEnabled,
            quietStartHour: quietStartHour,
            quietEndHour: quietEndHour
        )

        if showMessage {
            statusMessage = "Reminder settings saved."
        }
    }

    private func dateFrom(hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    private func updateTime(_ date: Date, hour: inout Int, minute: inout Int) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = components.hour ?? hour
        minute = components.minute ?? minute
        scheduleIfAllowed()
    }

    private func selectedWeekdays(from text: String) -> Set<Int> {
        Set(text.split(separator: ",").compactMap { Int($0) })
    }

    private func toggleWeekday(_ weekday: Int, in selection: Binding<String>) {
        var selected = selectedWeekdays(from: selection.wrappedValue)

        if selected.contains(weekday) {
            selected.remove(weekday)
        } else {
            selected.insert(weekday)
        }

        selection.wrappedValue = selected.sorted().map(String.init).joined(separator: ",")
    }
}

enum ReminderScheduler {
    static func scheduleFromStoredSettings() {
        let defaults = UserDefaults.standard

        schedule(
            vcrEnabled: boolSetting("vcrReminderEnabled", defaultValue: true),
            vcrHour: defaults.object(forKey: "vcrReminderHour") as? Int ?? 9,
            vcrMinute: defaults.object(forKey: "vcrReminderMinute") as? Int ?? 0,
            journalEnabled: boolSetting("journalReminderEnabled", defaultValue: true),
            journalHour: defaults.object(forKey: "journalReminderHour") as? Int ?? 18,
            journalMinute: defaults.object(forKey: "journalReminderMinute") as? Int ?? 0,
            journalWeekdays: weekdaysSetting("journalReminderWeekdays", defaultValue: "2,4,6"),
            taskEnabled: boolSetting("taskReminderEnabled", defaultValue: true),
            taskHour: defaults.object(forKey: "taskReminderHour") as? Int ?? 18,
            taskMinute: defaults.object(forKey: "taskReminderMinute") as? Int ?? 0,
            taskWeekdays: weekdaysSetting("taskReminderWeekdays", defaultValue: "3,5"),
            quietHoursEnabled: boolSetting("quietHoursEnabled", defaultValue: true),
            quietStartHour: defaults.object(forKey: "quietStartHour") as? Int ?? 21,
            quietEndHour: defaults.object(forKey: "quietEndHour") as? Int ?? 8
        )
    }

    private static func boolSetting(_ key: String, defaultValue: Bool) -> Bool {
        if UserDefaults.standard.object(forKey: key) == nil {
            return defaultValue
        }

        return UserDefaults.standard.bool(forKey: key)
    }

    private static func weekdaysSetting(_ key: String, defaultValue: String) -> Set<Int> {
        let text = UserDefaults.standard.string(forKey: key) ?? defaultValue
        return Set(text.split(separator: ",").compactMap { Int($0) })
    }

    static func schedule(
        vcrEnabled: Bool,
        vcrHour: Int,
        vcrMinute: Int,
        journalEnabled: Bool,
        journalHour: Int,
        journalMinute: Int,
        journalWeekdays: Set<Int>,
        taskEnabled: Bool,
        taskHour: Int,
        taskMinute: Int,
        taskWeekdays: Set<Int>,
        quietHoursEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int
    ) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        if vcrEnabled {
            scheduleDaily(
                id: "vcr.daily",
                title: String(localized: "vCR session"),
                body: String(localized: "Your gloves are ready when you are"),
                hour: vcrHour,
                minute: vcrMinute
            )
        }

        if journalEnabled {
            let adjustedTime = adjustedForQuietHours(
                hour: journalHour,
                minute: journalMinute,
                quietHoursEnabled: quietHoursEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour
            )

            scheduleWeekly(
                idPrefix: "journal",
                weekdays: journalWeekdays,
                title: String(localized: "Journal check-in"),
                body: String(localized: "How are you feeling today?"),
                hour: adjustedTime.hour,
                minute: adjustedTime.minute
            )
        }

        if taskEnabled {
            let adjustedTime = adjustedForQuietHours(
                hour: taskHour,
                minute: taskMinute,
                quietHoursEnabled: quietHoursEnabled,
                quietStartHour: quietStartHour,
                quietEndHour: quietEndHour
            )

            scheduleWeekly(
                idPrefix: "task",
                weekdays: taskWeekdays,
                title: String(localized: "Movement task"),
                body: String(localized: "Let's do today’s movement task"),
                hour: adjustedTime.hour,
                minute: adjustedTime.minute
            )
        }
    }

    private static var identifiers: [String] {
        ["vcr.daily"] +
        (1...7).map { "journal.\($0)" } +
        (1...7).map { "task.\($0)" }
    }

    private static func adjustedForQuietHours(
        hour: Int,
        minute: Int,
        quietHoursEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int
    ) -> (hour: Int, minute: Int) {
        guard quietHoursEnabled else {
            return (hour, minute)
        }

        let selectedMinutes = hour * 60 + minute
        let quietStart = quietStartHour * 60
        let quietEnd = quietEndHour * 60

        let isInsideQuietHours: Bool
        if quietStart < quietEnd {
            isInsideQuietHours = selectedMinutes >= quietStart && selectedMinutes < quietEnd
        } else {
            isInsideQuietHours = selectedMinutes >= quietStart || selectedMinutes < quietEnd
        }

        if isInsideQuietHours {
            return (quietEndHour, 0)
        }

        return (hour, minute)
    }

    private static func scheduleDaily(id: String, title: String, body: String, hour: Int, minute: Int) {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private static func scheduleWeekly(
        idPrefix: String,
        weekdays: Set<Int>,
        title: String,
        body: String,
        hour: Int,
        minute: Int
    ) {
        for weekday in weekdays {
            var components = DateComponents()
            components.weekday = weekday
            components.hour = hour
            components.minute = minute

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(
                identifier: "\(idPrefix).\(weekday)",
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request)
        }
    }
}

struct StudyInformationSection: Identifiable {
    let id: String
    let headingKey: String?
    let paragraphKeys: [String]
}

enum StudyInformationTopic: String, CaseIterable, Identifiable {
    case study, participation, devices, safety, privacy, contact

    var id: String { rawValue }
    var titleKey: String { "study.\(rawValue).title" }
    var icon: String {
        switch self {
        case .study: return "info.circle"
        case .participation: return "calendar"
        case .devices: return "iphone"
        case .safety: return "hand.raised"
        case .contact: return "envelope"
        case .privacy: return "lock.shield"
        }
    }

    var sections: [StudyInformationSection] {
        guard self == .privacy else {
            let keys: [String]
            switch self {
            case .study: keys = ["study.study.body"]
            case .participation: keys = ["study.participation.body", "study.participation.plan"]
            case .devices:
                return [
                    .init(id: "devices", headingKey: nil, paragraphKeys: ["study.devices.body", "study.devices.results"]),
                    .init(id: "storage", headingKey: "Stored data", paragraphKeys: ["privacy.app.localData"]),
                    .init(id: "videos", headingKey: "privacy.app.videoTitle", paragraphKeys: [
                        "privacy.app.videoCapture", "privacy.app.videoStorage", "privacy.app.videoSharing", "privacy.app.videoDeletion"])
                ]
            case .safety: keys = ["study.safety.body", "study.safety.voluntary"]
            case .contact: return []
            case .privacy: keys = []
            }
            return [StudyInformationSection(id: rawValue, headingKey: nil, paragraphKeys: keys)]
        }
        return [
            .init(id: "intro", headingKey: "study.privacy.heading", paragraphKeys: [
                "study.privacy.confidentiality", "study.privacy.storage", "study.privacy.keyFile",
                "study.privacy.use", "study.privacy.gdpr"]),
            .init(id: "basis", headingKey: "study.privacy.basis.title", paragraphKeys: ["study.privacy.basis.body"]),
            .init(id: "responsible", headingKey: "study.privacy.responsible.title", paragraphKeys: ["study.privacy.responsible.body"]),
            .init(id: "access", headingKey: "study.privacy.access.title", paragraphKeys: ["study.privacy.access.body"]),
            .init(id: "rectification", headingKey: "study.privacy.rectification.title", paragraphKeys: ["study.privacy.rectification.body"]),
            .init(id: "erasure", headingKey: "study.privacy.erasure.title", paragraphKeys: ["study.privacy.erasure.body"]),
            .init(id: "restriction", headingKey: "study.privacy.restriction.title", paragraphKeys: ["study.privacy.restriction.body"]),
            .init(id: "portability", headingKey: "study.privacy.portability.title", paragraphKeys: ["study.privacy.portability.body"]),
            .init(id: "objection", headingKey: "study.privacy.objection.title", paragraphKeys: ["study.privacy.objection.body"]),
            .init(id: "withdrawal", headingKey: "study.privacy.withdrawal.title", paragraphKeys: [
                "study.privacy.withdrawal.basis", "study.privacy.withdrawal.body", "study.privacy.withdrawal.contact",
                "study.privacy.complaint"]),
            .init(id: "contacts", headingKey: "study.privacy.contacts.title", paragraphKeys: [
                "study.privacy.dpo", "study.privacy.authority"]),
            .init(id: "definitions", headingKey: "study.privacy.definitions.title", paragraphKeys: [
                "study.privacy.pseudonymisation", "study.privacy.anonymisation"]),
            .init(id: "ethics", headingKey: nil, paragraphKeys: ["study.privacy.ethics"])
        ]
    }
}

private struct StudyInformationSettingsView: View {
    let patientID: String

    var body: some View {
        List {
            Section {
                Text(L10n("study.info.intro"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                ForEach(StudyInformationTopic.allCases) { topic in
                    NavigationLink {
                        if topic == .contact {
                            StudyContactSettingsView(patientID: patientID)
                        } else {
                            StudyInformationTopicView(topic: topic)
                        }
                    } label: {
                        Label {
                            Text(L10n(topic.titleKey))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: topic.icon).foregroundStyle(.teal)
                        }
                        .padding(.vertical, 5)
                    }
                    .accessibilityIdentifier("studyTopic_\(topic.rawValue)")
                }
            }
        }
        .navigationTitle(L10n("study.info.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StudyInformationTopicView: View {
    let topic: StudyInformationTopic

    var body: some View {
        List {
            ForEach(topic.sections) { content in
                Section {
                    ForEach(content.paragraphKeys, id: \.self) { key in
                        Text(L10n(key))
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.vertical, 4)
                            .accessibilityIdentifier(key)
                    }
                } header: {
                    if let heading = content.headingKey {
                        Text(L10n(heading))
                            .textCase(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            if topic == .privacy {
                Section {
                    Text(L10n("study.privacy.version"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("studyPrivacyVersion")
                }
            }
        }
        .navigationTitle(L10n(topic.titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StudyContactSettingsView: View {
    let patientID: String

    private var emailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "vcr@uke.de"
        let subject = L10n("study.contact.emailSubject")
        components.queryItems = [URLQueryItem(name: "subject", value: patientID.isEmpty ? subject : "\(subject) - ID \(patientID)")]
        return components.url
    }

    var body: some View {
        List {
            Section {
                ICNSContactDetails(emailURL: emailURL)
            }
        }
        .navigationTitle(L10n("study.contact.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ICNSContactDetails: View {
    let emailURL: URL?

    var body: some View {
        Text("ICNS")
        Text(L10n("support.institutionAddress"))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityIdentifier("supportInstitutionAddress")
        Link("015221500869", destination: URL(string: "tel:015221500869")!)
            .accessibilityIdentifier("supportPhone")
        if let emailURL {
            Link(L10n("Send Email to vcr@uke.de"), destination: emailURL)
                .accessibilityIdentifier("supportEmail")
        }
    }
}

private struct InstructionsSettingsView: View {
    let patientID: String

    var body: some View {
        List {
            Section {
                Text(L10n("instructions.intro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }

            Section(L10n("instructions.topics")) {
                ForEach(InstructionTopic.allCases) { topic in
                    NavigationLink {
                        InstructionTopicView(topic: topic)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: topic.icon)
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(topic.color)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n(topic.titleKey))
                                    .font(.headline)

                                Text(L10n(topic.subtitleKey))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }

            Section(L10n("instructions.help.section")) {
                NavigationLink {
                    SupportSettingsView(patientID: patientID)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n("instructions.help.title"))
                                .font(.headline)

                            Text(L10n("instructions.help.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "questionmark.circle.fill")
                            .foregroundStyle(.pink)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .navigationTitle(L10n("Instructions"))
    }
}

private enum InstructionTopic: String, CaseIterable, Identifiable {
    case gloves
    case vcr
    case journal
    case movement

    var id: String { rawValue }

    var titleKey: String {
        "instructions.\(rawValue).title"
    }

    var subtitleKey: String {
        "instructions.\(rawValue).subtitle"
    }

    var icon: String {
        switch self {
        case .gloves: return "hand.raised.fill"
        case .vcr: return "waveform.path.ecg"
        case .journal: return "calendar"
        case .movement: return "figure.walk.motion"
        }
    }

    var color: Color {
        switch self {
        case .gloves: return .blue
        case .vcr: return .indigo
        case .journal: return .green
        case .movement: return .orange
        }
    }

    var stepKeys: [String] {
        switch self {
        case .gloves:
            return (1...5).map { "instructions.gloves.step\($0)" }
        case .vcr:
            return (1...6).map { "instructions.vcr.step\($0)" }
        case .journal:
            return (1...5).map { "instructions.journal.step\($0)" }
        case .movement:
            return (1...6).map { "instructions.movement.step\($0)" }
        }
    }

    var noteKey: String? {
        switch self {
        case .vcr: return "instructions.vcr.note"
        case .movement: return "instructions.movement.note"
        default: return nil
        }
    }
}

private struct InstructionTopicView: View {
    let topic: InstructionTopic

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: topic.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(topic.color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n(topic.titleKey))
                            .font(.title3.bold())

                        Text(L10n(topic.subtitleKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 5)
            }

            Section(L10n("instructions.steps")) {
                ForEach(Array(topic.stepKeys.enumerated()), id: \.offset) { index, key in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(topic.color)
                            .clipShape(Circle())
                            .accessibilityHidden(true)

                        Text(L10n(key))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        String(
                            format: L10n("instructions.step.accessibility"),
                            index + 1,
                            L10n(key)
                        )
                    )
                }
            }

            if let noteKey = topic.noteKey {
                Section {
                    Label(L10n(noteKey), systemImage: "info.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(L10n(topic.titleKey))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SupportSettingsView: View {
    let patientID: String

    @State private var topic: String

    init(patientID: String, initialTopic: String = "Finger check") {
        self.patientID = patientID
        _topic = State(initialValue: initialTopic)
    }

    private let topics = [
        "Finger check",
        "Glove connection",
        "vCR session",
        "Journal",
        "Notifications",
        "App problem",
        "Other"
    ]

    private var supportEmailURL: URL? {
        let idText = patientID.isEmpty ? "No ID" : "ID \(patientID)"
        let subject = "vCR Help - \(idText) - \(topic)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        return URL(string: "mailto:vcr@uke.de?subject=\(encodedSubject)")
    }

    var body: some View {
        List {
            Section {
                Picker(L10n("What is not working?"), selection: $topic) {
                    ForEach(topics, id: \.self) { topic in
                        Text(L10n(topic))
                    }
                }
            }

            if topic == "Other" {
                Section(L10n("Tell Us What Happened")) {
                    Text(L10n("Please contact support and briefly describe what was not working."))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(L10n("Try This First")) {
                    ForEach(troubleshootingSteps.indices, id: \.self) { index in
                        let item = troubleshootingSteps[index]

                        DisclosureGroup(L10n(item.question)) {
                            Text(L10n(item.answer))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            Section(L10n("Still Need Help?")) {
                Text(L10n("If the steps above did not solve the issue, contact ICNS support."))
                    .foregroundStyle(.secondary)

                ICNSContactDetails(emailURL: supportEmailURL)
            }
        }
        .navigationTitle(L10n("Troubleshooting"))
    }

    private var troubleshootingSteps: [
        (question: String, answer: String)
    ] {
        switch topic {
        case "Finger check":
            return [
                ("One finger did not buzz", "Make sure both gloves are charged and worn correctly. Stop the session, press Scan for Gloves again, then start vCR once more."),
                ("The buzzes felt uneven", "Keep the app open and avoid switching apps during the finger check. If this happens repeatedly, contact support."),
                ("The wrong finger buzzed", "Continue only if all fingers can be felt clearly. Please report this to support so we can check the glove mapping.")
            ]

        case "Glove connection":
            return [
                ("A glove is not detected", "Turn the glove off and on again. Then press Scan for Gloves and wait up to one minute."),
                ("Only one glove connects", "You can still start vCR with one glove. If the second glove does not appear after scanning, charge it and try again."),
                ("The glove disconnects", "Keep the phone close to the gloves and keep the app open. If both gloves disconnect, the session will stop automatically.")
            ]

        case "vCR session":
            return [
                ("Stimulation does not start", "Check that at least one glove shows Ready. Then press Start vCR."),
                ("Stimulation feels interrupted", "Keep the app open during stimulation. Avoid locking the phone or switching to another app."),
                ("I need to pause", "Use Pause during the session. Press Resume when you are ready to continue.")
            ]

        case "Journal":
            return [
                ("I cannot find today’s log", "Open the Journal tab and tap today’s date in the calendar."),
                ("I entered something wrong", "For now, add a note explaining the correction. Editing entries can be added later.")
            ]

        case "Notifications":
            return [
                ("I get too many reminders", "Reminder frequency can be adjusted in Settings > Reminders."),
                ("I do not receive reminders", "Check that notifications are allowed for this app in iPhone Settings.")
            ]

        default:
            return [
                ("The app is behaving strangely", "Close and reopen the app. If stimulation is running, stop it first if possible."),
                ("The issue keeps happening", "Contact support and include what you were trying to do when the problem happened.")
            ]
        }
    }
}
