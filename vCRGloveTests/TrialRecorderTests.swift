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

struct TrialRecorderTests {

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
        #expect(trial.samples.last!.t >= 15)
        #expect(trial.samples.last!.t < 16)
    }
}
