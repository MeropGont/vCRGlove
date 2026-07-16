//
//  PhoneWC.swift
//  vCRGlove
//
//  Created by Tactile Glove on 16.09.25.
//

import Foundation
import WatchConnectivity

final class PhoneWC: NSObject, WCSessionDelegate {
    static let shared = PhoneWC()
    private override init() { super.init(); activate() }

    private func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - Live motion streaming (movement tasks, e.g. 3.6)

    /// Set by WatchMotionCapture during a trial. Called on a background queue
    /// with one batch of [timestamp, value] pairs (watch monotonic clock).
    var onMotionBatch: (([[Double]]) -> Void)?

    var isWatchReachable: Bool {
        WCSession.isSupported() && WCSession.default.isReachable
    }

    func startMotionStream() {
        guard WCSession.default.activationState == .activated else {
            Logger.shared.log("WC", "Cannot start stream: WCSession not activated yet")
            return
        }
        attemptStartMotionStream(retriesLeft: 10)
    }

    private func attemptStartMotionStream(retriesLeft: Int) {
        guard WCSession.default.isReachable else {
            Logger.shared.log("WC", "Watch not reachable, retries left: \(retriesLeft)")
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.attemptStartMotionStream(retriesLeft: retriesLeft - 1)
                }
            } else {
                // Fall back to queued delivery; the watch will act on it when it becomes reachable.
                WCSession.default.transferUserInfo(["type": "startMotionStream"])
                Logger.shared.log("WC", "Queued startMotionStream via transferUserInfo")
            }
            return
        }
        WCSession.default.sendMessage(["type": "startMotionStream"],
                                      replyHandler: nil,
                                      errorHandler: { error in
            Logger.shared.log("WC", "startMotionStream failed: \(error.localizedDescription)")
        })
        Logger.shared.log("WC", "Sent startMotionStream")
    }

    func stopMotionStream() {
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(["type": "stopMotionStream"],
                                          replyHandler: nil,
                                          errorHandler: { error in
                Logger.shared.log("WC", "stopMotionStream failed: \(error.localizedDescription)")
            })
        } else {
            WCSession.default.transferUserInfo(["type": "stopMotionStream"])
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        // High-frequency motion batches go straight to the capture pipeline —
        // never into the handshake log.
        if message["type"] as? String == "motionBatch" {
            if let samples = message["samples"] as? [[Double]] {
                onMotionBatch?(samples)
            }
            return
        }
        append(["kind":"message","payload":message, "ts_phone": ISO8601DateFormatter().string(from: Date())])
    }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        append(["kind":"userInfo","payload":userInfo, "ts_phone": ISO8601DateFormatter().string(from: Date())])
    }

    // activation stubs
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

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
