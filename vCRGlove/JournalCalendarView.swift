import SwiftUI

private struct RoutineAcknowledgementPermissionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var routineAcknowledgementsAllowed: Bool {
        get { self[RoutineAcknowledgementPermissionKey.self] }
        set { self[RoutineAcknowledgementPermissionKey.self] = newValue }
    }
}

@MainActor
final class JournalActivityController: ObservableObject {
    @Published private(set) var history: ActivityHistory?
    @Published private(set) var sessions: [MovementSession] = []
    @Published private(set) var starts: [Date] = []
    @Published private(set) var limitsUnassignedHistory = false
    @Published private(set) var failed = false
    @Published private(set) var canRetry = true
    @Published var refreshToken = 0
    @Published private(set) var referenceDate = Date.distantPast
    let events: EventStore

    init(events: EventStore? = nil) {
        #if DEBUG && targetEnvironment(simulator)
        let args = ProcessInfo.processInfo.arguments
        if events == nil, let index = args.firstIndex(of: "--ui-test-journal"), args.indices.contains(index + 1) {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(args[index + 1])")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.events = EventStore(directory: directory)
            return
        }
        #endif
        self.events = events ?? .shared
    }

    func unavailable(failed: Bool, canRetry: Bool = true) {
        history = nil
        sessions = []
        starts = []
        self.failed = failed
        self.canRetry = canRetry
    }

    func refresh(journal: [JournalEntry], sessions: [MovementSession], participantID: String,
                 links: MovementTrendIdentityLinks, now: Date, calendar: Calendar) async {
        unavailable(failed: false)
        do {
            let evidence = try await events.recordedActivityEvidence()
            try Task.checkCancellation()
            let scope = JournalActivityScope(journal: journal, sessions: sessions, evidence: evidence,
                participantID: participantID, links: links, now: now)
            let id = MovementTrendIdentityLinks.isUnassigned(participantID) ? "unset" : participantID
            self.sessions = scope.sessions
            starts = scope.starts.filter { $0 <= now }
            limitsUnassignedHistory = scope.limitsUnassignedHistory
            referenceDate = now
            history = DailyActivityCalculator.calculate(journal: scope.journal, sessions: scope.sessions,
                movementParticipantIDs: [id], stimulationStarts: starts, now: now, calendar: calendar)
        } catch is CancellationError {
            // A newer snapshot owns the UI; never publish the cancelled one.
        } catch {
            guard !Task.isCancelled else { return }
            unavailable(failed: true)
        }
    }
}

struct JournalActivityLifecycle: ViewModifier {
    @ObservedObject var activity: JournalActivityController
    @ObservedObject private var journal = JournalStore.shared
    @ObservedObject private var tasks = TaskSessionStore.shared
    @AppStorage("patientID") private var participantID = ""
    @AppStorage("movementTrendIdentityLinks") private var linksData = Data()
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var revision = 0

    private struct RefreshKey: Hashable {
        let revision: Int
        let token: Int
        let id: String
        let links: Data
        let locale: String
        let zone: String
    }

    func body(content: Content) -> some View {
        content
            .task(id: RefreshKey(revision: revision, token: activity.refreshToken, id: participantID,
                links: linksData, locale: locale.identifier, zone: calendar.timeZone.identifier)) {
                guard tasks.hasLoaded else { activity.unavailable(failed: false); return }
                guard !journal.isLoadBlocked, !tasks.activityHistoryLoadFailed else {
                    activity.unavailable(failed: true, canRetry: false); return
                }
                await activity.refresh(journal: journal.entries, sessions: tasks.sessions,
                    participantID: participantID, links: .init(data: linksData), now: Date(), calendar: calendar)
            }
            .onAppear { revision += 1 }
            .onReceive(journal.$entries.dropFirst()) { _ in revision += 1 }
            .onReceive(journal.$isLoadBlocked.dropFirst()) { _ in revision += 1 }
            .onReceive(tasks.$sessions.dropFirst()) { _ in revision += 1 }
            .onReceive(tasks.$hasLoaded.dropFirst()) { _ in revision += 1 }
            .onReceive(tasks.$activityHistoryLoadFailed.dropFirst()) { _ in revision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: EventStore.activityDidChange)) { _ in revision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in revision += 1 }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { now in
                if scenePhase == .active, !calendar.isDate(now, inSameDayAs: activity.referenceDate) { revision += 1 }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { revision += 1 } }
    }
}

struct JournalCalendarPanel: View {
    @Binding var selectedDate: Date
    @ObservedObject var activity: JournalActivityController
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.routineAcknowledgementsAllowed) private var acknowledgementsAllowed
    @ObservedObject private var recording = RoutineRecordingActivity.shared
    @AppStorage(RoutineMilestoneLedger.enabledKey) private var celebrationsEnabled = true
    @AppStorage("patientID") private var participantID = ""
    @State private var acknowledgement: RoutineMilestone?
    @State private var isVisible = false
    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var showsRoutineInfo = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private struct AcknowledgementKey: Hashable {
        let longest: Int?
        let total: Int?
        let participantID: String
        let enabled: Bool
        let allowed: Bool
    }

    private var canAcknowledge: Bool {
        acknowledgementsAllowed && !recording.isActive && scenePhase == .active && isVisible && !showsRoutineInfo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            routineSummary
            Divider()
            HStack(spacing: 8) {
                Text(displayedMonth.formatted(.dateTime.month(.wide).year().locale(locale)))
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                monthButton("chevron.left", title: "Previous month", offset: -1)
                monthButton("chevron.right", title: "Next month", offset: 1)
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(height: 24).lineLimit(1).minimumScaleFactor(0.6)
                }
                ForEach(Array(calendarDays.enumerated()), id: \.offset) { _, date in
                    if let date { dayButton(date) }
                    else { Color.clear.frame(height: 48) }
                }
            }
            if !calendar.isDateInToday(selectedDate) {
                Button {
                    selectedDate = Date()
                    displayedMonth = calendar.startOfMonth(for: selectedDate)
                } label: { Label(L10n("Today"), systemImage: "calendar").frame(minHeight: 44) }
                    .accessibilityIdentifier("journalReturnToday")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false; acknowledgement = nil }
        .onChange(of: participantID) { _, _ in acknowledgement = nil }
        .task(id: AcknowledgementKey(longest: activity.history?.longestStreak,
            total: activity.history?.totalActiveDays, participantID: participantID,
            enabled: celebrationsEnabled, allowed: canAcknowledge)) {
            guard celebrationsEnabled, canAcknowledge else { acknowledgement = nil; return }
            guard let history = activity.history else { return }
            if let acknowledgement, !RoutineMilestone.earned(in: history).contains(acknowledgement) {
                self.acknowledgement = nil
            }
            do {
                // Let navigation/capture teardown settle; changed eligibility cancels this task.
                try await Task.sleep(nanoseconds: 350_000_000)
                if acknowledgement == nil {
                    acknowledgement = RoutineMilestoneLedger(defaults: .standard).claim(history: history,
                        participantID: participantID, enabled: celebrationsEnabled, allowed: canAcknowledge)
                }
                guard acknowledgement != nil else { return }
                try await Task.sleep(nanoseconds: UIAccessibility.isVoiceOverRunning ? 20_000_000_000 : 8_000_000_000)
                acknowledgement = nil
            } catch { }
        }
        .onChange(of: activity.referenceDate) { previous, current in
            if !calendar.isDate(previous, inSameDayAs: current), calendar.isDate(selectedDate, inSameDayAs: previous) {
                selectedDate = current
                displayedMonth = calendar.startOfMonth(for: current)
            }
        }
        .onChange(of: calendar.timeZone.identifier) { _, _ in
            displayedMonth = calendar.startOfMonth(for: selectedDate)
        }
        .sheet(isPresented: $showsRoutineInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n("routine.explanation"))
                        if activity.limitsUnassignedHistory { Text(L10n("routine.identityScope")) }
                        if let history = activity.history {
                            LabeledContent(L10n("routine.totalDays"), value: history.totalActiveDays.formatted())
                            LabeledContent(L10n("routine.longestStreak"), value: history.longestStreak.formatted())
                            let earned = RoutineMilestone.earned(in: history)
                            if !earned.isEmpty {
                                Text(L10n("routine.milestones")).font(.headline)
                                ForEach(earned, id: \.rawValue) { milestone in
                                    Label(L10n(milestone.titleKey), systemImage: "checkmark.seal")
                                }
                            }
                        }
                    }.padding()
                }
                .navigationTitle(L10n("routine.title"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n("Done")) { showsRoutineInfo = false } } }
            }
        }
    }

    @ViewBuilder private var routineSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n("routine.title")).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { showsRoutineInfo = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
                    .accessibilityLabel(L10n("routine.about"))
                    .accessibilityIdentifier("journalRoutineInfo")
            }
            if let history = activity.history {
                Text(history.currentStreak == 0 ? L10n(history.totalActiveDays > 0 ? "routine.welcomeBack" : "routine.ready") : String(format:
                    L10n(history.currentStreak == 1 ? "routine.oneDay" : "routine.streak"), history.currentStreak))
                    .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("journalRoutineStreak")
                    .accessibilityValue(String(history.currentStreak))
                ZStack(alignment: .leading) {
                    Text(String(format: L10n(history.activeDaysThisWeek == 1 ? "routine.oneDayThisWeek" : "routine.daysThisWeek"), history.activeDaysThisWeek))
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        .opacity(acknowledgement == nil ? 1 : 0)
                        .accessibilityHidden(acknowledgement != nil)
                        .accessibilityIdentifier("journalRoutineWeek")
                    if let acknowledgement {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(.teal)
                                .accessibilityHidden(true)
                            Text(String(format: L10n("routine.milestone.message"), L10n(acknowledgement.titleKey)))
                                .font(.subheadline.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("journalMilestoneMessage")
                            Button { self.acknowledgement = nil } label: {
                                Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel(L10n("Dismiss"))
                            .accessibilityIdentifier("journalDismissMilestone")
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .transaction { $0.animation = nil }
            } else if activity.failed {
                Text(L10n("routine.unavailable")).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if activity.canRetry {
                    Button(L10n("Try again")) { activity.refreshToken += 1 }
                        .accessibilityIdentifier("journalActivityRetry")
                } else {
                    Text(L10n("routine.restart")).font(.caption).foregroundStyle(.secondary)
                }
            } else { ProgressView(L10n("routine.loading")).font(.subheadline) }
        }
    }

    private func dayButton(_ date: Date) -> some View {
        let active = activity.history?.summary(on: date, calendar: calendar).isActive == true
        return Button { selectedDate = date } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(calendar.isDateInToday(date) || isSelected(date) ? .bold : .regular))
                    .foregroundStyle(date > Date() && !calendar.isDateInToday(date) ? Color.secondary : .primary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.teal).opacity(active ? 1 : 0).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? Color.teal.opacity(0.13) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected(date) ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(locale)))
        .accessibilityValue(L10n(activity.failed ? "routine.unavailable" : activity.history == nil ? "routine.loading" : active ? "routine.activeDay" : "routine.noActivity"))
        .accessibilityAddTraits(isSelected(date) ? .isSelected : [])
        .accessibilityIdentifier("journalCalendarDay-\(calendar.component(.day, from: date))")
    }

    private func monthButton(_ symbol: String, title: String, offset: Int) -> some View {
        Button {
            guard let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) else { return }
            displayedMonth = month
            selectedDate = month
        } label: { Image(systemName: symbol).frame(width: 44, height: 44) }
            .buttonStyle(.plain).accessibilityLabel(L10n(title)).help(L10n(title))
            .accessibilityIdentifier(offset < 0 ? "journalPreviousMonth" : "journalNextMonth")
    }

    private var weekdaySymbols: [String] {
        var localizedCalendar = calendar
        localizedCalendar.locale = locale
        let symbols = localizedCalendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private var calendarDays: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: displayedMonth) - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map { calendar.date(byAdding: .day, value: $0 - 1, to: displayedMonth) }
    }
    private func isSelected(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: selectedDate) }
}

struct JournalCalendarView: View {
    @State private var selectedDate = Date()
    @StateObject private var activity = JournalActivityController()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                JournalCalendarPanel(selectedDate: $selectedDate, activity: activity)
                NavigationLink { DailyLogView(date: selectedDate) } label: {
                    Label(L10n("View entries"), systemImage: "list.bullet").frame(minHeight: 44)
                }
            }.padding()
        }
        .modifier(JournalActivityLifecycle(activity: activity))
        .navigationTitle(L10n("Calendar"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
