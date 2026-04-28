//
//  JournalHomeView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import SwiftUI

struct JournalHomeView: View {
    @ObservedObject private var store = JournalStore.shared

    private var lastEntry: JournalEntry? {
        store.entries.sorted { $0.date > $1.date }.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Journal")
                    .font(.largeTitle.bold())

                Text("Track daily symptoms, mood, and notes around your vCR sessions.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                dailyCheckInCard

                JournalCalendarPanel()

                lastCheckInCard
            }
            .padding()
        }
    }

    private var dailyCheckInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily Check-In")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("How are you today?")
                        .font(.title3.bold())
                }

                Spacer()

                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            if let last = lastEntry {
                Text("Last saved: \(last.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("No check-in saved yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            NavigationLink {
                DailyLogView(date: Date())
            } label: {
                Text("OPEN TODAY'S LOG")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var lastCheckInCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last check-in")
                .font(.headline)

            if let last = lastEntry {
                HStack(spacing: 12) {
                    moodIcon(for: last.mood)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(last.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.semibold))

                        Text(summary(for: last))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            } else {
                Text("Your most recent check-in will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func moodIcon(for mood: Int?) -> some View {
        let symbol: String

        switch mood {
        case 1: symbol = "face.dashed"
        case 2: symbol = "face.smiling.inverse"
        case 3: symbol = "circle"
        case 4: symbol = "face.smiling"
        case 5: symbol = "sun.max.fill"
        default: symbol = "questionmark.circle"
        }

        return Image(systemName: symbol)
            .font(.title2)
            .foregroundStyle(.blue)
            .frame(width: 36, height: 36)
            .background(Color.blue.opacity(0.12))
            .clipShape(Circle())
    }

    private func summary(for entry: JournalEntry) -> String {
        var parts: [String] = []

        if let mood = entry.mood {
            parts.append("Mood \(mood)/5")
        }

        if let severity = entry.symptomSeverity {
            parts.append(severity.label)
        }

        if !entry.symptoms.isEmpty {
            parts.append(entry.symptoms.joined(separator: ", "))
        }

        return parts.isEmpty ? "No details" : parts.joined(separator: " · ")
    }
}
