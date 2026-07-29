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

    // Recording machinery
    @State private var recorder: TrialRecorder?
    @State private var cameraCapture: VisionHandPoseCapture?
    @State private var watchCapture: WatchMotionCapture?
    @State private var countdownTimer: Timer?
    @State private var cameraError: String?
    @StateObject private var signalMonitor = LiveSignalMonitor()
    @State private var isCalibrating = false

    private var usingCamera: Bool { activeSignalSource == .camera }
    private var usingWatch: Bool { activeSignalSource == .watchMotion }

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
                        onDiscard: { phase = .setup }
                    )
                }
            }

            // Persistent camera preview: shown during countdown + recording only.
            // Lives outside the phase-switch so SwiftUI never tears it down.
            if usingCamera, let cc = cameraCapture, showsPreview, cc.isSessionRunning {
                VStack(spacing: 4) {
                    CameraPreviewView(session: cc.session)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            HandGuideOverlay(capture: cc, taskType: taskType, side: side)
                        }
                        .overlay {
                            ClippedWarningOverlay(capture: cc)
                        }
                        .overlay(alignment: .bottomLeading) {
                            HandVisibilityHint(capture: cc)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding(6)
                        }
                        .overlay(alignment: .bottomTrailing) {
                            HandDistanceHint(capture: cc)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding(6)
                        }
                    // TODO: Replace placeholder with VideoPlayer(videoURL) once assets are ready.
                    MovementVideoPlaceholder(taskType: taskType)
                        .frame(height: 80)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    // Live signal chart — shows exactly what the analyzer sees.
                    LiveSignalChart(monitor: signalMonitor)
                        .frame(height: 40)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                .padding(.top, 40)
            }
            // Persistent watch signal chart: same idea as the camera preview.
            else if usingWatch, let wc = watchCapture, showsPreview {
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
        .navigationTitle("Movement Test")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: recorder?.isRecording) { _, isRec in
            if isRec == false, case .recording = phase {
                phase = .analyzing
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    MovementTrendView()
                } label: {
                    Label("Trends", systemImage: "chart.xyaxis.line")
                }
            }
        }
        .onDisappear { cancelEverything() }
        .sheet(isPresented: $isCalibrating) {
            HandCalibrationView { isCalibrating = false }
        }
    }

    // MARK: - Setup

    private var setupView: some View {
        Form {
            Section("Task") {
                Picker("Movement", selection: $taskType) {
                    ForEach(MovementTaskType.allCases) { t in
                        Text("\(t.rawValue)  \(t.displayName)").tag(t)
                    }
                }
                Picker("Hand", selection: $side) {
                    Text("Left").tag(BodySide.left)
                    Text("Right").tag(BodySide.right)
                }
                .pickerStyle(.segmented)
            }

            Section("Protocol") {
                LabeledContent("Stop after", value: "10 repetitions")
            }

            Section("Context") {
                Picker("Relative to stimulation", selection: $context) {
                    ForEach(StimulationContext.allCases) { c in
                        Text(contextLabel(c)).tag(c)
                    }
                }
            }

            Section {
                if usingCamera {
                    Text("This task uses the front camera to track your hand. No video is stored — only movement measurements.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if usingWatch {
                    Text("Wear the watch on the tested arm and keep the vCRGlove watch app open during the recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sensor")
            }

            if usingCamera {
                Section("Calibration") {
                    if HandCalibrationStore.shared.isCalibrated {
                        HStack {
                            Text("Hand scale calibrated")
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Recalibrate") {
                                isCalibrating = true
                            }
                        }
                    } else {
                        Button {
                            isCalibrating = true
                        } label: {
                            Label("Calibrate hand size", systemImage: "hand.raised")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section {
                Button {
                    startCountdown()
                } label: {
                    Label("Start", systemImage: "record.circle")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
            } footer: {
                if let cameraError {
                    Text(cameraError).foregroundStyle(.red)
                }
            }
        }
    }

    private func contextLabel(_ c: StimulationContext) -> String {
        switch c {
        case .baseline:    return "Baseline (before any stimulation)"
        case .preStim:     return "Before session"
        case .postStim:    return "After session"
        case .unspecified: return "Not specified"
        }
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
            Button("Cancel", role: .cancel) { cancelEverything() }
        }
    }

    private var taskInstruction: String {
        switch taskType {
        case .fingerTap:
            return "Tap your index finger on your thumb as fast and as big as possible."
        case .handOpenClose:
            return "Open and close your fist as fast and as fully as possible."
        case .pronationSupination:
            return "Rotate your forearm palm-up / palm-down as fast and as fully as possible."
        }
    }

    private func startCountdown() {
        cameraError = nil
        if usingWatch {
            // Start the watch stream during the countdown so the user can
            // verify the connection + signal before the recording begins.
            let capture = WatchMotionCapture()
            watchCapture = capture
            signalMonitor.reset()
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start { result in
                if case .failure(let error) = result {
                    cameraError = error.localizedDescription
                    cancelEverything()
                }
            }
        }
        if usingCamera {
            // Warm the camera up during the countdown so recording starts with
            // live frames (otherwise startup time inflates onset latency).
            let capture = VisionHandPoseCapture()
            cameraCapture = capture
            signalMonitor.reset()
            // During the countdown: feed the monitor only, so the user can
            // check signal quality before the recording starts.
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start(taskType: taskType) { result in
                if case .failure(let error) = result {
                    cameraError = error.localizedDescription
                    cancelEverything()
                }
            }
        }
        phase = .countdown(3)
        countdownTimer?.invalidate()
        var remaining = 3
        let t = Timer(timeInterval: 1.0, repeats: true) { timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                startRecording()
            } else {
                phase = .countdown(remaining)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    // MARK: - Analyzing (shown between recording end and result)

    private var analyzingView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.6)
            Text("Analysing movement…")
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
            if let recorder {
                RecordingProgressView(recorder: recorder,
                                      stopCondition: stopCondition)
            }
            Button(role: .destructive) {
                recorder?.finish()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.headline)
            }
        }
        .padding()
    }

    private var stopCondition: StopCondition { .thirtySec }

    private func startRecording() {
        let r = TrialRecorder(taskType: taskType,
                              side: side,
                              source: activeSignalSource,
                              stopCondition: stopCondition)
        r.onComplete = { trial in
            let cam = cameraCapture
            let watch = watchCapture
            cameraCapture = nil
            watchCapture = nil
            Task.detached(priority: .userInitiated) {
                cam?.stop()
                watch?.stop()
            }
            phase = .result(trial)
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
        r.start()
        if let cameraCapture {
            cameraCapture.onSample = { [signalMonitor] value, time in
                r.ingest(value: value, at: time)
                signalMonitor.ingest(value: value, at: time)
            }
        } else if let watchCapture {
            watchCapture.onSample = { [signalMonitor] value, time in
                r.ingest(value: value, at: time)
                signalMonitor.ingest(value: value, at: time)
            }
        }
        EventStore.shared.append(
            type: "TASK", tag: "trial_started",
            message: "Movement trial started",
            details: ["task": taskType.rawValue,
                      "side": side.rawValue,
                      "source": activeSignalSource.rawValue,
                      "mode": stopCondition.mode.rawValue])
    }

    // MARK: - Save / cleanup

    private func save(_ trial: Trial) {
        let session = MovementSession(
            patientId: patientID.isEmpty ? "unset" : patientID,
            stimulationContext: context,
            trials: [trial]
        )
        TaskSessionStore.shared.add(session)
        phase = .setup
    }

    private func cancelEverything() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        cameraCapture?.stop()
        cameraCapture = nil
        watchCapture?.stop()
        watchCapture = nil
        signalMonitor.reset()
        recorder?.onComplete = nil
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
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
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
                    // Mirror the silhouette for the left hand so it matches the user's own hand.
                    .scaleEffect(x: side == .left ? -1 : 1, y: 1)
                    .position(x: zone.midX, y: zone.midY)

                if !good {
                    Text("Place your \(side == .left ? "left" : "right") hand here")
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
        Label(capture.isReceiving ? "Watch connected — receiving motion"
                                  : "Waiting for watch… open the watch app",
              systemImage: capture.isReceiving ? "applewatch.radiowaves.left.and.right" : "applewatch.slash")
            .font(.caption.bold())
            .foregroundStyle(capture.isReceiving ? .green : .orange)
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
                    Label("Keep your whole hand in the frame!", systemImage: "exclamationmark.triangle.fill")
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
            guard samples.count >= 2 else { return }

            let tMax = samples.last!.t
            let tMin = tMax - monitor.windowSec
            let values = samples.map(\.value)
            let vMin = values.min()!
            let vMax = values.max()!
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
                Text("Waiting for signal…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Live progress subview

struct RecordingProgressView: View {
    @ObservedObject var recorder: TrialRecorder
    let stopCondition: StopCondition

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording)
                .foregroundStyle(.tint)

            Text("Recording…")
                .font(.title2.bold())

            switch stopCondition.mode {
            case .repetitions:
                Text("\(recorder.liveCycleCount) / \(stopCondition.targetReps) repetitions")
                    .font(.title3.monospacedDigit())
                ProgressView(value: Double(min(recorder.liveCycleCount, stopCondition.targetReps)),
                             total: Double(stopCondition.targetReps))
            case .duration:
                Text(String(format: "%.1f / %.0f s", min(recorder.elapsed, stopCondition.targetDuration), stopCondition.targetDuration))
                    .font(.title3.monospacedDigit())
                let progress = max(0.0, min(recorder.elapsed, stopCondition.targetDuration))
                ProgressView(value: progress,
                             total: stopCondition.targetDuration)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Result screen

struct MovementTrialResultView: View {
    let trial: Trial
    var onSave: () -> Void
    var onDiscard: () -> Void
    var saveTitle: String = "Save"
    var discardTitle: String = "Discard"

    var body: some View {
        Form {
            Section {
                LabeledContent("Task", value: "\(trial.taskType.rawValue) \(trial.taskType.displayName)")
                LabeledContent("Hand", value: trial.side.rawValue.capitalized)
                LabeledContent("Duration", value: String(format: "%.1f s", trial.samples.last?.t ?? 0))
            } header: {
                Text("Trial")
            }

            Section {
                metricRow("Cycles", "\(trial.metrics.cycleCount)")
                metricRow("Speed", String(format: "%.2f Hz", trial.metrics.frequencyHz))
                metricRow("Mean amplitude", String(format: "%.3f", trial.metrics.meanAmplitude))
                metricRow("Amplitude decrement", String(format: "%.3f /cycle", trial.metrics.amplitudeDecrementSlope))
                metricRow("Rhythm variability", String(format: "%.2f", trial.metrics.rhythmCV))
                metricRow("Pauses", "\(trial.metrics.pauseCount)")
                metricRow("Onset latency", String(format: "%.2f s", trial.metrics.onsetLatencySec))
            } header: {
                Text("Metrics")
            } footer: {
                Text("These values describe this recording only. They are not a clinical rating.")
            }

            Section {
                Gauge(value: trial.metrics.qualityIndex) {
                    Text("Movement quality (heuristic)")
                }
                .gaugeStyle(.accessoryLinear)
                .tint(Gradient(colors: [.red, .orange, .green]))
            } footer: {
                Text("Heuristic 0–1 index for personal trends — not a validated UPDRS score.")
            }

            Section {
                Button {
                    onSave()
                } label: {
                    Label(saveTitle, systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Text(discardTitle)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Result")
        .navigationBarBackButtonHidden(true)
    }

    private func metricRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label, value: value)
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
    @State private var currentStepIndex: Int = 0
    @State private var trials: [Trial] = []

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
    private var usingWatch: Bool   { activeSignalSource == .watchMotion }
    private var usingSynthetic: Bool { activeSignalSource == .synthetic }

    private var flowUsesCamera: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        steps.contains { $0.task.preferredSource == .camera }
        #endif
    }

    private var stopCondition: StopCondition { .thirtySec }

    private var progressText: String {
        "Step \(currentStepIndex + 1) of \(steps.count)"
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

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Group {
                    switch phase {
                    case .intro:              introView
                    case .contextSelection:   contextSelectionView
                    case .instruction:        instructionView
                    case .countdown:            countdownView
                    case .recording:            recordingView
                    case .analyzing:            analyzingView
                    case .trialResult(let t):   trialResultView(t)
                    case .summary:              summaryView
                    }
                }

                // Persistent camera preview: shown during countdown + recording,
                // exactly like the original single-task view.
                if usingCamera, let cc = cameraCapture, showsPreview, cc.isSessionRunning {
                    VStack(spacing: 4) {
                        CameraPreviewView(session: cc.session)
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay { HandGuideOverlay(capture: cc, taskType: currentStep.task, side: currentStep.side) }
                            .overlay { ClippedWarningOverlay(capture: cc) }

                        // TODO: Replace placeholder with VideoPlayer(videoURL) once assets are ready.
                        MovementVideoPlaceholder(taskType: currentStep.task)
                            .frame(height: 80)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                        LiveSignalChart(monitor: signalMonitor)
                            .frame(height: 40)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(.horizontal)
                    .padding(.top, 40)
                }
            }
            .navigationTitle("Movement Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MovementTrendView()
                    } label: {
                        Label("Trends", systemImage: "chart.xyaxis.line")
                    }
                }
            }
        }
        .onChange(of: recorder?.isRecording) { oldIsRec, newIsRec in
            print("[PERF] isRecording changed from \(String(describing: oldIsRec)) to \(String(describing: newIsRec))")
            // Only switch to .analyzing when the recorder actually stopped recording.
            // Reassigning a fresh recorder (nil -> false or false -> false) must NOT trigger this.
            if oldIsRec == true, newIsRec == false, case .recording = phase {
                print("[PERF] stopping hardware before .analyzing")
                // Stop the camera/watch BEFORE the preview overlay disappears. If the
                // AVCaptureSession is still running when the preview layer is torn down,
                // the main thread blocks until the session stops (~9 s hang).
                let cam = self.cameraCapture
                let watch = self.watchCapture
                Task.detached(priority: .userInitiated) {
                    let group = DispatchGroup()
                    if let cam { group.enter(); cam.stop { group.leave() } }
                    if let watch { group.enter(); watch.stop { group.leave() } }
                    group.notify(queue: .main) {
                        self.cameraCapture = nil
                        self.watchCapture = nil
                        if case .recording = self.phase {
                            self.phase = .analyzing
                        }
                        print("[PERF] hardware stopped; phase now \(String(describing: self.phase))")
                    }
                }
            }
        }
        .onDisappear { cancelEverything() }
        .sheet(isPresented: $isCalibrating) {
            HandCalibrationView { isCalibrating = false }
        }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            Text("Movement Session")
                .font(.largeTitle.bold())

            Text("We will guide you through 6 short hand recordings. It takes about 2 minutes.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                bullet("Tap index finger on thumb")
                bullet("Open and close your fist")
                bullet("Rotate forearm palm-up / palm-down")
            }
            .padding(.horizontal, 32)

            if flowUsesCamera {
                if HandCalibrationStore.shared.isCalibrated {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Hand scale calibrated")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Recalibrate") {
                            isCalibrating = true
                        }
                    }
                    .padding(.horizontal, 32)
                } else {
                    Button {
                        isCalibrating = true
                    } label: {
                        Label("Calibrate hand size", systemImage: "hand.raised")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal, 32)
                }
            }

            Spacer()

            Button {
                phase = .contextSelection
            } label: {
                Label("Start", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.body)
        }
    }

    // MARK: - Context selection

    private var contextSelectionView: some View {
        VStack(spacing: 24) {
            Text("When is this measurement?")
                .font(.title2.bold())
                .padding(.top, 40)

            Text("Pick the context once. All 6 recordings of this session will be tagged the same way.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 12) {
                ForEach(StimulationContext.allCases) { c in
                    Button {
                        context = c
                        startInstruction(step: 0)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(contextTitle(c))
                                    .font(.headline)
                                Text(contextSubtitle(c))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if context == c {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(context == c ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private func contextTitle(_ c: StimulationContext) -> String {
        switch c {
        case .baseline:    return "Baseline"
        case .preStim:     return "Before stimulation"
        case .postStim:    return "After stimulation"
        case .unspecified: return "Not specified"
        }
    }

    private func contextSubtitle(_ c: StimulationContext) -> String {
        switch c {
        case .baseline:    return "No stimulation yet today"
        case .preStim:     return "Before your vCR / medication session"
        case .postStim:    return "After your vCR / medication session"
        case .unspecified: return "Use when none of the above applies"
        }
    }

    // MARK: - Instruction

    private var instructionView: some View {
        let step = currentStep
        return VStack(spacing: 24) {
            Spacer()

            Text(progressText)
                .font(.headline)
                .foregroundStyle(.secondary)

            Image(systemName: taskIcon(step.task))
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text(step.task.displayName)
                .font(.title.bold())

            Text(taskInstruction(step.task))
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Bitte führen Sie die Bewegung so schnell und so weit wie möglich aus.")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.title)
                    .scaleEffect(x: step.side == .left ? -1 : 1, y: 1)
                Text("\(step.side.rawValue.capitalized) hand")
                    .font(.title2.bold())
            }
            .padding(.top, 8)

            if usingCamera {
                Text("Hold your hand in front of the camera so it fills the frame.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if usingWatch {
                Text("Wear the watch on your \(step.side.rawValue) arm and keep the watch app open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    startCountdown(step: currentStepIndex)
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    skipStep()
                } label: {
                    Text("Skip this measurement")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    private func skipStep() {
        if isLastStep {
            phase = .summary
        } else {
            currentStepIndex += 1
            startInstruction(step: currentStepIndex)
        }
    }

    private func taskIcon(_ task: MovementTaskType) -> String {
        switch task {
        case .fingerTap:         return "hand.tap.fill"
        case .handOpenClose:     return "hand.raised.fill"
        case .pronationSupination: return "arrow.clockwise.circle.fill"
        }
    }

    private func taskInstruction(_ task: MovementTaskType) -> String {
        switch task {
        case .fingerTap:
            return "Tap your index finger on your thumb as fast and as big as possible."
        case .handOpenClose:
            return "Open and close your fist as fast and as fully as possible."
        case .pronationSupination:
            return "Rotate your forearm palm-up / palm-down as fast and as fully as possible."
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

            if usingWatch {
                WatchStatusView(capture: watchCapture)
            }

            if let recorder {
                RecordingProgressView(recorder: recorder, stopCondition: stopCondition)
            }

            Button(role: .destructive) {
                recorder?.finish()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .font(.headline)
            }
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
            Text("Analysing movement…")
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
                onSave: { acceptTrial(trial) },
                onDiscard: { retakeTrial() },
                saveTitle: isLastStep ? "Use & Finish" : "Use & Continue",
                discardTitle: "Retake"
            )
        }
    }

    private func acceptTrial(_ trial: Trial) {
        trials.append(trial)
        cleanupAfterTrial()
        if isLastStep {
            phase = .summary
        } else {
            currentStepIndex += 1
            startInstruction(step: currentStepIndex)
        }
    }

    private func retakeTrial() {
        cleanupAfterTrial()
        startInstruction(step: currentStepIndex)
    }

    // MARK: - Summary

    private var summaryView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("All done!")
                .font(.largeTitle.bold())

            Text("\(trials.count) recordings are ready to be saved as one session.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            List {
                Section("Recordings") {
                    ForEach(trials) { trial in
                        HStack {
                            Text(trial.taskType.displayName)
                            Spacer()
                            Text(trial.side.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    LabeledContent("Context", value: contextTitle(context))
                }
            }
            .scrollContentBackground(.hidden)
            .frame(height: 260)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    saveSession()
                } label: {
                    Label("Save Session", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(trials.isEmpty)

                Button(role: .destructive) {
                    resetFlow()
                } label: {
                    Text(trials.isEmpty ? "Start over" : "Discard")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Flow navigation

    private func startInstruction(step: Int) {
        currentStepIndex = step
        phase = .instruction(step: step)
    }

    private func startCountdown(step: Int) {
        cameraError = nil
        signalMonitor.reset()

        if usingWatch {
            let capture = WatchMotionCapture()
            watchCapture = capture
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start { result in
                if case .failure(let error) = result {
                    cameraError = error.localizedDescription
                    cancelEverything()
                }
            }
        }

        if usingCamera {
            let capture = VisionHandPoseCapture()
            cameraCapture = capture
            capture.onSample = { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            }
            capture.start(taskType: currentStep.task) { result in
                if case .failure(let error) = result {
                    cameraError = error.localizedDescription
                    cancelEverything()
                }
            }
        }

        if usingSynthetic {
            let source = SyntheticCaptureSource()
            syntheticSource = source
            // The source will be started once the recorder is ready.
        }

        phase = .countdown(step: step)
        countdownRemaining = 3
        countdownTimer?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { timer in
            countdownRemaining -= 1
            if countdownRemaining <= 0 {
                timer.invalidate()
                startRecording(step: step)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        countdownTimer = t
    }

    private func startRecording(step: Int) {
        let current = steps[step]
        let r = TrialRecorder(taskType: current.task,
                              side: current.side,
                              source: activeSignalSource,
                              stopCondition: stopCondition)
        r.onComplete = { trial in
            print("[PERF] flow received trial for step \(self.currentStepIndex + 1)")
            EventStore.shared.append(
                type: "PERF", tag: "flow_received_trial",
                message: "Flow received completed trial",
                details: ["step": "\(self.currentStepIndex + 1)",
                          "task": trial.taskType.rawValue,
                          "side": trial.side.rawValue])

            // Hardware was already stopped when .analyzing began.
            Task { @MainActor in
                self.phase = .trialResult(trial)
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
        r.start()

        if let cameraCapture {
            cameraCapture.onSample = { [signalMonitor] value, time in
                r.ingest(value: value, at: time)
                signalMonitor.ingest(value: value, at: time)
            }
        } else if let watchCapture {
            watchCapture.onSample = { [signalMonitor] value, time in
                r.ingest(value: value, at: time)
                signalMonitor.ingest(value: value, at: time)
            }
        } else if let syntheticSource {
            syntheticSource.start(preset: .parkinsonian,
                                  feeding: r,
                                  onSample: { [signalMonitor] value, time in
                signalMonitor.ingest(value: value, at: time)
            })
        }

        EventStore.shared.append(
            type: "TASK", tag: "trial_started",
            message: "Movement trial started",
            details: ["task": current.task.rawValue,
                      "side": current.side.rawValue,
                      "source": activeSignalSource.rawValue,
                      "mode": stopCondition.mode.rawValue])
    }

    private func cleanupAfterTrial() {
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
        recorder = nil
    }

    private func cancelEverything() {
        cleanupAfterTrial()
        phase = .intro
    }

    private func saveSession() {
        let session = MovementSession(
            patientId: patientID.isEmpty ? "unset" : patientID,
            stimulationContext: context,
            trials: trials
        )
        TaskSessionStore.shared.add(session)
        resetFlow()
    }

    private func resetFlow() {
        trials.removeAll()
        currentStepIndex = 0
        context = .unspecified
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

/// Placeholder shown under the camera preview during movement tasks.
/// Swap in a `VideoPlayer` here once the instruction videos are ready.
private struct MovementVideoPlaceholder: View {
    let taskType: MovementTaskType

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.6))
            Text("Instruction video for \(taskType.displayName)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One-time hand scale calibration

private struct HandCalibrationView: View {
    @StateObject private var capture = VisionHandPoseCapture()
    @State private var progress: Double = 0
    @State private var samples: [Double] = []
    @State private var isCollecting = true
    @State private var error: String?

    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Hand calibration")
                .font(.largeTitle.bold())
            Text("Hold your hand steady in front of the camera for 2 seconds.")
                .font(.headline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                CameraPreviewView(session: capture.session)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if capture.isHandVisible {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.green, lineWidth: 4)
                        }
                    }

                Text(isCollecting ? "Calibrating…" : "Done")
                    .font(.title2.bold())

                ProgressView(value: progress, total: 2.0)
                    .padding(.horizontal)
                    .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .onAppear(perform: start)
    }

    private func start() {
        capture.start(taskType: .fingerTap) { result in
            switch result {
            case .success:
                collectForTwoSeconds()
            case .failure(let err):
                error = err.localizedDescription
            }
        }
    }

    private func collectForTwoSeconds() {
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak capture] t in
            guard let capture else {
                t.invalidate()
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            self.progress = min(elapsed, 2.0)

            if capture.isHandVisible, capture.handScale > 0.005 {
                self.samples.append(capture.handScale)
            }

            guard elapsed >= 2.0 else { return }
            t.invalidate()
            finish()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finish() {
        let avg = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
        if avg > 0.005 {
            HandCalibrationStore.shared.set(scale: avg)
        }
        capture.stop()
        isCollecting = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onComplete()
        }
    }
}

#Preview {
    MovementSessionFlowView()
}
