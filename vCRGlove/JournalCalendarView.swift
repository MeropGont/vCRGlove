import SwiftUI

struct JournalCalendarPanel: View {
    @Binding var selectedDate: Date
    @ObservedObject private var store = JournalStore.shared
    @ObservedObject private var taskStore = TaskSessionStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(locale)))
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                monthButton("chevron.left", title: "Previous month", offset: -1)
                monthButton("chevron.right", title: "Next month", offset: 1)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(height: 24).lineLimit(1).minimumScaleFactor(0.5)
                }
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button { selectedDate = date } label: {
                            VStack(spacing: 4) {
                                Text("\(calendar.component(.day, from: date))")
                                    .font(.subheadline.weight(isSelected(date) ? .bold : .regular))
                                    .foregroundStyle(isSelected(date) ? Color.white : Color.primary)
                                    .lineLimit(1).minimumScaleFactor(0.5)
                                Circle().fill(markerColor(for: date)).frame(width: 5, height: 5)
                            }
                            .frame(maxWidth: .infinity).frame(height: 44)
                            .background(Circle().fill(dayBackgroundColor(for: date))
                                .overlay(Circle().stroke(hasMovement(on: date) ? Color.purple : .clear, lineWidth: 3)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
                        .accessibilityValue(dayAccessibilityValue(for: date))
                        .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
                        .accessibilityIdentifier("journalCalendarDay-\(calendar.component(.day, from: date))")
                    } else { Color.clear.frame(height: 44) }
                }
            }

            calendarLegend
            if !calendar.isDateInToday(selectedDate) {
                Button {
                    selectedDate = Date()
                    displayedMonth = calendar.startOfMonth(for: selectedDate)
                } label: {
                    Label(L10n("Today"), systemImage: "calendar")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("journalReturnToday")
            }
        }
    }

    private func monthButton(_ symbol: String, title: String, offset: Int) -> some View {
        Button {
            guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
            displayedMonth = month
            selectedDate = month
        } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n(title))
        .help(L10n(title))
        .accessibilityIdentifier(offset < 0 ? "journalPreviousMonth" : "journalNextMonth")
    }

    private var calendarLegend: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                  alignment: .leading, spacing: 8) {
            legendItem("vCR log") {
                Circle().fill(Color.green.opacity(0.25))
                    .overlay(Circle().fill(.green).frame(width: 5, height: 5).offset(y: 5))
            }
            legendItem("Journal entry") { Circle().fill(.blue).frame(width: 5, height: 5) }
            legendItem("Movement session") { Circle().stroke(.purple, lineWidth: 3).padding(2) }
            legendItem("Selected day") { Circle().fill(.blue) }
        }
        .accessibilityIdentifier("journalCalendarLegend")
    }

    private func legendItem<Marker: View>(_ key: String, @ViewBuilder marker: () -> Marker) -> some View {
        HStack(alignment: .top, spacing: 8) {
            marker().frame(width: 20, height: 20).accessibilityHidden(true)
            Text(L10n(key)).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
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
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: displayedMonth) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map {
            calendar.date(byAdding: .day, value: $0 - 1, to: displayedMonth)
        }
    }

    private func hasEntry(on date: Date) -> Bool {
        store.entries.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }
    private func hasStimulation(on date: Date) -> Bool {
        store.entries.contains { $0.type == .stimulation && calendar.isDate($0.date, inSameDayAs: date) }
    }
    private func hasMovement(on date: Date) -> Bool {
        taskStore.sessions.contains { calendar.isDate($0.date, inSameDayAs: date) }
    }
    private func isSelected(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: selectedDate) }

    private func dayBackgroundColor(for date: Date) -> Color {
        if isSelected(date) { return .blue }
        return hasStimulation(on: date) ? Color.green.opacity(0.25) : Color(.systemGray6)
    }
    private func markerColor(for date: Date) -> Color {
        if hasStimulation(on: date) { return isSelected(date) ? .white : .green }
        if hasEntry(on: date) { return isSelected(date) ? .white : .blue }
        return .clear
    }
    private func dayAccessibilityValue(for date: Date) -> String {
        var markers: [String] = []
        if hasStimulation(on: date) { markers.append(L10n("vCR log")) }
        if hasEntry(on: date) { markers.append(L10n("Journal entry")) }
        if hasMovement(on: date) { markers.append(L10n("Movement session")) }
        return markers.joined(separator: ", ")
    }
}

struct JournalCalendarView: View {
    @State private var selectedDate = Date()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JournalCalendarPanel(selectedDate: $selectedDate)
                NavigationLink { DailyLogView(date: selectedDate) } label: {
                    Label(L10n("View entries"), systemImage: "list.bullet").frame(minHeight: 44)
                }
            }
            .padding()
        }
            .navigationTitle(L10n("Calendar"))
            .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
