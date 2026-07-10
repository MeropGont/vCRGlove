//
//  MovementExportView.swift
//  vCRGlove
//
//  Clinic-facing export screen for movement task sessions (Task F).
//  Writes JSON / CSV files to Documents/vcr/tasks/exports/ (reachable via the
//  Files app) and offers immediate sharing via ShareLink (AirDrop, Mail, …).
//

import SwiftUI

struct MovementExportView: View {
    @ObservedObject private var store = TaskSessionStore.shared

    @State private var lastExport: URL?
    @State private var errorMessage: String?

    private var trialCount: Int { store.sessions.reduce(0) { $0 + $1.trials.count } }

    var body: some View {
        Form {
            Section {
                LabeledContent("Sessions", value: "\(store.sessions.count)")
                LabeledContent("Trials", value: "\(trialCount)")
            } header: {
                Text("Recorded data")
            }

            Section {
                exportButton("JSON (full sessions)", systemImage: "doc.badge.gearshape") {
                    try TaskSessionExporter.exportJSON(store.sessions)
                }
                exportButton("CSV — metrics per trial", systemImage: "tablecells") {
                    try TaskSessionExporter.exportMetricsCSV(store.sessions)
                }
                exportButton("CSV — raw samples", systemImage: "waveform.path") {
                    try TaskSessionExporter.exportSamplesCSV(store.sessions)
                }
            } header: {
                Text("Export")
            } footer: {
                Text("Files are saved to vcr/tasks/exports and can also be accessed from the Files app.")
            }

            if let url = lastExport {
                Section("Last export") {
                    LabeledContent("File", value: url.lastPathComponent)
                    ShareLink(item: url) {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Movement Data Export")
    }

    private func exportButton(_ title: String, systemImage: String,
                              _ action: @escaping () throws -> URL) -> some View {
        Button {
            do {
                lastExport = try action()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

#Preview {
    NavigationStack { MovementExportView() }
}
