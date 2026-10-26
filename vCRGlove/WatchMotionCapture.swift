import Foundation
import Combine

/// Watch-relative spacing is preserved. Receipt anchoring is not clock sync.
@MainActor
final class WatchMotionCapture: ObservableObject {
    enum CaptureError: LocalizedError {
        case watchNotReachable, startTimedOut, streamFailed

        var errorDescription: String? {
            switch self {
            case .watchNotReachable:
                return L10n("Apple Watch is not reachable. Open the vCRGlove app on your watch and make sure Bluetooth is on.")
            case .startTimedOut: return L10n("watch.startTimeout")
            case .streamFailed: return L10n("watch.startFailed")
            }
        }
    }

    @Published private(set) var isReceiving = false
    var onSample: (@MainActor (_ value: Double, _ time: Double) -> Void)?
    private let transport: any WatchMotionTransport
    private let now: () -> Double
    private let startupTimeout: TimeInterval
    private var activeID: UUID?
    private var watchAnchor: Double?
    private var phoneAnchor: Double = 0
    private var lastWatchTime: Double?
    private var lastBatchAt: Double = 0
    private var timer: Timer?
    private var startCompletion: (@MainActor (Result<Void, CaptureError>) -> Void)?

    init(transport: (any WatchMotionTransport)? = nil, startupTimeout: TimeInterval = 8,
         now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport ?? PhoneWC.shared
        self.startupTimeout = startupTimeout
        self.now = now
    }

    deinit { timer?.invalidate() }

    func start(completion: @escaping @MainActor (Result<Void, CaptureError>) -> Void) {
        stop()
        guard transport.isWatchReachable else { completion(.failure(.watchNotReachable)); return }
        let id = UUID()
        activeID = id
        watchAnchor = nil
        lastWatchTime = nil
        lastBatchAt = now()
        let startedAt = now()
        startCompletion = completion
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeID == id else { return }
                if self.startCompletion != nil, self.now() - startedAt >= self.startupTimeout {
                    self.fail(.startTimedOut, id: id)
                } else if self.now() - self.lastBatchAt > 1.5 {
                    self.isReceiving = false
                }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        transport.startMotionStream(id: id, onBatch: { [weak self] samples in
            self?.ingest(samples, id: id)
        }, onFailure: { [weak self] in self?.fail(.streamFailed, id: id) })
    }

    func stop(completion: (() -> Void)? = nil) {
        let id = activeID
        activeID = nil
        startCompletion = nil
        timer?.invalidate()
        timer = nil
        isReceiving = false
        if let id { transport.stopMotionStream(id: id) }
        completion?()
    }

    private func fail(_ error: CaptureError, id: UUID) {
        guard activeID == id else { return }
        let completion = startCompletion
        stop()
        completion?(.failure(error))
    }

    private func ingest(_ samples: [[Double]], id: UUID) {
        guard activeID == id, WatchStreamProtocol.validSamples(samples),
              lastWatchTime.map({ samples[0][0] > $0 }) ?? true else { return }
        if watchAnchor == nil {
            // Anchor the newest buffered sample to receipt, not into the future.
            watchAnchor = samples.last![0]
            phoneAnchor = now()
        }
        guard let watchAnchor else { return }
        lastWatchTime = samples.last?[0]
        lastBatchAt = now()
        isReceiving = true
        let completion = startCompletion
        startCompletion = nil
        completion?(.success(()))
        guard activeID == id else { return }
        for sample in samples {
            guard activeID == id else { return }
            onSample?(sample[1], sample[0] - watchAnchor + phoneAnchor)
        }
    }
}
