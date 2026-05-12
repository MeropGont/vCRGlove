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
                    SettingsRow(icon: "waveform.path.ecg", color: .blue, title: "vCR Settings", subtitle: "Duration, gloves, and session preferences")
                }

                NavigationLink {
                    ProfileSettingsView(patientID: $patientID)
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
                        ResearchAdminSettingsView(patientID: patientID)
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

private struct ProfileSettingsView: View {
    @Binding var patientID: String

    var body: some View {
        Form {
            Section("Profile") {
                TextField("ID", text: $patientID)
                Text("Language: English / Deutsch")
                    .foregroundStyle(.secondary)
                Text("Avatar selection will go here.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profile")
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

private struct SupportSettingsView: View {
    let patientID: String

    @State private var topic = "App problem"

    private let topics = [
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
            Section("Contact") {
                Text("ICNS")
                Link("015221500869", destination: URL(string: "tel:015221500869")!)
                Link("vcr@uke.de", destination: URL(string: "mailto:vcr@uke.de")!)
            }

            Section("Problem Topic") {
                Picker("Topic", selection: $topic) {
                    ForEach(topics, id: \.self) { topic in
                        Text(topic)
                    }
                }

                if let supportEmailURL {
                    Link("Send Email", destination: supportEmailURL)
                }
            }
        }
        .navigationTitle("Need Help?")
    }
}
