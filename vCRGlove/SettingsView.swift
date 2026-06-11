//
//  SettingsView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 11.05.26.
//

import SwiftUI
import UIKit
import ParkinsonMetadata

// ---------------------------------------------------------------------
// MARK: Main Settings Tab UI
// ---------------------------------------------------------------------
// find Research Settings UI in seperate files

struct SettingsView: View {
    @AppStorage("patientID") private var patientID = ""
    @AppStorage("researchSettingsUnlocked") private var researchSettingsUnlocked = false
    @AppStorage("researchAutoLockEnabled") private var researchAutoLockEnabled = true
    @AppStorage("researchAutoLockDeadline") private var researchAutoLockDeadlineTimestamp = 0.0

    var body: some View {
        List {
            Section {
                NavigationLink {
                    GeneralSettingsView()
                } label: {
                    SettingsRow(icon: "gearshape", color: .gray, title: "General", subtitle: "Appearance, language, and patient overview")
                }

                NavigationLink {
                    VCRSettingsView()
                } label: {
                    SettingsRow(icon: "waveform.path.ecg", color: .blue, title: "vCR Settings", subtitle: "Duration, gloves, and session preferences")
                }

                if isResearchModeActive {
                    NavigationLink {
                        ProfileSettingsView(patientID: $patientID)
                    } label: {
                        SettingsRow(icon: "person.crop.circle", color: .purple, title: "Profile", subtitle: "Pseudonym in Study, Soarian Case ID, and patient details")
                    }
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

                NavigationLink {
                    ResearchSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "slider.horizontal.3", color: .cyan, title: "Research", subtitle: "Unlock research tools, export, and admin options")
                        .modifier(ResearchUnlockedFrame(isActive: isResearchModeActive))
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

    private var isResearchModeActive: Bool {
        ResearchModeAccess.isActive(
            unlocked: researchSettingsUnlocked,
            autoLockEnabled: researchAutoLockEnabled,
            autoLockDeadlineTimestamp: researchAutoLockDeadlineTimestamp
        )
    }
}

enum ResearchModeAccess {
    static func isActive(
        unlocked: Bool,
        autoLockEnabled: Bool,
        autoLockDeadlineTimestamp: Double,
        at date: Foundation.Date = Foundation.Date()
    ) -> Bool {
        guard unlocked else { return false }
        guard autoLockEnabled else { return true }
        guard autoLockDeadlineTimestamp > 0 else { return false }
        return Foundation.Date(timeIntervalSince1970: autoLockDeadlineTimestamp) > date
    }

    static func remainingMinutesBadge(
        unlocked: Bool,
        autoLockEnabled: Bool,
        autoLockDeadlineTimestamp: Double,
        at date: Foundation.Date
    ) -> String? {
        guard unlocked else { return nil }
        guard autoLockEnabled else { return "∞" }
        guard autoLockDeadlineTimestamp > 0 else { return nil }

        let deadline = Foundation.Date(timeIntervalSince1970: autoLockDeadlineTimestamp)
        let remainingSeconds = deadline.timeIntervalSince(date)
        guard remainingSeconds > 0 else { return nil }

        let remainingMinutes = max(1, Int(ceil(remainingSeconds / 60)))
        return "\(remainingMinutes)m"
    }
}

private struct ResearchUnlockedFrame: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            TimelineView(.animation) { context in
                let rotation = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4) / 4 * 360

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    .padding(.horizontal, 8)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                AngularGradient(
                                    colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red],
                                    center: .center,
                                    angle: .degrees(rotation)
                                ),
                                lineWidth: 2
                            )
                    }
            }
        } else {
            content
        }
    }
}

struct SettingsRow: View {
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

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = AppAppearanceMode.auto.rawValue
    @AppStorage("profileAvatar") private var profileAvatar = ProfileAvatarValue.default.storageValue
    @State private var language = "English"
    @State private var showingAvatarEditor = false
    @State private var showingVersionDetails = false
    @ObservedObject private var store = ParkinsonMetadataStore.shared

    private let languages = ["English"]

    var body: some View {
        List {
            Section {
                if let patient = store.activePatient {
                    aboutMeHeader(for: patient)
                    profileCopyableOptionalRow("UUID", patient.id?.pseudonymString())
                    profileOptionalRow("Pseudonym in Study", patient.additionalLabPseudonym)
                } else {
                    emptyAboutMeHeader
                }
            }

            Section("Appearance") {
                Picker("Appearance", selection: $appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.self) { language in
                        Text(language).tag(language)
                    }
                }

            }

            Section {
                HStack {
                    Spacer()
                    versionPill
                    Spacer()
                }
                .padding(.vertical, 10)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("General")
        .sheet(isPresented: $showingAvatarEditor) {
            AvatarSelectionSheet(avatarStorage: $profileAvatar)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: profileAvatar) { _, newValue in
            store.saveVcrSettingsEvent(
                reason: "profile_avatar_changed",
                showResearchTab: nil,
                avatar: newValue,
                details: ["avatar": newValue]
            )
        }
        .onAppear {
            store.reloadPatients()
        }
    }

    private func aboutMeHeader(for patient: ParkinsonMetadata.Patient) -> some View {
        HStack(spacing: 16) {
            editableAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(patient.alias)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Age \(ageText(for: patient))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    private var emptyAboutMeHeader: some View {
        HStack(spacing: 16) {
            editableAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text("No Patient")
                    .font(.title3.weight(.semibold))

                Text("Create a profile to show patient details here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
    }

    private var versionPill: some View {
        Button {
            showingVersionDetails = true
        } label: {
            Label {
                Text("Version: \(VersionDetails.current.appVersion)")
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            } icon: {
                Text("🧑🏽‍💻")
                    .font(.footnote)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .versionPillBackground()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("App version details")
        .popover(isPresented: $showingVersionDetails, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
            VersionDetailsView(storageInfo: store.storageInfo())
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCompactAdaptation(.sheet)
        }
    }

    private var editableAvatar: some View {
        Button {
            showingAvatarEditor = true
        } label: {
            ZStack(alignment: .bottomTrailing) {
                ProfileAvatarView(avatar: ProfileAvatarValue(storageValue: profileAvatar), size: 68)

                Image(systemName: "pencil")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor, in: Circle())
                    .overlay {
                        Circle().stroke(Color(.systemBackground), lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit avatar")
    }

    @ViewBuilder
    private func profileOptionalRow(_ title: String, _ value: String?) -> some View {
        if let value = normalizedProfileValue(value) {
            LabeledContent(title, value: value)
        }
    }

    @ViewBuilder
    private func profileCopyableOptionalRow(_ title: String, _ value: String?) -> some View {
        if let value = normalizedProfileValue(value) {
            LabeledContent {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(value)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        UIPasteboard.general.string = value
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy")
                }
            } label: {
                Text(title)
            }
        }
    }

    private func normalizedProfileValue(_ value: String?) -> String? {
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return nil
    }

    private func ageText(for patient: ParkinsonMetadata.Patient) -> String {
        guard let birthDate = patient.dateBirth?.toFoundationDate() else {
            return "Not available"
        }
        let years = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
        return years.map { "\($0)" } ?? "Not available"
    }
}

private struct VersionDetails {
    let appVersion: String
    let frontendGitHubURL: URL?
    let backendVersion: String
    let backendGitHubURL: URL?
    let deviceID: String
    let appStorage: String
    let sqliteSize: String
    let testFlightURL: URL?

    static var current: VersionDetails {
        VersionDetails(storageInfo: ParkinsonMetadataStore.shared.storageInfo())
    }

    init(storageInfo: ParkinsonMetadataStorageInfo) {
        appVersion = Self.bundleVersionText()
        frontendGitHubURL = URL(string: "https://github.com/MeropGont/vCRGlove")
        backendVersion = "ParkinsonMetadata"
        backendGitHubURL = URL(string: "https://github.com/UKEIAM/de.uke.iam.parkinson.metadata/tree/vcr_gloves")
        deviceID = AppDeviceIdentifier.current
        appStorage = Self.byteText(storageInfo.appStorageBytes)
        sqliteSize = Self.byteText(storageInfo.sqliteBytes)
        testFlightURL = nil
    }

    private static func bundleVersionText() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        switch (version?.nilIfBlank, build?.nilIfBlank) {
        case let (version?, build?) where version != build:
            return "\(version) (\(build))"
        case let (version?, _):
            return version
        case let (_, build?):
            return build
        default:
            return "Not set"
        }
    }

    private static func byteText(_ bytes: Int64?) -> String {
        guard let bytes else { return "Not available" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct VersionDetailsView: View {
    let storageInfo: ParkinsonMetadataStorageInfo
    @Environment(\.dismiss) private var dismiss

    private var details: VersionDetails {
        VersionDetails(storageInfo: storageInfo)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    detailRow("Version", details.appVersion)
                    linkRow("GitHub", url: details.frontendGitHubURL)
                    detailRow("Device ID", details.deviceID)
                    linkRow("TestFlight", url: details.testFlightURL)
                }

                Section("Storage Impact") {
                    detailRow("Device Storage", details.appStorage)
                    detailRow("SQLite Size", details.sqliteSize)
                }

                Section("Backend") {
                    detailRow("Package", details.backendVersion)
                    linkRow("GitHub", url: details.backendGitHubURL)
                }
            }
            .navigationTitle("App Version Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .frame(minWidth: 340, minHeight: 360)
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(title)
        }
    }

    @ViewBuilder
    private func linkRow(_ title: String, url: URL?) -> some View {
        if let url {
            LabeledContent {
                Link(url.host(percentEncoded: false) ?? url.absoluteString, destination: url)
                    .multilineTextAlignment(.trailing)
            } label: {
                Text(title)
            }
        } else {
            detailRow(title, "Not configured")
        }
    }
}

private extension View {
    @ViewBuilder
    func versionPillBackground() -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                self
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .overlay {
                        Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    }
            }
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(Color(.separator).opacity(0.25), lineWidth: 1)
                }
        }
    }
}

struct ProfileAvatarValue: Equatable {
    let emoji: String
    let colorName: String

    static let `default` = ProfileAvatarValue(emoji: "🙂", colorName: "purple")

    init(emoji: String, colorName: String) {
        self.emoji = emoji
        self.colorName = colorName
    }

    init(storageValue: String) {
        let parts = storageValue.split(separator: ";", maxSplits: 1).map(String.init)
        let emoji = parts.first?.nilIfBlank ?? Self.default.emoji
        let colorName = parts.dropFirst().first?.nilIfBlank ?? Self.default.colorName
        self.init(emoji: emoji, colorName: colorName)
    }

    var storageValue: String {
        "\(emoji);\(colorName)"
    }

    var colorOption: AvatarColorOption {
        AvatarColorOption.option(named: colorName)
    }
}

struct AvatarColorOption: Identifiable, Equatable {
    let name: String
    let color: Color

    var id: String { name }
    var isRainbow: Bool { name == "rainbow" }

    static let all: [AvatarColorOption] = [
        AvatarColorOption(name: "red", color: .red),
        AvatarColorOption(name: "orange", color: .orange),
        AvatarColorOption(name: "yellow", color: .yellow),
        AvatarColorOption(name: "green", color: .green),
        AvatarColorOption(name: "mint", color: .mint),
        AvatarColorOption(name: "teal", color: .teal),
        AvatarColorOption(name: "cyan", color: .cyan),
        AvatarColorOption(name: "blue", color: .blue),
        AvatarColorOption(name: "indigo", color: .indigo),
        AvatarColorOption(name: "purple", color: .purple),
        AvatarColorOption(name: "pink", color: .pink),
        AvatarColorOption(name: "brown", color: .brown),
        AvatarColorOption(name: "gray", color: .gray),
        AvatarColorOption(name: "black", color: .black),
        AvatarColorOption(name: "white", color: .white),
        AvatarColorOption(name: "rainbow", color: .clear)
    ]

    static func option(named name: String) -> AvatarColorOption {
        all.first { $0.name == name } ?? all.first { $0.name == ProfileAvatarValue.default.colorName } ?? all[0]
    }
}

struct ProfileAvatarView: View {
    let avatar: ProfileAvatarValue
    let size: CGFloat

    var body: some View {
        ZStack {
            AvatarColorCircle(option: avatar.colorOption, size: size)
            Text(avatar.emoji)
                .font(.system(size: size * 0.52))
        }
        .overlay {
            Circle().stroke(Color(.separator).opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        .accessibilityLabel("Avatar")
    }
}

struct AvatarColorCircle: View {
    let option: AvatarColorOption
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(.clear)
            .frame(width: size, height: size)
            .background {
                if option.isRainbow {
                    Circle()
                        .fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red], center: .center))
                } else {
                    Circle()
                        .fill(option.color.gradient)
                }
            }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct VCRSettingsView: View {
    var body: some View {
        List {
            Section("Session") {
                Text("Default duration")
                Text("Glove status and last connection time will go here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("vCR Settings")
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
