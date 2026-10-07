//
//  VisionHandPoseCapture.swift
//  vCRGlove
//
//  Camera capture source for tasks 3.4 (finger tapping) and 3.5 (hand
//  open/close): front camera frames → VNDetectHumanHandPoseRequest → one
//  scalar per frame, normalized by hand size so the value is independent of
//  how far the hand is from the camera.
//
//    3.4 → thumb tip ↔ index tip distance / hand scale
//    3.5 → mean fingertip ↔ palm-center distance / hand scale
//
//  The scalar is delivered via `onSample` with a monotonic timestamp — the
//  consumer (MovementTaskView) feeds it into the same TrialRecorder used by
//  the synthetic source. No video is ever stored.
//
//  NOTE: Requires a real device — the Simulator has no camera.
//

import Foundation
import AVFoundation
import Vision
import Combine

final class VisionHandPoseCapture: NSObject, ObservableObject {

    enum CaptureError: LocalizedError {
        case permissionDenied
        case noCamera

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Camera access was denied. Enable it in Settings to record movement tests."
            case .noCamera:
                return "No camera is available on this device (the Simulator has no camera)."
            }
        }
    }

    /// Exposed so the UI can attach an AVCaptureVideoPreviewLayer.
    let session = AVCaptureSession()

    /// True while a hand is currently detected — lets the UI prompt the user.
    @Published private(set) var isHandVisible = false
    /// Normalized wrist→middleMCP distance (0…~0.25 in Vision coords).
    /// Use to guide the user: too small = hand too far, too large = too close.
    @Published private(set) var handScale: Double = 0
    /// True while task-relevant joints are cut off by the frame edge — the
    /// signal is unreliable then and the UI should warn immediately.
    @Published private(set) var isHandClipped = false
    /// True once `session.startRunning()` has returned. The preview should only
    /// be attached/removed while the session is in a known running state.
    @Published private(set) var isSessionRunning = false

    /// Opt-in setup observations; movement recording and its scalar stay unchanged.
    var tracksCalibration = false
    @Published private(set) var calibrationFrame: HandCalibrationFrame?

    /// One normalized scalar per processed frame. Called on the main queue.
    /// `time` is in the host/monotonic clock (comparable to systemUptime).
    var onSample: ((_ value: Double, _ time: Double) -> Void)?

    private var taskType: MovementTaskType = .fingerTap
    private let videoQueue = DispatchQueue(label: "vcr.handpose.video", qos: .userInitiated)
    private let handPoseRequest: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 1
        return r
    }()
    private let minJointConfidence: Float = 0.2
    /// Joints closer than this (normalized coords) to any frame edge count as clipped.
    private let edgeMargin: Double = 0.04
    /// Keep the clipped warning up briefly so it doesn't flicker frame-to-frame.
    private let clippedHoldSec: Double = 0.6
    private var lastClippedAt: Double = -.infinity
    private var isConfigured = false
    private var videoOrientation: CGImagePropertyOrientation = .up

    /// Records the camera feed to a temporary movie file during the measurement.
    private let movieFileOutput = AVCaptureMovieFileOutput()
    private let recordingDelegate = MovieFileOutputDelegate()
    /// Set before `stopRecording`; called on the main queue with the recorded file URL.
    private var recordingCompletion: ((URL?) -> Void)?

    // MARK: - Lifecycle

    /// Requests permission, configures the front camera, and starts streaming.
    func start(taskType: MovementTaskType,
               completion: @escaping (Result<Void, CaptureError>) -> Void) {
        self.taskType = taskType

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.permissionDenied)) }
                return
            }
            self.videoQueue.async {
                let start = CFAbsoluteTimeGetCurrent()
                do {
                    try self.configureSessionIfNeeded()
                    self.session.startRunning()
                    let elapsed = CFAbsoluteTimeGetCurrent() - start
                    print("[PERF] camera session started in \(String(format: "%.3f", elapsed)) s")
                    DispatchQueue.main.async {
                        self.isSessionRunning = true
                        completion(.success(()))
                    }
                } catch {
                    DispatchQueue.main.async { completion(.failure(.noCamera)) }
                }
            }
        }
    }

    func stop(completion: (() -> Void)? = nil) {
        videoQueue.async { [weak self] in
            guard let self else {
                DispatchQueue.main.async { completion?() }
                return
            }
            // Make sure any active recording is aborted cleanly before tearing down.
            if self.movieFileOutput.isRecording {
                self.movieFileOutput.stopRecording()
            }
            if self.session.isRunning {
                let start = CFAbsoluteTimeGetCurrent()
                self.session.stopRunning()
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                print("[PERF] camera session stopped in \(String(format: "%.3f", elapsed)) s")
                DispatchQueue.main.async { self.isSessionRunning = false }
            }
            DispatchQueue.main.async { completion?() }
        }
    }

    /// Start writing the camera feed to a temporary `.mov` file.
    /// - Returns: the temporary URL, or `nil` if the movie output is not available.
    @discardableResult
    func startRecordingToTemporaryFile() -> URL? {
        guard movieFileOutput.isRecording == false,
              session.outputs.contains(movieFileOutput) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        movieFileOutput.startRecording(to: url, recordingDelegate: recordingDelegate)
        return url
    }

    /// Stop the active recording. `completion` is called on the main queue with the
    /// temporary file URL, or `nil` if no recording was running or it failed.
    func stopRecording(completion: @escaping (URL?) -> Void) {
        recordingCompletion = completion
        recordingDelegate.onComplete = { [weak self] url in
            self?.recordingCompletion = nil
            DispatchQueue.main.async { completion(url) }
        }
        if movieFileOutput.isRecording {
            movieFileOutput.stopRecording()
        } else {
            DispatchQueue.main.async { completion(nil) }
        }
    }

    // MARK: - Session setup

    private func configureSessionIfNeeded() throws {
        guard !isConfigured else { return }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CaptureError.noCamera
        }

        session.beginConfiguration()
        // Higher resolution noticeably improves hand pose detection,
        // especially for finger tapping at arm's length.
        session.sessionPreset = .hd1280x720

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureError.noCamera }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true   // analysis must never back up
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { throw CaptureError.noCamera }
        session.addOutput(output)

        // The sample buffer orientation must match what we tell Vision.
        // Lock to portrait; the preview layer follows the same connection.
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            } else {
                connection.videoOrientation = .portrait
            }
        }

        // Movie output records the actual measurement video to the Photo Library.
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
            if let connection = movieFileOutput.connection(with: .video) {
                if #available(iOS 17.0, *) {
                    connection.videoRotationAngle = 90
                } else {
                    connection.videoOrientation = .portrait
                }
            }
        }

        session.commitConfiguration()
        isConfigured = true

        // Cap frame rate to reduce CPU/heat without hurting detection.
        let targetFPS: Double = 30
        let supports30 = device.activeFormat.videoSupportedFrameRateRanges
            .contains(where: { $0.minFrameRate <= targetFPS && targetFPS <= $0.maxFrameRate })
        if supports30 {
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                device.unlockForConfiguration()
            } catch {
                // Frame-rate capping is optional; ignore lock failure.
            }
        }
    }
}

// MARK: - Movie file recording delegate

private final class MovieFileOutputDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var onComplete: ((URL?) -> Void)?

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.onComplete?(error == nil ? outputFileURL : nil)
            self?.onComplete = nil
        }
    }
}

// MARK: - Frame processing

extension VisionHandPoseCapture: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // Frame PTS is on the host clock — same time base as systemUptime,
        // so the TrialRecorder can normalize it directly.
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: videoOrientation)
        do {
            try handler.perform([handPoseRequest])
        } catch {
            publishCalibrationFrame(nil, at: time)
            return
        }

        if tracksCalibration, let image = CMSampleBufferGetImageBuffer(sampleBuffer) {
            publishCalibrationFrame(handPoseRequest.results?.first, at: time,
                                    imageAspectRatio: Double(CVPixelBufferGetWidth(image))
                                        / Double(CVPixelBufferGetHeight(image)))
        }

        guard let observation = handPoseRequest.results?.first else {
            setHandVisible(false)
            updateClipped(false, at: time)
            return
        }

        // Edge check BEFORE the scalar guard: clipped fingertips are exactly
        // the case where scalar extraction fails — warn instead of going silent.
        let clipped = isClipped(observation)
        updateClipped(clipped, at: time)

        guard let value = scalar(from: observation),
              let wrist = try? observation.recognizedPoint(.wrist),
              let mcp   = try? observation.recognizedPoint(.middleMCP)
        else {
            setHandVisible(false)
            return
        }
        let scale = distance(wrist.location, mcp.location)
        setHandVisible(true)
        DispatchQueue.main.async { [weak self] in self?.handScale = scale }
        onSample?(value, time)
    }

    /// A hand is "clipped" when a task-relevant joint hugs the frame edge, or
    /// when fingertips are missing although the wrist is confidently visible
    /// (they usually vanish because they left the frame).
    private func isClipped(_ observation: VNHumanHandPoseObservation) -> Bool {
        let relevantTips: [VNHumanHandPoseObservation.JointName] = taskType == .fingerTap
            ? [.thumbTip, .indexTip]
            : [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]

        let wristVisible = (try? observation.recognizedPoint(.wrist))
            .map { $0.confidence >= minJointConfidence } ?? false

        var missingTips = 0
        for name in relevantTips {
            guard let p = try? observation.recognizedPoint(name),
                  p.confidence >= minJointConfidence else {
                missingTips += 1
                continue
            }
            let loc = p.location
            if loc.x < edgeMargin || loc.x > 1 - edgeMargin
                || loc.y < edgeMargin || loc.y > 1 - edgeMargin {
                return true
            }
        }
        // Wrist clearly there but fingertips gone → most likely out of frame.
        return wristVisible && missingTips == relevantTips.count
    }

    private func updateClipped(_ clipped: Bool, at time: Double) {
        if clipped { lastClippedAt = time }
        let effective = clipped || (time - lastClippedAt) < clippedHoldSec
        guard effective != isHandClipped else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isHandClipped = effective
        }
    }

    private func setHandVisible(_ visible: Bool) {
        guard visible != isHandVisible else { return }
        DispatchQueue.main.async { [weak self] in
            self?.isHandVisible = visible
        }
    }

    // MARK: - Scalar extraction

    /// Reduces one hand pose to the task's 1-D signal, normalized by hand
    /// size (wrist ↔ middle-finger MCP) so camera distance cancels out.
    /// Uses a one-time calibration if available, otherwise the live frame value.
    private func scalar(from observation: VNHumanHandPoseObservation) -> Double? {
        guard let wrist = point(observation, .wrist),
              let middleMCP = point(observation, .middleMCP) else { return nil }
        let liveScale = distance(wrist, middleMCP)
        let handScale = HandCalibrationStore.shared.isCalibrated
            ? HandCalibrationStore.shared.scale
            : liveScale
        guard handScale > 0.005 else { return nil }   // degenerate / hand too small/edge-on

        switch taskType {
        case .fingerTap:
            guard let thumbTip = point(observation, .thumbTip),
                  let indexTip = point(observation, .indexTip) else { return nil }
            return distance(thumbTip, indexTip) / handScale

        case .handOpenClose:
            let tips: [VNHumanHandPoseObservation.JointName] =
                [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
            let palmCenter = CGPoint(x: (wrist.x + middleMCP.x) / 2,
                                     y: (wrist.y + middleMCP.y) / 2)
            let distances = tips.compactMap { name -> Double? in
                guard let p = point(observation, name) else { return nil }
                return distance(p, palmCenter)
            }
            guard distances.count >= 3 else { return nil }   // tolerate occluded fingers
            return distances.reduce(0, +) / Double(distances.count) / handScale

        case .pronationSupination:
            return nil   // 3.6 is a Watch task (Task C), not camera-based
        }
    }

    private func point(_ observation: VNHumanHandPoseObservation,
                       _ joint: VNHumanHandPoseObservation.JointName) -> CGPoint? {
        guard let p = try? observation.recognizedPoint(joint),
              p.confidence >= minJointConfidence else { return nil }
        return p.location
    }

    private func publishCalibrationFrame(_ observation: VNHumanHandPoseObservation?,
                                         at time: Double, imageAspectRatio: Double = 9.0 / 16.0) {
        guard tracksCalibration else { return }
        var frame = HandCalibrationFrame(timestamp: time, scale: 0,
                                         isDetected: false, isFullyVisible: false,
                                         isOpenHand: false, isFacingCamera: false, isInsideGuide: false)
        if let observation,
           let wrist = point(observation, .wrist),
           let middleMCP = point(observation, .middleMCP) {
            // Calibration needs reliable complete finger chains, not just inferred tips.
            func finger(_ names: [VNHumanHandPoseObservation.JointName]) -> HandCalibrationPose.Finger? {
                let positions = names.compactMap { name -> CGPoint? in
                    guard let joint = try? observation.recognizedPoint(name),
                          joint.confidence >= 0.5 else { return nil }
                    return joint.location
                }
                guard positions.count == 4 else { return nil }
                return .init(base: positions[0], middle: positions[1], distal: positions[2], tip: positions[3])
            }
            var pose: HandCalibrationPose?
            if let wristPoint = try? observation.recognizedPoint(.wrist), wristPoint.confidence >= 0.5,
               let thumb = finger([.thumbCMC, .thumbMP, .thumbIP, .thumbTip]),
               let index = finger([.indexMCP, .indexPIP, .indexDIP, .indexTip]),
               let middle = finger([.middleMCP, .middlePIP, .middleDIP, .middleTip]),
               let ring = finger([.ringMCP, .ringPIP, .ringDIP, .ringTip]),
               let little = finger([.littleMCP, .littlePIP, .littleDIP, .littleTip]) {
                pose = HandCalibrationPose(wrist: wristPoint.location, thumb: thumb,
                                           fingers: [index, middle, ring, little],
                                           imageAspectRatio: imageAspectRatio)
            }
            frame = HandCalibrationFrame(timestamp: time,
                                         scale: distance(wrist, middleMCP),
                                         isDetected: true, isFullyVisible: pose?.isFullyVisible ?? false,
                                         isOpenHand: pose?.hasOpenFingers ?? false,
                                         isFacingCamera: pose?.isFacingCamera ?? false,
                                         isInsideGuide: pose?.isInsideGuide ?? false)
        }
        let observationFrame = frame
        DispatchQueue.main.async { [weak self] in self?.calibrationFrame = observationFrame }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

// MARK: - Calibration quality gate

struct HandCalibrationPose {
    struct Finger {
        let base: CGPoint
        let middle: CGPoint
        let distal: CGPoint
        let tip: CGPoint
        var points: [CGPoint] { [base, middle, distal, tip] }
    }

    let wrist: CGPoint
    let thumb: Finger
    /// Index, middle, ring, little, in that order.
    let fingers: [Finger]
    let imageAspectRatio: Double

    static let guideRect = CGRect(x: 0.12, y: 0.08, width: 0.76, height: 0.84)
    private var points: [CGPoint] { [wrist] + thumb.points + fingers.flatMap(\.points) }
    private var isValid: Bool {
        fingers.count == 4 && imageAspectRatio.isFinite && imageAspectRatio > 0
            && points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
    }
    var isFullyVisible: Bool {
        isValid && points.allSatisfy { $0.x >= 0.04 && $0.x <= 0.96 && $0.y >= 0.04 && $0.y <= 0.96 }
    }
    var isInsideGuide: Bool { isValid && points.allSatisfy { Self.guideRect.contains($0) } }
    private var palmScale: Double { isValid ? distance(wrist, fingers[1].base) : 0 }

    var isFacingCamera: Bool {
        guard isValid, palmScale > 0 else { return false }
        // A narrow projected palm indicates an edge-on view. This cannot distinguish palm from back.
        let width = distance(fingers[0].base, fingers[3].base)
        let axisX = (fingers[1].base.x - wrist.x) * imageAspectRatio
        let axisY = fingers[1].base.y - wrist.y
        let acrossX = (fingers[0].base.x - fingers[3].base.x) * imageAspectRatio
        let acrossY = fingers[0].base.y - fingers[3].base.y
        let perpendicularWidth = abs(axisX * acrossY - axisY * acrossX) / palmScale
        return width / palmScale >= 0.55 && perpendicularWidth / palmScale >= 0.50
    }

    var hasOpenFingers: Bool {
        guard isValid, palmScale > 0 else { return false }
        return fingers.allSatisfy { finger in
            straightness(finger) >= 0.80
                && distance(finger.base, finger.tip) / palmScale >= 0.65
                && distance(wrist, finger.tip) - distance(wrist, finger.base) >= 0.45 * palmScale
        } && straightness(thumb) >= 0.75
            && distance(thumb.base, thumb.tip) / palmScale >= 0.45
            && distance(thumb.tip, fingers[0].base) / palmScale >= 0.55
    }

    private func straightness(_ finger: Finger) -> Double {
        let length = distance(finger.base, finger.middle) + distance(finger.middle, finger.distal)
            + distance(finger.distal, finger.tip)
        return length > 0 ? distance(finger.base, finger.tip) / length : 0
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        // Vision normalizes x and y separately; restore pixel proportions for shape checks.
        hypot((a.x - b.x) * imageAspectRatio, a.y - b.y)
    }
}

struct HandCalibrationFrame: Equatable {
    let timestamp: TimeInterval
    let scale: Double
    let isDetected: Bool
    let isFullyVisible: Bool
    let isOpenHand: Bool
    let isFacingCamera: Bool
    let isInsideGuide: Bool
}

/// Camera-setup checks, not a score of the patient's movement ability.
struct HandCalibrationQualityGate {
    enum Phase: Equatable { case positioning, countdown, collecting, retry, complete }
    enum Guidance: Equatable {
        case showHand, wholeHand, openHand, faceCamera, insideGuide, closer, farther, holdStill, ready, retry
    }

    struct Result {
        let scale: Double
        let sampleCount: Int
        let relativeVariation: Double
    }

    private(set) var phase: Phase = .positioning
    private(set) var guidance: Guidance = .showHand
    private(set) var result: Result?
    private(set) var progress: Double = 0
    private(set) var countdown = 3

    // Match the existing positioning guide. These are setup tolerances, not clinical cutoffs.
    static let scaleRange = 0.06...0.20
    static let maximumFrameAge = 0.35
    private static let maximumFrameGap = 0.25
    private static let maximumVariation = 0.10
    private var positioningFrames: [HandCalibrationFrame] = []
    private var samples: [HandCalibrationFrame] = []
    private var lastTimestamp: TimeInterval?
    private var phaseStartedAt: TimeInterval = 0
    private var referenceScale: Double = 0

    var isReady: Bool { phase == .positioning && guidance == .ready }

    mutating func update(frame: HandCalibrationFrame?, now: TimeInterval) {
        guard phase != .complete, phase != .retry else { return }
        guard now.isFinite, let frame, frame.timestamp.isFinite,
              now >= frame.timestamp, now - frame.timestamp <= Self.maximumFrameAge,
              frame.isDetected, frame.scale.isFinite, frame.scale > 0 else {
            reject(.showHand)
            return
        }
        guard frame.isFullyVisible else { reject(.wholeHand); return }
        guard frame.scale >= Self.scaleRange.lowerBound else { reject(.closer); return }
        guard frame.scale <= Self.scaleRange.upperBound else { reject(.farther); return }
        guard frame.isFacingCamera else { reject(.faceCamera); return }
        guard frame.isOpenHand else { reject(.openHand); return }
        guard frame.isInsideGuide else { reject(.insideGuide); return }
        if let lastTimestamp {
            guard frame.timestamp >= lastTimestamp else { reject(.showHand); return }
            if frame.timestamp - lastTimestamp > Self.maximumFrameGap {
                reject(.holdStill)
                if phase == .retry { return }
            }
        }
        let isNewFrame = frame.timestamp != lastTimestamp
        if isNewFrame { lastTimestamp = frame.timestamp }

        switch phase {
        case .positioning:
            if isNewFrame { positioningFrames.append(frame) }
            positioningFrames.removeAll { frame.timestamp - $0.timestamp > 1.0 }
            let span = frame.timestamp - (positioningFrames.first?.timestamp ?? frame.timestamp)
            let quality = statistics(positioningFrames)
            guidance = positioningFrames.count >= 8 && span >= 0.8
                && quality.variation <= Self.maximumVariation ? .ready : .holdStill
        case .countdown:
            guard abs(frame.scale - referenceScale) / referenceScale <= 0.25 else {
                reject(.holdStill)
                return
            }
            countdown = max(1, 3 - Int(max(0, now - phaseStartedAt)))
            if now - phaseStartedAt >= 3 {
                phase = .collecting
                phaseStartedAt = now
                samples = []
                if isNewFrame, frame.timestamp >= now { samples.append(frame) }
            }
        case .collecting:
            guard abs(frame.scale - referenceScale) / referenceScale <= 0.25 else {
                reject(.holdStill)
                return
            }
            if isNewFrame, frame.timestamp >= phaseStartedAt { samples.append(frame) }
            progress = min(max(0, now - phaseStartedAt) / 2, 1)
            if now - phaseStartedAt >= 2 {
                let span = (samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0)
                let quality = statistics(samples)
                guard samples.count >= 20, span >= 1.8,
                      quality.variation <= Self.maximumVariation else {
                    reject(.retry)
                    return
                }
                result = Result(scale: quality.mean, sampleCount: samples.count,
                                relativeVariation: quality.variation)
                phase = .complete
            }
        case .retry, .complete:
            break
        }
    }

    mutating func start(frame: HandCalibrationFrame?, now: TimeInterval) {
        update(frame: frame, now: now)
        guard isReady else { return }
        referenceScale = statistics(positioningFrames).mean
        phaseStartedAt = now
        phase = .countdown
        countdown = 3
    }

    mutating func reset() { self = Self() }

    private mutating func reject(_ reason: Guidance) {
        if phase == .countdown || phase == .collecting {
            phase = .retry
            samples = []
            progress = 0
        }
        positioningFrames = []
        lastTimestamp = nil
        guidance = reason
    }

    private func statistics(_ frames: [HandCalibrationFrame]) -> (mean: Double, variation: Double) {
        guard !frames.isEmpty else { return (0, .infinity) }
        let mean = frames.reduce(0) { $0 + $1.scale } / Double(frames.count)
        let variance = frames.reduce(0) { $0 + pow($1.scale - mean, 2) } / Double(frames.count)
        return (mean, variance.squareRoot() / mean)
    }
}

// MARK: - Hand calibration store

/// One-time hand-scale calibration. Persists the wrist↔middleMCP distance so
/// the camera-derived signal is normalized against a stable, user-specific
/// reference instead of the per-frame (potentially noisy) live value.
final class HandCalibrationStore: ObservableObject {
    static let shared = HandCalibrationStore()

    private let key = "calibratedHandScale"

    @Published private(set) var scale: Double {
        didSet { UserDefaults.standard.set(scale, forKey: key) }
    }

    var isCalibrated: Bool { scale > 0.005 }

    private init() {
        scale = UserDefaults.standard.double(forKey: key)
    }

    func set(scale: Double) {
        self.scale = scale
    }

    func clear() {
        scale = 0
        UserDefaults.standard.removeObject(forKey: key)
    }
}
