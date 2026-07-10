//
//  TaskSessionExporterTests.swift
//  vCRGloveTests
//
//  Task F: exports must be well-formed (JSON round-trips, CSV has the right
//  shape) and old JSONL recordings without the new sync field must still decode.
//

import Testing
import Foundation
@testable import vCRGlove

struct TaskSessionExporterTests {

    private func makeSessions() -> [MovementSession] {
        var gen = SyntheticSignalGenerator(params: .healthy, seed: 5)
        let samples = gen.generate()
        let metrics = MovementAnalyzer().analyze(samples)
        let trial = Trial(taskType: .fingerTap, side: .right, source: .synthetic,
                          stopCondition: .tenReps,
                          startUptime: ProcessInfo.processInfo.systemUptime,
                          samples: samples, metrics: metrics)
        return [MovementSession(patientId: "test-01",
                                stimulationContext: .preStim,
                                trials: [trial])]
    }

    @Test func jsonExportRoundTrips() throws {
        let sessions = makeSessions()
        let url = try TaskSessionExporter.exportJSON(sessions)
        defer { try? FileManager.default.removeItem(at: url) }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([MovementSession].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded[0].patientId == "test-01")
        #expect(decoded[0].trials[0].samples == sessions[0].trials[0].samples)
        #expect(decoded[0].trials[0].startUptime != nil)
    }

    @Test func metricsCSVHasHeaderAndOneRowPerTrial() throws {
        let sessions = makeSessions()
        let url = try TaskSessionExporter.exportMetricsCSV(sessions)
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 2) // header + 1 trial
        #expect(lines[0].hasPrefix("session_id,patient_id,session_date,context,trial_id,task"))
        // Every row must have as many columns as the header.
        let headerCols = lines[0].split(separator: ",", omittingEmptySubsequences: false).count
        let rowCols = lines[1].split(separator: ",", omittingEmptySubsequences: false).count
        #expect(rowCols == headerCols)
    }

    @Test func samplesCSVHasOneRowPerSample() throws {
        let sessions = makeSessions()
        let url = try TaskSessionExporter.exportSamplesCSV(sessions)
        defer { try? FileManager.default.removeItem(at: url) }

        let lines = try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == sessions[0].trials[0].samples.count + 1)
    }

    @Test func emptyExportThrows() throws {
        #expect(throws: TaskSessionExporter.ExportError.self) {
            try TaskSessionExporter.exportJSON([])
        }
    }

    /// Recordings saved before the `startUptime` field existed must still decode.
    @Test func trialWithoutStartUptimeStillDecodes() throws {
        let legacyJSON = """
        {"id":"11111111-1111-1111-1111-111111111111","taskType":"3.4","side":"right",
         "source":"synthetic","stopCondition":{"mode":"repetitions","targetReps":10,"targetDuration":15},
         "startedAt":"2026-07-01T10:00:00Z","samples":[{"t":0,"value":0.1}],
         "metrics":{"cycleCount":0,"frequencyHz":0,"meanAmplitude":0,"amplitudeDecrementSlope":0,
                    "rhythmCV":0,"pauseCount":0,"onsetLatencySec":0,"qualityIndex":0}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let trial = try decoder.decode(Trial.self, from: Data(legacyJSON.utf8))
        #expect(trial.startUptime == nil)
        #expect(trial.taskType == .fingerTap)
    }
}
