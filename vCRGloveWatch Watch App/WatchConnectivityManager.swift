import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    override init() {
        super.init()
        if WCSession.isSupported() {
            let s = WCSession.default
            s.delegate = self
            s.activate()
        }
    }

    // 🔹 Simple ping sender for Milestone A
    func sendPing() {
        let payload: [String: Any] = [
            "type": "ping",
            "ts_watch": ISO8601DateFormatter().string(from: Date())
        ]
        let s = WCSession.default
        if s.isReachable {
            s.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            s.transferUserInfo(payload) // queued & reliable
        }
    }

    func transferFile(_ url: URL, meta: [String:String] = [:]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferFile(url, metadata: meta)
    }

    // MARK: - Live motion streaming (movement tasks, e.g. 3.6)

    /// Sends one batch of [timestamp, value] pairs. Uses sendMessage (fast,
    /// unqueued) — during a live trial, stale samples are useless anyway.
    func sendMotionBatch(_ samples: [[Double]]) {
        let s = WCSession.default
        guard s.isReachable else { return }
        s.sendMessage(["type": "motionBatch", "samples": samples],
                      replyHandler: nil, errorHandler: nil)
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) { }

    /// Phone-initiated commands: start/stop streaming for a movement trial.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let type = message["type"] as? String else { return }
        DispatchQueue.main.async {
            switch type {
            case "startMotionStream": MotionService.shared.startStreaming()
            case "stopMotionStream":  MotionService.shared.stopStreaming()
            default: break
            }
        }
    }

    #if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) { }
    #endif
}
