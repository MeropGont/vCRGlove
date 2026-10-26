import SwiftUI

struct JournalHomeView: View {
    @ObservedObject private var store = JournalStore.shared
    @ObservedObject private var taskStore = TaskSessionStore.shared
    @StateObject private var activity = JournalActivityController()
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
        + activity.sessions.filter { $0.trials.contains { Calendar.current.isDate($0.startedAt, inSameDayAs: selectedDate) } }.count
    }
    private var dayActivity: DailyActivitySummary? {
        activity.history?.summary(on: selectedDate, calendar: .current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                JournalCalendarPanel(selectedDate: $selectedDate, activity: activity)
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

                    VStack(spacing: 0) {
                        NavigationLink {
                            DailyLogView(date: selectedDate, filter: .stimulation, stimulationStarts: activity.starts)
                        } label: {
                            activityRow("vCR", status: stimulationStatus, icon: "waveform.path.ecg")
                        }
                        .accessibilityIdentifier("journalDayStimulation")
                        Divider()
                        NavigationLink {
                            DailyLogView(date: selectedDate, filter: .movement, scopedSessions: activity.sessions)
                        } label: {
                            activityRow("Movement", status: movementStatus, icon: "hand.tap")
                        }
                        .accessibilityIdentifier("journalDayMovement")
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 8) {
                        logButton(.medication, type: .medication, title: "Medication", icon: "pills", id: "journalAddMedication")
                        logButton(.symptom, type: .symptom, title: "Symptom episode", icon: "waveform.path.ecg", id: "journalAddSymptom")
                        logButton(.note, type: .note, title: "Notes", icon: "note.text", id: "journalAddNote")
                    }

                    NavigationLink {
                        DailyLogView(date: selectedDate, scopedSessions: activity.sessions)
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
        .modifier(JournalActivityLifecycle(activity: activity))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $eventDestination) { destination in
            switch destination {
            case .medication: MedicationLogView(date: selectedDate)
            case .symptom: SymptomEpisodeLogView(date: selectedDate)
            case .note: NoteLogView(date: selectedDate)
            }
        }
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--ui-test-activity-calendar"), store.entries.isEmpty else { return }
            let now = Date().addingTimeInterval(-60)
            for offset in 0..<3 {
                let date = Calendar.current.date(byAdding: .day, value: -offset, to: now)!
                _ = store.add(.init(date: date, type: .dailyCheckIn, mood: 3))
            }
            _ = store.add(.init(date: now, type: .stimulation, note: "Start request"))
            activity.events.append(type: "stimulation_started", tag: "vCR", message: "UI fixture")
            let trial = Trial(taskType: .fingerTap, side: .right, source: .camera,
                stopCondition: .thirtySec, startedAt: now, samples: [], metrics: .empty, recordedDurationSeconds: 10)
            let id = UserDefaults.standard.string(forKey: "patientID") ?? "unset"
            taskStore.saveAcceptedTrial(trial, in: .init(patientId: id, date: now), temporaryVideoURL: nil) { _ in }
        }
        #endif
    }

    private var stimulationStatus: String {
        guard let dayActivity else { return L10n(activity.failed ? "routine.unavailable" : "routine.loading") }
        return L10n(dayActivity.hasRecordedStimulationStart ? "routine.startRecorded"
            : dayActivity.hasStimulationLog ? "routine.startUnverified" : "None recorded")
    }

    private var movementStatus: String {
        guard let dayActivity else { return L10n(activity.failed ? "routine.unavailable" : "routine.loading") }
        return dayActivity.savedMeasurementCount == 0 ? L10n("None recorded") : String(format:
            L10n(dayActivity.savedMeasurementCount == 1 ? "routine.oneMeasurement" : "routine.measurements"), dayActivity.savedMeasurementCount)
    }

    private func activityRow(_ title: String, status: String, icon: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 24)).foregroundStyle(.teal).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n(title)).font(.body.weight(.semibold))
                Text(status).font(.subheadline).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.vertical, 10)
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
