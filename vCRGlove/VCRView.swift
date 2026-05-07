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
        var line: String {
            "\(Logger.df.string(from: date)) [\(tag.uppercased())] \(message)"
        }
    }

    private static let df: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    func log(_ tag: String, _ message: String) {
        DispatchQueue.main.async {
            self.entries.append(.init(date: Date(), tag: tag, message: message))
            if self.entries.count > 2000 {
                self.entries.removeFirst(self.entries.count - 2000)
            }
        }

        EventStore.shared.append(
            type: "app_event",
            tag: tag,
            message: message
        )
    }

    func clear() { entries.removeAll() }
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
    
    private var readyDevices: [HDevice] {
        vm.devices.filter { $0.isReadyForStimulation && !$0.pos.isEmpty }
    }

    private var activePositions: [String] {
        vm.countdowns
            .filter { $0.value > 0 }
            .map(\.key)
    }

    private var isResearchStimulating: Bool {
        !activePositions.isEmpty
    }

    private var researchRemainingSeconds: Int {
        activePositions
            .compactMap { vm.countdowns[$0] }
            .max() ?? 0
    }
    
    private func startAllResearchStimulation() {
        for device in readyDevices {
            vm.startVibration(position: device.pos)
        }
    }

    private func stopAllResearchStimulation() {
        for position in activePositions {
            vm.stopVibration(position: position)
        }
    }

    private func timeText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
    private var researchStimulationControl: some View {
        HStack(spacing: 12) {
            Button {
                if isResearchStimulating {
                    stopAllResearchStimulation()
                } else {
                    startAllResearchStimulation()
                }
            } label: {
                Text(isResearchStimulating ? "STOP STIMULATION" : "START STIMULATION")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isResearchStimulating ? .red : .green)
            .disabled(!isResearchStimulating && readyDevices.isEmpty)

            VStack(alignment: .trailing, spacing: 2) {
                Text(isResearchStimulating ? "Remaining" : "Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(isResearchStimulating ? timeText(researchRemainingSeconds) : "\(readyDevices.count) glove(s)")
                    .font(.headline)
                    .monospacedDigit()
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
    }

    


    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // --- Bluetooth panel ---
                HStack {
                    Button(vm.scanning ? "Stop Scan" : "Start Scan") {
                        vm.scanning ? vm.stopScan() : vm.startScan()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    
                    Button("Disconnect All") { vm.disconnectAll() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
                
                // --- Parameters ---
                VStack(spacing: 8) {
                    Text("Vibration Parameters")
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
                                  range: 1...120, step: 1,
                                  unit: "min", format: "%.0f")
                    
                    Toggle("vCR Mode", isOn: $vm.vcrMode)
                        .tint(.orange)
                        .onChange(of: vm.vcrMode) { oldValue, newValue in
                            if newValue {
                                vm.amplitude       = VCRPreset.amplitude
                                vm.frequency       = VCRPreset.frequency
                                vm.pulseMs         = Double(VCRPreset.pulseMs)
                                vm.fingersPerCycle = VCRPreset.fingersPerCycle
                            }
                        }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                
                researchStimulationControl

                
                // --- Devices list ---
                VStack(spacing: 10) {
                    ForEach(vm.devices, id: \.id) { d in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.prettyName)
                                        .font(.subheadline.weight(.semibold))

                                    Text("Status: \(d.connectionStatusText)")
                                        .font(.caption2)
                                        .foregroundColor(d.isReadyForStimulation ? .green : .secondary)
                                }

                                Spacer()

                                if let remaining = vm.countdowns[d.pos], remaining > 0 {
                                    Text("\(remaining / 60)m \(remaining % 60)s")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }

                            HStack {
                                Button(d.isConnected == true ? "Reconnect" : "Pair / Connect") {
                                    vm.pair(device: d)
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                if d.isConnected == true {
                                    if vm.countdowns[d.pos] ?? 0 > 0 {
                                        Button("Stop Test") {
                                            vm.stopVibration(position: d.pos)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                    } else {
                                        Button("Start Test") {
                                            vm.startVibration(position: d.pos)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.green)
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    }
                }
                .frame(minHeight: 150, maxHeight: 280)

                
                // --- Logs ---
                LogsPanel(logger: logger)
                    .frame(height: 220)
            }
            .padding()
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .navigationTitle("vCR")
        .navigationBarTitleDisplayMode(.inline)
    }
}
