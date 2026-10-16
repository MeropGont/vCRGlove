//
//  SymptomEpisodeLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct SymptomEpisodeLogView: View {
    let date: Date
    private let entryID: UUID?
    private let originalSymptoms: Set<String>
    private let originalSeverity: SymptomSeverity?

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var selectedSymptoms: Set<String> = []
    @State private var severity: SymptomSeverity? = nil
    @State private var motorState: MotorState? = nil
    @State private var note = ""
    @State private var saveFailed = false

    private let calendar = Calendar.current

    init(date: Date, editing entry: JournalEntry? = nil) {
        self.date = entry?.date ?? date
        entryID = entry?.id
        originalSymptoms = Set(entry?.symptoms ?? [])
        originalSeverity = entry?.symptomSeverity
        _selectedTime = State(initialValue: entry?.date ?? Date())
        _selectedSymptoms = State(initialValue: Set(entry?.symptoms ?? []))
        _severity = State(initialValue: entry?.symptomSeverity)
        _motorState = State(initialValue: entry?.motorState)
        _note = State(initialValue: entry?.note ?? "")
    }
    
    private var isSaveDisabled: Bool {
        if entryID != nil && selectedSymptoms == originalSymptoms && severity == originalSeverity { return false }
        return selectedSymptoms.isEmpty || severity == nil
    }

    private var saveRequirementMessage: String? {
        guard isSaveDisabled else { return nil }
        switch (selectedSymptoms.isEmpty, severity == nil) {
        case (true, true):
            return L10n("Select at least one symptom and its intensity.")
        case (true, false):
            return L10n("Select at least one symptom.")
        case (false, true):
            return L10n("Select the symptom intensity.")
        case (false, false):
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n("Symptom Episode"))
                    .font(.largeTitle.bold())

                DatePicker(L10n("Time"), selection: $selectedTime, displayedComponents: .hourAndMinute)

                sectionTitle("What happened?")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                    ForEach(SymptomTag.allCases) { symptom in
                        Button {
                            if selectedSymptoms.contains(symptom.rawValue) {
                                selectedSymptoms.remove(symptom.rawValue)
                            } else {
                                selectedSymptoms.insert(symptom.rawValue)
                            }
                        } label: {
                            HStack {
                                Text(symptom.displayName)
                                    .font(.subheadline)
                                Spacer()
                                if selectedSymptoms.contains(symptom.rawValue) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedSymptoms.contains(symptom.rawValue) ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("journalSymptom-\(symptom.rawValue)")
                        .accessibilityAddTraits(selectedSymptoms.contains(symptom.rawValue) ? .isSelected : [])
                    }
                }

                sectionTitle("How intense was it?")

                ForEach(SymptomSeverity.allCases, id: \.self) { item in
                    choiceButton(
                        title: item.label,
                        isSelected: severity == item
                    ) {
                        severity = item
                    }
                }

                sectionTitle("Medication state")

                ForEach(MotorState.allCases) { state in
                    choiceButton(
                        title: state.displayName,
                        isSelected: motorState == state
                    ) {
                        motorState = state
                    }
                }

                sectionTitle("Optional note")

                TextField(L10n("Add details"), text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("journalSymptomNote")
            }
            .padding()
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Text(saveRequirementMessage ?? " ")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .accessibilityHidden(saveRequirementMessage == nil)

                Button {
                    let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

                    let entry = JournalEntry(
                        date: combinedDate,
                        type: .symptom,
                        symptomSeverity: severity,
                        symptoms: selectedSymptoms.sorted(),
                        note: cleanNote.isEmpty ? nil : cleanNote,
                        motorState: motorState
                    )

                    let saved: Bool
                    if let entryID {
                        saved = JournalStore.shared.updateSymptom(id: entryID, date: combinedDate, severity: severity,
                            symptoms: entry.symptoms, motorState: motorState, note: entry.note)
                    } else {
                        saved = JournalStore.shared.add(entry)
                    }
                    if saved {
                        dismiss()
                    } else {
                        saveFailed = true
                    }
                } label: {
                    Text(L10n(entryID == nil ? "Save Symptom Episode" : "Save changes"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
                .accessibilityIdentifier("journalSaveSymptom")
                .accessibilityHint(
                    Text(
                        saveRequirementMessage
                            ?? L10n("Saves this symptom episode.")
                    )
                )
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(L10n("Symptom"))
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
        .accessibilityIdentifier("journalSymptomChoice-\(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
