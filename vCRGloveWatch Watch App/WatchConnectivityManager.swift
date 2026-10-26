import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    private var commands = WatchStreamCommandGate()

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
    func sendMotionBatch(_ samples: [[Double]], id: UUID, sequence: Int) {
        let s = WCSession.default
        guard s.isReachable else { return }
        var message = WatchStreamProtocol.command("motionBatch", id: id)
        message["samples"] = samples
        message["sequence"] = sequence
        s.sendMessage(message,
                      replyHandler: nil,
                      errorHandler: { error in
            print("WC sendMotionBatch failed:", error.localizedDescription)
        })
    }

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            print("WC activation failed:", error.localizedDescription)
        } else {
            print("WC activation state:", activationState.rawValue)
        }
    }

    /// Phone-initiated commands: start/stop streaming for a movement trial.
    private func handleCommand(_ message: [String: Any], queued: Bool = false,
                               reply: (([String: Any]) -> Void)? = nil) {
        DispatchQueue.main.async {
            guard let type = message["type"] as? String,
                  let id = WatchStreamProtocol.streamID(in: message) else {
                reply?(["accepted": false, "protocolVersion": WatchStreamProtocol.version])
                return
            }
            let motion = MotionService.shared
            var accepted = false
            switch type {
            case "startMotionStream":
                if !queued, (!motion.isStreaming || motion.streamID == id), self.commands.start(id) {
                    accepted = motion.startStreaming(id: id, phoneControlled: true)
                    if !accepted { self.commands.end(id) }
                }
            case "stopMotionStream":
                self.commands.end(id)
                if motion.streamID == id { motion.stopStreaming() }
                accepted = true
            default: break
            }
            var response = WatchStreamProtocol.command("streamAcknowledgement", id: id)
            response["accepted"] = accepted
            reply?(response)
        }
    }

    func streamDidEnd(_ id: UUID) { commands.end(id) }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleCommand(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        handleCommand(message, reply: replyHandler)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // A queued start could begin recording long after the patient left.
        guard userInfo["type"] as? String == "stopMotionStream" else { return }
        handleCommand(userInfo, queued: true)
    }

    #if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("WC reachability changed:", session.isReachable)
    }
    #endif
}
