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
        case noAngleRecordings
        var errorDescription: String? {
            switch self {
            case .nothingToExport: return "There are no recorded sessions to export."
            case .noAngleRecordings: return "No finger-tapping angle recordings are available to export."
            }
        }
    }

    // MARK: - Public API

    /// Full sessions (raw + metrics) as a pretty-printed JSON array.
    static func exportJSON(_ sessions: [MovementSession], directory: URL? = nil) throws -> URL {
        guard !sessions.isEmpty || directory != nil else { throw ExportError.nothingToExport }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sessions)
        return try write(data, name: "sessions", ext: "json", directory: directory)
    }

    /// One row per trial with all metrics — the clinic's primary table.
    static func exportMetricsCSV(_ sessions: [MovementSession], directory: URL? = nil) throws -> URL {
        guard !sessions.isEmpty || directory != nil else { throw ExportError.nothingToExport }
        var rows = [csvHeaderMetrics]
        for s in sessions {
            for t in s.trials {
                var fields: [String] = [
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
                ]
                let medicationFields: [String] = [
                    t.medicationTiming?.status.rawValue ?? "",
                    t.medicationTiming?.takenAt.map(iso8601) ?? "",
                    t.medicationTiming?.elapsedSeconds(at: t.startedAt).map { String($0) } ?? "",
                    t.medicationTiming.map { iso8601($0.confirmedAt) } ?? "",
                    t.medicationTiming?.journalEntryID?.uuidString ?? "",
                    quote(t.medicationTiming?.medicationName ?? ""),
                    quote(t.medicationTiming?.medicationDose ?? "")
                ]
                fields.append(contentsOf: medicationFields)
                fields.append(quote(t.measurementVersion ?? ""))
                rows.append(fields.joined(separator: ","))
            }
        }
        return try write(Data(rows.joined(separator: "\n").utf8), name: "metrics", ext: "csv", directory: directory)
    }

    /// One row per raw sample — for signal-level re-analysis.
    static func exportSamplesCSV(_ sessions: [MovementSession], directory: URL? = nil) throws -> URL {
        guard !sessions.isEmpty || directory != nil else { throw ExportError.nothingToExport }
        var rows = ["session_id,trial_id,task,side,t_sec,value"]
        for s in sessions {
            for t in s.trials {
                for sample in t.samples {
                    rows.append("\(s.id.uuidString),\(t.id.uuidString),\(t.taskType.rawValue),\(t.side.rawValue),\(sample.t),\(sample.value)")
                }
            }
        }
        return try write(Data(rows.joined(separator: "\n").utf8), name: "samples", ext: "csv", directory: directory)
    }

    /// Separate units/schema: existing raw-sample and metrics CSVs stay unchanged.
    static func exportFingerTappingAnglesCSV(_ sessions: [MovementSession], directory: URL? = nil) throws -> URL {
        guard !sessions.isEmpty || directory != nil else { throw ExportError.nothingToExport }
        var rows = ["session_id,trial_id,task,side,t_sec,angle_degrees,angle_valid,measurement_version,unit,time_reference"]
        var hasRecording = false
        for session in sessions {
            for trial in session.trials {
                guard let recording = trial.fingerTappingAngle else { continue }
                hasRecording = true
                for sample in recording.samples {
                    let fields = [session.id.uuidString, trial.id.uuidString, trial.taskType.rawValue,
                        trial.side.rawValue, String(sample.t), sample.degrees.map { String($0) } ?? "",
                        sample.degrees == nil ? "false" : "true", quote(recording.measurementVersion),
                        quote(recording.unit), quote(recording.timeReference)]
                    rows.append(fields.joined(separator: ","))
                }
            }
        }
        guard hasRecording || directory != nil else { throw ExportError.noAngleRecordings }
        return try write(Data(rows.joined(separator: "\n").utf8), name: "finger-tapping-angles", ext: "csv", directory: directory)
    }

    // MARK: - Helpers

    private static let csvHeaderMetrics = [
        "session_id", "patient_id", "session_date", "context",
        "trial_id", "task", "side", "source", "stop_mode",
        "started_at", "start_uptime_sec", "sample_count", "duration_sec",
        "cycle_count", "frequency_hz", "mean_amplitude",
        "amplitude_decrement_slope", "rhythm_cv", "pause_count",
        "onset_latency_sec", "quality_index",
        "medication_status", "medication_taken_at", "seconds_since_medication",
        "medication_confirmed_at", "medication_journal_entry_id", "medication_name", "medication_dose",
        "measurement_version"
    ].joined(separator: ",")

    private static func write(_ data: Data, name: String, ext: String, directory: URL? = nil) throws -> URL {
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(name).\(ext)")
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return url
        }
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
