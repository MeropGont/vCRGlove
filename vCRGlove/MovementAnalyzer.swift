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

/// Timestamp-based descriptive angle analysis. Intentionally distinct from the
/// ROC-HCI offline kernel: no interpolation, nominal frame clock or ten-tap trim.
enum FingerTappingAngleAnalyzer {
    private static func validSegments(_ recording: FingerTappingAngleRecording) -> [[TimestampedAngleSample]]? {
        guard recording.measurementVersion == FingerTappingAngleRecording.currentVersion,
              recording.unit == "degrees", recording.timeReference == "seconds_since_trial_start" else {
            return nil
        }
        var segments: [[TimestampedAngleSample]] = []
        var segment: [TimestampedAngleSample] = []
        var lastTime: Double?
        for sample in recording.samples {
            guard sample.t.isFinite, sample.t >= 0, lastTime.map({ sample.t > $0 }) ?? true else { return nil }
            lastTime = sample.t
            guard let angle = sample.degrees, angle.isFinite, (0...180).contains(angle) else {
                if !segment.isEmpty { segments.append(segment); segment = [] }
                continue
            }
            if let previous = segment.last,
               sample.t - previous.t > 0.2 {
                segments.append(segment)
                segment = []
            }
            segment.append(sample)
        }
        if !segment.isEmpty { segments.append(segment) }
        return segments
    }

    static func analyze(_ recording: FingerTappingAngleRecording) -> FingerTappingAngleMetrics? {
        guard let segments = validSegments(recording) else { return nil }
        var trackedSeconds = 0.0
        var angularTravel = 0.0
        var periods: [Double] = []
        var openings: [Double] = []
        for samples in segments where samples.count >= 3 {
            for index in 1..<samples.count {
                trackedSeconds += samples[index].t - samples[index - 1].t
                angularTravel += abs(samples[index].degrees! - samples[index - 1].degrees!)
            }
            // Five-degree reversals suppress tiny jitter. A cycle additionally
            // needs a closure <=10 degrees and opening peaks >=150 ms apart.
            let peaks = openingPeaks(samples)
            var accepted = Set<Int>()
            for index in peaks.indices.dropFirst() {
                let left = peaks[index - 1]
                let right = peaks[index]
                let period = samples[right].t - samples[left].t
                let closure = samples[left...right].compactMap(\.degrees).min() ?? 180
                guard period >= 0.15, closure <= 10 else { continue }
                periods.append(period)
                accepted.insert(left)
                accepted.insert(right)
            }
            openings.append(contentsOf: accepted.sorted().map { samples[$0].degrees! })
        }
        let meanPeriod = periods.isEmpty ? 0 : periods.reduce(0, +) / Double(periods.count)
        let variance = periods.isEmpty ? 0 : periods.reduce(0) { $0 + pow($1 - meanPeriod, 2) } / Double(periods.count)
        let speed = trackedSeconds > 0 ? angularTravel / trackedSeconds : nil
        return FingerTappingAngleMetrics(
            calculationVersion: FingerTappingAngleMetrics.currentVersion,
            intervalCount: periods.count, openingPeakCount: openings.count,
            trackedSeconds: trackedSeconds,
            meanOpeningAngleDegrees: openings.isEmpty ? nil : openings.reduce(0, +) / Double(openings.count),
            meanAbsoluteAngularSpeedDegreesPerSecond: speed.flatMap { $0.isFinite ? $0 : nil },
            meanRateHz: periods.count >= 2 ? periods.map { 1 / $0 }.reduce(0, +) / Double(periods.count) : nil,
            periodCV: periods.count >= 2 && meanPeriod > 0 ? sqrt(variance) / meanPeriod : nil)
    }

    /// A source-index window only: no new score, reference limits or replacement metrics.
    static func firstTenTaps(_ recording: FingerTappingAngleRecording) -> FingerTappingReferenceSegment? {
        guard let samples = validSegments(recording)?.first, samples.count >= 3,
              let sourceStart = recording.samples.firstIndex(where: { $0.t == samples[0].t }) else { return nil }
        let peaks = openingPeaks(samples)
        var accepted: [Int] = []
        for index in peaks.indices.dropFirst() {
            let left = peaks[index - 1], right = peaks[index]
            let closed = (samples[left...right].compactMap(\.degrees).min() ?? 180) <= 10
            if samples[right].t - samples[left].t >= 0.15 && closed {
                if accepted.isEmpty { accepted.append(left) }
                accepted.append(right)
                if accepted.count == 11 {
                    let first = accepted[0]
                    return FingerTappingReferenceSegment(
                        selectionVersion: FingerTappingReferenceSegment.currentVersion,
                        sourceAngleVersion: recording.measurementVersion,
                        detectorVersion: FingerTappingAngleMetrics.currentVersion,
                        completedTapCount: 10,
                        firstSampleIndex: sourceStart + first,
                        endSampleIndexExclusive: sourceStart + right + 1,
                        startTrialTimeSeconds: samples[first].t,
                        endTrialTimeSeconds: samples[right].t,
                        openingPeakTimes: accepted.map { samples[$0].t })
                }
            } else if !accepted.isEmpty {
                // Do not restart later to obtain a cleaner/better-performing stretch.
                return nil
            }
        }
        return nil
    }

    private static func openingPeaks(_ samples: [TimestampedAngleSample]) -> [Int] {
        var peaks: [Int] = []
        var extremum = 0
        var rising = false
        for index in samples.indices.dropFirst() {
            let value = samples[index].degrees!
            let extreme = samples[extremum].degrees!
            if rising {
                if value > extreme { extremum = index }
                else if extreme - value >= 5 {
                    peaks.append(extremum)
                    rising = false
                    extremum = index
                }
            } else {
                if value < extreme { extremum = index }
                else if value - extreme >= 5 { rising = true; extremum = index }
            }
        }
        return peaks
    }
}

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
        /// as an observed pause, not a diagnosis of freezing.
        var pauseFactor: Double = 2.0
        /// Camera continuity tolerance (six nominal 30 fps frames), not a
        /// clinical threshold. Nil preserves the existing Watch analysis.
        var maximumSampleGap: Double? = nil
        /// Follow local extrema without normalizing the measured amplitudes.
        var detectsLocalExcursions = false
        static let `default` = Config()
        static let cameraGapAware = Config(maximumSampleGap: 0.2)
        static let camera = Config(maximumSampleGap: 0.2, detectsLocalExcursions: true)
    }

    var config: Config = .default

    // MARK: - Public entry point

    func analyze(_ samples: [TimestampedSample]) -> MovementMetrics {
        analyzeWithEvidence(samples).metrics
    }

    struct Analysis {
        let metrics: MovementMetrics
        let intervalCount: Int
        let amplitudeComparisonCount: Int
        let cycleEventTimes: [Double]
        static let empty = Analysis(metrics: .empty, intervalCount: 0, amplitudeComparisonCount: 0, cycleEventTimes: [])
    }

    func analyzeWithEvidence(_ samples: [TimestampedSample]) -> Analysis {
        guard samples.count >= 4,
              samples.allSatisfy({ $0.t.isFinite && $0.t >= 0 && $0.value.isFinite }),
              zip(samples, samples.dropFirst()).allSatisfy({ $0.t < $1.t }) else { return .empty }

        var segments: [[TimestampedSample]] = [[]]
        for sample in samples {
            if let limit = config.maximumSampleGap, let previous = segments.last?.last,
               sample.t - previous.t > limit {
                segments.append([])
            }
            segments[segments.count - 1].append(sample)
        }
        let hasGap = segments.count > 1
        var cycleCount = 0
        var firstEventTime: Double?
        var durations: [Double] = []
        var amplitudes: [Double] = []
        var weightedSlope = 0.0
        var comparisonCount = 0
        var eventTimes: [Double] = []
        for segment in segments where segment.count >= 4 {
            let times = segment.map { $0.t }
            let raw = segment.map { $0.value }
            let meanDt = (times.last! - times.first!) / Double(times.count - 1)
            let window = max(3, Int((config.smoothingSec / meanDt).rounded()))
            let signal = smooth(raw, window: window)
            let events = config.detectsLocalExcursions
                ? localExcursionCycleIndices(signal, times: times)
                : hysteresisCycleIndices(signal, times: times)
            cycleCount += events.count
            eventTimes.append(contentsOf: events.map { times[$0] })
            if firstEventTime == nil, let first = events.first { firstEventTime = times[first] }
            for (a, b) in zip(events, events.dropFirst()) {
                durations.append(times[b] - times[a])
            }
            guard events.count >= 2 else { continue }
            // A tail ending at tracking loss is not a complete movement cycle.
            var localAmplitudes = segmentAmplitudes(signal, eventIndices: events)
            if hasGap, localAmplitudes.count == events.count { localAmplitudes.removeLast() }
            amplitudes.append(contentsOf: localAmplitudes)
            let comparisons = max(0, localAmplitudes.count - 1)
            let mean = localAmplitudes.isEmpty ? 0 : localAmplitudes.reduce(0, +) / Double(localAmplitudes.count)
            if mean > 0 {
                weightedSlope += linearSlope(y: localAmplitudes) / mean * Double(comparisons)
                comparisonCount += comparisons
            }
        }
        guard !durations.isEmpty else {
            return Analysis(metrics: MovementMetrics(
                cycleCount: cycleCount, frequencyHz: 0, meanAmplitude: 0,
                amplitudeDecrementSlope: 0, rhythmCV: 0, pauseCount: 0,
                onsetLatencySec: max(0, (firstEventTime ?? samples[0].t) - samples[0].t),
                qualityIndex: 0), intervalCount: 0, amplitudeComparisonCount: 0, cycleEventTimes: eventTimes)
        }

        let frequency = Double(durations.count) / durations.reduce(0, +)

        let meanAmp = amplitudes.isEmpty ? 0 : amplitudes.reduce(0,+) / Double(amplitudes.count)

        // Decrement: slope of amplitude vs cycle index, normalized by mean amplitude
        // so it is comparable across recordings/scales. Negative = fatiguing.
        // Never interpret a pose/size change across missing observations as decrement.
        let normSlope = comparisonCount > 0 ? weightedSlope / Double(comparisonCount) : 0

        // Rhythm: coefficient of variation of cycle durations.
        let cv = coefficientOfVariation(durations)

        // Pauses: inter-peak intervals much longer than the median.
        let pauses = countPauses(durations, factor: config.pauseFactor)

        // Onset latency: time from recording start to first detected cycle.
        let onset = (firstEventTime ?? samples[0].t) - samples[0].t

        let quality = qualityIndex(frequency: frequency,
                                   rhythmCV: cv,
                                   normSlope: normSlope,
                                   pauseCount: pauses)

        return Analysis(metrics: MovementMetrics(
            cycleCount: cycleCount,
            frequencyHz: frequency,
            meanAmplitude: meanAmp,
            amplitudeDecrementSlope: normSlope,
            rhythmCV: cv,
            pauseCount: pauses,
            onsetLatencySec: max(onset, 0),
            qualityIndex: quality
        ), intervalCount: durations.count, amplitudeComparisonCount: comparisonCount, cycleEventTimes: eventTimes)
    }

    // MARK: - Signal processing helpers

    /// Directional hysteresis uses the same robust excursion band as the older
    /// detector, but anchors it to the latest extremum rather than a fixed level.
    /// A sustained plateau cannot create cycles without both a fall and a rise.
    private func localExcursionCycleIndices(_ signal: [Double], times: [Double]) -> [Int] {
        guard signal.count >= 3 else { return [] }
        let ordered = signal.sorted()
        let range = ordered[Int(Double(ordered.count - 1) * 0.95)]
            - ordered[Int(Double(ordered.count - 1) * 0.05)]
        let excursion = range * (config.highFraction - config.lowFraction)
        guard excursion.isFinite, excursion > 1e-9 else { return [] }
        // Start unarmed: a recording/gap can begin halfway through a movement.
        var seekingRise = false
        var extreme = signal[0]
        var lastEventTime = -Double.infinity
        var events: [Int] = []
        for i in signal.indices {
            let value = signal[i]
            if seekingRise {
                extreme = min(extreme, value)
                if value - extreme >= excursion {
                    if times[i] - lastEventTime >= config.minPeakSpacingSec {
                        events.append(i)
                        lastEventTime = times[i]
                    }
                    seekingRise = false
                    extreme = value
                }
            } else {
                extreme = max(extreme, value)
                if extreme - value >= excursion {
                    seekingRise = true
                    extreme = value
                }
            }
        }
        return events
    }

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
