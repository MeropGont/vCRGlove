//
//  JournalCalendarView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct JournalCalendarPanel: View {
    @ObservedObject private var store = JournalStore.shared
    @ObservedObject private var taskStore = TaskSessionStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Date()

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n("Daily check-ins"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(locale)))
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
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 24)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
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
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)

                                Circle()
                                    .fill(markerColor(for: date))
                                    .frame(width: 5, height: 5)

                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(
                                Circle()
                                    .fill(dayBackgroundColor(for: date))
                                    .overlay(
                                        Circle()
                                            .stroke(hasMovementMeasurement(on: date) ? Color.purple : .clear, lineWidth: 3)
                                    )
                            )

                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
                        .accessibilityValue(dayAccessibilityValue(for: date))
                        .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
                        .accessibilityIdentifier("journalCalendarDay-\(calendar.component(.day, from: date))")
                    } else {
                        Color.clear
                            .frame(height: 42)
                    }
                }
            }

            calendarLegend

            Divider()

            selectedDaySummary
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var calendarLegend: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: 8) {
            legendItem("vCR log") {
                Circle().fill(Color.green.opacity(0.25))
                    .overlay(Circle().fill(.green).frame(width: 5, height: 5).offset(y: 5))
            }
            legendItem("Journal entry") {
                Circle().fill(.blue).frame(width: 5, height: 5)
            }
            legendItem("Movement session") {
                Circle().stroke(.purple, lineWidth: 3).padding(2)
            }
            legendItem("Selected day") {
                Circle().fill(.blue)
            }
        }
        .accessibilityIdentifier("journalCalendarLegend")
    }

    private func legendItem<Marker: View>(_ key: String, @ViewBuilder marker: () -> Marker) -> some View {
        HStack(alignment: .top, spacing: 8) {
            marker().frame(width: 20, height: 20).accessibilityHidden(true)
            Text(L10n(key))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func dayAccessibilityValue(for date: Date) -> String {
        var markers: [String] = []
        if hasStimulation(on: date) { markers.append(L10n("vCR log")) }
        if hasEntry(on: date) { markers.append(L10n("Journal entry")) }
        if hasMovementMeasurement(on: date) { markers.append(L10n("Movement session")) }
        return markers.joined(separator: ", ")
    }

    private var selectedDaySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(selectedDate.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale)))
                .font(.headline)

            let selectedEntries = entries(on: selectedDate)
            let selectedMovementSessions = movementSessions(on: selectedDate)

            if selectedEntries.isEmpty && selectedMovementSessions.isEmpty {
                Text(L10n("No check-in for this day"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(selectedEntries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                                .font(.subheadline.weight(.semibold))

                            Text(summary(for: entry))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }

                ForEach(selectedMovementSessions) { session in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "hand.tap.fill")
                            .foregroundStyle(.purple)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                                .font(.subheadline.weight(.semibold))

                            Text(String(format: L10n("Movement session: %d trial(s)"), session.trials.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(L10n(session.completionLabelKey))
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
                Text(L10n("OPEN DAILY LOG"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weekdaySymbols: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = dynamicTypeSize.isAccessibilitySize
            ? localizedCalendar.veryShortStandaloneWeekdaySymbols : localizedCalendar.shortStandaloneWeekdaySymbols
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
    
    private func movementSessions(on date: Date) -> [MovementSession] {
        taskStore.sessions
            .filter { calendar.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }
    
    private func hasStimulation(on date: Date) -> Bool {
        entries(on: date).contains { $0.type == .stimulation }
    }
    
    private func hasMovementMeasurement(on date: Date) -> Bool {
        taskStore.sessions.contains { calendar.isDate($0.date, inSameDayAs: date) }
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
            parts.append(L10n("vCR stimulation"))
        }

        if let mood = entry.mood {
            parts.append(String(format: L10n("Mood %d/5"), mood))
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


        return parts.isEmpty ? L10n("No details") : parts.joined(separator: " · ")
    }
}

struct JournalCalendarView: View {
    var body: some View {
        ScrollView {
            JournalCalendarPanel()
                .padding()
        }
        .navigationTitle(L10n("Calendar"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
