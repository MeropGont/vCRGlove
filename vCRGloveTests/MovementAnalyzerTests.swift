//
//  MovementAnalyzerTests.swift
//  vCRGloveTests
//
//  Task A of the movement task module: verifies the sensor-independent
//  analysis pipeline (SyntheticSignalGenerator → MovementAnalyzer) produces
//  clinically plausible, clearly separated metrics for healthy-like vs.
//  parkinsonian-like synthetic signals. Runs entirely in the Simulator.
//

import Testing
@testable import vCRGlove

struct MovementAnalyzerTests {

    // MARK: - Healthy-like signal

    @Test func healthySignalMetrics() throws {
        var gen = SyntheticSignalGenerator(params: .healthy, seed: 42)
        let samples = gen.generate()
        let metrics = MovementAnalyzer().analyze(samples)

        #expect(metrics.frequencyHz > 3.5, "healthy tapping should be fast (got \(metrics.frequencyHz) Hz)")
        #expect(metrics.rhythmCV < 0.1, "healthy rhythm should be steady (got CV \(metrics.rhythmCV))")
        #expect(metrics.pauseCount == 0, "healthy signal should have no freezing pauses")
        #expect(metrics.cycleCount > 10, "8 s at ~4.5 Hz should yield many cycles")
        #expect(metrics.meanAmplitude > 0)
    }

    // MARK: - Parkinsonian-like signal

    @Test func parkinsonianSignalMetrics() throws {
        var gen = SyntheticSignalGenerator(params: .parkinsonian, seed: 42)
        let samples = gen.generate()
        let metrics = MovementAnalyzer().analyze(samples)

        #expect(metrics.frequencyHz < 3, "bradykinetic tapping should be slow (got \(metrics.frequencyHz) Hz)")
        #expect(metrics.rhythmCV > 0.2, "parkinsonian rhythm should be irregular (got CV \(metrics.rhythmCV))")
        #expect(metrics.amplitudeDecrementSlope < 0, "amplitude should decrement (got slope \(metrics.amplitudeDecrementSlope))")
        #expect(metrics.pauseCount >= 1, "injected pause should be detected")
    }

    // MARK: - Separation between the two profiles

    @Test func profilesSeparateCleanly() throws {
        var healthyGen = SyntheticSignalGenerator(params: .healthy, seed: 7)
        var pdGen      = SyntheticSignalGenerator(params: .parkinsonian, seed: 7)
        let analyzer = MovementAnalyzer()

        let healthy = analyzer.analyze(healthyGen.generate())
        let pd      = analyzer.analyze(pdGen.generate())

        #expect(healthy.frequencyHz > pd.frequencyHz)
        #expect(healthy.rhythmCV < pd.rhythmCV)
        #expect(healthy.qualityIndex > pd.qualityIndex)
    }

    // MARK: - Determinism

    @Test func generatorIsDeterministic() throws {
        var a = SyntheticSignalGenerator(params: .parkinsonian, seed: 123)
        var b = SyntheticSignalGenerator(params: .parkinsonian, seed: 123)
        #expect(a.generate() == b.generate())
    }

    // MARK: - Edge cases

    @Test func emptyAndTinyInputsReturnEmptyMetrics() throws {
        let analyzer = MovementAnalyzer()
        #expect(analyzer.analyze([]) == .empty)

        let tiny = [TimestampedSample(t: 0, value: 0),
                    TimestampedSample(t: 0.1, value: 1),
                    TimestampedSample(t: 0.2, value: 0)]
        #expect(analyzer.analyze(tiny) == .empty)
    }

    @Test func flatSignalYieldsNoCycles() throws {
        let flat = (0..<200).map { TimestampedSample(t: Double($0) / 60.0, value: 0.5) }
        let metrics = MovementAnalyzer().analyze(flat)
        #expect(metrics.cycleCount == 0)
        #expect(metrics.frequencyHz == 0)
        #expect(metrics.pauseCount == 0)
    }
}
