//
//  LiveSignalMonitor.swift
//  vCRGlove
//
//  Debug/feedback helper: collects the live 1-D movement signal from any
//  capture source and publishes a downsampled recent window for a small
//  real-time chart in the recording UI. Purely visual — does not affect
//  the TrialRecorder or the analysis pipeline.
//

import Foundation
import Combine

final class LiveSignalMonitor: ObservableObject {

    /// Recent samples (last `windowSec` seconds), published at ~10 Hz.
    @Published private(set) var window: [TimestampedSample] = []

    /// How many seconds of signal to keep/display.
    let windowSec: Double = 5.0

    private var buffer: [TimestampedSample] = []
    private var lastPublish: Double = 0
    private let queue = DispatchQueue(label: "vcr.livesignal", qos: .utility)

    /// Safe to call from any thread. `time` is monotonic (systemUptime-like).
    func ingest(value: Double, at time: Double) {
        queue.async { [weak self] in
            guard let self else { return }
            self.buffer.append(TimestampedSample(t: time, value: value))
            // Trim to window.
            let cutoff = time - self.windowSec
            if let firstKept = self.buffer.firstIndex(where: { $0.t >= cutoff }),
               firstKept > 0 {
                self.buffer.removeFirst(firstKept)
            }
            // Publish at most every 100 ms.
            guard time - self.lastPublish >= 0.1 else { return }
            self.lastPublish = time
            let snapshot = self.buffer
            DispatchQueue.main.async { self.window = snapshot }
        }
    }

    func reset() {
        queue.async { [weak self] in
            self?.buffer.removeAll()
            self?.lastPublish = 0
            DispatchQueue.main.async { self?.window = [] }
        }
    }
}
