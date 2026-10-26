//
//  MovementTaskView.swift
//  vCRGlove
//
//  Recording flow for the MDS-UPDRS-inspired movement tasks (3.4 / 3.5 / 3.6):
//  setup → countdown → live recording → result → save.
//
//  Capture sources: VisionHandPoseCapture (camera, tasks 3.4/3.5, real device)
//  or SyntheticCaptureSource (Simulator / demo). Task C (Watch motion for 3.6)
//  will plug into the same TrialRecorder without changing this flow.
//

import SwiftUI
import AVFoundation

struct MovementTaskView: View {

    private enum Phase {
        case setup
        case countdown(Int)
        case recording
        case analyzing          // analysis running in background after recording stops
        case result(Trial)
    }

    @AppStorage("patientID") private var patientID = ""

    @State private var phase: Phase = .setup

    // Setup choices
    @State private var taskType: MovementTaskType = .fingerTap
    @State private var side: BodySide = .right
    @State private var context: StimulationContext = .unspecified
    @State private var medicationTiming: MedicationTiming?

    // Recording machinery
    @State private var recorder: TrialRecorder?
    @State private var cameraCapture: VisionHandPoseCapture?
    @State private var watchCapture: WatchMotionCapture?
    @State private var countdownTimer: Timer?
    @State private var cameraError: String?
    @StateObject private var signalMonitor = LiveSignalMonitor()
    @State private var isCalibrating = false
    @StateObject private var videoDraft = MovementVideoDraft()
    @State private var completedTrial: Trial?
    @State private var isFinishingRecording = false
    @State private var captureAttemptID = UUID()
    @State private var isSaving = false
    @State private var showsSaveError = false

    private var usingCamera: Bool { activeSignalSource == .camera }
    private var usingWatch: Bool { activeSignalSource == .watchMotion }
    private var canStartRecording: Bool {
        StimulationContext.patientChoices.contains(context) &&
            (!usingWatch || PhoneWC.shared.isWatchReachable) && cameraCapture == nil && watchCapture == nil
    }

    private var showsPreview: Bool {
        switch phase {
        case .countdown, .recording: return true
        default:                     return false
        }
    }

    private var activeSignalSource: SignalSource {
        taskType.preferredSource
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Main content
            if usingCamera, showsPreview {
                CameraMovementRecordingView(
                    taskType: taskType, side: side, capture: cameraCapture,
                    monitor: signalMonitor, recorder: recorder, stopCondition: stopCondition,
                    countdown: cameraCountdown, showsDetectionHints: true,
                    isFinishingRecording: isFinishingRecording
                ) {
                    if case .recording = phase {
                        Button(role: .destructive) { requestRecordingStop() } label: {
                            Label(L10n(isFinishingRecording ? "Finishing recording…" : "Stop"), systemImage: "stop.circle.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 54)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isFinishingRecording)
                    } else {
                        Button(L10n("Cancel"), role: .cancel) { cancelEverything() }
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .buttonStyle(.bordered)
                    }
                }
            } else {
                Group {
                    switch phase {
                    case .setup:
                        setupView
                    case .countdown(let n):
                        countdownView(n)
                    case .recording:
                        recordingView
                    case .analyzing:
                        analyzingView
                    case .result(let trial):
                        MovementTrialResultView(
                            trial: trial,
                            onSave: { save(trial) },
                            onDiscard: { cancelEverything() },
                            isSaving: isSaving,
                            videoMessage: videoDraft.messageKey
                        )
                    }
                }
            }

            // Persistent watch signal chart: same idea as the camera preview.
            if usingWatch, let wc = watchCapture, showsPreview {
                VStack(spacing: 4) {
                    WatchStreamHint(capture: wc)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    LiveSignalChart(monitor: signalMonitor)
                        .frame(height: 56)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
        }
        .navigationTitle(L10n("Movement Test"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert(L10n("Recording not saved"), isPresented: $showsSaveError) {
            Button(L10n("OK"), role: .cancel) {}
            if videoDraft.url != nil, case .result(let trial) = phase {
                Button(L10n("Save without video")) { save(trial, includeVideo: false) }
            }
        } message: {
            Text(L10n("Please try saving again. This recording is still here."))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MovementTrendView()
                } label: {
                    Label(L10n("Trends"), systemImage: "chart.xyaxis.line")
                }
            }
        }
        .onDisappear {
            if case .result = phase { return }
            if !isSaving { cancelEverything() }
        }
        .sheet(isPresented: $isCalibrating) {
            HandCalibrationView { isCalibrating = false }
        }
    }

    private var cameraCountdown: Int? {
        if case .countdown(let value) = phase { return value }
        return nil
    }

    // MARK: - Setup

    private var setupView: some View {
        Form {
            Section("Task") {
                Picker(L10n("Movement"), selection: $taskType) {
                    ForEach(MovementTaskType.allCases) { t in
                        Text("\(t.rawValue)  \(t.displayName)").tag(t)
                    }
                }
                Picker(L10n("Hand"), selection: $side) {
                    Text(BodySide.left.displayName).tag(BodySide.left)
                    Text(BodySide.right.displayName).tag(BodySide.right)
                }
                .pickerStyle(.segmented)
            }

            if MovementDemonstrationClip.clip(task: taskType, side: side) != nil {
                Section {
                    MovementDemonstrationView(taskType: taskType, side: side)
                }
            }

            Section("Protocol") {
                LabeledContent(L10n("Stop after"), value: L10n("10 repetitions"))
            }

            Section("Context") {
                Picker(L10n("Relative to stimulation"), selection: $context) {
                    Text(L10n("Choose stimulation timing")).tag(StimulationContext.unspecified)
                    ForEach(StimulationContext.patientChoices) { c in
                        Text(contextLabel(c)).tag(c)
                    }
                }
            }

            Section {
                MovementMedicationSelection(timing: $medicationTiming)
            }

            Section {
                if usingCamera {
                    Text(L10n("This task uses the front camera to track your hand. Accepted videos stay in this app."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if usingWatch {
                    Text(L10n("Wear the watch on the tested arm and keep the vCRGlove watch app open during the recording."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n("Sensor"))
            }

            if usingCamera {
                Section("Calibration") {
                    if HandCalibrationStore.shared.isCalibrated {
                        HStack {
                            Text(L10n("Hand size calibrated"))
                                .foregroundStyle(.green)
                            Spacer()
                            Button(L10n("Recalibrate")) {
                                isCalibrating = true
                            }
                        }
                    } else {
                        Button {
                            isCalibrating = true
                        } label: {
                            Label(L10n("Calibrate hand size"), systemImage: "hand.raised")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(L10n("For each new session, we recommend recalibrating."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                if usingWatch {
                    WatchPrerequisiteView()
                }

                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                    Button {
                        startCountdown()
                    } label: {
                        Label(L10n("Start"), systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                            .font(.title3.bold())
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStartRecording)
                }
            } footer: {
                if let cameraError {
                    Text(L10n(cameraError)).foregroundStyle(.red)
                }
            }
        }
    }

    private func contextLabel(_ c: StimulationContext) -> String {
        L10n(c.titleKey)
    }

    // MARK: - Countdown

    private func countdownView(_ n: Int) -> some View {
        VStack(spacing: 24) {
            // Camera preview shown here only when NOT using camera
            // (when using camera it's in the persistent ZStack overlay above).
            Text(taskInstruction)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, usingCamera ? 340 : (usingWatch ? 120 : 0))
            Text("\(n)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Button(L10n("Cancel"), role: .cancel) { cancelEverything() }
        }
    }

    private var taskInstruction: String {
        switch taskType {
        case .fingerTap:
            return L10n("Tap your index finger on your thumb as fast and as big as possible.")
        case .handOpenClose:
            return L10n("Open and close your fist as fast and as fully as possible.")
        case .pronationSupination:
            return L10n("Rotate your forearm palm-up / palm-down as fast and as fully as possible.")
        }
    }

    private func startCountdown() {
        guard canStartRecording else { return }
        captureAttemptID = UUID()
        let attemptID = captureAttemptID
        completedTrial = nil
        videoDraft.discard()
        cameraError = nil
        signalMonitor.reset()

        if usingWatch {
            let capture = WatchMotionCapture()
            watchCapture = capture
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start { result in
                guard captureAttemptID == attemptID else { capture.stop(); return }
                switch result {
                case .success:
                    beginCountdown()
                case .failure(let error):
                    cameraError = error.localizedDescription
                    cancelEverything()
                }
            }
            return
        }

        if usingCamera {
            let capture = VisionHandPoseCapture()
            cameraCapture = capture
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start(taskType: taskType) { result in
                guard captureAttemptID == attemptID else { capture.stop(); return }
                if case .failure(let error) = result {
                    cameraError = error.localizedDescription
                    cancelEverything()
                } else {
                    beginCountdown()
                }
            }
            return
        }

        beginCountdown()
    }

    private func beginCountdown() {
        isFinishingRecording = false
        phase = .countdown(3)
        countdownTimer?.invalidate()

        let timer = Timer(timeInterval: 1.0, repeats: true) { timer in
            if case .countdown(let n) = phase, n > 1 {
                phase = .countdown(n - 1)
            } else {
                timer.invalidate()
                startRecording()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }

    // MARK: - Analyzing (shown between recording end and result)

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
            Text(L10n("Analysing movement…"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 24) {
            // Top padding so content doesn't overlap the persistent preview overlay.
            if usingCamera { Color.clear.frame(height: 340) }
            if usingWatch { Color.clear.frame(height: 114) }
            Text(taskType.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let recorder {
                RecordingProgressView(recorder: recorder,
                                      stopCondition: stopCondition)
            }
            Button(role: .destructive) {
                requestRecordingStop()
            } label: {
                Label(L10n(isFinishingRecording ? "Finishing recording…" : "Stop"), systemImage: "stop.circle.fill")
                    .font(.headline)
            }
            .disabled(isFinishingRecording)
        }
        .padding()
    }

    private var stopCondition: StopCondition { .thirtySec }

    private func requestRecordingStop() {
        guard !isFinishingRecording else { return }
        isFinishingRecording = true
        recorder?.finish()
    }

    private func finishRecordingCapture() {
        isFinishingRecording = true
        // Keep the preview mounted until capture stops. Completion, not a
        // SwiftUI-observed flag transition, owns this teardown.
        let cam = self.cameraCapture
        let watch = self.watchCapture
        let attemptID = captureAttemptID
        let group = DispatchGroup()
        if let cam {
            group.enter()
            cam.finishMeasurement { url, startPTS in
                if captureAttemptID == attemptID {
                    videoDraft.receive(url, captureStartPTSSeconds: startPTS, normalizedHandCrop: cam.completedHandCrop)
                }
                else if let url { try? FileManager.default.removeItem(at: url) }
                group.leave()
            }
        }
        if let watch { group.enter(); watch.stop { group.leave() } }
        group.notify(queue: .main) {
            Task { @MainActor in
                guard self.captureAttemptID == attemptID else { return }
                self.cameraCapture = nil
                self.watchCapture = nil
                if case .recording = self.phase {
                    self.phase = .analyzing
                }
                self.showCompletedTrialIfReady()
                print("[PERF] single-task capture finalized")
            }
        }
    }

    private func startRecording() {
        videoDraft.beginTake()
        isFinishingRecording = false
        completedTrial = nil
        let attemptID = captureAttemptID
        let medicationSnapshot = medicationTiming
        let r = TrialRecorder(taskType: taskType,
                              side: side,
                              source: activeSignalSource,
                              stopCondition: stopCondition,
                              measurementVersion: cameraCapture != nil ? MovementMeasurementVersion.camera
                                  : (watchCapture != nil ? MovementMeasurementVersion.watch : nil),
                              recordsFingerTappingAngles: cameraCapture != nil)
        r.onComplete = { trial in
            guard captureAttemptID == attemptID else { return }
            completedTrial = trial.withMedicationTiming(medicationSnapshot)
            finishRecordingCapture()
            EventStore.shared.append(
                type: "TASK", tag: "trial_completed",
                message: "Movement trial completed",
                details: ["task": trial.taskType.rawValue,
                          "side": trial.side.rawValue,
                          "cycles": "\(trial.metrics.cycleCount)",
                          "duration": String(format: "%.1f", trial.samples.last?.t ?? 0)])
        }
        recorder = r
        phase = .recording
        if let cameraCapture {
            cameraCapture.onFrame = { frame, time in r.ingestCameraFrame(frame, at: time) }
            cameraCapture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
        } else if let watchCapture {
            watchCapture.onSample = { [signalMonitor] value, time in
                r.ingest(value: value, at: time)
                signalMonitor.ingest(value: value, at: time)
            }
        }
        if let cameraCapture, videoDraft.isVideoEnabledForTake {
            cameraCapture.startRecordingToTemporaryFile { started in
                guard captureAttemptID == attemptID else { return }
                if !started { videoDraft.receive(nil) }
                r.start()
                if isFinishingRecording { r.finish() }
            }
        } else { r.start() }
        EventStore.shared.append(
            type: "TASK", tag: "trial_started",
            message: "Movement trial started",
            details: ["task": taskType.rawValue,
                      "side": side.rawValue,
                      "source": activeSignalSource.rawValue,
                      "mode": stopCondition.mode.rawValue,
                      "videoRequested": "\(cameraCapture != nil && videoDraft.isVideoEnabledForTake)"])
    }

    // MARK: - Save / cleanup

    private func showCompletedTrialIfReady() {
        guard cameraCapture == nil, watchCapture == nil, let completedTrial else { return }
        phase = .result(completedTrial)
    }

    private func save(_ trial: Trial, includeVideo: Bool = true) {
        guard !isSaving else { return }
        let session = MovementSession(
            patientId: patientID.isEmpty ? "unset" : patientID,
            date: trial.startedAt, stimulationContext: context
        )
        isSaving = true
        TaskSessionStore.shared.saveAcceptedTrial(trial, in: session,
            temporaryVideoURL: includeVideo ? videoDraft.url : nil,
            videoCaptureStartPTSSeconds: includeVideo ? videoDraft.captureStartPTSSeconds : nil,
            normalizedHandCrop: includeVideo ? videoDraft.normalizedHandCrop : nil,
            deferVideoProcessing: true) { result in
            isSaving = false
            switch result {
            case .success(let saved):
                videoDraft.discard()
                TaskSessionStore.shared.finishAcceptedSession(saved)
                medicationTiming = nil
                phase = .setup
            case .failure:
                showsSaveError = true
            }
        }
    }

    private func cancelEverything() {
        guard !isSaving else { return }
        captureAttemptID = UUID()
        completedTrial = nil
        videoDraft.discard()
        countdownTimer?.invalidate()
        countdownTimer = nil
        cameraCapture?.stop()
        cameraCapture = nil
        watchCapture?.stop()
        watchCapture = nil
        signalMonitor.reset()
        recorder?.onComplete = nil
        if recorder?.isRecording == true { recorder?.finish() }
        recorder = nil
        phase = .setup
    }
}

// MARK: - Camera helpers

/// Live camera preview backed by AVCaptureVideoPreviewLayer.
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        mirrorFrontPreview(view)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        mirrorFrontPreview(uiView)
    }

    private func mirrorFrontPreview(_ view: PreviewUIView) {
        guard session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.position == .front }),
              let connection = view.previewLayer.connection, connection.isVideoMirroringSupported else { return }
        // Only the self-view is mirrored; analysis frames and saved videos stay unchanged.
        if connection.automaticallyAdjustsVideoMirroring {
            connection.automaticallyAdjustsVideoMirroring = false
        }
        if !connection.isVideoMirrored {
            connection.isVideoMirrored = true
        }
    }
}

/// "Show your hand" prompt driven by the capture's live detection state.
private struct HandVisibilityHint: View {
    @ObservedObject var capture: VisionHandPoseCapture

    var body: some View {
        Label(capture.isHandVisible ? "Hand detected" : "Show hand",
              systemImage: capture.isHandVisible ? "hand.raised.fill" : "hand.raised.slash")
            .font(.caption.bold())
            .foregroundStyle(capture.isHandVisible ? .green : .orange)
    }
}

/// Guides the user on hand distance using the normalized hand scale.
/// Ideal range (wrist→MCP ~0.07…0.18 in Vision normalized coords).
private struct HandDistanceHint: View {
    @ObservedObject var capture: VisionHandPoseCapture

    private var guidance: (text: String, color: Color, icon: String) {
        let s = capture.handScale
        if !capture.isHandVisible { return ("–", .secondary, "arrow.up.and.down") }
        if s < 0.06 { return ("Move closer", .orange, "arrow.down.to.line") }
        if s > 0.20 { return ("Move further", .orange, "arrow.up.to.line") }
        return ("Good distance", .green, "checkmark.circle") }

    var body: some View {
        let g = guidance
        Label(g.text, systemImage: g.icon)
            .font(.caption.bold())
            .foregroundStyle(g.color)
    }
}

/// Positioning template on the camera preview: a dashed target zone with a
/// task-specific hand silhouette. Orange while the hand is missing/misplaced,
/// green + faded once the hand sits correctly — so patients know exactly
/// where to hold their hand before and during a recording.
struct HandGuideOverlay: View {
    @ObservedObject var capture: VisionHandPoseCapture
    let taskType: MovementTaskType
    let side: BodySide

    /// Hand is well placed: detected, fully in frame, and at a good distance.
    private var isPositionedWell: Bool {
        capture.isHandVisible
            && !capture.isHandClipped
            && capture.handScale >= 0.06 && capture.handScale <= 0.20
    }

    private var symbolName: String {
        taskType == .fingerTap ? "hand.pinch" : "hand.raised.fingers.spread"
    }

    var body: some View {
        let good = isPositionedWell
        let color: Color = good ? .green : .orange
        GeometryReader { geo in
            let zone = CGRect(x: geo.size.width * 0.18,
                              y: geo.size.height * 0.10,
                              width: geo.size.width * 0.64,
                              height: geo.size.height * 0.80)
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(color,
                                  style: StrokeStyle(lineWidth: 2.5, dash: [7, 6]))
                    .frame(width: zone.width, height: zone.height)
                    .position(x: zone.midX, y: zone.midY)

                Image(systemName: symbolName)
                    .resizable()
                    .scaledToFit()
                    .frame(height: zone.height * 0.55)
                    .foregroundStyle(color.opacity(good ? 0.25 : 0.55))
                    .scaleEffect(x: MovementRecordingGuidance(taskType: taskType, side: side).cameraGuideHorizontalScale, y: 1)
                    .position(x: zone.midX, y: zone.midY)

                if !good {
                    Text(String(format: L10n("Place your %@ hand here"), side == .left ? L10n("left") : L10n("right")))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(color, in: Capsule())
                        .position(x: zone.midX, y: zone.minY + 12)
                }
            }
            .opacity(good ? 0.45 : 1.0)
        }
        .animation(.easeInOut(duration: 0.25), value: isPositionedWell)
        .allowsHitTesting(false)
    }
}

/// Live status of the watch motion stream during countdown/recording.
private struct WatchStreamHint: View {
    @ObservedObject var capture: WatchMotionCapture

    var body: some View {
        Label(capture.isReceiving ? L10n("Watch connected — receiving motion")
                                  : L10n("Waiting for watch… open the watch app"),
              systemImage: capture.isReceiving ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
            .font(.caption.bold())
            .foregroundStyle(capture.isReceiving ? .green : .orange)
    }
}

private struct WatchPrerequisiteView: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { _ in
            let ready = PhoneWC.shared.isWatchReachable
            if !ready {
                VStack(alignment: .leading, spacing: 6) {
                    Label(L10n("Open the watch app to continue"), systemImage: "applewatch.slash")
                        .font(.callout.bold())

                    Text(L10n("Open Settings > Instructions > Troubleshooting if the watch does not connect."))
                        .font(.caption)
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Immediate warning when fingers leave the camera frame: red border around
/// the preview and banner — cycles are NOT counted while the hand is clipped,
/// so the user must notice right away.
struct ClippedWarningOverlay: View {
    @ObservedObject var capture: VisionHandPoseCapture

    var body: some View {
        ZStack {
            if capture.isHandClipped {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.red, lineWidth: 4)

                VStack {
                    Label(L10n("Keep your whole hand in the frame!"), systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.red, in: Capsule())
                        .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: capture.isHandClipped)
    }
}

/// Lightweight real-time sparkline of the movement signal — shows exactly
/// what the analyzer sees, so signal-quality problems are visible immediately.
struct LiveSignalChart: View {
    @ObservedObject var monitor: LiveSignalMonitor

    var body: some View {
        Canvas { context, size in
            let samples = monitor.window
            guard samples.count >= 2,
                  let tMax = samples.last?.t,
                  let vMin = samples.map(\.value).min(),
                  let vMax = samples.map(\.value).max() else { return }
            let tMin = tMax - monitor.windowSec
            let vRange = max(vMax - vMin, 0.001)

            var path = Path()
            for (i, s) in samples.enumerated() {
                let x = (s.t - tMin) / monitor.windowSec * size.width
                let y = size.height - ((s.value - vMin) / vRange) * (size.height - 8) - 4
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else      { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .padding(.horizontal, 6)
        .overlay {
            if monitor.window.count < 2 {
                Text(L10n("Waiting for signal…"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Live progress subview

struct MovementRecordingGuidance {
    let taskType: MovementTaskType
    let side: BodySide

    var handKey: String { side == .right ? "Right hand" : "Left hand" }

    var cameraGuideHorizontalScale: CGFloat {
        if taskType == .handOpenClose {
            return side == .right ? -1 : 1
        }
        return side == .left ? -1 : 1
    }

    // Instruction symbols face the reader; camera guides keep their separate mirrored rule.
    var taskIconHorizontalScale: CGFloat {
        switch taskType {
        case .handOpenClose: return handIconHorizontalScale
        case .fingerTap: return side == .left ? -1 : 1
        case .pronationSupination: return 1
        }
    }

    var handIconHorizontalScale: CGFloat { side == .right ? -1 : 1 }

    var instructionKey: String {
        switch taskType {
        case .fingerTap:
            return "Tap your index finger to your thumb.\nOpen wide. Repeat as fast as you can."
        case .handOpenClose:
            return "Open your hand fully, then make a fist.\nRepeat as fast as you can."
        case .pronationSupination:
            return "Rotate your forearm palm-up / palm-down as fast and as fully as possible."
        }
    }
}

/// A stable preview parent spans countdown and recording; only the progress changes.
private struct CameraMovementRecordingView<Controls: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let taskType: MovementTaskType
    let side: BodySide
    let capture: VisionHandPoseCapture?
    let monitor: LiveSignalMonitor
    let recorder: TrialRecorder?
    let stopCondition: StopCondition
    let countdown: Int?
    var progressText: String? = nil
    var showsDetectionHints = false
    var isFinishingRecording = false
    @ViewBuilder var controls: () -> Controls

    private var guidance: MovementRecordingGuidance {
        MovementRecordingGuidance(taskType: taskType, side: side)
    }

    private var usesCompactHandLayout: Bool {
        taskType == .handOpenClose && dynamicTypeSize <= .large
    }

    private var usesCompactTappingLayout: Bool {
        taskType == .fingerTap && dynamicTypeSize <= .large
    }

    private var usesCompactHeader: Bool {
        usesCompactHandLayout || usesCompactTappingLayout
    }

    private var handLabel: some View {
        Text(L10n(guidance.handKey))
            .font(.headline.bold())
            .accessibilityIdentifier("movementRecordingHand")
    }

    private var movementInstruction: some View {
        Text(L10n(guidance.instructionKey))
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("movementRecordingInstruction")
    }

    private var demonstration: some View {
        MovementDemonstrationView(taskType: taskType, side: side, automaticallyPlays: true,
                                  allowsPlayback: !isFinishingRecording)
            .frame(maxWidth: 240)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: usesCompactTappingLayout ? 4 : (usesCompactHandLayout ? 6 : 10)) {
                if usesCompactHeader {
                    HStack {
                        if let progressText {
                            Text(progressText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        handLabel
                    }
                } else if let progressText {
                    Text(progressText).font(.subheadline).foregroundStyle(.secondary)
                }

                Text(taskType.displayName)
                    .font(usesCompactHeader ? .headline : .title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("movementRecordingTask")

                Group {
                    if let capture {
                        MovementCameraPreview(capture: capture, taskType: taskType,
                                              side: side, showsDetectionHints: showsDetectionHints,
                                              isFinishingRecording: isFinishingRecording)
                    } else {
                        #if DEBUG && targetEnvironment(simulator)
                        // Layout fixture only; synthetic recording remains unchanged.
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.secondarySystemBackground))
                        #else
                        ProgressView(L10n(isFinishingRecording ? "Finishing recording…" : "Starting camera…"))
                        #endif
                    }
                }
                .frame(height: usesCompactTappingLayout ? 200 : (usesCompactHandLayout ? 210 : 230))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if let countdown {
                        Text("\(countdown)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 88)
                            .background(.black.opacity(0.6), in: Circle())
                            .accessibilityLabel(String(format: L10n("Starting in %d"), countdown))
                            .accessibilityIdentifier("movementCameraCountdown")
                    }
                }
                .accessibilityIdentifier("movementCameraPreview")

                if usesCompactHandLayout {
                    HStack(spacing: 12) {
                        demonstration.frame(width: 170)
                        movementInstruction
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if usesCompactTappingLayout {
                    movementInstruction
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    demonstration
                } else {
                    VStack(spacing: 4) {
                        handLabel
                        movementInstruction
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)

                    demonstration
                }

                if isFinishingRecording {
                    ProgressView(L10n("Finishing recording…"))
                        .accessibilityIdentifier("movementFinishingRecording")
                } else {
                    LiveSignalChart(monitor: monitor)
                        .frame(height: 40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("movementLiveRhythm")
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, usesCompactHeader ? 4 : 8)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if countdown == nil, let recorder {
                    RecordingProgressView(recorder: recorder, stopCondition: stopCondition, compact: true)
                }
                controls()
            }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
        }
    }
}

private struct MovementCameraPreview: View {
    @ObservedObject var capture: VisionHandPoseCapture
    let taskType: MovementTaskType
    let side: BodySide
    let showsDetectionHints: Bool
    var isFinishingRecording = false

    var body: some View {
        if capture.isSessionRunning {
            CameraPreviewView(session: capture.session)
                .overlay { HandGuideOverlay(capture: capture, taskType: taskType, side: side) }
                .overlay { ClippedWarningOverlay(capture: capture) }
                .overlay(alignment: .bottomLeading) {
                    if showsDetectionHints {
                        HandVisibilityHint(capture: capture)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showsDetectionHints {
                        HandDistanceHint(capture: capture)
                            .padding(8)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .padding(6)
                    }
                }
        } else {
            ProgressView(L10n(isFinishingRecording ? "Finishing recording…" : "Starting camera…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct RecordingProgressView: View {
    @ObservedObject var recorder: TrialRecorder
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stopCondition: StopCondition
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 8 : 16) {
            if !compact {
                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording)
                    .foregroundStyle(.tint)
            }

            if compact {
                if dynamicTypeSize.isAccessibilitySize {
                    progressLabel.font(.body.monospacedDigit())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("movementRecordingTimer")
                } else {
                    HStack {
                        Text(L10n("Recording…"))
                            .font(.headline)
                        Spacer()
                        progressLabel.font(.body.monospacedDigit())
                            .accessibilityIdentifier("movementRecordingTimer")
                    }
                }
            } else {
                Text(L10n("Recording…"))
                    .font(.title2.bold())
                progressLabel.font(.title3.monospacedDigit())
            }

            switch stopCondition.mode {
            case .repetitions:
                ProgressView(value: Double(min(recorder.liveCycleCount, stopCondition.targetReps)),
                             total: Double(stopCondition.targetReps))
            case .duration:
                let progress = max(0.0, min(recorder.elapsed, stopCondition.targetDuration))
                ProgressView(value: progress,
                             total: stopCondition.targetDuration)
            }
        }
        .padding(.horizontal)
    }

    private var progressLabel: Text {
        switch stopCondition.mode {
        case .repetitions:
            Text(String(format: L10n("%d / %d repetitions"), recorder.liveCycleCount, stopCondition.targetReps))
        case .duration:
            Text(String(format: L10n("%.1f / %.0f s"), min(recorder.elapsed, stopCondition.targetDuration), stopCondition.targetDuration))
        }
    }
}

// MARK: - Result screen

private struct MovementMedicationSelection: View {
    private enum Choice: String { case unanswered, takenAt, noneToday, unsure }

    @Binding var timing: MedicationTiming?
    var showsHeading = true
    @ObservedObject private var journal = JournalStore.shared

    private var suggestion: JournalEntry? {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-test-medication-journal") {
            return JournalEntry(date: Date().addingTimeInterval(-3600), type: .medication,
                                medicationName: "Test medication", medicationDose: "Test dose",
                                medicationEvent: .usual)
        }
        #endif
        return MedicationTiming.latestIntake(in: journal.entries, before: Date())
    }

    private var choice: Binding<Choice> {
        Binding(get: {
            guard let timing else { return .unanswered }
            switch timing.status {
            case .takenAt: return .takenAt
            case .noneToday: return .noneToday
            case .unsure: return .unsure
            }
        }, set: { selection in
            switch selection {
            case .unanswered: timing = nil
            case .takenAt: timing = MedicationTiming(status: .takenAt, takenAt: Date())
            case .noneToday: timing = MedicationTiming(status: .noneToday)
            case .unsure: timing = MedicationTiming(status: .unsure)
            }
        })
    }

    private var choiceTitleKey: String {
        switch choice.wrappedValue {
        case .unanswered: return "Not entered"
        case .takenAt: return "At a specific time"
        case .noneToday: return "None taken today"
        case .unsure: return "Not sure"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeading {
                Text(L10n("Last Parkinson's medication"))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Menu {
                Picker(L10n("Last Parkinson's medication"), selection: choice) {
                    Text(L10n("Not entered")).tag(Choice.unanswered)
                    Text(L10n("At a specific time")).tag(Choice.takenAt)
                    Text(L10n("None taken today")).tag(Choice.noneToday)
                    Text(L10n("Not sure")).tag(Choice.unsure)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 12) {
                    Text(L10n(choiceTitleKey))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
            .accessibilityLabel(L10n("Last Parkinson's medication"))
            .accessibilityValue(L10n(choiceTitleKey))
            .accessibilityIdentifier("movementMedicationChoice")

            if timing?.status == .takenAt {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n("Last dose"))
                    DatePicker(L10n("Last dose"), selection: Binding(get: {
                        timing?.takenAt ?? Date()
                    }, set: { date in
                        // A corrected time is manual, not the original journal entry.
                        timing = MedicationTiming(status: .takenAt, takenAt: date)
                    }), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("movementMedicationTime")
            }

            if let suggestion, timing == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Last intake in your journal"))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(suggestion.date, format: .dateTime.day().month().year().hour().minute())
                    if let name = suggestion.medicationName, !name.isEmpty {
                        Text([name, suggestion.medicationDose].compactMap { $0 }.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        timing = MedicationTiming(status: .takenAt, takenAt: suggestion.date,
                                                  journalEntryID: suggestion.id,
                                                  medicationName: suggestion.medicationName,
                                                  medicationDose: suggestion.medicationDose)
                    } label: {
                        Label(L10n("Confirm journal time"), systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 54)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("movementConfirmMedication")
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MovementMedicationSummary: View {
    let timing: MedicationTiming
    let recordedAt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch timing.status {
            case .takenAt:
                if let date = timing.takenAt {
                    Text(L10n("Last dose"))
                    Text(date, format: .dateTime.day().month().year().hour().minute())
                    if let seconds = timing.elapsedSeconds(at: recordedAt) {
                        Text(String(format: L10n("Time since last dose: %d min"), Int(seconds / 60)))
                    }
                }
            case .noneToday: Text(L10n("No medication taken today"))
            case .unsure: Text(L10n("Medication time: not sure"))
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("movementMedicationSummary")
    }
}

struct MovementTrialResultView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let trial: Trial
    var onSave: () -> Void
    var onDiscard: () -> Void
    var saveTitle: String = "Save"
    var discardTitle: String = "Retake"
    var onSaveAndFinish: (() -> Void)?
    var isSaving = false
    var videoMessage: String?
    var showsTrendsHint = false
    var recordingIsSaved = false
    @State private var confirmsRetake = false
    @State private var showsStudyInfo = false

    private var feedback: MovementRecordingFeedback { MovementRecordingFeedback(trial: trial) }

    var body: some View {
        Form {
            Section {
                Label {
                    Text(L10n(feedback.titleKey))
                } icon: {
                    Image(systemName: feedback == .captured ? "waveform" : "exclamationmark.circle")
                        .accessibilityHidden(true)
                }
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L10n(feedback.titleKey))
                    .accessibilityIdentifier("movementRecordingFeedback")
                Text(L10n(feedback.detailKey))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if recordingIsSaved {
                    Label(L10n("Recording saved automatically."), systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movementAutosaveStatus")
                }
                if showsTrendsHint {
                    Text(L10n(recordingIsSaved
                              ? "Open Trends using the chart button at the top right."
                              : "After saving, open Trends using the chart button at the top right."))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movementResultTrendsHint")
                }
                if let videoMessage {
                    Label(L10n(videoMessage), systemImage: "video")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movementVideoNotice")
                }
            }
            Section {
                LabeledContent(L10n("Task"), value: trial.taskType.displayName)
                LabeledContent(L10n("Hand"), value: trial.side.displayName)
                metricRow("Duration", MovementSignalAssessment(samples: trial.samples).hasPlottableSignal
                          ? String(format: L10n("%.1f s"), trial.samples.last?.t ?? 0) : L10n("Value unavailable"))
                    .accessibilityIdentifier("movementResultDuration")
            } header: {
                Text(L10n("Trial"))
            }

            if let timing = trial.medicationTiming {
                Section(L10n("Medication")) {
                    MovementMedicationSummary(timing: timing, recordedAt: trial.startedAt)
                }
            }

            Section {
                metricRow("Cycles", MovementSignalAssessment(samples: trial.samples).hasAnalysisInput
                          && trial.metrics.cycleCount >= 0 ? "\(trial.metrics.cycleCount)" : L10n("Value unavailable"))
                resultMetricRow("Speed", metric: .frequency)
                resultMetricRow("Mean amplitude", metric: .amplitude)
                resultMetricRow("Amplitude decrement", metric: .decrement)
                resultMetricRow("Rhythm variability", metric: .rhythm)
                resultMetricRow("Pauses", metric: .pauses)
                resultMetricRow("Onset latency", metric: .onset)
            } header: {
                Text(L10n("Metrics"))
            } footer: {
                Text(L10n("These values describe this recording only. They are not a clinical rating."))
            }

            if let angles = trial.displayedFingerTappingAngleMetrics {
                Section {
                    angleMetricRow("Opening angle", value: angles.meanOpeningAngleDegrees, unit: "°")
                    angleMetricRow("Angular speed", value: angles.meanAbsoluteAngularSpeedDegreesPerSecond, unit: "°/s")
                    angleMetricRow("Angle-based tapping rate", value: angles.meanRateHz, unit: L10n("Taps/second"))
                    angleMetricRow("Angle-based rhythm variability", value: angles.periodCV.map { $0 * 100 }, unit: "%")
                } header: {
                    Text(L10n("Tapping angles"))
                } footer: {
                    Text(L10n("Camera-view angles, not joint angles. Hand position affects these values."))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if trial.taskType == .fingerTap, trial.source == .camera, trial.fingerTappingAngle != nil {
                MovementStudyComparisonSection(trial: trial, onInfo: { showsStudyInfo = true })
            }

            Section {
                RawSignalPlotView(samples: trial.samples)
                    .frame(height: 180)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("movementResultSignal")
            } header: {
                Text(L10n("Signal"))
            } footer: {
                if MovementSignalAssessment(samples: trial.samples).hasPlottableSignal
                    && MovementSignalAssessment(samples: trial.samples,
                                                recordedDurationSeconds: trial.recordedDurationSeconds).hasGaps {
                    Text(L10n("Gaps mean no signal was captured during those intervals."))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("movementResultSignalGap")
                }
            }

        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button {
                    onSave()
                } label: {
                    Label(L10n(saveTitle), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("movementSaveContinue")
                if let onSaveAndFinish {
                    Button(action: onSaveAndFinish) {
                        Label(L10n("Save & Finish"), systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("movementSaveFinish")
                }
                Button {
                    confirmsRetake = true
                } label: {
                    Label(L10n(discardTitle), systemImage: "arrow.counterclockwise")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("movementRetake")
                if isSaving { ProgressView(L10n("Saving…")) }
            }
            .disabled(isSaving)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .alert(L10n("Retake this recording?"), isPresented: $confirmsRetake) {
            Button(L10n("Keep this result"), role: .cancel) {}
            Button(L10n("Retake"), role: .destructive) { onDiscard() }
        } message: {
            Text(L10n(recordingIsSaved
                      ? "Your saved recording stays until a new one is saved."
                      : "This unsaved recording will be replaced. Previously saved recordings stay."))
        }
        .navigationTitle(L10n("Result"))
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showsStudyInfo) { MovementStudyComparisonInfoView() }
    }

    private func angleMetricRow(_ label: String, value: Double?, unit: String) -> some View {
        metricRow(label, value.map {
            String(format: "%.1f", locale: Locale(identifier: AppSettings.shared.language.rawValue), $0) + " " + unit
        } ?? L10n("Value unavailable"))
        .accessibilityIdentifier("movementAngleMetric-\(label)")
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n(label)).foregroundStyle(.secondary)
                    Text(value)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent(L10n(label), value: value)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n(label))
        .accessibilityValue(value)
    }

    private func resultMetricRow(_ label: String, metric: TrendMetric) -> some View {
        metricRow(label, metric.availability(for: trial).value.map { metric.formatted($0) }
                  ?? L10n("Value unavailable"))
            .accessibilityIdentifier("movementResultMetric-\(metric.rawValue)")
    }
}

struct MovementStudyComparisonSection: View {
    let trial: Trial?
    var showsRecordingDate = false
    var onInfo: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Section {
            if let trial, let rate = trial.displayedFirstTenTappingRate {
                if showsRecordingDate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Latest available comparison")).foregroundStyle(.secondary)
                        Text(trial.startedAt, format: .dateTime.day().month().year().hour().minute())
                    }
                    .accessibilityIdentifier("movementStudyRecordingDate")
                }
                studyRateRow("Your first 10 taps", rate: rate, identifier: "movementStudyYourRate")
                studyRateRow("Study median", rate: FingerTappingStudyReference.medianRate(for: trial.side),
                             identifier: "movementStudyMedian")
            } else {
                Text(L10n("Study comparison unavailable for this recording."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movementStudyUnavailable")
            }
        } header: {
            HStack {
                Text(L10n("Study comparison"))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer()
                Button(action: onInfo) {
                    Image(systemName: "info.circle").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(L10n("About this study comparison"))
                .accessibilityIdentifier("movementStudyInfo")
            }
        } footer: {
            Text(L10n("For context, not a target or a clinical assessment."))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func studyRateRow(_ label: String, rate: Double, identifier: String) -> some View {
        let value = String(format: "%.2f", locale: Locale(identifier: AppSettings.shared.language.rawValue), rate)
            + " " + L10n("Taps/second")
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n(label)).foregroundStyle(.secondary)
                    Text(value)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LabeledContent(L10n(label), value: value)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n(label))
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}

struct MovementResearchComparisonView: View {
    let trial: Trial?
    @State private var showsInfo = false

    var body: some View {
        Form {
            MovementStudyComparisonSection(trial: trial, showsRecordingDate: true, onInfo: { showsInfo = true })
        }
        .navigationTitle(L10n("Research comparison"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsInfo) { MovementStudyComparisonInfoView() }
    }
}

struct MovementStudyComparisonInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n("Your rate uses the first 10 complete detected taps. The study median comes from 78 recordings of the same hand from people who reported no Parkinson's diagnosis."))
                    Text(L10n("The study requested ten taps and used a different camera and detection method. Our recording lasts 30 seconds. These values are not directly interchangeable or adjusted for age; the study median is not a healthy cutoff."))
                }
                Section {
                    Text("Islam et al., npj Digital Medicine (2023)")
                    Link(L10n("Read the study"), destination: URL(string: "https://doi.org/10.1038/s41746-023-00905-9")!)
                }
            }
            .navigationTitle(L10n("Study comparison"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n("Done")) { dismiss() }
                        .accessibilityIdentifier("movementStudyInfoDone")
                }
            }
        }
    }
}

struct RawSignalPlotView: View {
    let samples: [TimestampedSample]

    private var signal: MovementSignalAssessment { MovementSignalAssessment(samples: samples) }

    var body: some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let points = samples
                guard signal.hasPlottableSignal,
                      let tMin = points.first?.t,
                      let tMax = points.last?.t,
                      let vMin = points.map(\.value).min(),
                      let vMax = points.map(\.value).max(),
                      tMax > tMin else { return }

                let tRange = tMax - tMin
                let vRange = max(vMax - vMin, 0.001)
                let plotHeight = max(size.height - 8, 1)
                let topPadding: CGFloat = 4

                if vMin < 0 && vMax > 0 {
                    let zeroY = topPadding + plotHeight - CGFloat((0 - vMin) / vRange) * plotHeight
                    var zeroLine = Path()
                    zeroLine.move(to: CGPoint(x: 0, y: zeroY))
                    zeroLine.addLine(to: CGPoint(x: size.width, y: zeroY))
                    context.stroke(zeroLine, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
                }

                var path = Path()
                for (index, sample) in points.enumerated() {
                    let x = CGFloat((sample.t - tMin) / tRange) * size.width
                    let y = topPadding + plotHeight - CGFloat((sample.value - vMin) / vRange) * plotHeight
                    if index == 0 || sample.t - points[index - 1].t >= MovementSignalAssessment.gapWarningSeconds {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(.accentColor), lineWidth: 1.8)
            }
            .overlay {
                if !signal.hasPlottableSignal {
                    Text(L10n("No usable signal to display"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(String(format: L10n("%.1f s"), signal.hasPlottableSignal ? samples.first?.t ?? 0.0 : 0.0))
                Spacer()
                Text(String(format: L10n("%.1f s"), signal.hasPlottableSignal ? samples.last?.t ?? 0.0 : 0.0))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    NavigationStack { MovementTaskView() }
}

// MARK: - Guided session flow

///
/// Step-by-step movement session for home use.
///
/// The patient is taken through the complete UPDRS hand-movement protocol:
///   3.4 Finger tapping      – right, then left
///   3.5 Hand open/close       – right, then left
///   3.6 Pronation/supination  – right, then left
///
/// Before the first recording the patient picks the stimulation context
/// (baseline / before / after). That context is stored once for the whole
/// session and automatically colours the corresponding points in Trends.
///
struct MovementSessionFlowView: View {

    @AppStorage("patientID") private var patientID = ""
    @ObservedObject private var sessionStore = TaskSessionStore.shared

    // MARK: - Flow state

    private enum FlowPhase: Equatable {
        case intro
        case contextSelection
        case instruction(step: Int)
        case countdown(step: Int)
        case recording(step: Int)
        case analyzing
        case trialResult(Trial)
        case summary
    }

    /// Fixed clinical protocol: all three tasks, right hand first, then left.
    private let steps: [(task: MovementTaskType, side: BodySide)] = [
        (.fingerTap, .right),
        (.fingerTap, .left),
        (.handOpenClose, .right),
        (.handOpenClose, .left),
        (.pronationSupination, .right),
        (.pronationSupination, .left),
    ]

    @State private var phase: FlowPhase = .intro
    @State private var context: StimulationContext = .unspecified
    @State private var hasSelectedContext = false
    @State private var medicationTiming: MedicationTiming?
    @State private var currentStepIndex: Int = 0
    @State private var trials: [Trial] = []
    @State private var captureAttemptID = UUID()
    @State private var isGoingBack = false
    @State private var confirmsRecordingBack = false
    @State private var savedSession: MovementSession?
    @State private var isSaving = false
    @State private var showsSaveError = false
    @State private var hasFinishedSession = false
    @StateObject private var videoDraft = MovementVideoDraft()
    @State private var completedTrial: Trial?
    @State private var isFinishingRecording = false
    @State private var showsTaskInformation = false
    @State private var pendingSaveFinishes: Bool?
    @State private var attemptedAutomaticSaveID: UUID?
    @State private var savedVideoMessage: String?

    // MARK: - Per-trial recording machinery

    @State private var recorder: TrialRecorder?
    @State private var cameraCapture: VisionHandPoseCapture?
    @State private var watchCapture: WatchMotionCapture?
    @State private var syntheticSource: SyntheticCaptureSource?
    @State private var countdownTimer: Timer?
    @State private var countdownRemaining: Int = 3
    @State private var cameraError: String?
    @StateObject private var signalMonitor = LiveSignalMonitor()
    @State private var isCalibrating = false

    // MARK: - Computed helpers

    private var currentStep: (task: MovementTaskType, side: BodySide) {
        steps[currentStepIndex]
    }

    private var activeSignalSource: SignalSource {
        #if targetEnvironment(simulator)
        .synthetic
        #else
        currentStep.task.preferredSource
        #endif
    }

    private var usingCamera: Bool { activeSignalSource == .camera }
    private var usingWatch: Bool {
        #if DEBUG && targetEnvironment(simulator)
        // Exercise the disconnected Watch layout without physical hardware.
        if currentStep.task.preferredSource == .watchMotion,
           ProcessInfo.processInfo.arguments.contains("--ui-test-watch-layout") { return true }
        #endif
        return activeSignalSource == .watchMotion
    }
    private var usingSynthetic: Bool { activeSignalSource == .synthetic }
    private var canStartRecording: Bool {
        (!usingWatch || PhoneWC.shared.isWatchReachable) && cameraCapture == nil && watchCapture == nil
    }

    private var flowUsesCamera: Bool {
        #if targetEnvironment(simulator)
        #if DEBUG
        // UI tests can open setup; task recording still uses the synthetic source.
        ProcessInfo.processInfo.arguments.contains("--ui-test-calibration")
        #else
        false
        #endif
        #else
        steps.contains { $0.task.preferredSource == .camera }
        #endif
    }

    private var stopCondition: StopCondition { .thirtySec }

    private var progressText: String {
        String(format: L10n("Step %d of %d"), currentStepIndex + 1, steps.count)
    }

    private var isLastStep: Bool {
        currentStepIndex == steps.count - 1
    }

    // MARK: - Body

    private var showsPreview: Bool {
        switch phase {
        case .countdown, .recording: return true
        default:                     return false
        }
    }

    private var showsCameraRecordingLayout: Bool {
        if usingCamera { return true }
        #if DEBUG && targetEnvironment(simulator)
        return currentStep.task.preferredSource == .camera
            && ProcessInfo.processInfo.arguments.contains("--ui-test-recording-layout")
        #else
        return false
        #endif
    }

    private var cameraCountdown: Int? {
        if case .countdown = phase { return countdownRemaining }
        return nil
    }

    private var showsFlowBack: Bool {
        switch phase {
        case .intro, .trialResult, .summary: return false
        default: return true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                if showsCameraRecordingLayout, showsPreview {
                    CameraMovementRecordingView(
                        taskType: currentStep.task, side: currentStep.side, capture: cameraCapture,
                        monitor: signalMonitor, recorder: recorder, stopCondition: stopCondition,
                        countdown: cameraCountdown, progressText: progressText,
                        isFinishingRecording: isFinishingRecording
                    ) {
                        if case .recording = phase {
                            Button(role: .destructive) { requestRecordingStop() } label: {
                                Label(L10n(isFinishingRecording ? "Finishing recording…" : "Stop"), systemImage: "stop.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 54)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isFinishingRecording)
                        }
                    }
                    .disabled(isGoingBack || isSaving)
                } else {
                    Group {
                        switch phase {
                        case .intro:              introView
                        case .contextSelection:   contextSelectionView
                        case .instruction:        instructionView
                        case .countdown:          countdownView
                        case .recording:          recordingView
                        case .analyzing:          analyzingView
                        case .trialResult(let t): trialResultView(t)
                        case .summary:            summaryView
                        }
                    }
                    .disabled(isGoingBack || isSaving)
                }
            }
            .navigationTitle(L10n("Movement Test"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if showsFlowBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if case .recording = phase {
                                confirmsRecordingBack = true
                            } else {
                                goBackInFlow()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(L10n("Back"))
                        .accessibilityIdentifier("movementSessionBack")
                        .help(L10n("Back"))
                        .disabled(isGoingBack || isSaving)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MovementTrendView()
                    } label: {
                        Label(L10n("Trends"), systemImage: "chart.xyaxis.line")
                    }
                    .disabled(isSaving)
                }
            }
        }
        .alert(L10n("Stop this recording and go back?"), isPresented: $confirmsRecordingBack) {
            Button(L10n("Keep recording"), role: .cancel) {}
            Button(L10n("Stop and go back"), role: .destructive) { goBackInFlow() }
        }
        .alert(L10n("Recording not saved"), isPresented: $showsSaveError) {
            Button(L10n("OK"), role: .cancel) {}
            if videoDraft.url != nil, case .trialResult(let trial) = phase {
                Button(L10n("Save without video")) {
                    persistTrial(trial, finish: pendingSaveFinishes, includeVideo: false)
                }
            }
        } message: {
            Text(L10n("Please try saving again. This recording is still here."))
        }
        #if DEBUG && targetEnvironment(simulator)
        .onAppear {
            let arguments = ProcessInfo.processInfo.arguments
            if phase == .intro, arguments.contains("--ui-test-save-result"),
               arguments.contains("--ui-test-session-save") {
                // Isolated completed-recording fixture, including automatic local saving.
                context = .preStim
                hasSelectedContext = true
                let scenarioIndex = arguments.firstIndex(of: "--ui-test-recording-feedback")
                let scenario = scenarioIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                let samples: [TimestampedSample]
                switch scenario {
                case "missing": samples = []
                case "gaps": samples = [0.0, 0.1, 0.2, 10.0, 10.1, 10.2].map { .init(t: $0, value: sin($0)) }
                case "trailingGap": samples = (0...100).map { .init(t: Double($0) / 10, value: sin(Double($0) / 3)) }
                default: samples = (0...300).map { .init(t: Double($0) / 10, value: sin(Double($0) / 3)) }
                }
                videoDraft.beginTake()
                let hasVideo = arguments.contains("--ui-test-private-video") && videoDraft.isVideoEnabledForTake
                let hasAngles = arguments.contains("--ui-test-angle-metrics")
                let angleFrameCount = arguments.contains("--ui-test-angle-brief") ? 120 : 600
                let angleRecording = hasAngles ? FingerTappingAngleRecording(samples: (0..<angleFrameCount).map {
                    let time = Double($0) / 60
                    return TimestampedAngleSample(t: time, degrees: 20 - 20 * cos(4 * .pi * time))
                }) : nil
                let trial = Trial(taskType: .fingerTap, side: .right, source: hasVideo || hasAngles ? .camera : .synthetic,
                    stopCondition: .thirtySec,
                    samples: samples,
                    metrics: MovementMetrics(cycleCount: scenario == "noCycles" ? 0 : 15, frequencyHz: 2, meanAmplitude: 0.2,
                        amplitudeDecrementSlope: 0, rhythmCV: 0.1, pauseCount: 0,
                        onsetLatencySec: 0.2, qualityIndex: scenario == "lowIndex" ? 0 : 0.8),
                    recordedDurationSeconds: scenario == "trailingGap" ? 30 : nil,
                    fingerTappingAngle: angleRecording,
                    fingerTappingAngleMetrics: angleRecording.flatMap { FingerTappingAngleAnalyzer.analyze($0) })
                if hasVideo {
                    Task { @MainActor in
                        do {
                            let raw = try await makeMovementVideoTestFixture()
                            let url = try await MovementFaceMasker.consume(raw) { _ in [] }
                            videoDraft.receive(url)
                            if arguments.contains("--ui-test-video-save-failure") {
                                try? FileManager.default.removeItem(at: url)
                            }
                        } catch { videoDraft.receive(nil) }
                        phase = .trialResult(trial)
                    }
                } else { phase = .trialResult(trial) }
            } else if phase == .intro, arguments.contains("--ui-test-watch-layout") {
                context = .preStim
                hasSelectedContext = true
                startInstruction(step: 4)
            }
        }
        #endif
        .onDisappear { handleFlowDisappearance() }
        .sheet(isPresented: $isCalibrating) {
            HandCalibrationView { isCalibrating = false }
        }
        .sheet(isPresented: $showsTaskInformation) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n("These tasks are adapted from hand-movement tests in MDS-UPDRS Part III, used by clinicians to assess movement in Parkinson's disease."))
                        Text(L10n("They measure speed, movement size and rhythm, including pauses or slowing."))
                        Text(L10n("This app records each hand for 30 seconds."))
                        Text(L10n("The recordings can help you follow changes in your movement. They complement a clinical examination, but do not provide an MDS-UPDRS score."))
                    }
                    .font(.body)
                    .padding()
                }
                .navigationTitle(L10n("About these tasks"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L10n("Done")) { showsTaskInformation = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Intro

    private var introView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.tint)

                VStack(spacing: 4) {
                    Text(L10n("Movement Session"))
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { showsTaskInformation = true } label: {
                        Image(systemName: "info.circle")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(L10n("About these tasks"))
                    .accessibilityIdentifier("movementSessionInfo")
                }

                Text(L10n("6 recordings, about 5–7 minutes. Take breaks whenever you need."))
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !trials.isEmpty {
                    Text(savedRecordingCountText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--ui-test-session-save") {
                    Text("sessions=\(sessionStore.sessions.count);trials=\(sessionStore.sessions.reduce(0) { $0 + $1.trials.count })")
                        .font(.caption2)
                        .accessibilityIdentifier("movementSavedTestCounts")
                }
                #endif

                VStack(alignment: .leading, spacing: 12) {
                    numberedTask(1, "Tap index finger on thumb")
                    numberedTask(2, "Open and close your fist")
                    numberedTask(3, "Rotate forearm palm-up / palm-down")
                }

                if flowUsesCamera {
                    if HandCalibrationStore.shared.isCalibrated {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(L10n("Hand size calibrated"))
                                .foregroundStyle(.green)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(L10n("Recalibrate")) {
                                isCalibrating = true
                            }
                        }
                    } else {
                        Button {
                            isCalibrating = true
                        } label: {
                            Label(L10n("Calibrate hand size"), systemImage: "hand.raised")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    Text(L10n("For each new session, we recommend recalibrating."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                hasSelectedContext = !trials.isEmpty
                phase = .contextSelection
            } label: {
                Label(L10n("Start"), systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
        }
    }

    private func numberedTask(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            Text(L10n(text))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Context selection

    private var contextSelectionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(L10n("When is this measurement?"))
                    .font(.title2.bold())
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 12) {
                    ForEach(StimulationContext.patientChoices) { c in
                        Button {
                            context = c
                            hasSelectedContext = true
                        } label: {
                            HStack(spacing: 12) {
                                Text(contextTitle(c)).font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: hasSelectedContext && context == c
                                      ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                            .padding(12)
                            .background(hasSelectedContext && context == c
                                        ? Color.accentColor.opacity(0.12) : Color(.systemGray6),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("movementContext-\(c.rawValue)")
                        .accessibilityAddTraits(hasSelectedContext && context == c ? .isSelected : [])
                        // Keep the tag consistent with recordings already accepted.
                        .disabled(!trials.isEmpty && context != c)
                    }
                }

                Divider()
                MovementMedicationSelection(timing: $medicationTiming)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                startInstruction(step: 0)
            } label: {
                Label(L10n("Continue"), systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasSelectedContext)
            .accessibilityIdentifier("movementContextContinue")
            .padding(.horizontal, 24).padding(.vertical, 12)
            .background(.bar)
        }
    }

    private func contextTitle(_ c: StimulationContext) -> String {
        L10n(c.titleKey)
    }

    // MARK: - Instruction

    private var instructionView: some View {
        ScrollView {
            instructionContent
                .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            instructionActions
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
        }
    }

    private var instructionContent: some View {
        let step = currentStep
        return VStack(spacing: 14) {
            Text(progressText)
                .font(.headline)
                .foregroundStyle(.secondary)

            if !trials.isEmpty {
                Text(savedRecordingCountText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 32)
            }

            if MovementDemonstrationClip.clip(task: step.task, side: step.side) == nil {
                Image(systemName: taskIcon(step.task))
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("movementInstructionTaskIcon")
            }

            Text(step.task.displayName)
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

            MovementDemonstrationView(taskType: step.task, side: step.side)
                .padding(.horizontal, 24)

            Text(taskInstruction(step.task))
                .font(.title3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title)
                    .scaleEffect(x: MovementRecordingGuidance(taskType: step.task, side: step.side).handIconHorizontalScale, y: 1)
                Text(L10n("\(step.side.rawValue.capitalized) hand"))
                    .font(.title2.bold())
            }

            if usingCamera {
                Text(L10n("Hold your hand in front of the camera so it fills the frame."))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
            } else if usingWatch {
                Text(L10n("Wear the watch on your \(step.side.rawValue) arm and keep the watch app open."))
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
            }

            if usingWatch {
                WatchPrerequisiteView()
                    .padding(.horizontal, 24)
            }
        }
    }

    private var instructionActions: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1.0)) { _ in
                Button {
                    startCountdown(step: currentStepIndex)
                } label: {
                    Label(L10n("Start Recording"), systemImage: "record.circle")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStartRecording)
                .accessibilityIdentifier("movementStartRecording")
            }

            Button {
                skipStep()
            } label: {
                Label(L10n("Skip this measurement"), systemImage: "forward.end")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
            .accessibilityIdentifier("movementSkipMeasurement")

            if !trials.isEmpty {
                Button { finishAcceptedFlow() } label: {
                    Label(L10n("Finish for now"), systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .accessibilityIdentifier("movementFinishForNow")
            }
        }
    }


    private func skipStep() {
        if isLastStep {
            finishAcceptedFlow()
        } else {
            currentStepIndex += 1
            startInstruction(step: currentStepIndex)
        }
    }

    private func taskIcon(_ task: MovementTaskType) -> String {
        switch task {
        case .fingerTap:         return "hand.tap.fill"
        case .handOpenClose:     return "hand.raised.fill"
        case .pronationSupination: return "rotate.3d"
        }
    }

    private func taskInstruction(_ task: MovementTaskType) -> String {
        switch task {
        case .fingerTap:
            return L10n("Tap your index finger on your thumb as fast and as big as possible.")
        case .handOpenClose:
            return L10n("Open and close your fist as fast and as fully as possible.")
        case .pronationSupination:
            return L10n("Rotate your forearm palm-up / palm-down as fast and as fully as possible.")
        }
    }

    // MARK: - Countdown

    private var countdownView: some View {
        VStack(spacing: 24) {
            // Top padding so content doesn't overlap the persistent preview overlay.
            if usingCamera { Color.clear.frame(height: 340) }
            if usingWatch  { Color.clear.frame(height: 120) }

            Text(progressText)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(currentStep.task.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if usingWatch {
                WatchStatusView(capture: watchCapture)
            }

            Spacer()

            Text(taskInstruction(currentStep.task))
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("\(countdownRemaining)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .contentTransition(.numericText())

            Spacer()
        }
        .padding(.horizontal)
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 24) {
            // Top padding so content doesn't overlap the persistent preview overlay.
            if usingCamera { Color.clear.frame(height: 340) }
            if usingWatch  { Color.clear.frame(height: 114) }

            Text(progressText)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(currentStep.task.displayName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("movementRecordingTask")

            if usingWatch {
                WatchStatusView(capture: watchCapture)
            }

            if let recorder {
                RecordingProgressView(recorder: recorder, stopCondition: stopCondition)
            }

            Button(role: .destructive) {
                requestRecordingStop()
            } label: {
                Label(L10n(isFinishingRecording ? "Finishing recording…" : "Stop"), systemImage: "stop.circle.fill")
                    .font(.headline)
            }
            .disabled(isFinishingRecording)
        }
        .padding(.horizontal)
        .padding(.top, 4)
    }

    // MARK: - Analyzing

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
            Text(L10n("Analysing movement…"))
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trial result

    private func trialResultView(_ trial: Trial) -> some View {
        VStack(spacing: 0) {
            Text(progressText)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            MovementTrialResultView(
                trial: trial,
                onSave: { acceptTrial(trial, finish: isLastStep) },
                onDiscard: { retakeTrial() },
                saveTitle: isLastStep ? "Save & Finish" : "Save & Continue",
                discardTitle: "Retake",
                onSaveAndFinish: isLastStep ? nil : { acceptTrial(trial, finish: true) },
                isSaving: isSaving,
                videoMessage: isSaved(trial) ? savedVideoMessageFor(trial) : videoDraft.messageKey,
                showsTrendsHint: true,
                recordingIsSaved: isSaved(trial)
            )
        }
        .task(id: trial.id) { automaticallySaveTrial(trial) }
    }

    private func isSaved(_ trial: Trial) -> Bool {
        savedSession?.trials.contains(where: { $0.id == trial.id }) == true
    }

    private func savedVideoMessageFor(_ trial: Trial) -> String? {
        switch sessionStore.videoPreparationStates[trial.id] {
        case .queued, .preparing: return "Video is being prepared. Find it later in Settings > Data."
        case .unavailable: return "Video not saved. Your measurement is saved."
        case nil:
            if sessionStore.sessions.contains(where: { $0.trials.contains(where: { $0.id == trial.id && $0.video != nil }) }) {
                return "Video saved in this app."
            }
            return savedVideoMessage
        }
    }

    private func automaticallySaveTrial(_ trial: Trial) {
        guard !isSaving, !isSaved(trial), attemptedAutomaticSaveID != trial.id else { return }
        attemptedAutomaticSaveID = trial.id
        persistTrial(trial, finish: nil)
    }

    private func acceptTrial(_ trial: Trial, finish: Bool, includeVideo: Bool = true) {
        guard !isSaving else { return }
        if isSaved(trial) {
            advanceAfterSavedTrial(trial, finish: finish)
        } else {
            persistTrial(trial, finish: finish, includeVideo: includeVideo)
        }
    }

    // A completed take is checkpointed locally; only an explicit Finish requests upload.
    private func persistTrial(_ trial: Trial, finish: Bool?, includeVideo: Bool = true) {
        guard !isSaving else { return }
        let session = savedSession ?? MovementSession(
            patientId: patientID.isEmpty ? "unset" : patientID,
            date: trial.startedAt, stimulationContext: context)
        pendingSaveFinishes = finish
        isSaving = true
        sessionStore.saveAcceptedTrial(trial, in: session,
            temporaryVideoURL: includeVideo ? videoDraft.url : nil,
            videoCaptureStartPTSSeconds: includeVideo ? videoDraft.captureStartPTSSeconds : nil,
            normalizedHandCrop: includeVideo ? videoDraft.normalizedHandCrop : nil,
            deferVideoProcessing: true) { result in
            isSaving = false
            switch result {
            case .success(let session):
                if session.trials.first(where: { $0.id == trial.id })?.video != nil {
                    savedVideoMessage = "Video saved in this app."
                } else if videoDraft.unavailable || (!includeVideo && videoDraft.url != nil) {
                    savedVideoMessage = "Video not saved. Your measurement is saved."
                } else {
                    savedVideoMessage = nil
                }
                videoDraft.discard()
                savedSession = session
                trials = session.trials
                if let finish { advanceAfterSavedTrial(trial, finish: finish) }
            case .failure:
                phase = .trialResult(trial)
                showsSaveError = true
            }
        }
    }

    private func advanceAfterSavedTrial(_ trial: Trial, finish: Bool) {
        guard case .trialResult(let current) = phase, current.id == trial.id else { return }
        cleanupAfterTrial()
        if finish {
            finishAcceptedFlow()
        } else {
            currentStepIndex += 1
            startInstruction(step: currentStepIndex)
        }
    }

    private func finishAcceptedFlow() {
        guard !isSaving else { return }
        if let savedSession, !hasFinishedSession {
            sessionStore.finishAcceptedSession(savedSession)
            hasFinishedSession = true
        }
        phase = .summary
    }

    private func retakeTrial() {
        guard !isSaving else { return }
        cleanupAfterTrial()
        startInstruction(step: currentStepIndex)
    }

    // MARK: - Summary

    private var summaryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: trials.isEmpty ? "minus.circle" : "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(trials.isEmpty ? Color.secondary : Color.green)

                Text(L10n(trials.isEmpty ? "No recordings saved" : "Recordings saved"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("movementSavedSummary")

                if let savedSession {
                    Text(savedRecordingCountText)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L10n(savedSession.completionLabelKey))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("movementSavedSetStatus")

                    Text(contextTitle(savedSession.stimulationContext))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    if trials.contains(where: { $0.source == .camera }) {
                        Text(L10n("Find your videos in Settings > Data."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(trials) { trial in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trial.taskType.displayName)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(trial.side.displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
        }
        .safeAreaInset(edge: .bottom) {
            Button { resetFlow() } label: {
                Label(L10n("Done"), systemImage: "checkmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("movementSummaryDone")
            .padding(.horizontal, 32)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Flow navigation

    private func goBackInFlow() {
        guard showsFlowBack, !isGoingBack, !isSaving else { return }
        let destination: FlowPhase
        switch phase {
        case .contextSelection:
            if trials.isEmpty {
                context = .unspecified
                hasSelectedContext = false
                medicationTiming = nil
            }
            destination = .intro
        case .instruction(let step):
            destination = step == 0 ? .contextSelection : .instruction(step: step - 1)
        default:
            destination = .instruction(step: currentStepIndex)
        }

        isGoingBack = true
        captureAttemptID = UUID()
        completedTrial = nil
        videoDraft.discard()
        let attemptID = captureAttemptID
        countdownTimer?.invalidate()
        countdownTimer = nil
        recorder?.onComplete = nil
        recorder?.finish()
        syntheticSource?.stop()
        cameraCapture?.onSample = nil
        cameraCapture?.onFrame = nil
        watchCapture?.onSample = nil
        // Keep the live preview attached until its capture session has actually stopped.
        let group = DispatchGroup()
        if let cameraCapture {
            group.enter()
            cameraCapture.stop { group.leave() }
        }
        if let watchCapture {
            group.enter()
            watchCapture.stop { group.leave() }
        }
        group.notify(queue: .main) {
            guard captureAttemptID == attemptID else { return }
            cameraCapture = nil
            watchCapture = nil
            syntheticSource = nil
            recorder = nil
            signalMonitor.reset()
            cameraError = nil
            if case .instruction(let step) = destination { currentStepIndex = step }
            phase = destination
            isGoingBack = false
        }
    }

    private func startInstruction(step: Int) {
        currentStepIndex = step
        phase = .instruction(step: step)
    }

    private func startCountdown(step: Int) {
        guard canStartRecording else { return }
        captureAttemptID = UUID()
        completedTrial = nil
        videoDraft.discard()
        let attemptID = captureAttemptID
        cameraError = nil
        signalMonitor.reset()

        if usingWatch {
            let capture = WatchMotionCapture()
            watchCapture = capture
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start { result in
                guard captureAttemptID == attemptID else { return }
                switch result {
                case .success:
                    beginCountdown(step: step)
                case .failure(let error):
                    cameraError = error.localizedDescription
                    cleanupAfterTrial()
                    phase = .instruction(step: step)
                }
            }
            return
        }

        if usingCamera {
            let capture = VisionHandPoseCapture()
            cameraCapture = capture
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start(taskType: currentStep.task) { result in
                guard captureAttemptID == attemptID else { capture.stop(); return }
                if case .failure(let error) = result {
                    cameraError = error.localizedDescription
                    cleanupAfterTrial()
                    phase = .instruction(step: step)
                } else {
                    beginCountdown(step: step)
                }
            }
            return
        }

        if usingSynthetic {
            let source = SyntheticCaptureSource()
            syntheticSource = source
        }

        beginCountdown(step: step)
    }

    private func beginCountdown(step: Int) {
        isFinishingRecording = false
        phase = .countdown(step: step)
        countdownRemaining = 3
        countdownTimer?.invalidate()

        let timer = Timer(timeInterval: 1.0, repeats: true) { timer in
            countdownRemaining -= 1
            if countdownRemaining <= 0 {
                timer.invalidate()
                startRecording(step: step)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer
    }


    private func requestRecordingStop() {
        guard !isFinishingRecording else { return }
        isFinishingRecording = true
        recorder?.finish()
    }

    private func finishRecordingCapture() {
        isFinishingRecording = true
        // Keep the preview mounted until capture stops. Completion, not a
        // SwiftUI-observed flag transition, owns this teardown.
        let cam = self.cameraCapture
        let watch = self.watchCapture
        let attemptID = captureAttemptID
        let group = DispatchGroup()
        if let cam {
            group.enter()
            cam.finishMeasurement { url, startPTS in
                if captureAttemptID == attemptID {
                    videoDraft.receive(url, captureStartPTSSeconds: startPTS, normalizedHandCrop: cam.completedHandCrop)
                    checkpointBeforeVideoProcessing(group: group, attemptID: attemptID)
                }
                else if let url { try? FileManager.default.removeItem(at: url) }
                group.leave()
            }
        }
        if let watch { group.enter(); watch.stop { group.leave() } }
        group.notify(queue: .main) {
            Task { @MainActor in
                guard self.captureAttemptID == attemptID else { return }
                self.cameraCapture = nil
                self.watchCapture = nil
                self.syntheticSource?.stop()
                if case .recording = self.phase {
                    self.phase = .analyzing
                }
                self.showCompletedTrialIfReady()
                print("[PERF] guided capture finalized")
            }
        }
    }

    private func checkpointBeforeVideoProcessing(group: DispatchGroup, attemptID: UUID) {
        guard cameraCapture != nil, let trial = completedTrial else { return }
        let session = savedSession ?? MovementSession(
            patientId: patientID.isEmpty ? "unset" : patientID,
            date: trial.startedAt, stimulationContext: context)
        group.enter()
        sessionStore.saveAcceptedTrial(trial, in: session, temporaryVideoURL: videoDraft.url,
            videoCaptureStartPTSSeconds: videoDraft.captureStartPTSSeconds,
            normalizedHandCrop: videoDraft.normalizedHandCrop,
            deferVideoProcessing: true) { result in
            if captureAttemptID == attemptID, case .success(let checkpoint) = result {
                savedSession = checkpoint
                trials = checkpoint.trials
                savedVideoMessage = videoDraft.unavailable ? "Video not saved. Your measurement is saved." : nil
                videoDraft.discard()
            }
            group.leave()
        }
    }

    private func startRecording(step: Int) {
        videoDraft.beginTake()
        isFinishingRecording = false
        let current = steps[step]
        let attemptID = captureAttemptID
        let medicationSnapshot = medicationTiming
        let r = TrialRecorder(taskType: current.task,
                              side: current.side,
                              source: activeSignalSource,
                              stopCondition: stopCondition,
                              measurementVersion: cameraCapture != nil ? MovementMeasurementVersion.camera
                                  : (watchCapture != nil ? MovementMeasurementVersion.watch : nil),
                              recordsFingerTappingAngles: cameraCapture != nil)
        r.onComplete = { trial in
            print("[PERF] flow received trial for step \(self.currentStepIndex + 1)")
            EventStore.shared.append(
                type: "PERF", tag: "flow_received_trial",
                message: "Flow received completed trial",
                details: ["step": "\(self.currentStepIndex + 1)",
                          "task": trial.taskType.rawValue,
                          "side": trial.side.rawValue])

            // Completion also handles an empty or very short recording.
            Task { @MainActor in
                guard self.captureAttemptID == attemptID else { return }
                self.completedTrial = trial.withMedicationTiming(medicationSnapshot)
                self.finishRecordingCapture()
            }
            EventStore.shared.append(
                type: "TASK", tag: "trial_completed",
                message: "Movement trial completed",
                details: ["task": trial.taskType.rawValue,
                          "side": trial.side.rawValue,
                          "cycles": "\(trial.metrics.cycleCount)",
                          "duration": String(format: "%.1f", trial.samples.last?.t ?? 0)])
        }
        recorder = r
        phase = .recording(step: step)

        if let cameraCapture {
            cameraCapture.onFrame = { frame, time in r.ingestCameraFrame(frame, at: time) }
            cameraCapture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
        } else if let watchCapture {
            watchCapture.onSample = { [signalMonitor] value, time in
                r.ingest(value: value, at: time)
                signalMonitor.ingest(value: value, at: time)
            }
        } else if let syntheticSource {
            let startSynthetic = {
                r.start()
                syntheticSource.start(preset: .parkinsonian, feeding: r,
                                      onSample: { [signalMonitor] value, time in
                    signalMonitor.ingest(value: value, at: time)
                })
            }
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--ui-test-delayed-recorder-start") {
                // Exercise Stop before capture starts, without inventing signal samples.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    guard captureAttemptID == attemptID else { return }
                    r.start()
                    if isFinishingRecording { r.finish() }
                }
            } else { startSynthetic() }
            #else
            startSynthetic()
            #endif
        }
        if let cameraCapture, videoDraft.isVideoEnabledForTake {
            cameraCapture.startRecordingToTemporaryFile { started in
                guard captureAttemptID == attemptID else { return }
                if !started { videoDraft.receive(nil) }
                r.start()
                if isFinishingRecording { r.finish() }
            }
        } else if cameraCapture != nil || watchCapture != nil { r.start() }

        EventStore.shared.append(
            type: "TASK", tag: "trial_started",
            message: "Movement trial started",
            details: ["task": current.task.rawValue,
                      "side": current.side.rawValue,
                      "source": activeSignalSource.rawValue,
                      "mode": stopCondition.mode.rawValue,
                      "videoRequested": "\(cameraCapture != nil && videoDraft.isVideoEnabledForTake)"])
    }

    private func showCompletedTrialIfReady() {
        guard cameraCapture == nil, watchCapture == nil, let completedTrial else { return }
        phase = .trialResult(completedTrial)
        automaticallySaveTrial(completedTrial)
    }

    private func cleanupAfterTrial() {
        captureAttemptID = UUID()
        completedTrial = nil
        videoDraft.discard()
        isGoingBack = false
        countdownTimer?.invalidate()
        countdownTimer = nil
        cameraCapture?.stop()
        cameraCapture = nil
        watchCapture?.stop()
        watchCapture = nil
        syntheticSource?.stop()
        syntheticSource = nil
        signalMonitor.reset()
        recorder?.onComplete = nil
        if recorder?.isRecording == true { recorder?.finish() }
        recorder = nil
    }

    private func handleFlowDisappearance() {
        guard !isSaving else { return }
        switch phase {
        case .trialResult(let trial):
            automaticallySaveTrial(trial)
        case .countdown, .recording:
            cleanupAfterTrial()
            phase = .instruction(step: currentStepIndex)
        default:
            // Navigation to a video, Trends, or another tab is not a new session.
            break
        }
    }

    private var savedRecordingCountText: String {
        String(format: L10n("Saved recordings: %d / %d"), trials.count, steps.count)
    }

    private func resetFlow() {
        trials.removeAll()
        savedSession = nil
        hasFinishedSession = false
        attemptedAutomaticSaveID = nil
        savedVideoMessage = nil
        pendingSaveFinishes = nil
        showsSaveError = false
        currentStepIndex = 0
        context = .unspecified
        hasSelectedContext = false
        medicationTiming = nil
        phase = .intro
    }
}

// MARK: - Watch status helper

private struct WatchStatusView: View {
    let capture: WatchMotionCapture?

    var body: some View {
        HStack {
            Image(systemName: capture?.isReceiving == true
                  ? "applewatch.radiowaves.left.and.right"
                  : "applewatch.slash")
            Text(capture?.isReceiving == true
                 ? "Watch connected"
                 : "Waiting for watch…")
        }
        .font(.callout.bold())
        .foregroundStyle(capture?.isReceiving == true ? .green : .orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - One-time hand scale calibration

private struct HandCalibrationView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var capture = VisionHandPoseCapture()
    @State private var gate = HandCalibrationQualityGate()
    @State private var showsIntroduction = true
    @State private var isActive = true
    @State private var isStarting = false
    @State private var isFinishing = false
    @State private var cameraPaused = false
    @State private var cameraError: VisionHandPoseCapture.CaptureError?
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    let onComplete: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n("Hand calibration"))
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    Button(L10n("Cancel")) { close(save: false) }
                        .frame(minHeight: 44)
                        .disabled(isFinishing)
                }

                if showsIntroduction {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 88))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                        .padding(.vertical, 24)
                    instruction("A quick camera check before your tests.")
                    instruction("Keep your phone still. Show your open hand.")
                    Text(L10n("Either hand is fine"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let cameraError {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    instruction(cameraErrorTitle(cameraError))
                    if case .permissionDenied = cameraError {
                        instruction("Allow camera access in Settings.")
                    }
                } else if gate.phase == .complete && !capture.isSessionRunning {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(L10n("Hand calibration complete"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(L10n("Camera check passed"), systemImage: "checkmark.shield")
                        .foregroundStyle(.green)
                    instruction("Keep the same hand distance during your tests.")
                } else {
                    instruction("Open your hand inside the guide. Face your palm toward the camera.")
                    if capture.isSessionRunning {
                        CalibrationCameraPreview(session: capture.session)
                            .frame(width: 180, height: 320)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                CalibrationPositionGuide(isReady: gate.guidance == .ready)
                                    .allowsHitTesting(false)
                            }
                            .accessibilityLabel(L10n("Hand camera preview"))
                    } else {
                        ProgressView(L10n("Starting camera…"))
                            .frame(height: 120)
                    }

                    if gate.phase == .countdown {
                        Text("\(gate.countdown)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(height: 72)
                            .accessibilityLabel(String(format: L10n("Starting in %d"), gate.countdown))
                        instruction("Keep your hand still")
                    } else if gate.phase == .collecting {
                        Label(L10n("Checking camera setup…"), systemImage: "camera")
                            .font(.headline)
                        ProgressView(value: gate.progress)
                        instruction("Keep your hand still")
                    } else if gate.phase == .retry {
                        Label(L10n("Let's try again"), systemImage: "exclamationmark.circle")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        instruction(guidanceText)
                    } else if gate.phase == .complete {
                        ProgressView(L10n("Camera check passed"))
                    } else {
                        Label(L10n(guidanceText), systemImage: gate.isReady ? "checkmark.circle" : "viewfinder")
                            .font(.headline)
                            .foregroundStyle(gate.isReady ? Color.green : Color.primary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if showsIntroduction {
                    primaryButton("Continue", icon: "arrow.right") {
                        showsIntroduction = false
                        startCamera()
                    }
                } else if let cameraError {
                    if case .permissionDenied = cameraError {
                        primaryButton("Open Settings", icon: "gearshape") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    } else {
                        primaryButton("Try again", icon: "arrow.counterclockwise") { startCamera() }
                    }
                } else if gate.phase == .complete {
                    primaryButton("Continue", icon: "arrow.right", enabled: !capture.isSessionRunning) {
                        close(save: true)
                    }
                    Button(L10n("Try again")) { retry() }
                        .frame(minHeight: 44)
                        .disabled(capture.isSessionRunning || isFinishing)
                } else if gate.phase == .retry {
                    primaryButton("Try again", icon: "arrow.counterclockwise") { retry() }
                } else {
                    primaryButton("Start check", icon: "camera", enabled: gate.isReady && capture.isSessionRunning) {
                        gate.start(frame: capture.calibrationFrame, now: ProcessInfo.processInfo.systemUptime)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial)
        }
        .onReceive(capture.$calibrationFrame) { frame in updateQuality(frame: frame) }
        .onReceive(ticker) { _ in updateQuality(frame: capture.calibrationFrame) }
        .onChange(of: gate.phase) { _, phase in
            if phase == .complete { capture.stop() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard !showsIntroduction, gate.phase != .complete, !isFinishing else { return }
            if phase != .active, capture.isSessionRunning {
                cameraPaused = true
                gate.reset()
                capture.stop()
            } else if phase == .active, cameraPaused || cameraError != nil {
                cameraPaused = false
                startCamera()
            }
        }
        .onDisappear {
            isActive = false
            capture.stop()
        }
    }

    private var guidanceText: String {
        switch gate.guidance {
        case .showHand: return "Show your open hand"
        case .wholeHand: return "Keep your wrist and all fingers visible"
        case .openHand: return "Open your hand. Show all five fingers."
        case .faceCamera: return "Face your palm toward the camera"
        case .insideGuide: return "Keep your whole hand inside the guide"
        case .closer: return "Move your hand closer"
        case .farther: return "Move your hand farther away"
        case .holdStill: return "Keep your hand still"
        case .ready: return "Hand in position"
        case .retry: return "Keep your phone and hand still, then try again."
        }
    }

    private func instruction(_ key: String) -> some View {
        Text(L10n(key))
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    private func primaryButton(_ key: String, icon: String, enabled: Bool = true,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(L10n(key), systemImage: icon)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled || isFinishing)
    }

    private func cameraErrorTitle(_ error: VisionHandPoseCapture.CaptureError) -> String {
        switch error {
        case .permissionDenied: return "Camera access is off"
        case .noCamera: return "Camera unavailable"
        }
    }

    private func startCamera() {
        guard isActive, !isStarting, !isFinishing else { return }
        isStarting = true
        cameraError = nil
        gate.reset()
        capture.tracksCalibration = true
        capture.start(taskType: .fingerTap) { [self] result in
            isStarting = false
            guard isActive, !isFinishing else { capture.stop(); return }
            switch result {
            case .success:
                if scenePhase != .active {
                    cameraPaused = true
                    capture.stop()
                }
            case .failure(let err):
                cameraError = err
            }
        }
    }

    private func updateQuality(frame: HandCalibrationFrame?) {
        guard isActive, !isFinishing, !showsIntroduction, cameraError == nil,
              capture.isSessionRunning, scenePhase == .active else { return }
        gate.update(frame: frame, now: ProcessInfo.processInfo.systemUptime)
    }

    private func retry() {
        gate.reset()
        if !capture.isSessionRunning { startCamera() }
    }

    private func close(save: Bool) {
        guard isActive, !isFinishing else { return }
        if save {
            guard gate.phase == .complete, let result = gate.result else { return }
            HandCalibrationStore.shared.set(scale: result.scale)
        }
        isFinishing = true
        capture.stop { [self] in
            guard isActive else { return }
            onComplete()
        }
    }
}

/// The same normalized target zone is used by the pose check and the portrait preview.
struct CalibrationPositionGuide: View {
    let isReady: Bool

    var body: some View {
        GeometryReader { geometry in
            let zone = HandCalibrationPose.guideRect
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isReady ? Color.green : Color.orange,
                              style: StrokeStyle(lineWidth: 2.5, dash: [7, 6]))
                .frame(width: geometry.size.width * zone.width, height: geometry.size.height * zone.height)
                .position(x: geometry.size.width * zone.midX, y: geometry.size.height * (1 - zone.midY))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shows the complete portrait feed for calibration without changing task previews.
private struct CalibrationCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> CameraPreviewView.PreviewUIView {
        let view = CameraPreviewView.PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        if let connection = view.previewLayer.connection {
            if #available(iOS 17.0, *) {
                connection.videoRotationAngle = 90
            } else {
                connection.videoOrientation = .portrait
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: CameraPreviewView.PreviewUIView, context: Context) {}
}

#Preview {
    MovementSessionFlowView()
}
