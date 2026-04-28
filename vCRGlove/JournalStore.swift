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
        load()
    }

    private func fileURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("vcr/journal", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal_entries.json")
    }

    func add(_ entry: JournalEntry) {
        entries.append(entry)
        save()
        Logger.shared.log("JOURNAL", "Journal entry saved: \(entry.type.rawValue)")
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: try fileURL())
        } catch {
            Logger.shared.log("JOURNAL", "Save error: \(error.localizedDescription)")
        }
    }

    private func load() {
        do {
            let url = try fileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            entries = try JSONDecoder().decode([JournalEntry].self, from: data)
        } catch {
            Logger.shared.log("JOURNAL", "Load error: \(error.localizedDescription)")
        }
    }
}
