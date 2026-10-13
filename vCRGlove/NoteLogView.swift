//
//  NoteLogView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import SwiftUI

struct NoteLogView: View {
    let date: Date

    static let noteExamples = [
        "For example: Today I feel strong.",
        "For example: My mood is low today.",
        "For example: I slept well last night.",
        "For example: Walking felt easier today.",
        "For example: I needed more breaks today.",
        "For example: Today was a quiet day."
    ]

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTime = Date()
    @State private var note = ""
    @State private var noteExample = NoteLogView.noteExamples.randomElement() ?? "For example: Today I feel strong."

    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n("Note"))
                    .font(.largeTitle.bold())

                DatePicker(L10n("Time"), selection: $selectedTime, displayedComponents: .hourAndMinute)

                Text(L10n("What would you like to record?"))
                    .font(.headline)

                TextField(L10n(noteExample), text: $note, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(5...10)
                    .accessibilityLabel(L10n("Add a note"))
                    .accessibilityIdentifier("journalNoteField")
            }
            .padding()
            .padding(.bottom, 90)
        }
        .safeAreaInset(edge: .bottom) {
            Button(L10n("Save Note")) {
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
            .accessibilityIdentifier("journalSaveNote")
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle(L10n("Note"))
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
