//
//  SyntheticSignalGenerator.swift
//  vCRGlove
//
//  Generates fake movement signals so the whole analysis + storage + UI stack
//  can be developed and tested in the Simulator with NO camera/watch/glove.
//
//  Model: a decaying sinusoid (open/close cycles) with optional rhythm jitter,
//  noise, onset delay, and injected pauses ("freezing").
//

import Foundation

struct SyntheticSignalGenerator {

    struct Params {
        var durationSec: Double   = 8.0
        var sampleRateHz: Double  = 60.0    // camera-like
        var frequencyHz: Double   = 3.0     // cycles per second
        var baseAmplitude: Double = 1.0
        /// Fraction of amplitude lost per second (0 = none). Models decrement.
        var decrementPerSec: Double = 0.05
        var noiseSD: Double       = 0.02
        var onsetDelaySec: Double = 0.3
        /// Rhythm jitter as a fraction of the period (0 = perfectly regular).
        var jitterFraction: Double = 0.0
        /// Times (sec) at which to inject a ~0.6 s pause. Empty = none.
        var pauseAtSec: [Double]  = []

        static let healthy = Params(frequencyHz: 4.5, decrementPerSec: 0.01,
                                    noiseSD: 0.015, jitterFraction: 0.03)
        static let parkinsonian = Params(frequencyHz: 2.2, decrementPerSec: 0.12,
                                         noiseSD: 0.04, jitterFraction: 0.18,
                                         pauseAtSec: [3.5])
    }

    var params: Params = Params()
    private var rng: SeededGenerator

    init(params: Params = Params(), seed: UInt64 = 42) {
        self.params = params
        self.rng = SeededGenerator(seed: seed)
    }

    mutating func generate() -> [TimestampedSample] {
        let dt = 1.0 / params.sampleRateHz
        let n = Int(params.durationSec * params.sampleRateHz)
        var out: [TimestampedSample] = []
        out.reserveCapacity(n)

        var phase = 0.0
        var lastValue = 0.0
        for i in 0..<n {
            let t = Double(i) * dt

            // Before onset: essentially flat (hand at rest).
            if t < params.onsetDelaySec {
                out.append(TimestampedSample(t: t, value: gaussianNoise() * params.noiseSD))
                continue
            }

            // Inside an injected pause: freeze at the LAST value, advance no
            // phase — real freezing holds the hand wherever it stopped
            // (a jump to an arbitrary level would itself look like movement).
            if isInPause(t) {
                out.append(TimestampedSample(t: t, value: lastValue + gaussianNoise() * params.noiseSD))
                continue
            }

            // Instantaneous frequency with optional jitter.
            let jitter = 1.0 + params.jitterFraction * (gaussianNoise())
            let f = max(0.2, params.frequencyHz * jitter)
            phase += 2 * Double.pi * f * dt

            // Amplitude decays over active time (decrement / sequence effect).
            let activeTime = t - params.onsetDelaySec
            let amp = max(0, params.baseAmplitude * (1 - params.decrementPerSec * activeTime))

            // Half-rectified so the signal looks like a distance (>= 0), like
            // thumb–index distance or fingertip-to-palm distance.
            let raw = amp * (0.5 - 0.5 * cos(phase))
            lastValue = raw
            let value = raw + gaussianNoise() * params.noiseSD
            out.append(TimestampedSample(t: t, value: value))
        }
        return out
    }

    private func isInPause(_ t: Double) -> Bool {
        for p in params.pauseAtSec where t >= p && t < p + 0.6 { return true }
        return false
    }

    private mutating func gaussianNoise() -> Double {
        // Box–Muller.
        let u1 = max(rng.nextUnit(), 1e-9)
        let u2 = rng.nextUnit()
        return sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
    }
}

/// Tiny reproducible PRNG so tests are deterministic.
struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        return state &* 0x2545F4914F6CDD1D
    }
    /// Uniform in [0,1).
    mutating func nextUnit() -> Double {
        Double(next() >> 11) * (1.0 / 9007199254740992.0)
    }
}
