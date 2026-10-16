//
//  MedicationLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct MedicationLogView: View {
    let date: Date
    private let entryID: UUID?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var event: MedicationEvent? = nil
    @State private var motorState: MotorState? = nil
    @State private var factors: Set<MedicationFactor> = []
    @State private var note = ""
    @State private var noteExpanded = false
    @State private var saveFailed = false

    private let calendar = Calendar.current
    private var showNote: Bool { noteExpanded || !note.isEmpty || (event != nil && event != .usual) }

    init(date: Date, editing entry: JournalEntry? = nil) {
        self.date = entry?.date ?? date
        entryID = entry?.id
        _selectedTime = State(initialValue: entry?.date ?? Date())
        _event = State(initialValue: entry?.medicationEvent)
        _motorState = State(initialValue: entry?.motorState)
        _factors = State(initialValue: Set(entry?.medicationFactors ?? []))
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n("Medication"))
                    .font(.largeTitle.bold())

                DatePicker(L10n("Time"), selection: $selectedTime, displayedComponents: .hourAndMinute)

                sectionTitle("What happened?")

                ForEach(MedicationEvent.allCases) { item in
                    choiceButton(
                        title: item.displayName,
                        isSelected: event == item
                    ) {
                        event = item
                    }
                }

                if showNote {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionTitle("Note")
                        TextField(L10n("Add details"), text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)
                            .accessibilityIdentifier("journalMedicationNote")
                    }
                } else {
                    Button { noteExpanded = true } label: {
                        Label(L10n("Add note"), systemImage: "square.and.pencil")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("journalMedicationAddNote")
                }

                sectionTitle(entryID == nil && calendar.isDateInToday(date)
                    ? "How are you right now?" : "How did you feel at that time?")

                ForEach(MotorState.allCases) { state in
                    choiceButton(
                        title: state.displayName,
                        isSelected: motorState == state
                    ) {
                        motorState = state
                    }
                }

                sectionTitle("Anything that may affect it?")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                    ForEach(MedicationFactor.allCases) { factor in
                        Button {
                            if factors.contains(factor) {
                                factors.remove(factor)
                            } else {
                                factors.insert(factor)
                            }
                        } label: {
                            HStack {
                                Text(factor.displayName)
                                    .font(.subheadline)
                                Spacer()
                                if factors.contains(factor) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(factors.contains(factor) ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

            }
            .padding()
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button(L10n(entryID == nil ? "Save Medication Log" : "Save changes")) {
                let entry = JournalEntry(
                    date: combinedDate,
                    type: .medication,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
                    medicationEvent: event,
                    motorState: motorState,
                    medicationFactors: Array(factors).sorted { $0.rawValue < $1.rawValue }
                )

                let saved: Bool
                if let entryID {
                    saved = JournalStore.shared.updateMedication(id: entryID, date: combinedDate, event: event,
                        motorState: motorState, factors: entry.medicationFactors, note: entry.note)
                } else {
                    saved = JournalStore.shared.add(entry)
                }
                if saved {
                    dismiss()
                } else {
                    saveFailed = true
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(entryID == nil && event == nil)
            .accessibilityIdentifier("journalSaveMedication")
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(L10n("Medication"))
        .navigationBarTitleDisplayMode(.inline)
        .journalSaveAlert(isPresented: $saveFailed)
    }

    private var combinedDate: Date {
        if entryID != nil, calendar.compare(selectedTime, to: date, toGranularity: .minute) == .orderedSame {
            return date
        }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: selectedTime)

        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute
        components.second = calendar.component(.second, from: selectedTime)

        return calendar.date(from: components) ?? date
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(L10n(title))
            .font(.headline)
    }

    private func choiceButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("journalMedicationChoice-\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
