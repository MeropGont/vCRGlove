//
//  MovementModels.swift
//  vCRGlove
//
//  Data models for the MDS-UPDRS-inspired movement task module.
//  Sensor-independent: a Trial holds a 1-D signal (`[TimestampedSample]`)
//  regardless of whether it came from the camera (Vision) or the Watch (CoreMotion).
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
        case .fingerTap:           return "Finger Tapping"
        case .handOpenClose:       return "Hand Open/Close"
        case .pronationSupination: return "Pronation/Supination"
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
}

/// Relation of a recording to the vCR stimulation, for pre/post comparisons.
enum StimulationContext: String, CaseIterable, Codable, Identifiable {
    case baseline      // before any stimulation
    case preStim       // immediately before a session
    case postStim      // immediately after a session
    case unspecified
    var id: String { rawValue }
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
}

// MARK: - Raw signal

/// One sample of the 1-D movement signal.
/// `t` is seconds relative to trial start (already normalized, wall-clock agnostic).
struct TimestampedSample: Codable, Equatable {
    let t: Double      // seconds since trial start
    let value: Double  // e.g. thumb–index distance, or forearm rotation rate
}

// MARK: - Computed metrics

/// Continuous metrics mapped 1:1 to the five UPDRS scoring criteria,
/// plus rhythm variability. These are the numbers shown to the patient
/// as trends and exported for the clinic.
struct MovementMetrics: Codable, Equatable {
    var cycleCount: Int              // number of completed movement cycles
    var frequencyHz: Double          // speed: cycles per second
    var meanAmplitude: Double        // amplitude: mean peak-to-peak (normalized units)
    var amplitudeDecrementSlope: Double // decrement: slope of amplitude over cycle index (neg = fatiguing)
    var rhythmCV: Double             // rhythm: coefficient of variation of cycle durations
    var pauseCount: Int              // interruptions / "freezing": abnormally long gaps
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

/// A single recording of one task on one hand.
struct Trial: Identifiable, Codable {
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

    init(id: UUID = UUID(),
         taskType: MovementTaskType,
         side: BodySide,
         source: SignalSource,
         stopCondition: StopCondition,
         startedAt: Date = Date(),
         startUptime: Double? = nil,
         samples: [TimestampedSample],
         metrics: MovementMetrics) {
        self.id = id
        self.taskType = taskType
        self.side = side
        self.source = source
        self.stopCondition = stopCondition
        self.startedAt = startedAt
        self.startUptime = startUptime
        self.samples = samples
        self.metrics = metrics
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
