//
//  SyntheticCaptureSource.swift
//  vCRGlove
//
//  Replays a pre-generated synthetic movement signal into a TrialRecorder in
//  real time, exactly like a camera or watch capture source would — so the
//  whole recording flow (UI, recorder, analyzer, store) is testable in the
//  Simulator with no hardware. Tasks B/C swap this out for Vision / CoreMotion.
//

import Foundation

final class SyntheticCaptureSource {

    enum Preset: String, CaseIterable, Identifiable {
        case healthy, parkinsonian
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .healthy:       return "Healthy-like"
            case .parkinsonian:  return "Parkinsonian-like"
            }
        }
        var params: SyntheticSignalGenerator.Params {
            switch self {
            case .healthy:       return .healthy
            case .parkinsonian:  return .parkinsonian
            }
        }
    }

    private var timer: Timer?
    private var samples: [TimestampedSample] = []
    private var index = 0
    private weak var recorder: TrialRecorder?

    /// Pre-generates a signal long enough for any stop condition and starts
    /// feeding it to the recorder at the signal's sample rate.
    func start(preset: Preset, feeding recorder: TrialRecorder, seed: UInt64 = .random(in: 0...UInt64.max)) {
        stop()
        var params = preset.params
        params.durationSec = 60   // plenty for 10 reps or any duration mode
        var generator = SyntheticSignalGenerator(params: params, seed: seed)
        samples = generator.generate()
        index = 0
        self.recorder = recorder

        let interval = 1.0 / params.sampleRateHz
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let recorder, recorder.isRecording, index < samples.count else {
            stop()
            return
        }
        let sample = samples[index]
        index += 1
        recorder.ingest(value: sample.value, at: ProcessInfo.processInfo.systemUptime)
    }
}
