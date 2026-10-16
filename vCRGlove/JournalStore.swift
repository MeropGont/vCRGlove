//
//  JournalStore.swift
//  vCRGlove
//
//  Created by Tactile Glove on 27.04.26.
//

import Foundation

@MainActor
final class JournalStore: ObservableObject {
    static let shared: JournalStore = {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ui-test-journal"),
           arguments.indices.contains(index + 1),
           let id = UUID(uuidString: arguments[index + 1]) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(id.uuidString).json")
            if arguments.contains("--ui-test-journal-legacy-events"), !FileManager.default.fileExists(atPath: url.path) {
                try? JSONEncoder().encode([
                    JournalEntry(type: .medication, medicationName: "Legacy medicine", medicationDose: "100 mg", note: "Legacy medication note"),
                    JournalEntry(type: .symptom, note: "Legacy symptom note")
                ]).write(to: url, options: .atomic)
            }
            return JournalStore(storageURL: url, writeData: { data, destination in
                if arguments.contains("--ui-test-journal-save-failure") {
                    throw CocoaError(.fileWriteOutOfSpace)
                }
                try data.write(to: destination, options: .atomic)
            })
        }
        #endif
        return JournalStore()
    }()

    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var isLoadBlocked = false
    @Published private(set) var saveErrorMessage: String?

    private let storageURL: URL?
    private let writeData: (Data, URL) throws -> Void
    private let now: () -> Date
    private var storedRecords: [UUID: [String: Any]] = [:]

    init(storageURL: URL? = nil,
         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) },
         now: @escaping () -> Date = Date.init) {
        self.storageURL = storageURL
        self.writeData = writeData
        self.now = now
        load()
    }

    private func fileURL() throws -> URL {
        if let storageURL { return storageURL }
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

    var latestDailyCheckIn: JournalEntry? {
        entries.reversed().filter { $0.type == .dailyCheckIn }.max {
            Calendar.current.startOfDay(for: $0.date) < Calendar.current.startOfDay(for: $1.date)
        }
    }

    /// Journal writes are synchronous on the main actor. Keep the original JSON and unknown fields.
    func exportSnapshot() throws -> Data? {
        do { return try Data(contentsOf: fileURL()) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }

    func dailyCheckIn(on date: Date, calendar: Calendar = .current) -> JournalEntry? {
        entries.last { $0.type == .dailyCheckIn && calendar.isDate($0.date, inSameDayAs: date) }
    }

    @discardableResult
    func add(_ entry: JournalEntry) -> Bool {
        guard !entries.contains(where: { $0.id == entry.id }) else { return saveFailed() }
        var saved = entry
        saved.createdAt = now()
        saved.updatedAt = saved.createdAt
        return persist(entries + [saved])
    }

    @discardableResult
    func saveDailyCheckIn(date: Date, mood: Int?, severity: SymptomSeverity?, symptoms: [String]) -> Bool {
        saveCheckIn(date: date) {
            $0.mood = mood
            $0.symptomSeverity = severity
            $0.symptoms = symptoms
        }
    }

    @discardableResult
    func saveMoodAndImpactCheckIn(date: Date, mood: Int?, impact: DailyActivityImpact?) -> Bool {
        guard mood != nil || impact != nil,
              mood.map({ (1...5).contains($0) }) ?? true else { return saveFailed() }
        let isNew = dailyCheckIn(on: date) == nil
        return saveCheckIn(date: date) {
            // Historical medication/symptom answers are not owned by this two-question editor.
            $0.mood = mood
            $0.activityImpact = impact
            if isNew { $0.checkInVersion = 3 }
        }
    }

    @discardableResult
    func saveQuickCheckIn(date: Date, mood: Int?, impact: DailyActivityImpact?,
                          medication: DailyMedicationSummary?, changes: [DailyMedicationChange],
                          severity: SymptomSeverity?, symptoms: [String]) -> Bool {
        guard mood != nil || impact != nil || medication != nil || severity != nil || !symptoms.isEmpty else {
            return saveFailed()
        }
        return saveCheckIn(date: date) {
            $0.mood = mood
            $0.activityImpact = impact
            $0.medicationSummary = medication
            $0.medicationChanges = medication == .changed ? changes : []
            $0.checkInVersion = 2
            $0.symptomSeverity = severity
            $0.symptoms = symptoms
        }
    }

    private func saveCheckIn(date: Date, edit: (inout JournalEntry) -> Void) -> Bool {
        // Edit only the latest check-in for this day; historical duplicates and events stay intact.
        if let existing = dailyCheckIn(on: date),
           let index = entries.firstIndex(where: { $0.id == existing.id }) {
            var edited = existing
            edit(&edited)
            edited.updatedAt = now()
            var candidate = entries
            candidate[index] = edited
            return persist(candidate)
        }
        var newEntry = JournalEntry(date: date, type: .dailyCheckIn)
        edit(&newEntry)
        return add(newEntry)
    }

    private func saveFailed() -> Bool {
        saveErrorMessage = L10n("Your entry was not saved. Your answers are still here. Please try again.")
        return false
    }

    @discardableResult
    func updateMedication(id: UUID, date: Date, event: MedicationEvent?, motorState: MotorState?,
                          factors: [MedicationFactor], note: String?) -> Bool {
        update(id: id, type: .medication) {
            $0.date = date
            $0.medicationEvent = event
            $0.motorState = motorState
            $0.medicationFactors = factors
            $0.note = note
        }
    }

    @discardableResult
    func updateSymptom(id: UUID, date: Date, severity: SymptomSeverity?, symptoms: [String],
                       motorState: MotorState?, note: String?) -> Bool {
        update(id: id, type: .symptom) {
            $0.date = date
            $0.symptomSeverity = severity
            $0.symptoms = symptoms
            $0.motorState = motorState
            $0.note = note
        }
    }

    private func update(id: UUID, type: JournalEntryType, edit: (inout JournalEntry) -> Void) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.type == type }) else {
            return saveFailed()
        }
        var candidate = entries
        edit(&candidate[index])
        candidate[index].updatedAt = now()
        return persist(candidate)
    }

    private func persist(_ candidate: [JournalEntry]) -> Bool {
        guard !isLoadBlocked else {
            saveErrorMessage = L10n("Your saved journal could not be opened. Nothing has been overwritten. Please try restarting the app.")
            return false
        }
        do {
            let encoded = try JSONEncoder().encode(candidate)
            guard let records = try JSONSerialization.jsonObject(with: encoded) as? [[String: Any]] else {
                throw CocoaError(.fileWriteUnknown)
            }
            // Keep unrecognized research metadata while replacing only fields owned by this model.
            let merged = zip(candidate, records).map { entry, record in
                var stored = storedRecords[entry.id] ?? [:]
                for key in JournalEntry.CodingKeys.allCases { stored.removeValue(forKey: key.rawValue) }
                stored.merge(record) { _, new in new }
                return stored
            }
            let data = try JSONSerialization.data(withJSONObject: merged, options: .sortedKeys)
            try writeData(data, fileURL())
            storedRecords = Dictionary(uniqueKeysWithValues: zip(candidate.map(\.id), merged))
            entries = candidate
            saveErrorMessage = nil
            Logger.shared.log("JOURNAL", "Journal saved: \(candidate.count) entry(s)")
            return true
        } catch {
            Logger.shared.log("JOURNAL", "Save error: \(error.localizedDescription)")
            return saveFailed()
        }
    }

    private func load() {
        do {
            let url = try fileURL()
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([JournalEntry].self, from: data)
            guard Set(decoded.map(\.id)).count == decoded.count,
                  let records = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            storedRecords = Dictionary(uniqueKeysWithValues: zip(decoded.map(\.id), records))
            entries = decoded
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            isLoadBlocked = true
            Logger.shared.log("JOURNAL", "Load error: \(error.localizedDescription)")
        }
    }
}
