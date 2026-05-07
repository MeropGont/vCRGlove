//
//  PatientVCRView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 06.05.26.
//

import SwiftUI

struct PatientVCRView: View {
    @ObservedObject var vm: GloveVM
    @State private var stopProgress: Double = 0
    @State private var stopTimer: Timer? = nil
    @State private var autoPairAttemptedIDs: Set<String> = []


    private var readyGloves: [HDevice] {
        vm.devices.filter { $0.isReadyForStimulation && !$0.pos.isEmpty }
    }


    private var activePositions: [String] {
        vm.countdowns
            .filter { $0.value > 0 }
            .map(\.key)
    }

    private var isSessionRunning: Bool {
        !activePositions.isEmpty
    }

    private var remainingSeconds: Int {
        activePositions
            .compactMap { vm.countdowns[$0] }
            .max() ?? 0
    }

    private var leftGlove: HDevice? {
        vm.devices.first { $0.isLeftGlove }
    }

    private var rightGlove: HDevice? {
        vm.devices.first { $0.isRightGlove }
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("vCR Session")
                    .font(.largeTitle.bold())

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            gloveStatusGrid

            scanButton

            sessionCard

            Spacer()

            Text("Keep this app open during stimulation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            applyPatientPreset()
        }
        .onChange(of: vm.devices) {
            autoPairDetectedGloves()
        }
    }
    
    private func autoPairDetectedGloves() {
        for glove in vm.devices {
            guard glove.isLeftGlove || glove.isRightGlove else { continue }
            guard !glove.isReadyForStimulation else { continue }
            guard !autoPairAttemptedIDs.contains(glove.id) else { continue }

            autoPairAttemptedIDs.insert(glove.id)
            vm.pair(device: glove)
        }
    }


    private var sessionCard: some View {
        VStack(spacing: 16) {
            if isSessionRunning {
                Text("Session running")
                    .font(.title2.bold())

                Text(timeText(remainingSeconds))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()

                VStack(spacing: 8) {
                    Text("Hold for 2 seconds to stop")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red.opacity(0.25))
                            .frame(height: 52)

                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.red)
                            .frame(width: max(8, stopProgress * 320), height: 52)

                        Text("HOLD TO STOP")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                startStopHold()
                            }
                            .onEnded { _ in
                                cancelStopHold()
                            }
                    )
                }

            } else {
                Text("Ready for stimulation")
                    .font(.title2.bold())

                Button {
                    startSession()
                } label: {
                    Text("START vCR SESSION")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(readyGloves.isEmpty)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var scanButton: some View {
        Button {
            if vm.scanning {
                vm.stopScan()
            } else {
                autoPairAttemptedIDs.removeAll()
                vm.startScan()
            }
        } label: {
            Label(
                vm.scanning ? "STOP SCAN" : "SCAN FOR GLOVES",
                systemImage: vm.scanning ? "stop.circle.fill" : "dot.radiowaves.left.and.right"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }
    
    private func gloveStatusCard(title: String, assetName: String, glove: HDevice?) -> some View {
        let isReady = glove?.isReadyForStimulation == true
        let isStimulating = glove.flatMap { vm.countdowns[$0.pos] } ?? 0 > 0
        let canBuzz = isReady && !isStimulating

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
                        .stroke(gloveFrameColor(isReady: isReady, isStimulating: isStimulating), lineWidth: 4)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .onTapGesture {
                    guard canBuzz, let glove else { return }
                    vm.testBuzz(device: glove)
                }


            Text("\(title) glove")
                .font(.headline)

            Text(statusText(for: glove, isStimulating: isStimulating))
                .font(.caption)
                .foregroundStyle(statusColor(isReady: isReady, isStimulating: isStimulating))
            
            if canBuzz {
                Text("Tap to test buzz")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var gloveStatusGrid: some View {
        HStack(spacing: 14) {
            gloveStatusCard(title: "Left", assetName: "glove_L_icon", glove: leftGlove)
            gloveStatusCard(title: "Right", assetName: "glove_R_icon", glove: rightGlove)
        }
    }
    private func gloveFrameColor(isReady: Bool, isStimulating: Bool) -> Color {
        if isStimulating {
            return .indigo
        }

        if isReady {
            return .green
        }

        return .gray.opacity(0.35)
    }

    private func statusColor(isReady: Bool, isStimulating: Bool) -> Color {
        if isStimulating {
            return .indigo
        }

        if isReady {
            return .green
        }

        return .secondary
    }

    private func statusText(for glove: HDevice?, isStimulating: Bool) -> String {
        if isStimulating {
            return "Stimulating"
        }

        if glove?.isReadyForStimulation == true {
            return "Ready"
        }

        if glove == nil {
            return "Not detected"
        }

        return "Not ready"
    }

    
    private func gloveFigure(title: String, device: HDevice?) -> some View {
        let ready = device?.isReadyForStimulation == true

        return VStack(spacing: 10) {
            Image(systemName: "circle.hexagongrid.fill")
                .font(.system(size: 42))
                .foregroundStyle(ready ? .green : .red)

            Text("\(title) glove")
                .font(.headline)

            Text(device?.connectionStatusText ?? "Not detected")
                .font(.caption)
                .foregroundStyle(ready ? .green : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var statusText: String {
        if isSessionRunning {
            return "Stimulation is active."
        }

        if readyGloves.isEmpty {
            return "Scan and connect gloves before starting."
        }

        return "\(readyGloves.count) glove(s) ready."
    }

    private func applyPatientPreset() {
        vm.vcrMode = true
        vm.amplitude = VCRPreset.amplitude
        vm.frequency = VCRPreset.frequency
        vm.pulseMs = Double(VCRPreset.pulseMs)
        vm.fingersPerCycle = VCRPreset.fingersPerCycle
    }

    private func startSession() {
        applyPatientPreset()

        for glove in readyGloves {
            vm.startVibration(position: glove.pos)
        }

        let entry = JournalEntry(
            type: .stimulation,
            note: "vCR session started with \(readyGloves.count) glove(s)"
        )

        JournalStore.shared.add(entry)
    }

    private func stopSession() {
        for position in activePositions {
            vm.stopVibration(position: position)
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
                stopSession()
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


    private func timeText(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
