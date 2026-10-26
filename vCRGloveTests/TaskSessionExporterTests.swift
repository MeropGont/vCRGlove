//
//  TaskSessionExporterTests.swift
//  vCRGloveTests
//
//  Task F: exports must be well-formed (JSON round-trips, CSV has the right
//  shape) and old JSONL recordings without the new sync field must still decode.
//

import Testing
import Foundation
import XCTest
@testable import vCRGlove

@Suite(.serialized)
struct SelectedStudyExportTests {
    func fixture() throws -> (URL, URL, [MovementSession], Data) {
        let base = try FullDataExporter.makeDirectory()
        let snapshot = base.appendingPathComponent("snapshot")
        let tasks = snapshot.appendingPathComponent("tasks")
        let logs = snapshot.appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: tasks, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let dates = ["2026-10-01T08:00:00Z", "2026-10-15T08:00:00Z", "2026-10-23T08:00:00Z"]
            .map { FullDataExporter.parsedDate($0)! }
        let sessions = dates.enumerated().map { index, date in
            MovementSession(patientId: "TEAM-EXPORT", date: date, stimulationContext: .preStim,
                trials: [Trial(taskType: .fingerTap, side: .right, source: .camera,
                    stopCondition: .thirtySec, startedAt: date,
                    samples: [.init(t: 0, value: Double(index))], metrics: .empty,
                    video: .init(fileName: "\(UUID().uuidString).mov", byteCount: 10),
                    fingerTappingAngle: .init(samples: [.init(t: 0, degrees: 10), .init(t: 0.1, degrees: nil)]))])
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var raw = Data()
        for session in sessions {
            var object = try JSONSerialization.jsonObject(with: encoder.encode(session)) as! [String: Any]
            object["futureMetadata"] = "preserve"
            raw.append(try JSONSerialization.data(withJSONObject: object)); raw.append(0x0A)
        }
        try raw.write(to: tasks.appendingPathComponent("sessions.jsonl"))
        for (name, key) in [("events.jsonl", "ts"), ("handshake.jsonl", "ts_phone")] {
            let lines = try dates.reduce(into: Data()) { data, date in
                data.append(try JSONSerialization.data(withJSONObject: [key: ISO8601DateFormatter().string(from: date), "futureEvent": true]))
                data.append(0x0A)
            }
            try lines.write(to: logs.appendingPathComponent(name))
        }
        let journal = try JSONSerialization.data(withJSONObject: dates.map {
            ["date": $0.timeIntervalSinceReferenceDate, "futureJournal": "preserve"] as [String: Any]
        })
        return (base, snapshot, sessions, journal)
    }

    @Test func manualSelectionKeepsMatchingJSONCSVAnglesAndCalendarDayLogs() throws {
        let (base, snapshot, sessions, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = snapshot.appendingPathComponent("tasks/sessions.jsonl")
        let original = try Data(contentsOf: source)
        let root = base.appendingPathComponent("output")
        var selection = StudyExportSelection(sessionIDs: [sessions[0].id, sessions[2].id])
        selection.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        try FullDataExporter.buildSelectedFiles(selection: selection, snapshot: snapshot, root: root,
            journalData: journal, settingsData: Data("settings".utf8))
        let data = try Data(contentsOf: root.appendingPathComponent("tasks/sessions.json"))
        let objects = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(objects.count == 2 && objects.allSatisfy { $0["futureMetadata"] as? String == "preserve" })
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([MovementSession].self, from: data)
        #expect(decoded.map(\.id) == [sessions[0].id, sessions[2].id])
        for file in ["metrics.csv", "samples.csv", "finger-tapping-angles.csv"] {
            let csv = try String(contentsOf: root.appendingPathComponent("tasks/\(file)"), encoding: .utf8)
            #expect(csv.contains(sessions[0].id.uuidString) && csv.contains(sessions[2].id.uuidString))
            #expect(!csv.contains(sessions[1].id.uuidString))
        }
        let journalObjects = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("journal/journal_entries.json"))) as! [[String: Any]]
        #expect(journalObjects.count == 2)
        for name in ["events.jsonl", "handshake.jsonl"] {
            let events = try String(contentsOf: root.appendingPathComponent("logs/\(name)"), encoding: .utf8)
            #expect(events.split(separator: "\n").count == 2 && !events.contains("2026-10-15"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("tasks/videos").path))
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func dateRangeIncludesStartExcludesEndAndKeepsAllTrials() throws {
        let (base, snapshot, sessions, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let selection = StudyExportSelection(interval: DateInterval(start: sessions[1].date, end: sessions[2].date))
        let root = base.appendingPathComponent("output")
        try FullDataExporter.buildSelectedFiles(selection: selection, snapshot: snapshot, root: root,
            journalData: journal, settingsData: Data())
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode([MovementSession].self, from: Data(contentsOf: root.appendingPathComponent("tasks/sessions.json")))
        #expect(exported.count == 1 && exported[0].trials == sessions[1].trials)
        let log = try String(contentsOf: root.appendingPathComponent("logs/events.jsonl"), encoding: .utf8)
        #expect(log.contains("2026-10-15") && !log.contains("2026-10-23") && !log.contains("2026-10-01"))
    }

    @Test func fileGroupsAndMissingAnglesAreExplicitWithoutPersistentExportCopies() throws {
        let (base, snapshot, _, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appendingPathComponent("output")
        try FullDataExporter.buildSelectedFiles(selection: .init(groups: [.samples]), snapshot: snapshot, root: root,
            journalData: nil, settingsData: Data())
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tasks").path) == ["samples.csv"])
        let empty = try TaskSessionExporter.exportFingerTappingAnglesCSV([], directory: base.appendingPathComponent("empty"))
        #expect(try String(contentsOf: empty, encoding: .utf8).split(separator: "\n").count == 1)
        #expect(throws: (any Error).self) { try TaskSessionExporter.exportFingerTappingAnglesCSV([]) }
    }

    @Test func staleSelectionAndMalformedScopedRecordsFailRatherThanLeakUnselectedData() throws {
        let (base, snapshot, _, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(throws: (any Error).self) {
            try FullDataExporter.buildSelectedFiles(selection: .init(sessionIDs: [UUID()]), snapshot: snapshot,
                root: base.appendingPathComponent("stale"), journalData: journal, settingsData: Data())
        }
        try Data("malformed\n".utf8).write(to: snapshot.appendingPathComponent("logs/events.jsonl"))
        let selection = StudyExportSelection(groups: [.events], interval: DateInterval(start: .distantPast, end: .distantFuture))
        #expect(throws: (any Error).self) {
            try FullDataExporter.buildSelectedFiles(selection: selection, snapshot: snapshot,
                root: base.appendingPathComponent("bad"), journalData: nil, settingsData: Data())
        }
    }

    @Test @MainActor func nonVideoSnapshotDoesNotReadMovieStoreAndCreatesRealZIP() async throws {
        let (base, snapshot, _, journal) = try fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let movies = base.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: movies, withIntermediateDirectories: true)
        try Data("must not be copied".utf8).write(to: movies.appendingPathComponent("unexpected-file"))
        let journalURL = base.appendingPathComponent("journal.json"); try journal.write(to: journalURL)
        let tasks = TaskSessionStore(storageURL: snapshot.appendingPathComponent("tasks/sessions.jsonl"),
            videoStore: MovementVideoStore(directory: movies))
        let package = try await FullDataExporter.prepare(selection: .init(), journal: JournalStore(storageURL: journalURL),
            tasks: tasks, events: EventStore(directory: snapshot.appendingPathComponent("logs")))
        defer { package.remove() }
        #expect(package.missingVideoCount == 0)
        #expect(Array(try Data(contentsOf: package.archive).prefix(2)) == [0x50, 0x4b])
        #expect(!FileManager.default.fileExists(atPath: package.directory.appendingPathComponent("snapshot").path))
        #expect(try Data(contentsOf: movies.appendingPathComponent("unexpected-file")) == Data("must not be copied".utf8))
    }

    @Test @MainActor func settingsOnlyAndEmptyDevicePackagesDoNotRequireOtherStores() async throws {
        let base = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let tasks = TaskSessionStore(storageURL: base.appendingPathComponent("absent-sessions.jsonl"),
            videoStore: MovementVideoStore(directory: base.appendingPathComponent("no-movies")))
        for groups in [Set<StudyExportSelection.FileGroup>([.settings]), Set(StudyExportSelection.FileGroup.allCases)] {
            let package = try await FullDataExporter.prepare(selection: .init(groups: groups),
                journal: JournalStore(storageURL: base.appendingPathComponent("absent-journal.json")),
                tasks: tasks, events: EventStore(directory: base.appendingPathComponent("no-logs")))
            #expect(package.missingVideoCount == 0)
            #expect(try Data(contentsOf: package.archive).count > 100)
            package.remove()
        }
    }
}

@Suite(.serialized)
@MainActor
struct FullDataExportTests {
    @Test func copiesRawMovementAndAllSavedMoviesWithoutRewriting() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions.jsonl")
        let raw = Data("{\"unknown_future_field\":7}\nmalformed older line\n".utf8)
        try raw.write(to: sessions)
        let videos = root.appendingPathComponent("videos", isDirectory: true)
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).mov"
        let movie = Data("stand-in movie bytes".utf8)
        try movie.write(to: videos.appendingPathComponent(name))
        let store = TaskSessionStore(storageURL: sessions, videoStore: MovementVideoStore(directory: videos))
        let destination = root.appendingPathComponent("snapshot")
        let absent = try await store.copyExportSnapshot(to: destination)
        #expect(absent.isEmpty)
        #expect(try Data(contentsOf: destination.appendingPathComponent("tasks/sessions.jsonl")) == raw)
        #expect(try Data(contentsOf: destination.appendingPathComponent("tasks/videos/\(name)")) == movie)
        #expect(try Data(contentsOf: sessions) == raw)
        #expect(try Data(contentsOf: videos.appendingPathComponent(name)) == movie)
    }

    @Test func missingStorageIsExplicitAndSymlinksAreRejected() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("snapshot")
        let store = TaskSessionStore(storageURL: root.appendingPathComponent("absent.jsonl"),
            videoStore: MovementVideoStore(directory: root.appendingPathComponent("no-videos")))
        #expect(try await store.copyExportSnapshot(to: destination) == ["tasks/sessions.jsonl"])
        let original = root.appendingPathComponent("private")
        try Data("private".utf8).write(to: original)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        #expect(throws: (any Error).self) {
            try FullDataExporter.copyFile(link, to: root.appendingPathComponent("must-not-exist"))
        }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("must-not-exist").path))
    }

    @Test func eventSnapshotWaitsForQueuedWrites() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let events = EventStore(directory: root)
        events.append(type: "stim", tag: "test", message: "queued-before-snapshot")
        let destination = root.appendingPathComponent("snapshot")
        let absent = try await events.copyExportSnapshot(to: destination)
        let copied = try String(contentsOf: destination.appendingPathComponent("logs/events.jsonl"), encoding: .utf8)
        #expect(copied.contains("queued-before-snapshot"))
        #expect(absent == ["logs/handshake.jsonl"])
    }

    @Test func settingsAllowlistIncludesResearchDataButNotCredentials() {
        #expect(FullDataExporter.settingsKeys.contains(StimulationProfileStore.key))
        #expect(FullDataExporter.settingsKeys.contains("patientStudyNotes"))
        #expect(FullDataExporter.settingsKeys.contains("vcr.uploader.pending"))
        #expect(!FullDataExporter.settingsKeys.contains("researchPassword"))
        #expect(!FullDataExporter.settingsKeys.contains("researchUnlocked"))
    }

    @Test func movementSnapshotWaitsForAcceptedRecordingSave() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TaskSessionStore(storageURL: root.appendingPathComponent("sessions.jsonl"),
            videoStore: MovementVideoStore(directory: root.appendingPathComponent("videos")))
        let session = MovementSession(patientId: "QUEUED-TEST")
        let angles = FingerTappingAngleRecording(samples: (0..<300).map {
            let time = Double($0) / 30
            return TimestampedAngleSample(t: time, degrees: 20 - 20 * cos(4 * .pi * time))
        })
        let angleMetrics = FingerTappingAngleAnalyzer.analyze(angles)
        let referenceSegment = try #require(FingerTappingAngleAnalyzer.firstTenTaps(angles))
        let trial = Trial(taskType: .fingerTap, side: .left, source: .camera,
            stopCondition: .thirtySec, samples: [], metrics: .empty, fingerTappingAngle: angles,
            fingerTappingAngleMetrics: angleMetrics, fingerTappingReferenceSegment: referenceSegment)
        store.saveAcceptedTrial(trial, in: session, temporaryVideoURL: nil) { _ in }
        let destination = root.appendingPathComponent("snapshot")
        #expect(try await store.copyExportSnapshot(to: destination).isEmpty)
        let raw = try String(contentsOf: destination.appendingPathComponent("tasks/sessions.jsonl"), encoding: .utf8)
        #expect(raw.contains("QUEUED-TEST"))
        #expect(raw.contains(trial.id.uuidString))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(MovementSession.self, from: Data(raw.utf8))
        #expect(restored.trials[0].fingerTappingAngle == angles)
        #expect(restored.trials[0].fingerTappingAngleMetrics == angleMetrics)
        #expect(restored.trials[0].fingerTappingReferenceSegment == referenceSegment)
    }

    @Test func interruptedCleanupDoesNotTouchUnrelatedFiles() throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let interrupted = try FullDataExporter.makeDirectory(parent: root)
        let unrelated = root.appendingPathComponent("original-recording.mov")
        try Data("keep".utf8).write(to: unrelated)
        FullDataExporter.removeInterruptedExports(parent: root)
        #expect(!FileManager.default.fileExists(atPath: interrupted.path))
        #expect(try Data(contentsOf: unrelated) == Data("keep".utf8))
    }
}

final class FullDataArchiveTests: XCTestCase {
    @MainActor
    func testSelectedArchiveManifestAndCleanup() async throws {
        let (base, snapshot, sessions, journal) = try SelectedStudyExportTests().fixture()
        defer { try? FileManager.default.removeItem(at: base) }
        let journalURL = base.appendingPathComponent("journal.json"); try journal.write(to: journalURL)
        let defaultsName = "selected-export-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set("must-not-export", forKey: "researchPassword")
        defaults.set("out-of-range-pending", forKey: "vcr.uploader.pending")
        let package = try await FullDataExporter.prepare(selection: .init(sessionIDs: [sessions[1].id]),
            journal: JournalStore(storageURL: journalURL),
            tasks: TaskSessionStore(storageURL: snapshot.appendingPathComponent("tasks/sessions.jsonl"),
                videoStore: MovementVideoStore(directory: base.appendingPathComponent("movies"))),
            events: EventStore(directory: snapshot.appendingPathComponent("logs")), defaults: defaults)
        let attachment = XCTAttachment(contentsOfFile: package.archive)
        attachment.name = "Selected-study-data-fixture.zip"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(package.missingVideoCount, 0)
        package.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.archive.path))
        XCTAssertEqual(try Data(contentsOf: journalURL), journal)
    }

    @MainActor
    func testFailureLeavesOriginalsAndRemovesPartialExport() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let videos = root.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        let source = videos.appendingPathComponent("unexpected-file")
        try Data("original".utf8).write(to: source)
        let before = try FileManager.default.contentsOfDirectory(atPath: FullDataExporter.temporaryRoot.path).sorted()
        do {
            let package = try await FullDataExporter.prepare(journal: JournalStore(storageURL: root.appendingPathComponent("journal.json")),
                tasks: TaskSessionStore(storageURL: root.appendingPathComponent("sessions.jsonl"),
                    videoStore: MovementVideoStore(directory: videos)), events: EventStore(directory: root))
            package.remove()
            XCTFail("Unexpected video-store file must not be silently omitted")
        } catch {
            XCTAssertTrue(error is MovementVideoStore.VideoError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: FullDataExporter.temporaryRoot.path).sorted(), before)
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
    }

    @MainActor
    func testCompleteArchiveAndCleanup() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let journalFile = root.appendingPathComponent("journal.json")
        let rawJournal = Data("[{\"future_journal_field\":\"preserve exactly\"}]".utf8)
        try rawJournal.write(to: journalFile)
        let sessionsFile = root.appendingPathComponent("sessions.jsonl")
        let name = "\(UUID().uuidString).mov"
        let missing = "\(UUID().uuidString).mov"
        let rawSessions = Data("{\"trials\":[{\"video\":{\"fileName\":\"\(name)\"}},{\"video\":{\"fileName\":\"\(missing)\"}}],\"unknown_metadata\":true}\ninvalid legacy line\n".utf8)
        try rawSessions.write(to: sessionsFile)
        let videos = root.appendingPathComponent("videos")
        try FileManager.default.createDirectory(at: videos, withIntermediateDirectories: true)
        try Data("movie-fixture-contents".utf8).write(to: videos.appendingPathComponent(name))
        let defaultsName = "full-export-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.set("TEST-123", forKey: "patientID")
        defaults.set("do-not-export-password", forKey: "researchPassword")
        try StimulationProfileStore(defaults: defaults).save(StimulationProfile())
        let events = EventStore(directory: root)
        events.append(type: "stimulation", tag: "test", message: "archive-event-fixture")
        let package = try await FullDataExporter.prepare(journal: JournalStore(storageURL: journalFile),
            tasks: TaskSessionStore(storageURL: sessionsFile, videoStore: MovementVideoStore(directory: videos)),
            events: events, defaults: defaults)
        defer { package.remove() }
        XCTAssertEqual(package.missingVideoCount, 1)
        let archive = try Data(contentsOf: package.archive)
        XCTAssertEqual(Array(archive.prefix(2)), [0x50, 0x4b])
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.directory.appendingPathComponent("vCRGlove-data").path))
        let attachment = XCTAttachment(contentsOfFile: package.archive)
        attachment.name = "Full-data-export-fixture.zip"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(try Data(contentsOf: journalFile), rawJournal)
        XCTAssertEqual(try Data(contentsOf: sessionsFile), rawSessions)
        package.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.archive.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: videos.appendingPathComponent(name).path))
    }

    @MainActor
    func testEmptyDeviceStillCreatesArchive() async throws {
        let root = try FullDataExporter.makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = try await FullDataExporter.prepare(journal: JournalStore(storageURL: root.appendingPathComponent("journal.json")),
            tasks: TaskSessionStore(storageURL: root.appendingPathComponent("sessions.jsonl"),
                videoStore: MovementVideoStore(directory: root.appendingPathComponent("videos"))),
            events: EventStore(directory: root))
        defer { package.remove() }
        XCTAssertEqual(package.missingVideoCount, 0)
        XCTAssertGreaterThan(try Data(contentsOf: package.archive).count, 100)
    }
}

@Suite(.serialized)
struct TaskSessionExporterTests {

    @Test func videoTimingUsesSourceTimestampAndPreservesSignedOffsets() throws {
        let timing = try #require(MovementVideoTiming.make(captureStartPTS: 1000,
            trialStartUptime: 1000.125, firstMoviePTS: 0.02))
        #expect(timing.firstFrameTrialTimeSeconds == -0.125)
        #expect(abs(try #require(timing.movieTime(forTrialTime: 0)) - 0.145) < 1e-10)
        #expect(timing.movieTime(forTrialTime: -0.5)! < 0)
        let afterStart = try #require(MovementVideoTiming.make(captureStartPTS: 1001,
            trialStartUptime: 1000, firstMoviePTS: 0))
        #expect(afterStart.movieTime(forTrialTime: 0) == -1)
        #expect(afterStart.movieTime(forTrialTime: 1) == 0)
    }

    @Test func videoTimingDoesNotInventMissingOrUnsupportedAnchors() throws {
        #expect(MovementVideoTiming.make(captureStartPTS: nil, trialStartUptime: 1, firstMoviePTS: 0) == nil)
        #expect(MovementVideoTiming.make(captureStartPTS: 1, trialStartUptime: nil, firstMoviePTS: 0) == nil)
        #expect(MovementVideoTiming.make(captureStartPTS: 1, trialStartUptime: 1, firstMoviePTS: nil) == nil)
        for bad in [Double.nan, .infinity, -1] {
            #expect(MovementVideoTiming.make(captureStartPTS: bad, trialStartUptime: 1, firstMoviePTS: 0) == nil)
            #expect(MovementVideoTiming.make(captureStartPTS: 1, trialStartUptime: bad, firstMoviePTS: 0) == nil)
            #expect(MovementVideoTiming.make(captureStartPTS: 1, trialStartUptime: 1, firstMoviePTS: bad) == nil)
        }
        let unknown = MovementVideoTiming(version: 99, method: "future", firstFrameTrialTimeSeconds: 0,
                                         firstFrameMoviePTSSeconds: 0)
        #expect(unknown.movieTime(forTrialTime: 0) == nil)
        let timing = try #require(MovementVideoTiming.make(captureStartPTS: 1, trialStartUptime: 1, firstMoviePTS: 0))
        #expect(timing.movieTime(forTrialTime: .nan) == nil)
    }

    @Test func videoTimingSurvivesCopiesAndJSONWithoutChangingSamplesOrCSVs() throws {
        let original = makeSessions()[0].trials[0]
        let timing = try #require(MovementVideoTiming.make(captureStartPTS: 1000,
            trialStartUptime: 1000.1, firstMoviePTS: 0))
        let linked = original.withVideo(.init(fileName: "\(original.id).mov", byteCount: 100, timing: timing))
            .withMedicationTiming(.init(status: .unsure))
        #expect(linked.video?.timing == timing)
        #expect(linked.samples == original.samples && linked.metrics == original.metrics)
        let encoder = JSONEncoder()
        let bytes = try encoder.encode(linked)
        #expect(try JSONDecoder().decode(Trial.self, from: bytes).video?.timing == timing)
        var legacy = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var video = try #require(legacy["video"] as? [String: Any])
        video.removeValue(forKey: "timing")
        legacy["video"] = video
        let old = try JSONDecoder().decode(Trial.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.video?.timing == nil && old.video?.fileName == linked.video?.fileName)
        let session = MovementSession(patientId: "TIMING-TEST", trials: [linked])
        let url = try TaskSessionExporter.exportJSON([session])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([MovementSession].self, from: Data(contentsOf: url))
        #expect(restored[0].trials[0].video?.timing == timing)
        #expect(linked.withVideo(nil).video == nil)
    }

    @Test func angleChannelSurvivesCopiesJSONAndLegacyDecodeWithoutChangingOtherCSVs() throws {
        let original = makeSessions()[0].trials[0]
        let angles = FingerTappingAngleRecording(samples: [.init(t: 0.1, degrees: 0), .init(t: 0.2, degrees: nil)])
        let angleMetrics = FingerTappingAngleAnalyzer.analyze(angles)
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
            samples: original.samples, metrics: original.metrics, measurementVersion: MovementMeasurementVersion.camera,
            fingerTappingAngle: angles, fingerTappingAngleMetrics: angleMetrics)
        let copied = trial.withMedicationTiming(.init(status: .unsure)).withVideo(.init(fileName: "example.mov", byteCount: 1))
        #expect(copied.fingerTappingAngle == angles)
        let data = try JSONEncoder().encode(copied)
        #expect(try JSONDecoder().decode(Trial.self, from: data) == copied)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "fingerTappingAngle")
        let decodedLegacy = try JSONDecoder().decode(Trial.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decodedLegacy.fingerTappingAngle == nil && decodedLegacy.samples == trial.samples)

        let session = MovementSession(patientId: "ANGLE-TEST", trials: [copied])
        let url = try TaskSessionExporter.exportJSON([session])
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([MovementSession].self, from: Data(contentsOf: url))
        #expect(restored[0].trials[0].fingerTappingAngle == angles)
        #expect(restored[0].trials[0].fingerTappingAngleMetrics == angleMetrics)
        let samples = try TaskSessionExporter.exportSamplesCSV([session])
        defer { try? FileManager.default.removeItem(at: samples) }
        let rows = try String(contentsOf: samples, encoding: .utf8).split(separator: "\n")
        #expect(rows.first == "session_id,trial_id,task,side,t_sec,value")
        #expect(rows.count == trial.samples.count + 1)
        let metrics = try TaskSessionExporter.exportMetricsCSV([session])
        defer { try? FileManager.default.removeItem(at: metrics) }
        #expect(try String(contentsOf: metrics, encoding: .utf8).split(separator: "\n")[0].split(separator: ",").count == 29)
    }

    @Test func angleCSVPreservesMissingVersusZeroAndExplicitUnits() throws {
        let trial = Trial(taskType: .fingerTap, side: .left, source: .camera, stopCondition: .thirtySec,
            samples: [], metrics: .empty, fingerTappingAngle: .init(samples: [
                .init(t: 0.1, degrees: 0), .init(t: 0.2, degrees: nil), .init(t: 0.3, degrees: 90)]))
        let url = try TaskSessionExporter.exportFingerTappingAnglesCSV([.init(patientId: "TEST", trials: [trial])])
        defer { try? FileManager.default.removeItem(at: url) }
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map {
            $0.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        }
        #expect(rows.count == 4 && rows.allSatisfy { $0.count == 10 })
        #expect(rows[1][5] == "0.0" && rows[1][6] == "true")
        #expect(rows[2][5].isEmpty && rows[2][6] == "false")
        #expect(rows[3][5] == "90.0" && rows[3][6] == "true")
        #expect(rows[1][7] == "\"\(FingerTappingAngleRecording.currentVersion)\"")
        #expect(rows[1][8] == "\"degrees\"" && rows[1][9] == "\"seconds_since_trial_start\"")
        #expect(throws: TaskSessionExporter.ExportError.self) {
            try TaskSessionExporter.exportFingerTappingAnglesCSV(makeSessions())
        }
    }

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

    @Test func jsonExportPreservesVideoLinkAndActualRecordingDuration() throws {
        var sessions = makeSessions()
        let original = sessions[0].trials[0]
        let video = MovementVideoReference(fileName: original.id.uuidString + ".mov", byteCount: 1234)
        sessions[0].trials = [Trial(id: original.id, taskType: original.taskType, side: original.side,
            source: .camera, stopCondition: .thirtySec, startedAt: original.startedAt,
            samples: original.samples, metrics: original.metrics, recordedDurationSeconds: 30,
            video: video, measurementVersion: MovementMeasurementVersion.camera).withMedicationTiming(nil)]
        let url = try TaskSessionExporter.exportJSON(sessions)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([MovementSession].self, from: Data(contentsOf: url))
        #expect(decoded[0].trials[0].video == video)
        #expect(decoded[0].trials[0].recordedDurationSeconds == 30)
        #expect(decoded[0].trials[0].id == original.id)
        #expect(decoded[0].trials[0].measurementVersion == MovementMeasurementVersion.camera)
    }

    @Test func csvAppendsVersionWithoutChangingExistingColumnsOrLabellingLegacyAsCurrent() throws {
        var sessions = makeSessions()
        let original = sessions[0].trials[0]
        let versioned = Trial(taskType: original.taskType, side: original.side, source: .camera,
                              stopCondition: original.stopCondition, samples: original.samples,
                              metrics: original.metrics, measurementVersion: MovementMeasurementVersion.camera)
        sessions[0].trials.append(versioned)
        let url = try TaskSessionExporter.exportMetricsCSV(sessions)
        defer { try? FileManager.default.removeItem(at: url) }
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        #expect(lines[0].hasSuffix(",measurement_version"))
        #expect(lines[1].hasSuffix(",\"\""))
        #expect(lines[2].hasSuffix(",\"\(MovementMeasurementVersion.camera)\""))
        #expect(lines[0].split(separator: ",").count == 29)
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
        let values = lines[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(values[21].isEmpty && values[22].isEmpty && values[23].isEmpty)
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

    @Test func medicationCSVAppendsFieldsWithoutChangingOriginalColumns() throws {
        var sessions = makeSessions()
        let original = sessions[0].trials[0]
        let timing = MedicationTiming(status: .takenAt,
                                      takenAt: original.startedAt.addingTimeInterval(-3600),
                                      journalEntryID: UUID(), medicationName: "Medicine", medicationDose: "100 mg")
        sessions[0].trials = [original.withMedicationTiming(timing)]
        let url = try TaskSessionExporter.exportMetricsCSV(sessions)
        defer { try? FileManager.default.removeItem(at: url) }
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let header = rows[0].split(separator: ",", omittingEmptySubsequences: false)
        let values = rows[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(header.count == 29 && values.count == 29)
        #expect(header[28] == "measurement_version")
        #expect(header[20] == "quality_index")
        #expect(header[21] == "medication_status")
        #expect(values[21] == "takenAt")
        #expect(values[23] == "3600.0")
        #expect(values[25] == Substring(timing.journalEntryID!.uuidString))
        #expect(values[26] == "\"Medicine\"" && values[27] == "\"100 mg\"")
    }

    @Test func medicationJSONExportRetainsConfirmedJournalFields() throws {
        var sessions = makeSessions()
        let intake = Date(timeIntervalSince1970: 1700000000)
        let timing = MedicationTiming(status: .takenAt, takenAt: intake, confirmedAt: intake,
                                      journalEntryID: UUID(), medicationName: "Medicine", medicationDose: "100 mg")
        let original = sessions[0].trials[0]
        sessions[0].trials = [original.withMedicationTiming(timing)]
        let url = try TaskSessionExporter.exportJSON(sessions)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode([MovementSession].self, from: Data(contentsOf: url))
        #expect(restored[0].trials[0].medicationTiming == timing)
        #expect(restored[0].trials[0].id == original.id)
        #expect(restored[0].trials[0].samples == original.samples)
        #expect(restored[0].trials[0].metrics == original.metrics)
    }

    @Test(arguments: [MedicationTiming.Status.noneToday, .unsure])
    func unknownAndNoMedicationExportWithoutInventingTime(status: MedicationTiming.Status) throws {
        var sessions = makeSessions()
        let original = sessions[0].trials[0]
        sessions[0].trials = [original.withMedicationTiming(.init(status: status, confirmedAt: original.startedAt))]
        let url = try TaskSessionExporter.exportMetricsCSV(sessions)
        defer { try? FileManager.default.removeItem(at: url) }
        let rows = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        let values = rows[1].split(separator: ",", omittingEmptySubsequences: false)
        #expect(values[21] == Substring(status.rawValue))
        #expect(values[22].isEmpty && values[23].isEmpty)
    }

    @Test func journalNameAndDoseAreQuotedInCSV() throws {
        var sessions = makeSessions()
        let trial = sessions[0].trials[0]
        sessions[0].trials = [trial.withMedicationTiming(.init(status: .takenAt, takenAt: trial.startedAt,
                                                              medicationName: "A, \"B\"", medicationDose: "1,5 tablets"))]
        let url = try TaskSessionExporter.exportMetricsCSV(sessions)
        defer { try? FileManager.default.removeItem(at: url) }
        let csv = try String(contentsOf: url, encoding: .utf8)
        #expect(csv.contains("\"A, \"\"B\"\"\",\"1,5 tablets\""))
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
