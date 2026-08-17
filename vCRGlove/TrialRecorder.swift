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
    #if targetEnvironment(simulator)
    static let repetitionsSafetyTimeoutSec: Double = 5
    #else
    static let repetitionsSafetyTimeoutSec: Double = 30
    #endif

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
    /// Re-run the cycle-count analyzer every N samples (30 fps → ~1 Hz updates).
    /// Lower frequency keeps the serial recordQueue responsive so _finish() can
    /// start immediately when the stop condition is met.
    private static let analysisInterval = 30

    /// Serial queue that owns all mutable state; `ingest` is safe to call from any thread.
    private let recordQueue = DispatchQueue(label: "vcr.trialrecorder", qos: .userInitiated)

    /// Fires every 0.5 s to enforce the duration / safety timeout even when no samples
    /// are arriving (e.g. the camera or watch feed stalls).
    private var durationTimer: DispatchSourceTimer?

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
            self.startDurationTimer()
            DispatchQueue.main.async {
                self.liveCycleCount = 0
                self.elapsed = 0
                self.isRecording = true
            }
        }
    }

    private func startDurationTimer() {
        durationTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: recordQueue)
        timer.schedule(deadline: .now() + .milliseconds(500), repeating: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            guard let self, self.isActive else { return }
            let elapsed = ProcessInfo.processInfo.systemUptime - self.startMonotonic
            DispatchQueue.main.async {
                self.elapsed = elapsed
            }
            switch self.stopCondition.mode {
            case .duration:
                if elapsed >= self.stopCondition.targetDuration {
                    self._finish()
                }
            case .repetitions:
                if elapsed >= Self.repetitionsSafetyTimeoutSec {
                    EventStore.shared.append(
                        type: "PERF", tag: "safety_timeout",
                        message: String(format: "Repetition safety timeout hit after %.1f s", elapsed),
                        details: ["duration": String(format: "%.1f", elapsed)])
                    self._finish()
                }
            }
        }
        timer.resume()
        durationTimer = timer
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
                if self.currentCycles >= self.stopCondition.targetReps {
                    shouldStop = true
                } else if t >= Self.repetitionsSafetyTimeoutSec {
                    EventStore.shared.append(
                        type: "PERF", tag: "safety_timeout",
                        message: String(format: "Repetition safety timeout hit after %.1f s", t),
                        details: ["duration": String(format: "%.1f", t)])
                    shouldStop = true
                } else {
                    shouldStop = false
                }
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
        print("[PERF] finish() called from main")
        recordQueue.async { [weak self] in self?._finish() }
    }

    /// Must be called on recordQueue.
    private func _finish() {
        guard isActive else { return }
        isActive = false
        durationTimer?.cancel()
        durationTimer = nil

        let finishStart = CFAbsoluteTimeGetCurrent()
        print("[PERF] _finish() started, buffer samples: \(buffer.count)")
        EventStore.shared.append(
            type: "PERF", tag: "finish_start",
            message: "_finish() started",
            details: ["buffer_samples": "\(buffer.count)"])

        // Snapshot everything the analysis needs.
        let snapshotBuffer    = buffer
        let snapshotTaskType  = taskType
        let snapshotSide      = side
        let snapshotSource    = source
        let snapshotStop      = stopCondition
        let snapshotStart     = startWallClock ?? Date()
        let snapshotUptime    = startMonotonic

        // Tell the UI the recording is over right now — no waiting for analysis.
        Task { @MainActor [weak self] in
            self?.isRecording = false
        }

        // Run analysis off the serial recordQueue so the recorder stays responsive
        // (e.g. Stop button / next start) even if the buffer is large.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let analysisStart = CFAbsoluteTimeGetCurrent()
            let metrics = self.analyzer.analyze(snapshotBuffer)
            let analysisElapsed = CFAbsoluteTimeGetCurrent() - analysisStart

            let trial = Trial(
                taskType:      snapshotTaskType,
                side:          snapshotSide,
                source:        snapshotSource,
                stopCondition: snapshotStop,
                startedAt:     snapshotStart,
                startUptime:   snapshotUptime,
                samples:       snapshotBuffer,
                metrics:       metrics
            )

            print("[PERF] analyzed \(snapshotBuffer.count) samples in \(String(format: "%.3f", analysisElapsed)) s")
            EventStore.shared.append(
                type: "PERF", tag: "analysis_timed",
                message: String(format: "Analyzed %d samples in %.3f s", snapshotBuffer.count, analysisElapsed),
                details: ["samples": "\(snapshotBuffer.count)",
                          "seconds": String(format: "%.3f", analysisElapsed)])

            let finishElapsed = CFAbsoluteTimeGetCurrent() - finishStart
            print("[PERF] _finish() completed in \(String(format: "%.3f", finishElapsed)) s")
            EventStore.shared.append(
                type: "PERF", tag: "finish_complete",
                message: String(format: "_finish() completed in %.3f s", finishElapsed),
                details: ["seconds": String(format: "%.3f", finishElapsed)])

            DispatchQueue.main.async { [weak self] in
                self?.onComplete?(trial)
            }
        }
    }
}
