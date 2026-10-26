import Foundation

enum RoutineMilestone: String, Codable, CaseIterable {
    case threeDayRun, sevenDayRun, thirtyActiveDays

    var titleKey: String {
        switch self {
        case .threeDayRun: return "routine.milestone.three"
        case .sevenDayRun: return "routine.milestone.seven"
        case .thirtyActiveDays: return "routine.milestone.thirty"
        }
    }

    static func earned(in history: ActivityHistory) -> [Self] {
        allCases.filter {
            switch $0 {
            case .threeDayRun: return history.longestStreak >= 3
            case .sevenDayRun: return history.longestStreak >= 7
            case .thirtyActiveDays: return history.totalActiveDays >= 30
            }
        }
    }
}

@MainActor
struct RoutineMilestoneLedger {
    nonisolated static let enabledKey = "routineCelebrationsEnabled"
    nonisolated static let seenKey = "routineMilestonesSeen"
    let defaults: UserDefaults

    /// Commit before presentation; one acknowledgement absorbs lower milestones.
    /// Corrupt UI-only state fails quietly rather than replaying every achievement.
    func claim(history: ActivityHistory, participantID: String, enabled: Bool, allowed: Bool) -> RoutineMilestone? {
        guard enabled, allowed else { return nil }
        let earned = RoutineMilestone.earned(in: history)
        var seen: [String: Set<RoutineMilestone>]
        if let data = defaults.data(forKey: Self.seenKey) {
            guard let decoded = try? JSONDecoder().decode([String: Set<RoutineMilestone>].self, from: data) else { return nil }
            seen = decoded
        } else {
            guard defaults.object(forKey: Self.seenKey) == nil else { return nil }
            seen = [:]
        }
        let id = MovementTrendIdentityLinks.isUnassigned(participantID) ? "unset" : participantID
        let previous = seen[id] ?? []
        guard let next = earned.last(where: { !previous.contains($0) }) else { return nil }
        seen[id, default: []].formUnion(earned)
        guard let encoded = try? JSONEncoder().encode(seen) else { return nil }
        defaults.set(encoded, forKey: Self.seenKey)
        return next
    }
}

/// Participation, not treatment adherence or a motor-performance score.
struct DailyActivitySummary: Equatable {
    let day: Date
    var journalEntryCount = 0
    var hasCheckIn = false
    var hasStimulationLog = false
    var hasRecordedStimulationStart = false
    var savedMeasurementCount = 0
    var movementAttemptCount = 0
    var recordedTaskHands = Set<TaskHand>()

    struct TaskHand: Hashable {
        let task: MovementTaskType
        let side: BodySide
    }

    var isActive: Bool {
        hasCheckIn || hasRecordedStimulationStart || movementAttemptCount > 0
    }
}

struct ActivityHistory {
    let days: [DailyActivitySummary]
    let currentStreak: Int
    let longestStreak: Int
    let totalActiveDays: Int
    let activeDaysThisWeek: Int
    let todayIsActive: Bool

    func summary(on date: Date, calendar: Calendar) -> DailyActivitySummary {
        let day = calendar.startOfDay(for: date)
        return days.first { $0.day == day } ?? DailyActivitySummary(day: day)
    }
}

enum DailyActivityCalculator {
    /// Journal and stimulation inputs must already belong to the same person.
    /// Movement identities are explicit: never merge everyone who used a phone.
    static func calculate(journal: [JournalEntry], sessions: [MovementSession],
                          movementParticipantIDs: Set<String>, stimulationStarts: [Date],
                          now: Date, calendar: Calendar) -> ActivityHistory {
        let today = calendar.startOfDay(for: now)
        var summaries: [Date: DailyActivitySummary] = [:]
        func update(_ date: Date, _ edit: (inout DailyActivitySummary) -> Void) {
            guard date.timeIntervalSinceReferenceDate.isFinite, date <= now else { return }
            let day = calendar.startOfDay(for: date)
            var summary = summaries[day] ?? DailyActivitySummary(day: day)
            edit(&summary)
            summaries[day] = summary
        }

        // Prefer an edited record over a stale copy of the same journal UUID.
        let orderedEntries = journal.sorted {
            let left = $0.updatedAt ?? $0.createdAt ?? $0.date
            let right = $1.updatedAt ?? $1.createdAt ?? $1.date
            return left == right ? $0.date > $1.date : left > right
        }
        var entryIDs = Set<UUID>()
        for entry in orderedEntries where entryIDs.insert(entry.id).inserted {
            update(entry.date) { day in
                day.journalEntryCount += 1
                if entry.type == .dailyCheckIn { day.hasCheckIn = true }
                if entry.type == .stimulation { day.hasStimulationLog = true }
            }
        }
        for date in stimulationStarts {
            update(date) { $0.hasRecordedStimulationStart = true }
        }

        var trialIDs = Set<UUID>()
        let scopedSessions = sessions.filter { movementParticipantIDs.contains($0.patientId) }
            .sorted { $0.date == $1.date ? $0.id.uuidString > $1.id.uuidString : $0.date > $1.date }
        for session in scopedSessions {
            for trial in session.trials where trial.source != .synthetic && trialIDs.insert(trial.id).inserted {
                // Use the take's date, not the containing session's date.
                update(trial.startedAt) { day in
                    day.savedMeasurementCount += 1
                    if isGenuineAttempt(trial) {
                        day.movementAttemptCount += 1
                        day.recordedTaskHands.insert(.init(task: trial.taskType, side: trial.side))
                    }
                }
            }
        }

        let days = summaries.values.sorted { $0.day < $1.day }
        let activeDays = days.filter(\.isActive).map(\.day)
        let activeSet = Set(activeDays)
        let todayIsActive = activeSet.contains(today)
        var cursor = todayIsActive ? today : calendar.date(byAdding: .day, value: -1, to: today)
        var current = 0
        while let day = cursor, activeSet.contains(day) {
            current += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: day)
        }
        var longest = 0
        var run = 0
        var previous: Date?
        for day in activeDays {
            run = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day ? run + 1 : 1
            longest = max(longest, run)
            previous = day
        }
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        return ActivityHistory(days: days, currentStreak: current, longestStreak: longest,
            totalActiveDays: activeDays.count,
            activeDaysThisWeek: activeDays.filter { week?.contains($0) == true }.count,
            todayIsActive: todayIsActive)
    }

    private static func isGenuineAttempt(_ trial: Trial) -> Bool {
        // No quality, speed, amplitude or minimum clinical-duration gate. An empty
        // immediate stop is excluded; an actual attempt with lost tracking counts.
        if let duration = trial.recordedDurationSeconds {
            return duration.isFinite && duration > 0
        }
        let times = trial.samples.filter { $0.t.isFinite && $0.t >= 0 && $0.value.isFinite }.map(\.t)
        guard let first = times.min(), let last = times.max() else { return false }
        return last > first
    }
}

enum StimulationActivityReader {
    struct Evidence {
        struct Assignment {
            let date: Date
            let participantID: String
        }
        var starts: [Date] = []
        var reassignments: [Assignment] = []
    }
    private struct Event: Decodable {
        let ts: String
        let type: String
        let tag: String
        let details: [String: String]?
    }

    /// Ignore free-text messages, finger checks and requested session durations.
    /// A recorded start is participation evidence, not proof of delivered dose.
    static func startDates(in data: Data) -> [Date] {
        evidence(in: data).starts
    }

    static func evidence(in data: Data) -> Evidence {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        var result = Evidence()
        for line in data.split(separator: 0x0A) {
            guard let event = try? decoder.decode(Event.self, from: Data(line)),
                  let date = fractional.date(from: event.ts) ?? plain.date(from: event.ts) else { continue }
            if event.type == "stimulation_started", event.tag == "vCR" { result.starts.append(date) }
            if event.type == "admin_metadata", event.tag == "Research",
               event.details?["studyIDChanged"] == "true",
               let previous = event.details?["previousPatientID"], !MovementTrendIdentityLinks.isUnassigned(previous),
               let id = event.details?["patientID"], previous != id {
                result.reassignments.append(.init(date: date, participantID: id))
            }
        }
        return result
    }
}

/// Display-only scope. Never rewrites original study IDs or journal dates.
struct JournalActivityScope {
    let journal: [JournalEntry]
    let sessions: [MovementSession]
    let starts: [Date]
    let limitsUnassignedHistory: Bool

    init(journal: [JournalEntry], sessions: [MovementSession], evidence: StimulationActivityReader.Evidence,
         participantID: String, links: MovementTrendIdentityLinks, now: Date) {
        let id = MovementTrendIdentityLinks.isUnassigned(participantID) ? "unset" : participantID
        self.sessions = sessions.compactMap { session in
            let trials = session.trials.filter {
                let displayID = links.displayID(for: session, trial: $0)
                return (MovementTrendIdentityLinks.isUnassigned(displayID) ? "unset" : displayID) == id
            }
            guard !trials.isEmpty else { return nil }
            return MovementSession(id: session.id, patientId: id, date: session.date,
                stimulationContext: session.stimulationContext, trials: trials)
        }
        let assignment = evidence.reassignments.filter { $0.date <= now }.max { $0.date < $1.date }
        let hasOtherOwner = sessions.contains { session in
            session.trials.contains {
                let owner = links.displayID(for: session, trial: $0)
                return !MovementTrendIdentityLinks.isUnassigned(owner) && owner != id
            }
        }
        if let assignment, assignment.participantID == id {
            self.journal = journal.filter { $0.date >= assignment.date }
            starts = evidence.starts.filter { $0 >= assignment.date }
            limitsUnassignedHistory = true
        } else if assignment != nil || hasOtherOwner {
            // Device-only records cannot safely be attributed after an unknown reassignment.
            self.journal = []
            starts = []
            limitsUnassignedHistory = true
        } else {
            self.journal = journal
            starts = evidence.starts
            limitsUnassignedHistory = false
        }
    }
}
