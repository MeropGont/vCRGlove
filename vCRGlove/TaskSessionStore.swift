//
//  TaskSessionStore.swift
//  vCRGlove
//
//  Persistence for movement task sessions. Mirrors the existing JournalStore
//  singleton pattern, with JSONL containing one entry per session. The guided
//  flow can atomically update an accepted session before the full set is finished.
//
//  File location follows the existing convention:
//      Documents/vcr/tasks/sessions.jsonl
//

import Foundation

final class TaskSessionStore: ObservableObject {
    static let shared: TaskSessionStore = {
        #if DEBUG && targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ui-test-session-save"),
           arguments.indices.contains(index + 1),
           let id = UUID(uuidString: arguments[index + 1]) {
            // A unique test file survives relaunch without touching actual sessions.
            var directory = FileManager.default.temporaryDirectory
            if arguments.contains("--ui-test-session-save-failure") {
                directory = directory.appendingPathComponent("missing-\(id.uuidString)")
            }
            return TaskSessionStore(storageURL: directory.appendingPathComponent("save-\(id.uuidString).jsonl"))
        }
        #endif
        return TaskSessionStore()
    }()

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

    private let storageURL: URL?

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
        load()
    }

    // MARK: - Paths

    private func fileURL() throws -> URL {
        if let storageURL { return storageURL }
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("vcr/tasks", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.jsonl")
    }

    // MARK: - Write

    /// Keep an accepted, possibly partial session under one ID. Do not advance
    /// the flow or publish a success until the atomic disk write has succeeded.
    /// Upload remains the responsibility of the final session action, not every trial.
    func saveAcceptedSession(_ session: MovementSession,
                             completion: @escaping (Result<Void, Error>) -> Void) {
        ioQueue.async {
            do {
                let url = try self.fileURL()
                let existing = FileManager.default.fileExists(atPath: url.path)
                    ? try Data(contentsOf: url) : Data()
                let updated = try Self.replacingSession(session, in: existing)
                try updated.write(to: url, options: .atomic)
                if self.storageURL == nil {
                    EventStore.shared.append(type: "TASK", tag: "recording_saved",
                        message: "Accepted movement recordings saved locally",
                        details: ["session_id": session.id.uuidString, "trials": "\(session.trials.count)"])
                }
                DispatchQueue.main.async {
                    if let index = self.sessions.firstIndex(where: { $0.id == session.id }) {
                        self.sessions[index] = session
                    } else {
                        self.sessions.append(session)
                    }
                    completion(.success(()))
                }
            } catch {
                if self.storageURL == nil {
                    EventStore.shared.append(type: "TASK", tag: "save_error",
                        message: "Save error: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// The flow calls this once when the user finishes, never after every task.
    func finishAcceptedSession(_ session: MovementSession) {
        guard storageURL == nil else { return }
        ioQueue.async {
            EventStore.shared.append(type: "TASK", tag: "session_saved",
                message: "Finished saved movement session",
                details: ["session_id": session.id.uuidString, "trials": "\(session.trials.count)",
                          "context": session.stimulationContext.rawValue])
            SessionUploader.shared.upload(session)
        }
    }

    /// Replace only the matching JSONL entry. Keep all other lines verbatim,
    /// including legacy/unknown fields and lines that cannot currently decode.
    static func replacingSession(_ session: MovementSession, in existing: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(session)
        let lines = existing.split(separator: 0x0A, omittingEmptySubsequences: false)
        var result = Data()
        var replaced = false
        for (index, line) in lines.enumerated() {
            let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            let id = (object?["id"] as? String).flatMap(UUID.init(uuidString:))
            if id == session.id {
                if replaced { continue }
                result.append(encoded)
                replaced = true
            } else {
                result.append(contentsOf: line)
            }
            if index < lines.count - 1 { result.append(0x0A) }
        }
        if !replaced {
            if !result.isEmpty, result.last != 0x0A { result.append(0x0A) }
            result.append(encoded)
            result.append(0x0A)
        }
        return result
    }

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
