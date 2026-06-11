//
//  ParkinsonMetadataStorage.swift
//  vCRGlove
//
//  Created by Alexander Wiederhold on 30/05/2026.
//

import Foundation
import ParkinsonMetadata
import SQLite3


// ---------------------------------------------------------------------
// MARK: The event store and its helpers
// ---------------------------------------------------------------------

final class EventStore {
    static let shared = EventStore()
    private init() {}

    func append(type: String,
                tag: String,
                message: String,
                details: [String: String] = [:]) {
        ParkinsonMetadataStore.shared.saveAppEvent(type: type, tag: tag, message: message, details: details)
    }
}

enum ParkinsonMetadataStoreError: LocalizedError {
    case databaseUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable(let message):
            return message
        }
    }
}

struct ParkinsonMetadataStorageInfo {
    let appStorageBytes: Int64?
    let sqliteBytes: Int64?
}

final class ParkinsonMetadataStore: ObservableObject {
    static let shared = ParkinsonMetadataStore()

    @Published private(set) var activePatient: ParkinsonMetadata.Patient?
    @Published private(set) var allPatients: [ParkinsonMetadata.Patient] = []
    @Published private(set) var lastErrorMessage: String?

    let database: ParkinsonMetadata.Database?

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        do {
            let databaseURL = try Self.databaseURL()
            database = try ParkinsonMetadata.Database.fromFile(path: databaseURL.path)
            print("[ParkinsonMetadata] Database opened: \(databaseURL.path)")
            reloadPatients()
        } catch {
            database = nil
            activePatient = nil
            allPatients = []
            lastErrorMessage = "Could not open Parkinson metadata database: \(error.localizedDescription)"
            print("[ParkinsonMetadata] Could not open database: \(error)")
        }
    }

    func reloadPatients() {
        guard let database else {
            allPatients = []
            activePatient = nil
            if lastErrorMessage == nil {
                lastErrorMessage = "Parkinson metadata database is not available."
            }
            print("[ParkinsonMetadata] Skipping patient reload without database")
            return
        }

        do {
            allPatients = try ParkinsonMetadata.loadPatients(database: database, activeOnly: false)
            activePatient = try ParkinsonMetadata.loadPatients(database: database, activeOnly: true).first
            lastErrorMessage = nil
            print("[ParkinsonMetadata] Loaded \(allPatients.count) patient(s), active: \(activePatient?.displayID ?? "none")")
        } catch {
            allPatients = []
            activePatient = nil
            lastErrorMessage = error.localizedDescription
            print("[ParkinsonMetadata] Patient reload failed: \(error)")
        }
    }

    @discardableResult
    func savePatient(_ patient: ParkinsonMetadata.Patient) throws -> ParkinsonMetadata.Patient {
        guard let database else {
            let message = lastErrorMessage ?? "Parkinson metadata database is not available."
            print("[ParkinsonMetadata] Patient save failed without database: \(message)")
            throw ParkinsonMetadataStoreError.databaseUnavailable(message)
        }

        let saved = try ParkinsonMetadata.savePatient(patient: patient, database: database)
        reloadPatients()
        print("[ParkinsonMetadata] Patient saved: \(saved.displayID)")
        return saved
    }

    func saveAppEvent(type: String, tag: String, message: String, details: [String: String] = [:]) {
        guard let database else {
            print("[ParkinsonMetadata] Skipping app event without database: [\(tag)] \(message)")
            return
        }

        guard let patientId = activePatient?.id else {
            print("[ParkinsonMetadata] Skipping app event without active patient: [\(tag)] \(message)")
            return
        }

        let now = ParkinsonMetadata.DateTime.now()
        let data = ParkinsonMetadata.AppEventData(
            ts: isoFormatter.string(from: Foundation.Date()),
            type: type,
            tag: tag,
            message: message,
            details: details
                .sorted { $0.key < $1.key }
                .map { ParkinsonMetadata.AppEventDetail(key: $0.key, value: $0.value) }
        )

        do {
            let event = ParkinsonMetadata.AppEvent(patient: patientId, start: now, end: now, data: data)
            try event.save(database: database)
        } catch {
            print("[ParkinsonMetadata] App event save failed: \(error)")
        }
    }

    func saveVcrSettingsEvent(
        reason: String,
        showResearchTab: Bool?,
        researchUnlocked: Bool? = nil,
        researchLocked: Bool? = nil,
        researchAutoLocked: Bool? = nil,
        researchUnlockFailed: Bool? = nil,
        successfullyLoggedIn: Bool? = nil,
        failedLoggedInAttempts: UInt32? = nil,
        avatar: String? = nil,
        details: [String: String] = [:]
    ) {
        guard let database else {
            print("[ParkinsonMetadata] Skipping vCR settings event without database: \(reason)")
            return
        }

        guard let patientId = activePatient?.id else {
            print("[ParkinsonMetadata] Skipping vCR settings event without active patient: \(reason)")
            return
        }

        let now = ParkinsonMetadata.DateTime.now()
        let data = ParkinsonMetadata.VcrSettingsData(
            showResearchTab: showResearchTab,
            researchUnlocked: researchUnlocked,
            researchLocked: researchLocked,
            researchAutoLocked: researchAutoLocked,
            researchUnlockFailed: researchUnlockFailed,
            designMode: nil,
            successfullyLoggedIn: successfullyLoggedIn,
            failedLoggedInAttempts: failedLoggedInAttempts,
            vibration: true,
            avatar: avatar ?? ""
        )

        do {
            try ParkinsonMetadata.VcrSettings(patient: patientId, start: now, end: now, data: data).save(database: database)
            print("[ParkinsonMetadata] vCR settings event saved: \(reason)")
        } catch {
            print("[ParkinsonMetadata] vCR settings event save failed: \(error)")
        }

        guard !details.isEmpty else { return }
        saveAppEvent(type: "vcr_settings", tag: reason, message: "vCR settings changed", details: details)
    }

    func saveJournalEntry(_ entry: JournalEntry) {
        guard let database else {
            print("[ParkinsonMetadata] Skipping journal entry without database: \(entry.type.rawValue)")
            return
        }

        guard let patientId = activePatient?.id else {
            print("[ParkinsonMetadata] Skipping journal entry without active patient: \(entry.type.rawValue)")
            return
        }

        let now = ParkinsonMetadata.DateTime.now()

        do {
            switch entry.type {
            case .dailyCheckIn:
                let data = ParkinsonMetadata.JournalDailyCheckInData(
                    mood: entry.mood.map(Int32.init),
                    symptomSeverity: entry.symptomSeverity?.rawValue,
                    symptoms: entry.symptoms
                )
                try ParkinsonMetadata.JournalDailyCheckIn(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .medication:
                let data = ParkinsonMetadata.JournalMedicationData(
                    medicationEvent: entry.medicationEvent?.rawValue,
                    motorState: entry.motorState?.rawValue,
                    medicationFactors: entry.medicationFactors.map(\.rawValue),
                    note: entry.note,
                    medicationName: entry.medicationName,
                    medicationDose: entry.medicationDose
                )
                try ParkinsonMetadata.JournalMedication(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .pdq8:
                try ParkinsonMetadata.JournalPdq8(patient: patientId, start: now, end: now, data: ParkinsonMetadata.JournalPdq8Data()).save(database: database)

            case .stimulation:
                let data = ParkinsonMetadata.JournalStimulationData(note: entry.note)
                try ParkinsonMetadata.JournalStimulation(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .symptm:
                let data = ParkinsonMetadata.JournalSymptomEpisodeData(
                    symptomSeverity: entry.symptomSeverity?.rawValue,
                    symptoms: entry.symptoms,
                    note: entry.note,
                    motorState: entry.motorState?.rawValue
                )
                try ParkinsonMetadata.JournalSymptomEpisode(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .note:
                let data = ParkinsonMetadata.JournalNotesQuestionaireData(
                    betreff: "vCR Journal Note",
                    body: entry.note,
                    privat: false
                )
                try ParkinsonMetadata.JournalNotesQuestionaire(patient: patientId, start: now, end: now, data: data).save(database: database)
            }

            print("[ParkinsonMetadata] Journal entry saved: \(entry.type.rawValue)")
        } catch {
            print("[ParkinsonMetadata] Journal entry save failed: \(entry.type.rawValue) - \(error)")
        }
    }

    func loadJournalEntries() -> [JournalEntry] {
        guard let database else {
            print("[ParkinsonMetadata] Skipping journal load without database")
            return []
        }

        guard let patientNumericId = activePatient?.id?.numericId() else {
            print("[ParkinsonMetadata] Skipping journal load without active patient")
            return []
        }

        do {
            let events = try ParkinsonMetadata.loadEventsForPatient(database: database, patientId: Int64(patientNumericId))
            let entries = events.compactMap(Self.makeJournalEntry)
                .sorted { $0.date > $1.date }
            print("[ParkinsonMetadata] Loaded \(entries.count) journal entrie(s)")
            return entries
        } catch {
            print("[ParkinsonMetadata] Journal load failed: \(error)")
            return []
        }
    }

    func saveGloveSnapshot(reason: String, devices: [HDevice]) {
        guard let database else {
            print("[ParkinsonMetadata] Skipping glove snapshot without database: \(reason)")
            return
        }

        guard let patientId = activePatient?.id else {
            print("[ParkinsonMetadata] Skipping glove snapshot without active patient: \(reason)")
            return
        }

        let now = ParkinsonMetadata.DateTime.now()
        let data = ParkinsonMetadata.VcrGloveSnapshotData(
            reason: reason,
            devices: devices.map { device in
                ParkinsonMetadata.VcrGloveSnapshotDevice(
                    id: device.id,
                    name: device.name,
                    position: device.position,
                    battery: device.battery.map(Int32.init),
                    isConnected: device.isConnected,
                    isPaired: device.isPaired
                )
            }
        )

        do {
            try ParkinsonMetadata.VcrGloveSnapshot(patient: patientId, start: now, end: now, data: data).save(database: database)
            print("[ParkinsonMetadata] Glove snapshot saved: \(reason)")
        } catch {
            print("[ParkinsonMetadata] Glove snapshot save failed: \(error)")
        }
    }

    func saveStimulationSettings(amplitude: Double, frequencyHz: Double, pulseMs: Double, totalSeconds: Double, fingersPerCycle: Int, vcrPreset: Bool) {
        guard let database else {
            print("[ParkinsonMetadata] Skipping stimulation settings without database")
            return
        }

        guard let patientId = activePatient?.id else {
            print("[ParkinsonMetadata] Skipping stimulation settings without active patient")
            return
        }

        let now = ParkinsonMetadata.DateTime.now()
        let data = ParkinsonMetadata.VcrStimulationSettingsData(
            amplitude: amplitude,
            frequencyHz: frequencyHz,
            pulseMs: pulseMs,
            totalSeconds: totalSeconds,
            fingersPerCycle: UInt8(clamping: fingersPerCycle),
            vcrPreset: vcrPreset
        )

        do {
            try ParkinsonMetadata.VcrStimulationSettings(patient: patientId, start: now, end: now, data: data).save(database: database)
            print("[ParkinsonMetadata] Stimulation settings saved")
        } catch {
            print("[ParkinsonMetadata] Stimulation settings save failed: \(error)")
        }
    }

    private static func makeJournalEntry(from event: ParkinsonMetadata.GenericEvent) -> JournalEntry? {
        let eventType = event.eventType.lowercased()
        guard let date = journalDate(from: event.startUtc) else {
            print("[ParkinsonMetadata] Skipping journal event with invalid date: \(event.eventType)")
            return nil
        }

        if eventType.contains("daily") && eventType.contains("check") {
            return makeDailyCheckInEntry(from: event, date: date)
        }

        if eventType.contains("medication") {
            return makeMedicationEntry(from: event, date: date)
        }

        if eventType.contains("symptom") {
            return makeSymptomEpisodeEntry(from: event, date: date)
        }

        if eventType.contains("note") || eventType.contains("questionaire") || eventType.contains("questionnaire") {
            return makeNoteEntry(from: event, date: date)
        }

        if eventType.contains("pdq") {
            return JournalEntry(date: date, type: .pdq8, note: "PDQ-8")
        }

        if eventType.contains("journal") && eventType.contains("stimulation") {
            return makeStimulationEntry(from: event, date: date)
        }

        return nil
    }

    private static func makeDailyCheckInEntry(from event: ParkinsonMetadata.GenericEvent, date: Foundation.Date) -> JournalEntry? {
        do {
            let data = try JSONDecoder().decode(PersistedDailyCheckIn.self, from: Data(event.dataJson.utf8))
            return JournalEntry(
                date: date,
                type: .dailyCheckIn,
                mood: data.mood.map(Int.init),
                symptomSeverity: data.symptomSeverity.flatMap(SymptomSeverity.init(rawValue:)),
                symptoms: data.symptoms
            )
        } catch {
            print("[ParkinsonMetadata] Daily check-in decode failed for event \(event.id): \(error)")
            return nil
        }
    }

    private static func makeMedicationEntry(from event: ParkinsonMetadata.GenericEvent, date: Foundation.Date) -> JournalEntry? {
        do {
            let data = try JSONDecoder().decode(PersistedMedication.self, from: Data(event.dataJson.utf8))
            return JournalEntry(
                date: date,
                type: .medication,
                medicationName: data.medicationName,
                medicationDose: data.medicationDose,
                note: data.note,
                medicationEvent: data.medicationEvent.flatMap(MedicationEvent.init(rawValue:)),
                motorState: data.motorState.flatMap(MotorState.init(rawValue:)),
                medicationFactors: data.medicationFactors.compactMap(MedicationFactor.init(rawValue:))
            )
        } catch {
            print("[ParkinsonMetadata] Medication journal decode failed for event \(event.id): \(error)")
            return nil
        }
    }

    private static func makeSymptomEpisodeEntry(from event: ParkinsonMetadata.GenericEvent, date: Foundation.Date) -> JournalEntry? {
        do {
            let data = try JSONDecoder().decode(PersistedSymptomEpisode.self, from: Data(event.dataJson.utf8))
            return JournalEntry(
                date: date,
                type: .symptm,
                symptomSeverity: data.symptomSeverity.flatMap(SymptomSeverity.init(rawValue:)),
                symptoms: data.symptoms,
                note: data.note,
                motorState: data.motorState.flatMap(MotorState.init(rawValue:))
            )
        } catch {
            print("[ParkinsonMetadata] Symptom journal decode failed for event \(event.id): \(error)")
            return nil
        }
    }

    private static func makeNoteEntry(from event: ParkinsonMetadata.GenericEvent, date: Foundation.Date) -> JournalEntry? {
        do {
            let data = try JSONDecoder().decode(PersistedJournalNote.self, from: Data(event.dataJson.utf8))
            return JournalEntry(date: date, type: .note, note: data.body)
        } catch {
            print("[ParkinsonMetadata] Note journal decode failed for event \(event.id): \(error)")
            return nil
        }
    }

    private static func makeStimulationEntry(from event: ParkinsonMetadata.GenericEvent, date: Foundation.Date) -> JournalEntry? {
        do {
            let data = try JSONDecoder().decode(PersistedJournalStimulation.self, from: Data(event.dataJson.utf8))
            return JournalEntry(date: date, type: .stimulation, note: data.note)
        } catch {
            print("[ParkinsonMetadata] Stimulation journal decode failed for event \(event.id): \(error)")
            return JournalEntry(date: date, type: .stimulation)
        }
    }

    private static func journalDate(from startUtc: String) -> Foundation.Date? {
        if let date = isoDateTimeWithFractions.date(from: startUtc) {
            return date
        }

        if let date = isoDateTime.date(from: startUtc) {
            return date
        }

        return nil
    }

    private static let isoDateTimeWithFractions: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoDateTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func makeDatabaseExportCopy() throws -> [URL] {
        let fileManager = FileManager.default
        let sourceURL = try Self.databaseURL()
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let exportDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("vcrglove-database-export-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let dateStamp = Self.exportDateFormatter.string(from: Foundation.Date())
        let destinationURL = exportDirectory.appendingPathComponent("vcrglove-database-\(dateStamp).sqlite")
        try Self.backupSQLiteDatabase(from: sourceURL, to: destinationURL)

        print("[ParkinsonMetadata] Database export prepared as single SQLite file: \(destinationURL.path)")
        return [destinationURL]
    }

    func cleanupDatabaseExport(urls: [URL]) {
        let fileManager = FileManager.default
        let directories = Set(urls.map { $0.deletingLastPathComponent() })

        for directory in directories {
            do {
                if fileManager.fileExists(atPath: directory.path) {
                    try fileManager.removeItem(at: directory)
                    print("[ParkinsonMetadata] Database export cache removed: \(directory.path)")
                }
            } catch {
                print("[ParkinsonMetadata] Database export cache cleanup failed: \(error)")
            }
        }
    }

    func storageInfo() -> ParkinsonMetadataStorageInfo {
        do {
            let databaseURL = try Self.databaseURL()
            let storageDirectory = databaseURL.deletingLastPathComponent().deletingLastPathComponent()
            return ParkinsonMetadataStorageInfo(
                appStorageBytes: Self.directorySize(at: storageDirectory),
                sqliteBytes: Self.fileSize(at: databaseURL)
            )
        } catch {
            print("[ParkinsonMetadata] Storage info unavailable: \(error)")
            return ParkinsonMetadataStorageInfo(appStorageBytes: nil, sqliteBytes: nil)
        }
    }

    private static var exportDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }

    private static func backupSQLiteDatabase(from sourceURL: URL, to destinationURL: URL) throws {
        var sourceDatabase: OpaquePointer?
        var destinationDatabase: OpaquePointer?

        guard sqlite3_open_v2(sourceURL.path, &sourceDatabase, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(sourceDatabase)
            sqlite3_close(sourceDatabase)
            throw CocoaError(.fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: "Could not open source database for export: \(message)"])
        }
        defer { sqlite3_close(sourceDatabase) }

        guard sqlite3_open_v2(destinationURL.path, &destinationDatabase, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = sqliteErrorMessage(destinationDatabase)
            sqlite3_close(destinationDatabase)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Could not create export database: \(message)"])
        }
        defer { sqlite3_close(destinationDatabase) }

        guard let backup = sqlite3_backup_init(destinationDatabase, "main", sourceDatabase, "main") else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Could not start database backup: \(sqliteErrorMessage(destinationDatabase))"])
        }

        let result = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "Could not finish database backup: \(sqliteErrorMessage(destinationDatabase))"])
        }
    }

    private static func sqliteErrorMessage(_ database: OpaquePointer?) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return "Unknown SQLite error" }
        return String(cString: message)
    }

    private static func directorySize(at url: URL) -> Int64? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), values.isRegularFile == true else {
                continue
            }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
        return values.fileSize.map(Int64.init)
    }

    private static func databaseURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("vcr/parkinson_metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vcrglove.sqlite")
    }
}

private struct PersistedDailyCheckIn: Decodable {
    let mood: Int32?
    let symptomSeverity: String?
    let symptoms: [String]

    private enum CodingKeys: String, CodingKey {
        case mood
        case symptomSeverity
        case symptomSeveritySnake = "symptom_severity"
        case symptoms
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mood = try container.decodeIfPresent(Int32.self, forKey: .mood)
        symptomSeverity = try container.decodeIfPresent(String.self, forKey: .symptomSeverity)
            ?? container.decodeIfPresent(String.self, forKey: .symptomSeveritySnake)
        symptoms = try container.decodeIfPresent([String].self, forKey: .symptoms) ?? []
    }
}

private struct PersistedMedication: Decodable {
    let medicationEvent: String?
    let motorState: String?
    let medicationFactors: [String]
    let note: String?
    let medicationName: String?
    let medicationDose: String?

    private enum CodingKeys: String, CodingKey {
        case medicationEvent
        case medicationEventSnake = "medication_event"
        case motorState
        case motorStateSnake = "motor_state"
        case medicationFactors
        case medicationFactorsSnake = "medication_factors"
        case note
        case medicationName
        case medicationNameSnake = "medication_name"
        case medicationDose
        case medicationDoseSnake = "medication_dose"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        medicationEvent = try container.decodeIfPresent(String.self, forKey: .medicationEvent)
            ?? container.decodeIfPresent(String.self, forKey: .medicationEventSnake)
        motorState = try container.decodeIfPresent(String.self, forKey: .motorState)
            ?? container.decodeIfPresent(String.self, forKey: .motorStateSnake)
        medicationFactors = try container.decodeIfPresent([String].self, forKey: .medicationFactors)
            ?? container.decodeIfPresent([String].self, forKey: .medicationFactorsSnake)
            ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        medicationName = try container.decodeIfPresent(String.self, forKey: .medicationName)
            ?? container.decodeIfPresent(String.self, forKey: .medicationNameSnake)
        medicationDose = try container.decodeIfPresent(String.self, forKey: .medicationDose)
            ?? container.decodeIfPresent(String.self, forKey: .medicationDoseSnake)
    }
}

private struct PersistedSymptomEpisode: Decodable {
    let symptomSeverity: String?
    let symptoms: [String]
    let note: String?
    let motorState: String?

    private enum CodingKeys: String, CodingKey {
        case symptomSeverity
        case symptomSeveritySnake = "symptom_severity"
        case symptoms
        case note
        case motorState
        case motorStateSnake = "motor_state"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        symptomSeverity = try container.decodeIfPresent(String.self, forKey: .symptomSeverity)
            ?? container.decodeIfPresent(String.self, forKey: .symptomSeveritySnake)
        symptoms = try container.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note)
        motorState = try container.decodeIfPresent(String.self, forKey: .motorState)
            ?? container.decodeIfPresent(String.self, forKey: .motorStateSnake)
    }
}

private struct PersistedJournalNote: Decodable {
    let body: String?
}

private struct PersistedJournalStimulation: Decodable {
    let note: String?
}

extension ParkinsonMetadata.Patient {
    var displayID: String {
        guard let id else { return "Unsaved" }
        return "\(id.numericId())"
    }
}

extension ParkinsonMetadata.Date {
    func toFoundationDate() -> Foundation.Date {
        let parts = toString().split(separator: "-")
        guard parts.count == 3 else { return Foundation.Date() }

        var components = DateComponents()
        components.year = Int(parts[0])
        components.month = Int(parts[1])
        components.day = Int(parts[2])
        return Calendar.current.date(from: components) ?? Foundation.Date()
    }
}

extension Foundation.Date {
    func toParkinsonMetadataDate() throws -> ParkinsonMetadata.Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return try ParkinsonMetadata.Date.fromNumbers(
            year: Int32(components.year ?? 1970),
            month: UInt32(components.month ?? 1),
            day: UInt32(components.day ?? 1)
        )
    }
}

// ---------------------------------------------------------------------
// MARK: Device Identifier
// ---------------------------------------------------------------------

enum AppDeviceIdentifier {
    private static let storageKey = "vcrglove.localDeviceIdentifier"

    static var current: String {
        ensureCreated()
    }

    @discardableResult
    static func ensureCreated() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: storageKey), existing.count == 16 {
            return existing
        }

        let generated = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)).uppercased()
        defaults.set(generated, forKey: storageKey)
        print("[DeviceID] Generated local device identifier: \(generated)")
        return generated
    }
}
