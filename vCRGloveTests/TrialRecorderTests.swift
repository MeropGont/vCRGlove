//
//  TrialRecorderTests.swift
//  vCRGloveTests
//
//  Covers the TrialRecorder stop logic — in particular the safety timeout in
//  .repetitions mode: a signal whose amplitude decrements to zero (severe
//  bradykinesia) never reaches 10 countable cycles and must not hang forever.
//

import Testing
import Foundation
@testable import vCRGlove
// Watch transport tests use an in-memory counterpart, not paired hardware.

@MainActor
private final class MockWatchMotionTransport: WatchMotionTransport {
    struct Attempt {
        let id: UUID
        let batch: ([[Double]]) -> Void
        let failure: () -> Void
    }
    var isWatchReachable = true
    var attempts: [Attempt] = []
    var stopped: [UUID] = []
    func startMotionStream(id: UUID, onBatch: @escaping ([[Double]]) -> Void, onFailure: @escaping () -> Void) {
        attempts.append(Attempt(id: id, batch: onBatch, failure: onFailure))
    }
    func stopMotionStream(id: UUID) { stopped.append(id) }
}

struct WatchStreamReliabilityTests {
    private func message(id: UUID, sequence: Int, samples: [[Double]]) -> [String: Any] {
        var value = WatchStreamProtocol.command("motionBatch", id: id)
        value["sequence"] = sequence
        value["samples"] = samples
        return value
    }

    @Test func packetsRejectWrongTrialsDuplicatesAndMalformedSamples() {
        let id = UUID()
        var cursor = WatchStreamBatchCursor(id: id)
        #expect(cursor.accept(message(id: UUID(), sequence: 0, samples: [[1, 2]])) == nil)
        #expect(cursor.accept(["type": "motionBatch", "samples": [[1.0, 2.0]]]) == nil)
        for invalid in [[], [[]], [[1]], [[1, .nan]], [[.infinity, 1]], [[2, 1], [1, 2]]] as [[[Double]]] {
            #expect(cursor.accept(message(id: id, sequence: 0, samples: invalid)) == nil)
        }
        #expect(cursor.accept(message(id: id, sequence: 0, samples: [[1, 2], [1.02, 3]])) != nil)
        #expect(cursor.accept(message(id: id, sequence: 0, samples: [[1.04, 4]])) == nil)
        #expect(cursor.accept(message(id: id, sequence: 1, samples: [[1, 2]])) == nil)
        // Lost packets may leave a real timestamp gap; never invent replacements.
        #expect(cursor.accept(message(id: id, sequence: 3, samples: [[3, 4]])) != nil)
        #expect(cursor.lastTimestamp == 3)
    }

    @Test func delayedStopsAndCancelledStartsCannotAffectTheNextTrial() {
        var gate = WatchStreamCommandGate()
        let old = UUID(), current = UUID()
        gate.end(old)
        #expect(gate.start(old) == false)
        #expect(gate.start(current) == true)
        #expect(gate.start(current) == true)
        #expect(gate.start(UUID()) == false)
        #expect(gate.end(old) == false)
        #expect(gate.activeID == current)
        #expect(gate.end(current) == true)
        #expect(gate.start(current) == false)
    }

    @Test @MainActor func captureWaitsForValidSamplesAndPreservesWatchSpacing() {
        let transport = MockWatchMotionTransport()
        var time = 500.0
        let capture = WatchMotionCapture(transport: transport, now: { time })
        var successes = 0
        var received: [(Double, Double)] = []
        capture.onSample = { received.append(($0, $1)) }
        capture.start { if case .success = $0 { successes += 1 } }
        transport.attempts[0].batch([[]])
        #expect(successes == 0 && !capture.isReceiving)
        transport.attempts[0].batch([[1000, 2], [1000.02, 3]])
        #expect(successes == 1 && capture.isReceiving)
        #expect(abs(received[0].1 - 499.98) < 0.00001)
        #expect(received[1].1 == 500)
        time = 510
        transport.attempts[0].batch([[1010.02, 4]])
        #expect(abs(received[2].1 - 510) < 0.00001)
        #expect(successes == 1)
        capture.stop()
    }

    @Test @MainActor func stoppingOrRestartingIgnoresLateSamplesAndFailures() {
        let transport = MockWatchMotionTransport()
        let capture = WatchMotionCapture(transport: transport)
        var completions = 0, samples = 0
        capture.onSample = { _, _ in samples += 1 }
        capture.start { _ in completions += 1 }
        capture.stop()
        capture.start { _ in completions += 1 }
        transport.attempts[0].batch([[1, 2]])
        transport.attempts[0].failure()
        #expect(completions == 0 && samples == 0)
        transport.attempts[1].batch([[2, 3]])
        #expect(completions == 1 && samples == 1)
        capture.stop()
        transport.attempts[1].batch([[3, 4]])
        #expect(samples == 1)
        #expect(Set(transport.stopped) == Set(transport.attempts.map(\.id)))
    }

    @Test @MainActor func stoppingDuringBatchPreventsRemainingCallbacks() {
        let transport = MockWatchMotionTransport()
        let capture = WatchMotionCapture(transport: transport)
        var count = 0
        capture.onSample = { _, _ in count += 1; capture.stop() }
        capture.start { _ in }
        transport.attempts[0].batch([[1, 2], [1.02, 3]])
        #expect(count == 1)
        capture.onSample = nil
    }

    @Test @MainActor func unreachableOrRejectedStartsFailWithoutCreatingARecording() {
        let transport = MockWatchMotionTransport()
        transport.isWatchReachable = false
        let capture = WatchMotionCapture(transport: transport)
        var failures = 0
        capture.start { if case .failure = $0 { failures += 1 } }
        #expect(failures == 1 && transport.attempts.isEmpty)
        transport.isWatchReachable = true
        capture.start { if case .failure = $0 { failures += 1 } }
        transport.attempts[0].failure()
        transport.attempts[0].batch([[1, 2]])
        #expect(failures == 2 && !capture.isReceiving)
    }

    @Test @MainActor func startupDeadlineFailsOnceAndStopsItsOwnStream() async throws {
        let transport = MockWatchMotionTransport()
        let capture = WatchMotionCapture(transport: transport, startupTimeout: 0.02)
        var failures = 0
        capture.start { if case .failure(.startTimedOut) = $0 { failures += 1 } }
        for _ in 0..<100 where failures == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(failures == 1)
        #expect(transport.stopped == [transport.attempts[0].id])
        transport.attempts[0].batch([[1, 2]])
        #expect(failures == 1 && !capture.isReceiving)
    }
}

struct TrialRecorderTests {
    @Test @MainActor func routineGateTracksTheRecorderThroughItsCompletionCallback() async throws {
        let recorder = TrialRecorder(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec)
        var completed = false
        recorder.onComplete = { _ in
            #expect(RoutineRecordingActivity.shared.activeIDs.contains(recorder.routineActivityID))
            completed = true
        }
        recorder.start()
        for _ in 0..<200 where !recorder.isRecording { try await Task.sleep(for: .milliseconds(10)) }
        #expect(RoutineRecordingActivity.shared.activeIDs.contains(recorder.routineActivityID))
        recorder.finish()
        for _ in 0..<200 where !completed { try await Task.sleep(for: .milliseconds(10)) }
        #expect(completed)
        #expect(!RoutineRecordingActivity.shared.activeIDs.contains(recorder.routineActivityID))
        recorder.onComplete = nil
    }

    @Test @MainActor func cameraUsesGapAwarenessButWatchKeepsExistingAnalysis() async throws {
        for source in [SignalSource.camera, .watchMotion] {
            let trial = try await cameraTrial(source: source) { recorder, start in
                for i in 0..<300 where !(90..<180).contains(i) {
                    recorder.ingest(value: 1 + sin(Double(i) * 2 * .pi * 4 / 30),
                                    at: start + 0.05 + Double(i) / 30)
                }
            }
            let expected = MovementAnalyzer(config: source == .camera ? .camera : .default).analyze(trial.samples)
            #expect(trial.metrics == expected)
            #expect(source == .camera ? trial.metrics.pauseCount == 0 : trial.metrics.pauseCount > 0)
        }
    }

    @MainActor private func cameraTrial(task: MovementTaskType = .fingerTap, source: SignalSource = .camera,
                                       enabled: Bool = true,
                                       feed: (TrialRecorder, Double) -> Void) async throws -> Trial {
        let recorder = TrialRecorder(taskType: task, side: .right, source: source,
            stopCondition: .thirtySec, measurementVersion: MovementMeasurementVersion.camera,
            recordsFingerTappingAngles: enabled)
        var trials: [Trial] = []
        recorder.onComplete = { trials.append($0) }
        recorder.start()
        for _ in 0..<200 where !recorder.isRecording { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.isRecording)
        feed(recorder, ProcessInfo.processInfo.systemUptime)
        recorder.finish()
        recorder.finish()
        for _ in 0..<200 where trials.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(trials.count == 1)
        return try #require(trials.first)
    }

    @Test @MainActor func cameraAnglesAlignWithDistanceAndDoNotChangeMetrics() async throws {
        let trial = try await cameraTrial { recorder, start in
            for i in 0..<90 {
                let value = sin(Double(i) * 2 * .pi / 10) + 1
                recorder.ingestCameraFrame(.init(value: value, fingerTappingAngleDegrees: Double(i)),
                                           at: start + 0.05 + Double(i) / 30)
            }
        }
        let recording = try #require(trial.fingerTappingAngle)
        #expect(recording.samples.count == 90 && trial.samples.count == 90)
        #expect(recording.samples.map(\.t) == trial.samples.map(\.t))
        #expect(recording.samples.last?.degrees == 89)
        #expect(recording.unit == "degrees" && recording.timeReference == "seconds_since_trial_start")
        #expect(recording.measurementVersion == FingerTappingAngleRecording.currentVersion)
        #expect(trial.measurementVersion == MovementMeasurementVersion.camera)
        #expect(trial.metrics == MovementAnalyzer(config: .camera).analyze(trial.samples))
        #expect(trial.fingerTappingAngleMetrics == FingerTappingAngleAnalyzer.analyze(recording))
        #expect(trial.fingerTappingAngleMetrics?.calculationVersion == FingerTappingAngleMetrics.currentVersion)
        #expect(trial.fingerTappingReferenceSegment == nil)
    }

    @Test @MainActor func cameraTrialPersistsFirstTenTapWindowAlongsideFullSignal() async throws {
        let trial = try await cameraTrial { recorder, start in
            for i in 0..<400 {
                let time = Double(i) / 60
                recorder.ingestCameraFrame(.init(value: 1 + sin(4 * .pi * time),
                    fingerTappingAngleDegrees: 20 - 20 * cos(4 * .pi * time)), at: start + 0.05 + time)
            }
        }
        let segment = try #require(trial.fingerTappingReferenceSegment)
        #expect(segment.completedTapCount == 10)
        #expect(segment.endSampleIndexExclusive < trial.fingerTappingAngle!.samples.count)
        #expect(trial.fingerTappingAngle?.samples.count == 400)
        #expect(trial.samples.count == 400)
        #expect(trial.metrics == MovementAnalyzer(config: .camera).analyze(trial.samples))
    }

    @Test @MainActor func missingAndInvalidAnglesAreNotZeroAndDoNotDropDistance() async throws {
        let trial = try await cameraTrial { recorder, start in
            let angles: [Double?] = [0, nil, .nan, .infinity, -1, 181, 180]
            for (i, angle) in angles.enumerated() {
                recorder.ingestCameraFrame(.init(value: Double(i), fingerTappingAngleDegrees: angle),
                                           at: start + 0.05 + Double(i) / 30)
            }
            recorder.ingestCameraFrame(.init(value: nil, fingerTappingAngleDegrees: 45), at: start + 0.4)
            recorder.ingestCameraFrame(.init(value: nil, fingerTappingAngleDegrees: nil), at: start + 0.5)
        }
        let angles = try #require(trial.fingerTappingAngle).samples
        #expect(trial.samples.map(\.value) == [0, 1, 2, 3, 4, 5, 6])
        #expect(angles.map(\.degrees) == [0, nil, nil, nil, nil, nil, 180, 45, nil])
        #expect(trial.metrics == MovementAnalyzer(config: .camera).analyze(trial.samples))
    }

    @Test @MainActor func cameraFramesOutsideRecordingAndAfterStopAreExcluded() async throws {
        let trial = try await cameraTrial { recorder, start in
            recorder.ingestCameraFrame(.init(value: 99, fingerTappingAngleDegrees: 99), at: start - 10)
            recorder.ingestCameraFrame(.init(value: 99, fingerTappingAngleDegrees: 99), at: .nan)
            recorder.ingestCameraFrame(.init(value: 1, fingerTappingAngleDegrees: 30), at: start + 0.05)
            recorder.ingestCameraFrame(.init(value: 2, fingerTappingAngleDegrees: 60), at: start + 29.9)
            recorder.ingestCameraFrame(.init(value: 99, fingerTappingAngleDegrees: 99), at: start + 31)
            recorder.ingestCameraFrame(.init(value: 99, fingerTappingAngleDegrees: 99), at: start + 32)
        }
        #expect(trial.samples.map(\.value) == [1, 2])
        let angles = try #require(trial.fingerTappingAngle).samples
        #expect(angles.map(\.degrees) == [30, 60])
        #expect(angles.map(\.t) == trial.samples.map(\.t))
        #expect(angles.allSatisfy { $0.t >= 0 && $0.t <= 30 })
    }

    @Test @MainActor func angleOnlyRecordingStillCompletesAndLegacyAndOtherSourcesStayUnchanged() async throws {
        let empty = try await cameraTrial { _, _ in }
        #expect(empty.samples.isEmpty && empty.fingerTappingAngle?.samples.isEmpty == true)
        let angleOnly = try await cameraTrial { recorder, start in
            recorder.ingestCameraFrame(.init(value: nil, fingerTappingAngleDegrees: 45), at: start + 0.05)
        }
        #expect(angleOnly.samples.isEmpty && angleOnly.metrics == .empty)
        #expect(angleOnly.fingerTappingAngle?.samples.map(\.degrees) == [45])
        for (task, source, enabled) in [
            (MovementTaskType.fingerTap, SignalSource.camera, false),
            (.handOpenClose, .camera, true), (.pronationSupination, .watchMotion, true),
            (.fingerTap, .synthetic, true)
        ] {
            let trial = try await cameraTrial(task: task, source: source, enabled: enabled) { recorder, start in
                recorder.ingestCameraFrame(.init(value: 1, fingerTappingAngleDegrees: 90), at: start + 0.05)
            }
            #expect(trial.fingerTappingAngle == nil && trial.samples.count == 1)
            #expect(trial.fingerTappingAngleMetrics == nil)
        }
    }

    @Test @MainActor func manualStopRejectsLateCameraFrames() async throws {
        let trial = try await cameraTrial { recorder, start in
            recorder.ingestCameraFrame(.init(value: 1, fingerTappingAngleDegrees: 30), at: start + 0.05)
            recorder.finish()
            recorder.ingestCameraFrame(.init(value: 9, fingerTappingAngleDegrees: 90), at: start + 0.1)
        }
        #expect(trial.samples.map(\.value) == [1])
        #expect(trial.fingerTappingAngle?.samples.map(\.degrees) == [30])
    }

    @Test @MainActor func restartingRecorderClearsAngleBufferAndKeepsCompletedSnapshot() async throws {
        let recorder = TrialRecorder(taskType: .fingerTap, side: .left, source: .camera,
                                     stopCondition: .thirtySec, recordsFingerTappingAngles: true)
        var trials: [Trial] = []
        recorder.onComplete = { trials.append($0) }
        for i in 0..<2 {
            recorder.start()
            for _ in 0..<200 where !recorder.isRecording { try await Task.sleep(for: .milliseconds(10)) }
            recorder.ingestCameraFrame(.init(value: Double(i), fingerTappingAngleDegrees: Double(i) * 90),
                                       at: ProcessInfo.processInfo.systemUptime + 0.05)
            recorder.finish()
            for _ in 0..<200 where trials.count <= i { try await Task.sleep(for: .milliseconds(10)) }
        }
        #expect(trials.count == 2)
        #expect(trials.first?.fingerTappingAngle?.samples.map(\.degrees) == [0])
        #expect(trials.last?.fingerTappingAngle?.samples.map(\.degrees) == [90])
    }

    @Test(arguments: [false, true])
    @MainActor func manualStopCompletesExactlyOnceIncludingEmptyRecording(withSample: Bool) async throws {
        let recorder = TrialRecorder(taskType: .fingerTap, side: .right, source: .camera,
                                     stopCondition: .thirtySec, measurementVersion: MovementMeasurementVersion.camera)
        var completed: [Trial] = []
        recorder.onComplete = { completed.append($0) }
        recorder.start()
        if withSample { recorder.ingest(value: 0.5, at: ProcessInfo.processInfo.systemUptime + 0.1) }
        recorder.finish()
        recorder.finish()
        for _ in 0..<200 where completed.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(completed.count == 1)
        let trial = try #require(completed.first)
        #expect(trial.samples.isEmpty == !withSample)
        #expect(trial.recordedDurationSeconds != nil)
        #expect(trial.measurementVersion == MovementMeasurementVersion.camera)
        #expect(trial.recordedDurationSeconds! < 30)
        #expect(!recorder.isRecording)
    }

    /// TrialRecorder is asynchronous (serial queue + main-thread callbacks):
    /// feed all samples up-front — samples after the stop condition are
    /// ignored — then await the onComplete callback.
    private final class CompletionBox: @unchecked Sendable {
        var trial: Trial?
    }

    private func awaitCompletion(_ box: CompletionBox,
                                 timeoutSec: Double = 10) async -> Trial? {
        let deadline = Date().addingTimeInterval(timeoutSec)
        while box.trial == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)   // 20 ms
        }
        return box.trial
    }

    @Test func repsModeFinishesViaSafetyTimeoutWhenTargetUnreachable() async throws {
        let recorder = TrialRecorder(taskType: .fingerTap,
                                     side: .right,
                                     source: .synthetic,
                                     stopCondition: .tenReps)
        let box = CompletionBox()
        recorder.onComplete = { box.trial = $0 }
        recorder.start()

        // Flat signal → zero countable cycles, target of 10 reps is unreachable.
        // Feed samples past the safety timeout (virtual timestamps).
        let t0 = ProcessInfo.processInfo.systemUptime
        var t = 0.0
        while t < TrialRecorder.repetitionsSafetyTimeoutSec + 5 {
            recorder.ingest(value: 0.5, at: t0 + t)
            t += 1.0 / 60.0
        }

        let trial = try #require(await awaitCompletion(box),
                                 "recorder must finish via safety timeout")
        #expect(trial.samples.last!.t >= TrialRecorder.repetitionsSafetyTimeoutSec)
        #expect(trial.metrics.cycleCount < 10)
    }

    @Test func repsModeFinishesAtTargetReps() async throws {
        let recorder = TrialRecorder(taskType: .fingerTap,
                                     side: .right,
                                     source: .synthetic,
                                     stopCondition: .tenReps)
        let box = CompletionBox()
        recorder.onComplete = { box.trial = $0 }
        recorder.start()

        // Healthy-like signal reaches 10 cycles well before the timeout.
        var gen = SyntheticSignalGenerator(params: .healthy, seed: 1)
        let t0 = ProcessInfo.processInfo.systemUptime
        for s in gen.generate() {
            recorder.ingest(value: s.value, at: t0 + s.t)
        }

        let trial = try #require(await awaitCompletion(box),
                                 "recorder must finish at target reps")
        #expect(trial.metrics.cycleCount >= 10)
        #expect(trial.samples.last!.t < TrialRecorder.repetitionsSafetyTimeoutSec)
    }

    @Test func durationModeFinishesAtTargetDuration() async throws {
        let recorder = TrialRecorder(taskType: .handOpenClose,
                                     side: .left,
                                     source: .synthetic,
                                     stopCondition: .fifteenSec)
        let box = CompletionBox()
        recorder.onComplete = { box.trial = $0 }
        recorder.start()

        let t0 = ProcessInfo.processInfo.systemUptime
        var t = 0.0
        while t < 20 {
            recorder.ingest(value: sin(t * 2 * .pi * 3), at: t0 + t)
            t += 1.0 / 60.0
        }

        let trial = try #require(await awaitCompletion(box))
        #expect(trial.samples.last!.t > 14.9)
        #expect(trial.samples.last!.t <= 15)
    }

    @Test(arguments: [false, true])
    @MainActor func durationDeadlineFinishesWithoutFurtherSamples(hadSignal: Bool) async throws {
        let target = 1.0
        let recorder = TrialRecorder(taskType: .fingerTap, side: .right, source: .camera,
                                     stopCondition: .init(mode: .duration, targetReps: 10,
                                                          targetDuration: target))
        let start = ProcessInfo.processInfo.systemUptime
        let trial: Trial = await withCheckedContinuation { continuation in
            recorder.onComplete = { continuation.resume(returning: $0) }
            recorder.start()
            if hadSignal {
                Task { @MainActor in
                    while !recorder.isRecording {
                        try? await Task.sleep(nanoseconds: 1_000_000)
                    }
                    recorder.ingest(value: 0.5, at: ProcessInfo.processInfo.systemUptime)
                }
            }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        #expect(elapsed >= target)
        #expect(elapsed < target + 2)
        #expect(trial.recordedDurationSeconds == target)
        #expect(trial.samples.allSatisfy { $0.t <= target })
        #expect(trial.samples.isEmpty == !hadSignal)
    }
}
