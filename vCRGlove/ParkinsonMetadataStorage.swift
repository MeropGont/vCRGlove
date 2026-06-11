//
//  MappStorage.swift
//  vCRGlove
//
//  Created by Alexander Wiederhold on 30/05/2026.
//

import Foundation
import Mapp

final class MappStorageStore: ObservableObject {
    static let shared = MappStorageStore()

    @Published private(set) var activePatient: Mapp.Patient?
    @Published private(set) var allPatients: [Mapp.Patient] = []
    @Published private(set) var lastErrorMessage: String?

    let database: Mapp.Database

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private init() {
        do {
            let databaseURL = try Self.databaseURL()
            database = try Mapp.Database.fromFile(path: databaseURL.path)
            print("[MappStorage] Database opened: \(databaseURL.path)")
            reloadPatients()
        } catch {
            fatalError("[MappStorage] Could not open database: \(error)")
        }
    }

    func reloadPatients() {
        do {
            allPatients = try Mapp.loadPatients(database: database, activeOnly: false)
            activePatient = try Mapp.loadPatients(database: database, activeOnly: true).first
            lastErrorMessage = nil
            print("[MappStorage] Loaded \(allPatients.count) patient(s), active: \(activePatient?.displayID ?? "none")")
        } catch {
            allPatients = []
            activePatient = nil
            lastErrorMessage = error.localizedDescription
            print("[MappStorage] Patient reload failed: \(error)")
        }
    }

    @discardableResult
    func savePatient(_ patient: Mapp.Patient) throws -> Mapp.Patient {
        let saved = try Mapp.savePatient(patient: patient, database: database)
        reloadPatients()
        print("[MappStorage] Patient saved: \(saved.displayID)")
        return saved
    }

    func saveAppEvent(type: String, tag: String, message: String, details: [String: String] = [:]) {
        guard let patientId = activePatient?.id else {
            print("[MappStorage] Skipping app event without active patient: [\(tag)] \(message)")
            return
        }

        let now = Mapp.DateTime.now()
        let data = Mapp.AppEventData(
            ts: isoFormatter.string(from: Foundation.Date()),
            type: type,
            tag: tag,
            message: message,
            details: details
                .sorted { $0.key < $1.key }
                .map { Mapp.AppEventDetail(key: $0.key, value: $0.value) }
        )

        do {
            let event = Mapp.AppEvent(patient: patientId, start: now, end: now, data: data)
            try event.save(database: database)
        } catch {
            print("[MappStorage] App event save failed: \(error)")
        }
    }

    func saveJournalEntry(_ entry: JournalEntry) {
        guard let patientId = activePatient?.id else {
            print("[MappStorage] Skipping journal entry without active patient: \(entry.type.rawValue)")
            return
        }

        let now = Mapp.DateTime.now()

        do {
            switch entry.type {
            case .dailyCheckIn:
                let data = Mapp.JournalDailyCheckInData(
                    mood: entry.mood.map(Int32.init),
                    symptomSeverity: entry.symptomSeverity?.rawValue,
                    symptoms: entry.symptoms
                )
                try Mapp.JournalDailyCheckIn(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .medication:
                let data = Mapp.JournalMedicationData(
                    medicationEvent: entry.medicationEvent?.rawValue,
                    motorState: entry.motorState?.rawValue,
                    medicationFactors: entry.medicationFactors.map(\.rawValue),
                    note: entry.note,
                    medicationName: entry.medicationName,
                    medicationDose: entry.medicationDose
                )
                try Mapp.JournalMedication(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .pdq8:
                try Mapp.JournalPdq8(patient: patientId, start: now, end: now, data: Mapp.JournalPdq8Data()).save(database: database)

            case .stimulation:
                let data = Mapp.JournalStimulationData(note: entry.note)
                try Mapp.JournalStimulation(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .symptm:
                let data = Mapp.JournalSymptomEpisodeData(
                    symptomSeverity: entry.symptomSeverity?.rawValue,
                    symptoms: entry.symptoms,
                    note: entry.note,
                    motorState: entry.motorState?.rawValue
                )
                try Mapp.JournalSymptomEpisode(patient: patientId, start: now, end: now, data: data).save(database: database)

            case .note:
                let data = Mapp.JournalNotesQuestionaireData(
                    betreff: "vCR Journal Note",
                    body: entry.note,
                    privat: false
                )
                try Mapp.JournalNotesQuestionaire(patient: patientId, start: now, end: now, data: data).save(database: database)
            }

            print("[MappStorage] Journal entry saved: \(entry.type.rawValue)")
        } catch {
            print("[MappStorage] Journal entry save failed: \(entry.type.rawValue) - \(error)")
        }
    }

    func saveGloveSnapshot(reason: String, devices: [HDevice]) {
        guard let patientId = activePatient?.id else {
            print("[MappStorage] Skipping glove snapshot without active patient: \(reason)")
            return
        }

        let now = Mapp.DateTime.now()
        let data = Mapp.VcrGloveSnapshotData(
            reason: reason,
            devices: devices.map { device in
                Mapp.VcrGloveSnapshotDevice(
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
            try Mapp.VcrGloveSnapshot(patient: patientId, start: now, end: now, data: data).save(database: database)
            print("[MappStorage] Glove snapshot saved: \(reason)")
        } catch {
            print("[MappStorage] Glove snapshot save failed: \(error)")
        }
    }

    func saveStimulationSettings(amplitude: Double, frequencyHz: Double, pulseMs: Double, totalSeconds: Double, fingersPerCycle: Int, vcrPreset: Bool) {
        guard let patientId = activePatient?.id else {
            print("[MappStorage] Skipping stimulation settings without active patient")
            return
        }

        let now = Mapp.DateTime.now()
        let data = Mapp.VcrStimulationSettingsData(
            amplitude: amplitude,
            frequencyHz: frequencyHz,
            pulseMs: pulseMs,
            totalSeconds: totalSeconds,
            fingersPerCycle: UInt8(clamping: fingersPerCycle),
            vcrPreset: vcrPreset
        )

        do {
            try Mapp.VcrStimulationSettings(patient: patientId, start: now, end: now, data: data).save(database: database)
            print("[MappStorage] Stimulation settings saved")
        } catch {
            print("[MappStorage] Stimulation settings save failed: \(error)")
        }
    }

    private static func databaseURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = docs.appendingPathComponent("vcr/mapp", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("vcrglove.sqlite")
    }
}

extension Mapp.Patient {
    var displayID: String {
        guard let id else { return "Unsaved" }
        return "ID \(id.numericId())"
    }
}

extension Mapp.Date {
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
    func toMappDate() throws -> Mapp.Date {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return try Mapp.Date.fromNumbers(
            year: Int32(components.year ?? 1970),
            month: UInt32(components.month ?? 1),
            day: UInt32(components.day ?? 1)
        )
    }
}
