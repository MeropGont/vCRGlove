//
//  NoteLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct NoteLogView: View {
    let date: Date

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var note = ""

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Note")
                    .font(.largeTitle.bold())

                DatePicker("Time", selection: $selectedTime, displayedComponents: .hourAndMinute)

                Text("What would you like to record?")
                    .font(.headline)

                TextField("Add a note", text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...10)
            }
            .padding()
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Save Note") {
                let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

                let entry = JournalEntry(
                    date: combinedDate,
                    type: .note,
                    note: cleanNote
                )

                JournalStore.shared.add(entry)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("Note")
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
}
