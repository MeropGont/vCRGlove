//
//  TaskSessionStore.swift
//  vCRGlove
//
//  Persistence for movement task sessions. Mirrors the existing JournalStore
//  singleton pattern, but writes append-only JSONL (one session per line) —
//  which the repo README lists as the preferred format for longer studies.
//
//  File location follows the existing convention:
//      Documents/vcr/tasks/sessions.jsonl
//

import Foundation

final class TaskSessionStore: ObservableObject {
    static let shared = TaskSessionStore()

    @Published private(set) var sessions: [MovementSession] = []

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// sessions.jsonl with raw samples takes visible time to decode/encode).
    private let ioQueue = DispatchQueue(label: "vcr.tasksessions.io", qos: .utility)

    private init() {
        load()
    }

    // MARK: - Paths

    private func fileURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("vcr/tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.jsonl")
    }

    // MARK: - Write

    /// Append one session as a single JSONL line. The published array updates
    /// immediately; encoding + disk write happen on the IO queue so the UI
    /// never blocks (raw samples make sessions heavyweight to encode).
    func add(_ session: MovementSession) {
        if Thread.isMainThread {
            sessions.append(session)
        } else {
            DispatchQueue.main.async { self.sessions.append(session) }
        }
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                let url = try self.fileURL()
                let line = try self.encoder.encode(session) + Data([0x0A])
                if FileManager.default.fileExists(atPath: url.path) {
                    let h = try FileHandle(forWritingTo: url)
                    defer { try? h.close() }
                    try h.seekToEnd()
                    try h.write(contentsOf: line)
                } else {
                    try line.write(to: url)
                }
                // Reuse the app-wide event log so tasks land on the shared timeline.
                EventStore.shared.append(
                    type: "TASK", tag: "session_saved",
                    message: "Saved movement session",
                    details: ["patient": session.patientId,
                              "trials": "\(session.trials.count)",
                              "context": session.stimulationContext.rawValue])
                SessionUploader.shared.upload(session)
            } catch {
                EventStore.shared.append(
                    type: "TASK", tag: "save_error",
                    message: "Save error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Read

    private func load() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            do {
                let url = try self.fileURL()
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                let text = try String(contentsOf: url, encoding: .utf8)
                let loaded = text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .compactMap { line -> MovementSession? in
                        guard let data = line.data(using: .utf8) else { return nil }
                        return try? self.decoder.decode(MovementSession.self, from: data)
                    }
                DispatchQueue.main.async {
                    // Sessions saved while loading (unlikely) stay — prepend disk state.
                    self.sessions = loaded + self.sessions
                }
            } catch {
                EventStore.shared.append(
                    type: "TASK", tag: "load_error",
                    message: "Load error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Queries for the patient trend view

    /// All trials of a given task/side across sessions, oldest first —
    /// ready to feed a Swift Charts line of any metric over time.
    /// Includes the session's stimulation context so the chart can mark
    /// pre/post recordings.
    func history(task: MovementTaskType, side: BodySide)
        -> [(date: Date, context: StimulationContext, metrics: MovementMetrics)] {
        sessions
            .flatMap { s in s.trials.map { (s.date, s.stimulationContext, $0) } }
            .filter { $0.2.taskType == task && $0.2.side == side }
            .sorted { $0.0 < $1.0 }
            .map { ($0.0, $0.1, $0.2.metrics) }
    }
}
