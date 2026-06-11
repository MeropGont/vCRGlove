//
//  SymptomEpisodeLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct SymptomEpisodeLogView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var selectedSymptoms: Set<SymptomTag> = []
    @State private var severity: SymptomSeverity? = nil
    @State private var motorState: MotorState? = nil
    @State private var note = ""

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Symptom Episode")
                    .font(.largeTitle.bold())

                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)

                sectionTitle("What happened?")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], spacing: 10) {
                    ForEach(SymptomTag.allCases) { symptom in
                        Button {
                            if selectedSymptoms.contains(symptom) {
                                selectedSymptoms.remove(symptom)
                            } else {
                                selectedSymptoms.insert(symptom)
                            }
                        } label: {
                            HStack {
                                Text(symptom.rawValue)
                                    .font(.subheadline)
                                Spacer()
                                if selectedSymptoms.contains(symptom) {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedSymptoms.contains(symptom) ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
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
                        title: state.rawValue,
                        isSelected: motorState == state
                    ) {
                        motorState = state
                    }
                }

                sectionTitle("Optional note")

                TextField("Add details", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
            .padding()
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save Symptom Episode") {
                let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

                let entry = JournalEntry(
                    date: combinedDate,
                    type: .symptm,
                    symptomSeverity: severity,
                    symptoms: selectedSymptoms
                        .map { $0.rawValue }
                        .sorted(),
                    note: cleanNote.isEmpty ? nil : cleanNote,
                    motorState: motorState
                )

                JournalStore.shared.add(entry)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedSymptoms.isEmpty || severity == nil)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Symptom")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var combinedDate: Date {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let time = calendar.dateComponents([.hour, .minute], from: selectedTime)

        var components = DateComponents()
        components.year = day.year
        components.month = day.month
        components.day = day.day
        components.hour = time.hour
        components.minute = time.minute

        return calendar.date(from: components) ?? date
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
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
    }
}
