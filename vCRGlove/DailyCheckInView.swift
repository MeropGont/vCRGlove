import SwiftUI

struct DailyCheckInView: View {
    let entryDate: Date

    @Environment(\.dismiss) private var dismiss

    @State private var mood: Int? = nil
    @State private var symptomSeverity: SymptomSeverity? = nil
    @State private var selectedSymptoms: Set<String> = []

    private let symptomOptions = [
        "Tremor",
        "Slowness",
        "Stiffness",
        "Walking difficulty",
        "Freezing",
        "Balance problems",
        "Dyskinesia",
        "Fatigue",
        "Pain",
        "Anxiety"
    ]
    
    init(entryDate: Date = Date()) {
        self.entryDate = entryDate
    }


    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Daily Check-In")
                    .font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text("How are you today?")
                        .font(.headline)

                    HStack(spacing: 14) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                mood = value
                            } label: {
                                Text(["😣", "🙁", "😐", "🙂", "😄"][value - 1])
                                    .font(.system(size: 34))
                                    .padding(8)
                                    .background(
                                        Circle()
                                            .fill(mood == value ? Color.blue.opacity(0.18) : Color.clear)
                                    )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Overall symptom intensity")
                        .font(.headline)

                    ForEach(SymptomSeverity.allCases, id: \.self) { severity in
                        Button {
                            symptomSeverity = severity
                        } label: {
                            HStack {
                                Text(severity.label)
                                Spacer()

                                if symptomSeverity == severity {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(symptomSeverity == severity ? Color.blue.opacity(0.15) : Color(.systemGray6))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Which symptoms are present?")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 10) {
                        ForEach(symptomOptions, id: \.self) { symptom in
                            Button {
                                if selectedSymptoms.contains(symptom) {
                                    selectedSymptoms.remove(symptom)
                                } else {
                                    selectedSymptoms.insert(symptom)
                                }
                            } label: {
                                HStack {
                                    Text(symptom)
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
                }

                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

            }
            
            
            .padding()
            .padding(.top, 8)
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save Check-In") {
                let entry = JournalEntry(
                    date: entryDate,
                    type: .dailyCheckIn,
                    mood: mood,
                    symptomSeverity: symptomSeverity,
                    symptoms: Array(selectedSymptoms).sorted()
                )

                JournalStore.shared.add(entry)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(mood == nil || symptomSeverity == nil)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Check-In")
        .navigationBarTitleDisplayMode(.inline)
    }
}
