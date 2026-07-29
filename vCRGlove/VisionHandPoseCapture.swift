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
            return
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

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
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
