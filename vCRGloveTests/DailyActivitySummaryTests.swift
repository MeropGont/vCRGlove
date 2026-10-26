import Foundation
import Testing
import UserNotifications
@testable import vCRGlove

struct EncouragingReminderCopyTests {
    @Test(arguments: ["en", "de"])
    func reminderMessagesAreBundledInBothAppLanguages(_ language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let expected = language == "de" ? [
            "reminder.vcr.body": "Wenn Sie bereit sind, können Sie Ihre geplante vCR-Sitzung starten.",
            "reminder.journal.body": "Ein Moment für Sie. Wie geht es Ihnen heute?",
            "reminder.movement.body": "Wenn es für Sie passt, nehmen Sie sich einen Moment für Ihre Bewegungsaufgaben."
        ] : [
            "reminder.vcr.body": "When you're ready, you can start your planned vCR session.",
            "reminder.journal.body": "A moment for you. How are you feeling today?",
            "reminder.movement.body": "When it suits you, take a moment for your movement tasks."
        ]
        for (key, text) in expected {
            #expect(bundle.localizedString(forKey: key, value: key, table: nil) == text)
        }
    }

    @Test(arguments: ["en", "de"])
    func allThirtySixMessagesAreTranslatedAndBrief(_ language: String) throws {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        for kind in ReminderScheduler.Kind.allCases {
            var messages = Set<String>()
            for variant in 0..<ReminderScheduler.messageCount {
                let key = kind.messagePrefix + (variant == 0 ? ".body" : ".\(variant + 1)")
                let text = bundle.localizedString(forKey: key, value: key, table: nil)
                #expect(text != key && !text.isEmpty)
                #expect(text.count <= 140)
                messages.insert(text)
            }
            #expect(messages.count == 12)
        }
    }

    @Test func rotationIsStableWithinADayAndVisitsEveryMessage() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20)))
        for kind in ReminderScheduler.Kind.allCases {
            let keys = (0..<12).map { offset in
                ReminderScheduler.messageKey(for: kind, on: calendar.date(byAdding: .day, value: offset, to: start)!, calendar: calendar)
            }
            #expect(Set(keys).count == 12) // Includes the autumn DST change.
            #expect(keys[0] != keys[7])
            let later = try #require(calendar.date(byAdding: .hour, value: 18, to: start))
            #expect(keys[0] == ReminderScheduler.messageKey(for: kind, on: later, calendar: calendar))
        }
    }

    @Test @MainActor func repeatingRequestsStayBoundedAndRespectQuietHoursAndSound() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12)))
        var ids = Set<String>()
        for kind in ReminderScheduler.Kind.allCases {
            let requests = ReminderScheduler.weeklyRequests(kind: kind, weekdays: Set(0...8),
                hour: 22, minute: 30, quietHoursEnabled: true, quietStartHour: 21,
                quietEndHour: 8, soundEnabled: false, now: now, calendar: calendar)
            #expect(requests.count == 7)
            for request in requests {
                #expect(ids.insert(request.identifier).inserted)
                let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
                #expect(trigger.repeats)
                #expect(trigger.dateComponents.hour == 8 && trigger.dateComponents.minute == 0)
                #expect(request.content.sound == nil)
                #expect(request.content.threadIdentifier == "routine-reminders")
                let next = try #require(calendar.nextDate(after: now, matching: trigger.dateComponents, matchingPolicy: .nextTime))
                #expect(request.content.body == L10n(ReminderScheduler.messageKey(for: kind, on: next, calendar: calendar)))
            }
        }
        #expect(ids.count == 21)
        #expect(Set(ReminderScheduler.identifiers) == ids.union(["vcr.daily"]))
        #expect(ReminderScheduler.weeklyRequests(kind: .journal, weekdays: [], hour: 18, minute: 0,
            quietHoursEnabled: true, quietStartHour: 21, quietEndHour: 8, soundEnabled: true).isEmpty)

        for quietEnabled in [true, false] {
            let request = try #require(ReminderScheduler.weeklyRequests(kind: .task, weekdays: [2],
                hour: 14, minute: 15, quietHoursEnabled: quietEnabled, quietStartHour: 13,
                quietEndHour: 16, soundEnabled: true, now: now, calendar: calendar).first)
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            #expect(trigger.dateComponents.hour == (quietEnabled ? 16 : 14))
            #expect(trigger.dateComponents.minute == (quietEnabled ? 0 : 15))
            #expect(request.content.sound != nil)
        }
    }
}

struct RoutineMilestoneTests {
    private func history(run: Int = 0, total: Int = 0) -> ActivityHistory {
        ActivityHistory(days: [], currentStreak: run, longestStreak: run,
            totalActiveDays: total, activeDaysThisWeek: 0, todayIsActive: false)
    }

    @Test func thresholdsAreIndependentOfMovementPerformance() {
        #expect(RoutineMilestone.earned(in: history(run: 2, total: 29)).isEmpty)
        #expect(RoutineMilestone.earned(in: history(run: 3)) == [.threeDayRun])
        #expect(RoutineMilestone.earned(in: history(run: 7)) == [.threeDayRun, .sevenDayRun])
        #expect(RoutineMilestone.earned(in: history(total: 30)) == [.thirtyActiveDays])
    }

    @Test @MainActor func onlyHighestUnseenMilestoneIsClaimedAndRelaunchDoesNotReplayIt() throws {
        let name = "milestones-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let ledger = RoutineMilestoneLedger(defaults: defaults)
        let all = history(run: 7, total: 30)
        #expect(ledger.claim(history: all, participantID: "TEAM-A", enabled: true, allowed: true) == .thirtyActiveDays)
        let reopened = RoutineMilestoneLedger(defaults: try #require(UserDefaults(suiteName: name)))
        #expect(reopened.claim(history: all, participantID: "TEAM-A", enabled: true, allowed: true) == nil)
        #expect(reopened.claim(history: history(run: 3), participantID: "TEAM-A", enabled: true, allowed: true) == nil)
        #expect(reopened.claim(history: all, participantID: "TEAM-B", enabled: true, allowed: true) == .thirtyActiveDays)
    }

    @Test @MainActor func disabledAndBlockedAcknowledgementsWaitWithoutConsumingTheMilestone() throws {
        let name = "milestones-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let ledger = RoutineMilestoneLedger(defaults: defaults)
        let first = history(run: 3)
        #expect(ledger.claim(history: first, participantID: "TEAM-A", enabled: false, allowed: true) == nil)
        #expect(ledger.claim(history: first, participantID: "TEAM-A", enabled: true, allowed: false) == nil)
        #expect(defaults.object(forKey: RoutineMilestoneLedger.seenKey) == nil)
        #expect(ledger.claim(history: first, participantID: "TEAM-A", enabled: true, allowed: true) == .threeDayRun)
        #expect(ledger.claim(history: history(run: 7), participantID: "TEAM-A", enabled: true, allowed: true) == .sevenDayRun)
        #expect(ledger.claim(history: history(run: 7, total: 30), participantID: "TEAM-A", enabled: true, allowed: true) == .thirtyActiveDays)
    }

    @Test @MainActor func corruptLedgerFailsQuietlyInsteadOfRepeatingMessages() throws {
        let name = "milestones-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let bad = Data("invalid".utf8)
        defaults.set(bad, forKey: RoutineMilestoneLedger.seenKey)
        #expect(RoutineMilestoneLedger(defaults: defaults).claim(history: history(run: 7),
            participantID: "TEAM-A", enabled: true, allowed: true) == nil)
        #expect(defaults.data(forKey: RoutineMilestoneLedger.seenKey) == bad)
    }

    @Test @MainActor func recorderGateKeepsOverlappingAndRestartedRunsBlocked() {
        let activity = RoutineRecordingActivity()
        let first = UUID(), second = UUID()
        activity.begin(first); activity.begin(first); activity.begin(second)
        activity.end(first)
        #expect(activity.activeIDs == [first, second] && activity.isActive)
        activity.end(first)
        #expect(activity.activeIDs == [second])
        activity.remove(second)
        #expect(!activity.isActive)
    }
}

struct DailyActivitySummaryTests {
    @Test func mixedOwnersDoNotAttributeDeviceOnlyActivityToCurrentID() {
        let now = Date()
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
            startedAt: now, samples: [], metrics: .empty, recordedDurationSeconds: 10)
        let sessions = [MovementSession(patientId: "TEAM-A", trials: [trial]),
                        MovementSession(patientId: "TEAM-B", trials: [trial])]
        let scope = JournalActivityScope(journal: [.init(date: now, type: .dailyCheckIn)], sessions: sessions,
            evidence: .init(starts: [now]), participantID: "TEAM-A", links: .init(), now: now)
        #expect(scope.limitsUnassignedHistory && scope.journal.isEmpty && scope.starts.isEmpty)
        #expect(scope.sessions.count == 1 && scope.sessions[0].patientId == "TEAM-A")
    }

    @Test func confirmedReassignmentBoundsDeviceActivityAndApprovedLinksRemainDisplayOnly() {
        let now = Date(), boundary = Date().addingTimeInterval(-3600)
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
            startedAt: now, samples: [], metrics: .empty, recordedDurationSeconds: 10)
        let original = MovementSession(patientId: "unset", trials: [trial])
        var links = MovementTrendIdentityLinks()
        links.linkUnassignedTests([original], to: "TEAM-CURRENT")
        let scope = JournalActivityScope(journal: [.init(date: boundary.addingTimeInterval(-1), type: .dailyCheckIn),
                                                   .init(date: now, type: .dailyCheckIn)], sessions: [original],
            evidence: .init(starts: [boundary.addingTimeInterval(-1), now],
                reassignments: [.init(date: boundary, participantID: "TEAM-CURRENT")]),
            participantID: "TEAM-CURRENT", links: links, now: now)
        #expect(scope.journal.count == 1 && scope.starts == [now])
        #expect(scope.sessions.first?.patientId == "TEAM-CURRENT" && original.patientId == "unset")
    }

    @Test @MainActor func controllerDoesNotTurnReadFailureIntoAZeroStreak() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("events.jsonl"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = JournalActivityController(events: EventStore(directory: directory))
        await controller.refresh(journal: [], sessions: [], participantID: "TEAM-A", links: .init(),
            now: Date(), calendar: .current)
        #expect(controller.failed && controller.history == nil)
    }

    @Test @MainActor func movementLoadStateDistinguishesEmptyFromUnreadableHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = TaskSessionStore(storageURL: directory.appendingPathComponent("missing.jsonl"))
        let unreadable = directory.appendingPathComponent("bad.jsonl")
        try Data([0xFF]).write(to: unreadable)
        let failed = TaskSessionStore(storageURL: unreadable)
        let malformedURL = directory.appendingPathComponent("malformed.jsonl")
        try Data("broken\n".utf8).write(to: malformedURL)
        let malformed = TaskSessionStore(storageURL: malformedURL)
        for _ in 0..<200 where !missing.hasLoaded || !failed.hasLoaded || !malformed.hasLoaded {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(missing.hasLoaded && !missing.activityHistoryLoadFailed && missing.sessions.isEmpty)
        #expect(failed.hasLoaded && failed.activityHistoryLoadFailed)
        #expect(malformed.hasLoaded && malformed.activityHistoryLoadFailed)
    }

    private func calendar(_ zone: String = "Europe/Berlin", firstWeekday: Int = 2) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: zone)!
        value.firstWeekday = firstWeekday
        value.minimumDaysInFirstWeek = 4
        return value
    }

    private func date(_ day: String, hour: Int = 12, in calendar: Calendar) -> Date {
        let values = day.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: values[0], month: values[1], day: values[2], hour: hour))!
    }

    private func history(_ entries: [JournalEntry] = [], sessions: [MovementSession] = [],
                         starts: [Date] = [], now: Date, calendar: Calendar) -> ActivityHistory {
        DailyActivityCalculator.calculate(journal: entries, sessions: sessions,
            movementParticipantIDs: ["TEAM"], stimulationStarts: starts, now: now, calendar: calendar)
    }

    @Test func emptyHistoryAndOrdinaryEntriesDoNotEarnActiveDays() {
        let c = calendar(), now = date("2026-10-23", in: calendar())
        let empty = history(now: now, calendar: c)
        #expect(empty.currentStreak == 0 && empty.longestStreak == 0 && empty.totalActiveDays == 0)
        let entries = [JournalEntryType.note, .medication, .symptom, .stimulation].map {
            JournalEntry(date: now, type: $0)
        }
        let result = history(entries, now: now, calendar: c)
        let day = result.summary(on: now, calendar: c)
        #expect(day.journalEntryCount == 4 && day.hasStimulationLog)
        #expect(!day.hasRecordedStimulationStart && !day.isActive)
    }

    @Test func todayRemainsOpenUntilMidnightAndPastAchievementsSurviveGaps() {
        let c = calendar(), now = date("2026-10-23", hour: 23, in: calendar())
        let entries = [19, 20, 21, 22].map { JournalEntry(date: date("2026-10-\($0)", in: c), type: .dailyCheckIn) }
        let todayOpen = history(entries, now: now, calendar: c)
        #expect(todayOpen.currentStreak == 4 && !todayOpen.todayIsActive)
        #expect(todayOpen.activeDaysThisWeek == 4)
        let missed = history(entries, now: date("2026-10-24", hour: 0, in: c), calendar: c)
        #expect(missed.currentStreak == 0 && missed.longestStreak == 4 && missed.totalActiveDays == 4)
        let resumed = history(entries + [.init(date: date("2026-10-24", in: c), type: .dailyCheckIn)],
            now: date("2026-10-24", hour: 13, in: c), calendar: c)
        #expect(resumed.currentStreak == 1 && resumed.longestStreak == 4 && resumed.totalActiveDays == 5)
    }

    @Test func differentActivitiesEarnOnlyOneDayAndDuplicatesDoNotInflateCounts() {
        let c = calendar(), now = date("2026-10-23", in: calendar())
        let entry = JournalEntry(date: now, type: .dailyCheckIn)
        let trial = Trial(taskType: .fingerTap, side: .left, source: .camera, stopCondition: .thirtySec,
            startedAt: now, samples: [], metrics: .empty, recordedDurationSeconds: 10)
        let session = MovementSession(patientId: "TEAM", date: now, trials: [trial, trial])
        let result = history([entry, entry], sessions: [session, session], starts: [now, now], now: now, calendar: c)
        let day = result.summary(on: now, calendar: c)
        #expect(result.totalActiveDays == 1 && result.currentStreak == 1)
        #expect(day.journalEntryCount == 1 && day.movementAttemptCount == 1 && day.recordedTaskHands.count == 1)
        #expect(day.hasRecordedStimulationStart)
    }

    @Test func movementUsesEachTakeDateAndExplicitParticipantScope() {
        let c = calendar(), now = date("2026-10-23", in: calendar())
        let yesterday = date("2026-10-22", in: c)
        let trial = Trial(taskType: .handOpenClose, side: .right, source: .camera, stopCondition: .thirtySec,
            startedAt: yesterday, samples: [], metrics: .empty, recordedDurationSeconds: 10)
        let own = MovementSession(patientId: "TEAM", date: now, trials: [trial])
        let other = MovementSession(patientId: "OTHER", date: now, trials: [
            Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                  startedAt: now, samples: [], metrics: .empty, recordedDurationSeconds: 30)])
        let result = history(sessions: [other, own], now: now, calendar: c)
        #expect(!result.todayIsActive && result.currentStreak == 1 && result.totalActiveDays == 1)
        #expect(result.summary(on: yesterday, calendar: c).movementAttemptCount == 1)
    }

    @Test func effortsCountWithoutQualityGateButEmptyStopsAndSyntheticTrialsDoNot() {
        let c = calendar(), now = date("2026-10-23", in: calendar())
        func trial(_ duration: Double?, samples: [TimestampedSample] = [], source: SignalSource = .camera) -> Trial {
            Trial(taskType: .fingerTap, side: .right, source: source, stopCondition: .thirtySec,
                startedAt: now, samples: samples, metrics: .empty, recordedDurationSeconds: duration)
        }
        let trials = [trial(10), trial(0), trial(nil), trial(.nan), trial(-1), trial(30, source: .synthetic),
                      trial(nil, samples: [.init(t: 0, value: 0.1), .init(t: 10, value: 0.1)])]
        let result = history(sessions: [.init(patientId: "TEAM", date: now, trials: trials)], now: now, calendar: c)
        let day = result.summary(on: now, calendar: c)
        #expect(day.savedMeasurementCount == 6 && day.movementAttemptCount == 2)
        #expect(day.recordedTaskHands.count == 1 && day.isActive)
    }

    @Test func futureEntriesAndFutureTakesCannotEarnCredit() {
        let c = calendar(), now = date("2026-10-23", in: calendar())
        let future = now.addingTimeInterval(60)
        let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
            startedAt: future, samples: [], metrics: .empty, recordedDurationSeconds: 10)
        let result = history([.init(date: future, type: .dailyCheckIn)],
            sessions: [.init(patientId: "TEAM", date: now, trials: [trial])], starts: [future], now: now, calendar: c)
        #expect(result.days.isEmpty && result.totalActiveDays == 0)
    }

    @Test func editsAndBackfilledCheckInsUseEntryDateNotEditDate() {
        let c = calendar(), now = date("2026-10-23", in: calendar())
        let id = UUID(), past = date("2026-10-20", in: c)
        let old = JournalEntry(id: id, date: past, type: .dailyCheckIn, updatedAt: past)
        let edited = JournalEntry(id: id, date: past, type: .dailyCheckIn, updatedAt: now)
        let result = history([old, edited], now: now, calendar: c)
        #expect(result.totalActiveDays == 1 && result.currentStreak == 0 && !result.todayIsActive)
        #expect(result.summary(on: past, calendar: c).journalEntryCount == 1)
    }

    @Test func consecutiveCalendarDaysSurviveDSTAndYearBoundaries() {
        let c = calendar()
        for dates in [["2026-03-28", "2026-03-29", "2026-03-30"],
                      ["2026-10-24", "2026-10-25", "2026-10-26"],
                      ["2026-12-31", "2027-01-01", "2027-01-02"]] {
            let values = dates.map { date($0, in: c) }
            let result = history(values.map { .init(date: $0, type: .dailyCheckIn) }, now: values[2], calendar: c)
            #expect(result.currentStreak == 3 && result.longestStreak == 3)
        }
    }

    @Test func weekUsesSuppliedCalendarAndZoneRatherThanRollingSevenDays() {
        let berlin = calendar(), sundayFirst = calendar("America/Los_Angeles", firstWeekday: 1)
        for c in [berlin, sundayFirst] {
            let now = date("2026-10-19", in: c)
            let sunday = date("2026-10-18", in: c)
            let result = history([.init(date: sunday, type: .dailyCheckIn), .init(date: now, type: .dailyCheckIn)],
                now: now, calendar: c)
            #expect(result.activeDaysThisWeek == (c.firstWeekday == 2 ? 1 : 2))
            #expect(result.currentStreak == 2)
        }
    }

    @Test func historicalEventReaderIgnoresMessagesRequestsAndMalformedLines() throws {
        let records: [[String: String]] = [
            ["ts": "2026-10-23T08:00:00.123Z", "type": "stimulation_started", "tag": "vCR"],
            ["ts": "2026-10-23T08:01:00Z", "type": "stimulation_started", "tag": "vCR"],
            ["ts": "2026-10-23T08:02:00Z", "type": "finger_check_started", "tag": "vCR"],
            ["ts": "2026-10-23T08:02:00Z", "type": "app_event", "tag": "vCR", "message": "Patient session completed"],
            ["ts": "invalid", "type": "stimulation_started", "tag": "vCR"],
            ["ts": "2026-10-23T08:03:00Z", "type": "stimulation_started", "tag": "other"]]
        var data = Data("broken\n".utf8)
        for record in records { data.append(try JSONEncoder().encode(record)); data.append(0x0A) }
        #expect(StimulationActivityReader.startDates(in: data).count == 2)
    }

    @Test func eventStoreReaderWaitsForPendingAppendsAndMissingLogIsEmpty() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = EventStore(directory: directory)
        #expect(try await store.recordedStimulationStartDates().isEmpty)
        store.append(type: "stimulation_started", tag: "vCR", message: "ignored")
        #expect(try await store.recordedStimulationStartDates().count == 1)
    }
}
