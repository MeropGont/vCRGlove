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
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logger.entries) { e in
                            Text(e.line)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
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

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var vm = GloveVM()
    @StateObject private var logger = Logger.shared

    var body: some View {
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
                              range: 1...60, step: 1,
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

            // --- Devices list ---
            List(vm.devices, id: \.id) { d in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(d.prettyName).font(.subheadline)
                        Spacer()
                        if d.isConnected == true {
                            if vm.countdowns[d.pos] ?? 0 > 0 {
                                Button("Stop") { vm.stopVibration(position: d.pos) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.red)
                                    .font(.caption)
                            } else {
                                Button("Vibrate") { vm.startVibration(position: d.pos) }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.green)
                                    .font(.caption)
                            }
                        } else {
                            Button("Pair") { vm.pair(device: d) }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(d.isPaired == true)
                                .font(.caption)
                        }
                    }

                    if let remaining = vm.countdowns[d.pos], remaining > 0 {
                        Text("⏱ \(remaining/60)m \(remaining%60)s left")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if d.isConnected == true {
                        Text("Status: Connected").font(.caption2).foregroundColor(.green)
                    } else if d.isPaired == true {
                        Text("Status: Paired").font(.caption2).foregroundColor(.orange)
                    } else {
                        Text("Status: Off / Not paired").font(.caption2).foregroundColor(.gray)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 150, maxHeight: 250)

            // --- Logs ---
            LogsPanel(logger: logger)
                .frame(minHeight: 140, maxHeight: 220)
        }
        .padding()
    }
}
