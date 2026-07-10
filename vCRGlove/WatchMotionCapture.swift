//
//  WatchMotionCapture.swift
//  vCRGlove
//
//  Live movement-signal source backed by the Apple Watch (CoreMotion via
//  WatchConnectivity). Mirrors the VisionHandPoseCapture API so
//  MovementTaskView can treat camera and watch sources identically:
//  start → onSample(value, monotonicTime) → stop.
//
//  Signal for 3.6 (pronation/supination): rotation rate around the forearm
//  axis in rad/s. The watch timestamps samples with ITS OWN monotonic clock;
//  this class rebases them onto the phone's systemUptime so the TrialRecorder
//  can normalize them like any other source.
//

import Foundation
import Combine

final class WatchMotionCapture: ObservableObject {

    enum CaptureError: LocalizedError {
        case watchNotReachable

        var errorDescription: String? {
            switch self {
            case .watchNotReachable:
                return "Apple Watch is not reachable. Open the vCRGlove app on your watch and make sure Bluetooth is on."
            }
        }
    }

    /// True while motion batches are actively arriving (updated per batch,
    /// cleared if none arrive for `staleAfterSec`).
    @Published private(set) var isReceiving = false

    /// One sample per watch motion frame. Called on a background queue.
    /// `time` is rebased to the phone's monotonic clock (systemUptime).
    var onSample: ((_ value: Double, _ time: Double) -> Void)?

    private let staleAfterSec: Double = 1.0
    private var watchT0: Double?
    private var phoneT0: Double = 0
    private var staleTimer: Timer?

    func start(completion: @escaping (Result<Void, CaptureError>) -> Void) {
        guard PhoneWC.shared.isWatchReachable else {
            completion(.failure(.watchNotReachable))
            return
        }
        watchT0 = nil
        PhoneWC.shared.onMotionBatch = { [weak self] batch in
            self?.ingest(batch)
        }
        PhoneWC.shared.startMotionStream()
        startStaleTimer()
        completion(.success(()))
    }

    func stop() {
        PhoneWC.shared.stopMotionStream()
        PhoneWC.shared.onMotionBatch = nil
        staleTimer?.invalidate()
        staleTimer = nil
        DispatchQueue.main.async { [weak self] in self?.isReceiving = false }
    }

    // MARK: - Private

    private var lastBatchAt: Double = 0

    private func ingest(_ batch: [[Double]]) {
        guard !batch.isEmpty else { return }
        // Rebase watch clock → phone clock on the first sample. Relative
        // spacing within the watch stream is exact; only the offset differs.
        if watchT0 == nil {
            watchT0 = batch[0][0]
            phoneT0 = ProcessInfo.processInfo.systemUptime
        }
        guard let watchT0 else { return }

        lastBatchAt = ProcessInfo.processInfo.systemUptime
        if !isReceiving {
            DispatchQueue.main.async { [weak self] in self?.isReceiving = true }
        }
        for pair in batch where pair.count >= 2 {
            let t = pair[0] - watchT0 + phoneT0
            onSample?(pair[1], t)
        }
    }

    private func startStaleTimer() {
        staleTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let stale = ProcessInfo.processInfo.systemUptime - self.lastBatchAt > self.staleAfterSec
            if stale && self.isReceiving { self.isReceiving = false }
        }
        RunLoop.main.add(timer, forMode: .common)
        staleTimer = timer
    }
}
