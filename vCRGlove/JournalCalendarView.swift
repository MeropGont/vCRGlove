//
//  JournalCalendarView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct JournalCalendarPanel: View {
    @ObservedObject private var store = JournalStore.shared

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily check-ins")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                        .font(.title2.bold())
                }

                Spacer()

                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)

                Button {
                    displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                }

                ForEach(calendarDays, id: \.self) { date in
                    if let date {
                        Button {
                            selectedDate = date
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.subheadline.weight(isSelected(date) ? .bold : .regular))
                                    .foregroundStyle(isSelected(date) ? .white : .primary)

                                Circle()
                                    .fill(markerColor(for: date))
                                    .frame(width: 5, height: 5)

                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                Circle()
                                    .fill(dayBackgroundColor(for: date))
                            )

                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(height: 42)
                    }
                }
            }

            Divider()

            selectedDaySummary
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var selectedDaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                .font(.headline)

            let selectedEntries = entries(on: selectedDate)

            if selectedEntries.isEmpty {
                Text("No check-in for this day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedEntries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

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

            NavigationLink {
                DailyLogView(date: selectedDate)
            } label: {
                Text("OPEN DAILY LOG")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var calendarDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leadingEmptyDays = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [Date?] = Array(repeating: nil, count: leadingEmptyDays)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: displayedMonth) {
                days.append(date)
            }
        }

        return days
    }

    private func entries(on date: Date) -> [JournalEntry] {
        store.entries
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    private func hasEntry(on date: Date) -> Bool {
        !entries(on: date).isEmpty
    }
    
    private func hasStimulation(on date: Date) -> Bool {
        entries(on: date).contains { $0.type == .stimulation }
    }

    private func dayBackgroundColor(for date: Date) -> Color {
        if isSelected(date) {
            return .blue
        }

        if hasStimulation(on: date) {
            return Color.green.opacity(0.25)
        }

        return Color(.systemGray6)
    }

    private func markerColor(for date: Date) -> Color {
        if hasStimulation(on: date) {
            return isSelected(date) ? .white : .green
        }

        if hasEntry(on: date) {
            return isSelected(date) ? .white : .blue
        }

        return .clear
    }


    private func isSelected(_ date: Date) -> Bool {
        calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func summary(for entry: JournalEntry) -> String {
        var parts: [String] = []
        
        if entry.type == .stimulation {
            parts.append("vCR stimulation")
        }

        if let mood = entry.mood {
            parts.append("Mood \(mood)/5")
        }

        if let severity = entry.symptomSeverity {
            parts.append(severity.label)
        }

        if !entry.symptoms.isEmpty {
            parts.append(entry.symptoms.joined(separator: ", "))
        }
        
        if let note = entry.note {
            parts.append(note)
        }


        return parts.isEmpty ? "No details" : parts.joined(separator: " · ")
    }
}

struct JournalCalendarView: View {
    var body: some View {
        ScrollView {
            JournalCalendarPanel()
                .padding()
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
