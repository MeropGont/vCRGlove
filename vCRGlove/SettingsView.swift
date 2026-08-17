//
//  SettingsView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 11.05.26.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("showResearchTab") private var showResearchTab = false
    @AppStorage("patientID") private var patientID = ""

    @State private var researchPassword = ""
    @State private var researchUnlocked = false
    @State private var passwordError = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    VCRSettingsView()
                } label: {
                    SettingsRow(icon: "waveform.path.ecg", color: .blue, title: L10n("vCR Settings"), subtitle: L10n("Duration, gloves, and session preferences"))
                }

                NavigationLink {
                    ProfileSettingsView(patientID: $patientID)
                } label: {
                    SettingsRow(icon: "person.crop.circle", color: .purple, title: L10n("Profile"), subtitle: L10n("ID, icon, and language"))
                }

                NavigationLink {
                    ReminderSettingsView()
                } label: {
                    SettingsRow(icon: "bell.badge", color: .orange, title: L10n("Reminders"), subtitle: L10n("vCR, journal, and task notifications"))
                }

                NavigationLink {
                    PrivacyDataSettingsView()
                } label: {
                    SettingsRow(icon: "lock.shield", color: .green, title: L10n("Privacy & Data"), subtitle: L10n("Permissions, storage, and data handling"))
                }

                NavigationLink {
                    InstructionsSettingsView()
                } label: {
                    SettingsRow(icon: "book.closed", color: .teal, title: L10n("Instructions"), subtitle: L10n("Gloves, vCR, journal, and troubleshooting"))
                }
            }

            Section(L10n("Research Mode")) {
                if researchUnlocked {
                    Toggle(L10n("Show Research Tab"), isOn: $showResearchTab)

                    NavigationLink {
                        ResearchAdminSettingsView(patientID: patientID)
                    } label: {
                        SettingsRow(icon: "slider.horizontal.3", color: .indigo, title: L10n("Research Admin"), subtitle: L10n("Logs, exports, backup, and study notes"))
                    }
                } else {
                    SecureField(L10n("Password"), text: $researchPassword)

                    Button(L10n("Unlock Research Mode")) {
                        if researchPassword == "vcr2026" {
                            researchUnlocked = true
                            passwordError = false
                            researchPassword = ""
                        } else {
                            passwordError = true
                        }
                    }

                    if passwordError {
                        Text(L10n("Incorrect password"))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section {
                NavigationLink {
                    SupportSettingsView(patientID: patientID)
                } label: {
                    SettingsRow(icon: "questionmark.circle", color: .pink, title: L10n("Need Help?"), subtitle: L10n("Contact ICNS support"))
                }
            }
        }
        .navigationTitle(L10n("Settings"))
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
            }
        }
        .padding(.vertical, 4)
    }
}

private struct VCRSettingsView: View {
    var body: some View {
        List {
            Section(L10n("Session")) {
                Text(L10n("Default duration"))
                Text(L10n("Glove status and last connection time will go here."))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n("vCR Settings"))
    }
}

private struct ProfileSettingsView: View {
    @Binding var patientID: String
    @StateObject private var appSettings = AppSettings.shared

    var body: some View {
        Form {
            Section(L10n("Profile")) {
                TextField(L10n("ID"), text: $patientID)
                Text(L10n("Avatar selection will go here."))
                    .foregroundStyle(.secondary)
            }

            Section(L10n("Language")) {
                Picker(L10n("Language"), selection: $appSettings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(L10n("Font Size")) {
                Picker(L10n("Font Size"), selection: $appSettings.fontSize) {
                    ForEach(AppFontSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .navigationTitle(L10n("Profile"))
    }
}

private struct ReminderSettingsView: View {
    var body: some View {
        List {
            Section(L10n("Reminders")) {
                Text(L10n("vCR reminders"))
                Text(L10n("Journal reminders"))
                Text(L10n("Task reminders"))
                Text(L10n("Quiet hours"))
            }
        }
        .navigationTitle(L10n("Reminders"))
    }
}

private struct PrivacyDataSettingsView: View {
    var body: some View {
        List {
            Section(L10n("Privacy & Data")) {
                Text(L10n("Stored data"))
                Text(L10n("Permissions"))
                Text(L10n("Storage status"))
                Text(L10n("Backup status"))
            }
        }
        .navigationTitle(L10n("Privacy & Data"))
    }
}

private struct InstructionsSettingsView: View {
    var body: some View {
        List {
            Section(L10n("Instructions")) {
                Text(L10n("Gloves"))
                Text(L10n("vCR session"))
                Text(L10n("Journal"))
                Text(L10n("Troubleshooting"))
                Text(L10n("Future movement tasks"))
            }
        }
        .navigationTitle(L10n("Instructions"))
    }
}

private struct ResearchAdminSettingsView: View {
    let patientID: String

    var body: some View {
        List {
            Section(L10n("Study")) {
                Text(String(format: L10n("ID: %@"), patientID.isEmpty ? L10n("Not set") : patientID))
                Text(L10n("Study start date"))
                Text(L10n("Patient notes"))
            }

            Section(L10n("Data")) {
                NavigationLink {
                    MovementExportView()
                } label: {
                    Text(L10n("Movement task export"))
                }
                Text(L10n("Export logs"))
                Text(L10n("Sync data"))
                Text(L10n("Storage size"))
                Text(L10n("Latest backup"))
            }

            Section(L10n("Diagnostics")) {
                Text(L10n("Bluetooth diagnostics"))
                Text(L10n("App version"))
                Text(L10n("Device version"))
            }
        }
        .navigationTitle(L10n("Research Admin"))
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
                    ForEach(troubleshootingSteps, id: \.question) { item in
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

                Text("ICNS")
                Link("015221500869", destination: URL(string: "tel:015221500869")!)

                if let supportEmailURL {
                    Link(L10n("Send Email to vcr@uke.de"), destination: supportEmailURL)
                }
            }
        }
        .navigationTitle(L10n("Troubleshooting"))
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
