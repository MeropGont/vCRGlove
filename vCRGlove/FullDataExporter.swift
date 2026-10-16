import Foundation
import CryptoKit
import SwiftUI
import UIKit

enum FullDataExporter {
    static let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent("vcr-full-exports", isDirectory: true)

    struct Package: Sendable, Identifiable {
        let directory: URL
        let archive: URL
        let missingVideoCount: Int
        var id: URL { archive }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    struct FileRecord: Codable {
        let path: String
        let bytes: Int64
        let sha256: String
    }

    struct Manifest: Codable {
        let formatVersion: Int
        let startedAt: Date
        let completedAt: Date
        let appVersion: String
        let timeZone: String
        let files: [FileRecord]
        let absentFiles: [String]
        let missingReferencedVideos: [String]
    }

    // Export only app-owned study settings, never credentials or the entire preferences domain.
    static let settingsKeys = [
        "patientID", "studyStartDate", "patientStudyNotes", "deviceAssignmentNotes", "protocolNotes",
        StimulationProfileStore.key, "calibratedHandScale", "vcrSessionPlan",
        "vcrSplitCompletionDate", "vcrSplitCompletionCount", "vcrFourHourCompletionDate",
        "appLanguage", "appFontSize", "notificationsEnabled", "vcrReminderEnabled",
        "vcrReminderHour", "vcrReminderMinute", "journalReminderEnabled", "journalReminderHour",
        "journalReminderMinute", "journalReminderWeekdays", "taskReminderEnabled",
        "taskReminderHour", "taskReminderMinute", "taskReminderWeekdays", "quietHoursEnabled",
        "quietStartHour", "quietEndHour", "vcr.uploader.pending"
    ]

    @MainActor
    static func prepare(journal: JournalStore? = nil, tasks: TaskSessionStore = .shared,
                        events: EventStore = .shared, defaults: UserDefaults = .standard) async throws -> Package {
        let directory = try makeDirectory()
        do {
            let root = directory.appendingPathComponent("vCRGlove-data", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let startedAt = Date()
            try Data(archiveReadme.utf8).write(to: root.appendingPathComponent("README.txt"), options: .atomic)
            let journalData = try (journal ?? .shared).exportSnapshot()
            let settings = settingsKeys.reduce(into: [String: Any]()) { result, key in
                result[key] = defaults.object(forKey: key)
            }
            let settingsData = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            try settingsData.write(to: root.appendingPathComponent("study-settings.plist"), options: .atomic)
            var absent = [String]()
            let journalPath = "journal/journal_entries.json"
            if let journalData {
                let destination = root.appendingPathComponent(journalPath)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try journalData.write(to: destination, options: .atomic)
            } else { absent.append(journalPath) }

            // The movement queue also owns accepted movie copies and video deletion.
            absent += try await tasks.copyExportSnapshot(to: root)
            try Task.checkCancellation()
            absent += try await events.copyExportSnapshot(to: root)
            try Task.checkCancellation()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let package = try await Task.detached(priority: .utility) {
                try finish(directory: directory, root: root, startedAt: startedAt,
                           appVersion: "\(version) (\(build))", absent: absent)
            }.value
            try Task.checkCancellation()
            return package
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func makeDirectory(parent: URL = temporaryRoot) throws -> URL {
        let directory = parent.appendingPathComponent("vcr-full-export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        var protected = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        return directory
    }

    /// Remove only our unfinished share copies on the next launch, never original study data.
    static func removeInterruptedExports(parent: URL = temporaryRoot) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix("vcr-full-export-") {
            let suffix = String(file.lastPathComponent.dropFirst("vcr-full-export-".count))
            if UUID(uuidString: suffix) != nil { try? FileManager.default.removeItem(at: file) }
        }
    }

    private static let archiveReadme = """
    vCRGlove local study-data export, format version 1

    journal/journal_entries.json: Original journal JSON array. Dates are Foundation
    numeric seconds since 2001-01-01 UTC, not Unix seconds.
    logs/events.jsonl: Original stimulation and app events; ISO-8601 timestamps.
    logs/handshake.jsonl: Watch connection log, if present.
    tasks/sessions.jsonl: Original movement sessions, raw samples, metrics and context;
    ISO-8601 timestamps. Trials use startedAt for their recording time.
    tasks/videos/: All retained private task movies, including any orphaned movies.
    study-settings.plist: App-owned study/profile/preferences and pending upload data.
    Data-valued preferences (including the stimulation profile) are base64 in this plist.
    manifest.json: UTC export interval, app version, original time zone, file sizes and
    SHA-256 hashes (excluding the manifest itself), absent stores and missing video files.

    Stores are captured sequentially after their queued writes, not as one global
    transaction. Unsaved drafts and in-progress recordings are not included.
    Unknown fields and malformed raw records are preserved, not repaired or omitted.
    Previously generated exports, demo videos, passwords and system settings are excluded.
    No data is deleted or automatically uploaded. This ZIP is not password-encrypted.
    It contains sensitive data; use only an institutionally approved transfer destination.
    Verify files against the manifest before treating the copy as a backup.
    """

    /// Missing storage is legitimate on a fresh install; unreadable/symlinked storage is not.
    @discardableResult
    static func copyFile(_ source: URL, to destination: URL) throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do { attributes = try FileManager.default.attributesOfItem(atPath: source.path) }
        catch CocoaError.fileReadNoSuchFile { return false }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
        return true
    }

    static func finish(directory: URL, root: URL, startedAt: Date, appVersion: String,
                       absent: [String]) throws -> Package {
        let fileManager = FileManager.default
        var enumerationError: Error?
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
            errorHandler: { _, error in enumerationError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var records = [FileRecord]()
        for case let file as URL in enumerator {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256()
                var bytes: Int64 = 0
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    hash.update(data: data)
                    bytes += Int64(data.count)
                }
                records.append(FileRecord(path: String(file.path.dropFirst(root.path.count + 1)), bytes: bytes,
                    sha256: hash.finalize().map { String(format: "%02x", $0) }.joined()))
            }
        }
        if let enumerationError { throw enumerationError }
        let missing = try missingVideos(in: root)
        let manifest = Manifest(formatVersion: 1, startedAt: startedAt, completedAt: Date(),
            appVersion: appVersion, timeZone: TimeZone.current.identifier,
            files: records.sorted { $0.path < $1.path }, absentFiles: absent.sorted(), missingReferencedVideos: missing)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: root.appendingPathComponent("manifest.json"), options: .atomic)
        let stamp = ISO8601DateFormatter().string(from: startedAt).replacingOccurrences(of: ":", with: "-")
        let archive = directory.appendingPathComponent("vCRGlove-data-\(stamp).zip")
        var coordinationError: NSError?
        var copyError: Error?
        // Foundation creates a ZIP for a directory. Its temporary URL is valid only inside the accessor.
        NSFileCoordinator().coordinate(readingItemAt: root, options: .forUploading, error: &coordinationError) { zip in
            do { try fileManager.copyItem(at: zip, to: archive) }
            catch { copyError = error }
        }
        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
        guard fileManager.fileExists(atPath: archive.path) else { throw CocoaError(.fileWriteUnknown) }
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: archive.path)
        try fileManager.removeItem(at: root)
        return Package(directory: directory, archive: archive, missingVideoCount: missing.count)
    }

    private static func missingVideos(in root: URL) throws -> [String] {
        let source = root.appendingPathComponent("tasks/sessions.jsonl")
        guard FileManager.default.fileExists(atPath: source.path) else { return [] }
        var missing = Set<String>()
        for line in try Data(contentsOf: source).split(separator: 0x0A) {
            // Preserve malformed/unknown records verbatim; do not decode/rewrite the session model.
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let trials = object["trials"] as? [[String: Any]] else { continue }
            for trial in trials {
                guard let video = trial["video"] as? [String: Any], let name = video["fileName"] as? String else { continue }
                if name != URL(fileURLWithPath: name).lastPathComponent
                    || !FileManager.default.fileExists(atPath: root.appendingPathComponent("tasks/videos/\(name)").path) {
                    missing.insert(name)
                }
            }
        }
        return missing.sorted()
    }
}

struct FullDataShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { completion() }
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
