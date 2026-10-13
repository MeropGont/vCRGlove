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
import AVFoundation
@testable import vCRGlove

struct JournalNoteExampleTests {
    @Test @MainActor func allExamplesHaveDistinctGermanTranslations() throws {
        let keys = NoteLogView.noteExamples
        #expect(keys.count == 6 && Set(keys).count == keys.count)
        let path = try #require(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: path))
        let translations = keys.map { german.localizedString(forKey: $0, value: $0, table: nil) }
        #expect(Set(translations).count == keys.count)
        for (key, translation) in zip(keys, translations) {
            #expect(translation != key)
            #expect(translation.hasPrefix("Zum Beispiel:"))
        }
    }
}

struct MovementVideoStorageTests {
    @Test @MainActor func batchSharingValidatesEveryFileWithoutCreatingExportCopies() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TaskSessionStore(storageURL: directory.appendingPathComponent("sessions.jsonl"),
                                     videoStore: MovementVideoStore(directory: directory.appendingPathComponent("videos")))
        let first = try await save(trial(), session: MovementSession(patientId: "TEST", trials: []),
                                   temporary: temporaryVideo(in: directory), store: store)
        let second = try await save(trial(), session: MovementSession(patientId: "TEST", trials: []),
                                    temporary: temporaryVideo(in: directory), store: store)
        let trials = [first.trials[0], second.trials[0]]
        let urls = try store.videoStore.shareURLs(for: trials + trials)
        #expect(urls.count == 2 && Set(urls).count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("videos").path).count == 2)
        try store.videoStore.delete(trials[1])
        #expect(throws: (any Error).self) { try store.videoStore.shareURLs(for: trials) }
        #expect(FileManager.default.fileExists(atPath: urls[0].path))
    }
    @MainActor private func delete(_ ids: Set<UUID>, store: TaskSessionStore) async throws -> TaskSessionStore.VideoDeletionResult {
        try await withCheckedThrowingContinuation { continuation in
            store.deleteVideos(ids: ids) { continuation.resume(with: $0) }
        }
    }

    @Test @MainActor func deletingSelectedVideosKeepsMeasurementsAndDoesNotRestoreStaleLinks() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let json = dir.appendingPathComponent("sessions.jsonl")
        let store = TaskSessionStore(storageURL: json, videoStore: videos)
        var saved: [MovementSession] = []
        for _ in 0..<4 {
            saved.append(try await save(trial(), session: .init(patientId: "TEST"),
                                       temporary: temporaryVideo(in: dir), store: store))
        }
        let selected = Set(saved.suffix(3).flatMap(\.trials).map(\.id))
        let outcome = try await delete(selected, store: store)
        #expect(outcome.deletedCount == 3 && outcome.failedCount == 0)
        for original in saved {
            let restored = try #require(store.sessions.first { $0.id == original.id })
            #expect(restored.trials[0].metrics == original.trials[0].metrics)
            #expect(restored.trials[0].samples == original.trials[0].samples)
            #expect(restored.trials[0].startedAt == original.trials[0].startedAt)
            #expect(FileManager.default.fileExists(atPath: try videos.url(for: original.trials[0]).path)
                    == !selected.contains(original.trials[0].id))
            if selected.contains(original.trials[0].id) { #expect(restored.trials[0].video == nil) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.saveAcceptedSession(saved[3]) { continuation.resume(with: $0) }
        }
        #expect(store.sessions.first { $0.id == saved[3].id }?.trials.first?.video == nil)
        let decoded = JSONDecoder(); decoded.dateDecodingStrategy = .iso8601
        let persisted = try Data(contentsOf: json).split(separator: 10).map {
            try decoded.decode(MovementSession.self, from: Data($0))
        }
        #expect(persisted.count == 4 && persisted.flatMap(\.trials).filter { $0.video != nil }.count == 1)
        #expect(try await delete(selected, store: store).deletedCount == 0)
        let staleDraft = try temporaryVideo(in: dir)
        do {
            _ = try await save(saved[3].trials[0], session: saved[3], temporary: staleDraft, store: store)
            Issue.record("A deleted trial UUID must not acquire a movie through a stale retry")
        } catch {
            #expect(FileManager.default.fileExists(atPath: staleDraft.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("private").path).count == 1)
        }
        let retake = try await save(trial(), session: store.sessions.first { $0.id == saved[3].id }!,
                                   temporary: temporaryVideo(in: dir), store: store)
        #expect(retake.trials.first?.video != nil && retake.trials.first?.id != saved[3].trials[0].id)
    }

    @Test @MainActor func missingFileCanBeDeletedAndUnsafeReferenceFailsWithoutTouchingOtherFiles() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let store = TaskSessionStore(storageURL: dir.appendingPathComponent("sessions.jsonl"), videoStore: videos)
        let saved = try await save(trial(), session: .init(patientId: "TEST"), temporary: temporaryVideo(in: dir), store: store)
        try videos.delete(saved.trials[0])
        #expect(try await delete([saved.trials[0].id], store: store).deletedCount == 1)
        #expect(store.sessions[0].trials[0].video == nil)
        let unsafe = trial().withVideo(.init(fileName: "../protected.mov", byteCount: 4))
        let protected = dir.appendingPathComponent("protected.mov")
        try Data([9]).write(to: protected)
        let failed = try await save(unsafe, session: .init(patientId: "TEST"), temporary: nil, store: store)
        let result = try await delete([unsafe.id], store: store)
        #expect(result.failedCount == 1 && result.deletedCount == 0)
        #expect(try Data(contentsOf: protected) == Data([9]))
        #expect(store.sessions.first { $0.id == failed.id }?.trials.first?.video == unsafe.video)
    }

    @Test func deletingVideoMetadataPreservesUnknownFieldsAndUnrelatedLines() throws {
        let id = UUID()
        let input = Data("{\"custom\":42,\"trials\":[{\"id\":\"\(id)\",\"video\":{\"fileName\":\"x.mov\"},\"futureField\":true}]}\nlegacy invalid line\n".utf8)
        let result = try TaskSessionStore.removingVideoReferences(ids: [id], in: input)
        #expect(String(decoding: result, as: UTF8.self).hasSuffix("\nlegacy invalid line\n"))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(result.split(separator: 10)[0])) as? [String: Any])
        let record = try #require((object["trials"] as? [[String: Any]])?.first)
        #expect(object["custom"] as? Int == 42 && record["futureField"] as? Bool == true)
        #expect(record["video"] == nil && record["videoDeletedAt"] is String)
    }
    private func trial(side: BodySide = .right, source: SignalSource = .camera,
                       invalid: Bool = false) -> Trial {
        Trial(taskType: .fingerTap, side: side, source: source, stopCondition: .thirtySec,
            samples: [.init(t: 0, value: invalid ? .nan : 0.2)], metrics: .empty,
            recordedDurationSeconds: 30)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func temporaryVideo(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString + ".mov")
        try Data([1, 2, 3, 4]).write(to: url)
        return url
    }

    @MainActor private func save(_ trial: Trial, session: MovementSession, temporary: URL?,
                                 store: TaskSessionStore) async throws -> MovementSession {
        try await withCheckedThrowingContinuation { continuation in
            store.saveAcceptedTrial(trial, in: session, temporaryVideoURL: temporary) {
                continuation.resume(with: $0)
            }
        }
    }

    @Test func legacyTrialAndMedicationCopyKeepCompatibility() throws {
        let original = trial()
        let bytes = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(Trial.self, from: bytes).video == nil)
        let linked = original.withVideo(.init(fileName: "\(original.id.uuidString).mov", byteCount: 4))
        #expect(linked.withMedicationTiming(.init(status: .noneToday)).video == linked.video)
        #expect(linked.samples == original.samples && linked.metrics == original.metrics)
        #expect(linked.recordedDurationSeconds == 30)
        #expect(try JSONDecoder().decode(Trial.self, from: JSONEncoder().encode(linked)) == linked)
    }

    @Test @MainActor func acceptedVideoPersistsWithPrivateReferenceAndProtection() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = dir.appendingPathComponent("sessions.jsonl")
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let store = TaskSessionStore(storageURL: json, videoStore: videos)
        let source = try temporaryVideo(in: dir)
        let recording = trial()
        let saved = try await save(recording, session: .init(patientId: "TEST"), temporary: source, store: store)
        let accepted = try #require(saved.trials.first)
        #expect(accepted.video?.fileName == "\(recording.id.uuidString).mov")
        #expect(accepted.video?.byteCount == 4)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let privateURL = try videos.url(for: accepted)
        #expect(try Data(contentsOf: privateURL) == Data([1, 2, 3, 4]))
        #expect(try privateURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #if !targetEnvironment(simulator)
        // Simulator files use the Mac filesystem, not iOS hardware Data Protection.
        #expect(try FileManager.default.attributesOfItem(atPath: privateURL.path)[.protectionKey]
                as? String == FileProtectionType.complete.rawValue)
        #endif
        let line = try Data(contentsOf: json).split(separator: 10)[0]
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reloaded = try decoder.decode(MovementSession.self, from: Data(line))
        #expect(reloaded.trials[0].video == accepted.video)
        #expect(FileManager.default.fileExists(atPath: try videos.url(for: reloaded.trials[0]).path))
        #expect(store.sessions.count == 1)
    }

    @Test @MainActor func encodingFailureRollsBackVideoAndRetryKeepsSameMeasurement() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let json = dir.appendingPathComponent("sessions.jsonl")
        let store = TaskSessionStore(storageURL: json, videoStore: videos)
        let source = try temporaryVideo(in: dir)
        do {
            _ = try await save(trial(invalid: true), session: .init(patientId: "TEST"), temporary: source, store: store)
            Issue.record("Expected encoding failure")
        } catch {
            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(store.sessions.isEmpty)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("private").path).isEmpty)
        }
        let saved = try await save(trial(), session: .init(patientId: "TEST"), temporary: source, store: store)
        #expect(saved.trials.count == 1 && store.sessions.count == 1)
    }

    @Test @MainActor func diskFailurePreservesDraftAndPreviouslySavedVideo() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let store = TaskSessionStore(storageURL: dir.appendingPathComponent("sessions.jsonl"), videoStore: videos)
        let original = try await save(trial(), session: .init(patientId: "TEST"),
                                     temporary: temporaryVideo(in: dir), store: store)
        let oldURL = try videos.url(for: original.trials[0])
        let failing = TaskSessionStore(storageURL: dir.appendingPathComponent("missing/sessions.jsonl"), videoStore: videos)
        let draft = try temporaryVideo(in: dir)
        do {
            _ = try await save(trial(), session: original, temporary: draft, store: failing)
            Issue.record("Expected disk failure")
        } catch {
            #expect(FileManager.default.fileExists(atPath: oldURL.path))
            #expect(FileManager.default.fileExists(atPath: draft.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: oldURL.deletingLastPathComponent().path).count == 1)
            #expect(failing.sessions.isEmpty)
        }
    }

    @Test @MainActor func replacingAcceptedTaskRemovesOnlyItsPreviousVideo() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let store = TaskSessionStore(storageURL: dir.appendingPathComponent("sessions.jsonl"), videoStore: videos)
        let first = try await save(trial(), session: .init(patientId: "TEST"), temporary: temporaryVideo(in: dir), store: store)
        let both = try await save(trial(side: .left), session: first, temporary: temporaryVideo(in: dir), store: store)
        let oldRight = try videos.url(for: both.trials[0])
        let left = try videos.url(for: both.trials[1])
        let replaced = try await save(trial(), session: both, temporary: temporaryVideo(in: dir), store: store)
        #expect(replaced.id == first.id && replaced.trials.count == 2)
        #expect(!FileManager.default.fileExists(atPath: oldRight.path))
        #expect(FileManager.default.fileExists(atPath: left.path))
        #expect(store.sessions.count == 1)
    }

    @Test @MainActor func failedVideoCanBeSavedExplicitlyAsMeasurementOnly() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TaskSessionStore(storageURL: dir.appendingPathComponent("sessions.jsonl"),
            videoStore: MovementVideoStore(directory: dir.appendingPathComponent("private")))
        let recording = trial()
        let session = MovementSession(patientId: "TEST")
        do {
            _ = try await save(recording, session: session, temporary: dir.appendingPathComponent("missing.mov"), store: store)
            Issue.record("Expected missing video error")
        } catch { #expect(store.sessions.isEmpty) }
        let saved = try await save(recording, session: session, temporary: nil, store: store)
        #expect(saved.trials[0].id == recording.id && saved.trials[0].video == nil)
        #expect(saved.trials[0].samples == recording.samples)
    }

    @Test func emptyVideoAndUnsafeReferencesAreRejected() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir)
        let recording = trial()
        #expect(throws: (any Error).self) {
            try videos.url(for: recording.withVideo(.init(fileName: "../other.mov", byteCount: 4)))
        }
        let empty = dir.appendingPathComponent("empty.mov")
        try Data().write(to: empty)
        #expect(throws: (any Error).self) { try videos.save(empty, for: recording) }
        #expect(throws: (any Error).self) { try videos.save(dir, for: recording) }
        #expect(throws: (any Error).self) { try videos.save(temporaryVideo(in: dir), for: trial(source: .synthetic)) }
    }

    @Test @MainActor func duplicateSaveDoesNotDeleteExistingCommittedVideo() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let videos = MovementVideoStore(directory: dir.appendingPathComponent("private"))
        let store = TaskSessionStore(storageURL: dir.appendingPathComponent("sessions.jsonl"), videoStore: videos)
        let saved = try await save(trial(), session: .init(patientId: "TEST"), temporary: temporaryVideo(in: dir), store: store)
        let accepted = saved.trials[0]
        let draft = try temporaryVideo(in: dir)
        do {
            _ = try await save(accepted, session: saved, temporary: draft, store: store)
            Issue.record("Expected duplicate destination error")
        } catch {
            #expect(FileManager.default.fileExists(atPath: try videos.url(for: accepted).path))
            #expect(FileManager.default.fileExists(atPath: draft.path))
            #expect(store.sessions[0].trials == saved.trials)
        }
    }

    @Test func unacceptedDraftIsDeletedOnDiscardOrRelease() throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try temporaryVideo(in: dir)
        let second = try temporaryVideo(in: dir)
        var draft: MovementVideoDraft? = MovementVideoDraft()
        draft?.receive(first)
        draft?.receive(second)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        draft = nil
        #expect(!FileManager.default.fileExists(atPath: second.path))
        let missing = MovementVideoDraft()
        missing.receive(nil)
        #expect(missing.unavailable && missing.messageKey != nil)
        missing.discard()
        #expect(!missing.unavailable && missing.messageKey == nil)
    }

    #if DEBUG && targetEnvironment(simulator)
    @Test @MainActor func savedMovieRemainsPlayableWithoutAnAudioTrack() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await makeMovementVideoTestFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let videos = MovementVideoStore(directory: dir)
        let recording = trial()
        let linked = recording.withVideo(try videos.save(source, for: recording))
        let asset = AVURLAsset(url: try videos.url(for: linked))
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await asset.load(.duration).seconds > 0)
    }
    #endif
}

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

struct MovementTrendFilterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_797_000_000)

    private func trial(date: Date? = nil, medication: MedicationTiming? = nil,
                       source: SignalSource = .camera, rhythm: Double = 0.1,
                       duration: Double = 6) -> Trial {
        Trial(taskType: .fingerTap, side: .right, source: source, stopCondition: .thirtySec,
              startedAt: date ?? now,
              samples: (0..<60).map { .init(t: Double($0) / 10, value: sin(Double($0))) },
              metrics: MovementMetrics(cycleCount: 10, frequencyHz: 2, meanAmplitude: 0.2,
                                       amplitudeDecrementSlope: 0, rhythmCV: rhythm,
                                       pauseCount: 0, onsetLatencySec: 0, qualityIndex: 0.8),
              medicationTiming: medication, recordedDurationSeconds: duration)
    }
    private func includes(_ recording: Trial, filters: MovementTrendFilters,
                          context: StimulationContext = .preStim) -> Bool {
        filters.includes(recording, context: context, now: now, calendar: calendar)
    }

    @Test func plotOffersRateAndRhythmWithoutRemovingOtherStoredMetrics() {
        #expect(TrendMetric.plotCases == [.frequency, .rhythm])
        #expect(TrendMetric.patientCases.count == 6)
        #expect(TrendMetric.rhythm.plotValue(0.1) == 10)
        #expect(TrendMetric.frequency.plotValue(2) == 2)
    }

    @Test(arguments: StimulationContext.allCases)
    func contextsAreExactAndLegacyIsNotReinterpreted(context: StimulationContext) {
        var filters = MovementTrendFilters()
        #expect(includes(trial(), filters: filters, context: context))
        filters.context = context
        for candidate in StimulationContext.allCases {
            #expect(includes(trial(), filters: filters, context: candidate) == (candidate == context))
        }
    }

    @Test func doseWindowUsesRecordingTimeAndInclusiveBoundaries() {
        var filters = MovementTrendFilters()
        filters.medication = .sinceDose
        filters.minimumDoseHours = 1
        filters.maximumDoseHours = 3
        for (seconds, expected) in [(3599.0, false), (3600.0, true), (7200.0, true), (10800.0, true), (10801.0, false)] {
            let medication = MedicationTiming(status: .takenAt, takenAt: now.addingTimeInterval(-seconds))
            #expect(includes(trial(medication: medication), filters: filters) == expected)
        }
        #expect(!includes(trial(), filters: filters))
        filters.minimumDoseHours = 4
        #expect(!includes(trial(medication: .init(status: .takenAt, takenAt: now)), filters: filters))
    }

    @Test func unknownDoesNotMeanNoMedicationAndFutureOrStaleReportsAreUnknown() {
        var filters = MovementTrendFilters()
        filters.medication = .unknown
        for timing in [nil, MedicationTiming(status: .unsure),
                       MedicationTiming(status: .takenAt, takenAt: now.addingTimeInterval(1)),
                       MedicationTiming(status: .noneToday, confirmedAt: now.addingTimeInterval(-86400))] {
            #expect(includes(trial(medication: timing), filters: filters))
        }
        let none = trial(medication: .init(status: .noneToday, confirmedAt: now))
        #expect(!includes(none, filters: filters))
        filters.medication = .noneToday
        #expect(includes(none, filters: filters))
        #expect(!includes(trial(), filters: filters))
    }

    @Test(arguments: [TrendPeriod.week, .month])
    func dateWindowIncludesFirstDayMidnightButNotFutureRecordings(period: TrendPeriod) {
        var filters = MovementTrendFilters()
        filters.period = period
        let days = period == .week ? 7 : 30
        let first = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        #expect(includes(trial(date: first), filters: filters))
        #expect(!includes(trial(date: first.addingTimeInterval(-1)), filters: filters))
        #expect(includes(trial(date: now), filters: filters))
        #expect(!includes(trial(date: now.addingTimeInterval(1)), filters: filters))
    }

    @Test func summaryPreservesEveryShortRecordingAndSourceIsolationWithoutMutatingData() throws {
        let first = trial(date: now.addingTimeInterval(-10))
        let last = trial(duration: 30)
        let session = MovementSession(patientId: "TEST", trials: [last, trial(source: .synthetic), first])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(session)
        let summary = MovementTrendSummary(sessions: [session], task: .fingerTap, side: .right,
                                           metric: .frequency, source: .camera)
        #expect(summary.points.count == 2)
        #expect(summary.recordings.map(\.duration) == [6, 30])
        #expect(summary.recordings.last?.hasSignalGaps == true)
        #expect(summary.nearest(to: now.addingTimeInterval(-9))?.date == first.startedAt)
        #expect(try encoder.encode(session) == before)
        var filters = MovementTrendFilters()
        filters.context = .preStim
        let excluded = MovementTrendSummary(sessions: [session], task: .fingerTap, side: .right,
                                            metric: .frequency, filters: filters, source: .camera)
        #expect(excluded.unfilteredCount == 2)
        #expect(excluded.recordings.isEmpty)
    }

    @Test func zeroRhythmIsRealButPercentageOverflowIsUnavailable() {
        let session = MovementSession(patientId: "TEST", trials: [trial(rhythm: 0), trial(rhythm: .greatestFiniteMagnitude)])
        let summary = MovementTrendSummary(sessions: [session], task: .fingerTap, side: .right, metric: .rhythm)
        #expect(summary.points.count == 1)
        #expect(summary.points.first?.availability == .available(0))
        #expect(summary.unavailableCount == 1)
    }
}

struct MovementRecordingFeedbackTests {
    private func trial(samples: [TimestampedSample]? = nil, cycles: Int = 5,
                       quality: Double = 0.8, frequency: Double = 2,
                       recordedDurationSeconds: Double? = nil) -> Trial {
        Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
              samples: samples ?? (0...300).map { .init(t: Double($0) / 10, value: sin(Double($0) / 3)) },
              metrics: MovementMetrics(cycleCount: cycles, frequencyHz: frequency, meanAmplitude: 0.001,
                                       amplitudeDecrementSlope: -0.4, rhythmCV: 2, pauseCount: 4,
                                       onsetLatencySec: 4, qualityIndex: quality),
              recordedDurationSeconds: recordedDurationSeconds)
    }

    @Test func absentAndMalformedSignalNeverClaimsCaptureOrDisplaysMadeUpMetrics() {
        let invalid: [[TimestampedSample]] = [[], [.init(t: 0, value: 1)],
            Array(repeating: .init(t: 0, value: 1), count: 5),
            [.init(t: 0, value: 1), .init(t: 1, value: .nan), .init(t: 2, value: 1), .init(t: 3, value: 1)],
            [.init(t: 0, value: 1), .init(t: 2, value: 1), .init(t: 1, value: 1), .init(t: 3, value: 1)],
            [.init(t: -1, value: 1), .init(t: 0, value: 1), .init(t: 1, value: 1), .init(t: 2, value: 1)]]
        for samples in invalid {
            #expect(MovementRecordingFeedback(trial: trial(samples: samples)) == .missingSignal)
            #expect(!MovementSignalAssessment(samples: samples).hasPlottableSignal)
            #expect(TrendMetric.allCases.allSatisfy { $0.availability(for: trial(samples: samples)).value == nil })
        }
    }

    @Test func fewSamplesCanHaveARawPlotWithoutClaimingCalculatedValues() {
        let samples: [TimestampedSample] = [.init(t: 0, value: 0), .init(t: 0.1, value: 1)]
        let signal = MovementSignalAssessment(samples: samples)
        #expect(signal.hasPlottableSignal)
        #expect(!signal.hasAnalysisInput)
        #expect(MovementRecordingFeedback(trial: trial(samples: samples)) == .missingSignal)
    }

    @Test func flatSignalAndSlowMovementDoNotBecomeCaptureFailures() {
        let flat = trial(samples: (0...300).map { .init(t: Double($0) / 10, value: 0.1) }, cycles: 0)
        #expect(MovementRecordingFeedback(trial: flat) == .noDetectedCycles)
        #expect(MovementSignalAssessment(samples: flat.samples).hasAnalysisInput)
        let slow = trial(quality: 0, frequency: 0.01)
        #expect(MovementRecordingFeedback(trial: slow) == .captured)
        #expect(TrendMetric.frequency.availability(for: slow) == .available(0.01))
        #expect(TrendMetric.quality.availability(for: slow) == .available(0))
    }

    @Test func oneOrTwoCyclesHaveCalculationSpecificAvailability() {
        for cycles in [1, 2] {
            #expect(MovementRecordingFeedback(trial: trial(cycles: cycles)) == .someValuesUnavailable)
            #expect(TrendMetric.onset.availability(for: trial(cycles: cycles)).value != nil)
        }
        #expect(TrendMetric.frequency.availability(for: trial(cycles: 2)).value != nil)
        #expect(TrendMetric.rhythm.availability(for: trial(cycles: 2)) == .insufficientCycles)
    }

    @Test func hiddenExperimentalIndexDoesNotAffectPatientFeedback() {
        #expect(MovementRecordingFeedback(trial: trial(quality: .nan)) == .captured)
        #expect(MovementRecordingFeedback.captured.detailKey == "Movement values are available.")
    }

    @Test func gapsAreAdvisoryAndDoNotDiscardAvailableValues() {
        for gap in [1.99, 2.0, 8.0] {
            let samples: [TimestampedSample] = [0.0, 0.1, 0.2, 0.2 + gap, 0.3 + gap]
                .map { .init(t: $0, value: sin($0)) }
            let recording = trial(samples: samples)
            #expect(MovementSignalAssessment(samples: samples).hasGaps == (gap >= 2))
            #expect(MovementRecordingFeedback(trial: recording) == (gap >= 2 ? .signalGaps : .captured))
            #expect(TrendMetric.frequency.availability(for: recording) == .available(2))
        }
    }

    @Test func lateCaptureWarnsWithoutInferringWhyTrackingWasMissing() {
        let samples = (0..<10).map { TimestampedSample(t: 20 + Double($0) / 10, value: sin(Double($0))) }
        let recording = trial(samples: samples)
        #expect(MovementRecordingFeedback(trial: recording) == .signalGaps)
        #expect(TrendMetric.frequency.availability(for: recording) == .available(2))
    }

    @Test(arguments: [1.99, 2.0, 20.0])
    func trailingTrackingLossWarnsWithoutRejectingAvailableMetrics(gap: Double) {
        let end = 30 - gap
        let samples = (0...100).map { TimestampedSample(t: Double($0) * end / 100, value: sin(Double($0))) }
        let recording = trial(samples: samples, recordedDurationSeconds: 30)
        let signal = MovementSignalAssessment(samples: samples, recordedDurationSeconds: 30)
        #expect(signal.hasGaps == (gap >= 2))
        #expect(MovementRecordingFeedback(trial: recording) == (gap >= 2 ? .signalGaps : .captured))
        #expect(TrendMetric.frequency.availability(for: recording) == .available(2))
        #expect(signal.hasAnalysisInput)
    }

    @Test func manualStopAndUnknownHistoricalDurationDoNotInventTrailingLoss() {
        let samples = (0...100).map { TimestampedSample(t: Double($0) / 10, value: sin(Double($0))) }
        #expect(MovementRecordingFeedback(trial: trial(samples: samples, recordedDurationSeconds: 10)) == .captured)
        #expect(MovementRecordingFeedback(trial: trial(samples: samples)) == .captured)
    }

    @Test func recordingDurationSurvivesMedicationCopyAndJSONRoundTrip() throws {
        let recording = trial(recordedDurationSeconds: 30)
        let copy = recording.withMedicationTiming(.init(status: .unsure, confirmedAt: recording.startedAt))
        #expect(copy.recordedDurationSeconds == 30)
        let data = try JSONEncoder().encode(copy)
        #expect(try JSONDecoder().decode(Trial.self, from: data) == copy)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "recordedDurationSeconds")
        let oldRecording = try JSONDecoder().decode(Trial.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(oldRecording.recordedDurationSeconds == nil)
        #expect(oldRecording.samples == recording.samples)
        #expect(oldRecording.metrics == recording.metrics)
    }

    @Test func feedbackDoesNotChangeSamplesMetricsOrSessionData() throws {
        let session = MovementSession(patientId: "TEST", stimulationContext: .postStim, trials: [trial()])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(session)
        _ = MovementRecordingFeedback(trial: session.trials[0])
        _ = MovementSignalAssessment(samples: session.trials[0].samples)
        #expect(try encoder.encode(session) == before)
    }
}

struct MovementDemonstrationTests {
    @Test(arguments: [MovementTaskType.fingerTap, .handOpenClose], BodySide.allCases)
    func eachTaskHandUsesItsOwnBundledPlayableVideo(task: MovementTaskType, side: BodySide) async throws {
        let clip = try #require(MovementDemonstrationClip.clip(task: task, side: side))
        let videoSide = task == .handOpenClose ? (side == .left ? BodySide.right : .left) : side
        let expected = "\(task == .fingerTap ? "finger_tapping" : "fist")_\(videoSide.rawValue)"
        #expect(clip.fileName == expected)
        let url = try #require(clip.url)
        let asset = AVURLAsset(url: url)
        #expect(try await asset.load(.isPlayable))
        #expect(try await asset.load(.duration).seconds >= 33)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 854, height: 480))
        let transform = try await track.load(.preferredTransform)
        if task == .handOpenClose {
            let expectedTransform = videoSide == .left
                ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 854)
                : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 480, ty: 0)
            #expect(transform == expectedTransform)
            #expect(abs(clip.presentationAspectRatio - 480.0 / 560.0) < 0.000001)
            #expect(clip.maximumWidth == 170 && clip.cropsVerticalMargins)
        } else {
            #expect(transform == .identity)
            #expect(!clip.cropsVerticalMargins)
            #expect(clip.presentationAspectRatio == MovementDemonstrationClip.aspectRatio)
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: CMTime(seconds: 5, preferredTimescale: 600))
        #expect(frame.image.width == (task == .handOpenClose ? 480 : 854))
        #expect(frame.image.height == (task == .handOpenClose ? 854 : 480))
        #expect(abs(Double(MovementDemonstrationClip.aspectRatio) - 854.0 / 480.0) < 0.000001)
    }

    @Test func watchTaskDoesNotUseAnUnrelatedCameraDemo() {
        #expect(MovementDemonstrationClip.clip(task: .pronationSupination, side: .left) == nil)
        #expect(MovementDemonstrationClip.clip(task: .pronationSupination, side: .right) == nil)
    }

    @Test @MainActor func playbackIsSilentManualAndStopsCleanly() async throws {
        let playback = MovementDemonstrationPlayer()
        let clip = try #require(MovementDemonstrationClip.clip(task: .fingerTap, side: .left))
        await playback.load(url: clip.url, automaticallyPlays: false)
        defer { playback.stop() }
        let player = try #require(playback.player)
        #expect(player.isMuted && !playback.isPlaying && !playback.hasFailed)
        playback.play()
        #expect(playback.isPlaying)
        playback.suspend()
        playback.suspend()
        #expect(!playback.isPlaying)
        playback.resume()
        #expect(playback.isPlaying)
        playback.pause()
        playback.suspend()
        playback.resume()
        #expect(!playback.isPlaying)
        playback.stop()
        #expect(playback.player == nil && player.items().isEmpty && playback.elapsed == 0)
    }

    @Test @MainActor func automaticPlaybackLoopsAndCanBePaused() async throws {
        let playback = MovementDemonstrationPlayer()
        let clip = try #require(MovementDemonstrationClip.clip(task: .handOpenClose, side: .right))
        await playback.load(url: clip.url, automaticallyPlays: true)
        defer { playback.stop() }
        let player = try #require(playback.player)
        let item = try #require(player.currentItem)
        for _ in 0..<100 where item.status != .readyToPlay {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(item.status == .readyToPlay)
        let duration = try await item.asset.load(.duration).seconds
        await player.seek(to: CMTime(seconds: duration - 0.5, preferredTimescale: 600),
                          toleranceBefore: .zero, toleranceAfter: .zero)
        try await Task.sleep(for: .seconds(2))
        #expect(playback.isPlaying && !playback.hasFailed)
        #expect(player.currentTime().seconds < 5)
        playback.pause()
        #expect(player.rate == 0 && !playback.isPlaying)
    }

    @Test @MainActor func missingVideoFailsWithoutBlockingTheTask() async {
        let playback = MovementDemonstrationPlayer()
        await playback.load(url: nil, automaticallyPlays: true)
        #expect(playback.hasFailed && !playback.isLoading && playback.player == nil)
    }
}

struct MovementRecordingGuidanceTests {
    @Test
    func experimentalIndexIsNotAPatientMetric() {
        #expect(!TrendMetric.patientCases.contains(.quality))
        #expect(TrendMetric.patientCases.count == 6)
        #expect(TrendMetric.allCases.contains(.quality))
    }

    @Test(arguments: [MovementTaskType.fingerTap, .handOpenClose])
    func cameraGuideSwapsOnlyOpenCloseAndPreservesFingerTapping(task: MovementTaskType) {
        let left = MovementRecordingGuidance(taskType: task, side: .left)
        let right = MovementRecordingGuidance(taskType: task, side: .right)
        #expect(left.cameraGuideHorizontalScale == (task == .handOpenClose ? 1 : -1))
        #expect(right.cameraGuideHorizontalScale == (task == .handOpenClose ? -1 : 1))
        #expect(left.handKey == "Left hand")
        #expect(right.handKey == "Right hand")
    }

    @Test(arguments: MovementTaskType.allCases)
    func instructionSymbolsFaceTheReaderAndDoNotChangeCameraGuides(task: MovementTaskType) {
        let left = MovementRecordingGuidance(taskType: task, side: .left)
        let right = MovementRecordingGuidance(taskType: task, side: .right)
        #expect(right.taskIconHorizontalScale == (task == .handOpenClose ? -1 : 1))
        #expect(left.taskIconHorizontalScale == (task == .fingerTap ? -1 : 1))
        #expect(right.handIconHorizontalScale == -1)
        #expect(left.handIconHorizontalScale == 1)
    }

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
