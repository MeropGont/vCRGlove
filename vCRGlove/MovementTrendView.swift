//
//  MovementTrendView.swift
//  vCRGlove
//
//  Context-separated daily medians with traceable recordings, not a clinical score.
//

import SwiftUI
import Charts

// MARK: - Which metric to plot

enum TrendMetric: String, CaseIterable, Identifiable {
    case frequency, amplitude, rhythm, decrement, pauses, onset, quality

    // Keep the experimental index available to legacy data/export code, not patient UI.
    static var patientCases: [Self] { allCases.filter { $0 != .quality } }
    static var plotCases: [Self] { [.frequency, .amplitude, .rhythm] }

    func plotName(task: MovementTaskType) -> String {
        if self == .frequency { return L10n(task == .fingerTap ? "Tapping rate" : "Repetition rate") }
        return self == .amplitude ? L10n("Movement size") : displayName
    }

    func plotValue(_ value: Double) -> Double { self == .rhythm ? value * 100 : value }

    func plotUnit(task: MovementTaskType) -> String {
        switch self {
        case .rhythm: return "%"
        case .amplitude: return L10n("Relative size")
        case .pauses: return L10n("count")
        case .decrement: return L10n("/cycle")
        default: return L10n(task == .fingerTap ? "Taps/second" : "Repetitions/second")
        }
    }

    func plotFormatted(_ value: Double, task: MovementTaskType) -> String {
        let locale = Locale(identifier: AppSettings.shared.language.rawValue)
        if self == .amplitude { return String(format: L10n("%.2f palm lengths"), locale: locale, value) }
        if self == .pauses {
            return String(format: value == value.rounded() ? "%.0f" : "%.1f", locale: locale, value)
        }
        if self == .decrement { return formatted(value) }
        let key = self == .rhythm ? "%.1f %%" : (task == .fingerTap ? "%.1f taps/s" : "%.1f repetitions/s")
        return String(format: L10n(key), locale: locale, plotValue(value))
    }

    var plotExplanationKey: String {
        switch self {
        case .frequency: return "How quickly you repeated the movement."
        case .amplitude: return "Average movement excursion relative to your palm length, not centimetres. Keep the same hand position and camera angle."
        case .rhythm: return "Variation in the time between repetitions. Lower values mean a more even rhythm, not a clinical rating."
        case .pauses: return "Intervals longer than twice your typical interval in this recording. This does not diagnose freezing."
        case .decrement: return "Change in movement size per repetition, relative to its average. Negative values mean size decreased during the recording."
        default: return "These values describe your recordings. They are not a clinical rating."
        }
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
    func availability(for trial: Trial, measurement: MovementTrendMeasurement? = nil) -> TrendMetricAvailability {
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
        let metrics = measurement?.metrics ?? trial.metrics
        let version = measurement?.version ?? trial.measurementVersion
        guard metrics.cycleCount >= minimumCycles else { return .insufficientCycles }
        if trial.source == .camera,
           [MovementMeasurementVersion.cameraBeforeLocalExcursions, MovementMeasurementVersion.camera]
            .contains(version ?? "") {
            let config: MovementAnalyzer.Config = version == MovementMeasurementVersion.camera
                ? .camera : .cameraGapAware
            let evidence = measurement?.evidence ?? MovementAnalyzer(config: config).analyzeWithEvidence(trial.samples)
            switch self {
            case .frequency, .amplitude:
                guard evidence.intervalCount >= 1 else { return .insufficientCycles }
            case .rhythm, .pauses, .quality:
                guard evidence.intervalCount >= 2 else { return .insufficientCycles }
            case .decrement:
                guard evidence.intervalCount >= 2, evidence.amplitudeComparisonCount >= 1 else {
                    return .insufficientCycles
                }
            case .onset: break
            }
        }
        let result = value(from: metrics)
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

/// Display projection only. Never write its recalculated values to the session store.
struct MovementTrendMeasurement {
    let metrics: MovementMetrics
    let version: String?
    let recalculated: Bool
    let evidence: MovementAnalyzer.Analysis?

    init(trial: Trial) {
        let compatibleHistory = trial.source == .camera
            && [.fingerTap, .handOpenClose].contains(trial.taskType)
            && [MovementMeasurementVersion.cameraBeforeGapAwareness,
                MovementMeasurementVersion.cameraBeforeLocalExcursions].contains(trial.measurementVersion ?? "")
        if compatibleHistory {
            let result = MovementAnalyzer(config: .camera).analyzeWithEvidence(trial.samples)
            metrics = result.metrics
            version = MovementMeasurementVersion.camera
            recalculated = true
            evidence = result
        } else {
            metrics = trial.metrics
            version = trial.measurementVersion
            recalculated = false
            evidence = nil
        }
    }
}

struct MovementTrendRecording: Identifiable {
    static let minimumTrackingSeconds: TimeInterval = 10
    private static let trackingBoundaryTolerance: TimeInterval = 0.1
    let id: String
    let date: Date
    let context: StimulationContext
    let medicationTiming: MedicationTiming?
    let availability: TrendMetricAvailability
    let segment: Int
    let duration: TimeInterval?
    let hasSignalGaps: Bool
    let trial: Trial
    let participantID: String
    let originalParticipantID: String
    let measurement: MovementTrendMeasurement

    var comparisonKey: String {
        let stop = trial.stopCondition
        let protocolKey = stop.mode == .duration ? "duration-\(stop.targetDuration)" : "reps-\(stop.targetReps)"
        return "\(participantID)/\(context.rawValue)/\(trial.source.rawValue)/\(measurement.version ?? "legacy")/\(protocolKey)"
    }

    /// Display-only evidence for older camera recordings, never saved as elapsed time.
    var inferredDuration: TimeInterval? {
        let stop = trial.stopCondition
        guard duration == nil, trial.measurementVersion == nil, trial.source == .camera,
              stop.mode == .duration, stop.targetDuration.isFinite, stop.targetDuration > 0 else { return nil }
        let signal = MovementSignalAssessment(samples: trial.samples, recordedDurationSeconds: stop.targetDuration)
        guard signal.hasAnalysisInput, !signal.hasGaps,
              let first = trial.samples.first, let last = trial.samples.last,
              abs(last.t - stop.targetDuration) <= 0.5,
              last.t - first.t >= stop.targetDuration - 0.5 else { return nil }
        return last.t
    }

    var cautionKey: String? {
        let identity = participantID.trimmingCharacters(in: .whitespacesAndNewlines)
        if identity.isEmpty || identity.lowercased() == "unset" { return "Study ID missing: shown separately." }
        let gapAwareCamera = trial.source == .camera && measurement.version == MovementMeasurementVersion.camera
        if hasSignalGaps && !gapAwareCamera { return "Signal gaps: shown separately, not joined to the trend." }
        guard let duration = duration ?? inferredDuration, duration.isFinite, duration > 0 else {
            return "Recording duration unknown: shown separately."
        }
        let stop = trial.stopCondition
        if stop.mode == .duration {
            // A usable take need not finish the timer. Allow the final camera frame's timestamp tolerance.
            guard stop.targetDuration.isFinite, stop.targetDuration > 0,
                  duration >= Self.minimumTrackingSeconds - Self.trackingBoundaryTolerance,
                  longestTrackedSegment >= Self.minimumTrackingSeconds - Self.trackingBoundaryTolerance else {
                return "Less than 10 seconds of usable tracking: shown separately."
            }
        } else if stop.targetReps <= 0 || measurement.metrics.cycleCount < stop.targetReps {
            return "Incomplete repetition test: shown separately."
        }
        return nil
    }

    private var longestTrackedSegment: TimeInterval {
        guard MovementSignalAssessment(samples: trial.samples).hasAnalysisInput else { return 0 }
        let limit = MovementAnalyzer.Config.camera.maximumSampleGap ?? 0.2
        let end = (duration ?? inferredDuration ?? 0) + Self.trackingBoundaryTolerance
        var start: TimeInterval?
        var previous: TimeInterval?
        var longest: TimeInterval = 0
        for sample in trial.samples where sample.t <= end {
            if let previous, sample.t - previous > limit { start = sample.t }
            if start == nil { start = sample.t }
            longest = max(longest, sample.t - (start ?? sample.t))
            previous = sample.t
        }
        return longest
    }

    func supportsSizeTrend(metric: TrendMetric) -> Bool {
        metric != .amplitude || (trial.source == .camera &&
            [MovementMeasurementVersion.cameraBeforeGapAwareness,
             MovementMeasurementVersion.cameraBeforeLocalExcursions, MovementMeasurementVersion.camera]
                .contains(measurement.version ?? ""))
    }
}

struct MovementTrendDay: Identifiable {
    let id: String
    let date: Date
    let recordings: [MovementTrendRecording]
    let median: Double
    let minimum: Double
    let maximum: Double
    let connects: Bool
    var seriesID: String
    var context: StimulationContext { recordings[0].context }
}

enum TrendPeriod: String, CaseIterable, Identifiable {
    case week, month, quarter, all
    var id: String { rawValue }
    var titleKey: String {
        switch self { case .week: return "7 days"; case .month: return "30 days"; case .quarter: return "90 days"; case .all: return "All dates" }
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
    static let contextChoices = StimulationContext.allCases.filter { $0 != .baseline }

    var period: TrendPeriod = .all
    var context: StimulationContext?
    var medication: TrendMedicationFilter = .all
    var minimumDoseHours = 0
    var maximumDoseHours = 24

    func includes(_ trial: Trial, context: StimulationContext, now: Date, calendar: Calendar) -> Bool {
        if let selected = self.context, selected != context { return false }
        if period != .all {
            let days = period == .week ? 7 : (period == .month ? 30 : 90)
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
    let days: [MovementTrendDay]

    init(sessions: [MovementSession], task: MovementTaskType, side: BodySide, metric: TrendMetric,
         filters: MovementTrendFilters = .init(), now: Date = Date(), calendar: Calendar = .current,
         source: SignalSource? = nil, identityLinks: MovementTrendIdentityLinks = .init()) {
        let trials = sessions.flatMap { session in
            session.trials.filter { $0.taskType == task && $0.side == side && (source == nil || $0.source == source) }
                .map { (id: "\(session.id)/\($0.id)", context: session.stimulationContext, trial: $0,
                        participantID: identityLinks.displayID(for: session, trial: $0), originalParticipantID: session.patientId) }
        }.sorted {
            if $0.trial.startedAt == $1.trial.startedAt { return $0.id < $1.id }
            return $0.trial.startedAt < $1.trial.startedAt
        }
        unfilteredCount = trials.count
        var segment = 0
        recordings = trials.filter { filters.includes($0.trial, context: $0.context, now: now, calendar: calendar) }.map { item in
            let measurement = MovementTrendMeasurement(trial: item.trial)
            let rawAvailability = metric.availability(for: item.trial, measurement: measurement)
            let availability = rawAvailability.value.map { metric.plotValue($0).isFinite } == false
                ? TrendMetricAvailability.invalidValue : rawAvailability
            if availability.value == nil { segment += 1 }
            return MovementTrendRecording(id: item.id, date: item.trial.startedAt,
                                          context: item.context, medicationTiming: item.trial.medicationTiming?.forRecording(at: item.trial.startedAt, calendar: calendar),
                                          availability: availability, segment: segment,
                                          duration: item.trial.recordedDurationSeconds,
                                          hasSignalGaps: MovementSignalAssessment(samples: item.trial.samples,
                                              recordedDurationSeconds: item.trial.recordedDurationSeconds).hasGaps,
                                          trial: item.trial, participantID: item.participantID,
                                          originalParticipantID: item.originalParticipantID, measurement: measurement)
        }
        // Filter first; summarize only within a matching context, acquisition
        // version and protocol. Usable early-stopped takes contribute normally.
        let usable = recordings.filter { $0.availability.value != nil && $0.supportsSizeTrend(metric: metric) }
        let grouped = Dictionary(grouping: usable) { recording in
            let day = calendar.startOfDay(for: recording.date).timeIntervalSince1970
            return "\(day)/\(recording.comparisonKey)/\(recording.cautionKey == nil ? "complete" : recording.id)"
        }
        var summaries: [MovementTrendDay] = []
        for (key, group) in grouped {
            let records = group.sorted { $0.id < $1.id }
            let values: [Double] = records.compactMap { $0.availability.value }.sorted()
            let middle = values.count / 2
            let median = values.count.isMultiple(of: 2) ? values[middle - 1] / 2 + values[middle] / 2 : values[middle]
            let connects = records[0].cautionKey == nil && StimulationContext.patientChoices.contains(records[0].context)
            let summary = MovementTrendDay(id: key, date: calendar.startOfDay(for: records[0].date), recordings: records,
                                          median: median, minimum: values[0], maximum: values[values.count - 1],
                                          connects: connects, seriesID: records[0].comparisonKey)
            summaries.append(summary)
        }
        summaries.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        var previousDay: [String: Date] = [:]
        var segments: [String: Int] = [:]
        let barriers = Dictionary(grouping: recordings.filter { $0.availability.value == nil || $0.cautionKey != nil }, by: \.comparisonKey)
        for index in summaries.indices where summaries[index].connects {
            let key = summaries[index].seriesID
            let day = summaries[index].date
            if let previous = previousDay[key], barriers[key, default: []].contains(where: {
                let missingDay = calendar.startOfDay(for: $0.date)
                return missingDay > previous && missingDay < day
            }) { segments[key, default: 0] += 1 }
            previousDay[key] = day
            summaries[index].seriesID = "\(key)/segment-\(segments[key, default: 0])"
        }
        days = summaries
    }

    var points: [MovementTrendRecording] { recordings.filter { $0.availability.value != nil } }
    /// Filters/task/hand are already applied; metric availability does not gate this independent measure.
    var latestStudyComparisonTrial: Trial? {
        recordings.reversed().first(where: { $0.trial.displayedFirstTenTappingRate != nil })?.trial
    }

    var unavailableCount: Int { recordings.count - points.count }
    var canShowTrend: Bool {
        Dictionary(grouping: days.filter(\.connects), by: \.seriesID).values.contains { $0.count >= 2 }
    }
    var hasStandalonePoints: Bool {
        let counts = Dictionary(grouping: days.filter(\.connects), by: \.seriesID).mapValues(\.count)
        return days.contains { !$0.connects || counts[$0.seriesID, default: 0] < 2 }
    }

    var noTrendExplanationKey: String? {
        guard !days.isEmpty, !canShowTrend else { return nil }
        let complete = days.filter(\.connects)
        if complete.isEmpty {
            if days.allSatisfy({ $0.recordings[0].cautionKey != nil }) {
                return "Incomplete capture or unknown duration keeps these points separate."
            }
            return "Recordings with unspecified or historical stimulation timing stay separate."
        }
        if Set(complete.map(\.date)).count < 2 {
            return Set(days.map(\.date)).count > 1
                ? "Only one day has comparable complete recordings. Other points remain separate."
                : "A line needs matching recordings on at least two different days."
        }
        let recordings = complete.flatMap(\.recordings)
        if Set(recordings.map(\.participantID)).count > 1 {
            return "Recordings with different study IDs are kept separate."
        }
        if Set(recordings.map { $0.measurement.version ?? "legacy" }).count > 1 {
            return "Earlier and current measurement methods are kept separate."
        }
        if Set(recordings.map(\.context)).count > 1 {
            return "Each stimulation timing needs matching recordings on at least two days."
        }
        if Set(recordings.map(\.comparisonKey)).count > 1 {
            return "Different test protocols or recording sources are kept separate."
        }
        return "An intervening day with incomplete capture separates these trend segments."
    }

    func nearestDay(to date: Date) -> Date? {
        days.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }?.date
    }

    func separationReason(for recording: MovementTrendRecording) -> String? {
        if recording.availability.value == nil { return recording.availability.explanationKey }
        if let caution = recording.cautionKey { return caution }
        guard StimulationContext.patientChoices.contains(recording.context) else {
            return "Recordings with unspecified or historical stimulation timing stay separate."
        }
        guard let day = days.first(where: { $0.recordings.contains(where: { $0.id == recording.id }) }) else {
            return "Older size measurement: different scale, not used in the size trend."
        }
        if days.filter({ $0.connects && $0.seriesID == day.seriesID }).count >= 2 { return nil }
        let peers = days.filter(\.connects).flatMap(\.recordings)
        if days.filter({ $0.connects && $0.recordings[0].comparisonKey == recording.comparisonKey }).count >= 2 {
            return "An intervening day with incomplete capture separates these trend segments."
        }
        if peers.contains(where: { $0.participantID == recording.participantID
            && $0.context == recording.context && $0.measurement.version != recording.measurement.version }) {
            return "Earlier and current measurement methods are kept separate."
        }
        if peers.contains(where: { $0.participantID != recording.participantID }) {
            return "Recordings with different study IDs are kept separate."
        }
        if peers.contains(where: { $0.trial.source != recording.trial.source || $0.trial.stopCondition != recording.trial.stopCondition }) {
            return "Different test protocols or recording sources are kept separate."
        }
        return "Each stimulation timing needs matching recordings on at least two days."
    }

    var separationExplanationKeys: [String] {
        var keys: [String] = []
        for recording in recordings {
            if let reason = separationReason(for: recording), !keys.contains(reason) { keys.append(reason) }
        }
        return keys
    }

    func nearest(to date: Date) -> MovementTrendRecording? {
        points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

// MARK: - Trend view

enum MovementProfileMetric: String, CaseIterable, Identifiable {
    case rate, rhythm, size, angularSpeed
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .rate: return "Repetition rate"
        case .rhythm: return "Rhythm variability"
        case .size: return "Movement size"
        case .angularSpeed: return "Finger movement speed"
        }
    }
    func value(_ recording: MovementTrendRecording) -> Double? {
        if self == .angularSpeed {
            guard let angles = recording.trial.displayedFingerTappingAngleMetrics, angles.intervalCount >= 2 else { return nil }
            return angles.meanAbsoluteAngularSpeedDegreesPerSecond
                .flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        let metric: TrendMetric = self == .rate ? .frequency : self == .rhythm ? .rhythm : .amplitude
        guard recording.supportsSizeTrend(metric: metric) else { return nil }
        return metric.availability(for: recording.trial, measurement: recording.measurement).value
    }
    func formatted(_ value: Double, task: MovementTaskType) -> String {
        if self == .angularSpeed {
            return String(format: "%.0f °/s", locale: Locale(identifier: AppSettings.shared.language.rawValue), value)
        }
        return (self == .rate ? TrendMetric.frequency : self == .rhythm ? .rhythm : .amplitude)
            .plotFormatted(value, task: task)
    }
}

enum MovementComparisonWindow: String, CaseIterable, Identifiable {
    case previousDay, recent, month, quarter, sevenMonths, all
    var id: String { rawValue }
    var titleKey: String {
        switch self {
        case .previousDay: return "Previous recording day"
        case .recent: return "Recent 7 recording days"
        case .month: return "Past month"
        case .quarter: return "Past 3 months"
        case .sevenMonths: return "Past 7 months"
        case .all: return "Whole study"
        }
    }
    func dates(from dates: [Date], before latestDay: Date, calendar: Calendar) -> [Date] {
        let earlier = dates.filter { $0 < latestDay }.sorted()
        switch self {
        case .previousDay: return Array(earlier.suffix(1))
        case .recent: return Array(earlier.suffix(7))
        case .all: return earlier
        case .month, .quarter, .sevenMonths:
            let months = self == .month ? 1 : self == .quarter ? 3 : 7
            guard let start = calendar.date(byAdding: .month, value: -months, to: latestDay) else { return [] }
            return earlier.filter { $0 >= start }
        }
    }
}

struct MovementPersonalProfile {
    struct Entry: Identifiable {
        let metric: MovementProfileMetric
        let latest: Double?
        let typical: Double?
        let previousDays: Int
        var id: String { metric.id }
    }
    let recording: MovementTrendRecording?
    let entries: [Entry]

    init(recordings: [MovementTrendRecording], task: MovementTaskType, calendar: Calendar = .current,
         window: MovementComparisonWindow = .recent) {
        let metrics: [MovementProfileMetric] = task == .fingerTap ? [.rate, .rhythm, .size, .angularSpeed]
            : task == .handOpenClose ? [.rate, .rhythm, .size] : [.rate, .rhythm]
        let latest = recordings.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }.reversed().first { item in
            metrics.contains { $0.value(item) != nil }
        }
        recording = latest
        guard let latest else { entries = []; return }
        let today = calendar.startOfDay(for: latest.date)
        // Use daily medians so repeatedly recording on one day cannot dominate.
        // Medication status is matched; elapsed-dose filters remain user controlled.
        let comparable = latest.cautionKey == nil && StimulationContext.patientChoices.contains(latest.context)
        let previous = recordings.filter {
            comparable && $0.comparisonKey == latest.comparisonKey && $0.cautionKey == nil
                && $0.medicationTiming?.status == latest.medicationTiming?.status
                && calendar.startOfDay(for: $0.date) < today
        }
        func median(_ values: [Double]) -> Double {
            let sorted = values.sorted(), middle = values.count/2
            return values.count.isMultiple(of: 2) ? sorted[middle-1]/2 + sorted[middle]/2 : sorted[middle]
        }
        let priorDays = Dictionary(grouping: previous, by: { calendar.startOfDay(for: $0.date) })
        let dates = window.dates(from: Array(priorDays.keys), before: today, calendar: calendar)
        entries = metrics.filter { $0 != .angularSpeed || latest.trial.fingerTappingAngle != nil }.map { metric in
            let values = dates.compactMap { date -> Double? in
                let day = priorDays[date]!.compactMap { metric.value($0) }
                return day.isEmpty ? nil : median(day)
            }
            return Entry(metric: metric, latest: metric.value(latest),
                         typical: values.isEmpty ? nil : median(values), previousDays: values.count)
        }
    }
}

struct MovementTrendView: View {
    @ObservedObject private var store = TaskSessionStore.shared
    @AppStorage("movementTrendIdentityLinks") private var identityLinksData = Data()
    @AppStorage("movementPersonalComparisonWindow") private var comparisonWindow: MovementComparisonWindow = .recent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var taskType: MovementTaskType = .fingerTap
    @State private var side: BodySide = .right
    @State private var metric: TrendMetric = .frequency
    @State private var filters = MovementTrendFilters()
    @State private var historyLimit = 50
    @State private var selectedDate: Date?
    @State private var showingMetricInfo = false
    @State private var showingSeparationInfo = false
    @State private var showingProfileInfo = false
    private var isDetail = false

    init(task: MovementTaskType = .fingerTap, side: BodySide = .right,
         metric: TrendMetric = .frequency, filters: MovementTrendFilters = .init(), isDetail: Bool = false) {
        _taskType = State(initialValue: task)
        _side = State(initialValue: side)
        _metric = State(initialValue: metric)
        _filters = State(initialValue: filters)
        self.isDetail = isDetail
    }

    private var summary: MovementTrendSummary {
        makeSummary(filters: filters)
    }

    private func makeSummary(filters: MovementTrendFilters) -> MovementTrendSummary {
        var sessions = store.sessions
        var source: SignalSource? = taskType.preferredSource
        #if DEBUG && targetEnvironment(simulator)
        // UI fixtures never write to the session store or enter device/Release builds.
        if let fixtures = MovementTrendFixtures.sessions { sessions = fixtures; source = nil }
        if ProcessInfo.processInfo.arguments.contains("--ui-test-session-save") { source = nil }
        #endif
        return MovementTrendSummary(sessions: sessions, task: taskType, side: side, metric: metric,
                                    filters: filters, source: source,
                                    identityLinks: MovementTrendIdentityLinks(data: identityLinksData))
    }

    var body: some View {
        let summary = self.summary
        let profile = makeProfile(summary: summary)
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
                } else if summary.days.isEmpty {
                    let needsNewSize = metric == .amplitude && !summary.recordings.contains {
                        $0.supportsSizeTrend(metric: .amplitude)
                    }
                    resultMessage(
                        title: L10n(needsNewSize ? "Size trend not available yet" : "Not enough movement data"),
                        detail: L10n(needsNewSize
                            ? "Size trends use new camera recordings. Older values remain in recording history."
                            : "This metric could not be calculated from your saved recordings.")
                    )
                    .accessibilityIdentifier("trendUnavailable")
                } else {
                    chart(summary: summary, profile: profile)
                        .frame(minHeight: 260)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("movementTrendChart")
                    legend(summary: summary)
                    if let explanation = summary.noTrendExplanationKey {
                        Text(L10n(explanation))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("trendSingleMeasurement")
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: L10n("%@ over time"), metric.plotName(task: taskType)))
                    Spacer(minLength: 8)
                    Button { showingMetricInfo = true } label: {
                        Image(systemName: "info.circle").font(.body).frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n("About this metric"))
                    .help(L10n("About this metric"))
                    .accessibilityIdentifier("trendMetricInfo")
                }
            } footer: {
                if !summary.days.isEmpty {
                    Text(L10n("Not a clinical score."))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let selectedDate, let day = summary.nearestDay(to: selectedDate) {
                Section {
                    ForEach(summary.days.filter { $0.date == day }) { point in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(contextLabel(point.context)).font(.subheadline).foregroundStyle(.secondary)
                            Text(metric.plotFormatted(point.median, task: taskType)).font(.headline)
                            Text(String(format: L10n("Daily median · %d recording(s)"), point.recordings.count))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if point.recordings.count > 1 {
                                Text(String(format: L10n("Range: %@ to %@"),
                                            metric.plotFormatted(point.minimum, task: taskType),
                                            metric.plotFormatted(point.maximum, task: taskType)))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(protocolLabel(point.recordings[0])).font(.caption).foregroundStyle(.secondary)
                            if let caution = point.recordings[0].cautionKey {
                                Text(L10n(caution)).font(.caption).foregroundStyle(.secondary)
                            }
                            if point.recordings.contains(where: { $0.inferredDuration != nil }) {
                                Text(L10n("Earlier durations estimated from signal timestamps."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let reason = summary.separationReason(for: point.recordings[0]) {
                                Text(L10n(reason)).font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("trendPointReason")
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    NavigationLink {
                        List {
                            ForEach(summary.recordings.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reversed()) {
                                recordingRow($0, reason: summary.separationReason(for: $0))
                            }
                        }
                        .navigationTitle(L10n("Recordings on this day"))
                    } label: { Label(L10n("Recordings on this day"), systemImage: "list.bullet") }
                    .accessibilityIdentifier("trendDayRecordings")
                } header: {
                    Text(day, format: .dateTime.day().month().year())
                        .accessibilityIdentifier("trendDaySummary")
                }
            }
            Section(L10n("Filters")) {
                Picker(L10n("Period"), selection: $filters.period) {
                    ForEach(TrendPeriod.allCases) { Text(L10n($0.titleKey)).tag($0) }
                }
                .accessibilityIdentifier("trendPeriodFilter")
                Menu {
                    Button(L10n("All stimulation timings")) { filters.context = nil }
                    ForEach(MovementTrendFilters.contextChoices) { context in
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
            if !isDetail {
                personalProfile(profile)
                if taskType == .fingerTap {
                    Section {
                        NavigationLink {
                            MovementResearchComparisonView(trial: summary.latestStudyComparisonTrial)
                        } label: {
                            Label(L10n("Compare with research recordings"), systemImage: "chart.bar.xaxis")
                        }
                        .accessibilityIdentifier("trendResearchComparison")
                    }
                }
                Section {
                    DisclosureGroup(L10n("More details")) {
                        ForEach(taskType == .pronationSupination ? [TrendMetric.pauses] : [.pauses, .decrement]) { detail in
                            NavigationLink(detail.displayName) {
                                MovementTrendView(task: taskType, side: side, metric: detail, filters: filters, isDetail: true)
                            }
                        }
                    }
                    .accessibilityIdentifier("trendMoreDetails")
                }
            }
            if !summary.recordings.isEmpty {
                Section {
                    NavigationLink {
                        List {
                            ForEach(Array(summary.recordings.suffix(historyLimit).reversed())) { recording in
                                recordingRow(recording, reason: summary.separationReason(for: recording))
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
        .navigationTitle(isDetail ? metric.displayName : L10n("Trends"))
        .sheet(isPresented: $showingProfileInfo) {
            NavigationStack {
                Form {
                    Text(L10n("Rate counts repetitions per second. Rhythm variability describes how evenly they repeat: lower values mean more even intervals. Movement size describes how widely you moved, relative to your palm."))
                    if taskType == .fingerTap {
                        Text(L10n("Finger movement speed describes how quickly the camera-view finger angle changes. It is different from tapping rate and is affected by hand position and tracking."))
                    }
                    Text(L10n("Your comparison uses daily medians within the selected comparison window. Whole study includes all earlier matching days, independently of the chart period. Other filters apply; each recording day has equal weight."))
                    Text(L10n("These measures help describe your movement pattern. Faster or larger does not automatically mean better, and small differences may reflect normal recording variation."))
                }
                .navigationTitle(L10n("Your movement pattern"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n("Done")) { showingProfileInfo = false }
                            .accessibilityIdentifier("trendProfileInfoDone")
                    }
                }
            }
        }
        .sheet(isPresented: $showingMetricInfo) {
            NavigationStack {
                Form {
                    Section {
                        Text(L10n(metric.plotExplanationKey))
                            .accessibilityIdentifier("trendMetricExplanation")
                        Text(L10n("Daily medians. Lines join matching recordings on measured days, not changes between them."))
                        Text(L10n("Separate points may have a different protocol or method, incomplete capture, or unknown context."))
                        Text(L10n("These values describe your recordings. They are not a clinical rating."))
                    }
                    Section {
                        if summary.recordings.contains(where: { $0.cautionKey != nil }) {
                            Text(L10n("Faded points: some recordings cannot be compared directly."))
                        }
                        if summary.unavailableCount > 0 {
                            Text(String(format: L10n("Results unavailable for this metric: %d"), summary.unavailableCount))
                        }
                        if summary.recordings.contains(where: { $0.measurement.recalculated }) {
                            Text(L10n("Earlier recordings reanalysed for this trend."))
                                .accessibilityIdentifier("trendReanalysisNote")
                        }
                        if summary.recordings.contains(where: { $0.inferredDuration != nil }) {
                            Text(L10n("Earlier durations estimated from signal timestamps."))
                                .accessibilityIdentifier("trendEstimatedDurations")
                        }
                    }
                }
                .navigationTitle(metric.plotName(task: taskType))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n("Done")) { showingMetricInfo = false }
                            .accessibilityIdentifier("trendMetricInfoDone")
                    }
                }
            }
        }
        .sheet(isPresented: $showingSeparationInfo) {
            NavigationStack {
                List {
                    ForEach(summary.separationExplanationKeys, id: \.self) { key in
                        Text(L10n(key)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .navigationTitle(L10n("Separate points"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n("Done")) { showingSeparationInfo = false }
                            .accessibilityIdentifier("trendSeparationDone")
                    }
                }
            }
        }
        .onChange(of: filters) { _, _ in selectedDate = nil }
        .onChange(of: side) { _, _ in selectedDate = nil }
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .onChange(of: taskType) { _, task in
            selectedDate = nil
            if !visibleMetrics.contains(metric) { metric = visibleMetrics[0] }
        }
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
            ForEach(visibleMetrics) { metric in
                Text(metric.plotName(task: taskType)).tag(metric)
            }
        }
    }

    private func personalProfile(_ profile: MovementPersonalProfile) -> some View {
        return Section {
            Menu {
                ForEach(MovementComparisonWindow.allCases) { window in
                    Button { comparisonWindow = window } label: {
                        if window == comparisonWindow {
                            Label(L10n(window.titleKey), systemImage: "checkmark")
                        } else { Text(L10n(window.titleKey)) }
                    }
                }
            } label: {
                selectionLabel(title: L10n("Comparison window"), value: L10n(comparisonWindow.titleKey))
            }
            .accessibilityIdentifier("trendComparisonWindow")
            .accessibilityValue(L10n(comparisonWindow.titleKey))
            if let recording = profile.recording {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Latest matching recording")).foregroundStyle(.secondary)
                    Text(recording.date, format: .dateTime.day().month().year().hour().minute())
                }
                .accessibilityIdentifier("trendProfileDate")
                ForEach(profile.entries) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.metric == .rate ? TrendMetric.frequency.plotName(task: taskType) : L10n(entry.metric.titleKey))
                            .font(.headline)
                        Text(entry.latest.map { entry.metric.formatted($0, task: taskType) } ?? L10n("Value unavailable"))
                            .accessibilityIdentifier("trendProfileValue-\(entry.id)")
                        if let typical = entry.typical {
                            Text(String(format: L10n("Your typical: %@ · %d earlier day(s)"),
                                        entry.metric.formatted(typical, task: taskType), entry.previousDays))
                                .font(.subheadline).foregroundStyle(.secondary)
                                .accessibilityIdentifier("trendProfileTypical-\(entry.id)")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                if profile.entries.allSatisfy({ $0.typical == nil }) {
                    Text(L10n("As you record on more days under similar conditions, your personal comparison will appear here."))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L10n("Your movement pattern will appear after a usable recording."))
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            HStack {
                Text(L10n("Your movement pattern"))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Spacer()
                Button { showingProfileInfo = true } label: {
                    Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n("About your movement pattern"))
                .accessibilityIdentifier("trendProfileInfo")
            }
        }
    }

    private func makeProfile(summary: MovementTrendSummary) -> MovementPersonalProfile {
        guard let latestDate = summary.recordings.map(\.date).max() else {
            return MovementPersonalProfile(recordings: [], task: taskType, window: comparisonWindow)
        }
        var comparisonFilters = filters
        comparisonFilters.period = .all
        let records = filters.period == .all ? summary.recordings : makeSummary(filters: comparisonFilters).recordings
        return MovementPersonalProfile(recordings: records.filter { $0.date <= latestDate },
            task: taskType, window: comparisonWindow)
    }

    private var visibleMetrics: [TrendMetric] {
        if isDetail { return taskType == .pronationSupination ? [.pauses] : [.pauses, .decrement] }
        return TrendMetric.plotCases.filter { taskType != .pronationSupination || $0 != .amplitude }
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

    private func chart(summary: MovementTrendSummary, profile: MovementPersonalProfile) -> some View {
        let first = summary.days.first!.date
        let last = summary.days.last!.date
        let padding = max(43200, last.timeIntervalSince(first) * 0.05)
        let values = summary.days.map { metric.plotValue($0.median) }
        let maximum = values.max() ?? 0
        let minimum = values.min() ?? 0
        let lower = min(0, minimum < -Double.greatestFiniteMagnitude / 1.15 ? minimum : minimum * 1.15)
        let upper = max(metric == .decrement ? 0.01 : 1,
                        maximum > Double.greatestFiniteMagnitude / 1.15 ? maximum : maximum * 1.15)
        let typical = profile.recording.flatMap { latest -> Double? in
            guard summary.days.allSatisfy({ $0.connects && $0.recordings[0].comparisonKey == latest.comparisonKey }) else { return nil }
            let dimension: MovementProfileMetric?
            switch metric {
            case .frequency: dimension = .rate
            case .rhythm: dimension = .rhythm
            case .amplitude: dimension = .size
            default: dimension = nil
            }
            return profile.entries.first { $0.metric == dimension }?.typical
        }
        return Chart {
            if let typical {
                RuleMark(y: .value(L10n("Your recent typical"), metric.plotValue(typical)))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text(L10n("Your recent typical")).font(.caption)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                    .accessibilityHidden(true)
            }
            ForEach(summary.days) { point in
                if point.connects {
                    LineMark(x: .value(L10n("Date"), point.date),
                             y: .value(metric.plotName(task: taskType), metric.plotValue(point.median)),
                             series: .value("Series", point.seriesID))
                        .foregroundStyle(contextColor(point.context))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: contextDash(point.context)))
                        .interpolationMethod(.linear)
                        .accessibilityHidden(true)
                }
                PointMark(x: .value(L10n("Date"), point.date),
                          y: .value(metric.plotName(task: taskType), metric.plotValue(point.median)))
                    .foregroundStyle(contextColor(point.context).opacity(point.recordings[0].cautionKey == nil ? 1 : 0.5))
                    .symbol(contextSymbol(point.context))
                    .symbolSize(60)
                    .accessibilityLabel("\(contextLabel(point.context)), \(point.date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(Locale(identifier: AppSettings.shared.language.rawValue)))), \(L10n("Daily median")), \(protocolLabel(point.recordings[0]))")
                    .accessibilityValue(metric.plotFormatted(point.median, task: taskType))
            }
            if let selectedDate, let day = summary.nearestDay(to: selectedDate) {
                RuleMark(x: .value(L10n("Date"), day)).foregroundStyle(.secondary.opacity(0.35))
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: first.addingTimeInterval(-padding)...last.addingTimeInterval(padding))
        .chartYScale(domain: lower...upper)
        .chartXAxis { AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) }
        .chartYAxisLabel(metric.plotUnit(task: taskType))
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        if let frame = proxy.plotFrame {
                            let rect = geometry[frame]
                            guard rect.contains(location) else { return }
                            let date: Date? = proxy.value(atX: location.x - rect.minX)
                            selectedDate = date.flatMap { summary.nearestDay(to: $0) }
                        }
                    }
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAction(named: Text(L10n("Latest day"))) { selectedDate = summary.days.last?.date }
    }

    private func contextColor(_ context: StimulationContext) -> Color {
        switch context {
        case .preStim: return .blue
        case .postStim: return .orange
        case .noStimPlanned: return .teal
        default: return .secondary
        }
    }

    private func contextSymbol(_ context: StimulationContext) -> BasicChartSymbolShape {
        switch context {
        case .preStim: return .circle
        case .postStim: return .diamond
        case .noStimPlanned: return .square
        default: return .cross
        }
    }

    private func contextDash(_ context: StimulationContext) -> [CGFloat] {
        switch context { case .postStim: return [6, 3]; case .noStimPlanned: return [2, 3]; default: return [] }
    }

    private func legend(summary: MovementTrendSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(StimulationContext.allCases.filter { context in summary.days.contains { $0.context == context } }) { context in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: context == .preStim ? "circle.fill" : context == .postStim ? "diamond.fill"
                          : context == .noStimPlanned ? "square.fill" : "xmark")
                        .foregroundStyle(contextColor(context)).font(.caption).accessibilityHidden(true)
                    Text(contextLabel(context)).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
            }
            if summary.hasStandalonePoints {
                Button { showingSeparationInfo = true } label: {
                    Label(L10n("Why some points are separate"), systemImage: "info.circle")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("trendSeparationInfo")
            }
        }
    }

    private func protocolLabel(_ recording: MovementTrendRecording) -> String {
        let stop = recording.trial.stopCondition
        let protocolName = stop.mode == .duration
            ? String(format: L10n("%.0f-second test"), stop.targetDuration)
            : String(format: L10n("%d-repetition test"), stop.targetReps)
        let current = [MovementMeasurementVersion.camera, MovementMeasurementVersion.watch]
            .contains(recording.measurement.version ?? "")
        return protocolName + " · " + L10n(current ? "Current measurement method" : "Earlier or different measurement method")
            + " · " + recording.participantID
            + (recording.participantID == recording.originalParticipantID ? "" : " · " + L10n("Earlier test linked for display only"))
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

    private func recordingRow(_ recording: MovementTrendRecording, reason: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let value = recording.availability.value {
                Text(metric == .amplitude && !recording.supportsSizeTrend(metric: metric)
                     ? metric.formatted(value) : metric.plotFormatted(value, task: taskType))
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
            Text(protocolLabel(recording)).font(.caption).foregroundStyle(.secondary)
            if recording.measurement.recalculated {
                Text(L10n("Updated analysis for this trend. Original values are unchanged."))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("trendRecordingReanalysis")
            }
            if metric == .amplitude && !recording.supportsSizeTrend(metric: metric) {
                Text(L10n("Older size measurement: different scale, not used in the size trend."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let timing = recording.medicationTiming {
                MovementMedicationSummary(timing: timing, recordedAt: recording.date)
            } else {
                Text(L10n("Medication timing unknown")).font(.subheadline).foregroundStyle(.secondary)
            }
            if let duration = recording.duration, duration.isFinite, duration >= 0 {
                Text(String(format: L10n("Recorded: %.1f seconds"), locale: Locale(identifier: AppSettings.shared.language.rawValue), duration))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if let duration = recording.inferredDuration {
                Text(String(format: L10n("Approx. %.1f seconds (estimated from signal)"),
                            locale: Locale(identifier: AppSettings.shared.language.rawValue), duration))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("trendInferredDuration")
            }
            if let reason {
                Text(L10n(reason))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("trendRecordingReason")
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
        let samples = (0..<300).map { TimestampedSample(t: Double($0) / 10, value: sin(Double($0)) + 1) }
        let metrics = MovementMetrics(cycleCount: 10, frequencyHz: 2, meanAmplitude: 0.3,
                                      amplitudeDecrementSlope: 0, rhythmCV: 0.1, pauseCount: 0,
                                      onsetLatencySec: 0, qualityIndex: 0.8)
        func session(offset: TimeInterval, available: Bool, context: StimulationContext = .unspecified,
                     medication: MedicationTiming? = nil) -> MovementSession {
            let startedAt = date.addingTimeInterval(offset)
            let trial = Trial(taskType: .fingerTap, side: .right, source: .synthetic,
                              stopCondition: .thirtySec, startedAt: startedAt,
                              samples: available ? samples : [], metrics: available ? metrics : .empty,
                              medicationTiming: medication, recordedDurationSeconds: 30)
            return MovementSession(patientId: "UI-FIXTURE", date: startedAt,
                                   stimulationContext: context, trials: [trial])
        }
        switch scenario {
        case "study-comparison":
            return (0...3).flatMap { day in BodySide.allCases.map { hand in
                let rate = hand == .left ? 2.0 : 3.0
                let angles = FingerTappingAngleRecording(samples: (0..<600).map {
                    let time = Double($0)/60
                    return TimestampedAngleSample(t: time, degrees: 20-20*cos(2 * .pi * rate * time))
                })
                var values = metrics
                values.frequencyHz = rate
                let trial = Trial(taskType: .fingerTap, side: hand, source: .camera,
                                  stopCondition: .thirtySec, startedAt: date.addingTimeInterval(Double(day-3)*86400),
                                  samples: samples, metrics: values, recordedDurationSeconds: 30,
                                  fingerTappingAngle: angles)
                return MovementSession(patientId: "UI-FIXTURE", stimulationContext: .preStim, trials: [trial])
            } }
        case "empty": return []
        case "unavailable": return [session(offset: 0, available: false)]
        case "single": return [session(offset: 0, available: true)]
        case "mixed": return [session(offset: 0, available: true), session(offset: 3600, available: false)]
        case "multiple": return [session(offset: 0, available: true, context: .preStim),
                                 session(offset: 86400, available: true, context: .preStim),
                                 session(offset: 172800, available: false, context: .preStim)]
        case "consistent-analysis":
            let versions: [String?] = [MovementMeasurementVersion.cameraBeforeGapAwareness,
                MovementMeasurementVersion.cameraBeforeLocalExcursions, MovementMeasurementVersion.camera, nil]
            var records = versions.enumerated().map { index, version in
                let current = version == MovementMeasurementVersion.camera
                let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                                  startedAt: date.addingTimeInterval(Double(index) * 86400), samples: samples,
                                  metrics: MovementAnalyzer(config: current ? .camera : .cameraGapAware).analyze(samples),
                                  recordedDurationSeconds: 30, measurementVersion: version)
                return MovementSession(patientId: "UI-FIXTURE", stimulationContext: .preStim, trials: [trial])
            }
            let other = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                              startedAt: date.addingTimeInterval(4 * 86400), samples: samples,
                              metrics: MovementAnalyzer(config: .camera).analyze(samples),
                              recordedDurationSeconds: 30, measurementVersion: MovementMeasurementVersion.camera)
            records.append(MovementSession(patientId: "UI-OTHER", stimulationContext: .preStim, trials: [other]))
            return records
        case "legacy-duration", "split-method":
            let legacySamples = (0...900).map {
                TimestampedSample(t: 0.02 + Double($0) / 30, value: sin(Double($0)) + 1)
            }
            let legacy = (0..<(scenario == "legacy-duration" ? 2 : 1)).map { day in
                let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                                  startedAt: date.addingTimeInterval(Double(day) * 86400),
                                  samples: legacySamples, metrics: metrics)
                return MovementSession(patientId: "UI-FIXTURE", stimulationContext: .preStim, trials: [trial])
            }
            let current = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                                startedAt: date.addingTimeInterval(2 * 86400), samples: samples, metrics: metrics,
                                recordedDurationSeconds: 30, measurementVersion: MovementMeasurementVersion.camera)
            return legacy + [MovementSession(patientId: "UI-FIXTURE", stimulationContext: .preStim, trials: [current])]
        case "daily":
            func current(_ offset: TimeInterval, _ rate: Double, context: StimulationContext = .preStim,
                         duration: Double = 30, version: String? = MovementMeasurementVersion.camera) -> MovementSession {
                var values = metrics
                values.frequencyHz = rate
                values.meanAmplitude = rate / 5
                let trial = Trial(taskType: .fingerTap, side: .right, source: .camera, stopCondition: .thirtySec,
                                  startedAt: date.addingTimeInterval(offset),
                                  samples: samples.filter { $0.t < duration }, metrics: values,
                                  recordedDurationSeconds: duration, measurementVersion: version)
                return MovementSession(patientId: "UI-FIXTURE", stimulationContext: context, trials: [trial])
            }
            return [current(0, 2), current(1800, 4), current(86400, 3.2), current(172800, 3.4),
                    current(0, 3.5, context: .postStim), current(86400, 3.7, context: .postStim),
                    current(172800, 3.8, context: .postStim), current(86400, 2.5, context: .noStimPlanned),
                    current(172800, 2.8, context: .noStimPlanned), current(86400, 1, context: .unspecified),
                    current(172800, 1.5, duration: 5), current(259200, 2, version: nil)]
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
