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
import AVFoundation
import UIKit

/// Only accepted videos live here. The directory is neither temporary nor exposed by Files sharing.
final class MovementVideoStore: Sendable {
    static let shared = MovementVideoStore()
    private let directory: URL?

    enum VideoError: LocalizedError {
        case unavailable
        case invalidReference
        var errorDescription: String? { "The video could not be saved. Your measurement is still here." }
    }

    init(directory: URL? = nil) { self.directory = directory }

    private func root() throws -> URL {
        if let directory { return directory }
        return try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("vcr/tasks/videos", isDirectory: true)
    }

    func url(for trial: Trial) throws -> URL {
        guard let video = trial.video, video.fileName == "\(trial.id.uuidString).mov" else {
            throw VideoError.invalidReference
        }
        return try root().appendingPathComponent(video.fileName)
    }

    func save(_ temporaryURL: URL, for trial: Trial,
              captureStartPTSSeconds: Double? = nil, normalizedSourceCrop: CGRect? = nil) throws -> MovementVideoReference {
        guard trial.source == .camera, trial.taskType.preferredSource == .camera else {
            throw VideoError.invalidReference
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            throw VideoError.unavailable
        }
        var directory = try root()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A study-approved independent backup is a separate feature, not implicit iCloud storage.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        // Reading timing is optional and never blocks saving a usable measurement/movie.
        let timing: MovementVideoTiming?
        if let captureStartPTSSeconds, captureStartPTSSeconds.isFinite, trial.startUptime != nil {
            timing = MovementVideoTiming.make(captureStartPTS: captureStartPTSSeconds,
                trialStartUptime: trial.startUptime, firstMoviePTS: Self.firstVideoPTS(at: temporaryURL))
        } else { timing = nil }
        let reference = MovementVideoReference(fileName: "\(trial.id.uuidString).mov",
            byteCount: size.int64Value, timing: timing,
            faceMaskingVersion: MovementFaceMasker.isProcessedFile(temporaryURL) ? MovementFaceMasker.version : nil,
            normalizedSourceCrop: normalizedSourceCrop)
        var destination = directory.appendingPathComponent(reference.fileName)
        try FileManager.default.copyItem(at: temporaryURL, to: destination)
        do {
            try destination.setResourceValues(values)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete],
                                                  ofItemAtPath: destination.path)
            return reference
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Reads the first compressed video sample only; no pixel decoding or full-video scan.
    static func firstVideoPTS(at url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        guard let sample = output.copyNextSampleBuffer() else { return nil }
        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let seconds = pts.seconds
        return pts.isNumeric && seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    func remove(_ trial: Trial) {
        guard let url = try? url(for: trial) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func delete(_ trial: Trial) throws {
        let file = try url(for: trial)
        do { try FileManager.default.removeItem(at: file) }
        catch CocoaError.fileNoSuchFile { /* A previously removed file needs only metadata cleanup. */ }
    }

    /// Share only existing, validated app-owned files. No extra export copies are created.
    func shareURLs(for trials: [Trial]) throws -> [URL] {
        var seen = Set<UUID>()
        return try trials.filter { seen.insert($0.id).inserted }.map { trial in
            let file = try url(for: trial)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
                throw VideoError.unavailable
            }
            return file
        }
    }

    func copyExportSnapshot(to destination: URL) throws {
        let directory = try root()
        let files: [URL]
        do { files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) }
        catch CocoaError.fileReadNoSuchFile { return }
        for file in files {
            // Include orphaned accepted movies too, but never follow arbitrary paths or symbolic links.
            guard file.pathExtension == "mov", UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil else {
                throw VideoError.invalidReference
            }
            guard try FullDataExporter.copyFile(file, to: destination.appendingPathComponent(file.lastPathComponent)) else {
                throw VideoError.unavailable
            }
        }
    }
}

enum MovementVideoPreference {
    static let key = "saveMovementVideos"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil || defaults.bool(forKey: key)
    }
}

/// Owns an unaccepted movie, including cleanup if its view is destroyed.
final class MovementVideoDraft: ObservableObject {
    @Published private(set) var url: URL?
    @Published private(set) var unavailable = false
    private(set) var captureStartPTSSeconds: Double?
    private(set) var normalizedHandCrop: CGRect?
    private(set) var isVideoEnabledForTake = true

    func beginTake(defaults: UserDefaults = .standard) {
        discard()
        isVideoEnabledForTake = MovementVideoPreference.isEnabled(in: defaults)
    }

    var messageKey: String? {
        if url != nil { return "Video stays in the app when you save." }
        if unavailable { return "Video unavailable. Your measurement can still be saved." }
        return nil
    }

    func receive(_ url: URL?, captureStartPTSSeconds: Double? = nil, normalizedHandCrop: CGRect? = nil) {
        guard isVideoEnabledForTake else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return
        }
        self.normalizedHandCrop = url == nil ? nil : normalizedHandCrop
        if self.url == url {
            self.captureStartPTSSeconds = url == nil ? nil : captureStartPTSSeconds
            unavailable = url == nil
            return
        }
        discard()
        self.url = url
        self.captureStartPTSSeconds = url == nil ? nil : captureStartPTSSeconds
        self.normalizedHandCrop = url == nil ? nil : normalizedHandCrop
        unavailable = url == nil
    }

    func discard() {
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
        captureStartPTSSeconds = nil
        normalizedHandCrop = nil
        unavailable = false
    }

    deinit {
        if let url { try? FileManager.default.removeItem(at: url) }
    }
}

final class TaskSessionStore: ObservableObject {
    enum VideoPreparationState { case queued, preparing, unavailable }
    typealias VideoProcessor = @Sendable (URL, CGRect?) async throws -> URL
    private struct VideoJob {
        let sessionID: UUID
        let trialID: UUID
        let source: URL
        let captureStartPTS: Double?
        let handCrop: CGRect
    }
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
            return TaskSessionStore(storageURL: directory.appendingPathComponent("save-\(id.uuidString).jsonl"),
                videoStore: MovementVideoStore(directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("videos-\(id.uuidString)", isDirectory: true)))
        }
        #endif
        return TaskSessionStore()
    }()

    @Published private(set) var sessions: [MovementSession] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var activityHistoryLoadFailed = false
    @Published private(set) var videoPreparationStates: [UUID: VideoPreparationState] = [:]
    private var videoJobs: [VideoJob] = []
    private var videoWorker: Task<Void, Never>?
    private let videoProcessor: VideoProcessor

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
    let videoStore: MovementVideoStore

    init(storageURL: URL? = nil, videoStore: MovementVideoStore = .shared,
         videoProcessor: @escaping VideoProcessor = { try await MovementFaceMasker.consume($0, handCrop: $1) }) {
        self.storageURL = storageURL
        self.videoStore = videoStore
        self.videoProcessor = videoProcessor
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

    func copyExportSnapshot(to destination: URL, includeVideos: Bool = true) async throws -> [String] {
        let source = try fileURL()
        let videos = videoStore
        return try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    let path = "tasks/sessions.jsonl"
                    let exists = try FullDataExporter.copyFile(source, to: destination.appendingPathComponent(path))
                    if includeVideos {
                        try videos.copyExportSnapshot(to: destination.appendingPathComponent("tasks/videos", isDirectory: true))
                    }
                    continuation.resume(returning: exists ? [] : [path])
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Commit the movie before the JSONL reference. Roll back a new movie on failure,
    /// but keep the temporary source so the patient can retry without re-recording.
    func saveAcceptedTrial(_ trial: Trial, in session: MovementSession, temporaryVideoURL: URL?,
                           videoCaptureStartPTSSeconds: Double? = nil,
                           normalizedHandCrop: CGRect? = nil,
                           deferVideoProcessing: Bool = false,
                           completion: @escaping (Result<MovementSession, Error>) -> Void) {
        if deferVideoProcessing, let source = temporaryVideoURL,
           !MovementFaceMasker.isProcessedFile(source) {
            // Commit measurements before handing the draft to the app-owned queue.
            saveAcceptedTrial(trial, in: session, temporaryVideoURL: nil) { result in
                if case .success = result {
                    self.enqueueVideo(source, sessionID: session.id, trialID: trial.id,
                        captureStartPTS: videoCaptureStartPTSSeconds, handCrop: normalizedHandCrop)
                }
                completion(result)
            }
            return
        }
        ioQueue.async {
            var accepted = trial
            var copiedVideo = false
            do {
                let file = try self.fileURL()
                let existing = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data()
                let previousTrials = existing.split(separator: 0x0A).compactMap {
                    try? self.decoder.decode(MovementSession.self, from: Data($0))
                }.first(where: { $0.id == session.id })?.trials ?? session.trials
                if let temporaryVideoURL {
                    if Self.deletedVideoIDs(in: existing).contains(trial.id) {
                        throw MovementVideoStore.VideoError.invalidReference
                    }
                    accepted = trial.withVideo(try self.videoStore.save(temporaryVideoURL, for: trial,
                        captureStartPTSSeconds: videoCaptureStartPTSSeconds))
                    copiedVideo = true
                }
                var updated = session
                updated.accept(accepted)
                updated = try self.writeSession(updated)
                if let temporaryVideoURL { try? FileManager.default.removeItem(at: temporaryVideoURL) }
                for previous in previousTrials where previous.taskType == trial.taskType
                    && previous.side == trial.side && previous.id != trial.id {
                    self.videoStore.remove(previous)
                }
                if self.storageURL == nil {
                    EventStore.shared.append(type: "TASK", tag: "recording_saved",
                        message: "Accepted movement recording saved locally",
                        details: ["session_id": session.id.uuidString,
                                  "video": accepted.video == nil ? "none" : "private"])
                }
                DispatchQueue.main.async {
                    self.publish(updated)
                    completion(.success(updated))
                }
            } catch {
                if copiedVideo { self.videoStore.remove(accepted) }
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Transfer ownership before the recording view clears its draft or disappears.
    private func enqueueVideo(_ source: URL, sessionID: UUID, trialID: UUID, captureStartPTS: Double?, handCrop: CGRect?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let handCrop else {
            try? FileManager.default.removeItem(at: source)
            videoPreparationStates[trialID] = .unavailable
            return
        }
        do {
            let owned = try MovementFaceMasker.recordingURL()
            try FileManager.default.moveItem(at: source, to: owned)
            videoPreparationStates[trialID] = .queued
            videoJobs.append(VideoJob(sessionID: sessionID, trialID: trialID,
                source: owned, captureStartPTS: captureStartPTS, handCrop: handCrop))
            startVideoWorkerIfNeeded()
        } catch {
            try? FileManager.default.removeItem(at: source)
            videoPreparationStates[trialID] = .unavailable
        }
    }

    private func startVideoWorkerIfNeeded() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard videoWorker == nil, !videoJobs.isEmpty else { return }
        videoWorker = Task { @MainActor in
            while !videoJobs.isEmpty {
                let job = videoJobs.removeFirst()
                videoPreparationStates[job.trialID] = .preparing
                let processor = videoProcessor
                let processing = Task.detached(priority: .utility) { try await processor(job.source, job.handCrop) }
                let backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Prepare movement video") {
                    processing.cancel()
                    // Do not leave more unprocessed originals queued after background time expires.
                    for waiting in self.videoJobs {
                        try? FileManager.default.removeItem(at: waiting.source)
                        self.videoPreparationStates[waiting.trialID] = .unavailable
                    }
                    self.videoJobs.removeAll()
                }
                do {
                    let output = try await processing.value
                    defer { try? FileManager.default.removeItem(at: output) }
                    try Task.checkCancellation()
                    if processing.isCancelled { throw CancellationError() }
                    _ = try await attachPreparedVideo(output, job: job)
                    videoPreparationStates.removeValue(forKey: job.trialID)
                } catch {
                    videoPreparationStates[job.trialID] = .unavailable
                }
                try? FileManager.default.removeItem(at: job.source)
                if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) }
            }
            videoWorker = nil
        }
    }

    private func attachPreparedVideo(_ output: URL, job: VideoJob) async throws -> MovementSession {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                var copiedTrial: Trial?
                do {
                    // Read the current record: never reinsert a discarded/retaken take or
                    // overwrite tasks completed while its movie was processing.
                    let data = try Data(contentsOf: self.fileURL())
                    guard MovementFaceMasker.isProcessedFile(output),
                          !Self.deletedVideoIDs(in: data).contains(job.trialID),
                          var session = data.split(separator: 0x0A).compactMap({
                              try? self.decoder.decode(MovementSession.self, from: Data($0))
                          }).first(where: { $0.id == job.sessionID }),
                          let index = session.trials.firstIndex(where: { $0.id == job.trialID }),
                          session.trials[index].video == nil else {
                        throw MovementVideoStore.VideoError.invalidReference
                    }
                    let trial = session.trials[index]
                    let accepted = trial.withVideo(try self.videoStore.save(output, for: trial,
                        captureStartPTSSeconds: job.captureStartPTS, normalizedSourceCrop: job.handCrop))
                    copiedTrial = accepted
                    session.trials[index] = accepted
                    let saved = try self.writeSession(session)
                    // Publish in the same I/O-to-main order as ordinary saves, not
                    // later when the worker's awaiting task happens to resume.
                    DispatchQueue.main.async {
                        self.publish(saved)
                        continuation.resume(returning: saved)
                    }
                } catch {
                    if let copiedTrial { self.videoStore.remove(copiedTrial) }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func writeSession(_ session: MovementSession) throws -> MovementSession {
        let url = try fileURL()
        let existing = FileManager.default.fileExists(atPath: url.path) ? try Data(contentsOf: url) : Data()
        let updated = try Self.replacingSession(session, in: existing)
        try updated.write(to: url, options: .atomic)
        let lines: [Data.SubSequence] = updated.split(separator: 0x0A)
        for line in lines {
            let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            if (object?["id"] as? String).flatMap(UUID.init(uuidString:)) == session.id {
                return try decoder.decode(MovementSession.self, from: Data(line))
            }
        }
        throw MovementVideoStore.VideoError.invalidReference
    }

    private func publish(_ session: MovementSession) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    /// Keep an accepted, possibly partial session under one ID. Do not advance
    /// the flow or publish a success until the atomic disk write has succeeded.
    /// Upload remains the responsibility of the final session action, not every trial.
    func saveAcceptedSession(_ session: MovementSession,
                             completion: @escaping (Result<Void, Error>) -> Void) {
        ioQueue.async {
            do {
                let updated = try self.writeSession(session)
                if self.storageURL == nil {
                    EventStore.shared.append(type: "TASK", tag: "recording_saved",
                        message: "Accepted movement recordings saved locally",
                        details: ["session_id": session.id.uuidString, "trials": "\(session.trials.count)"])
                }
                DispatchQueue.main.async {
                    self.publish(updated)
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
            if let data = try? Data(contentsOf: self.fileURL()),
               let saved = data.split(separator: 0x0A).compactMap({
                   try? self.decoder.decode(MovementSession.self, from: Data($0))
               }).first(where: { $0.id == session.id }) {
                SessionUploader.shared.upload(saved)
            }
        }
    }

    /// Replace only the matching JSONL entry. Keep all other lines verbatim,
    /// including legacy/unknown fields and lines that cannot currently decode.
    static func replacingSession(_ session: MovementSession, in existing: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var encodedObject = try JSONSerialization.jsonObject(with: encoder.encode(session)) as! [String: Any]
        let lines = existing.split(separator: 0x0A, omittingEmptySubsequences: false)
        var result = Data()
        var replaced = false
        for (index, line) in lines.enumerated() {
            let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            let id = (object?["id"] as? String).flatMap(UUID.init(uuidString:))
            if id == session.id {
                if replaced { continue }
                // A stale recording-flow checkpoint must not restore a patient-deleted video.
                let oldTrials = object?["trials"] as? [[String: Any]] ?? []
                var newTrials = encodedObject["trials"] as? [[String: Any]] ?? []
                for index in newTrials.indices {
                    if let old = oldTrials.first(where: {
                        ($0["id"] as? String).flatMap(UUID.init(uuidString:)) ==
                            (newTrials[index]["id"] as? String).flatMap(UUID.init(uuidString:))
                    }),
                       let deletedAt = old["videoDeletedAt"] as? String {
                        newTrials[index].removeValue(forKey: "video")
                        newTrials[index]["videoDeletedAt"] = deletedAt
                    } else if newTrials[index]["video"] == nil,
                              let old = oldTrials.first(where: { $0["id"] as? String == newTrials[index]["id"] as? String }),
                              let video = old["video"] {
                        // The flow may still hold a checkpoint from before deferred masking finished.
                        newTrials[index]["video"] = video
                    }
                }
                encodedObject["trials"] = newTrials
                result.append(try JSONSerialization.data(withJSONObject: encodedObject, options: [.sortedKeys]))
                replaced = true
            } else {
                result.append(contentsOf: line)
            }
            if index < lines.count - 1 { result.append(0x0A) }
        }
        if !replaced {
            if !result.isEmpty, result.last != 0x0A { result.append(0x0A) }
            result.append(try encoder.encode(session))
            result.append(0x0A)
        }
        return result
    }

    struct VideoDeletionResult {
        let deletedCount: Int
        let failedCount: Int
    }

    private static func deletedVideoIDs(in data: Data) -> Set<UUID> {
        Set(data.split(separator: 0x0A).flatMap { line -> [UUID] in
            let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            return (object?["trials"] as? [[String: Any]] ?? []).compactMap {
                guard $0["videoDeletedAt"] is String else { return nil }
                return ($0["id"] as? String).flatMap(UUID.init(uuidString:))
            }
        })
    }

    /// Remove only selected private movies. Measurements and other JSON fields stay intact.
    func deleteVideos(ids: Set<UUID>, completion: @escaping (Result<VideoDeletionResult, Error>) -> Void) {
        ioQueue.async {
            do {
                let url = try self.fileURL()
                let existing = try Data(contentsOf: url)
                let sessions = existing.split(separator: 0x0A).compactMap {
                    try? self.decoder.decode(MovementSession.self, from: Data($0))
                }
                let selected = sessions.flatMap(\.trials).filter { ids.contains($0.id) && $0.video != nil }
                var deleted = Set<UUID>()
                var failed = Set<UUID>()
                for trial in selected where !deleted.contains(trial.id) && !failed.contains(trial.id) {
                    do { try self.videoStore.delete(trial); deleted.insert(trial.id) }
                    catch { failed.insert(trial.id) }
                }
                let updated = try Self.removingVideoReferences(ids: deleted, in: existing)
                try updated.write(to: url, options: .atomic)
                let restored = updated.split(separator: 0x0A).compactMap {
                    try? self.decoder.decode(MovementSession.self, from: Data($0))
                }
                DispatchQueue.main.async {
                    self.sessions = restored
                    completion(.success(VideoDeletionResult(deletedCount: deleted.count, failedCount: failed.count)))
                }
            } catch {
                // Files already removed stay removed; retry can clear their stale references.
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    static func removingVideoReferences(ids: Set<UUID>, in existing: Data, deletedAt: Date = Date()) throws -> Data {
        var result = Data()
        let lines = existing.split(separator: 0x0A, omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            if var object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               var trials = object["trials"] as? [[String: Any]],
               trials.contains(where: { ($0["id"] as? String).flatMap(UUID.init(uuidString:)).map(ids.contains) == true }) {
                for index in trials.indices {
                    if let id = (trials[index]["id"] as? String).flatMap(UUID.init(uuidString:)), ids.contains(id) {
                        trials[index].removeValue(forKey: "video")
                        trials[index]["videoDeletedAt"] = ISO8601DateFormatter().string(from: deletedAt)
                    }
                }
                object["trials"] = trials
                result.append(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            } else { result.append(contentsOf: line) }
            if index < lines.count - 1 { result.append(0x0A) }
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
                let text = FileManager.default.fileExists(atPath: url.path)
                    ? try String(contentsOf: url, encoding: .utf8) : ""
                let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                let loaded = lines.compactMap { line -> MovementSession? in
                        guard let data = line.data(using: .utf8) else { return nil }
                        return try? self.decoder.decode(MovementSession.self, from: data)
                    }
                DispatchQueue.main.async {
                    // Sessions saved while loading (unlikely) stay — prepend disk state.
                    self.sessions = loaded + self.sessions
                    self.activityHistoryLoadFailed = loaded.count != lines.count
                    self.hasLoaded = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.activityHistoryLoadFailed = true
                    self.hasLoaded = true
                }
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
