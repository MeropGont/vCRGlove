//
//  WatchConnectivityManager.swift
//  vCRGloveWatch Watch App
//
//  Created by Tactile Glove on 03.09.25.
//

import Foundation
import WatchConnectivity

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func transferFile(_ url: URL, meta: [String:String] = [:]) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferFile(url, metadata: meta)
    }

    // WCSessionDelegate stubs
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { }
#if os(watchOS)
    func sessionReachabilityDidChange(_ session: WCSession) { }
#endif
}
