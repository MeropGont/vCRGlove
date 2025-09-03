import SwiftUI
import BhapticsPlugin

// MARK: - Helpers
enum HandSide: String, CaseIterable, Identifiable {
    case left = "Left", right = "Right"
    var id: String { rawValue }
    var devicePosition: String { self == .left ? "GloveL" : "GloveR" }
    var label: String { self == .left ? "Left" : "Right" }
    var pretty: String { self == .left ? "Glove Left" : "Glove Right" }
}

struct LabeledSlider<T: BinaryFloatingPoint>: View where T.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: T
    let range: ClosedRange<T>
    let step: T
    let unit: String
    let format: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text(String(format: format, Double(value)) + " \(unit)")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range, step: T.Stride(step))
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Main iOS UI
struct ContentView: View {
    @StateObject private var vm = GloveVM()

    // vCR parameter controls
    @State private var selectedSide: HandSide = .left
    @State private var strength: Double = 70
    @State private var cycleHz: Double = 1.5
    @State private var burstMs: Double = 100
    @State private var motorCount: Double = 4
    @State private var pattern: BuzzPattern = .constant

    private var motorsPerBurst: [Int] {
        let N = max(1, min(20, Int(motorCount)))
        return Array(0..<N)
    }

    private var strengthU8: UInt8 { UInt8(max(0, min(100, Int(strength)))) }
    private var burstMsInt: Int { max(10, min(1000, Int(burstMs))) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {

                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)
                        Text("vCR Glove Control")
                            .font(.title3).fontWeight(.semibold)
                        Spacer()
                        Picker("Side", selection: $selectedSide) {
                            ForEach(HandSide.allCases) { s in Text(s.label).tag(s) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    .padding(.horizontal)

                    // Devices
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Button(vm.scanning ? "Stop Scan" : "Start Scan") {
                                    vm.scanning ? vm.stopScan() : vm.startScan()
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Disconnect All") { vm.disconnectAll() }
                                    .buttonStyle(.bordered).tint(.red)

                                Spacer()

                                Button("Vibrate \(selectedSide.label)") {
                                    if selectedSide == .left { vm.vibrateLeft(strength: strengthU8) }
                                    else { vm.vibrateRight(strength: strengthU8) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }

                            if !vm.devices.isEmpty {
                                Divider().padding(.vertical, 2)
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(vm.devices, id: \.id) { d in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(d.prettyName).font(.subheadline).fontWeight(.medium)
                                                if d.isConnected == true {
                                                    Text("Connected").font(.caption2).foregroundStyle(.green)
                                                } else if d.isPaired == true {
                                                    Text("Paired").font(.caption2).foregroundStyle(.orange)
                                                } else {
                                                    Text("Off / Not paired").font(.caption2).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            if d.isConnected == true {
                                                Button("Disconnect") { vm.disconnect(device: d) }
                                                    .buttonStyle(.bordered).tint(.red)
                                            } else {
                                                Button("Pair") { vm.pair(device: d) }
                                                    .buttonStyle(.borderedProminent).tint(.blue)
                                                    .disabled(d.isPaired == true)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("Devices", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .padding(.horizontal)

                    // vCR Parameters
                    GroupBox {
                        VStack(spacing: 10) {
                            LabeledSlider(title: "Amplitude", value: $strength,
                                          range: 0...100, step: 1, unit: "%", format: "%.0f")

                            LabeledSlider(title: "Cycle Frequency", value: $cycleHz,
                                          range: 0.5...6.0, step: 0.1, unit: "Hz", format: "%.1f")

                            LabeledSlider(title: "Burst Duration", value: $burstMs,
                                          range: 20...300, step: 5, unit: "ms", format: "%.0f")

                            LabeledSlider(title: "Motors per Burst", value: $motorCount,
                                          range: 1...8, step: 1, unit: "motors", format: "%.0f")

                            HStack {
                                Text("Pattern").font(.subheadline)
                                Spacer()
                                Picker("Pattern", selection: $pattern) {
                                    ForEach(BuzzPattern.allCases, id: \.self) { p in
                                        Text(p.rawValue).tag(p)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(maxWidth: 260)
                            }
                            .padding(.top, 4)
                        }
                        .padding(8)
                    } label: {
                        Label("vCR Parameters", systemImage: "slider.horizontal.3")
                    }
                    .padding(.horizontal)

                    // Actions
                    GroupBox {
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Button("Start vCR on \(selectedSide.label)") {
                                    vm.performVCRSequence(
                                        position: selectedSide.devicePosition,
                                        strength: strengthU8,
                                        cycleHz: cycleHz,
                                        burstMs: burstMsInt,
                                        motorsPerBurst: motorsPerBurst
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)

                                Button("Stop vCR") {
                                    vm.stopVCR(position: selectedSide.devicePosition)
                                }
                                .buttonStyle(.bordered).tint(.red)

                                Spacer()
                            }

                            Divider().padding(.vertical, 2)

                            HStack(spacing: 12) {
                                Button(vm.isLongBuzzing(selectedSide.devicePosition)
                                       ? "Stop Long Buzz"
                                       : "Start Long Buzz (1h)") {
                                    vm.toggleLongBuzz(position: selectedSide.devicePosition,
                                                      seconds: 3600,
                                                      pattern: pattern)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)

                                if vm.isLongBuzzing(selectedSide.devicePosition),
                                   let remaining = vm.countdowns[selectedSide.devicePosition] {
                                    Text("⏱ \(remaining/60)m \(remaining%60)s left")
                                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }

                                Spacer()
                            }
                        }
                        .padding(8)
                    } label: {
                        Label("Actions", systemImage: "playpause.circle")
                    }
                    .padding(.horizontal)

                    // Logs
                    GroupBox {
                        if vm.log.isEmpty {
                            Text("No logs yet").font(.caption).foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(vm.log.suffix(80), id: \.self) { line in
                                    Text(line).font(.caption2).monospaced()
                                }
                            }
                        }
                    } label: {
                        Label("Log", systemImage: "text.justify.leading")
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }
}
