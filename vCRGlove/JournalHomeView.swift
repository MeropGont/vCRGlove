import SwiftUI

struct JournalHomeView: View {
    @ObservedObject private var store = JournalStore.shared
    @ObservedObject private var taskStore = TaskSessionStore.shared
    @Environment(\.locale) private var locale
    @State private var selectedDate = Date()
    @State private var eventDestination: EventDestination?

    private enum EventDestination: String, Hashable { case medication, symptom, note }
    private var checkIn: JournalEntry? { store.dailyCheckIn(on: selectedDate) }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDate) }
    private var isFuture: Bool {
        Calendar.current.startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date())
    }
    private var entryCount: Int {
        store.entries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }.count
        + taskStore.sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                JournalCalendarPanel(selectedDate: $selectedDate)
                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text(isToday ? L10n("Today") : selectedDate.formatted(
                        Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("journalSelectedDay")

                    if store.isLoadBlocked {
                        Text(L10n("Your saved journal could not be opened. Nothing has been overwritten. Please try restarting the app."))
                            .font(.subheadline).foregroundStyle(.red)
                    } else if let checkIn {
                        Label(L10n(isToday ? "Checked in today" : "Check-in completed"), systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                            .accessibilityIdentifier("journalCheckInStatus")
                        if !checkIn.checkInSummary.isEmpty {
                            Text(checkIn.checkInSummary)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text(L10n(isFuture ? "No entries yet" : "No check-in yet"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        DailyCheckInView(entryDate: selectedDate)
                    } label: {
                        Label(L10n(checkIn != nil ? "Edit check-in" : isToday ? "Today's check-in" : "Check in"),
                              systemImage: checkIn != nil ? "pencil" : "heart.text.square")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isFuture || store.isLoadBlocked)
                    .accessibilityIdentifier("journalOpenCheckIn")

                    VStack(spacing: 8) {
                        logButton(.medication, type: .medication, title: "Medication", icon: "pills", id: "journalAddMedication")
                        logButton(.symptom, type: .symptom, title: "Symptom episode", icon: "waveform.path.ecg", id: "journalAddSymptom")
                        logButton(.note, type: .note, title: "Notes", icon: "note.text", id: "journalAddNote")
                    }

                    NavigationLink {
                        DailyLogView(date: selectedDate)
                    } label: {
                        HStack {
                            Label(L10n("View entries"), systemImage: "list.bullet")
                            Spacer()
                            Text("\(entryCount)").monospacedDigit().foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("journalViewEntries")
                    .padding(.top, 4)
                }
            }
            .padding()
        }
        .navigationTitle(L10n("Journal"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $eventDestination) { destination in
            switch destination {
            case .medication: MedicationLogView(date: selectedDate)
            case .symptom: SymptomEpisodeLogView(date: selectedDate)
            case .note: NoteLogView(date: selectedDate)
            }
        }
    }

    private func logButton(_ destination: EventDestination, type: JournalEntryType,
                           title: String, icon: String, id: String) -> some View {
        let count = store.entries.filter {
            $0.type == type && Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }.count
        return Button { eventDestination = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n(title)).font(.body.weight(.semibold))
                    Text(count == 0 ? L10n("None recorded")
                         : String(format: L10n(count == 1 ? "%d entry" : "%d entries"), count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isFuture || store.isLoadBlocked)
        .accessibilityIdentifier(id)
    }
}
