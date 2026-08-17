//
//  TaskSessionExporter.swift
//  vCRGlove
//
//  Clinic-facing export of movement task sessions (Task F):
//    • JSON  — full sessions (raw samples + metrics), pretty-printed
//    • CSV   — metrics.csv (one row per trial) and samples.csv (one row per
//              raw sample), ready for R / Python / REDCap-style pipelines
//
//  Files are written to Documents/vcr/tasks/exports/ so they are reachable
//  via the Files app (file sharing is enabled in Info.plist) and via ShareLink.
//

import Foundation

enum TaskSessionExporter {

    enum ExportError: LocalizedError {
        case nothingToExport
        var errorDescription: String? { "There are no recorded sessions to export." }
    }

    // MARK: - Public API

    /// Full sessions (raw + metrics) as a pretty-printed JSON array.
    static func exportJSON(_ sessions: [MovementSession]) throws -> URL {
        guard !sessions.isEmpty else { throw ExportError.nothingToExport }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        return try write(data, name: "sessions", ext: "json")
    }

    /// One row per trial with all metrics — the clinic's primary table.
    static func exportMetricsCSV(_ sessions: [MovementSession]) throws -> URL {
        guard !sessions.isEmpty else { throw ExportError.nothingToExport }
        var rows = [csvHeaderMetrics]
        for s in sessions {
            for t in s.trials {
                rows.append([
                    s.id.uuidString,
                    quote(s.patientId),
                    iso8601(s.date),
                    s.stimulationContext.rawValue,
                    t.id.uuidString,
                    t.taskType.rawValue,
                    t.side.rawValue,
                    t.source.rawValue,
                    t.stopCondition.mode.rawValue,
                    iso8601(t.startedAt),
                    t.startUptime.map { String($0) } ?? "",
                    String(t.samples.count),
                    String(t.samples.last?.t ?? 0),
                    String(t.metrics.cycleCount),
                    String(t.metrics.frequencyHz),
                    String(t.metrics.meanAmplitude),
                    String(t.metrics.amplitudeDecrementSlope),
                    String(t.metrics.rhythmCV),
                    String(t.metrics.pauseCount),
                    String(t.metrics.onsetLatencySec),
                    String(t.metrics.qualityIndex)
                ].joined(separator: ","))
            }
        }
        return try write(Data(rows.joined(separator: "\n").utf8), name: "metrics", ext: "csv")
    }

    /// One row per raw sample — for signal-level re-analysis.
    static func exportSamplesCSV(_ sessions: [MovementSession]) throws -> URL {
        guard !sessions.isEmpty else { throw ExportError.nothingToExport }
        var rows = ["session_id,trial_id,task,side,t_sec,value"]
        for s in sessions {
            for t in s.trials {
                for sample in t.samples {
                    rows.append("\(s.id.uuidString),\(t.id.uuidString),\(t.taskType.rawValue),\(t.side.rawValue),\(sample.t),\(sample.value)")
                }
            }
        }
        return try write(Data(rows.joined(separator: "\n").utf8), name: "samples", ext: "csv")
    }

    // MARK: - Helpers

    private static let csvHeaderMetrics = [
        "session_id", "patient_id", "session_date", "context",
        "trial_id", "task", "side", "source", "stop_mode",
        "started_at", "start_uptime_sec", "sample_count", "duration_sec",
        "cycle_count", "frequency_hz", "mean_amplitude",
        "amplitude_decrement_slope", "rhythm_cv", "pause_count",
        "onset_latency_sec", "quality_index"
    ].joined(separator: ",")

    private static func write(_ data: Data, name: String, ext: String) throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("vcr/tasks/exports", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let stamp = fileTimestamp.string(from: Date())
        let url = dir.appendingPathComponent("\(name)-\(stamp).\(ext)")
        try data.write(to: url, options: .atomic)

        EventStore.shared.append(
            type: "TASK", tag: "export",
            message: "Exported \(url.lastPathComponent)",
            details: ["bytes": "\(data.count)"])
        return url
    }

    private static let fileTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func iso8601(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }

    /// Minimal CSV quoting for free-text fields (patient IDs are pseudonyms,
    /// but be safe against commas/quotes).
    private static func quote(_ s: String) -> String {
        "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
