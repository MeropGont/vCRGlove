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

    func append(type: String,
                tag: String,
                message: String,
                details: [String: String] = [:]) {
        do {
            let url = try eventFileURL()

            let obj: [String: Any] = [
                "ts": iso.string(from: Date()),
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

    func fileURL() -> URL? {
        try? eventFileURL()
    }
}
