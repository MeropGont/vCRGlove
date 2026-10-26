import SwiftUI

struct DailyLogView: View {
    enum Filter { case all, stimulation, movement }
    let date: Date
    var filter: Filter = .all
    var stimulationStarts: [Date] = []
    var scopedSessions: [MovementSession]? = nil
    @ObservedObject private var store = JournalStore.shared
    @ObservedObject private var taskStore = TaskSessionStore.shared
    @Environment(\.locale) private var locale

    private var entries: [JournalEntry] {
        store.entries.filter {
            Calendar.current.isDate($0.date, inSameDayAs: date) && filter != .movement
                && (filter != .stimulation || $0.type == .stimulation)
        }.sorted { $0.date > $1.date }
    }
    private var sessions: [MovementSession] {
        guard filter != .stimulation else { return [] }
        return (scopedSessions ?? taskStore.sessions).compactMap { session in
            let trials = session.trials.filter { Calendar.current.isDate($0.startedAt, inSameDayAs: date) }
            guard !trials.isEmpty else { return nil }
            return MovementSession(id: session.id, patientId: session.patientId, date: trials.map(\.startedAt).max()!,
                stimulationContext: session.stimulationContext, trials: trials)
        }.sorted { $0.date > $1.date }
    }

    private var startMinutes: [Date] {
        guard filter == .stimulation else { return [] }
        return Set(stimulationStarts.filter { Calendar.current.isDate($0, inSameDayAs: date) }
            .compactMap { Calendar.current.dateInterval(of: .minute, for: $0)?.start }).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if entries.isEmpty && sessions.isEmpty && startMinutes.isEmpty {
                    Text(L10n("No entries saved for this day yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(startMinutes, id: \.self) { start in
                    Label {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n("routine.startRecorded")).font(.headline)
                            Text(start.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                                .foregroundStyle(.secondary)
                        }
                    } icon: { Image(systemName: "waveform.path.ecg").foregroundStyle(.teal) }
                }
                ForEach(entries) { entry in
                    if entry.type == .medication {
                        NavigationLink { MedicationLogView(date: entry.date, editing: entry) } label: {
                            entryRow(entry, editable: true)
                        }
                        .accessibilityIdentifier("journalEditMedication-\(entry.id)")
                        .accessibilityHint(L10n("Edit entry"))
                    } else if entry.type == .symptom {
                        NavigationLink { SymptomEpisodeLogView(date: entry.date, editing: entry) } label: {
                            entryRow(entry, editable: true)
                        }
                        .accessibilityIdentifier("journalEditSymptom-\(entry.id)")
                        .accessibilityHint(L10n("Edit entry"))
                    } else if entry.type == .dailyCheckIn && entry.id == store.dailyCheckIn(on: date)?.id {
                        NavigationLink { DailyCheckInView(entryDate: date) } label: {
                            entryRow(entry, editable: true)
                        }
                        .accessibilityIdentifier("journalEditDailyCheckIn")
                        .accessibilityHint(L10n("Edit entry"))
                    } else { entryRow(entry, editable: false) }
                    Divider()
                }
                ForEach(sessions) { session in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "hand.tap").foregroundStyle(.purple).frame(width: 24)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n("Movement session")).font(.headline)
                            Text(session.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(String(format: L10n("Movement session: %d trial(s)"), session.trials.count))
                                .font(.subheadline)
                            Text(L10n(session.completionLabelKey)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
            .buttonStyle(.plain)
            .padding()
        }
        .navigationTitle(L10n("Entries"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func entryRow(_ entry: JournalEntry, editable: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.iconName).foregroundStyle(.teal).frame(width: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title).font(.headline)
                Text(timestamp(for: entry))
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.detailSummary).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if editable {
                Image(systemName: "pencil").foregroundStyle(Color.accentColor)
                    .frame(width: 24, height: 24).accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.primary)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func timestamp(for entry: JournalEntry) -> String {
        if entry.type == .dailyCheckIn {
            if let savedAt = entry.updatedAt {
                return String(format: L10n("Last saved: %@"), savedAt.formatted(
                    Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))
            }
            return entry.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(locale))
        }
        return entry.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }
}
