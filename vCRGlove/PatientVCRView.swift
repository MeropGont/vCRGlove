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
    @State private var patientSessionActive = false
    @State private var missingActivePositions: Set<String> = []
    @State private var sessionMessage: String?
    @State private var sessionMonitorTimer: Timer?
    @State private var sessionWasStarted = false



    private var readyGloves: [HDevice] {
        [leftGlove, rightGlove]
            .compactMap { $0 }
            .filter { $0.isReadyForStimulation && !$0.pos.isEmpty }
    }


    private var activePositions: [String] {
        vm.countdowns
            .filter { $0.value > 0 }
            .map(\.key)
    }

    private var isSessionRunning: Bool {
        !activePositions.isEmpty
    }
    
    private var pausedPositions: [String] {
        activePositions.filter { vm.pausedPositions.contains($0) }
    }

    private var isSessionPaused: Bool {
        !activePositions.isEmpty && activePositions.allSatisfy { vm.pausedPositions.contains($0) }
    }

    private var remainingSeconds: Int {
        activePositions
            .compactMap { vm.countdowns[$0] }
            .max() ?? 0
    }

    private var leftGlove: HDevice? {
        bestGlove(from: vm.devices.filter { $0.isLeftGlove })
    }

    private var rightGlove: HDevice? {
        bestGlove(from: vm.devices.filter { $0.isRightGlove })
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

        if glove.isConnected == true {
            score += 100
        }

        if glove.isPaired == true && glove.battery != nil && !glove.pos.isEmpty {
            score += 80
        }

        if glove.battery != nil {
            score += 20
        }

        if glove.isPaired == true {
            score += 10
        }

        if !glove.pos.isEmpty {
            score += 1
        }

        return score
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
                
                if let sessionMessage {
                    Text(sessionMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }

            }

            scanButton

            gloveStatusGrid

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
            startSessionMonitor()
        }
        .onChange(of: vm.devices) {
            autoPairDetectedGloves()
            monitorPatientSession()
        }
    }
    
    private func monitorPatientSession() {
        if !isSessionRunning {
            if sessionWasStarted && remainingSeconds == 0 {
                sessionMessage = "Great job. Your vCR session is complete for today."
                Logger.shared.log("vCR", "Patient session completed")
                patientSessionActive = false
                sessionWasStarted = false
            }

            return
        }

        let readyPositions = Set(readyGloves.map(\.pos))
        let currentlyActive = Set(activePositions)

        let stillActivePositions = currentlyActive.intersection(readyPositions)

        if currentlyActive.isEmpty {
            missingActivePositions.removeAll()
        } else if stillActivePositions.isEmpty {
            if missingActivePositions == currentlyActive {
                sessionMessage = "Session interrupted because both gloves disconnected."
                Logger.shared.log("vCR", "Patient session interrupted: no active gloves connected")
                stopSession()
                patientSessionActive = false
                missingActivePositions.removeAll()
                return
            }

            missingActivePositions = currentlyActive
        } else {
            missingActivePositions.removeAll()
        }


        let newReadyGloves = readyGloves.filter { !currentlyActive.contains($0.pos) }

        for glove in newReadyGloves {
            let remaining = max(remainingSeconds, 1)
            vm.startVibration(position: glove.pos, durationSeconds: remaining)

            if isSessionPaused {
                vm.pauseVibration(position: glove.pos)
                Logger.shared.log("vCR", "Added \(glove.prettyName) to paused patient session with \(remaining)s remaining")
            } else {
                Logger.shared.log("vCR", "Added \(glove.prettyName) to active patient session with \(remaining)s remaining")
            }
        }


    }
    
    private func startSessionMonitor() {
        guard sessionMonitorTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { _ in
            monitorPatientSession()
        }

        RunLoop.main.add(timer, forMode: .common)
        sessionMonitorTimer = timer
    }


    private func autoPairDetectedGloves() {
        if let leftGlove, !leftGlove.isReadyForStimulation, !autoPairAttemptedIDs.contains("left") {
            autoPairAttemptedIDs.insert("left")
            vm.pair(device: leftGlove)
        }

        if let rightGlove, !rightGlove.isReadyForStimulation, !autoPairAttemptedIDs.contains("right") {
            autoPairAttemptedIDs.insert("right")
            vm.pair(device: rightGlove)
        }
    }


    private var sessionCard: some View {
        VStack(spacing: 16) {
            if isSessionRunning {
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(isSessionPaused ? Color.orange : Color.indigo)
                            .frame(width: 10, height: 10)

                        Text(isSessionPaused ? "Paused" : "Stimulation running")
                            .font(.headline)

                        Spacer()
                    }

                    Text(durationText(remainingSeconds))
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Time remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ProgressView(value: sessionProgress)
                        .tint(isSessionPaused ? .orange : .indigo)
                }

                HStack(spacing: 12) {
                    sessionActionButton(
                        title: isSessionPaused ? "Resume" : "Pause",
                        systemImage: isSessionPaused ? "play.fill" : "pause.fill",
                        fill: isSessionPaused ? .green : .orange
                    ) {
                        togglePauseSession()
                    }

                    holdStopButton
                }

            } else {
                VStack(spacing: 8) {
                    Text("Ready")
                        .font(.title2.bold())

                    Text(readyGloves.isEmpty ? "Connect at least one glove to begin" : "4 h vCR session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    startSession()
                } label: {
                    Label("Start vCR", systemImage: "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(readyGloves.isEmpty)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func sessionActionButton(
        title: String,
        systemImage: String,
        fill: Color,
        action: @escaping () -> Void
    ) -> some View {
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
                .onChanged { _ in
                    startStopHold()
                }
                .onEnded { _ in
                    cancelStopHold()
                }
        )
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

        return "Disconnected"
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
            return ""
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
        
        patientSessionActive = true
        sessionWasStarted = true
        sessionMessage = nil
        missingActivePositions.removeAll()

        let entry = JournalEntry(
            type: .stimulation,
            note: "vCR session started with \(readyGloves.count) glove(s)"
        )

        JournalStore.shared.add(entry)
        
    }

    private func stopSession() {
        for position in activePositions {
            vm.stopVibration(position: position)
            patientSessionActive = false
            sessionWasStarted = false
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
    
    private var sessionProgress: Double {
        guard vm.totalSeconds > 0 else { return 0 }
        let elapsed = max(vm.totalSeconds - Double(remainingSeconds), 0)
        return min(max(elapsed / vm.totalSeconds, 0), 1)
    }

    private func togglePauseSession() {
        if isSessionPaused {
            for position in activePositions {
                vm.resumeVibration(position: position)
            }
        } else {
            for position in activePositions {
                vm.pauseVibration(position: position)
            }
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }

        return "\(minutes)m"
    }

}
