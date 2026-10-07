//
//  MovementTrendView.swift
//  vCRGlove
//
//  Patient-facing trend view (Task E): plots one chosen movement metric over
//  time from saved trials, with recordings colored by
//  their stimulation context (baseline / before / after session) — a clear
//  before/after visualization without any guessed UPDRS score.
//

import SwiftUI
import Charts

// MARK: - Which metric to plot

enum TrendMetric: String, CaseIterable, Identifiable {
    case frequency, amplitude, rhythm, decrement, pauses, onset, quality

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
        let samples = trial.samples
        guard samples.count >= 4,
              samples.allSatisfy({ $0.t.isFinite && $0.value.isFinite && $0.t >= 0 }),
              let first = samples.first, let last = samples.last, last.t > first.t,
              zip(samples, samples.dropFirst()).allSatisfy({ pair in pair.0.t <= pair.1.t }) else {
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

struct MovementTrendRecording: Identifiable {
    let id: String
    let date: Date
    let context: StimulationContext
    let availability: TrendMetricAvailability
    let segment: Int
}

struct MovementTrendSummary {
    let recordings: [MovementTrendRecording]

    init(sessions: [MovementSession], task: MovementTaskType, side: BodySide, metric: TrendMetric) {
        let trials = sessions.flatMap { session in
            session.trials.filter { $0.taskType == task && $0.side == side }
                .map { (id: "\(session.id)/\($0.id)", context: session.stimulationContext, trial: $0) }
        }.sorted {
            if $0.trial.startedAt == $1.trial.startedAt { return $0.id < $1.id }
            return $0.trial.startedAt < $1.trial.startedAt
        }
        var segment = 0
        recordings = trials.map { item in
            let availability = metric.availability(for: item.trial)
            if availability.value == nil { segment += 1 }
            return MovementTrendRecording(id: item.id, date: item.trial.startedAt,
                                          context: item.context, availability: availability, segment: segment)
        }
    }

    var points: [MovementTrendRecording] { recordings.filter { $0.availability.value != nil } }
    var unavailableCount: Int { recordings.count - points.count }
    var canShowTrend: Bool { Set(points.map(\.date)).count >= 2 }
}

// MARK: - Trend view

struct MovementTrendView: View {
    @ObservedObject private var store = TaskSessionStore.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var taskType: MovementTaskType = .fingerTap
    @State private var side: BodySide = .right
    @State private var metric: TrendMetric = .frequency

    private var summary: MovementTrendSummary {
        var sessions = store.sessions
        #if DEBUG && targetEnvironment(simulator)
        // UI fixtures never write to the session store or enter device/Release builds.
        if let fixtures = MovementTrendFixtures.sessions { sessions = fixtures }
        #endif
        return MovementTrendSummary(sessions: sessions, task: taskType, side: side, metric: metric)
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
                        selectionLabel(title: L10n("Metric"), value: metric.displayName)
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
                        title: L10n("No recordings yet"),
                        detail: String(format: L10n("Record a %@ test with your %@ hand to see trends here."), taskType.displayName, side.displayName)
                    )
                    .accessibilityIdentifier("trendEmpty")
                } else if summary.points.isEmpty {
                    resultMessage(
                        title: L10n("Not enough movement data"),
                        detail: L10n("This metric could not be calculated from your saved recordings.")
                    )
                    .accessibilityIdentifier("trendUnavailable")
                } else if summary.canShowTrend {
                    chart(summary: summary)
                        .frame(minHeight: 260)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("movementTrendChart")
                } else if let latest = summary.points.last {
                    recordingRow(latest, prominent: true)
                    Text(L10n("More measurements needed for a trend."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("trendSingleMeasurement")
                }
                if summary.unavailableCount > 0 && !summary.points.isEmpty {
                    Text(String(format: L10n("Results unavailable for this metric: %d"), summary.unavailableCount))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(String(format: L10n("%@ over time"), metric.displayName))
            } footer: {
                if !summary.points.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        if summary.canShowTrend && summary.points.contains(where: { $0.context == .unspecified }) {
                            Text(L10n("Blue marks recordings without stimulation timing. It does not indicate recording quality."))
                        }
                        Text(L10n(metric == .quality
                             ? "Experimental movement index. Not recording quality or a clinical score."
                             : "These values describe your recordings. They are not a clinical rating."))
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if summary.recordings.count > 1 || summary.points.isEmpty && !summary.recordings.isEmpty {
                Section(L10n("Latest recordings")) {
                    ForEach(Array(summary.recordings.suffix(5).reversed())) { recording in
                        recordingRow(recording)
                    }
                }
            }
        }
        .navigationTitle(L10n("Trends"))
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
            ForEach(TrendMetric.allCases) { metric in
                Text(metric.displayName).tag(metric)
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
    }

    private func chart(summary: MovementTrendSummary) -> some View {
        let colors: [String: Color] = [
            contextLabel(.baseline): .gray, contextLabel(.preStim): .orange,
            contextLabel(.postStim): .green, contextLabel(.unspecified): .blue
        ]
        let usedLabels = StimulationContext.allCases
            .filter { context in summary.points.contains { $0.context == context } }
            .map { contextLabel($0) }
        return Chart {
            ForEach(summary.points) { p in
                if let value = p.availability.value {
                    LineMark(x: .value(L10n("Date"), p.date), y: .value(metric.displayName, value),
                             series: .value("Segment", p.segment))
                        .foregroundStyle(.gray.opacity(0.4))
                        .interpolationMethod(.linear)
                    PointMark(x: .value(L10n("Date"), p.date), y: .value(metric.displayName, value))
                        .foregroundStyle(by: .value(L10n("Context"), contextLabel(p.context)))
                        .symbolSize(80)
                        .accessibilityLabel("\(contextLabel(p.context)), \(p.date.formatted(date: .abbreviated, time: .shortened))")
                        .accessibilityValue(metric.formatted(value))
                }
            }
        }
        .chartForegroundStyleScale(domain: usedLabels, range: usedLabels.map { colors[$0] ?? .gray })
        .chartYAxisLabel(metric.unit)
        .chartLegend(position: .bottom, spacing: 12)
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

    private func recordingRow(_ recording: MovementTrendRecording, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let value = recording.availability.value {
                Text(metric.formatted(value))
                    .font(prominent ? .title2.bold() : .headline)
                    .accessibilityIdentifier(prominent ? "trendSingleValue" : "trendRecordingValue")
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
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func contextLabel(_ c: StimulationContext) -> String {
        switch c {
        case .baseline:    return L10n("Baseline")
        case .preStim:     return L10n("Before session")
        case .postStim:    return L10n("After session")
        case .unspecified: return L10n("Stimulation timing not specified")
        }
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
        func session(offset: TimeInterval, available: Bool) -> MovementSession {
            let startedAt = date.addingTimeInterval(offset)
            let trial = Trial(taskType: .fingerTap, side: .right, source: .synthetic,
                              stopCondition: .thirtySec, startedAt: startedAt,
                              samples: available ? samples : [], metrics: available ? metrics : .empty)
            return MovementSession(patientId: "UI-FIXTURE", date: startedAt,
                                   stimulationContext: .unspecified, trials: [trial])
        }
        switch scenario {
        case "empty": return []
        case "unavailable": return [session(offset: 0, available: false)]
        case "single": return [session(offset: 0, available: true)]
        case "mixed": return [session(offset: 0, available: true), session(offset: 3600, available: false)]
        case "multiple": return [session(offset: 0, available: true), session(offset: 3600, available: false),
                                 session(offset: 7200, available: true)]
        default: return nil
        }
    }()
}
#endif

#Preview {
    NavigationStack { MovementTrendView() }
}
