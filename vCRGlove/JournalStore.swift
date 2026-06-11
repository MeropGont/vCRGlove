//
//  JournalStore.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import Foundation

final class JournalStore: ObservableObject {
    static let shared = JournalStore()

    @Published private(set) var entries: [JournalEntry] = []

    private init() {
        reloadFromDatabase()
    }

    func reloadFromDatabase() {
        entries = ParkinsonMetadataStore.shared.loadJournalEntries()
        Logger.shared.log("JOURNAL", "Journal entries loaded: \(entries.count)")
    }

    func add(_ entry: JournalEntry) {
        entries.append(entry)
        ParkinsonMetadataStore.shared.saveJournalEntry(entry)
        Logger.shared.log("JOURNAL", "Journal entry saved: \(entry.type.rawValue)")
    }
}
