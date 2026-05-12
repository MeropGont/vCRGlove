import SwiftUI
import Combine

// MARK: - Inline Logger
final class Logger: ObservableObject {
    static let shared = Logger()
    @Published private(set) var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let tag: String
        let message: String
        var repeatCount: Int = 1

        var line: String {
            let repeatText = repeatCount > 1 ? "  x\(repeatCount)" : ""
            return "\(Logger.df.string(from: date)) [\(tag.uppercased())] \(message)\(repeatText)"
        }
    }

    private static let df: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private let hiddenVisibleTags: Set<String> = [
        "BLE_RAW"
    ]

    private let hiddenVisibleMessageFragments: [String] = [
        "Showing ",
        "detected bHaptics device",
        "Scan stopped"
    ]

    func log(_ tag: String, _ message: String) {
        EventStore.shared.append(
            type: "app_event",
            tag: tag,
            message: message
        )

        guard shouldShowInVisibleLog(tag: tag, message: message) else {
            return
        }

        DispatchQueue.main.async {
            if let last = self.entries.last,
               last.tag == tag,
               last.message == message {
                var updated = last
                updated.repeatCount += 1
                self.entries[self.entries.count - 1] = updated
            } else {
                self.entries.append(.init(date: Date(), tag: tag, message: message))
            }

            if self.entries.count > 300 {
                self.entries.removeFirst(self.entries.count - 300)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }

    private func shouldShowInVisibleLog(tag: String, message: String) -> Bool {
        if hiddenVisibleTags.contains(tag.uppercased()) {
            return false
        }

        for fragment in hiddenVisibleMessageFragments {
            if message.contains(fragment) {
                return false
            }
        }

        return true
    }
}


// MARK: - Inline LogsPanel
struct LogsPanel: View {
    @ObservedObject var logger: Logger

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Logs", systemImage: "doc.plaintext")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    logger.clear()
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
            }

            Divider().padding(.top, -2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(logger.entries) { e in
                            Text(e.line)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 12)
                    .id("bottom")
                }
                .onChange(of: logger.entries.count) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - LabeledSlider
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let format: String
    var disabled: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(disabled ? .gray : .primary)
                Spacer()
                Text(String(format: format, value) + " \(unit)")
                    .font(.caption2)
                    .foregroundStyle(disabled ? .gray : .secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
                .disabled(disabled)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - ContentView (changed to VCRView)
struct VCRView: View {
    @ObservedObject var vm: GloveVM
    @StateObject private var logger = Logger.shared
    @State private var stopProgress: Double = 0
    @State private var stopTimer: Timer?

    private var leftGlove: HDevice? {
        bestGlove(from: vm.devices.filter { $0.isLeftGlove })
    }

    private var rightGlove: HDevice? {
        bestGlove(from: vm.devices.filter { $0.isRightGlove })
    }

    private var readyDevices: [HDevice] {
        [leftGlove, rightGlove]
            .compactMap { $0 }
            .filter { $0.isReadyForStimulation && !$0.pos.isEmpty }
    }

    private var activePositions: [String] {
        vm.countdowns.filter { $0.value > 0 }.map(\.key)
    }

    private var isStimulating: Bool {
        !activePositions.isEmpty
    }

    private var isPaused: Bool {
        !activePositions.isEmpty && activePositions.allSatisfy { vm.pausedPositions.contains($0) }
    }

    private var remainingSeconds: Int {
        activePositions.compactMap { vm.countdowns[$0] }.max() ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scanSection
                gloveStatusGrid
                stimulationParameters
                stimulationControl
                LogsPanel(logger: logger)
                    .frame(height: 220)
            }
            .padding()
            .padding(.bottom, 24)
        }
        .navigationTitle("Research")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var scanSection: some View {
        VStack(spacing: 10) {
            Button {
                vm.scanning ? vm.stopScan() : vm.startScan(clearHistory: false)
            } label: {
                Label(
                    vm.scanning ? "STOP SCAN" : "SCAN FOR GLOVES",
                    systemImage: vm.scanning ? "stop.circle.fill" : "dot.radiowaves.left.and.right"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button("Clear History & Fresh Scan") {
                vm.startScan(clearHistory: true)
            }
            .font(.caption)
            .buttonStyle(.bordered)
        }
    }


    private var gloveStatusGrid: some View {
        HStack(spacing: 14) {
            gloveStatusCard(title: "Left", assetName: "glove_L_icon", glove: leftGlove)
            gloveStatusCard(title: "Right", assetName: "glove_R_icon", glove: rightGlove)
        }
    }

    private func gloveStatusCard(title: String, assetName: String, glove: HDevice?) -> some View {
        let isReady = glove?.isReadyForStimulation == true
        let isActive = glove.flatMap { vm.countdowns[$0.pos] } ?? 0 > 0
        let canBuzz = isReady && !isActive

        return VStack(spacing: 10) {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(height: 110)
                .opacity(isReady ? 1.0 : 0.28)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(gloveFrameColor(isReady: isReady, isActive: isActive), lineWidth: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .onTapGesture {
                    guard canBuzz, let glove else { return }
                    vm.testBuzz(device: glove)
                }

            Text("\(title) glove")
                .font(.headline)

            Text(statusText(for: glove, isActive: isActive))
                .font(.caption)
                .foregroundStyle(isActive ? .indigo : isReady ? .green : .secondary)

            if let glove {
                if isReady {
                    Button(role: .destructive) {
                        vm.disconnect(device: glove)
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isActive)
                } else {
                    Button {
                        vm.pair(device: glove)
                    } label: {
                        Label("Reconnect", systemImage: "arrow.clockwise.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var stimulationParameters: some View {
        VStack(spacing: 8) {
            Text("Stimulation Parameters")
                .font(.headline)

            LabeledSlider(title: "Amplitude", value: $vm.amplitude,
                          range: 0...100, step: 1,
                          unit: "%", format: "%.0f",
                          disabled: vm.vcrMode)

            LabeledSlider(title: "Frequency", value: $vm.frequency,
                          range: 0.5...5, step: 0.1,
                          unit: "Hz", format: "%.1f",
                          disabled: vm.vcrMode)

            LabeledSlider(title: "Pulse length", value: $vm.pulseMs,
                          range: 20...500, step: 10,
                          unit: "ms", format: "%.0f",
                          disabled: vm.vcrMode)

            LabeledSlider(title: "Fingers per cycle", value: Binding(
                get: { Double(vm.fingersPerCycle) },
                set: { vm.fingersPerCycle = Int($0) }),
                          range: 1...4, step: 1,
                          unit: "motors", format: "%.0f",
                          disabled: vm.vcrMode)

            LabeledSlider(title: "Total duration", value: Binding(
                get: { vm.totalSeconds / 60 },
                set: { vm.totalSeconds = $0 * 60 }),
                          range: 1...240, step: 1,
                          unit: "min", format: "%.0f")

            Toggle("vCR preset", isOn: $vm.vcrMode)
                .tint(.orange)
                .onChange(of: vm.vcrMode) { _, newValue in
                    if newValue {
                        vm.amplitude = VCRPreset.amplitude
                        vm.frequency = VCRPreset.frequency
                        vm.pulseMs = Double(VCRPreset.pulseMs)
                        vm.fingersPerCycle = VCRPreset.fingersPerCycle
                    }
                }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var stimulationControl: some View {
        VStack(spacing: 16) {
            if isStimulating {
                Text(isPaused ? "Paused" : "Stimulation running")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(durationText(remainingSeconds))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)

                ProgressView(value: sessionProgress)
                    .tint(isPaused ? .orange : .indigo)

                HStack(spacing: 12) {
                    sessionActionButton(
                        title: isPaused ? "Resume" : "Pause",
                        systemImage: isPaused ? "play.fill" : "pause.fill",
                        fill: isPaused ? .green : .orange
                    ) {
                        togglePause()
                    }

                    holdStopButton
                }
            } else {
                Text("Ready")
                    .font(.title2.bold())

                Text(readyDevices.isEmpty ? "Connect at least one glove to begin" : "\(readyDevices.count) glove(s) ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                sessionActionButton(title: "Start Stimulation", systemImage: "play.fill", fill: .green) {
                    startAll()
                }
                .disabled(readyDevices.isEmpty)
                .opacity(readyDevices.isEmpty ? 0.45 : 1)
            }
        }
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sessionActionButton(title: String, systemImage: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var holdStopButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray4))

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.red.opacity(0.85))
                    .frame(width: geo.size.width * stopProgress)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))

            Label("Hold to Stop", systemImage: "stop.fill")
                .font(.headline)
                .foregroundStyle(stopProgress > 0.45 ? .white : .primary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in startStopHold() }
                .onEnded { _ in cancelStopHold() }
        )
    }

    private func startAll() {
        for device in readyDevices {
            vm.startVibrationWithFingerCheck(positions: readyDevices.map(\.pos))
        }
    }

    private func stopAll() {
        for position in activePositions {
            vm.stopVibration(position: position)
        }
    }

    private func togglePause() {
        if isPaused {
            for position in activePositions {
                vm.resumeVibration(position: position)
            }
        } else {
            for position in activePositions {
                vm.pauseVibration(position: position)
            }
        }
    }

    private func startStopHold() {
        guard stopTimer == nil else { return }
        stopProgress = 0

        let timer = Timer(timeInterval: 0.05, repeats: true) { timer in
            stopProgress += 0.05 / 2.0

            if stopProgress >= 1 {
                timer.invalidate()
                stopTimer = nil
                stopProgress = 0
                stopAll()
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        stopTimer = timer
    }

    private func cancelStopHold() {
        stopTimer?.invalidate()
        stopTimer = nil
        stopProgress = 0
    }

    private var sessionProgress: Double {
        guard vm.totalSeconds > 0 else { return 0 }
        let elapsed = max(vm.totalSeconds - Double(remainingSeconds), 0)
        return min(max(elapsed / vm.totalSeconds, 0), 1)
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m \(seconds)s"
    }

    private func gloveFrameColor(isReady: Bool, isActive: Bool) -> Color {
        if isActive { return .indigo }
        if isReady { return .green }
        return .gray.opacity(0.35)
    }

    private func statusText(for glove: HDevice?, isActive: Bool) -> String {
        if isActive { return "Stimulating" }
        if glove?.isReadyForStimulation == true { return "Ready" }
        if glove == nil { return "Not detected" }
        return "Disconnected"
    }

    private func bestGlove(from gloves: [HDevice]) -> HDevice? {
        gloves.sorted {
            let lhsScore = gloveScore($0)
            let rhsScore = gloveScore($1)

            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }

            return $0.displayName < $1.displayName
        }
        .first
    }

    private func gloveScore(_ glove: HDevice) -> Int {
        var score = 0
        if glove.isConnected == true { score += 100 }
        if glove.isPaired == true && glove.battery != nil && !glove.pos.isEmpty { score += 80 }
        if glove.battery != nil { score += 20 }
        if glove.isPaired == true { score += 10 }
        if !glove.pos.isEmpty { score += 1 }
        return score
    }
}
