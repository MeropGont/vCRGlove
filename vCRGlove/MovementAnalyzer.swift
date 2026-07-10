//
//  MovementAnalyzer.swift
//  vCRGlove
//
//  Turns a 1-D movement signal into MovementMetrics.
//  Completely sensor-independent and side-effect free — fully testable in the
//  Simulator (or unit tests) against synthetic signals, no hardware required.
//
//  Pipeline:  smooth → detect peaks/troughs → segment into cycles →
//             per-cycle amplitude & duration → aggregate metrics.
//

import Foundation

struct MovementAnalyzer {

    // Tunable parameters (sensible defaults; expose later if needed).
    struct Config {
        /// Moving-average smoothing length in seconds. Converted to a sample
        /// window using the signal's actual sample rate, so 30 fps camera and
        /// 60 Hz synthetic data are smoothed equally in the time domain.
        var smoothingSec: Double = 0.07
        /// Hysteresis thresholds as fractions of the robust dynamic range
        /// (5th–95th percentile). A cycle is counted only when the signal
        /// rises above `highFraction` after having been below `lowFraction`
        /// (Schmitt trigger) — plateau wobble and occlusion noise can never
        /// double-count, unlike pure peak prominence. The band sits in the
        /// lower part of the range so cycles with decremented amplitude
        /// (sequence effect) still traverse it and are counted.
        var lowFraction: Double  = 0.25
        var highFraction: Double = 0.45
        /// Minimum spacing between successive cycles, in seconds
        /// (guards against double-counting jitter). ~ max plausible 8 Hz.
        var minPeakSpacingSec: Double = 0.12
        /// An inter-cycle gap longer than this factor × median gap counts
        /// as a pause ("freezing").
        var pauseFactor: Double = 2.0
        static let `default` = Config()
    }

    var config: Config = .default

    // MARK: - Public entry point

    func analyze(_ samples: [TimestampedSample]) -> MovementMetrics {
        guard samples.count >= 4 else { return .empty }

        let times = samples.map { $0.t }
        let raw   = samples.map { $0.value }

        // Convert time-domain smoothing to a sample window via the mean dt.
        let span = times.last! - times.first!
        let meanDt = span > 0 ? span / Double(samples.count - 1) : 0
        let window = meanDt > 0
            ? max(3, Int((config.smoothingSec / meanDt).rounded()))
            : 5
        let signal = smooth(raw, window: window)

        // Cycle events via hysteresis: index of each low→high traversal.
        let events = hysteresisCycleIndices(signal, times: times)
        guard events.count >= 2 else {
            // Not enough cycles to say anything meaningful.
            return MovementMetrics(
                cycleCount: events.count,
                frequencyHz: 0, meanAmplitude: 0, amplitudeDecrementSlope: 0,
                rhythmCV: 0, pauseCount: 0,
                onsetLatencySec: events.first.map { times[$0] - times.first! } ?? 0,
                qualityIndex: 0
            )
        }

        // Per-cycle amplitude: max−min of the signal within each cycle segment.
        let amplitudes = segmentAmplitudes(signal, eventIndices: events)

        // Cycle durations = time between successive cycle events.
        var durations: [Double] = []
        for i in 1..<events.count { durations.append(times[events[i]] - times[events[i-1]]) }

        // One event = one executed movement (a tap, an open/close, a rotation).
        let cycleCount = events.count
        // Frequency uses the intervals BETWEEN events (count - 1 over the span).
        let totalTime  = times[events.last!] - times[events.first!]
        let frequency  = totalTime > 0 ? Double(events.count - 1) / totalTime : 0

        let meanAmp = amplitudes.isEmpty ? 0 : amplitudes.reduce(0,+) / Double(amplitudes.count)

        // Decrement: slope of amplitude vs cycle index, normalized by mean amplitude
        // so it is comparable across recordings/scales. Negative = fatiguing.
        let slope = linearSlope(y: amplitudes)
        let normSlope = meanAmp > 0 ? slope / meanAmp : 0

        // Rhythm: coefficient of variation of cycle durations.
        let cv = coefficientOfVariation(durations)

        // Pauses: inter-peak intervals much longer than the median.
        let pauses = countPauses(durations, factor: config.pauseFactor)

        // Onset latency: time from recording start to first detected cycle.
        let onset = times[events.first!] - times.first!

        let quality = qualityIndex(frequency: frequency,
                                   rhythmCV: cv,
                                   normSlope: normSlope,
                                   pauseCount: pauses)

        return MovementMetrics(
            cycleCount: cycleCount,
            frequencyHz: frequency,
            meanAmplitude: meanAmp,
            amplitudeDecrementSlope: normSlope,
            rhythmCV: cv,
            pauseCount: pauses,
            onsetLatencySec: max(onset, 0),
            qualityIndex: quality
        )
    }

    // MARK: - Signal processing helpers

    private func smooth(_ x: [Double], window: Int) -> [Double] {
        guard window > 1, x.count > window else { return x }
        let half = window / 2
        var out = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let lo = max(0, i - half)
            let hi = min(x.count - 1, i + half)
            var sum = 0.0
            for j in lo...hi { sum += x[j] }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    /// Hysteresis (Schmitt-trigger) cycle detection: returns the sample index
    /// of each low→high traversal. Thresholds derive from the robust dynamic
    /// range (5th–95th percentile), so single outlier frames (Vision
    /// mis-detections) cannot skew them. A cycle is only counted after the
    /// signal has dropped below the LOW threshold and then risen above the
    /// HIGH threshold — wobble on an open/closed plateau can never
    /// double-count because it does not traverse the full band.
    private func hysteresisCycleIndices(_ s: [Double], times: [Double]) -> [Int] {
        guard s.count >= 3 else { return [] }
        let sorted = s.sorted()
        let lo = sorted[Int(Double(sorted.count - 1) * 0.05)]
        let hi = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let range = hi - lo
        guard range > 1e-9 else { return [] }   // flat signal → no cycles

        let lowTh  = lo + range * config.lowFraction
        let highTh = lo + range * config.highFraction

        var events: [Int] = []
        var armed = false          // true once the signal has been below lowTh
        var lastEventTime = -Double.infinity
        for i in 0..<s.count {
            if s[i] < lowTh {
                armed = true
            } else if armed && s[i] > highTh {
                if times[i] - lastEventTime >= config.minPeakSpacingSec {
                    events.append(i)
                    lastEventTime = times[i]
                }
                armed = false
            }
        }
        return events
    }

    /// Per-cycle amplitude: max − min of the signal within each segment
    /// between successive cycle events (last segment runs to the signal end).
    private func segmentAmplitudes(_ s: [Double], eventIndices: [Int]) -> [Double] {
        guard !eventIndices.isEmpty else { return [] }
        var amps: [Double] = []
        for (k, start) in eventIndices.enumerated() {
            let end = k + 1 < eventIndices.count ? eventIndices[k + 1] : s.count - 1
            guard end > start else { continue }
            let segment = s[start...end]
            amps.append((segment.max() ?? 0) - (segment.min() ?? 0))
        }
        return amps
    }

    // MARK: - Statistics

    /// Slope of y over its index (x = 0,1,2,...), via least squares.
    private func linearSlope(y: [Double]) -> Double {
        let n = Double(y.count)
        guard n >= 2 else { return 0 }
        let xs = (0..<y.count).map(Double.init)
        let meanX = xs.reduce(0,+) / n
        let meanY = y.reduce(0,+) / n
        var num = 0.0, den = 0.0
        for i in 0..<y.count {
            num += (xs[i] - meanX) * (y[i] - meanY)
            den += (xs[i] - meanX) * (xs[i] - meanX)
        }
        return den == 0 ? 0 : num / den
    }

    private func coefficientOfVariation(_ x: [Double]) -> Double {
        guard x.count >= 2 else { return 0 }
        let mean = x.reduce(0,+) / Double(x.count)
        guard mean != 0 else { return 0 }
        let variance = x.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(x.count)
        return sqrt(variance) / mean
    }

    private func countPauses(_ durations: [Double], factor: Double) -> Int {
        guard durations.count >= 2 else { return 0 }
        let sorted = durations.sorted()
        let median = sorted[sorted.count / 2]
        guard median > 0 else { return 0 }
        return durations.filter { $0 > median * factor }.count
    }

    /// Heuristic 0...1 index for UI trends only (NOT a validated UPDRS score).
    private func qualityIndex(frequency: Double, rhythmCV: Double,
                              normSlope: Double, pauseCount: Int) -> Double {
        // Each term in 0...1, higher = better; simple weighted average.
        let speedTerm   = min(frequency / 5.0, 1.0)                 // ~5 Hz ≈ healthy fast tapping
        let rhythmTerm  = max(0, 1 - min(rhythmCV, 1.0))            // steadier = better
        let decrTerm    = max(0, 1 - min(abs(normSlope) * 5, 1.0))  // less decrement = better
        let pauseTerm   = max(0, 1 - Double(pauseCount) * 0.25)     // fewer pauses = better
        return (speedTerm + rhythmTerm + decrTerm + pauseTerm) / 4.0
    }
}
