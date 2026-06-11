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

    // MARK: - WCSessionDelegate
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) { }

    #if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) { }
    #endif
}
