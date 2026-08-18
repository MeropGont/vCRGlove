//
//  EventStore.swift
//  vCRGlove
//
//  Created by Tactile Glove on 23.04.26.
//

import Foundation

final class EventStore {
    static let shared = EventStore()
    private init() {}

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func logsDirectory() throws -> URL {
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
            } catch {
                print("EventStore write error:", error.localizedDescription)
            }
        }
    }

    func fileURL() -> URL? {
        try? eventFileURL()
    }

    func clearEventLog(patientID: String) {
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
        } catch {
            print("EventStore clear error:", error.localizedDescription)
        }
    }
}
