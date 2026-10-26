//
//  EventStore.swift
//  vCRGlove
//
//  Created by Tactile Glove on 23.04.26.
//

import Foundation

final class EventStore {
    static let activityDidChange = Notification.Name("vCRGlove.activityDidChange")
    static let shared = EventStore()
    private let directory: URL?
    init(directory: URL? = nil) { self.directory = directory }

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func logsDirectory() throws -> URL {
        if let directory { return directory }
        let docs = try FileManager.default.url(for: .documentDirectory,
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        let dir = docs.appendingPathComponent("vcr/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func eventFileURL() throws -> URL {
        try logsDirectory().appendingPathComponent("events.jsonl")
    }

    /// Serial queue so log lines never interleave and callers (often the main
    /// thread) never block on disk IO.
    private let ioQueue = DispatchQueue(label: "vcr.eventstore.io", qos: .utility)

    func append(type: String,
                tag: String,
                message: String,
                details: [String: String] = [:]) {
        // Timestamp on the caller's thread so it reflects the event time,
        // not the (possibly delayed) write time.
        let ts = iso.string(from: Date())
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                let url = try self.eventFileURL()

                let obj: [String: Any] = [
                    "ts": ts,
                    "type": type,
                    "tag": tag,
                    "message": message,
                    "details": details
                ]

                let data = try JSONSerialization.data(withJSONObject: obj)
                let line = data + Data([0x0A])

                if FileManager.default.fileExists(atPath: url.path) {
                    let h = try FileHandle(forWritingTo: url)
                    defer { try? h.close() }
                    try h.seekToEnd()
                    try h.write(contentsOf: line)
                } else {
                    try line.write(to: url)
                }
                if type == "stimulation_started" || type == "admin_metadata" {
                    DispatchQueue.main.async { NotificationCenter.default.post(name: Self.activityDidChange, object: nil) }
                }
            } catch {
                print("EventStore write error:", error.localizedDescription)
            }
        }
    }

    func fileURL() -> URL? {
        try? eventFileURL()
    }

    /// Ordered after pending appends; callers need not read the log on the UI thread.
    func recordedStimulationStartDates() async throws -> [Date] {
        try await recordedActivityEvidence().starts
    }

    func recordedActivityEvidence() async throws -> StimulationActivityReader.Evidence {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let url = try self.eventFileURL()
                    let data: Data
                    do { data = try Data(contentsOf: url) }
                    catch CocoaError.fileReadNoSuchFile { data = Data() }
                    continuation.resume(returning: StimulationActivityReader.evidence(in: data))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func copyExportSnapshot(to destination: URL) async throws -> [String] {
        let logs = try logsDirectory()
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    var absent = [String]()
                    for name in ["events.jsonl", "handshake.jsonl"] {
                        let path = "logs/\(name)"
                        if try !FullDataExporter.copyFile(logs.appendingPathComponent(name), to: destination.appendingPathComponent(path)) {
                            absent.append(path)
                        }
                    }
                    continuation.resume(returning: absent)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func clearEventLog(patientID: String) {
        ioQueue.async { self.clearStoredLog(patientID: patientID) }
    }

    private func clearStoredLog(patientID: String) {
        do {
            let url = try eventFileURL()

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }

            append(
                type: "admin_action",
                tag: "Research",
                message: "Event log cleared",
                details: [
                    "patientID": patientID
                ]
            )
            DispatchQueue.main.async { NotificationCenter.default.post(name: Self.activityDidChange, object: nil) }
        } catch {
            print("EventStore clear error:", error.localizedDescription)
        }
    }
}
