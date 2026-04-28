//
//  DailyLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct DailyLogView: View {
    let date: Date

    @ObservedObject private var store = JournalStore.shared

    private let calendar = Calendar.current

    private var entriesForDay: [JournalEntry] {
        store.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(date.formatted(date: .complete, time: .omitted))
                    .font(.title2.bold())

                dailyCheckInCard
                
                symptomEpisodeCard

                medicationCard
                
                noteCard

                timelineCard
            }
            .padding()
        }
        .navigationTitle("Daily Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dailyCheckInCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Daily Check-In")
                .font(.headline)

            Text("Mood, overall symptoms, and symptom list for this day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                DailyCheckInView(entryDate: date)
            } label: {
                Text("CHECK IN")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    private var symptomEpisodeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Symptom Episode")
                .font(.headline)

            Text("Log OFF periods, tremor, freezing, dyskinesia, or other symptom changes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                SymptomEpisodeLogView(date: date)
            } label: {
                Text("LOG SYMPTOM")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }


    private var medicationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Medication")
                .font(.headline)

            Text("Log usual, late, missed, or extra medication events.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                MedicationLogView(date: date)
            } label: {
                Text("LOG MEDICATION")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Note")
                .font(.headline)

            Text("Record anything unusual or important for this day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            NavigationLink {
                NoteLogView(date: date)
            } label: {
                Text("ADD NOTE")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }


    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Day timeline")
                .font(.headline)

            if entriesForDay.isEmpty {
                Text("No entries saved for this day yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entriesForDay) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: iconName(for: entry))
                            .foregroundStyle(.blue)
                            .frame(width: 28, height: 28)
                            .background(Color.blue.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline.weight(.semibold))

                            Text(summary(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func iconName(for entry: JournalEntry) -> String {
        switch entry.type {
        case .dailyCheckIn:
            return "heart.text.square.fill"
        case .medication:
            return "pills.fill"
        case .symptm:
            return "waveform.path.ecg"
        case .note:
            return "note.text"
        default:
            return "circle.fill"
        }
    }

    private func summary(for entry: JournalEntry) -> String {
        var parts: [String] = []

        if entry.type == .dailyCheckIn {
            parts.append("Daily check-in")
        }
        
        if entry.type == .symptm {
            parts.append("Symptom episode")
        }

        if let mood = entry.mood {
            parts.append("Mood \(mood)/5")
        }

        if let severity = entry.symptomSeverity {
            parts.append(severity.label)
        }
        
        if let medicationEvent = entry.medicationEvent {
            parts.append(medicationEvent.rawValue)
        }

        if let motorState = entry.motorState {
            parts.append(motorState.rawValue)
        }

        if !entry.medicationFactors.isEmpty {
            parts.append(entry.medicationFactors.map(\.rawValue).joined(separator: ", "))
        }

        if let note = entry.note {
            parts.append(note)
        }

        if !entry.symptoms.isEmpty {
            parts.append(entry.symptoms.joined(separator: ", "))
        }

        return parts.isEmpty ? "No details" : parts.joined(separator: " · ")
    }
}
