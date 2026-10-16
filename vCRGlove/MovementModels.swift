//
//  MovementModels.swift
//  vCRGlove
//
//  Data models for the MDS-UPDRS-inspired movement task module.
//  Sensor-independent: a Trial holds a 1-D signal (`[TimestampedSample]`)
//  regardless of whether it came from the camera (Vision) or the Watch (CoreMotion).
//
//  These models are also the JSON payload the app uploads to the UKE backend.
//  See BACKEND_INTEGRATION.md for the full API contract.
//

import Foundation

// MARK: - Task definition

/// The three upper-limb bradykinesia items we evaluate.
/// Raw values map to MDS-UPDRS-III item numbers for easy export/reference.
enum MovementTaskType: String, CaseIterable, Codable, Identifiable {
    case fingerTap          = "3.4"   // Finger tapping (thumb–index distance)
    case handOpenClose      = "3.5"   // Hand opening/closing
    case pronationSupination = "3.6"  // Forearm pronation/supination

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fingerTap:           return L10n("Finger Tapping")
        case .handOpenClose:       return L10n("Hand Open/Close")
        case .pronationSupination: return L10n("Pronation/Supination")
        }
    }

    /// Which sensor is the primary source for this task.
    var preferredSource: SignalSource {
        switch self {
        case .fingerTap, .handOpenClose: return .camera
        case .pronationSupination:       return .watchMotion
        }
    }
}

enum SignalSource: String, Codable {
    case camera        // iPhone camera + Vision hand pose
    case watchMotion   // Apple Watch CoreMotion (rotationRate for 3.6)
    case synthetic     // generated test data (Simulator, no hardware)
}

enum BodySide: String, CaseIterable, Codable, Identifiable {
    case left, right
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .left:  return L10n("Left")
        case .right: return L10n("Right")
        }
    }
}

/// Relation of a recording to the vCR stimulation, for pre/post comparisons.
enum StimulationContext: String, CaseIterable, Codable, Identifiable {
    case baseline      // historical category; never reinterpret as no stimulation planned
    case preStim
    case postStim
    case noStimPlanned
    case unspecified
    var id: String { rawValue }

    static let patientChoices: [Self] = [.preStim, .postStim, .noStimPlanned]

    var titleKey: String {
        switch self {
        case .baseline: return "Baseline (older recording)"
        case .preStim: return "Before stimulation"
        case .postStim: return "After stimulation"
        case .noStimPlanned: return "No stimulation planned today"
        case .unspecified: return "Stimulation timing not specified"
        }
    }
}

// MARK: - Optional, patient-confirmed medication context

struct MedicationTiming: Codable, Equatable {
    enum Status: String, Codable { case takenAt, noneToday, unsure }

    let status: Status
    let takenAt: Date?
    let confirmedAt: Date
    let journalEntryID: UUID?
    let medicationName: String?
    let medicationDose: String?

    init(status: Status, takenAt: Date? = nil, confirmedAt: Date = Date(),
         journalEntryID: UUID? = nil, medicationName: String? = nil, medicationDose: String? = nil) {
        self.status = status
        self.takenAt = status == .takenAt ? takenAt : nil
        self.confirmedAt = confirmedAt
        self.journalEntryID = status == .takenAt ? journalEntryID : nil
        self.medicationName = status == .takenAt ? medicationName : nil
        self.medicationDose = status == .takenAt ? medicationDose : nil
    }

    func elapsedSeconds(at recordingStart: Date) -> TimeInterval? {
        guard status == .takenAt, let takenAt else { return nil }
        let seconds = recordingStart.timeIntervalSince(takenAt)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    func forRecording(at recordingStart: Date, calendar: Calendar = .current) -> Self? {
        if status == .takenAt && elapsedSeconds(at: recordingStart) == nil { return nil }
        // "Today" must not silently carry over when a set crosses midnight.
        if status == .noneToday && !calendar.isDate(confirmedAt, inSameDayAs: recordingStart) { return nil }
        return self
    }

    static func latestIntake(in entries: [JournalEntry], before date: Date) -> JournalEntry? {
        entries.filter { entry in
            guard entry.type == .medication, entry.date <= date,
                  let event = entry.medicationEvent else { return false }
            return [.usual, .late, .extra].contains(event)
        }.max { $0.date < $1.date }
    }
}

// MARK: - Stop condition (supports BOTH fixed reps and fixed duration)

enum StopMode: String, Codable { case repetitions, duration }

struct StopCondition: Codable, Equatable {
    var mode: StopMode
    /// Used when mode == .repetitions (e.g. 10, as in UPDRS).
    var targetReps: Int
    /// Used when mode == .duration, in seconds (e.g. 15).
    var targetDuration: TimeInterval

    static let tenReps      = StopCondition(mode: .repetitions, targetReps: 10, targetDuration: 15)
    static let fifteenSec   = StopCondition(mode: .duration,    targetReps: 10, targetDuration: 15)
    static let thirtySec    = StopCondition(mode: .duration,    targetReps: 10, targetDuration: 30)
}

// MARK: - Raw signal

/// One sample of the 1-D movement signal.
/// `t` is seconds relative to trial start (already normalized, wall-clock agnostic).
struct TimestampedSample: Codable, Equatable {
    let t: Double      // seconds since trial start
    let value: Double  // e.g. thumb–index distance, or forearm rotation rate
}

/// Capture evidence only. Slow, small or irregular movements are not capture failures.
struct MovementSignalAssessment: Equatable {
    // Advisory discontinuity, not a sampling-rate or clinical validity threshold.
    static let gapWarningSeconds = 2.0
    let hasPlottableSignal: Bool
    let hasAnalysisInput: Bool
    let hasGaps: Bool

    init(samples: [TimestampedSample], recordedDurationSeconds: Double? = nil) {
        let ordered = samples.allSatisfy { $0.t.isFinite && $0.value.isFinite && $0.t >= 0 }
            && zip(samples, samples.dropFirst()).allSatisfy { pair in pair.0.t <= pair.1.t }
        let hasSpan = samples.first.map { first in
            samples.last.map { $0.t > first.t } ?? false
        } ?? false
        hasPlottableSignal = ordered && hasSpan && samples.count >= 2
        hasAnalysisInput = ordered && hasSpan && samples.count >= 4
        let hasTrailingGap: Bool
        if let duration = recordedDurationSeconds, duration.isFinite, duration >= 0,
           let last = samples.last {
            hasTrailingGap = duration - last.t >= Self.gapWarningSeconds
        } else {
            hasTrailingGap = false
        }
        hasGaps = ordered && ((samples.first?.t ?? 0) >= Self.gapWarningSeconds
            || zip(samples, samples.dropFirst()).contains { pair in
                pair.1.t - pair.0.t >= Self.gapWarningSeconds
            } || hasTrailingGap)
    }
}

// MARK: - Computed metrics

/// Descriptive signal metrics, not validated clinical scores or UPDRS mappings.
struct MovementMetrics: Codable, Equatable {
    var cycleCount: Int              // number of completed movement cycles
    var frequencyHz: Double          // speed: cycles per second
    var meanAmplitude: Double        // amplitude: mean peak-to-peak (normalized units)
    var amplitudeDecrementSlope: Double // mean-normalized amplitude slope per cycle
    var rhythmCV: Double             // rhythm: coefficient of variation of cycle durations
    var pauseCount: Int              // intervals longer than twice the median; not diagnosed freezing
    var onsetLatencySec: Double      // delay before movement starts

    /// A convenience "quality index" in 0...1 (higher = smoother/faster/steadier).
    /// NOTE: this is a heuristic for UI trends only, NOT a validated UPDRS score.
    var qualityIndex: Double

    static let empty = MovementMetrics(
        cycleCount: 0, frequencyHz: 0, meanAmplitude: 0,
        amplitudeDecrementSlope: 0, rhythmCV: 0, pauseCount: 0,
        onsetLatencySec: 0, qualityIndex: 0
    )
}

// MARK: - Trial & Session

/// A relative file reference for an accepted, privately stored camera movie.
struct MovementVideoReference: Codable, Equatable {
    let fileName: String
    let byteCount: Int64
}

/// Versions describe the signal and analyzer used, not clinical validity.
enum MovementMeasurementVersion {
    static let camera = "camera-live-palm-aspect-v2-analysis-v1"
    static let watch = "watch-rotation-rate-v1-analysis-v1"
}

/// Vision points have independently normalized x/y coordinates. Ratios use
/// image-height units and the live palm length, never a saved image-space scale.
enum CameraMovementSignal {
    static func value(task: MovementTaskType, wrist: CGPoint, middleMCP: CGPoint,
                      fingertips: [CGPoint], imageAspectRatio: Double) -> Double? {
        guard imageAspectRatio.isFinite, imageAspectRatio > 0,
              ([wrist, middleMCP] + fingertips).allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
            hypot(Double(a.x - b.x) * imageAspectRatio, Double(a.y - b.y))
        }
        let scale = distance(wrist, middleMCP)
        guard scale > 0.005 else { return nil }
        let result: Double
        switch task {
        case .fingerTap:
            guard fingertips.count == 2 else { return nil }
            result = distance(fingertips[0], fingertips[1]) / scale
        case .handOpenClose:
            guard fingertips.count >= 3 else { return nil }
            let center = CGPoint(x: (wrist.x + middleMCP.x) / 2, y: (wrist.y + middleMCP.y) / 2)
            result = fingertips.reduce(0) { $0 + distance($1, center) } / Double(fingertips.count) / scale
        case .pronationSupination: return nil
        }
        return result.isFinite ? result : nil
    }
}

/// A single recording of one task on one hand.
struct Trial: Identifiable, Codable, Equatable {
    let id: UUID
    let taskType: MovementTaskType
    let side: BodySide
    let source: SignalSource
    let stopCondition: StopCondition
    let startedAt: Date
    /// Device uptime (ProcessInfo.systemUptime) at trial start. Together with
    /// `startedAt` (wall clock) this is the sync anchor for aligning sources
    /// that timestamp in uptime (Watch CoreMotion, camera frames) with wall
    /// time. Optional so pre-existing JSONL recordings still decode.
    let startUptime: Double?
    let samples: [TimestampedSample]
    let metrics: MovementMetrics
    /// Nil means unanswered (including older recordings), not "none taken".
    let medicationTiming: MedicationTiming?
    /// Actual elapsed recording time, independent of tracking. Nil for older recordings.
    let recordedDurationSeconds: Double?
    /// Relative private-file reference. No video bytes or absolute device paths in JSONL.
    let video: MovementVideoReference?
    /// Nil on historical recordings. Never infer a version or rewrite their values.
    let measurementVersion: String?

    init(id: UUID = UUID(),
         taskType: MovementTaskType,
         side: BodySide,
         source: SignalSource,
         stopCondition: StopCondition,
         startedAt: Date = Date(),
         startUptime: Double? = nil,
         samples: [TimestampedSample],
         metrics: MovementMetrics,
         medicationTiming: MedicationTiming? = nil,
         recordedDurationSeconds: Double? = nil,
         video: MovementVideoReference? = nil,
         measurementVersion: String? = nil) {
        self.id = id
        self.taskType = taskType
        self.side = side
        self.source = source
        self.stopCondition = stopCondition
        self.startedAt = startedAt
        self.startUptime = startUptime
        self.samples = samples
        self.metrics = metrics
        self.medicationTiming = medicationTiming
        self.recordedDurationSeconds = recordedDurationSeconds
        self.video = video
        self.measurementVersion = measurementVersion
    }

    func withMedicationTiming(_ timing: MedicationTiming?) -> Self {
        Self(id: id, taskType: taskType, side: side, source: source,
             stopCondition: stopCondition, startedAt: startedAt, startUptime: startUptime,
             samples: samples, metrics: metrics,
             medicationTiming: timing?.forRecording(at: startedAt),
             recordedDurationSeconds: recordedDurationSeconds, video: video,
             measurementVersion: measurementVersion)
    }

    func withVideo(_ video: MovementVideoReference?) -> Self {
        Self(id: id, taskType: taskType, side: side, source: source,
             stopCondition: stopCondition, startedAt: startedAt, startUptime: startUptime,
             samples: samples, metrics: metrics, medicationTiming: medicationTiming,
             recordedDurationSeconds: recordedDurationSeconds, video: video,
             measurementVersion: measurementVersion)
    }
}

/// A session groups the trials recorded together (typically all three tasks,
/// both hands, at one point in time and one stimulation context).
struct MovementSession: Identifiable, Codable {
    let id: UUID
    let patientId: String        // pseudonymized ID — never a real name
    let date: Date
    let stimulationContext: StimulationContext
    var trials: [Trial]

    var recordedTaskCount: Int {
        Set(trials.map { "\($0.taskType.rawValue)/\($0.side.rawValue)" }).count
    }

    var isFullMovementSet: Bool {
        recordedTaskCount == MovementTaskType.allCases.count * BodySide.allCases.count
    }

    var completionLabelKey: String { isFullMovementSet ? "All tasks recorded" : "Some tasks recorded" }

    mutating func accept(_ trial: Trial) {
        if let index = trials.firstIndex(where: { $0.taskType == trial.taskType && $0.side == trial.side }) {
            trials[index] = trial
        } else {
            trials.append(trial)
        }
    }

    init(id: UUID = UUID(),
         patientId: String,
         date: Date = Date(),
         stimulationContext: StimulationContext = .unspecified,
         trials: [Trial] = []) {
        self.id = id
        self.patientId = patientId
        self.date = date
        self.stimulationContext = stimulationContext
        self.trials = trials
    }
}
