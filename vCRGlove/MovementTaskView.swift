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
        case result(Trial)
    }

    @AppStorage("patientID") private var patientID = ""

    @State private var phase: Phase = .setup

    // Setup choices
    @State private var taskType: MovementTaskType = .fingerTap
    @State private var side: BodySide = .right
    @State private var stopMode: StopMode = .repetitions
    @State private var context: StimulationContext = .unspecified
    @State private var syntheticPreset: SyntheticCaptureSource.Preset = .healthy
    @State private var useCamera = false
    @State private var useWatch = false

    // Recording machinery
    @State private var recorder: TrialRecorder?
    @State private var source = SyntheticCaptureSource()
    @State private var cameraCapture: VisionHandPoseCapture?
    @State private var watchCapture: WatchMotionCapture?
    @State private var countdownTimer: Timer?
    @State private var cameraError: String?
    @StateObject private var signalMonitor = LiveSignalMonitor()

    private var cameraAvailableForTask: Bool {
        taskType.preferredSource == .camera
    }
    private var watchAvailableForTask: Bool {
        taskType.preferredSource == .watchMotion
    }
    private var usingCamera: Bool { useCamera && cameraAvailableForTask }
    private var usingWatch: Bool { useWatch && watchAvailableForTask }

    private var activeSignalSource: SignalSource {
        if usingCamera { return .camera }
        if usingWatch { return .watchMotion }
        return .synthetic
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
            if usingCamera, cameraCapture != nil,
               case .setup = phase { EmptyView() }
            else if usingCamera, let cc = cameraCapture {
                VStack(spacing: 4) {
                    CameraPreviewView(session: cc.session)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            HandGuideOverlay(capture: cc, taskType: taskType)
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
                    // Live signal chart — shows exactly what the analyzer sees.
                    LiveSignalChart(monitor: signalMonitor)
                        .frame(height: 56)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                .padding(.top, 4)
            }
            // Persistent watch signal chart: same idea as the camera preview.
            else if usingWatch, let wc = watchCapture {
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

            Section("Stop after") {
                Picker("Mode", selection: $stopMode) {
                    Text("10 repetitions").tag(StopMode.repetitions)
                    Text("15 seconds").tag(StopMode.duration)
                }
                .pickerStyle(.segmented)
            }

            Section("Context") {
                Picker("Relative to stimulation", selection: $context) {
                    ForEach(StimulationContext.allCases) { c in
                        Text(contextLabel(c)).tag(c)
                    }
                }
            }

            Section {
                if cameraAvailableForTask {
                    Picker("Source", selection: $useCamera) {
                        Text("Camera").tag(true)
                        Text("Simulated").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if watchAvailableForTask {
                    Picker("Source", selection: $useWatch) {
                        Text("Apple Watch").tag(true)
                        Text("Simulated").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if !usingCamera && !usingWatch {
                    Picker("Signal preset", selection: $syntheticPreset) {
                        ForEach(SyntheticCaptureSource.Preset.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                }
            } header: {
                Text("Signal source")
            } footer: {
                if usingCamera {
                    Text("The front camera tracks your hand. No video is stored — only movement measurements.")
                } else if usingWatch {
                    Text("Wear the watch on the tested arm and keep the vCRGlove watch app open during the recording.")
                } else {
                    Text("Simulated signals are for testing without hardware.")
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
                .padding(.top, usingCamera ? 280 : (usingWatch ? 120 : 0))
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

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 24) {
            // Top padding so content doesn't overlap the persistent preview overlay.
            if usingCamera { Color.clear.frame(height: 274) }
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

    private var stopCondition: StopCondition {
        stopMode == .repetitions ? .tenReps : .fifteenSec
    }

    private func startRecording() {
        let r = TrialRecorder(taskType: taskType,
                              side: side,
                              source: activeSignalSource,
                              stopCondition: stopCondition)
        r.onComplete = { trial in
            source.stop()
            cameraCapture?.stop()
            cameraCapture = nil
            watchCapture?.stop()
            watchCapture = nil
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
        } else {
            source.start(preset: syntheticPreset, feeding: r)
        }
        EventStore.shared.append(
            type: "TASK", tag: "trial_started",
            message: "Movement trial started",
            details: ["task": taskType.rawValue,
                      "side": side.rawValue,
                      "source": activeSignalSource.rawValue,
                      "mode": stopMode.rawValue])
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
        source.stop()
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
private struct CameraPreviewView: UIViewRepresentable {
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
private struct HandGuideOverlay: View {
    @ObservedObject var capture: VisionHandPoseCapture
    let taskType: MovementTaskType

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
                    .position(x: zone.midX, y: zone.midY)

                if !good {
                    Text("Place your hand here")
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
/// the preview, banner, and a haptic tap — cycles are NOT counted while the
/// hand is clipped, so the user must notice right away.
private struct ClippedWarningOverlay: View {
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
        .onChange(of: capture.isHandClipped) { _, clipped in
            if clipped {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
    }
}

/// Lightweight real-time sparkline of the movement signal — shows exactly
/// what the analyzer sees, so signal-quality problems are visible immediately.
private struct LiveSignalChart: View {
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

private struct RecordingProgressView: View {
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
                ProgressView(value: min(recorder.elapsed, stopCondition.targetDuration),
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
                    Label("Save", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Text("Discard")
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
