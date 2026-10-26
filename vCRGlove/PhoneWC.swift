//
//  PhoneWC.swift
//  vCRGlove
//
//  Created by Tactile Glove on 16.09.25.
//

import Foundation
import WatchConnectivity
import Combine

@MainActor
protocol WatchMotionTransport: AnyObject {
    var isWatchReachable: Bool { get }
    func startMotionStream(id: UUID, onBatch: @escaping ([[Double]]) -> Void, onFailure: @escaping () -> Void)
    func stopMotionStream(id: UUID)
}

@MainActor
final class PhoneWC: NSObject, ObservableObject, WCSessionDelegate, WatchMotionTransport {
    static let shared = PhoneWC()
    private override init() { super.init(); activate() }

    private func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Live motion streaming (movement tasks, e.g. 3.6)

    private var cursor: WatchStreamBatchCursor?
    private var startAcknowledged = false
    private var onMotionBatch: (([[Double]]) -> Void)?
    private var onStreamFailure: (() -> Void)?

    @Published private(set) var isWatchReachable = false

    private func refreshReachability() {
        isWatchReachable = WCSession.isSupported() && WCSession.default.activationState == .activated && WCSession.default.isReachable
    }

    func startMotionStream(id: UUID, onBatch: @escaping ([[Double]]) -> Void, onFailure: @escaping () -> Void) {
        guard isWatchReachable else { onFailure(); return }
        if let previous = cursor?.id { stopMotionStream(id: previous) }
        cursor = WatchStreamBatchCursor(id: id)
        startAcknowledged = false
        onMotionBatch = onBatch
        onStreamFailure = onFailure
        WCSession.default.sendMessage(WatchStreamProtocol.command("startMotionStream", id: id), replyHandler: { [weak self] reply in
            Task { @MainActor in
                guard let self, self.cursor?.id == id else { return }
                guard WatchStreamProtocol.streamID(in: reply) == id, reply["accepted"] as? Bool == true else {
                    Logger.shared.log("WC", "Watch rejected start; update both apps or open the Watch app")
                    self.failStream(id: id)
                    return
                }
                self.startAcknowledged = true
            }
        }, errorHandler: { [weak self] error in
            Task { @MainActor in
                Logger.shared.log("WC", "Stream start failed: \(error.localizedDescription)")
                self?.failStream(id: id)
            }
        })
    }

    private func failStream(id: UUID) {
        guard cursor?.id == id else { return }
        let failure = onStreamFailure
        stopMotionStream(id: id)
        failure?()
    }

    func stopMotionStream(id: UUID) {
        guard cursor?.id == id else { return }
        cursor = nil
        startAcknowledged = false
        onMotionBatch = nil
        onStreamFailure = nil
        let message = WatchStreamProtocol.command("stopMotionStream", id: id)
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(message, replyHandler: { reply in
                if reply["accepted"] as? Bool != true { session.transferUserInfo(message) }
            }, errorHandler: { _ in session.transferUserInfo(message) })
        } else {
            // Only stops may be queued. A late stop is scoped to its original ID.
            session.transferUserInfo(message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in self.receive(message) }
    }

    private func receive(_ message: [String: Any]) {
        // High-frequency motion batches go straight to the capture pipeline —
        // never into the handshake log.
        if message["type"] as? String == "motionBatch" {
            if startAcknowledged, let samples = cursor?.accept(message) {
                onMotionBatch?(samples)
            }
            return
        }
        append(["kind":"message","payload":message, "ts_phone": ISO8601DateFormatter().string(from: Date())])
    }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.append(["kind":"userInfo","payload":userInfo, "ts_phone": ISO8601DateFormatter().string(from: Date())])
        }
    }

    // activation stubs
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.refreshReachability() }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshReachability() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in self.isWatchReachable = false }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    private func append(_ obj: [String:Any]) {
        do {
            let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = docs.appendingPathComponent("vcr/logs", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("handshake.jsonl")
            let data = try JSONSerialization.data(withJSONObject: obj) + Data([0x0A])
            if FileManager.default.fileExists(atPath: url.path) {
                let h = try FileHandle(forWritingTo: url); defer { try? h.close() }
                try h.seekToEnd(); try h.write(contentsOf: data)
            } else {
                try data.write(to: url)
            }
            Logger.shared.log("WC", "Logged handshake → \(url.lastPathComponent)")
        } catch {
            Logger.shared.log("WC", "Write error: \(error.localizedDescription)")
        }
    }
}
