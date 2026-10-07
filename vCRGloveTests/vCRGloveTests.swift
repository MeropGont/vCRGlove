//
//  vCRGloveTests.swift
//  vCRGloveTests
//
//  Created by Tactile Glove on 22.08.25.
//

import Testing
import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import vCRGlove

struct MovementContextMedicationTests {
    private let intake = Date(timeIntervalSince1970: 1700000000)

    private func trial(at date: Date) -> Trial {
        Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
              startedAt: date, startUptime: 123, samples: [.init(t: 0, value: 0.2)], metrics: .empty)
    }

    @Test func patientChoicesExcludeHistoricalAndUnknownCategories() {
        #expect(StimulationContext.patientChoices == [.preStim, .postStim, .noStimPlanned])
        #expect(StimulationContext.baseline.rawValue == "baseline")
        #expect(StimulationContext.unspecified.rawValue == "unspecified")
        #expect(StimulationContext.noStimPlanned.rawValue != StimulationContext.baseline.rawValue)
    }

    @Test(arguments: [StimulationContext.baseline, .unspecified, .preStim, .postStim])
    func olderSessionsRemainUnchanged(context: StimulationContext) throws {
        let original = MovementSession(patientId: "TEST", stimulationContext: context,
                                       trials: [trial(at: intake)])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let saved = try decoder.decode(MovementSession.self, from: data)
        #expect(saved.stimulationContext == context)
        #expect(saved.trials == original.trials)
        #expect(saved.trials[0].medicationTiming == nil)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let trials = object["trials"] as! [[String: Any]]
        #expect(trials[0]["medicationTiming"] == nil)
    }

    @Test func metadataPreservesEveryRecordingFieldAndUsesItsStartTime() throws {
        let entryID = UUID()
        let timing = MedicationTiming(status: .takenAt, takenAt: intake,
                                      journalEntryID: entryID, medicationName: "A", medicationDose: "100 mg")
        let first = trial(at: intake.addingTimeInterval(3600))
        let tagged = first.withMedicationTiming(timing)
        #expect(tagged.id == first.id)
        #expect(tagged.samples == first.samples)
        #expect(tagged.metrics == first.metrics)
        #expect(tagged.startedAt == first.startedAt)
        #expect(tagged.startUptime == first.startUptime)
        #expect(tagged.stopCondition == first.stopCondition)
        #expect(tagged.source == first.source && tagged.side == first.side && tagged.taskType == first.taskType)
        #expect(tagged.medicationTiming?.elapsedSeconds(at: tagged.startedAt) == 3600)
        let later = trial(at: intake.addingTimeInterval(3900)).withMedicationTiming(timing)
        #expect(later.medicationTiming?.elapsedSeconds(at: later.startedAt) == 3900)
        #expect(try JSONDecoder().decode(Trial.self, from: JSONEncoder().encode(tagged)) == tagged)
    }

    @Test func missingFutureAndUnknownIntakeDoNotProduceElapsedTime() {
        #expect(MedicationTiming(status: .takenAt).elapsedSeconds(at: intake) == nil)
        let future = MedicationTiming(status: .takenAt, takenAt: intake.addingTimeInterval(1))
        #expect(trial(at: intake).withMedicationTiming(future).medicationTiming == nil)
        for status in [MedicationTiming.Status.noneToday, .unsure] {
            let timing = MedicationTiming(status: status, takenAt: intake, confirmedAt: intake)
            #expect(timing.elapsedSeconds(at: intake) == nil)
            #expect(timing.takenAt == nil)
            #expect(trial(at: intake).withMedicationTiming(timing).medicationTiming?.status == status)
        }
        #expect(trial(at: intake).withMedicationTiming(nil).medicationTiming == nil)
    }

    @Test func elapsedTimeCrossesMidnightButNoneTodayDoesNot() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 23, minute: 50)))
        let nextDay = yesterday.addingTimeInterval(1200)
        #expect(MedicationTiming(status: .takenAt, takenAt: yesterday).elapsedSeconds(at: nextDay) == 1200)
        let none = MedicationTiming(status: .noneToday, confirmedAt: yesterday)
        #expect(none.forRecording(at: yesterday, calendar: calendar) != nil)
        #expect(none.forRecording(at: nextDay, calendar: calendar) == nil)
    }

    @Test func journalSuggestionExcludesMissedFutureAndAmbiguousEntries() {
        let taken = JournalEntry(date: intake, type: .medication, medicationName: "A", medicationDose: "100 mg",
                                 medicationEvent: .usual)
        let entries = [taken,
                       JournalEntry(date: intake.addingTimeInterval(10), type: .medication, medicationEvent: .missed),
                       JournalEntry(date: intake.addingTimeInterval(20), type: .medication),
                       JournalEntry(date: intake.addingTimeInterval(30), type: .note, medicationEvent: .extra),
                       JournalEntry(date: intake.addingTimeInterval(100), type: .medication, medicationEvent: .extra)]
        #expect(MedicationTiming.latestIntake(in: entries, before: intake.addingTimeInterval(50))?.id == taken.id)
        #expect(MedicationTiming.latestIntake(in: Array(entries.dropFirst()), before: intake.addingTimeInterval(50)) == nil)
        let late = JournalEntry(date: intake.addingTimeInterval(40), type: .medication, medicationEvent: .late)
        #expect(MedicationTiming.latestIntake(in: entries + [late], before: intake.addingTimeInterval(50))?.id == late.id)
    }

    @Test(arguments: [MedicationTiming.Status.takenAt, .noneToday, .unsure])
    func acceptedSessionsRoundTripNewContextAndMedication(status: MedicationTiming.Status) throws {
        let timing = MedicationTiming(status: status, takenAt: intake, confirmedAt: intake)
        var session = MovementSession(patientId: "TEST", date: intake, stimulationContext: .noStimPlanned)
        session.accept(trial(at: intake).withMedicationTiming(timing))
        let saved = try TaskSessionStore.replacingSession(session, in: Data())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(MovementSession.self, from: saved)
        #expect(restored.stimulationContext == .noStimPlanned)
        #expect(restored.trials == session.trials)
    }
}

struct AcceptedMovementSessionTests {
    @Test func saveActionSymbolsExist() {
        for symbol in ["checkmark.circle.fill", "flag.checkered", "checkmark"] {
            #expect(UIImage(systemName: symbol) != nil)
        }
    }

    @Test func completenessCountsTaskHandPairsNotPerformanceOrRepeatedTrials() throws {
        let full = MovementTaskType.allCases.flatMap { task in
            BodySide.allCases.map { side in
                Trial(taskType: task, side: side, source: .synthetic,
                      stopCondition: .thirtySec, samples: [], metrics: .empty)
            }
        }
        var session = MovementSession(patientId: "TEST", trials: full)
        #expect(session.isFullMovementSet)
        #expect(session.completionLabelKey == "All tasks recorded")
        session.trials.removeLast()
        session.trials.append(full[0])
        #expect(session.recordedTaskCount == 5)
        #expect(!session.isFullMovementSet)
        #expect(session.completionLabelKey == "Some tasks recorded")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        #expect(encoded["isFullMovementSet"] == nil)
        #expect(encoded["completionLabelKey"] == nil)
    }

    @Test func acceptingRetakeReplacesOnlyItsTaskAndHandAndPreservesMetadata() {
        let original = trial()
        let otherHand = trial(side: .left)
        var session = MovementSession(patientId: "TEST", date: Date(timeIntervalSince1970: 10000),
                                      stimulationContext: .preStim, trials: [original, otherHand])
        let id = session.id
        let replacement = trial()
        session.accept(replacement)
        #expect(session.trials.map(\.id) == [replacement.id, otherHand.id])
        #expect(session.id == id)
        #expect(session.date == Date(timeIntervalSince1970: 10000))
        #expect(session.patientId == "TEST")
        #expect(session.stimulationContext == .preStim)
    }

    private func trial(side: BodySide = .right) -> Trial {
        Trial(taskType: .fingerTap, side: side, source: .synthetic,
              stopCondition: .thirtySec, samples: [.init(t: 0, value: 1)], metrics: .empty)
    }

    private func decode(_ data: Data) throws -> [MovementSession] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try data.split(separator: 0x0A).map { try decoder.decode(MovementSession.self, from: Data($0)) }
    }

    @Test func acceptsOneTaskThenUpdatesTheSameSessionWithoutDuplicateTrials() throws {
        var session = MovementSession(patientId: "TEST", date: Date(timeIntervalSince1970: 10000),
                                      stimulationContext: .preStim, trials: [trial()])
        let first = try TaskSessionStore.replacingSession(session, in: Data())
        #expect(try decode(first).count == 1)
        session.trials.append(trial(side: .left))
        let second = try TaskSessionStore.replacingSession(session, in: first)
        let decoded = try decode(second)
        #expect(decoded.count == 1)
        #expect(decoded[0].id == session.id)
        #expect(decoded[0].trials.count == 2)
        #expect(decoded[0].date == session.date)
        #expect(decoded[0].stimulationContext == .preStim)
        #expect(try TaskSessionStore.replacingSession(session, in: second) == second)
    }

    @Test func preservesOtherRecordsUnknownFieldsAndMalformedLinesVerbatim() throws {
        let prefix = Data("{\"id\":\"11111111-1111-1111-1111-111111111111\",\"futureField\":42}\nnot-json\n\n".utf8)
        let session = MovementSession(patientId: "TEST", trials: [trial()])
        let first = try TaskSessionStore.replacingSession(session, in: prefix)
        #expect(first.starts(with: prefix))
        var updated = session
        updated.trials.append(trial(side: .left))
        let second = try TaskSessionStore.replacingSession(updated, in: first)
        #expect(second.starts(with: prefix))
        #expect(second.split(separator: 0x0A).count == 3)
    }

    @Test func replacementRecordingDoesNotAccumulateAnotherTask() throws {
        var session = MovementSession(patientId: "TEST", trials: [trial()])
        let first = try TaskSessionStore.replacingSession(session, in: Data())
        session.trials[0] = trial()
        let decoded = try decode(TaskSessionStore.replacingSession(session, in: first))
        #expect(decoded.count == 1)
        #expect(decoded[0].trials.map(\.id) == session.trials.map(\.id))
    }

    @Test func missingTrailingNewlineDoesNotMergeRecords() throws {
        let first = MovementSession(patientId: "FIRST", trials: [trial()])
        let bytes = try TaskSessionStore.replacingSession(first, in: Data()).dropLast()
        let second = MovementSession(patientId: "SECOND", trials: [trial()])
        #expect(try decode(TaskSessionStore.replacingSession(second, in: Data(bytes))).count == 2)
    }

    @MainActor
    private func save(_ session: MovementSession, to store: TaskSessionStore) async throws {
        try await withCheckedThrowingContinuation { continuation in
            store.saveAcceptedSession(session) { continuation.resume(with: $0) }
        }
    }

    @Test @MainActor func partialSessionSurvivesReopeningAndLaterUpdates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sessions.jsonl")
        var session = MovementSession(patientId: "TEST", trials: [trial()])
        let store = TaskSessionStore(storageURL: url)
        try await save(session, to: store)
        #expect(store.sessions.count == 1)
        #expect(try decode(Data(contentsOf: url))[0].trials.count == 1)
        let reopened = TaskSessionStore(storageURL: url)
        session.trials.append(trial(side: .left))
        try await save(session, to: reopened)
        #expect(reopened.sessions.count == 1)
        #expect(reopened.sessions[0].trials.count == 2)
        #expect(try decode(Data(contentsOf: url)).count == 1)
    }

    @Test @MainActor func failedWriteDoesNotPublishASavedRecording() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing-parent/sessions.jsonl")
        let store = TaskSessionStore(storageURL: url)
        do {
            try await save(MovementSession(patientId: "TEST", trials: [trial()]), to: store)
            Issue.record("Expected a filesystem error")
        } catch {
            #expect(store.sessions.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test @MainActor func encodingFailureLeavesExistingFileAndPublishedTrialsUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sessions.jsonl")
        let original = MovementSession(patientId: "TEST", trials: [trial()])
        let bytes = try TaskSessionStore.replacingSession(original, in: Data())
        try bytes.write(to: url)
        let store = TaskSessionStore(storageURL: url)
        var updated = original
        let invalid = Trial(taskType: .fingerTap, side: .left, source: .synthetic,
                            stopCondition: .thirtySec, samples: [.init(t: 0, value: .nan)], metrics: .empty)
        updated.trials.append(invalid)
        do {
            try await save(updated, to: store)
            Issue.record("Expected an encoding error")
        } catch {
            #expect(try Data(contentsOf: url) == bytes)
            #expect(store.sessions.count == 1)
            #expect(store.sessions[0].trials.map(\.id) == original.trials.map(\.id))
        }
    }
}

struct MovementTrendAvailabilityTests {
    private func trial(cycles: Int = 5, samples: [TimestampedSample]? = nil,
                       date: Date = Date(timeIntervalSince1970: 100),
                       task: MovementTaskType = .fingerTap, side: BodySide = .right) -> Trial {
        Trial(taskType: task, side: side, source: .camera, stopCondition: .thirtySec, startedAt: date,
              samples: samples ?? (0..<20).map { TimestampedSample(t: Double($0) / 10, value: Double($0 % 3)) },
              metrics: MovementMetrics(cycleCount: cycles, frequencyHz: 2, meanAmplitude: 0.2,
                                       amplitudeDecrementSlope: 0, rhythmCV: 0, pauseCount: 0,
                                       onsetLatencySec: 0, qualityIndex: 0.8))
    }

    @Test(arguments: TrendMetric.allCases)
    func missingSignalDoesNotBecomeAZeroPoint(metric: TrendMetric) {
        #expect(metric.availability(for: trial(samples: [])) == .insufficientSignal)
        #expect(metric.availability(for: trial(samples: [.init(t: 0, value: 1)])) == .insufficientSignal)
        #expect(metric.availability(for: trial(cycles: 0)) == .insufficientCycles)
    }

    @Test func prerequisitesFollowTheCalculationNotAPerformanceThreshold() {
        let one = trial(cycles: 1)
        #expect(TrendMetric.onset.availability(for: one) == .available(0))
        #expect(TrendMetric.frequency.availability(for: one) == .insufficientCycles)
        let two = trial(cycles: 2)
        for metric in [TrendMetric.frequency, .amplitude, .onset] {
            #expect(metric.availability(for: two).value != nil)
        }
        for metric in [TrendMetric.decrement, .rhythm, .pauses, .quality] {
            #expect(metric.availability(for: two) == .insufficientCycles)
            #expect(metric.availability(for: trial(cycles: 3)).value != nil)
        }
    }

    @Test(arguments: [TrendMetric.rhythm, .pauses, .onset, .decrement])
    func genuineZerosAreShown(metric: TrendMetric) {
        #expect(metric.availability(for: trial()) == .available(0))
    }

    @Test func negativeDecrementAndLowIndexAreNotRejectedAsPoorPerformance() {
        var recording = trial()
        recording = Trial(taskType: recording.taskType, side: recording.side, source: recording.source,
                          stopCondition: recording.stopCondition, startedAt: recording.startedAt,
                          samples: recording.samples,
                          metrics: MovementMetrics(cycleCount: 5, frequencyHz: 0.01, meanAmplitude: 0.001,
                                                   amplitudeDecrementSlope: -0.4, rhythmCV: 2,
                                                   pauseCount: 4, onsetLatencySec: 4, qualityIndex: 0))
        #expect(TrendMetric.decrement.availability(for: recording) == .available(-0.4))
        #expect(TrendMetric.quality.availability(for: recording) == .available(0))
        #expect(TrendMetric.frequency.availability(for: recording) == .available(0.01))
    }

    @Test func malformedSamplesAreUnavailableWithoutReanalysis() {
        for samples in [
            Array(repeating: TimestampedSample(t: 0, value: 1), count: 5),
            [TimestampedSample(t: 0, value: 1), .init(t: 1, value: .nan), .init(t: 2, value: 1), .init(t: 3, value: 1)],
            [TimestampedSample(t: 0, value: 1), .init(t: 2, value: 1), .init(t: 1, value: 1), .init(t: 3, value: 1)],
            [TimestampedSample(t: -1, value: 1), .init(t: 0, value: 1), .init(t: 1, value: 1), .init(t: 2, value: 1)]
        ] {
            #expect(TrendMetric.frequency.availability(for: trial(samples: samples)) == .insufficientSignal)
        }
    }

    @Test func nonFiniteMetricsNeverReachCharts() {
        let recording = trial()
        var metrics = recording.metrics
        metrics.frequencyHz = .nan
        let invalid = Trial(taskType: recording.taskType, side: recording.side, source: recording.source,
                            stopCondition: recording.stopCondition, samples: recording.samples, metrics: metrics)
        #expect(TrendMetric.frequency.availability(for: invalid) == .invalidValue)
        #expect(TrendMetric.amplitude.availability(for: invalid) == .available(0.2))
    }

    @Test func summaryUsesTrialDatesFiltersTaskAndHandAndKeepsSavedData() throws {
        let first = trial(date: Date(timeIntervalSince1970: 100))
        let missing = trial(samples: [], date: Date(timeIntervalSince1970: 200))
        let last = trial(date: Date(timeIntervalSince1970: 300))
        let session = MovementSession(patientId: "TEST", date: Date(timeIntervalSince1970: 999),
                                      stimulationContext: .preStim,
                                      trials: [last, trial(task: .handOpenClose), trial(side: .left), missing, first])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(session)
        let summary = MovementTrendSummary(sessions: [session], task: .fingerTap, side: .right, metric: .frequency)
        #expect(summary.recordings.count == 3)
        #expect(summary.unavailableCount == 1)
        #expect(summary.points.map(\.date) == [first.startedAt, last.startedAt])
        #expect(summary.points.allSatisfy { $0.context == .preStim })
        #expect(summary.points.first?.segment != summary.points.last?.segment)
        #expect(summary.canShowTrend)
        #expect(try encoder.encode(session) == before)
    }

    @Test func zeroSingleAndSameTimeMeasurementsDoNotClaimATrend() {
        let empty = MovementTrendSummary(sessions: [], task: .fingerTap, side: .right, metric: .frequency)
        #expect(empty.recordings.isEmpty)
        #expect(!empty.canShowTrend)
        let session = MovementSession(patientId: "TEST", trials: [trial(), trial()])
        let sameTime = MovementTrendSummary(sessions: [session], task: .fingerTap, side: .right, metric: .frequency)
        #expect(sameTime.points.count == 2)
        #expect(!sameTime.canShowTrend)
        let single = MovementTrendSummary(sessions: [MovementSession(patientId: "TEST", trials: [trial()])],
                                          task: .fingerTap, side: .right, metric: .frequency)
        #expect(single.points.count == 1)
        #expect(!single.canShowTrend)
    }
}

struct MovementRecordingGuidanceTests {
    @Test(arguments: [BodySide.left, BodySide.right])
    func handLabelUsesACompleteTranslationKey(side: BodySide) {
        let guidance = MovementRecordingGuidance(taskType: .fingerTap, side: side)
        #expect(guidance.handKey == (side == .left ? "Left hand" : "Right hand"))
    }

    @Test(arguments: [MovementTaskType.fingerTap, .handOpenClose])
    func cameraInstructionsAreShortAndIndependentOfHand(task: MovementTaskType) {
        let left = MovementRecordingGuidance(taskType: task, side: .left)
        let right = MovementRecordingGuidance(taskType: task, side: .right)
        #expect(left.instructionKey == right.instructionKey)
        #expect(left.instructionKey.components(separatedBy: "\n").count == 2)
        #expect(left.instructionKey.contains("as fast as you can"))
        #expect(left.instructionKey.split(whereSeparator: { $0.isWhitespace }).count <= 20)
        #expect(!left.instructionKey.contains(task.rawValue))
    }
}

struct HandCalibrationQualityTests {
    private func frame(_ time: Double, scale: Double = 0.12,
                       detected: Bool = true, visible: Bool = true, open: Bool = true,
                       facing: Bool = true, inside: Bool = true) -> HandCalibrationFrame {
        HandCalibrationFrame(timestamp: time, scale: scale,
                             isDetected: detected, isFullyVisible: visible,
                             isOpenHand: open, isFacingCamera: facing, isInsideGuide: inside)
    }

    private func prepared() -> HandCalibrationQualityGate {
        var gate = HandCalibrationQualityGate()
        for i in 0...30 {
            let time = Double(i) / 30
            gate.update(frame: frame(time), now: time)
        }
        return gate
    }

    @Test func requiresStableDetectionBeforeStarting() {
        var gate = HandCalibrationQualityGate()
        gate.start(frame: frame(0), now: 0)
        #expect(gate.phase == .positioning)
        #expect(!gate.isReady)
        gate = prepared()
        #expect(gate.isReady)
        gate.start(frame: frame(1), now: 1)
        #expect(gate.phase == .countdown)
        #expect(gate.countdown == 3)
    }

    @Test(arguments: [15.0, 30.0])
    func stableFramesPassQualityCheck(fps: Double) throws {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        for i in 1...Int(fps * 5.2) {
            let time = 1 + Double(i) / fps
            gate.update(frame: frame(time, scale: 0.12 + 0.001 * sin(time)), now: time)
        }
        #expect(gate.phase == .complete)
        let result = try #require(gate.result)
        #expect(abs(result.scale - 0.12) < 0.002)
        #expect(result.sampleCount >= 20)
        #expect(result.relativeVariation < 0.10)
    }

    @Test func checksMissingClippedAndDistantHands() {
        var gate = HandCalibrationQualityGate()
        gate.update(frame: frame(0, detected: false), now: 0)
        #expect(gate.guidance == .showHand)
        gate.update(frame: frame(1, visible: false), now: 1)
        #expect(gate.guidance == .wholeHand)
        gate.update(frame: frame(2, scale: 0.03), now: 2)
        #expect(gate.guidance == .closer)
        gate.update(frame: frame(3, scale: 0.25), now: 3)
        #expect(gate.guidance == .farther)
        #expect(gate.result == nil)
    }

    @Test func rejectsStaleFramesAndStaleStart() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 2)
        #expect(gate.phase == .positioning)
        #expect(!gate.isReady)
        #expect(gate.result == nil)
    }

    @Test func rejectsClosedTurnedAndMisplacedHands() {
        var gate = HandCalibrationQualityGate()
        gate.update(frame: frame(0, open: false), now: 0)
        #expect(gate.guidance == .openHand)
        gate.update(frame: frame(1, facing: false), now: 1)
        #expect(gate.guidance == .faceCamera)
        gate.update(frame: frame(2, inside: false), now: 2)
        #expect(gate.guidance == .insideGuide)
        #expect(!gate.isReady)
        #expect(gate.result == nil)
    }

    @Test func closingHandDuringCountdownRequiresRetry() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        gate.update(frame: frame(1.1, open: false), now: 1.1)
        #expect(gate.phase == .retry)
        #expect(gate.guidance == .openHand)
        #expect(gate.result == nil)
    }

    @Test func leavingGuideDuringCollectionCannotSave() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        for i in 31...135 {
            let time = Double(i) / 30
            gate.update(frame: frame(time), now: time)
        }
        gate.update(frame: frame(4.6, inside: false), now: 4.6)
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func duplicateFramesCannotCreateReadiness() {
        var gate = HandCalibrationQualityGate()
        for i in 0...30 {
            gate.update(frame: frame(0), now: Double(i) / 30)
        }
        #expect(!gate.isReady)
        #expect(gate.result == nil)
    }

    @Test func countdownLossRequiresRetry() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        gate.update(frame: frame(1.1, detected: false), now: 1.1)
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func collectionLossCannotSavePartialCalibration() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        for i in 31...135 {
            let time = Double(i) / 30
            gate.update(frame: frame(time), now: time)
        }
        #expect(gate.phase == .collecting)
        gate.update(frame: frame(4.6, visible: false), now: 4.6)
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func staleCameraDuringCollectionRequiresRetry() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        for i in 31...135 {
            let time = Double(i) / 30
            gate.update(frame: frame(time), now: time)
        }
        gate.update(frame: frame(4.5), now: 5)
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func gapsCannotBeFilledByPolling() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        gate.update(frame: frame(1.4), now: 1.4)
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func excessiveVariationFailsFinalQualityCheck() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        for i in 31...181 {
            let time = Double(i) / 30
            let scale = time < 4 ? 0.12 : (i.isMultiple(of: 2) ? 0.095 : 0.145)
            gate.update(frame: frame(time, scale: scale), now: time)
        }
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func changingCameraDistanceDuringCountdownFails() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        gate.update(frame: frame(1.1, scale: 0.19), now: 1.1)
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }

    @Test func rejectsInvalidNumbersAndFutureTimestamps() {
        var gate = HandCalibrationQualityGate()
        for scale in [Double.nan, .infinity, 0, -0.1] {
            gate.update(frame: frame(0, scale: scale), now: 0)
            #expect(!gate.isReady)
        }
        gate.update(frame: frame(10), now: 1)
        #expect(gate.guidance == .showHand)
        #expect(gate.result == nil)
    }

    @Test func retryClearsAttemptButCanSucceedAgain() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        gate.update(frame: nil, now: 1.1)
        #expect(gate.phase == .retry)
        gate.reset()
        #expect(gate.phase == .positioning)
        #expect(gate.result == nil)
        for i in 0...30 {
            let time = 2 + Double(i) / 30
            gate.update(frame: frame(time), now: time)
        }
        #expect(gate.isReady)
    }

    @Test func sparseFramesFailEvenWhenSpanIsLongEnough() {
        var gate = prepared()
        gate.start(frame: frame(1), now: 1)
        for i in 1...26 {
            let time = 1 + Double(i) * 0.2
            gate.update(frame: frame(time), now: time)
        }
        #expect(gate.phase == .retry)
        #expect(gate.result == nil)
    }
}

struct HandCalibrationPoseTests {
    private func finger(_ base: CGPoint, _ tip: CGPoint) -> HandCalibrationPose.Finger {
        .init(base: base,
              middle: CGPoint(x: base.x + (tip.x - base.x) * 0.45, y: base.y + (tip.y - base.y) * 0.45),
              distal: CGPoint(x: base.x + (tip.x - base.x) * 0.75, y: base.y + (tip.y - base.y) * 0.75),
              tip: tip)
    }

    private var openPose: HandCalibrationPose {
        .init(wrist: CGPoint(x: 0.5, y: 0.20),
              thumb: finger(CGPoint(x: 0.43, y: 0.245), CGPoint(x: 0.22, y: 0.38)),
              fingers: [
                finger(CGPoint(x: 0.40, y: 0.31), CGPoint(x: 0.37, y: 0.58)),
                finger(CGPoint(x: 0.50, y: 0.32), CGPoint(x: 0.50, y: 0.65)),
                finger(CGPoint(x: 0.60, y: 0.315), CGPoint(x: 0.63, y: 0.60)),
                finger(CGPoint(x: 0.68, y: 0.30), CGPoint(x: 0.75, y: 0.49))
              ], imageAspectRatio: 9.0 / 16.0)
    }

    private func transform(_ pose: HandCalibrationPose, _ map: (CGPoint) -> CGPoint) -> HandCalibrationPose {
        func mapped(_ f: HandCalibrationPose.Finger) -> HandCalibrationPose.Finger {
            .init(base: map(f.base), middle: map(f.middle), distal: map(f.distal), tip: map(f.tip))
        }
        return .init(wrist: map(pose.wrist), thumb: mapped(pose.thumb),
                     fingers: pose.fingers.map(mapped), imageAspectRatio: pose.imageAspectRatio)
    }

    @Test(arguments: [false, true])
    func openHandsPassForEitherSide(mirrored: Bool) {
        let pose = mirrored ? transform(openPose) { CGPoint(x: 1 - $0.x, y: $0.y) } : openPose
        #expect(pose.isFullyVisible)
        #expect(pose.isInsideGuide)
        #expect(pose.isFacingCamera)
        #expect(pose.hasOpenFingers)
    }

    @Test func fistAndOneBentFingerAreRejected() {
        let pose = openPose
        func folded(_ f: HandCalibrationPose.Finger) -> HandCalibrationPose.Finger {
            .init(base: f.base, middle: CGPoint(x: f.base.x, y: f.base.y + 0.1),
                  distal: CGPoint(x: f.base.x, y: f.base.y + 0.06),
                  tip: CGPoint(x: f.base.x, y: f.base.y + 0.02))
        }
        let fist = HandCalibrationPose(wrist: pose.wrist, thumb: pose.thumb,
                                       fingers: pose.fingers.map(folded), imageAspectRatio: pose.imageAspectRatio)
        #expect(!fist.hasOpenFingers)
        var fingers = pose.fingers
        fingers[2] = folded(fingers[2])
        #expect(!HandCalibrationPose(wrist: pose.wrist, thumb: pose.thumb,
                                    fingers: fingers, imageAspectRatio: pose.imageAspectRatio).hasOpenFingers)
    }

    @Test func tuckedThumbIsRejected() {
        let pose = openPose
        let tucked = finger(pose.thumb.base, CGPoint(x: 0.46, y: 0.31))
        #expect(!HandCalibrationPose(wrist: pose.wrist, thumb: tucked,
                                    fingers: pose.fingers, imageAspectRatio: pose.imageAspectRatio).hasOpenFingers)
    }

    @Test func edgeOnHandIsRejected() {
        let pose = transform(openPose) { CGPoint(x: 0.5 + ($0.x - 0.5) * 0.12, y: $0.y) }
        #expect(pose.isFullyVisible)
        #expect(!pose.isFacingCamera)
    }

    @Test func guideRejectsOffCentreAndClippedHands() {
        let outside = transform(openPose) { CGPoint(x: $0.x + 0.16, y: $0.y) }
        #expect(outside.isFullyVisible)
        #expect(!outside.isInsideGuide)
        let clipped = transform(openPose) { CGPoint(x: $0.x + 0.3, y: $0.y) }
        #expect(!clipped.isFullyVisible)
    }

    @Test func shapeChecksAreIndependentOfImageAspectRatio() {
        let pose = openPose
        let adjusted = transform(pose) { CGPoint(x: 0.5 + ($0.x - 0.5) * pose.imageAspectRatio, y: $0.y) }
        let squareImage = HandCalibrationPose(wrist: adjusted.wrist, thumb: adjusted.thumb,
                                             fingers: adjusted.fingers, imageAspectRatio: 1)
        #expect(squareImage.hasOpenFingers == pose.hasOpenFingers)
        #expect(squareImage.isFacingCamera == pose.isFacingCamera)
    }

    @Test func invalidAndIncompleteLandmarksFailClosed() {
        let pose = openPose
        let invalid = transform(pose) { CGPoint(x: .nan, y: $0.y) }
        #expect(!invalid.hasOpenFingers)
        #expect(!invalid.isFacingCamera)
        #expect(!invalid.isFullyVisible)
        let incomplete = HandCalibrationPose(wrist: pose.wrist, thumb: pose.thumb,
                                             fingers: Array(pose.fingers.prefix(3)), imageAspectRatio: pose.imageAspectRatio)
        #expect(!incomplete.hasOpenFingers)
        #expect(!incomplete.isFullyVisible)
    }
}

final class HandCalibrationGuideRenderingTests: XCTestCase {
    @MainActor
    func testGuideFitsPortraitPreviewInBothStates() throws {
        for ready in [false, true] {
            let content = CalibrationPositionGuide(isReady: ready)
                .frame(width: 180, height: 320)
                .background(Color.black)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 180)
            XCTAssertEqual(image.size.height, 320)
            let attachment = XCTAttachment(image: image)
            attachment.name = ready ? "Calibration guide ready" : "Calibration guide positioning"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
