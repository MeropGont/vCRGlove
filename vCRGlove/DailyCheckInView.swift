import SwiftUI

struct DailyCheckInView: View {
    let entryDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject private var store = JournalStore.shared

    @State private var mood: Int?
    @State private var impact: DailyActivityImpact?
    @State private var saveFailed = false
    @State private var logDestination: LogDestination?

    private enum LogDestination: String, Hashable { case medication, symptom }
    private let moodSymbols = ["😣", "🙁", "😐", "🙂", "😄"]

    init(entryDate: Date = Date()) {
        self.entryDate = entryDate
        let existing = JournalStore.shared.dailyCheckIn(on: entryDate)
        _mood = State(initialValue: existing?.mood)
        _impact = State(initialValue: existing?.activityImpact)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(entryDate) }
    private var hasAnswer: Bool {
        mood != nil || impact != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entryDate.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("journalCheckInDate")
                        question(isToday ? "How are you today?" : "How were you feeling that day?")
                            .accessibilityIdentifier("journalMoodQuestion")
                    }
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) { moodChoices }
                    } else {
                        HStack(alignment: .top, spacing: 6) { moodChoices }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    question(isToday ? "How much did Parkinson's affect your usual activities today?"
                                    : "How much did Parkinson's affect your usual activities that day?")
                    VStack(spacing: 8) {
                        ForEach(DailyActivityImpact.ratingChoices, id: \.self) { value in
                            choice(value.label, selected: impact == value, id: "journalImpact-\(value.rawValue)",
                                   tint: impactTint(value)) {
                                impact = value
                            }
                        }
                    }
                    choice(DailyActivityImpact.unsure.label, selected: impact == .unsure,
                           id: "journalImpact-unsure") { impact = .unsure }
                }

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 8) { logShortcuts }
                } else {
                    HStack(spacing: 8) { logShortcuts }
                }
                if !hasAnswer {
                    Text(L10n("Choose at least one answer to save."))
                        .font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    if store.saveMoodAndImpactCheckIn(date: entryDate, mood: mood, impact: impact) {
                        dismiss()
                    } else { saveFailed = true }
                } label: {
                    Label(L10n("Save"), systemImage: "checkmark")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasAnswer || store.isLoadBlocked)
                .accessibilityIdentifier("journalSaveCheckIn")
            }
            .padding()
            .background(.regularMaterial)
        }
        .navigationTitle(L10n("Daily Check-In"))
        .navigationBarTitleDisplayMode(.inline)
        .journalSaveAlert(isPresented: $saveFailed)
        .navigationDestination(item: $logDestination) { destination in
            switch destination {
            case .medication: MedicationLogView(date: entryDate)
            case .symptom: SymptomEpisodeLogView(date: entryDate)
            }
        }
    }

    private var moodChoices: some View {
        ForEach(1...5, id: \.self) { value in
            Button { mood = value } label: {
                VStack(spacing: 6) {
                    Text(moodSymbols[value - 1]).font(.system(size: 28))
                    Text(MoodRating.allCases[value - 1].checkInLabel)
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 72)
                .padding(.vertical, 8)
                .background(moodTint(value).opacity(shadeOpacity))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(mood == value ? Color.accentColor : .clear, lineWidth: 2))
                .overlay(alignment: .topTrailing) {
                    if mood == value {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Color.accentColor)
                            .padding(5)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoodRating.allCases[value - 1].checkInLabel)
            .accessibilityIdentifier("journalMood-\(value)")
            .accessibilityAddTraits(mood == value ? .isSelected : [])
        }
    }

    private func question(_ key: String) -> some View {
        Text(L10n(key)).font(.headline).fixedSize(horizontal: false, vertical: true)
    }

    private var logShortcuts: some View {
        Group {
            logShortcut(.medication, title: "Medication", icon: "pills", id: "journalShortcutMedication")
            logShortcut(.symptom, title: "Log symptoms", icon: "waveform.path.ecg", id: "journalShortcutSymptoms")
        }
    }

    private func logShortcut(_ destination: LogDestination, title: String, icon: String, id: String) -> some View {
        Button {
            if hasAnswer && !store.saveMoodAndImpactCheckIn(date: entryDate, mood: mood, impact: impact) {
                saveFailed = true
                return
            }
            logDestination = destination
        } label: {
            Label(L10n(title), systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .disabled(store.isLoadBlocked)
        .accessibilityIdentifier(id)
    }

    private var shadeOpacity: Double { colorSchemeContrast == .increased ? 0.18 : 0.08 }

    private func moodTint(_ value: Int) -> Color {
        switch value {
        case 1: return .red
        case 2: return .orange
        case 3: return Color(.systemGray)
        case 4: return .mint
        default: return .green
        }
    }

    private func impactTint(_ value: DailyActivityImpact) -> Color {
        switch value {
        case .notAtAll: return .green
        case .little: return .mint
        case .moderate: return .yellow
        case .large: return .orange
        case .unable: return .red
        case .unsure, .skipped: return Color(.systemGray)
        }
    }

    private func choice(_ title: String, selected: Bool, id: String, tint: Color? = nil,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .font(.subheadline)
            .foregroundStyle(Color.primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(tint.map { $0.opacity(shadeOpacity) }
                        ?? (selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct JournalSaveAlert: ViewModifier {
    @Binding var isPresented: Bool
    @ObservedObject private var store = JournalStore.shared

    func body(content: Content) -> some View {
        content.alert(L10n("Journal not saved"), isPresented: $isPresented) {
            Button(L10n("OK"), role: .cancel) { }
        } message: {
            Text(store.saveErrorMessage ?? L10n("Your entry was not saved. Your answers are still here. Please try again."))
        }
    }
}

extension View {
    func journalSaveAlert(isPresented: Binding<Bool>) -> some View {
        modifier(JournalSaveAlert(isPresented: isPresented))
    }
}
