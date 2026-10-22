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
import Foundation
@testable import vCRGlove

struct MovementAnalyzerTests {

    private func angleWave(start: Double = 0, seconds: Double = 10) -> [TimestampedAngleSample] {
        (0..<Int(seconds * 60)).map {
            let t = Double($0) / 60
            return TimestampedAngleSample(t: start + t, degrees: 20 - 20 * cos(2 * .pi * 2 * t))
        }
    }

    @Test func firstTenTapsSelectEarliestCompleteCyclesWithoutChangingInputs() throws {
        let samples = angleWave()
        let recording = FingerTappingAngleRecording(samples: samples)
        let before = FingerTappingAngleAnalyzer.analyze(recording)
        let segment = try #require(FingerTappingAngleAnalyzer.firstTenTaps(recording))
        #expect(segment.selectionVersion == FingerTappingReferenceSegment.currentVersion)
        #expect(segment.completedTapCount == 10 && segment.openingPeakTimes.count == 11)
        #expect(segment.firstSampleIndex == 15 && segment.endSampleIndexExclusive == 316)
        #expect(abs(segment.startTrialTimeSeconds - 0.25) < 1e-12)
        #expect(abs(segment.endTrialTimeSeconds - 5.25) < 1e-12)
        #expect(recording.samples == samples)
        #expect(FingerTappingAngleAnalyzer.analyze(recording) == before)
    }

    @Test func studyComparisonUsesOnlyFirstTenAndCorrectHandReference() throws {
        let angles = FingerTappingAngleRecording(samples: angleWave())
        let trial = Trial(taskType: .fingerTap, side: .left, source: .camera,
                          stopCondition: .thirtySec, samples: [], metrics: .empty,
                          fingerTappingAngle: angles,
                          fingerTappingReferenceSegment: FingerTappingAngleAnalyzer.firstTenTaps(angles))
        #expect(abs(try #require(trial.displayedFirstTenTappingRate) - 2) < 1e-10)
        #expect(FingerTappingStudyReference.medianRate(for: .left) == 3.9151882425)
        #expect(FingerTappingStudyReference.medianRate(for: .right) == 4.05034882)
        #expect(trial.withVideo(nil).withMedicationTiming(nil).displayedFirstTenTappingRate == trial.displayedFirstTenTappingRate)
        let changedTail = angles.samples.map { sample in
            TimestampedAngleSample(t: sample.t, degrees: sample.t > 6 ? 0 : sample.degrees)
        }
        let legacy = Trial(taskType: .fingerTap, side: .right, source: .camera,
                           stopCondition: .thirtySec, samples: [], metrics: .empty,
                           fingerTappingAngle: .init(samples: changedTail))
        #expect(legacy.displayedFirstTenTappingRate == trial.displayedFirstTenTappingRate)
        #expect(legacy.fingerTappingReferenceSegment == nil)
    }

    @Test func studyComparisonRejectsMissingWrongTaskAndUnknownSelection() throws {
        let angles = FingerTappingAngleRecording(samples: angleWave())
        let segment = try #require(FingerTappingAngleAnalyzer.firstTenTaps(angles))
        let unknown = FingerTappingReferenceSegment(selectionVersion: "future",
            sourceAngleVersion: segment.sourceAngleVersion, detectorVersion: segment.detectorVersion,
            completedTapCount: 10, firstSampleIndex: segment.firstSampleIndex,
            endSampleIndexExclusive: segment.endSampleIndexExclusive,
            startTrialTimeSeconds: segment.startTrialTimeSeconds, endTrialTimeSeconds: segment.endTrialTimeSeconds,
            openingPeakTimes: segment.openingPeakTimes)
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera,
                          stopCondition: .thirtySec, samples: [], metrics: .empty,
                          fingerTappingAngle: angles, fingerTappingReferenceSegment: unknown)
        #expect(trial.displayedFirstTenTappingRate == nil)
        let brief = Trial(taskType: .fingerTap, side: .left, source: .camera,
                          stopCondition: .thirtySec, samples: [], metrics: .empty,
                          fingerTappingAngle: .init(samples: angleWave(seconds: 2)))
        #expect(brief.displayedFirstTenTappingRate == nil)
        let other = Trial(taskType: .fingerTap, side: .right, source: .synthetic,
                          stopCondition: .thirtySec, samples: [], metrics: .empty, fingerTappingAngle: angles)
        #expect(other.displayedFirstTenTappingRate == nil)
    }

    @Test func firstTenTapsDoNotStitchAcrossTrackingLossOrChooseLaterSegment() throws {
        let samples = angleWave()
        let missing = samples.map { TimestampedAngleSample(t: $0.t, degrees: (1...2).contains($0.t) ? nil : $0.degrees) }
        let dropped = samples.filter { !(1...2).contains($0.t) }
        #expect(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: missing)) == nil)
        #expect(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: dropped)) == nil)
        let lateMissing = samples.map { TimestampedAngleSample(t: $0.t, degrees: $0.t > 7 ? nil : $0.degrees) }
        #expect(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: lateMissing))
                == FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: samples)))
    }

    @Test func firstTenTapsAllowLeadingMissingFramesButNotInterruptedCycles() throws {
        let samples = angleWave()
        let leadingMissing = samples.map { TimestampedAngleSample(t: $0.t, degrees: $0.t < 0.08 ? nil : $0.degrees) }
        #expect(try #require(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: leadingMissing))).firstSampleIndex == 15)
        let interrupted = samples.map { sample in TimestampedAngleSample(t: sample.t,
            degrees: sample.degrees.map { $0 + ((2.2...2.8).contains(sample.t) ? 30 : 0) }) }
        #expect(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: interrupted)) == nil)
        #expect(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: angleWave(seconds: 5))) == nil)
        #expect(FingerTappingAngleAnalyzer.firstTenTaps(.init(samples: [])) == nil)
    }

    @Test func angleMetricsUseDegreesAndActualTimestamps() throws {
        let result = try #require(FingerTappingAngleAnalyzer.analyze(.init(samples: angleWave())))
        #expect(result.calculationVersion == FingerTappingAngleMetrics.currentVersion)
        #expect(abs(try #require(result.meanRateHz) - 2) < 0.001)
        #expect(abs(try #require(result.meanOpeningAngleDegrees) - 40) < 0.001)
        #expect(abs(try #require(result.meanAbsoluteAngularSpeedDegreesPerSecond) - 160) < 1)
        #expect(try #require(result.periodCV) < 0.001)
        #expect(result.intervalCount > 15)
        let slower = angleWave().map { TimestampedAngleSample(t: $0.t * 2, degrees: $0.degrees) }
        let slowResult = try #require(FingerTappingAngleAnalyzer.analyze(.init(samples: slower)))
        #expect(abs(try #require(slowResult.meanRateHz) - 1) < 0.001)
        #expect(abs(try #require(slowResult.meanAbsoluteAngularSpeedDegreesPerSecond) - 80) < 1)
    }

    @Test func angleMetricsNeverBridgeMissingOrLostTracking() throws {
        let wave = angleWave()
        let missing = wave.map { TimestampedAngleSample(t: $0.t, degrees: (3...6).contains($0.t) ? nil : $0.degrees) }
        let dropped = wave.filter { !(3...6).contains($0.t) }
        for samples in [missing, dropped] {
            let result = try #require(FingerTappingAngleAnalyzer.analyze(.init(samples: samples)))
            #expect(abs(try #require(result.meanRateHz) - 2) < 0.001)
            #expect(try #require(result.periodCV) < 0.001)
            #expect(result.trackedSeconds < 7)
            #expect(result.intervalCount < 15)
        }
    }

    @Test func angleMetricsFlatOpenOnlyAndInvalidInputsDoNotInventCycles() throws {
        for value in [0.0, 40.0] {
            let result = try #require(FingerTappingAngleAnalyzer.analyze(.init(samples:
                (0..<100).map { TimestampedAngleSample(t: Double($0) / 30, degrees: value) })))
            #expect(result.meanRateHz == nil)
            #expect(result.periodCV == nil)
            #expect(result.meanOpeningAngleDegrees == nil)
            #expect(result.meanAbsoluteAngularSpeedDegreesPerSecond == 0)
        }
        let openOnly = angleWave().map { TimestampedAngleSample(t: $0.t, degrees: $0.degrees.map { $0 + 20 }) }
        #expect(FingerTappingAngleAnalyzer.analyze(.init(samples: openOnly))?.meanRateHz == nil)
        for samples in [[], [.init(t: 0, degrees: nil)], [.init(t: 0, degrees: 181)],
                        [.init(t: 0, degrees: 0), .init(t: 0, degrees: 40)], [.init(t: .nan, degrees: 0)]] as [[TimestampedAngleSample]] {
            let result = FingerTappingAngleAnalyzer.analyze(.init(samples: samples))
            #expect(result?.meanRateHz == nil)
            #expect(result?.meanOpeningAngleDegrees == nil)
        }
    }

    @Test func angleMetricsPersistThroughTrialCopiesAndLegacyDecode() throws {
        let angle = FingerTappingAngleRecording(samples: angleWave())
        let metrics = try #require(FingerTappingAngleAnalyzer.analyze(angle))
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera,
                          stopCondition: .init(mode: .duration, targetReps: 10, targetDuration: 30),
                          samples: [], metrics: MovementAnalyzer().analyze([]),
                          fingerTappingAngle: angle, fingerTappingAngleMetrics: metrics,
                          fingerTappingReferenceSegment: FingerTappingAngleAnalyzer.firstTenTaps(angle))
        #expect(trial.withVideo(nil).withMedicationTiming(nil).fingerTappingAngleMetrics == metrics)
        #expect(trial.withVideo(nil).withMedicationTiming(nil).fingerTappingReferenceSegment == trial.fingerTappingReferenceSegment)
        let data = try JSONEncoder().encode(trial)
        #expect(try JSONDecoder().decode(Trial.self, from: data) == trial)
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "fingerTappingAngleMetrics")
        json.removeValue(forKey: "fingerTappingReferenceSegment")
        let legacy = try JSONDecoder().decode(Trial.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.fingerTappingAngleMetrics == nil)
        #expect(legacy.fingerTappingReferenceSegment == nil)
        #expect(legacy.displayedFingerTappingAngleMetrics == metrics)
        json.removeValue(forKey: "fingerTappingAngle")
        let oldest = try JSONDecoder().decode(Trial.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(oldest.displayedFingerTappingAngleMetrics == nil)
    }

    @Test func angleMetricsRejectUnknownContractsAndTooFewIntervals() throws {
        let source = FingerTappingAngleRecording(samples: angleWave())
        for field in ["measurementVersion", "unit", "timeReference"] {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as? [String: Any])
            json[field] = "unknown"
            let recording = try JSONDecoder().decode(FingerTappingAngleRecording.self,
                from: JSONSerialization.data(withJSONObject: json))
            #expect(FingerTappingAngleAnalyzer.analyze(recording) == nil)
        }
        let brief = try #require(FingerTappingAngleAnalyzer.analyze(.init(samples: angleWave(seconds: 0.4))))
        #expect(brief.meanRateHz == nil)
        #expect(brief.periodCV == nil)
        #expect(brief.intervalCount == 0)
        let backwards = [TimestampedAngleSample(t: 1, degrees: 40), .init(t: 0.5, degrees: 0)]
        #expect(FingerTappingAngleAnalyzer.analyze(.init(samples: backwards)) == nil)
    }

    private func periodic(_ seconds: Double = 12) -> [TimestampedSample] {
        (0..<Int(seconds * 30)).map {
            let t = Double($0) / 30
            return TimestampedSample(t: t, value: 1 + sin(2 * .pi * 4 * t))
        }
    }

    @Test func cameraGapDoesNotBecomePauseOrIrregularRhythm() {
        let samples = periodic().filter { $0.t < 4 || $0.t >= 7 }
        let old = MovementAnalyzer().analyze(samples)
        let result = MovementAnalyzer(config: .camera).analyzeWithEvidence(samples)
        #expect(old.rhythmCV > 0.5)
        #expect(result.metrics.rhythmCV < 0.1)
        #expect(result.metrics.pauseCount == 0)
        #expect(abs(result.metrics.frequencyHz - 4) < 0.1)
        #expect(result.intervalCount == result.metrics.cycleCount - 2)
    }

    @Test func continuousCameraKeepsRateAndEarlierDetectorRemainsAvailable() {
        let samples = periodic()
        #expect(MovementAnalyzer(config: .cameraGapAware).analyze(samples) == MovementAnalyzer().analyze(samples))
        let camera = MovementAnalyzer(config: .camera).analyze(samples)
        #expect(abs(camera.frequencyHz - 4) < 0.1)
        #expect(camera.rhythmCV < 0.1)
    }

    @Test func visiblePauseIsStillMeasured() {
        let samples = periodic().map {
            TimestampedSample(t: $0.t, value: (4..<6).contains($0.t) ? 0 : $0.value)
        }
        let result = MovementAnalyzer(config: .camera).analyze(samples)
        #expect(result.pauseCount >= 1)
        #expect(result.rhythmCV > 0.3)
    }

    @Test func detectorCannotCompleteCycleAcrossTrackingGap() {
        let samples = (0..<12).map {
            TimestampedSample(t: Double($0) / 30 + ($0 >= 6 ? 2 : 0), value: $0 < 6 ? 0 : 1)
        }
        #expect(MovementAnalyzer().analyze(samples).cycleCount == 1)
        #expect(MovementAnalyzer(config: .camera).analyze(samples).cycleCount == 0)
    }

    @Test func poseChangeAcrossGapIsNotAmplitudeDecrement() {
        let samples = periodic().filter { $0.t < 4 || $0.t >= 7 }.map {
            TimestampedSample(t: $0.t, value: $0.value * ($0.t < 4 ? 5 : 0.5))
        }
        let result = MovementAnalyzer(config: .camera).analyzeWithEvidence(samples)
        #expect(abs(result.metrics.amplitudeDecrementSlope) < 0.01)
        #expect(result.amplitudeComparisonCount > 0)
    }

    @Test func isolatedEventsDoNotProvideRateOrPerfectRhythm() {
        let samples = (0..<3).flatMap { segment in
            [0.0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, 1].enumerated().map { index, value in
                TimestampedSample(t: Double(segment) * 2 + Double(index) / 30, value: value)
            }
        }
        let result = MovementAnalyzer(config: .camera).analyzeWithEvidence(samples)
        #expect(result.metrics.cycleCount == 3)
        #expect(result.intervalCount == 0)
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera,
                          stopCondition: .thirtySec, startedAt: Date(), samples: samples,
                          metrics: result.metrics, measurementVersion: MovementMeasurementVersion.camera)
        for metric in [TrendMetric.frequency, .amplitude, .rhythm, .pauses, .decrement, .quality] {
            #expect(metric.availability(for: trial) == .insufficientCycles)
        }
    }

    @Test func briefFrameDropoutsRemainWithinContinuityTolerance() {
        let samples = periodic().enumerated().filter { $0.offset != 100 }.map(\.element)
        let result = MovementAnalyzer(config: .camera).analyze(samples)
        #expect(result.cycleCount == MovementAnalyzer(config: .camera).analyze(periodic()).cycleCount)
        #expect(abs(result.frequencyHz - 4) < 0.1)
        #expect(result.rhythmCV < 0.1)
    }

    @Test func baselineDriftDoesNotHideRepeatedMovements() {
        let samples = periodic().map {
            TimestampedSample(t: $0.t, value: 1 + $0.t / 6 + 0.35 * sin(2 * .pi * 4 * $0.t))
        }
        let result = MovementAnalyzer(config: .camera).analyze(samples)
        #expect(result.cycleCount >= 46)
        #expect(abs(result.frequencyHz - 4) < 0.1)
        #expect(result.pauseCount == 0)
    }

    @Test func decliningAmplitudeRemainsMeasuredRatherThanNormalizedAway() {
        let samples = periodic().map {
            TimestampedSample(t: $0.t, value: 2 + (1 - 0.7 * $0.t / 12) * sin(2 * .pi * 3 * $0.t))
        }
        let result = MovementAnalyzer(config: .camera).analyze(samples)
        #expect(result.cycleCount >= 34)
        #expect(result.amplitudeDecrementSlope < -0.01)
        #expect(result.meanAmplitude < MovementAnalyzer(config: .camera).analyze(periodic().map {
            .init(t: $0.t, value: 2 + sin(2 * .pi * 3 * $0.t))
        }).meanAmplitude)
    }

    @Test(arguments: [0.3, 1.0, 5.0])
    func slowAndFastSmallMovementsRemainCountable(rate: Double) {
        let samples = (0..<1800).map { i in
            let t = Double(i) / 30
            return TimestampedSample(t: t, value: 2 + 0.001 * sin(2 * .pi * rate * t))
        }
        let result = MovementAnalyzer(config: .camera).analyze(samples)
        #expect(abs(result.frequencyHz - rate) < 0.03)
        #expect(abs(Double(result.cycleCount) - 60 * rate) <= 1)
        #expect(result.pauseCount == 0)
    }

    @Test func plateauWobbleDoesNotCreateExtraCyclesButHoldRemainsAPause() {
        let samples = periodic().map {
            TimestampedSample(t: $0.t, value: (4..<6).contains($0.t)
                              ? 2 + 0.03 * sin(2 * .pi * 8 * $0.t) : $0.value)
        }
        let result = MovementAnalyzer(config: .camera).analyzeWithEvidence(samples)
        #expect(result.cycleEventTimes.filter { (4.2..<5.8).contains($0) }.isEmpty)
        #expect(result.metrics.pauseCount == 1)
    }

    @Test func measurementScaleAndOffsetDoNotChangeCycleCounts() {
        let analyzer = MovementAnalyzer(config: .camera)
        let reference = analyzer.analyze(periodic())
        let scaled = analyzer.analyze(periodic().map { .init(t: $0.t, value: $0.value * 0.005 + 10) })
        #expect(reference.cycleCount == scaled.cycleCount)
        #expect(abs(reference.frequencyHz - scaled.frequencyHz) < 1e-10)
        #expect(abs(reference.meanAmplitude * 0.005 - scaled.meanAmplitude) < 1e-10)
    }

    @Test func invalidAndFragmentedInputsDoNotProduceMetrics() {
        let analyzer = MovementAnalyzer(config: .camera)
        #expect(analyzer.analyze((0..<10).map { TimestampedSample(t: Double($0), value: Double($0 % 2)) }) == .empty)
        #expect(analyzer.analyze([.init(t: 0, value: 0), .init(t: 0.1, value: .nan),
                                 .init(t: 0.2, value: 1), .init(t: 0.3, value: 0)]) == .empty)
        #expect(analyzer.analyze([.init(t: 0, value: 0), .init(t: 0.1, value: 1),
                                 .init(t: 0.1, value: 0), .init(t: 0.2, value: 1)]) == .empty)
    }

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
