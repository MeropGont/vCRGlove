//
//  MedicationLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct MedicationLogView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var event: MedicationEvent? = nil
    @State private var motorState: MotorState? = nil
    @State private var factors: Set<MedicationFactor> = []
    @State private var note = ""

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Medication")
                    .font(.largeTitle.bold())

                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)

                sectionTitle("What happened?")

                ForEach(MedicationEvent.allCases) { item in
                    choiceButton(
                        title: item.rawValue,
                        isSelected: event == item
                    ) {
                        event = item
                    }
                }

                sectionTitle("How are you right now?")

                ForEach(MotorState.allCases) { state in
                    choiceButton(
                        title: state.rawValue,
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
                                Text(factor.rawValue)
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

                TextField("Optional note", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }
            .padding()
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save Medication Log") {
                let entry = JournalEntry(
                    date: combinedDate,
                    type: .medication,
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note,
                    medicationEvent: event,
                    motorState: motorState,
                    medicationFactors: Array(factors).sorted { $0.rawValue < $1.rawValue }
                )

                JournalStore.shared.add(entry)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(event == nil || motorState == nil)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Medication")
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
