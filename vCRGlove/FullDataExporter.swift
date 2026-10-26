import Foundation
import CryptoKit
import SwiftUI
import UIKit

private struct StudyExportBlockedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var studyExportBlocked: Bool {
        get { self[StudyExportBlockedKey.self] }
        set { self[StudyExportBlockedKey.self] = newValue }
    }
}

struct StudyExportSelection: Sendable, Codable {
    enum FileGroup: String, CaseIterable, Codable, Identifiable {
        case sessions, metrics, samples, angles, journal, events, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sessions: return "Session JSON"
            case .metrics: return "Metrics CSV"
            case .samples: return "Raw samples CSV"
            case .angles: return "Tapping angles CSV"
            case .journal: return "Journal"
            case .events: return "Stimulation and event logs"
            case .settings: return "Study settings"
            }
        }
    }
    var groups = Set(FileGroup.allCases)
    var sessionIDs: Set<UUID>?
    var interval: DateInterval?
    var calendar = Calendar.current
    var isScoped: Bool { sessionIDs != nil || interval != nil }

    func includesSession(id: UUID, date: Date) -> Bool {
        (sessionIDs?.contains(id) ?? true) && includesDate(date)
    }

    func includesDate(_ date: Date) -> Bool {
        interval.map { date >= $0.start && date < $0.end } ?? true
    }

    func includesRecord(_ date: Date, sessionDays: Set<Date>) -> Bool {
        includesDate(date) && (sessionIDs == nil || sessionDays.contains(calendar.startOfDay(for: date)))
    }
}

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
        var selection: StudyExportSelection? = nil
        var selectedSessionIDs: [UUID]? = nil
        var videosIncluded: Bool? = nil
    }

    // Export only app-owned study settings, never credentials or the entire preferences domain.
    static let settingsKeys = [
        "patientID", "studyStartDate", "patientStudyNotes", "deviceAssignmentNotes", "protocolNotes",
        "movementTrendIdentityLinks", MovementVideoPreference.key, RoutineMilestoneLedger.enabledKey,
        "reminderSoundEnabled",
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

    /// A snapshot-backed, non-video package. Sources are never filtered or rewritten in place.
    @MainActor
    static func prepare(selection: StudyExportSelection, journal: JournalStore? = nil,
                        tasks: TaskSessionStore = .shared, events: EventStore = .shared,
                        defaults: UserDefaults = .standard) async throws -> Package {
        let directory = try makeDirectory()
        do {
            guard !selection.groups.isEmpty else { throw SelectionError.noFiles }
            let startedAt = Date()
            let snapshot = directory.appendingPathComponent("snapshot", isDirectory: true)
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
            let needsMovement = !selection.groups.isDisjoint(with: [.sessions, .metrics, .samples, .angles])
                || selection.sessionIDs != nil
            var absent = [String]()
            if needsMovement { absent += try await tasks.copyExportSnapshot(to: snapshot, includeVideos: false) }
            if selection.groups.contains(.events) { absent += try await events.copyExportSnapshot(to: snapshot) }
            let journalData = selection.groups.contains(.journal) ? try (journal ?? .shared).exportSnapshot() : nil
            if selection.groups.contains(.journal) && journalData == nil { absent.append("journal/journal_entries.json") }
            let keys = selection.isScoped ? settingsKeys.filter { $0 != "vcr.uploader.pending" } : settingsKeys
            let settings = keys.reduce(into: [String: Any]()) { $0[$1] = defaults.object(forKey: $1) }
            let settingsData = try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            try Task.checkCancellation()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
            let package = try await Task.detached(priority: .utility) {
                try Task.checkCancellation()
                let root = directory.appendingPathComponent("vCRGlove-data", isDirectory: true)
                try buildSelectedFiles(selection: selection, snapshot: snapshot, root: root,
                    journalData: journalData, settingsData: settingsData)
                let ids = try selectedSessionObjects(in: snapshot, selection: selection).compactMap {
                    ($0["id"] as? String).flatMap(UUID.init(uuidString:))
                }
                try FileManager.default.removeItem(at: snapshot)
                try Task.checkCancellation()
                return try finish(directory: directory, root: root, startedAt: startedAt,
                    appVersion: "\(version) (\(build))", absent: absent,
                    selection: selection, selectedSessionIDs: ids)
            }.value
            try Task.checkCancellation()
            return package
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    enum SelectionError: LocalizedError {
        case noFiles, noSessions, unreadableRecord
        var errorDescription: String? {
            switch self {
            case .noFiles: return "Choose at least one data type."
            case .noSessions: return "No sessions match this selection."
            case .unreadableRecord: return "Some records could not be read safely. No package was shared."
            }
        }
    }

    static func parsedDate(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func objects(in data: Data) throws -> [[String: Any]] {
        try data.split(separator: 0x0A).filter { !$0.allSatisfy { $0 == 0x20 || $0 == 0x0D || $0 == 0x09 } }.map {
            guard let object = try JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] else {
                throw SelectionError.unreadableRecord
            }
            return object
        }
    }

    private static func selectedSessionObjects(in snapshot: URL, selection: StudyExportSelection) throws -> [[String: Any]] {
        let url = snapshot.appendingPathComponent("tasks/sessions.jsonl")
        guard FileManager.default.fileExists(atPath: url.path) else {
            if selection.sessionIDs != nil { throw SelectionError.noSessions }
            return []
        }
        let records = try objects(in: Data(contentsOf: url))
        let result = try records.filter { record in
            guard let text = record["id"] as? String, let id = UUID(uuidString: text),
                  let date = parsedDate(record["date"]) else { throw SelectionError.unreadableRecord }
            return selection.includesSession(id: id, date: date)
        }
        if let ids = selection.sessionIDs,
           ids.isEmpty || Set(result.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) }) != ids {
            throw SelectionError.noSessions
        }
        return result
    }

    /// Pure file assembly used by the package writer and completeness tests.
    static func buildSelectedFiles(selection: StudyExportSelection, snapshot: URL, root: URL,
                                   journalData: Data?, settingsData: Data) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        func write(_ data: Data, _ path: String) throws {
            try Task.checkCancellation()
            let url = root.appendingPathComponent(path)
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        }
        let records = try selectedSessionObjects(in: snapshot, selection: selection)
        let days = Set(records.compactMap { parsedDate($0["date"]) }.map { selection.calendar.startOfDay(for: $0) })
        let json = try JSONSerialization.data(withJSONObject: records, options: [.prettyPrinted, .sortedKeys])
        if selection.groups.contains(.sessions) {
            try write(json, "tasks/sessions.json")
            let lines = try records.reduce(into: Data()) { data, record in
                data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
                data.append(0x0A)
            }
            try write(lines, "tasks/sessions.jsonl")
        }
        if !selection.groups.isDisjoint(with: [.metrics, .samples, .angles]) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let sessions: [MovementSession]
            do { sessions = try decoder.decode([MovementSession].self, from: json) }
            catch { throw SelectionError.unreadableRecord }
            let directory = root.appendingPathComponent("tasks")
            if selection.groups.contains(.metrics) { _ = try TaskSessionExporter.exportMetricsCSV(sessions, directory: directory) }
            if selection.groups.contains(.samples) { _ = try TaskSessionExporter.exportSamplesCSV(sessions, directory: directory) }
            if selection.groups.contains(.angles) { _ = try TaskSessionExporter.exportFingerTappingAnglesCSV(sessions, directory: directory) }
        }
        if selection.groups.contains(.journal), let journalData {
            if selection.isScoped {
                guard let entries = try JSONSerialization.jsonObject(with: journalData) as? [[String: Any]] else {
                    throw SelectionError.unreadableRecord
                }
                let filtered = try entries.filter { entry in
                    guard let seconds = entry["date"] as? Double, seconds.isFinite else { throw SelectionError.unreadableRecord }
                    return selection.includesRecord(Date(timeIntervalSinceReferenceDate: seconds), sessionDays: days)
                }
                try write(JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted, .sortedKeys]), "journal/journal_entries.json")
            } else { try write(journalData, "journal/journal_entries.json") }
        }
        if selection.groups.contains(.events) {
            for name in ["events.jsonl", "handshake.jsonl"] {
                let url = snapshot.appendingPathComponent("logs/\(name)")
                guard manager.fileExists(atPath: url.path) else { continue }
                let raw = try Data(contentsOf: url)
                if selection.isScoped {
                    let filtered = try objects(in: raw).filter { record in
                        guard let date = parsedDate(record["ts"] ?? record["ts_phone"]) else { throw SelectionError.unreadableRecord }
                        return selection.includesRecord(date, sessionDays: days)
                    }
                    let data = try filtered.reduce(into: Data()) { data, record in
                        data.append(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]))
                        data.append(0x0A)
                    }
                    try write(data, "logs/\(name)")
                } else { try write(raw, "logs/\(name)") }
            }
        }
        if selection.groups.contains(.settings) { try write(settingsData, "study-settings.plist") }
        try write(Data(selectedReadme.utf8), "README.txt")
    }

    private static let selectedReadme = """
    vCRGlove selected study-data export, format version 2. No video files included.
    manifest.json records selected data types, session IDs, time zone, calendar and
    optional date interval [start, end), plus file sizes and SHA-256 checksums.
    Sessions are selected by session start date; all their trials are retained.
    Manual session selection limits journal/events to the selected sessions' local
    calendar days. Date-range selection limits journal/events to that exact range.
    Journal dates use seconds since 2001-01-01 UTC. Session/event dates use ISO-8601.
    Session JSON preserves unknown fields and video metadata, not the movie files.
    CSV tables are derived using the app's existing schema, without recalculating metrics.
    Empty CSVs contain headers. Settings are current, not historical; scoped exports
    exclude pending uploader payloads. Missing stores are listed in the manifest.
    Stores are snapshotted sequentially; drafts and active recordings are not included.
    This ZIP is not encrypted. Share only to an approved destination. Nothing is
    automatically sent, deleted, or marked as received by the study team.
    """

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
    It may include explicit local test-session display links; original session IDs are unchanged.
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
                       absent: [String], selection: StudyExportSelection? = nil,
                       selectedSessionIDs: [UUID]? = nil) throws -> Package {
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
        let missing = selection == nil ? try missingVideos(in: root) : []
        let manifest = Manifest(formatVersion: selection == nil ? 1 : 2, startedAt: startedAt, completedAt: Date(),
            appVersion: appVersion, timeZone: TimeZone.current.identifier,
            files: records.sorted { $0.path < $1.path }, absentFiles: absent.sorted(), missingReferencedVideos: missing,
            selection: selection, selectedSessionIDs: selectedSessionIDs, videosIncluded: selection == nil)
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

@MainActor
final class StudyDataExportController: ObservableObject {
    @Published var request: UUID?
    @Published var preparing = false
    @Published var package: FullDataExporter.Package?
    @Published var errorMessage: String?
    var selection = StudyExportSelection()
    private var retainedPackage: FullDataExporter.Package?

    func start(_ selection: StudyExportSelection) {
        self.selection = selection
        preparing = true
        request = UUID()
    }

    func prepare() async {
        guard request != nil else { return }
        defer { preparing = false; request = nil }
        do {
            let result = try await FullDataExporter.prepare(selection: selection)
            retainedPackage = result
            package = result
        } catch {
            if !Task.isCancelled {
                errorMessage = error is FullDataExporter.SelectionError ? L10n(error.localizedDescription)
                    : L10n("Data could not be prepared. Please try again. Your saved records have not changed.")
            }
        }
    }

    func cleanUp() { retainedPackage?.remove(); retainedPackage = nil; package = nil }
}

/// Attach presentation to a stable page, never to a recycled Form section/cell.
struct StudyDataExportPresentation: ViewModifier {
    @ObservedObject var controller: StudyDataExportController
    @Environment(\.studyExportBlocked) private var stimulationActive

    func body(content: Content) -> some View {
        content
            .task(id: controller.request) { await controller.prepare() }
            .sheet(item: $controller.package, onDismiss: controller.cleanUp) { item in
                FullDataShareSheet(url: item.archive) { controller.package = nil }
            }
            .alert(L10n("Could not prepare data"), isPresented: Binding(
                get: { controller.errorMessage != nil }, set: { if !$0 { controller.errorMessage = nil } })) {
                    Button(L10n("OK"), role: .cancel) { controller.errorMessage = nil }
            } message: {
                Text(controller.errorMessage ?? "")
            }
            .onDisappear {
                if controller.request == nil && controller.package == nil { controller.cleanUp() }
            }
            .onChange(of: stimulationActive) { _, active in if active { controller.request = nil } }
    }
}

/// Shared by patient Data and researcher exports; only temporary packages are removed.
struct StudyDataExportSection: View {
    @ObservedObject var controller: StudyDataExportController
    var selection = StudyExportSelection()
    var permitsConfiguration = true
    var canShare = true
    @Environment(\.studyExportBlocked) private var stimulationActive

    var body: some View {
        Section {
            Button {
                controller.start(selection)
            } label: {
                Label(L10n(permitsConfiguration ? "Share all data (ZIP)" : "Share selected data (ZIP)"),
                      systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("studyShareDataZIP")
            .disabled(controller.preparing || stimulationActive || !canShare || selection.groups.isEmpty || selection.sessionIDs?.isEmpty == true)
            if controller.preparing {
                ProgressView(L10n("Preparing data…"))
                    .accessibilityIdentifier("studyExportPreparing")
            }
            if permitsConfiguration {
                NavigationLink {
                    StudyDataExportView(research: false)
                } label: {
                    Label(L10n("Choose data to share"), systemImage: "checklist")
                }
                .disabled(controller.preparing)
                .accessibilityIdentifier("studyChooseExportData")
            }
        } header: {
            Text(L10n("Sharing"))
        } footer: {
            Text(L10n(stimulationActive ? "research.export.stop"
                : "Videos are not included. Sharing does not delete data or send it automatically."))
        }
    }
}

struct StudyDataExportView: View {
    let research: Bool
    @ObservedObject private var store = TaskSessionStore.shared
    @StateObject private var exportController = StudyDataExportController()
    @State private var groups = Set(StudyExportSelection.FileGroup.allCases)
    @State private var scope: Scope = .all
    @State private var start = Calendar.current.startOfDay(for: Date())
    @State private var end = Date()
    @State private var selectedIDs = Set<UUID>()

    enum Scope: String, CaseIterable, Identifiable {
        case all, fortnight, month, custom, selected
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All dates"
            case .fortnight: return "Last 2 weeks"
            case .month: return "Last month"
            case .custom: return "Custom dates"
            case .selected: return "Selected sessions"
            }
        }
    }

    private var selection: StudyExportSelection {
        var result = StudyExportSelection(groups: groups)
        guard research else { return result }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        switch scope {
        case .all: break
        case .fortnight:
            result.interval = DateInterval(start: calendar.date(byAdding: .day, value: -13, to: today)!, end: tomorrow)
        case .month:
            result.interval = DateInterval(start: calendar.date(byAdding: .month, value: -1, to: today)!, end: tomorrow)
        case .custom:
            result.interval = DateInterval(start: calendar.startOfDay(for: start),
                end: calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end))!)
        case .selected: result.sessionIDs = selectedIDs
        }
        return result
    }

    private var matchingSessions: [MovementSession] {
        store.sessions.filter { selection.includesSession(id: $0.id, date: $0.date) }
    }

    var body: some View {
        Form {
            if research {
                Section {
                    Menu {
                        ForEach(Scope.allCases) { option in
                            Button { scope = option } label: {
                                if scope == option { Label(L10n(option.title), systemImage: "checkmark") }
                                else { Text(L10n(option.title)) }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n("Period")).font(.caption).foregroundStyle(.secondary)
                            HStack(alignment: .top) {
                                Text(L10n(scope.title))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.up.chevron.down").font(.caption)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityLabel(L10n("Period"))
                    .accessibilityValue(L10n(scope.title))
                    .accessibilityIdentifier("studyExportPeriod")
                    if scope == .custom {
                        DatePicker(L10n("From"), selection: $start, in: ...end, displayedComponents: .date)
                        DatePicker(L10n("To"), selection: $end, in: start..., displayedComponents: .date)
                    }
                    if scope == .selected {
                        NavigationLink {
                            List {
                                ForEach(store.sessions.sorted { $0.date > $1.date }) { session in
                                    Button {
                                        if !selectedIDs.insert(session.id).inserted { selectedIDs.remove(session.id) }
                                    } label: {
                                        HStack {
                                            Image(systemName: selectedIDs.contains(session.id) ? "checkmark.circle.fill" : "circle")
                                                .frame(width: 32, height: 44)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(session.date, format: .dateTime.day().month().year().hour().minute())
                                                Text("\(session.patientId) · \(session.trials.count)")
                                                    .font(.subheadline).foregroundStyle(.secondary)
                                            }
                                            .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("studyExportSession_\(session.id)")
                                    .accessibilityValue(L10n(selectedIDs.contains(session.id) ? "Selected" : "Not selected"))
                                }
                            }
                            .navigationTitle(L10n("Selected sessions"))
                        } label: {
                            LabeledContent(L10n("Select sessions"), value: "\(selectedIDs.count)")
                        }
                        .accessibilityIdentifier("studyExportSelectSessions")
                    }
                    LabeledContent(L10n("Sessions"), value: "\(matchingSessions.count)")
                        .accessibilityIdentifier("studyExportSessionCount")
                    LabeledContent(L10n("Trials"), value: "\(matchingSessions.reduce(0) { $0 + $1.trials.count })")
                } footer: {
                    Text(L10n(scope == .selected
                        ? "Journal and logs cover the selected sessions' calendar days. All trials in each selected session are included."
                        : "Dates refer to session start. All trials in matching sessions are included; journal and logs use the chosen dates."))
                }
            }
            Section(L10n("Data to include")) {
                ForEach(StudyExportSelection.FileGroup.allCases) { group in
                    Toggle(L10n(group.title), isOn: Binding(get: { groups.contains(group) }, set: { enabled in
                        if enabled { groups.insert(group) } else { groups.remove(group) }
                    }))
                    .accessibilityIdentifier("studyExportGroup_\(group.rawValue)")
                }
            }
            StudyDataExportSection(controller: exportController, selection: selection, permitsConfiguration: false,
                canShare: scope != .selected || !matchingSessions.isEmpty)
        }
        .modifier(StudyDataExportPresentation(controller: exportController))
        .navigationTitle(L10n(research ? "Share study data" : "Choose data to share"))
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG && targetEnvironment(simulator)
        .task {
            guard ProcessInfo.processInfo.arguments.contains("--ui-test-export-fixture"), store.sessions.isEmpty else { return }
            for offset in [0, -10, -40] {
                let date = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
                let trial = Trial(taskType: .fingerTap, side: .right, source: .synthetic,
                    stopCondition: .thirtySec, startedAt: date, samples: [], metrics: .empty)
                let session = MovementSession(patientId: "TEAM-UI-EXPORT", date: date)
                await withCheckedContinuation { continuation in
                    store.saveAcceptedTrial(trial, in: session, temporaryVideoURL: nil) { _ in continuation.resume() }
                }
            }
        }
        #endif
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
