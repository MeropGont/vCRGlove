//
//  SettingsView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 11.05.26.
//

import SwiftUI
import UIKit
import UserNotifications

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
                    SettingsRow(icon: "person.crop.circle", color: .purple, title: "Profile", subtitle: "ID and icon")
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    Image(systemName: "globe")
                }
                .accessibilityLabel("Language")
            }
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

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
                Text("Avatar selection will go here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
    }
}

private struct LanguageSettingsView: View {
    var body: some View {
        List {
            Section {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open iPhone Language Settings", systemImage: "globe")
                }
            }
        }
        .navigationTitle("Language")
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
                        Text(LocalizedStringKey(topic))
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
                    ForEach(troubleshootingSteps.indices, id: \.self) { index in
                        let item = troubleshootingSteps[index]

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

    private var troubleshootingSteps: [(question: LocalizedStringKey, answer: LocalizedStringKey)] {
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
