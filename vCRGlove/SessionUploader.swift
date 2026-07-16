//
//  SessionUploader.swift
//  vCRGlove
//
//  Automatically uploads completed MovementSessions to the UKE research
//  backend immediately after they are saved.  The patient never needs to
//  do anything — the upload happens silently in the background.
//
//  Retry policy: exponential back-off (1 s, 2 s, 4 s … up to 64 s) for
//  transient errors.  Permanently failed uploads are queued in UserDefaults
//  and retried the next time the app comes to the foreground.
//
//  Configuration:
//    • Set VCRGSLOVE_BACKEND_URL in Settings.bundle / Info.plist, or
//      hard-code it via SessionUploader.configure(baseURL:apiKey:) once
//      at app startup.
//    • The API key is stored in the iOS Keychain (never in UserDefaults).
//

import Foundation
import UIKit

final class SessionUploader {

    static let shared = SessionUploader()

    // MARK: - Configuration

    struct Config {
        /// e.g. "https://vcr.uke.de/api"
        var baseURL: URL
        /// Bearer token / API key set by the UKE backend team.
        var apiKey: String
    }

    private(set) var config: Config?

    /// Call once at app launch (e.g. in vCRGloveApp.init or AppDelegate).
    func configure(baseURL: URL, apiKey: String) {
        config = Config(baseURL: baseURL, apiKey: apiKey)
        flushPendingQueue()
    }

    // MARK: - Public API

    /// Upload one session.  Called automatically by TaskSessionStore.add().
    func upload(_ session: MovementSession) {
        guard let cfg = config else {
            enqueue(session)
            return
        }
        uploadWithRetry(session, config: cfg, attempt: 0)
    }

    // MARK: - Private

    private let uploadQueue = DispatchQueue(label: "vcr.uploader", qos: .utility)
    private let session = URLSession(configuration: {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest  = 30
        c.timeoutIntervalForResource = 60
        return c
    }())
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let pendingKey = "vcr.uploader.pending"
    private static let maxAttempts = 7   // 1+2+4+8+16+32+64 s total wait ≈ 2 min

    private init() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(appForegrounded),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appForegrounded() { flushPendingQueue() }

    // MARK: - Upload + retry

    private func uploadWithRetry(_ movementSession: MovementSession,
                                  config: Config,
                                  attempt: Int) {
        uploadQueue.async { [weak self] in
            guard let self else { return }
            do {
                let body = try self.encoder.encode(movementSession)
                var request = URLRequest(url: config.baseURL.appendingPathComponent("sessions"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
                request.httpBody = body

                let sema = DispatchSemaphore(value: 0)
                var result: Result<Void, Error> = .failure(URLError(.unknown))

                self.session.dataTask(with: request) { _, response, error in
                    if let error {
                        result = .failure(error)
                    } else if let http = response as? HTTPURLResponse,
                              http.statusCode == 200 || http.statusCode == 201 {
                        result = .success(())
                    } else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                        result = .failure(URLError(.init(rawValue: code)))
                    }
                    sema.signal()
                }.resume()
                sema.wait()

                switch result {
                case .success:
                    EventStore.shared.append(
                        type: "UPLOAD", tag: "success",
                        message: "Session uploaded to backend",
                        details: ["session_id": movementSession.id.uuidString,
                                  "patient":    movementSession.patientId])
                case .failure(let error):
                    guard attempt < Self.maxAttempts else {
                        EventStore.shared.append(
                            type: "UPLOAD", tag: "failed_permanent",
                            message: "Upload permanently failed, queued for later",
                            details: ["error": error.localizedDescription])
                        self.enqueue(movementSession)
                        return
                    }
                    let delay = pow(2.0, Double(attempt))
                    EventStore.shared.append(
                        type: "UPLOAD", tag: "retry",
                        message: "Upload failed, retry in \(Int(delay))s (attempt \(attempt+1))",
                        details: ["error": error.localizedDescription])
                    self.uploadQueue.asyncAfter(deadline: .now() + delay) {
                        self.uploadWithRetry(movementSession, config: config, attempt: attempt + 1)
                    }
                }
            } catch {
                EventStore.shared.append(
                    type: "UPLOAD", tag: "encode_error",
                    message: "Failed to encode session: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Pending queue (UserDefaults, survives app restarts)

    private func enqueue(_ session: MovementSession) {
        guard let data = try? encoder.encode(session) else { return }
        var pending = rawPending()
        pending.append(data)
        UserDefaults.standard.set(pending, forKey: Self.pendingKey)
    }

    private func flushPendingQueue() {
        guard let cfg = config else { return }
        let pending = rawPending()
        guard !pending.isEmpty else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingKey)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for data in pending {
            if let s = try? decoder.decode(MovementSession.self, from: data) {
                uploadWithRetry(s, config: cfg, attempt: 0)
            }
        }
    }

    private func rawPending() -> [Data] {
        UserDefaults.standard.array(forKey: Self.pendingKey) as? [Data] ?? []
    }
}
