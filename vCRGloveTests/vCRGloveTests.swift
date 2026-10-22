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

@Suite(.serialized)
@MainActor
struct StimulationProfileTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "stimulation-test-\(UUID().uuidString)")!
    }

    private func vm(_ defaults: UserDefaults) -> GloveVM {
        GloveVM(defaults: defaults, motorOutput: { _, _ in }, stopOutput: {}, recordEvent: { _, _ in })
    }

    @Test func freshInstallKeepsExistingPresetAndStartsLocked() throws {
        let model = vm(defaults())
        #expect(model.stimulationProfile == StimulationProfile())
        #expect(!model.researchUnlocked && !model.configurationNeedsReview)
        #expect(model.stimulationProfile.leftAmplitude == 70 && model.stimulationProfile.frequency == 1.5)
        #expect(StimulationProfile.pulseMs == 100 && StimulationProfile.slotsPerCycle == 4)
    }

    @Test func unlockingIsRequiredAndDoesNotPersist() {
        let storage = defaults()
        let model = vm(storage)
        var edited = StimulationProfile()
        edited.leftAmplitude = 35
        #expect(!model.saveStimulationProfile(edited))
        #expect(!model.unlockResearch(password: "incorrect"))
        #expect(model.unlockResearch(password: "vcr2026"))
        #expect(model.saveStimulationProfile(edited))
        model.lockResearch()
        #expect(!model.saveStimulationProfile(StimulationProfile()))
        let relaunched = vm(storage)
        #expect(!relaunched.researchUnlocked)
        #expect(relaunched.stimulationProfile == edited)
    }

    @Test func bothAmplitudesAndPatternSurviveRelaunch() throws {
        let storage = defaults()
        let profile = StimulationProfile(leftAmplitude: 31, rightAmplitude: 62,
                                         frequency: 2, pattern: .simultaneous)
        try StimulationProfileStore(defaults: storage).save(profile)
        let model = vm(storage)
        #expect(model.stimulationProfile == profile)
        #expect(profile.amplitude(for: "GloveL") == 31)
        #expect(profile.amplitude(for: "GloveR") == 62)
        #expect(profile.amplitude(for: "Glove Left") == 31)
        #expect(profile.amplitude(for: "Glove Right") == 62)
        #expect(profile.amplitude(for: "unknown") == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1, 101, 0.5, 34.9])
    func invalidAmplitudesAreRejected(_ value: Double) throws {
        let storage = defaults()
        var profile = StimulationProfile()
        profile.leftAmplitude = value
        #expect(!profile.isValid)
        #expect(throws: (any Error).self) { try StimulationProfileStore(defaults: storage).save(profile) }
        profile = StimulationProfile()
        profile.rightAmplitude = value
        #expect(!profile.isValid)
    }

    @Test(arguments: [Double.nan, .infinity, 0, 0.4, 2.6, 5])
    func overlappingOrInvalidFrequencyIsRejected(_ value: Double) {
        var profile = StimulationProfile()
        profile.frequency = value
        #expect(!profile.isValid)
    }

    @Test func maximumFrequencyFitsExistingPulseLength() {
        var profile = StimulationProfile()
        profile.frequency = StimulationProfile.frequencyRange.upperBound
        #expect(profile.isValid)
        #expect(profile.slotSpacing >= Double(StimulationProfile.pulseMs) / 1000)
        #expect(StimulationProfile(leftAmplitude: 0, rightAmplitude: 100).isValid)
    }

    @Test func invalidStoredProfileBlocksStimulationUntilStaffResaves() {
        let storage = defaults()
        storage.set(Data("broken".utf8), forKey: StimulationProfileStore.key)
        var commands = 0
        let model = GloveVM(defaults: storage, motorOutput: { _, _ in commands += 1 },
                            stopOutput: {}, recordEvent: { _, _ in })
        #expect(model.configurationNeedsReview)
        model.startVibration(position: "GloveL", durationSeconds: 10)
        model.startVibrationWithFingerCheck(positions: ["GloveL"])
        #expect(!model.hasStimulationSession && commands == 0)
        #expect(model.unlockResearch(password: "vcr2026"))
        #expect(model.saveStimulationProfile(StimulationProfile()))
        #expect(!model.configurationNeedsReview)
    }

    @Test func unknownSchemaCannotSilentlyRestoreDefaultDose() throws {
        let storage = defaults()
        var profile = StimulationProfile()
        profile.version = 2
        storage.set(try JSONEncoder().encode(profile), forKey: StimulationProfileStore.key)
        #expect(vm(storage).configurationNeedsReview)
        storage.set("not data", forKey: StimulationProfileStore.key)
        #expect(vm(storage).configurationNeedsReview)
    }

    @Test func legacyPatternsPreserveMotorOrderAndAllMotorMode() {
        var profile = StimulationProfile()
        #expect(profile.motorIndices(order: [3, 1, 0, 2]) == [[3], [1], [0], [2]])
        profile.pattern = .simultaneous
        let commands = profile.motorIndices(order: [3, 1, 0, 2])
        #expect(commands.count == 4 && commands.allSatisfy { $0 == Array(0..<20) })
    }

    @Test func sessionProfileStaysFixedAcrossPauseResumeAndJoiningGlove() throws {
        let storage = defaults()
        let original = StimulationProfile(leftAmplitude: 34, rightAmplitude: 58, pattern: .simultaneous)
        try StimulationProfileStore(defaults: storage).save(original)
        let model = vm(storage)
        #expect(model.unlockResearch(password: "vcr2026"))
        model.startVibration(position: "GloveL", durationSeconds: 50)
        #expect(!model.saveStimulationProfile(StimulationProfile()))
        model.pauseVibration(position: "GloveL")
        #expect(!model.saveStimulationProfile(StimulationProfile()))
        model.resumeVibration(position: "GloveL")
        model.startVibration(position: "GloveR", durationSeconds: 40)
        #expect(model.sessionProfile == original)
        #expect(model.countdowns["GloveR"] == 40)
        model.lockResearch()
        #expect(model.hasStimulationSession && model.sessionProfile == original)
        model.stopVibration(position: "GloveL")
        #expect(model.sessionProfile == original)
        model.stopVibration(position: "GloveR")
        #expect(model.sessionProfile == nil && !model.hasStimulationSession)
    }

    @Test func effectiveSettingsAreLoggedAtSaveAndStart() {
        var events: [(String, [String: String])] = []
        let model = GloveVM(defaults: defaults(), motorOutput: { _, _ in }, stopOutput: {},
                            recordEvent: { events.append(($0, $1)) })
        #expect(model.unlockResearch(password: "vcr2026"))
        let profile = StimulationProfile(leftAmplitude: 25, rightAmplitude: 45, pattern: .simultaneous)
        #expect(model.saveStimulationProfile(profile))
        model.startVibration(position: "GloveR", durationSeconds: 20)
        model.stopVibration(position: "GloveR")
        #expect(events.first { $0.0 == "stimulation_profile_saved" }?.1["previous_leftAmplitude"] == "70.0")
        let start = events.first { $0.0 == "stimulation_started" }?.1
        #expect(start?["effectiveAmplitude"] == "45.0" && start?["pattern"] == "simultaneous")
        #expect(start?["durationSeconds"] == "20" && start?["pulseMs"] == "100")
    }

    @Test func unknownGloveCannotReceiveStimulation() {
        var commands = 0
        let model = GloveVM(defaults: defaults(), motorOutput: { _, _ in commands += 1 },
                            stopOutput: {}, recordEvent: { _, _ in })
        model.startVibration(position: "OtherDevice", durationSeconds: 20)
        model.startVibrationWithFingerCheck(positions: ["OtherDevice"], durationSeconds: 20)
        #expect(commands == 0 && !model.hasStimulationSession)
    }

    @Test func testBuzzUsesSavedHandAmplitudeAndIsBlockedWhilePaused() throws {
        let storage = defaults()
        try StimulationProfileStore(defaults: storage).save(StimulationProfile(leftAmplitude: 24, rightAmplitude: 52))
        var commands: [[UInt8]] = []
        let model = GloveVM(defaults: storage, motorOutput: { _, motors in commands.append(motors) },
                            stopOutput: {}, recordEvent: { _, _ in })
        let glove = try JSONDecoder().decode(HDevice.self, from: Data("""
            {"id":"left","position":"GloveL","isConnected":true}
            """.utf8))
        model.testBuzz(device: glove)
        #expect(commands.last == Array(repeating: UInt8(24), count: 20))
        model.startVibration(position: "GloveL", durationSeconds: 50)
        model.pauseVibration(position: "GloveL")
        let count = commands.count
        model.testBuzz(device: glove)
        #expect(commands.count == count)
        model.stopVibration(position: "GloveL")
    }

    @Test func simultaneousMotorCommandsUseRightHandAmplitude() async throws {
        let storage = defaults()
        try StimulationProfileStore(defaults: storage).save(
            StimulationProfile(leftAmplitude: 23, rightAmplitude: 51, frequency: 2, pattern: .simultaneous))
        var commands: [(String, [UInt8])] = []
        let model = GloveVM(defaults: storage, motorOutput: { commands.append(($0, $1)) },
                            stopOutput: {}, recordEvent: { _, _ in })
        model.startVibration(position: "GloveR", durationSeconds: 20)
        for _ in 0..<40 {
            if commands.contains(where: { $0.1.contains(51) }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        model.stopVibration(position: "GloveR")
        let on = commands.filter { $0.1.contains { $0 > 0 } }
        #expect(!on.isEmpty)
        #expect(on.allSatisfy { $0.0 == "GloveR" && $0.1 == Array(repeating: UInt8(51), count: 20) })
    }

    @Test func stoppingFingerCheckPreventsDelayedRestartAndUsesSavedAmplitude() async throws {
        let storage = defaults()
        try StimulationProfileStore(defaults: storage).save(StimulationProfile(leftAmplitude: 22, rightAmplitude: 49))
        var commands: [(String, [UInt8])] = []
        let model = GloveVM(defaults: storage, motorOutput: { commands.append(($0, $1)) },
                            stopOutput: {}, recordEvent: { _, _ in })
        model.startVibrationWithFingerCheck(positions: ["GloveL", "GloveR"], durationSeconds: 20)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.isCheckingFingers)
        #expect(commands.contains { $0.1.contains(22) })
        model.stopVibration(position: "GloveL")
        model.stopVibration(position: "GloveR")
        let count = commands.count
        try await Task.sleep(for: .milliseconds(800))
        #expect(commands.count == count)
        #expect(!model.isCheckingFingers && !model.hasStimulationSession)
    }

    @Test func queuedPulsesCannotFireAfterPauseOrStop() async throws {
        var commands: [[UInt8]] = []
        let model = GloveVM(defaults: defaults(), motorOutput: { _, motors in commands.append(motors) },
                            stopOutput: {}, recordEvent: { _, _ in })
        model.startVibration(position: "GloveL", durationSeconds: 20)
        for _ in 0..<40 {
            if commands.contains(where: { $0.contains(70) }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(commands.contains { $0.contains(70) })
        model.pauseVibration(position: "GloveL")
        let pausedCount = commands.count
        try await Task.sleep(for: .milliseconds(700))
        #expect(commands.count == pausedCount)
        model.resumeVibration(position: "GloveL")
        model.stopVibration(position: "GloveL")
        let stoppedCount = commands.count
        try await Task.sleep(for: .milliseconds(750))
        #expect(commands.count == stoppedCount)
    }
}

@MainActor
struct StudyInformationTests {
    @Test func informationTopicsHaveStableOrderAndEndWithContact() {
        #expect(StudyInformationTopic.allCases.map(\.rawValue) == [
            "study", "participation", "devices", "safety", "privacy", "contact"])
    }

    @Test func everySectionAndParagraphHasAUniqueIdentifier() {
        for topic in StudyInformationTopic.allCases {
            let sections = topic.sections
            if topic == .contact {
                #expect(sections.isEmpty)
                continue
            }
            #expect(!sections.isEmpty)
            #expect(Set(sections.map(\.id)).count == sections.count)
            let paragraphs = sections.flatMap(\.paragraphKeys)
            #expect(!paragraphs.isEmpty && Set(paragraphs).count == paragraphs.count)
            #expect(paragraphs.allSatisfy {
                $0.hasPrefix("study.\(topic.rawValue).") || (topic == .devices && $0.hasPrefix("privacy.app."))
            })
        }
    }

    @Test func privacyIncludesEveryRightsSectionAndNoConsentAction() {
        let sections = StudyInformationTopic.privacy.sections
        #expect(sections.map(\.id) == ["intro", "basis", "responsible", "access", "rectification",
            "erasure", "restriction", "portability", "objection", "withdrawal", "contacts", "definitions", "ethics"])
        let paragraphs = sections.flatMap(\.paragraphKeys)
        #expect(paragraphs.contains("study.privacy.withdrawal.body"))
        #expect(paragraphs.contains("study.privacy.complaint"))
        #expect(paragraphs.last == "study.privacy.ethics")
        #expect(!paragraphs.contains { $0.contains("video") || $0.contains("accept") })
    }

    @Test func devicesRetainsEveryAppDataAndVideoExplanationOutsideTheLegalNotice() {
        let sections = StudyInformationTopic.devices.sections
        #expect(sections.map(\.id) == ["devices", "storage", "videos"])
        #expect(sections.dropFirst().flatMap(\.paragraphKeys) == [
            "privacy.app.localData", "privacy.app.videoCapture", "privacy.app.videoStorage",
            "privacy.app.videoSharing", "privacy.app.videoDeletion"])
    }
}

@MainActor
struct JournalPersistenceTests {
    private func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("journal_entries.json")
    }

    @Test func oldEntriesDecodeWithoutInventingSaveTimes() throws {
        let json = """
        {"id":"11111111-1111-1111-1111-111111111111","date":12345,"type":"symptm","note":"Legacy"}
        """
        let entry = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        #expect(entry.type == .symptom && entry.note == "Legacy")
        #expect(entry.symptoms.isEmpty && entry.medicationFactors.isEmpty)
        #expect(entry.createdAt == nil && entry.updatedAt == nil)
        #expect(entry.checkInVersion == nil && entry.activityImpact == nil && entry.medicationSummary == nil)
        #expect(entry.medicationChanges.isEmpty)
        #expect(entry.date == Date(timeIntervalSinceReferenceDate: 12345))
    }

    @Test func twoQuestionCheckInCreatesNoMedicationOrSymptomEvents() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JournalStore(storageURL: url)
        #expect(!store.saveMoodAndImpactCheckIn(date: Date(), mood: nil, impact: nil))
        #expect(!store.saveMoodAndImpactCheckIn(date: Date(), mood: 0, impact: nil))
        #expect(store.entries.isEmpty)
        #expect(store.saveMoodAndImpactCheckIn(date: Date(), mood: 3, impact: .little))
        let result = try #require(JournalStore(storageURL: url).entries.first)
        #expect(result.checkInVersion == 3 && result.mood == 3 && result.activityImpact == .little)
        #expect(result.medicationSummary == nil && result.medicationChanges.isEmpty)
        #expect(result.medicationEvent == nil && result.symptomSeverity == nil && result.symptoms.isEmpty)
        #expect(result.checkInSummary.contains(MoodRating.neutral.checkInLabel))
        #expect(store.entries.count == 1)
        #expect(MedicationTiming.latestIntake(in: [result], before: Date()) == nil)
    }

    @Test func simplifiedEditPreservesHiddenLegacyAnswersAndUnknownMetadata() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var old = JournalEntry(type: .dailyCheckIn, mood: 2, symptomSeverity: .severe,
            symptoms: ["Tremor"], medicationName: "A", medicationDose: "100 mg", note: "Preserve")
        old.activityImpact = .skipped
        old.medicationSummary = .changed
        old.medicationChanges = [.late, .extra]
        old.checkInVersion = 2
        old.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        var records = try JSONSerialization.jsonObject(with: JSONEncoder().encode([old])) as! [[String: Any]]
        records[0]["researchMetadata"] = ["preserve": true]
        try JSONSerialization.data(withJSONObject: records).write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.saveMoodAndImpactCheckIn(date: old.date, mood: 4, impact: .moderate))
        let restored = JournalStore(storageURL: url)
        let result = try #require(restored.entries.first)
        #expect(result.id == old.id && result.createdAt == old.createdAt && result.date == old.date)
        #expect(result.checkInVersion == 2 && result.mood == 4 && result.activityImpact == .moderate)
        #expect(result.medicationSummary == old.medicationSummary && result.medicationChanges == old.medicationChanges)
        #expect(result.symptomSeverity == old.symptomSeverity && result.symptoms == old.symptoms)
        #expect(result.medicationName == old.medicationName && result.medicationDose == old.medicationDose)
        #expect(result.note == old.note && result.updatedAt != nil)
        #expect(!result.checkInSummary.contains(DailyMedicationChange.late.label))
        #expect(result.detailSummary.contains(DailyMedicationChange.late.label))
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        #expect((saved[0]["researchMetadata"] as? [String: Bool])?["preserve"] == true)
        #expect(restored.entries.count == 1 && MedicationTiming.latestIntake(in: restored.entries, before: Date()) == nil)
    }

    @Test func simplifiedFailedSaveLeavesOriginalAnswersIntactAndCanRetry() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var fail = false
        let store = JournalStore(storageURL: url, writeData: { data, destination in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: destination, options: .atomic)
        })
        let date = Date()
        #expect(store.saveMoodAndImpactCheckIn(date: date, mood: 2, impact: .large))
        let old = try #require(store.entries.first)
        let bytes = try Data(contentsOf: url)
        fail = true
        #expect(!store.saveMoodAndImpactCheckIn(date: date, mood: 4, impact: .little))
        #expect(store.entries[0].mood == old.mood && store.entries[0].updatedAt == old.updatedAt)
        #expect(try Data(contentsOf: url) == bytes)
        fail = false
        #expect(store.saveMoodAndImpactCheckIn(date: date, mood: 4, impact: .little))
        #expect(store.entries.count == 1 && store.entries[0].id == old.id && store.entries[0].mood == 4)
    }

    @Test func simplifiedEditDoesNotAssignVersionToUnknownLegacyFormat() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = JournalEntry(type: .dailyCheckIn, symptomSeverity: .mild, symptoms: ["Slowness"])
        try JSONEncoder().encode([old]).write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.saveMoodAndImpactCheckIn(date: old.date, mood: nil, impact: .unsure))
        let result = try #require(JournalStore(storageURL: url).entries.first)
        #expect(result.checkInVersion == nil && result.symptomSeverity == .mild && result.symptoms == old.symptoms)
        #expect(result.mood == nil && result.activityImpact == .unsure)
    }

    @Test func savedCheckInSurvivesRelaunchAndEditKeepsItsIdentity() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let savedAt = day.addingTimeInterval(86400)
        var clock = savedAt
        let store = JournalStore(storageURL: url, now: { clock })
        #expect(store.saveDailyCheckIn(date: day, mood: 4, severity: .mild, symptoms: ["Tremor"]))
        let original = try #require(store.entries.first)
        #expect(original.date == day && original.createdAt == savedAt && original.updatedAt == savedAt)
        clock = savedAt.addingTimeInterval(120)
        #expect(store.saveDailyCheckIn(date: day, mood: 3, severity: .moderate, symptoms: ["Slowness"]))
        let restored = JournalStore(storageURL: url)
        let edited = try #require(restored.dailyCheckIn(on: day))
        #expect(restored.entries.count == 1 && edited.id == original.id)
        #expect(edited.date == day && edited.createdAt == savedAt && edited.updatedAt == clock)
        #expect(edited.mood == 3 && edited.symptomSeverity == .moderate && edited.symptoms == ["Slowness"])
    }

    @Test func editingLegacyCheckInKeepsOtherEntriesAndUnknownMetadata() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = JournalEntry(date: day, type: .dailyCheckIn, mood: 2, note: "Keep earlier check-in")
        let latest = JournalEntry(date: day, type: .dailyCheckIn, mood: 3, note: "Keep note")
        let medication = JournalEntry(date: day, type: .medication, medicationName: "Medicine",
                                       medicationDose: "100 mg", medicationEvent: .usual)
        var records = try JSONSerialization.jsonObject(with: JSONEncoder().encode([first, latest, medication])) as! [[String: Any]]
        records[1]["futureResearchContext"] = ["keep": true]
        try JSONSerialization.data(withJSONObject: records).write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.latestDailyCheckIn?.id == latest.id)
        #expect(store.saveDailyCheckIn(date: day, mood: 5, severity: .mild, symptoms: []))
        #expect(store.entries.map(\.id) == [first.id, latest.id, medication.id])
        #expect(store.entries[0].mood == 2 && store.entries[1].note == "Keep note")
        #expect(store.entries[1].createdAt == nil && store.entries[1].updatedAt != nil)
        #expect(store.entries[2].medicationName == "Medicine" && store.entries[2].medicationDose == "100 mg")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        #expect((saved[1]["futureResearchContext"] as? [String: Bool])?["keep"] == true)
    }

    @Test func failedWritesKeepLastSavedDataAndAllowRetry() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var fail = false
        let store = JournalStore(storageURL: url, writeData: { data, destination in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: destination, options: .atomic)
        })
        let day = Date()
        #expect(store.saveDailyCheckIn(date: day, mood: 2, severity: .mild, symptoms: []))
        let bytes = try Data(contentsOf: url)
        let original = try #require(store.entries.first)
        fail = true
        #expect(!store.saveDailyCheckIn(date: day, mood: 5, severity: .severe, symptoms: ["Tremor"]))
        #expect(!store.add(JournalEntry(type: .note, note: "Unwritten draft")))
        #expect(store.entries.count == 1 && store.entries[0].mood == 2)
        #expect(store.entries[0].updatedAt == original.updatedAt)
        #expect(try Data(contentsOf: url) == bytes && store.saveErrorMessage != nil)
        fail = false
        #expect(store.saveDailyCheckIn(date: day, mood: 5, severity: .severe, symptoms: ["Tremor"]))
        #expect(store.entries.count == 1 && store.entries[0].id == original.id)
        #expect(store.saveErrorMessage == nil && JournalStore(storageURL: url).entries[0].mood == 5)
    }

    @Test func corruptFileIsNeverOverwrittenByANewEntry() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let corrupt = Data("[{incomplete journal".utf8)
        try corrupt.write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.isLoadBlocked && store.entries.isEmpty)
        #expect(!store.add(JournalEntry(type: .note, note: "Do not replace old data")))
        #expect(!store.saveDailyCheckIn(date: Date(), mood: 3, severity: .mild, symptoms: []))
        #expect(try Data(contentsOf: url) == corrupt && store.saveErrorMessage != nil)
    }

    @Test func duplicateRecordIDsBlockUnsafeRewrites() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let entry = JournalEntry(type: .note, note: "Keep")
        let data = try JSONEncoder().encode([entry, entry])
        try data.write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.isLoadBlocked && !store.add(JournalEntry(type: .note)))
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func medicationEventKeepsEventTimeAndCheckInSummaryIgnoresOtherTypes() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let eventAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let savedAt = eventAt.addingTimeInterval(3600)
        let store = JournalStore(storageURL: url, now: { savedAt })
        #expect(store.latestDailyCheckIn == nil)
        #expect(store.saveDailyCheckIn(date: eventAt, mood: 4, severity: .mild, symptoms: []))
        let checkIn = try #require(store.latestDailyCheckIn)
        let medication = JournalEntry(date: savedAt, type: .medication, medicationEvent: .late)
        #expect(store.add(medication))
        #expect(store.entries.last?.date == savedAt && store.entries.last?.createdAt == savedAt)
        #expect(store.latestDailyCheckIn?.id == checkIn.id)
        #expect(!store.add(medication) && store.entries.count == 2)
    }

    @Test func differentCalendarDaysKeepSeparateCheckIns() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = Calendar.current.startOfDay(for: Date())
        let second = try #require(Calendar.current.date(byAdding: .day, value: 1, to: first))
        let store = JournalStore(storageURL: url)
        #expect(store.saveDailyCheckIn(date: first, mood: 2, severity: .moderate, symptoms: []))
        #expect(store.saveDailyCheckIn(date: second, mood: 4, severity: .mild, symptoms: []))
        #expect(store.entries.count == 2 && store.latestDailyCheckIn?.date == second)
    }

    @Test func eventEditsPreserveIdentityIntakeLinksAndUnownedFields() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let oldTime = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let newTime = oldTime.addingTimeInterval(3600)
        let medication = JournalEntry(date: oldTime, type: .medication, medicationName: "A",
            medicationDose: "100 mg", note: "Old", medicationEvent: .usual, createdAt: oldTime)
        let symptom = JournalEntry(date: oldTime, type: .symptom, mood: 2, symptomSeverity: .mild,
            symptoms: ["Legacy symptom"], symptomEpisodeType: .off)
        var records = try JSONSerialization.jsonObject(with: JSONEncoder().encode([medication, symptom])) as! [[String: Any]]
        records[0]["studyContext"] = ["preserve": true]
        try JSONSerialization.data(withJSONObject: records).write(to: url)
        let store = JournalStore(storageURL: url, now: { newTime })
        #expect(store.updateMedication(id: medication.id, date: newTime, event: .late,
            motorState: .off, factors: [.food], note: "Corrected"))
        #expect(store.updateSymptom(id: symptom.id, date: newTime, severity: .moderate,
            symptoms: ["Legacy symptom", "Tremor"], motorState: .on, note: nil))
        let restored = JournalStore(storageURL: url)
        #expect(restored.entries.map(\.id) == [medication.id, symptom.id])
        let edited = restored.entries[0]
        #expect(edited.date == newTime && edited.createdAt == oldTime && edited.updatedAt == newTime)
        #expect(edited.medicationName == "A" && edited.medicationDose == "100 mg")
        #expect(edited.medicationEvent == .late && edited.medicationFactors == [.food] && edited.note == "Corrected")
        #expect(restored.entries[1].mood == 2 && restored.entries[1].symptomEpisodeType == .off)
        #expect(restored.entries[1].symptoms == ["Legacy symptom", "Tremor"])
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [[String: Any]]
        #expect((saved[0]["studyContext"] as? [String: Bool])?["preserve"] == true)
    }

    @Test func failedOrMismatchedEventEditsLeaveSavedDataUntouched() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var fail = false
        let store = JournalStore(storageURL: url, writeData: { data, destination in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: destination, options: .atomic)
        })
        let medication = JournalEntry(type: .medication, medicationEvent: .usual)
        #expect(store.add(medication))
        let bytes = try Data(contentsOf: url)
        fail = true
        #expect(!store.updateMedication(id: medication.id, date: Date(), event: .missed,
            motorState: nil, factors: [], note: "Not saved"))
        #expect(!store.updateSymptom(id: medication.id, date: Date(), severity: .severe,
            symptoms: ["Tremor"], motorState: nil, note: nil))
        #expect(!store.updateMedication(id: UUID(), date: Date(), event: .late,
            motorState: nil, factors: [], note: nil))
        #expect(store.entries.count == 1 && store.entries[0].medicationEvent == .usual)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func quickCheckInAddsNewMeasuresWithoutRecodingLegacySeverity() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = JournalEntry(type: .dailyCheckIn, mood: 2, symptomSeverity: .severe,
            symptoms: ["Legacy symptom"], note: "Preserve note")
        try JSONEncoder().encode([old]).write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.entries[0].activityImpact == nil && store.entries[0].medicationSummary == nil)
        #expect(store.saveQuickCheckIn(date: old.date, mood: 3, impact: .little, medication: .changed,
            changes: [.late, .other], severity: old.symptomSeverity, symptoms: old.symptoms))
        let restored = JournalStore(storageURL: url)
        let result = try #require(restored.entries.first)
        #expect(restored.entries.count == 1 && result.id == old.id && result.note == old.note)
        #expect(result.symptomSeverity == .severe && result.symptoms == old.symptoms)
        #expect(result.activityImpact == .little && result.medicationSummary == .changed)
        #expect(result.checkInVersion == 2 && result.medicationChanges == [.late, .other])
        #expect(result.detailSummary.contains(String(format: L10n("Medication: %@"), DailyMedicationSummary.changed.label)))
        #expect(MedicationTiming.latestIntake(in: restored.entries, before: Date()) == nil)
    }

    @Test func partialUnsureAndSkippedAnswersNeverBecomeNormalAnswers() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JournalStore(storageURL: url)
        let day = Date()
        #expect(!store.saveQuickCheckIn(date: day, mood: nil, impact: nil, medication: nil,
            changes: [], severity: nil, symptoms: []))
        #expect(store.entries.isEmpty)
        #expect(store.saveQuickCheckIn(date: day, mood: 4, impact: nil, medication: nil,
            changes: [], severity: nil, symptoms: []))
        #expect(store.entries[0].activityImpact == nil && store.entries[0].medicationSummary == nil)
        #expect(store.saveQuickCheckIn(date: day, mood: nil, impact: .unsure, medication: .skipped,
            changes: [.missed], severity: nil, symptoms: []))
        #expect(store.entries[0].activityImpact == .unsure && store.entries[0].medicationSummary == .skipped)
        #expect(store.entries[0].medicationChanges.isEmpty)
        #expect(store.saveQuickCheckIn(date: day, mood: nil, impact: .skipped, medication: .nonePlanned,
            changes: [], severity: nil, symptoms: []))
        #expect(store.entries[0].activityImpact == .skipped && store.entries[0].medicationSummary == .nonePlanned)
        #expect(store.saveQuickCheckIn(date: day, mood: nil, impact: .notAtAll, medication: .asPlanned,
            changes: [.late], severity: nil, symptoms: []))
        let result = try #require(JournalStore(storageURL: url).entries.first)
        #expect(result.activityImpact == .notAtAll && result.medicationSummary == .asPlanned)
        #expect(result.mood == nil && result.symptomSeverity == nil && result.medicationChanges.isEmpty)
    }

    @Test func failedQuickCheckInEditRetainsOriginalMeasures() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var fail = false
        let store = JournalStore(storageURL: url, writeData: { data, destination in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: destination, options: .atomic)
        })
        let day = Date()
        #expect(store.saveQuickCheckIn(date: day, mood: 4, impact: .moderate, medication: .changed,
            changes: [.late], severity: nil, symptoms: []))
        let bytes = try Data(contentsOf: url)
        fail = true
        #expect(!store.saveQuickCheckIn(date: day, mood: 1, impact: .large, medication: .asPlanned,
            changes: [], severity: nil, symptoms: []))
        #expect(store.entries[0].activityImpact == .moderate && store.entries[0].medicationChanges == [.late])
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func activityRatingsHaveOneIncreasingOrderWithoutUnknownOrSkipped() throws {
        #expect(DailyActivityImpact.ratingChoices == [.notAtAll, .little, .moderate, .large, .unable])
        #expect(!DailyActivityImpact.ratingChoices.contains(.unsure))
        #expect(!DailyActivityImpact.ratingChoices.contains(.skipped))
        for value in DailyActivityImpact.allCases {
            #expect(try JSONDecoder().decode(DailyActivityImpact.self, from: JSONEncoder().encode(value)) == value)
        }
    }

    @Test func directMedicationChangesSurviveAndExclusiveAnswersClearThem() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = JournalStore(storageURL: url)
        let day = Date()
        #expect(store.saveQuickCheckIn(date: day, mood: nil, impact: nil, medication: .changed,
            changes: [.late, .missed, .extra], severity: nil, symptoms: []))
        let original = try #require(JournalStore(storageURL: url).entries.first)
        #expect(original.medicationChanges == [.late, .missed, .extra])
        for answer in [DailyMedicationSummary.asPlanned, .nonePlanned, .unsure] {
            #expect(store.saveQuickCheckIn(date: day, mood: nil, impact: nil, medication: answer,
                changes: [.late, .missed], severity: nil, symptoms: []))
            let result = try #require(JournalStore(storageURL: url).entries.first)
            #expect(result.id == original.id && result.medicationSummary == answer)
            #expect(result.medicationChanges.isEmpty)
            #expect(MedicationTiming.latestIntake(in: [result], before: Date()) == nil)
        }
    }

    @Test func changingMoodPreservesLegacySkippedAndUnspecifiedChangeAnswers() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        for medication in [DailyMedicationSummary.skipped, .changed] {
            var old = JournalEntry(type: .dailyCheckIn, mood: 2, note: "Keep legacy context")
            old.activityImpact = .skipped
            old.medicationSummary = medication
            old.checkInVersion = 2
            try JSONEncoder().encode([old]).write(to: url)
            let store = JournalStore(storageURL: url)
            #expect(store.saveQuickCheckIn(date: old.date, mood: 4, impact: old.activityImpact,
                medication: old.medicationSummary, changes: old.medicationChanges,
                severity: old.symptomSeverity, symptoms: old.symptoms))
            let result = try #require(JournalStore(storageURL: url).entries.first)
            #expect(result.id == old.id && result.note == old.note)
            #expect(result.mood == 4 && result.activityImpact == .skipped)
            #expect(result.medicationSummary == medication && result.medicationChanges.isEmpty)
        }
    }

    @Test func legacyEventCorrectionsKeepMissingAnswersMissing() throws {
        let url = try location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let medication = JournalEntry(type: .medication, medicationName: "A", medicationDose: "100 mg")
        let symptom = JournalEntry(type: .symptom, note: "Legacy")
        try JSONEncoder().encode([medication, symptom]).write(to: url)
        let store = JournalStore(storageURL: url)
        #expect(store.updateMedication(id: medication.id, date: medication.date, event: nil,
            motorState: nil, factors: [], note: "Corrected"))
        #expect(store.updateSymptom(id: symptom.id, date: symptom.date, severity: nil,
            symptoms: [], motorState: nil, note: "Corrected"))
        let restored = JournalStore(storageURL: url)
        #expect(restored.entries.count == 2 && restored.entries[0].medicationEvent == nil)
        #expect(restored.entries[0].motorState == nil && restored.entries[0].medicationName == "A")
        #expect(restored.entries[1].symptomSeverity == nil && restored.entries[1].symptoms.isEmpty)
        #expect(restored.entries.allSatisfy { $0.note == "Corrected" && $0.createdAt == nil })
        #expect(MedicationTiming.latestIntake(in: restored.entries, before: Date()) == nil)
    }
}

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
            #expect(restored.trials[0].fingerTappingAngle == original.trials[0].fingerTappingAngle)
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
            recordedDurationSeconds: 30,
            fingerTappingAngle: source == .camera ? .init(samples: [.init(t: 0, degrees: 0), .init(t: 0.1, degrees: nil)]) : nil)
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
        #expect(reloaded.trials[0].fingerTappingAngle == recording.fingerTappingAngle)
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
        draft?.receive(first, captureStartPTSSeconds: 1000)
        #expect(draft?.captureStartPTSSeconds == 1000)
        draft?.receive(second)
        #expect(draft?.captureStartPTSSeconds == nil)
        #expect(!FileManager.default.fileExists(atPath: first.path))
        draft = nil
        #expect(!FileManager.default.fileExists(atPath: second.path))
        let missing = MovementVideoDraft()
        missing.receive(nil)
        #expect(missing.captureStartPTSSeconds == nil)
        #expect(missing.unavailable && missing.messageKey != nil)
        missing.discard()
        #expect(!missing.unavailable && missing.messageKey == nil)
    }

    #if DEBUG && targetEnvironment(simulator)
    @Test @MainActor func timingSurvivesMovieAcceptanceSnapshotAndMissingMetadataFallback() async throws {
        let dir = try directory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = try await makeMovementVideoTestFixture()
        defer { try? FileManager.default.removeItem(at: source) }
        let recording = Trial(taskType: .fingerTap, side: .right, source: .camera,
            stopCondition: .thirtySec, startUptime: 1000.125,
            samples: [.init(t: 0, value: 1)], metrics: .empty)
        let store = TaskSessionStore(storageURL: dir.appendingPathComponent("sessions.jsonl"),
            videoStore: MovementVideoStore(directory: dir.appendingPathComponent("videos")))
        let accepted: MovementSession = try await withCheckedThrowingContinuation { continuation in
            store.saveAcceptedTrial(recording, in: MovementSession(patientId: "TIMING-TEST"),
                temporaryVideoURL: source, videoCaptureStartPTSSeconds: 1000) {
                continuation.resume(with: $0)
            }
        }
        let timing = try #require(accepted.trials[0].video?.timing)
        #expect(timing.firstFrameTrialTimeSeconds == -0.125)
        #expect(timing.firstFrameMoviePTSSeconds >= 0)
        #expect(abs(try #require(timing.movieTime(forTrialTime: 0))
            - timing.firstFrameMoviePTSSeconds - 0.125) < 1e-10)
        let destination = dir.appendingPathComponent("snapshot")
        #expect(try await store.copyExportSnapshot(to: destination).isEmpty)
        let raw = try Data(contentsOf: destination.appendingPathComponent("tasks/sessions.jsonl"))
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(MovementSession.self, from: raw)
        #expect(restored.trials[0].video?.timing == timing)
        #expect(restored.trials[0].samples == recording.samples)

        // A movie-like file with unreadable timing must still follow existing save behavior.
        let badMovie = try temporaryVideo(in: dir)
        let other = Trial(taskType: .handOpenClose, side: .left, source: .camera,
            stopCondition: .thirtySec, startUptime: 1000, samples: [], metrics: .empty)
        let reference = try store.videoStore.save(badMovie, for: other, captureStartPTSSeconds: 999)
        #expect(reference.timing == nil)
        #expect(FileManager.default.fileExists(atPath: try store.videoStore.url(for: other.withVideo(reference)).path))
    }

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

struct MovementPersonalProfileTests {
    private func session(day: Int, rate: Double, context: StimulationContext = .preStim,
                         medication: MedicationTiming? = nil, angles: Bool = false) -> MovementSession {
        let samples = (0..<900).map { TimestampedSample(t: Double($0)/30, value: 1+sin(Double($0) * .pi/8)) }
        let angle = angles ? FingerTappingAngleRecording(samples: (0..<600).map {
            let t = Double($0)/60
            return TimestampedAngleSample(t: t, degrees: 20-20*cos(4 * .pi * t))
        }) : nil
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
            startedAt: Date(timeIntervalSince1970: Double(day)*86400+43200), samples: samples,
            metrics: MovementMetrics(cycleCount: 20, frequencyHz: rate, meanAmplitude: 1,
                amplitudeDecrementSlope: 0, rhythmCV: 0.1, pauseCount: 0, onsetLatencySec: 0, qualityIndex: 0.8),
            medicationTiming: medication, recordedDurationSeconds: 30, fingerTappingAngle: angle)
        return MovementSession(patientId: "PROFILE-TEST", stimulationContext: context, trials: [trial])
    }
    private func profile(_ sessions: [MovementSession]) -> MovementPersonalProfile {
        let summary = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right, metric: .frequency)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return MovementPersonalProfile(recordings: summary.recordings, task: .fingerTap, calendar: calendar)
    }
    @Test func personalTypicalUsesDailyMediansAndMatchingContext() throws {
        let sessions = [session(day: 1, rate: 1), session(day: 1, rate: 1), session(day: 1, rate: 1),
            session(day: 2, rate: 5), session(day: 2, rate: 99, context: .postStim),
            session(day: 2, rate: 88, medication: .init(status: .noneToday,
                confirmedAt: Date(timeIntervalSince1970: 2*86400+43200))), session(day: 3, rate: 3)]
        let result = profile(sessions)
        let rate = try #require(result.entries.first { $0.metric == .rate })
        #expect(rate.latest == 3 && rate.typical == 3 && rate.previousDays == 2)
        #expect(result.entries.first { $0.metric == .size }?.latest == nil)
        #expect(sessions.allSatisfy { $0.trials[0].fingerTappingReferenceSegment == nil })
    }
    @Test func personalTypicalLimitsHistoryAndKeepsAngleSpeedSeparate() throws {
        let history = (0...10).map { session(day: $0, rate: Double($0+1), angles: $0 == 10) }
        let result = profile(history)
        let rate = try #require(result.entries.first { $0.metric == .rate })
        #expect(rate.latest == 11 && rate.typical == 7 && rate.previousDays == 7)
        let speed = try #require(result.entries.first { $0.metric == .angularSpeed })
        #expect((speed.latest ?? 0) > 0 && speed.typical == nil)
        #expect(profile([history.last!]).entries.allSatisfy { $0.typical == nil })
        #expect(profile([]).recording == nil)
    }
}

struct MovementTrendAvailabilityTests {
    @Test func studyComparisonSelectsLatestUsableMatchingHandAndFiltersWithoutMetricGating() {
        func session(_ date: Double, side: BodySide = .right, angles: Bool = true,
                     context: StimulationContext = .preStim) -> MovementSession {
            let signal = angles ? FingerTappingAngleRecording(samples: (0..<600).map {
                let t = Double($0)/60
                return TimestampedAngleSample(t: t, degrees: 20-20*cos(4 * .pi * t))
            }) : nil
            let trial = Trial(taskType: .fingerTap, side: side, source: .camera,
                              stopCondition: .thirtySec, startedAt: Date(timeIntervalSince1970: date),
                              samples: [], metrics: .empty, fingerTappingAngle: signal)
            return MovementSession(patientId: "TEST", stimulationContext: context, trials: [trial])
        }
        let sessions = [session(100), session(200, context: .postStim),
                        session(300, side: .left), session(400, angles: false)]
        let right = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right, metric: .amplitude)
        #expect(right.latestStudyComparisonTrial?.startedAt == Date(timeIntervalSince1970: 200))
        #expect(right.days.isEmpty)
        let left = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .left, metric: .frequency)
        #expect(left.latestStudyComparisonTrial?.side == .left)
        #expect(left.latestStudyComparisonTrial?.startedAt == Date(timeIntervalSince1970: 300))
        let filtered = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right,
            metric: .rhythm, filters: .init(context: .preStim))
        #expect(filtered.latestStudyComparisonTrial?.startedAt == Date(timeIntervalSince1970: 100))
        let excluded = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right,
            metric: .frequency, filters: .init(context: .noStimPlanned))
        #expect(excluded.latestStudyComparisonTrial == nil)
        #expect(sessions.allSatisfy { $0.trials[0].fingerTappingReferenceSegment == nil })
    }

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
        #expect(!summary.canShowTrend) // Same-day historical recordings have no comparable multi-day line.
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

struct MovementDailyTrendTests {
    @Test func explicitTestLinksRestoreHistoricalLinesWithoutRewritingRecords() throws {
        let a = MovementSession(patientId: "unset", stimulationContext: .preStim, trials: [trial(version: nil)])
        let b = MovementSession(patientId: "unset", stimulationContext: .preStim, trials: [trial(day: 1, version: nil)])
        let assigned = MovementSession(patientId: "TEAM-EXAMPLE", stimulationContext: .preStim, trials: [trial(day: 2)])
        let sessions = [a, b, assigned]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let original = try encoder.encode(sessions)
        var links = MovementTrendIdentityLinks()
        links.linkUnassignedTests(sessions, to: "TEAM-EXAMPLE")
        let restored = MovementTrendIdentityLinks(data: try encoder.encode(links))
        #expect(restored == links)
        let linked = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right,
                                         metric: .frequency, calendar: calendar, identityLinks: restored)
        #expect(linked.canShowTrend)
        #expect(linked.days.filter { $0.connects }.count == 3)
        #expect(Set(linked.days.map(\.seriesID)).count == 2) // Unknown old capture method still differs.
        #expect(linked.recordings.filter { $0.originalParticipantID == "unset" }.allSatisfy { $0.participantID == "TEAM-EXAMPLE" })
        #expect(!summary(sessions).canShowTrend)
        #expect(try encoder.encode(sessions) == original)
    }

    @Test func testLinksAreSnapshotsAndNeverRelabelAssignedOrFutureRecordings() {
        let old = MovementSession(patientId: "unset", trials: [trial()])
        let assigned = MovementSession(patientId: "ANOTHER-ID", trials: [trial()])
        let future = MovementSession(patientId: "unset", trials: [trial(day: 1)])
        var links = MovementTrendIdentityLinks()
        links.linkUnassignedTests([old, assigned], to: "TEAM-FIRST")
        #expect(links.displayID(for: old, trial: old.trials[0]) == "TEAM-FIRST")
        #expect(links.displayID(for: assigned, trial: assigned.trials[0]) == "ANOTHER-ID")
        #expect(links.displayID(for: future, trial: future.trials[0]) == "unset")
        var extended = old
        extended.trials.append(future.trials[0])
        #expect(links.displayID(for: extended, trial: future.trials[0]) == "unset")
        links.linkUnassignedTests([old], to: "TEAM-SECOND")
        #expect(links.displayID(for: old, trial: old.trials[0]) == "TEAM-FIRST")
        #expect(MovementTrendIdentityLinks().displayID(for: old, trial: old.trials[0]) == "unset")
        let reassigned = MovementSession(id: old.id, patientId: "ASSIGNED-ID", trials: old.trials)
        #expect(links.displayID(for: reassigned, trial: reassigned.trials[0]) == "ASSIGNED-ID")
    }

    @Test func testLinksRejectParticipantTargetsAndCorruptData() {
        let old = MovementSession(patientId: "unset", trials: [trial()])
        for target in ["", "unset", "PAT-EXAMPLE", "TEAM-", "TEAM-ONE TWO"] {
            var links = MovementTrendIdentityLinks()
            links.linkUnassignedTests([old], to: target)
            #expect(links.sessions.isEmpty)
            #expect(links.displayID(for: old, trial: old.trials[0]) == "unset")
        }
        #expect(MovementTrendIdentityLinks(data: Data("invalid".utf8)).sessions.isEmpty)
        #expect(FullDataExporter.settingsKeys.contains("movementTrendIdentityLinks"))
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private let base = Date(timeIntervalSince1970: 1_790_000_000)

    private func trial(day: Int = 0, offset: Double = 0, rate: Double = 2,
                       duration: Double? = 30, stop: StopCondition = .thirtySec,
                       version: String? = MovementMeasurementVersion.camera,
                       source: SignalSource = .camera, samples: [TimestampedSample]? = nil,
                       medication: MedicationTiming? = nil) -> Trial {
        Trial(taskType: .fingerTap, side: .right, source: source, stopCondition: stop,
              startedAt: base.addingTimeInterval(Double(day) * 86400 + offset),
              samples: samples ?? (0..<900).map { .init(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30)) },
              metrics: MovementMetrics(cycleCount: 12, frequencyHz: rate, meanAmplitude: 0.2,
                                       amplitudeDecrementSlope: -0.01, rhythmCV: 0,
                                       pauseCount: 0, onsetLatencySec: 0, qualityIndex: 0),
              medicationTiming: medication, recordedDurationSeconds: duration, measurementVersion: version)
    }

    private func session(_ trial: Trial, context: StimulationContext = .preStim) -> MovementSession {
        MovementSession(patientId: "TEST", date: base.addingTimeInterval(10000000),
                        stimulationContext: context, trials: [trial])
    }

    private func summary(_ sessions: [MovementSession], metric: TrendMetric = .frequency,
                         filters: MovementTrendFilters = .init()) -> MovementTrendSummary {
        MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right, metric: metric,
                             filters: filters, now: base.addingTimeInterval(10 * 86400), calendar: calendar)
    }

    @Test func dailyMediansRangesAndCountsUseTrialDatesWithoutMutatingSessions() throws {
        let sessions = [session(trial(rate: 2)), session(trial(offset: 100, rate: 4)),
                        session(trial(offset: 200, rate: 20)), session(trial(day: 1, rate: 2)),
                        session(trial(day: 1, offset: 100, rate: 3))]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(sessions)
        let result = summary(sessions)
        #expect(result.days.map(\.median) == [4, 2.5])
        #expect(result.days.map { $0.recordings.count } == [3, 2])
        #expect(result.days.first?.minimum == 2)
        #expect(result.days.first?.maximum == 20)
        #expect(result.days.first?.date == calendar.startOfDay(for: base))
        #expect(result.canShowTrend)
        #expect(Set(result.days.map(\.seriesID)).count == 1)
        #expect(try encoder.encode(sessions) == before)
    }

    @Test func filteringPrecedesAggregationAndMedicationUnknownIsNotNone() {
        let a = trial(rate: 2, medication: .init(status: .takenAt, takenAt: base.addingTimeInterval(-3600)))
        let b = trial(offset: 100, rate: 10, medication: .init(status: .takenAt, takenAt: base.addingTimeInterval(-7200)))
        var filters = MovementTrendFilters()
        filters.medication = .sinceDose
        filters.minimumDoseHours = 1
        filters.maximumDoseHours = 1
        let result = summary([session(a), session(b), session(trial(rate: 8))], filters: filters)
        #expect(result.days.count == 1)
        #expect(result.days.first?.median == 2)
        #expect(result.recordings.count == 1)
        #expect(result.unfilteredCount == 3)
    }

    @Test func fourMonthsOfRetakesProduceOneMedianPerMeasuredDay() {
        let sessions = (0..<120).flatMap { day in
            [session(trial(day: day, rate: 1)), session(trial(day: day, offset: 100, rate: 3))]
        }
        let result = summary(sessions)
        #expect(result.recordings.count == 240)
        #expect(result.days.count == 120)
        #expect(result.days.allSatisfy { $0.median == 2 && $0.recordings.count == 2 })
        #expect(result.canShowTrend)
        #expect(!result.hasStandalonePoints)
    }

    @Test func eachContextHasItsOwnLineAndLegacyContextsNeverConnect() {
        let contexts = StimulationContext.allCases
        let result = summary(contexts.flatMap { context in
            [session(trial(), context: context), session(trial(day: 1), context: context)]
        })
        #expect(result.days.count == 10)
        #expect(result.days.filter(\.connects).count == 6)
        #expect(Set(result.days.filter(\.connects).map(\.seriesID)).count == 3)
        #expect(result.days.filter { [.baseline, .unspecified].contains($0.context) }.allSatisfy { !$0.connects })
    }

    @Test func protocolVersionAndSourceAreNeverMixed() {
        let result = summary([session(trial()), session(trial(day: 1, version: nil)),
                              session(trial(day: 2, duration: 15, stop: .fifteenSec,
                                            samples: (0..<450).map { .init(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30)) })),
                              session(trial(day: 3, source: .watchMotion))])
        #expect(result.days.count == 4)
        #expect(Set(result.days.map(\.seriesID)).count == 4)
        #expect(!result.canShowTrend)
    }

    @Test func differentParticipantIDsAreNeverAggregatedOrJoined() {
        let first = session(trial())
        let other = MovementSession(patientId: "OTHER", stimulationContext: .preStim, trials: [trial(day: 1)])
        let result = summary([first, other])
        #expect(result.days.count == 2)
        #expect(Set(result.days.map(\.seriesID)).count == 2)
        #expect(!result.canShowTrend)
    }

    @Test func legacyRateCanTrendButLegacyAmplitudeIsNotRelabelledAsPalmLengths() {
        let sessions = [session(trial(version: nil)), session(trial(day: 1, version: nil))]
        #expect(summary(sessions).canShowTrend)
        let size = summary(sessions, metric: .amplitude)
        #expect(size.days.isEmpty)
        #expect(size.recordings.count == 2)
        #expect(size.points.count == 2) // Stored values stay accessible in history.
        #expect(summary([session(trial()), session(trial(day: 1))], metric: .amplitude).canShowTrend)
    }

    @Test func compatibleLivePalmVersionsUseOneAnalysisAndLineWithoutHidingSize() {
        let sessions = [session(trial(version: MovementMeasurementVersion.cameraBeforeGapAwareness)),
                        session(trial(day: 1, version: MovementMeasurementVersion.cameraBeforeGapAwareness)),
                        session(trial(day: 2, version: MovementMeasurementVersion.cameraBeforeLocalExcursions)),
                        session(trial(day: 3, version: MovementMeasurementVersion.cameraBeforeLocalExcursions)),
                        session(trial(day: 4)), session(trial(day: 5))]
        for metric in [TrendMetric.frequency, .amplitude, .rhythm] {
            let result = summary(sessions, metric: metric)
            #expect(result.days.count == 6)
            #expect(result.days.allSatisfy { $0.connects })
            #expect(Set(result.days.map(\.seriesID)).count == 1)
            #expect(result.recordings.filter { $0.measurement.recalculated }.count == 4)
            #expect(result.canShowTrend)
        }
    }

    @Test func displayReanalysisPreservesOriginalRecordsAndMetadata() throws {
        let raw = (0..<900).map { TimestampedSample(t: Double($0) / 30, value: 1 + sin(Double($0) * 2 * .pi * 4 / 30)) }
        let original = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                             startedAt: base, samples: raw, metrics: .empty,
                             medicationTiming: .init(status: .unsure), recordedDurationSeconds: 30,
                             video: .init(fileName: "fixture.mov", byteCount: 42),
                             measurementVersion: MovementMeasurementVersion.cameraBeforeLocalExcursions,
                             fingerTappingAngle: .init(samples: [.init(t: 1, degrees: 30)]))
        let sessions = [session(original)]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(sessions)
        let result = summary(sessions)
        let expected = MovementAnalyzer(config: .camera).analyze(raw)
        #expect(result.recordings[0].availability.value == expected.frequencyHz)
        #expect(result.recordings[0].measurement.metrics == expected)
        #expect(result.recordings[0].measurement.version == MovementMeasurementVersion.camera)
        #expect(result.recordings[0].trial == original)
        #expect(result.recordings[0].trial.metrics == .empty)
        #expect(try encoder.encode(sessions) == before)
    }

    @Test func legacyUnknownAndOtherSourcesAreNotReinterpreted() {
        for recording in [trial(version: nil), trial(version: "future-camera-method"),
                          trial(version: MovementMeasurementVersion.cameraBeforeGapAwareness, source: .watchMotion),
                          trial(version: MovementMeasurementVersion.cameraBeforeGapAwareness, source: .synthetic)] {
            let display = MovementTrendMeasurement(trial: recording)
            #expect(!display.recalculated)
            #expect(display.metrics == recording.metrics)
            #expect(display.version == recording.measurementVersion)
        }
    }

    @Test func recalculationDoesNotCreateValuesFromMissingOrFlatSignal() {
        for samples in [[], (0..<900).map { TimestampedSample(t: Double($0) / 30, value: 1) }] {
            let result = summary([session(trial(version: MovementMeasurementVersion.cameraBeforeGapAwareness, samples: samples))])
            #expect(result.points.isEmpty)
            #expect(result.unavailableCount == 1)
        }
    }

    @Test func missingIdentityNeverCreatesACombinedTrend() {
        for id in ["", "unset", "  "] {
            let records = [MovementSession(patientId: id, stimulationContext: .preStim, trials: [trial()]),
                           MovementSession(patientId: id, stimulationContext: .preStim, trials: [trial(day: 1)])]
            let result = summary(records)
            #expect(!result.canShowTrend)
            #expect(result.days.allSatisfy { !$0.connects })
            #expect(result.separationExplanationKeys.contains("Study ID missing: shown separately."))
        }
    }

    @Test func remainingSeparationReasonsAppearEvenWhenOtherLinesExist() {
        let records = [session(trial()), session(trial(day: 1)), session(trial(day: 2, version: nil)),
                       MovementSession(patientId: "OTHER", stimulationContext: .preStim, trials: [trial(day: 3)])]
        let result = summary(records)
        #expect(result.canShowTrend)
        #expect(result.noTrendExplanationKey == nil)
        #expect(result.separationExplanationKeys.contains("Recordings with different study IDs are kept separate."))
        #expect(result.separationExplanationKeys.contains("Earlier and current measurement methods are kept separate."))
        #expect(result.separationReason(for: result.recordings[0]) == nil)
    }

    private func legacySamples(start: Double = 0.02, end: Double = 30.02) -> [TimestampedSample] {
        (0...900).map { index in
            .init(t: start + (end - start) * Double(index) / 900, value: sin(Double(index)))
        }
    }

    @Test(arguments: [TrendMetric.frequency, .rhythm])
    func legacyTimestampEvidenceRestoresHistoricalLinesWithoutChangingData(metric: TrendMetric) throws {
        // Synthetic counterparts of the reviewed export's before/after-stimulation dates.
        let sessions = [session(trial(day: 0, duration: nil, version: nil, samples: legacySamples()), context: .postStim),
                        session(trial(day: 1, duration: nil, version: nil, samples: legacySamples()), context: .postStim),
                        session(trial(day: 6, version: nil), context: .postStim),
                        session(trial(day: 2, duration: nil, version: nil, samples: legacySamples())),
                        session(trial(day: 6, version: nil)),
                        MovementSession(patientId: "ASSIGNED-TEST", stimulationContext: .preStim,
                                        trials: [trial(day: 10)])]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(sessions)
        let result = summary(sessions, metric: metric)
        let lines = Dictionary(grouping: result.days.filter(\.connects), by: \.seriesID).values.filter { $0.count >= 2 }
        #expect(lines.map(\.count).sorted() == [2, 3])
        #expect(result.canShowTrend)
        #expect(result.noTrendExplanationKey == nil)
        #expect(result.recordings.filter { $0.inferredDuration != nil }.count == 3)
        #expect(result.recordings.filter { $0.inferredDuration != nil }.allSatisfy { $0.duration == nil && $0.cautionKey == nil })
        #expect(try encoder.encode(sessions) == before)
        #expect(summary(sessions, metric: .amplitude).days.count == 1)
    }

    @Test func inferredAndMeasuredLegacyDurationsCanShareADailyMedian() {
        let result = summary([session(trial(rate: 2, duration: nil, version: nil, samples: legacySamples())),
                              session(trial(offset: 100, rate: 4, version: nil)),
                              session(trial(day: 1, version: nil))])
        #expect(result.days.count == 2)
        #expect(result.days.first?.median == 3)
        #expect(result.days.first?.recordings.count == 2)
        #expect(result.canShowTrend)
    }

    @Test func incompleteDelayedGappedAndInvalidLegacySignalsCannotSupplyDuration() {
        let full = legacySamples()
        let signals: [[TimestampedSample]] = [[], Array(full.prefix(3)), legacySamples(end: 29.4),
            legacySamples(start: 0.8, end: 30.02), legacySamples(start: 2.1, end: 30.02),
            full.filter { !((10...13).contains($0.t)) },
            Array(full.reversed()), [.init(t: -1, value: 1)] + full,
            full + [.init(t: .nan, value: 1)], full + [.init(t: 30.03, value: .infinity)],
            legacySamples(end: 30.51)]
        for samples in signals {
            let result = summary([session(trial(duration: nil, version: nil, samples: samples))])
            #expect(result.recordings[0].inferredDuration == nil)
            #expect(result.recordings[0].cautionKey != nil)
            #expect(!result.canShowTrend)
        }
    }

    @Test(arguments: [0.0, -1.0, 5.0, Double.nan, Double.infinity])
    func timestampInferenceNeverOverridesAnExplicitDuration(duration: Double) {
        let result = summary([session(trial(duration: duration, version: nil, samples: legacySamples()))])
        #expect(result.recordings[0].inferredDuration == nil)
        #expect(result.recordings[0].cautionKey != nil)
    }

    @Test func inferenceIsLimitedToLegacyCameraDurationTests() {
        let trials = [trial(duration: nil, samples: legacySamples()),
                      trial(duration: nil, version: "future-version", samples: legacySamples()),
                      trial(duration: nil, version: nil, source: .watchMotion, samples: legacySamples()),
                      trial(duration: nil, version: nil, source: .synthetic, samples: legacySamples()),
                      trial(duration: nil, stop: .tenReps, version: nil, samples: legacySamples())]
        for trial in trials {
            let result = summary([session(trial)])
            #expect(result.recordings[0].inferredDuration == nil)
            #expect(result.recordings[0].cautionKey != nil)
        }
    }

    @Test func inferredDurationUsesTheRequestedProtocolAndPreservesGroupingBoundaries() {
        let a = trial(duration: nil, version: nil, samples: legacySamples())
        let b = trial(day: 1, duration: nil, stop: .fifteenSec, version: nil,
                      samples: legacySamples(end: 15.02))
        let result = summary([session(a), session(b), session(trial(day: 2)),
                              MovementSession(patientId: "OTHER", stimulationContext: .preStim,
                                              trials: [trial(day: 3, duration: nil, version: nil, samples: legacySamples())])])
        #expect(result.recordings.filter { $0.inferredDuration != nil }.count == 3)
        #expect(result.days.filter(\.connects).count == 4)
        #expect(Set(result.days.map(\.seriesID)).count == 4)
        #expect(!result.canShowTrend)
        let unknown = summary([session(a, context: .unspecified), session(b, context: .baseline)])
        #expect(unknown.days.allSatisfy { !$0.connects })
    }

    @Test func noLineMessagesExplainTheActualComparisonBoundary() {
        #expect(summary([]).noTrendExplanationKey == nil)
        #expect(summary([session(trial())]).noTrendExplanationKey == "A line needs matching recordings on at least two different days.")
        #expect(summary([session(trial(duration: nil))]).noTrendExplanationKey == "Incomplete capture or unknown duration keeps these points separate.")
        #expect(summary([session(trial(), context: .unspecified)]).noTrendExplanationKey == "Recordings with unspecified or historical stimulation timing stay separate.")
        #expect(summary([session(trial()), session(trial(day: 1, duration: nil))]).noTrendExplanationKey == "Only one day has comparable complete recordings. Other points remain separate.")
        #expect(summary([session(trial()), session(trial(day: 1, version: nil))]).noTrendExplanationKey == "Earlier and current measurement methods are kept separate.")
        #expect(summary([session(trial()), MovementSession(patientId: "OTHER", stimulationContext: .preStim, trials: [trial(day: 1)])]).noTrendExplanationKey == "Recordings with different study IDs are kept separate.")
        #expect(summary([session(trial()), session(trial(day: 1), context: .postStim)]).noTrendExplanationKey == "Each stimulation timing needs matching recordings on at least two days.")
        #expect(summary([session(trial()), session(trial(day: 1, source: .watchMotion))]).noTrendExplanationKey == "Different test protocols or recording sources are kept separate.")
        #expect(summary([session(trial()), session(trial(day: 1, samples: [])), session(trial(day: 2))]).noTrendExplanationKey == "An intervening day with incomplete capture separates these trend segments.")
    }

    @Test func belowMinimumAndUnknownTakesStaySeparateWhileUsableGapsContribute() {
        let partialSamples = (0..<150).map { TimestampedSample(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30)) }
        let gapSamples = (0..<900).filter { !(150...300).contains($0) }.map {
            TimestampedSample(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30))
        }
        let result = summary([session(trial(rate: 2)), session(trial(rate: 9, duration: 5, samples: partialSamples)),
                              session(trial(rate: 9, duration: nil)), session(trial(rate: 9, samples: gapSamples))])
        #expect(result.days.count == 3)
        #expect(result.days.filter(\.connects).map(\.median) == [5.5])
        #expect(result.recordings.filter { $0.cautionKey != nil }.count == 2)
    }

    @Test(arguments: [TrendMetric.frequency, .amplitude, .rhythm])
    func tenSecondTakesContributeToNormalMediansAndLines(metric: TrendMetric) throws {
        let tenSeconds = (0..<300).map {
            TimestampedSample(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30))
        }
        let sessions = [session(trial(rate: 2)),
                        session(trial(offset: 100, rate: 4, duration: 10, samples: tenSeconds)),
                        session(trial(day: 1, duration: 10, samples: tenSeconds))]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(sessions)
        let result = summary(sessions, metric: metric)
        #expect(result.days.count == 2)
        #expect(result.days.first?.recordings.count == 2)
        #expect(result.days.allSatisfy { $0.connects })
        #expect(result.recordings.allSatisfy { $0.cautionKey == nil })
        #expect(result.canShowTrend)
        if metric == .frequency { #expect(result.days.first?.median == 3) }
        #expect(try encoder.encode(sessions) == before)
    }

    @Test func trackingTimeCannotBeInventedFromElapsedDurationOrAcrossGaps() {
        let indices = (0..<900).filter { $0 < 240 || ($0 >= 330 && $0 < 570) || $0 >= 660 }
        let fragmented: [TimestampedSample] = indices.map {
            TimestampedSample(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30))
        }
        let tiny = (0..<150).map {
            TimestampedSample(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30))
        }
        for samples in [fragmented, tiny, []] {
            let result = summary([session(trial(samples: samples))])
            #expect(result.recordings[0].cautionKey != nil)
            #expect(result.days.allSatisfy { !$0.connects })
        }
    }

    @Test func gapAwareTakesCanUseTenGoodSecondsWithoutReinterpretingLegacyMetrics() {
        let samples = (0..<900).filter { $0 < 180 || $0 >= 450 }.map {
            TimestampedSample(t: Double($0) / 30, value: sin(Double($0) * 2 * .pi * 4 / 30))
        }
        let result = summary([session(trial(samples: samples)), session(trial(day: 1, samples: samples))])
        #expect(result.recordings.allSatisfy { $0.hasSignalGaps })
        #expect(result.recordings.allSatisfy { $0.cautionKey == nil })
        #expect(result.canShowTrend)
        let legacy = summary([session(trial(version: nil, samples: samples))])
        #expect(legacy.recordings[0].cautionKey != nil)
    }

    @Test func unavailableInterveningRecordingBreaksLineWithoutInventingZero() {
        let result = summary([session(trial()), session(trial(day: 1, samples: [])), session(trial(day: 2))])
        #expect(result.days.count == 2)
        #expect(result.unavailableCount == 1)
        #expect(Set(result.days.map(\.seriesID)).count == 2)
        #expect(!result.canShowTrend)
    }

    @Test func validZeroRhythmAndNegativeDecrementSurviveAggregation() {
        let sessions = [session(trial()), session(trial(day: 1))]
        #expect(summary(sessions, metric: .rhythm).days.map(\.median) == [0, 0])
        #expect(summary(sessions, metric: .decrement).days.map(\.median) == [-0.01, -0.01])
        #expect(TrendMetric.pauses.plotFormatted(2.5, task: .fingerTap).contains("5"))
    }

    @Test func localCalendarDaysRespectMidnightAndDaylightSaving() throws {
        var berlin = calendar
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let formatter = ISO8601DateFormatter()
        let dates = ["2026-10-24T22:30:00Z", "2026-10-25T22:30:00Z", "2026-10-25T23:30:00Z"]
            .map { formatter.date(from: $0)! }
        let sessions = dates.map { date -> MovementSession in
            let recording = trial(offset: date.timeIntervalSince(base))
            return session(recording)
        }
        let result = MovementTrendSummary(sessions: sessions, task: .fingerTap, side: .right,
                                          metric: .frequency, calendar: berlin)
        #expect(result.days.count == 2)
        #expect(result.days.map { $0.recordings.count } == [2, 1])
        #expect(result.days[1].date.timeIntervalSince(result.days[0].date) == 25 * 3600)
    }

    @Test func measurementVersionSurvivesCopiesExportsAndMissingLegacyField() throws {
        let original = trial()
        let copied = original.withVideo(.init(fileName: "example.mov", byteCount: 1))
            .withMedicationTiming(.init(status: .unsure))
        #expect(copied.measurementVersion == MovementMeasurementVersion.camera)
        let data = try JSONEncoder().encode(copied)
        #expect(try JSONDecoder().decode(Trial.self, from: data) == copied)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json.removeValue(forKey: "measurementVersion")
        let legacy = try JSONDecoder().decode(Trial.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.measurementVersion == nil)
        #expect(legacy.samples == original.samples)
        #expect(legacy.metrics == original.metrics)
    }
}

struct CameraMovementNormalizationTests {
    private let wrist = CGPoint(x: 0.4, y: 0.2)
    private let mcp = CGPoint(x: 0.4, y: 0.4)
    private let tips = [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.5, y: 0.6),
                        CGPoint(x: 0.4, y: 0.7), CGPoint(x: 0.6, y: 0.6), CGPoint(x: 0.7, y: 0.5)]

    @Test(arguments: [MovementTaskType.fingerTap, .handOpenClose])
    func imageScaleTranslationAspectRotationAndMirroringDoNotChangeRatio(task: MovementTaskType) throws {
        let tips = task == .fingerTap ? Array(tips.prefix(2)) : tips
        let reference = try #require(CameraMovementSignal.value(task: task, wrist: wrist, middleMCP: mcp,
                                                                fingertips: tips, imageAspectRatio: 1))
        for aspect in [0.5625, 1.0, 1.777777] {
            for scale in [0.5, 1.0] {
                for mirrored in [false, true] {
                    for rotated in [false, true] {
                        func transform(_ p: CGPoint) -> CGPoint {
                            let x = (mirrored ? -p.x : p.x) * scale
                            let y = p.y * scale
                            return CGPoint(x: ((rotated ? -y : x) + 0.8) / aspect,
                                           y: (rotated ? x : y) + 0.8)
                        }
                        let value = try #require(CameraMovementSignal.value(task: task, wrist: transform(wrist),
                            middleMCP: transform(mcp), fingertips: tips.map(transform), imageAspectRatio: aspect))
                        #expect(abs(value - reference) < 1e-10)
                    }
                }
            }
        }
    }

    @Test func invalidGeometryIsMissingNotZeroAndClosedTapIsRealZero() {
        #expect(CameraMovementSignal.value(task: .fingerTap, wrist: wrist, middleMCP: wrist,
                                           fingertips: Array(tips.prefix(2)), imageAspectRatio: 1) == nil)
        #expect(CameraMovementSignal.value(task: .fingerTap, wrist: wrist, middleMCP: mcp,
                                           fingertips: [tips[0], tips[0]], imageAspectRatio: 1) == 0)
        #expect(CameraMovementSignal.value(task: .handOpenClose, wrist: wrist, middleMCP: mcp,
                                           fingertips: [tips[0]], imageAspectRatio: 1) == nil)
        #expect(CameraMovementSignal.value(task: .fingerTap, wrist: wrist, middleMCP: mcp,
                                           fingertips: Array(tips.prefix(2)), imageAspectRatio: .nan) == nil)
    }
}

struct FingerTappingAngleTests {
    @Test func frameMeasurementsRemainIndependentAndMatchExistingDistance() throws {
        let wrist = CGPoint(x: 0.5, y: 0.2)
        let mcp = CGPoint(x: 0.5, y: 0.4)
        let thumb = CGPoint(x: 0.3, y: 0.6)
        let index = CGPoint(x: 0.6, y: 0.7)
        let frame = CameraMovementFrame.fingerTap(wrist: wrist, middleMCP: mcp, thumbTip: thumb,
                                                 indexTip: index, imageAspectRatio: 9.0 / 16)
        #expect(frame.value == CameraMovementSignal.value(task: .fingerTap, wrist: wrist, middleMCP: mcp,
            fingertips: [thumb, index], imageAspectRatio: 9.0 / 16))
        #expect(frame.fingerTappingAngleDegrees != nil)
        let noPalm = CameraMovementFrame.fingerTap(wrist: wrist, middleMCP: nil, thumbTip: thumb,
                                                  indexTip: index, imageAspectRatio: 9.0 / 16)
        #expect(noPalm.value == nil && noPalm.fingerTappingAngleDegrees == frame.fingerTappingAngleDegrees)
        let degenerateAngle = CameraMovementFrame.fingerTap(wrist: wrist, middleMCP: mcp, thumbTip: wrist,
                                                           indexTip: index, imageAspectRatio: 9.0 / 16)
        #expect(degenerateAngle.value != nil && degenerateAngle.fingerTappingAngleDegrees == nil)
        let missingTip = CameraMovementFrame.fingerTap(wrist: wrist, middleMCP: mcp, thumbTip: nil,
                                                      indexTip: index, imageAspectRatio: 9.0 / 16)
        #expect(missingTip.value == nil && missingTip.fingerTappingAngleDegrees == nil)
    }

    @Test(arguments: [0.0, 30, 60, 90, 120, 179.999999, 180])
    func knownAnglesAreInDegrees(_ degrees: Double) throws {
        let radians = degrees * .pi / 180
        let angle = try #require(FingerTappingAngle.degrees(
            wrist: .zero, thumbTip: CGPoint(x: 1, y: 0),
            indexTip: CGPoint(x: cos(radians), y: sin(radians)), imageAspectRatio: 1))
        #expect(abs(angle - degrees) < 1e-10)
        #expect((0...180).contains(angle))
    }

    @Test func imageTransformationsAndTipOrderPreserveAngle() throws {
        let wrist = CGPoint(x: 0.1, y: -0.2)
        let thumb = CGPoint(x: 0.4, y: 0.2)
        let index = CGPoint(x: -0.2, y: 0.6)
        let expected = try #require(FingerTappingAngle.degrees(
            wrist: wrist, thumbTip: thumb, indexTip: index, imageAspectRatio: 1))
        for aspect in [9.0 / 16, 1, 16.0 / 9] {
            for scale in [0.001, 0.25, 1, 10] {
                for rotation in [0.0, .pi / 7, .pi / 2, .pi, -.pi / 3] {
                    for mirrored in [false, true] {
                        func transform(_ point: CGPoint) -> CGPoint {
                            let x = (mirrored ? -point.x : point.x) * scale
                            let y = point.y * scale
                            return CGPoint(x: (x * cos(rotation) - y * sin(rotation) + 0.5) / aspect,
                                           y: x * sin(rotation) + y * cos(rotation) + 0.4)
                        }
                        for swapped in [false, true] {
                            let result = try #require(FingerTappingAngle.degrees(
                                wrist: transform(wrist), thumbTip: transform(swapped ? index : thumb),
                                indexTip: transform(swapped ? thumb : index), imageAspectRatio: aspect))
                            #expect(abs(result - expected) < 1e-9)
                        }
                    }
                }
            }
        }
    }

    @Test func aspectCorrectionRestoresPixelGeometry() throws {
        // These normalized vectors are perpendicular only after correcting x by width/height.
        let result = try #require(FingerTappingAngle.degrees(
            wrist: CGPoint(x: 0.5, y: 0.5), thumbTip: CGPoint(x: 0.75, y: 0.75),
            indexTip: CGPoint(x: 0.25, y: 0.75), imageAspectRatio: 1))
        #expect(abs(result - 90) < 1e-10)
        let portrait = try #require(FingerTappingAngle.degrees(
            wrist: CGPoint(x: 0.5, y: 0.5), thumbTip: CGPoint(x: 0.75, y: 0.75),
            indexTip: CGPoint(x: 0.25, y: 0.75), imageAspectRatio: 0.5))
        #expect(abs(portrait - 53.13010235415598) < 1e-10)
    }

    @Test func touchingTipsAreValidZeroButWristCoincidenceIsMissing() {
        let wrist = CGPoint(x: 0.2, y: 0.3)
        let tip = CGPoint(x: 0.4, y: 0.8)
        #expect(FingerTappingAngle.degrees(wrist: wrist, thumbTip: tip, indexTip: tip,
                                          imageAspectRatio: 9.0 / 16) == 0)
        #expect(FingerTappingAngle.degrees(wrist: wrist, thumbTip: wrist, indexTip: tip,
                                          imageAspectRatio: 1) == nil)
        #expect(FingerTappingAngle.degrees(wrist: wrist, thumbTip: tip, indexTip: wrist,
                                          imageAspectRatio: 1) == nil)
        #expect(FingerTappingAngle.degrees(wrist: wrist, thumbTip: wrist, indexTip: wrist,
                                          imageAspectRatio: 1) == nil)
    }

    @Test(arguments: [0.0, -1, Double.nan, .infinity, -.infinity])
    func invalidAspectIsMissing(_ aspect: Double) {
        #expect(FingerTappingAngle.degrees(wrist: .zero, thumbTip: CGPoint(x: 1, y: 0),
                                          indexTip: CGPoint(x: 0, y: 1), imageAspectRatio: aspect) == nil)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity])
    func nonFiniteCoordinateIsMissing(_ invalid: Double) {
        let points = [CGPoint.zero, CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)]
        for joint in points.indices {
            for isX in [false, true] {
                var corrupted = points
                corrupted[joint] = isX ? CGPoint(x: invalid, y: points[joint].y)
                    : CGPoint(x: points[joint].x, y: invalid)
                #expect(FingerTappingAngle.degrees(wrist: corrupted[0], thumbTip: corrupted[1],
                    indexTip: corrupted[2], imageAspectRatio: 1) == nil)
            }
        }
    }

    @Test func vectorLengthsDoNotCreateAnAmplitudeThresholdOrNumericOverflow() throws {
        for length in [1e-200, 1e-20, 1.0, 1e200] {
            let result = try #require(FingerTappingAngle.degrees(
                wrist: .zero, thumbTip: CGPoint(x: length, y: 0),
                indexTip: CGPoint(x: 0, y: length), imageAspectRatio: 1))
            #expect(abs(result - 90) < 1e-10)
        }
        let unequal = try #require(FingerTappingAngle.degrees(
            wrist: .zero, thumbTip: CGPoint(x: 1e200, y: 1e200),
            indexTip: CGPoint(x: -1e-200, y: 1e-200), imageAspectRatio: 1))
        #expect(abs(unequal - 90) < 1e-10)
        let nearlyClosed = try #require(FingerTappingAngle.degrees(
            wrist: .zero, thumbTip: CGPoint(x: 1, y: 0),
            indexTip: CGPoint(x: 1, y: 1e-12), imageAspectRatio: 1))
        #expect(nearlyClosed > 0 && nearlyClosed < 1e-9)
    }

    @Test func unrepresentableCoordinateArithmeticIsMissing() {
        let huge = Double.greatestFiniteMagnitude
        #expect(FingerTappingAngle.degrees(wrist: CGPoint(x: -huge, y: 0),
            thumbTip: CGPoint(x: huge, y: 0), indexTip: CGPoint(x: 0, y: 1), imageAspectRatio: 1) == nil)
        #expect(FingerTappingAngle.degrees(wrist: .zero,
            thumbTip: CGPoint(x: huge, y: 0), indexTip: CGPoint(x: 0, y: 1), imageAspectRatio: 2) == nil)
    }
}

struct MovementTrendFilterTests {
    @Test func contextMenuOmitsBaselineWithoutDroppingHistoricalData() {
        #expect(!MovementTrendFilters.contextChoices.contains(.baseline))
        #expect(StimulationContext.patientChoices.allSatisfy(MovementTrendFilters.contextChoices.contains))
        #expect(MovementTrendFilters.contextChoices.contains(.unspecified))
        #expect(includes(trial(), filters: .init(), context: .baseline))
        #expect(StimulationContext(rawValue: "baseline") == .baseline)
    }

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
        #expect(TrendMetric.plotCases == [.frequency, .amplitude, .rhythm])
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

    @Test(arguments: [TrendPeriod.week, .month, .quarter])
    func dateWindowIncludesFirstDayMidnightButNotFutureRecordings(period: TrendPeriod) {
        var filters = MovementTrendFilters()
        filters.period = period
        let days = period == .week ? 7 : (period == .month ? 30 : 90)
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
