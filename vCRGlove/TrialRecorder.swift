//
//  TrialRecorder.swift
//  vCRGlove
//
//  Sensor-agnostic recorder that buffers incoming 1-D samples and decides when
//  a trial is finished — supporting BOTH stop modes:
//    • .duration    → stop after targetDuration seconds
//    • .repetitions → stop after targetReps completed cycles (live-counted)
//
//  A capture source (Vision hand pose, Watch motion, or the synthetic generator)
//  just calls `ingest(value:at:)` for each new sample. The recorder never touches
//  hardware itself, so it runs unchanged in the Simulator.
//

import Foundation
import Combine

final class TrialRecorder: ObservableObject {

    /// Safety net for .repetitions mode: if the target rep count is never
    /// reached (e.g. severe amplitude decrement — the patient physically
    /// cannot complete 10 countable cycles), the trial still ends after this
    /// many seconds instead of hanging forever. The partial recording is
    /// analyzed and returned as usual.
    static let repetitionsSafetyTimeoutSec: Double = 30

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: Double = 0        // seconds since start
    @Published private(set) var liveCycleCount: Int = 0    // for reps-mode progress UI

    private let taskType: MovementTaskType
    private let side: BodySide
    private let source: SignalSource
    private let stopCondition: StopCondition
    private let analyzer = MovementAnalyzer()

    private var startWallClock: Date?
    private var startMonotonic: Double = 0
    private var buffer: [TimestampedSample] = []
    /// Queue-owned recording flag (recordQueue only) — @Published `isRecording`
    /// mirrors it for the UI but is written exclusively on the main thread.
    private var isActive = false
    /// Queue-owned cycle count (recordQueue only); mirrored into `liveCycleCount`.
    private var currentCycles = 0
    private var samplesSinceLastAnalysis: Int = 0
    /// Re-run the cycle-count analyzer every N samples (30 fps → ~3 Hz updates).
    private static let analysisInterval = 10

    /// Serial queue that owns all mutable state; `ingest` is safe to call from any thread.
    private let recordQueue = DispatchQueue(label: "vcr.trialrecorder", qos: .userInitiated)

    /// Called when the stop condition is met (or `finish()` is invoked manually).
    var onComplete: ((Trial) -> Void)?

    init(taskType: MovementTaskType,
         side: BodySide,
         source: SignalSource,
         stopCondition: StopCondition) {
        self.taskType = taskType
        self.side = side
        self.source = source
        self.stopCondition = stopCondition
    }

    // MARK: - Lifecycle

    func start() {
        recordQueue.async { [weak self] in
            guard let self, !self.isActive else { return }
            self.isActive = true
            self.buffer.removeAll(keepingCapacity: true)
            self.currentCycles = 0
            self.samplesSinceLastAnalysis = 0
            self.startWallClock = Date()
            self.startMonotonic = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async {
                self.liveCycleCount = 0
                self.elapsed = 0
                self.isRecording = true
            }
        }
    }

    /// Feed one sample. `at` is an absolute monotonic time (systemUptime);
    /// the recorder normalizes it to seconds-since-start internally.
    /// Safe to call from any thread.
    func ingest(value: Double, at monotonicTime: Double) {
        recordQueue.async { [weak self] in
            guard let self, self.isActive else { return }
            let t = monotonicTime - self.startMonotonic
            self.buffer.append(TimestampedSample(t: t, value: value))
            self.samplesSinceLastAnalysis += 1

            let shouldStop: Bool

            switch self.stopCondition.mode {
            case .duration:
                shouldStop = t >= self.stopCondition.targetDuration
            case .repetitions:
                // Throttle the analyzer to every N samples to avoid O(n²) cost.
                if self.samplesSinceLastAnalysis >= Self.analysisInterval {
                    self.samplesSinceLastAnalysis = 0
                    self.currentCycles = self.analyzer.analyze(self.buffer).cycleCount
                }
                shouldStop = self.currentCycles >= self.stopCondition.targetReps
                    || t >= Self.repetitionsSafetyTimeoutSec
            }

            let capturedElapsed = t
            let capturedCycles = self.currentCycles
            DispatchQueue.main.async {
                self.elapsed = capturedElapsed
                if capturedCycles != self.liveCycleCount {
                    self.liveCycleCount = capturedCycles
                }
            }
            if shouldStop { self._finish() }
        }
    }

    /// Stop early / manually (e.g. user taps "Stop").
    func finish() {
        recordQueue.async { [weak self] in self?._finish() }
    }

    /// Must be called on recordQueue.
    private func _finish() {
        guard isActive else { return }
        isActive = false
        let metrics = analyzer.analyze(buffer)
        let trial = Trial(
            taskType: taskType,
            side: side,
            source: source,
            stopCondition: stopCondition,
            startedAt: startWallClock ?? Date(),
            startUptime: startMonotonic,
            samples: buffer,
            metrics: metrics
        )
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.onComplete?(trial)
        }
    }
}
