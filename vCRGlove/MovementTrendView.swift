//
//  MovementTrendView.swift
//  vCRGlove
//
//  Individual recording measurements, with context filters rather than
//  implied treatment effects or a guessed clinical score.
//

import SwiftUI
import Charts

// MARK: - Which metric to plot

enum TrendMetric: String, CaseIterable, Identifiable {
    case frequency, amplitude, rhythm, decrement, pauses, onset, quality

    // Keep the experimental index available to legacy data/export code, not patient UI.
    static var patientCases: [Self] { allCases.filter { $0 != .quality } }
    static var plotCases: [Self] { [.frequency, .rhythm] }

    func plotName(task: MovementTaskType) -> String {
        self == .frequency ? L10n(task == .fingerTap ? "Tapping rate" : "Repetition rate") : displayName
    }

    func plotValue(_ value: Double) -> Double { self == .rhythm ? value * 100 : value }

    func plotUnit(task: MovementTaskType) -> String {
        self == .rhythm ? "%" : L10n(task == .fingerTap ? "Taps/second" : "Repetitions/second")
    }

    func plotFormatted(_ value: Double, task: MovementTaskType) -> String {
        let locale = Locale(identifier: AppSettings.shared.language.rawValue)
        let key = self == .rhythm ? "%.1f %%" : (task == .fingerTap ? "%.1f taps/s" : "%.1f repetitions/s")
        return String(format: L10n(key), locale: locale, plotValue(value))
    }

    var plotExplanationKey: String {
        self == .frequency ? "How quickly you repeated the movement."
            : "Variation in the time between repetitions. Lower values mean a more even rhythm, not a clinical rating."
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frequency: return L10n("Speed")
        case .amplitude: return L10n("Amplitude")
        case .rhythm:    return L10n("Rhythm variability")
        case .decrement: return L10n("Amplitude decrement")
        case .pauses:    return L10n("Pauses")
        case .onset:     return L10n("Onset latency")
        case .quality:   return L10n("Quality index")
        }
    }

    var unit: String {
        switch self {
        case .frequency: return L10n("Hz")
        case .amplitude: return ""
        case .rhythm:    return L10n("CV")
        case .decrement: return L10n("/cycle")
        case .pauses:    return L10n("count")
        case .onset:     return L10n("s")
        case .quality:   return L10n("0–1")
        }
    }

    func value(from m: MovementMetrics) -> Double {
        switch self {
        case .frequency: return m.frequencyHz
        case .amplitude: return m.meanAmplitude
        case .rhythm:    return m.rhythmCV
        case .decrement: return m.amplitudeDecrementSlope
        case .pauses:    return Double(m.pauseCount)
        case .onset:     return m.onsetLatencySec
        case .quality:   return m.qualityIndex
        }
    }

    /// Calculation prerequisites, not a recording-quality or clinical threshold.
    func availability(for trial: Trial) -> TrendMetricAvailability {
        guard MovementSignalAssessment(samples: trial.samples).hasAnalysisInput else {
            return .insufficientSignal
        }
        let minimumCycles: Int
        switch self {
        case .onset: minimumCycles = 1
        case .frequency, .amplitude: minimumCycles = 2
        // Two full segments/intervals are needed to compare amplitudes, rhythm or pauses.
        case .decrement, .rhythm, .pauses, .quality: minimumCycles = 3
        }
        guard trial.metrics.cycleCount >= minimumCycles else { return .insufficientCycles }
        let result = value(from: trial.metrics)
        guard result.isFinite else { return .invalidValue }
        switch self {
        case .frequency, .amplitude:
            guard result > 0 else { return .invalidValue }
        case .rhythm, .pauses, .onset:
            guard result >= 0 else { return .invalidValue }
        case .quality:
            guard (0...1).contains(result) else { return .invalidValue }
        case .decrement: break
        }
        return .available(result)
    }

    func formatted(_ value: Double) -> String {
        let locale = Locale(identifier: AppSettings.shared.language.rawValue)
        switch self {
        case .frequency: return String(format: L10n("%.2f Hz"), locale: locale, value)
        case .amplitude: return String(format: L10n("%.3f"), locale: locale, value)
        case .decrement: return String(format: L10n("%.3f /cycle"), locale: locale, value)
        case .onset: return String(format: L10n("%.2f s"), locale: locale, value)
        case .pauses: return String(format: "%.0f", value)
        case .rhythm, .quality: return String(format: L10n("%.2f"), locale: locale, value)
        }
    }
}

enum TrendMetricAvailability: Equatable {
    case available(Double), insufficientSignal, insufficientCycles, invalidValue

    var value: Double? {
        if case .available(let value) = self { return value }
        return nil
    }

    var explanationKey: String {
        switch self {
        case .available: return ""
        case .insufficientSignal: return "Not enough signal was captured to calculate this value. Your recording is still saved."
        case .insufficientCycles: return "Not enough movement repetitions to calculate this value. Your recording is still saved."
        case .invalidValue: return "This value is unavailable. Your recording is still saved."
        }
    }
}

enum MovementRecordingFeedback: Equatable {
    case missingSignal, signalGaps, noDetectedCycles, someValuesUnavailable, captured

    init(trial: Trial) {
        let signal = MovementSignalAssessment(samples: trial.samples,
                                             recordedDurationSeconds: trial.recordedDurationSeconds)
        if !signal.hasAnalysisInput { self = .missingSignal }
        else if signal.hasGaps { self = .signalGaps }
        else if trial.metrics.cycleCount == 0 { self = .noDetectedCycles }
        else if TrendMetric.patientCases.contains(where: { $0.availability(for: trial).value == nil }) {
            self = .someValuesUnavailable
        } else { self = .captured }
    }

    var titleKey: String {
        switch self {
        case .missingSignal: return "No usable signal captured"
        case .signalGaps: return "Signal has gaps"
        case .noDetectedCycles: return "No complete repetitions detected"
        case .someValuesUnavailable: return "Some movement values unavailable"
        case .captured: return "Recording captured"
        }
    }

    var detailKey: String {
        switch self {
        case .missingSignal: return "There is not enough signal for movement values. You can keep this recording or try again."
        case .signalGaps: return "Part of the signal is missing. The available values may be less reliable. You can keep this recording or try again."
        case .noDetectedCycles: return "A signal was captured, but movement values could not be calculated. This does not mean you performed the task incorrectly."
        case .someValuesUnavailable: return "A signal was captured. Some values need more detected repetitions or could not be calculated."
        case .captured: return "Movement values are available."
        }
    }
}

struct MovementTrendRecording: Identifiable {
    let id: String
    let date: Date
    let context: StimulationContext
    let medicationTiming: MedicationTiming?
    let availability: TrendMetricAvailability
    let segment: Int
    let duration: TimeInterval?
    let hasSignalGaps: Bool
}

enum TrendPeriod: String, CaseIterable, Identifiable {
    case week, month, all
    var id: String { rawValue }
    var titleKey: String {
        switch self { case .week: return "7 days"; case .month: return "30 days"; case .all: return "All dates" }
    }
}

enum TrendMedicationFilter: String, CaseIterable, Identifiable {
    case all, sinceDose, noneToday, unknown
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .all: return "All medication timings"
        case .sinceDose: return "Time since last dose"
        case .noneToday: return "Not taken today"
        case .unknown: return "Timing unknown"
        }
    }
}

struct MovementTrendFilters: Equatable {
    var period: TrendPeriod = .all
    var context: StimulationContext?
    var medication: TrendMedicationFilter = .all
    var minimumDoseHours = 0
    var maximumDoseHours = 24

    func includes(_ trial: Trial, context: StimulationContext, now: Date, calendar: Calendar) -> Bool {
        if let selected = self.context, selected != context { return false }
        if period != .all {
            let days = period == .week ? 7 : 30
            guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)),
                  trial.startedAt >= start, trial.startedAt <= now else { return false }
        }
        let timing = trial.medicationTiming?.forRecording(at: trial.startedAt, calendar: calendar)
        switch medication {
        case .all: return true
        case .noneToday: return timing?.status == .noneToday
        case .unknown: return timing == nil || timing?.status == .unsure
        case .sinceDose:
            guard minimumDoseHours >= 0, maximumDoseHours >= minimumDoseHours,
                  let elapsed = timing?.elapsedSeconds(at: trial.startedAt) else { return false }
            return elapsed >= Double(minimumDoseHours) * 3600 && elapsed <= Double(maximumDoseHours) * 3600
        }
    }
}

struct MovementTrendSummary {
    let recordings: [MovementTrendRecording]
    let unfilteredCount: Int

    init(sessions: [MovementSession], task: MovementTaskType, side: BodySide, metric: TrendMetric,
         filters: MovementTrendFilters = .init(), now: Date = Date(), calendar: Calendar = .current,
         source: SignalSource? = nil) {
        let trials = sessions.flatMap { session in
            session.trials.filter { $0.taskType == task && $0.side == side && (source == nil || $0.source == source) }
                .map { (id: "\(session.id)/\($0.id)", context: session.stimulationContext, trial: $0) }
        }.sorted {
            if $0.trial.startedAt == $1.trial.startedAt { return $0.id < $1.id }
            return $0.trial.startedAt < $1.trial.startedAt
        }
        unfilteredCount = trials.count
        var segment = 0
        recordings = trials.filter { filters.includes($0.trial, context: $0.context, now: now, calendar: calendar) }.map { item in
            let rawAvailability = metric.availability(for: item.trial)
            let availability = rawAvailability.value.map { metric.plotValue($0).isFinite } == false
                ? TrendMetricAvailability.invalidValue : rawAvailability
            if availability.value == nil { segment += 1 }
            return MovementTrendRecording(id: item.id, date: item.trial.startedAt,
                                          context: item.context, medicationTiming: item.trial.medicationTiming?.forRecording(at: item.trial.startedAt, calendar: calendar),
                                          availability: availability, segment: segment,
                                          duration: item.trial.recordedDurationSeconds,
                                          hasSignalGaps: MovementSignalAssessment(samples: item.trial.samples,
                                              recordedDurationSeconds: item.trial.recordedDurationSeconds).hasGaps)
        }
    }

    var points: [MovementTrendRecording] { recordings.filter { $0.availability.value != nil } }
    var unavailableCount: Int { recordings.count - points.count }
    var canShowTrend: Bool { Set(points.map(\.date)).count >= 2 }

    func nearest(to date: Date) -> MovementTrendRecording? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Trend view

struct MovementTrendView: View {
    @ObservedObject private var store = TaskSessionStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var taskType: MovementTaskType = .fingerTap
    @State private var side: BodySide = .right
    @State private var metric: TrendMetric = .frequency
    @State private var filters = MovementTrendFilters()
    @State private var historyLimit = 50

    private var summary: MovementTrendSummary {
        var sessions = store.sessions
        var source: SignalSource? = taskType.preferredSource
        #if DEBUG && targetEnvironment(simulator)
        // UI fixtures never write to the session store or enter device/Release builds.
        if let fixtures = MovementTrendFixtures.sessions { sessions = fixtures; source = nil }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-session-save") { source = nil }
        #endif
        return MovementTrendSummary(sessions: sessions, task: taskType, side: side, metric: metric,
                                    filters: filters, source: source)
    }

    var body: some View {
        let summary = self.summary
        Form {
            Section {
                if dynamicTypeSize.isAccessibilitySize {
                    Menu {
                        taskPicker
                    } label: {
                        selectionLabel(title: L10n("Movement"), value: taskType.displayName)
                    }
                    .accessibilityIdentifier("trendTaskPicker")
                } else {
                    taskPicker
                        .accessibilityIdentifier("trendTaskPicker")
                }
                Picker(L10n("Hand"), selection: $side) {
                    Text(BodySide.left.displayName).tag(BodySide.left)
                    Text(BodySide.right.displayName).tag(BodySide.right)
                }
                .pickerStyle(.segmented)
                if dynamicTypeSize.isAccessibilitySize {
                    Menu {
                        metricPicker
                    } label: {
                        selectionLabel(title: L10n("Metric"), value: metric.plotName(task: taskType))
                    }
                    .accessibilityIdentifier("trendMetricPicker")
                } else {
                    metricPicker
                        .accessibilityIdentifier("trendMetricPicker")
                }
            }

            Section {
                if summary.recordings.isEmpty {
                    resultMessage(
                        title: L10n(summary.unfilteredCount == 0 ? "No recordings yet" : "No matching recordings"),
                        detail: summary.unfilteredCount == 0
                            ? String(format: L10n("Record a %@ test with your %@ hand to see trends here."), taskType.displayName, side.displayName)
                            : L10n("Try changing the filters below.")
                    )
                    .accessibilityIdentifier("trendEmpty")
                } else if summary.points.isEmpty {
                    resultMessage(
                        title: L10n("Not enough movement data"),
                        detail: L10n("This metric could not be calculated from your saved recordings.")
                    )
                    .accessibilityIdentifier("trendUnavailable")
                } else {
                    chart(summary: summary)
                        .frame(minHeight: 260)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("movementTrendChart")
                    if summary.points.count == 1 {
                        Text(L10n("More measurements needed for a trend."))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("trendSingleMeasurement")
                    }
                }
                if summary.unavailableCount > 0 && !summary.points.isEmpty {
                    Text(String(format: L10n("Results unavailable for this metric: %d"), summary.unavailableCount))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(format: L10n("%@ over time"), metric.plotName(task: taskType)))
            } footer: {
                if !summary.points.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n(metric.plotExplanationKey))
                        Text(L10n("These values describe your recordings. They are not a clinical rating."))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section(L10n("Filters")) {
                Picker(L10n("Period"), selection: $filters.period) {
                    ForEach(TrendPeriod.allCases) { Text(L10n($0.titleKey)).tag($0) }
                }
                .accessibilityIdentifier("trendPeriodFilter")
                Menu {
                    Button(L10n("All stimulation timings")) { filters.context = nil }
                    ForEach(StimulationContext.allCases) { context in
                        Button(L10n(context.titleKey)) { filters.context = context }
                    }
                } label: {
                    selectionLabel(title: L10n("Stimulation"),
                                   value: L10n(filters.context?.titleKey ?? "All stimulation timings"))
                }
                .accessibilityIdentifier("trendContextFilter")
                Menu {
                    ForEach(TrendMedicationFilter.allCases) { medication in
                        Button(L10n(medication.titleKey)) { filters.medication = medication }
                    }
                } label: {
                    selectionLabel(title: L10n("Last Parkinson's medication"), value: L10n(filters.medication.titleKey))
                }
                .accessibilityIdentifier("trendMedicationFilter")
                if filters.medication == .sinceDose {
                    Stepper(String(format: L10n("From %d hours"), filters.minimumDoseHours),
                            value: $filters.minimumDoseHours, in: 0...filters.maximumDoseHours)
                        .accessibilityIdentifier("trendDoseMinimum")
                    Stepper(String(format: L10n("To %d hours"), filters.maximumDoseHours),
                            value: $filters.maximumDoseHours, in: filters.minimumDoseHours...168)
                        .accessibilityIdentifier("trendDoseMaximum")
                }
            }
            if !summary.recordings.isEmpty {
                Section {
                    NavigationLink {
                        List {
                            ForEach(Array(summary.recordings.suffix(historyLimit).reversed())) { recording in
                                recordingRow(recording)
                            }
                            if summary.recordings.count > historyLimit {
                                Button(L10n("Show older recordings")) { historyLimit += 50 }
                            }
                        }
                        .navigationTitle(L10n("Recording history"))
                        .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        Label(L10n("Recording history"), systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("trendRecordingHistory")
                }
            }
        }
        .navigationTitle(L10n("Trends"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { MovementExportView() } label: {
                    Image(systemName: "folder")
                }
                .accessibilityLabel(L10n("Data"))
                .accessibilityIdentifier("trendData")
            }
        }
    }

    private var taskPicker: some View {
        Picker(L10n("Movement"), selection: $taskType) {
            ForEach(MovementTaskType.allCases) { task in
                Text(task.displayName).tag(task)
            }
        }
    }

    private var metricPicker: some View {
        Picker(L10n("Metric"), selection: $metric) {
            ForEach(TrendMetric.plotCases) { metric in
                Text(metric.plotName(task: taskType)).tag(metric)
            }
        }
    }

    private func selectionLabel(title: String, value: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down").font(.caption)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func chart(summary: MovementTrendSummary) -> some View {
        let first = summary.points.first!.date
        let last = summary.points.last!.date
        let padding = max(3600, last.timeIntervalSince(first) * 0.05)
        let maximum = summary.points.compactMap { $0.availability.value }.map(metric.plotValue).max() ?? 0
        return Chart {
            ForEach(summary.points) { p in
                if let value = p.availability.value {
                    PointMark(x: .value(L10n("Date"), p.date),
                              y: .value(metric.plotName(task: taskType), metric.plotValue(value)))
                        .foregroundStyle(Color.accentColor)
                        .symbolSize(80)
                        .accessibilityLabel("\(contextLabel(p.context)), \(p.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: AppSettings.shared.language.rawValue))))")
                        .accessibilityValue(metric.plotFormatted(value, task: taskType))
                }
            }
        }
        .chartXScale(domain: first.addingTimeInterval(-padding)...last.addingTimeInterval(padding))
        .chartYScale(domain: 0...max(1, maximum <= Double.greatestFiniteMagnitude / 1.15 ? maximum * 1.15 : maximum))
        .chartXAxis { AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) }
        .chartYAxisLabel(metric.plotUnit(task: taskType))
        .chartLegend(.hidden)
    }

    private func resultMessage(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.xyaxis.line")
                .font(.title)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(.vertical, 12)
    }

    private func recordingRow(_ recording: MovementTrendRecording) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let value = recording.availability.value {
                Text(metric.plotFormatted(value, task: taskType))
                    .font(.headline)
                    .accessibilityIdentifier("trendRecordingValue")
            } else {
                Text(L10n("Value unavailable"))
                    .font(.headline)
                Text(L10n(recording.availability.explanationKey))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(recording.date, format: .dateTime.day().month().year().hour().minute())
                .font(.subheadline)
                .accessibilityIdentifier("trendRecordingDate")
            Text(contextLabel(recording.context))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let timing = recording.medicationTiming {
                MovementMedicationSummary(timing: timing, recordedAt: recording.date)
            } else {
                Text(L10n("Medication timing unknown")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let duration = recording.duration, duration.isFinite, duration >= 0 {
                Text(String(format: L10n("Recorded: %.1f seconds"), locale: Locale(identifier: AppSettings.shared.language.rawValue), duration))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if recording.hasSignalGaps {
                Text(L10n("Signal has gaps. These values may be less reliable."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func contextLabel(_ c: StimulationContext) -> String {
        L10n(c.titleKey)
    }
}

#if DEBUG && targetEnvironment(simulator)
private enum MovementTrendFixtures {
    static let sessions: [MovementSession]? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--ui-test-trend-scenario"),
              arguments.indices.contains(index + 1) else { return nil }
        let scenario = arguments[index + 1]
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let samples = (0..<60).map { TimestampedSample(t: Double($0) / 10, value: sin(Double($0)) + 1) }
        let metrics = MovementMetrics(cycleCount: 10, frequencyHz: 2, meanAmplitude: 0.3,
                                      amplitudeDecrementSlope: 0, rhythmCV: 0.1, pauseCount: 0,
                                      onsetLatencySec: 0, qualityIndex: 0.8)
        func session(offset: TimeInterval, available: Bool, context: StimulationContext = .unspecified,
                     medication: MedicationTiming? = nil) -> MovementSession {
            let startedAt = date.addingTimeInterval(offset)
            let trial = Trial(taskType: .fingerTap, side: .right, source: .synthetic,
                              stopCondition: .thirtySec, startedAt: startedAt,
                              samples: available ? samples : [], metrics: available ? metrics : .empty,
                              medicationTiming: medication, recordedDurationSeconds: 6)
            return MovementSession(patientId: "UI-FIXTURE", date: startedAt,
                                   stimulationContext: context, trials: [trial])
        }
        switch scenario {
        case "empty": return []
        case "unavailable": return [session(offset: 0, available: false)]
        case "single": return [session(offset: 0, available: true)]
        case "mixed": return [session(offset: 0, available: true), session(offset: 3600, available: false)]
        case "multiple": return [session(offset: 0, available: true), session(offset: 3600, available: false),
                                 session(offset: 7200, available: true)]
        case "contexts": return [
            session(offset: 0, available: true, context: .preStim,
                    medication: MedicationTiming(status: .takenAt, takenAt: date.addingTimeInterval(-3600))),
            session(offset: 3600, available: true, context: .postStim,
                    medication: MedicationTiming(status: .noneToday, confirmedAt: date)),
            session(offset: 7200, available: true, context: .noStimPlanned,
                    medication: MedicationTiming(status: .unsure)),
            session(offset: 10800, available: true, context: .baseline),
            session(offset: 14400, available: true)
        ]
        default: return nil
        }
    }()
}
#endif

#Preview {
    NavigationStack { MovementTrendView() }
}
