//
//  SettingsView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 11.05.26.
//

import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var vm: GloveVM
    @AppStorage("showResearchTab") private var showResearchTab = false
    @AppStorage("patientID") private var patientID = ""

    @State private var researchPassword = ""
    @State private var researchUnlocked = false
    @State private var passwordError = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    VCRSettingsView(vm: vm)
                } label: {
                    SettingsRow(icon: "waveform.path.ecg", color: .blue, title: "vCR Settings", subtitle: "Duration, gloves, and session preferences")
                }

                NavigationLink {
                    ProfileSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "person.crop.circle", color: .purple, title: "Profile", subtitle: "ID, icon, and language")
                }

                NavigationLink {
                    ReminderSettingsView()
                } label: {
                    SettingsRow(icon: "bell.badge", color: .orange, title: "Reminders", subtitle: "vCR, journal, and task notifications")
                }

                NavigationLink {
                    PrivacyDataSettingsView()
                } label: {
                    SettingsRow(icon: "lock.shield", color: .green, title: "Privacy & Data", subtitle: "Permissions, storage, and data handling")
                }

                NavigationLink {
                    InstructionsSettingsView()
                } label: {
                    SettingsRow(icon: "book.closed", color: .teal, title: "Instructions", subtitle: "Gloves, vCR, journal, and troubleshooting")
                }
            }

            Section("Research Mode") {
                if researchUnlocked {
                    Toggle("Show Research Tab", isOn: $showResearchTab)

                    NavigationLink {
                        ResearchAdminSettingsView(patientID: $patientID)
                    } label: {
                        SettingsRow(icon: "slider.horizontal.3", color: .indigo, title: "Research Admin", subtitle: "Logs, exports, backup, and study notes")
                    }
                } else {
                    SecureField("Password", text: $researchPassword)

                    Button("Unlock Research Mode") {
                        if researchPassword == "vcr2026" {
                            researchUnlocked = true
                            passwordError = false
                            researchPassword = ""
                        } else {
                            passwordError = true
                        }
                    }

                    if passwordError {
                        Text("Incorrect password")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                NavigationLink {
                    SupportSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "questionmark.circle", color: .pink, title: "Need Help?", subtitle: "Contact ICNS support")
                }
            }
        }
        .navigationTitle("Settings")
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
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            Section("Session Plan") {
                Picker("Default vCR plan", selection: $vcrSessionPlan) {
                    Text("4 hours once").tag("fourHours")
                    Text("2 hours + 2 hours").tag("twoByTwo")
                }
                .pickerStyle(.inline)

                Text(vcrSessionPlan == "fourHours"
                     ? "Patients complete one 4-hour vCR session per day."
                     : "Patients complete two separate 2-hour vCR sessions per day.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gloves") {
                gloveRow(title: "Left glove", glove: leftGlove)
                gloveRow(title: "Right glove", glove: rightGlove)

                Button(vm.scanning ? "Stop Scan" : "Scan for Gloves") {
                    if vm.scanning {
                        vm.stopScan()
                    } else {
                        vm.startScan()
                    }
                }
            }
        }
        .navigationTitle("vCR Settings")
    }

    private func gloveRow(title: String, glove: HDevice?) -> some View {
        HStack {
            Text(title)

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
            Section("Patient") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ID")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(patientID.isEmpty ? "Not set" : patientID)
                        .font(.headline)
                        .foregroundStyle(patientID.isEmpty ? .secondary : .primary)
                }

                Text("This ID is set by the research team.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Profile") {
                Text("Language: English / Deutsch")
                    .foregroundStyle(.secondary)

                Text("Avatar selection will go here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
    }
}

private struct ResearchAdminSettingsView: View {
    @Binding var patientID: String

    @AppStorage("studyStartDate") private var studyStartDateString = ""
    @AppStorage("debugVerboseBLELogging") private var debugVerboseBLELogging = false
    @AppStorage("patientStudyNotes") private var patientStudyNotes = ""
    @AppStorage("deviceAssignmentNotes") private var deviceAssignmentNotes = ""
    @AppStorage("protocolNotes") private var protocolNotes = ""

    @State private var saveMessage: String?
    @State private var diagnosticsRefreshDate = Date()
    @State private var diagnosticsMessage: String?
    @State private var showClearAllLogsConfirmation = false

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
            Section("Study") {
                TextField("Patient ID", text: $patientID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()

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
                    saveStudyMetadata()
                } label: {
                    Label("Save Study Metadata", systemImage: "checkmark.circle")
                }

                if let saveMessage {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Section("Data") {
                Text("Export logs")
                Text("Sync data")
                Text("Storage size")
                Text("Latest backup")
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

    private func infoRow(_ title: String, _ value: String) -> some View {
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
        let startDate = Self.dateOnlyFormatter.string(from: studyStartDate.wrappedValue)

        EventStore.shared.append(
            type: "admin_metadata",
            tag: "Research",
            message: "Study metadata saved",
            details: [
                "patientID": patientID,
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
    var body: some View {
        List {
            Section("Reminders") {
                Text("vCR reminders")
                Text("Journal reminders")
                Text("Task reminders")
                Text("Quiet hours")
            }
        }
        .navigationTitle("Reminders")
    }
}

private struct PrivacyDataSettingsView: View {
    var body: some View {
        List {
            Section("Privacy & Data") {
                Text("Stored data")
                Text("Permissions")
                Text("Storage status")
                Text("Backup status")
            }
        }
        .navigationTitle("Privacy & Data")
    }
}

private struct InstructionsSettingsView: View {
    var body: some View {
        List {
            Section("Instructions") {
                Text("Gloves")
                Text("vCR session")
                Text("Journal")
                Text("Troubleshooting")
                Text("Future movement tasks")
            }
        }
        .navigationTitle("Instructions")
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
                Picker("What is not working?", selection: $topic) {
                    ForEach(topics, id: \.self) { topic in
                        Text(topic)
                    }
                }
            }

            if topic == "Other" {
                Section("Tell Us What Happened") {
                    Text("Please contact support and briefly describe what was not working.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Try This First") {
                    ForEach(troubleshootingSteps, id: \.question) { item in
                        DisclosureGroup(item.question) {
                            Text(item.answer)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
            }

            Section("Still Need Help?") {
                Text("If the steps above did not solve the issue, contact ICNS support.")
                    .foregroundStyle(.secondary)

                Text("ICNS")
                Link("015221500869", destination: URL(string: "tel:015221500869")!)

                if let supportEmailURL {
                    Link("Send Email to vcr@uke.de", destination: supportEmailURL)
                }
            }
        }
        .navigationTitle("Troubleshooting")
    }

    private var troubleshootingSteps: [(question: String, answer: String)] {
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
