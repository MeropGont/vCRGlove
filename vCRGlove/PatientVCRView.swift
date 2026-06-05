//
//  PatientVCRView.swift
//  vCRGlove
//
//  Created by Tactile Glove on 06.05.26.
//

import SwiftUI

struct PatientVCRView: View {
    @ObservedObject var vm: GloveVM
    
    @AppStorage("patientID") private var patientID = ""
    @AppStorage("vcrSessionPlan") private var vcrSessionPlan = "fourHours"
    @AppStorage("vcrSplitCompletionDate") private var vcrSplitCompletionDate = ""
    @AppStorage("vcrSplitCompletionCount") private var vcrSplitCompletionCount = 0
    
    @AppStorage("vcrFourHourCompletionDate") private var vcrFourHourCompletionDate = ""

    @State private var stopProgress: Double = 0
    @State private var stopTimer: Timer? = nil
    @State private var autoPairAttemptedIDs: Set<String> = []
    @State private var patientSessionActive = false
    @State private var missingActivePositions: Set<String> = []
    @State private var sessionMessage: String?
    @State private var sessionMonitorTimer: Timer?
    @State private var sessionWasStarted = false
    @State private var sessionPausedForNoGloves = false



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
            
            vcrHeader

            gloveStatusGrid

            sessionCard
            
            troubleshootingLink

            Spacer()

            Text("Keep this app open during stimulation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .padding(.top, 12)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            applyPatientPreset()
            startSessionMonitor()
        }
        .onChange(of: vm.devices) {
            autoPairDetectedGloves()
            stopScanningWhenBothGlovesReady()
            monitorPatientSession()
        }
    }
    
    private func stopScanningWhenBothGlovesReady() {
        guard vm.scanning else { return }

        if leftGlove?.isReadyForStimulation == true &&
            rightGlove?.isReadyForStimulation == true {
            vm.stopScan()
            Logger.shared.log("BLE", "Scan stopped automatically because both gloves are ready")
        }
    }
    
    private func monitorPatientSession() {
        if !isSessionRunning {
            if sessionWasStarted && remainingSeconds == 0 {
                sessionMessage = completionMessageForCurrentPlan()
                Logger.shared.log("vCR", "Patient session completed")
                patientSessionActive = false
                sessionWasStarted = false
                sessionPausedForNoGloves = false
            }
            return
        }

        let readyPositions = Set(readyGloves.map(\.pos))
        let currentlyActive = Set(activePositions)
        let stillReadyActivePositions = currentlyActive.intersection(readyPositions)
        let disconnectedActivePositions = currentlyActive.subtracting(readyPositions)

        if !currentlyActive.isEmpty && stillReadyActivePositions.isEmpty {
            if !sessionPausedForNoGloves {
                sessionMessage = "Gloves disconnected. Turn them on and scan again to continue."
                Logger.shared.log("vCR", "Patient session paused: no active gloves connected")

                for position in currentlyActive {
                    vm.pauseVibration(position: position)
                }

                sessionPausedForNoGloves = true
                missingActivePositions = currentlyActive
                autoPairAttemptedIDs.removeAll()

                if !vm.scanning {
                    vm.startScan(clearHistory: false)
                }
            }

            return
        }

        if !disconnectedActivePositions.isEmpty {
            for position in disconnectedActivePositions {
                if !vm.pausedPositions.contains(position) {
                    vm.pauseVibration(position: position)
                    Logger.shared.log("vCR", "Paused disconnected glove @ \(position)")
                }
            }

            sessionMessage = "One glove disconnected. vCR continues with the connected glove."

            if !vm.scanning {
                autoPairAttemptedIDs.removeAll()
                vm.startScan(clearHistory: false)
            }
        }

        if sessionPausedForNoGloves && !stillReadyActivePositions.isEmpty {
            sessionMessage = "Gloves reconnected. Press Resume to continue."
            Logger.shared.log("vCR", "Glove connection restored during paused patient session")
            sessionPausedForNoGloves = false
            missingActivePositions.removeAll()
        }

        if !isSessionPaused {
            let pausedReadyPositions = readyPositions.intersection(vm.pausedPositions).intersection(currentlyActive)
            for position in pausedReadyPositions {
                vm.resumeVibration(position: position)
                Logger.shared.log("vCR", "Resumed reconnected glove @ \(position)")
            }
        }

        let newReadyGloves = readyGloves.filter { !currentlyActive.contains($0.pos) }

        for glove in newReadyGloves {
            let remaining = max(remainingSeconds, 1)
            vm.startVibration(position: glove.pos, durationSeconds: remaining)

            if isSessionPaused || sessionPausedForNoGloves {
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
            vm.refreshDevices()
            stopScanningWhenBothGlovesReady()
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
                    Text(idleSessionTitle)
                        .font(.title2.bold())

                    Text(readyGloves.isEmpty ? "Connect at least one glove to begin" : idleSessionSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    startSession()
                } label: {
                    Label(startButtonTitle, systemImage: isVCRCompleteToday ? "checkmark.circle.fill" : "play.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                }
                .buttonStyle(.borderedProminent)
                .tint(isVCRCompleteToday ? .gray : .green)
                .disabled(readyGloves.isEmpty || isVCRCompleteToday)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var troubleshootingLink: some View {
        NavigationLink {
            SupportSettingsView(patientID: patientID, initialTopic: "Finger check")
        } label: {
            Label("Something not working?", systemImage: "questionmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
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

    private var vcrHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("vCR")
                    .font(.title.bold())
            }

            if let sessionMessage {
                Text(sessionMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let timingCompromiseMessage = vm.timingCompromiseMessage {
                Text(timingCompromiseMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if !isSessionRunning {
                HStack(spacing: 8) {
                    setupStep("1", "Turn gloves on")

                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    setupStep("2", "Scan")
                }
            }

            scanButton
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private var scanButton: some View {
        Button {
            if vm.scanning {
                vm.stopScan()
            } else {
                autoPairAttemptedIDs.removeAll()
                vm.startScan(clearHistory: !isSessionRunning)
            }
        } label: {
            HStack {
                Image(systemName: vm.scanning ? "stop.circle.fill" : "dot.radiowaves.left.and.right")

                Text(vm.scanning ? "Stop scanning" : "Scan for gloves")
                    .fontWeight(.semibold)

                Spacer()

                if vm.scanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 14)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .foregroundStyle(vm.scanning ? .orange : .blue)
            .background((vm.scanning ? Color.orange : Color.blue).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    
    private func gloveStatusCard(title: String, assetName: String, glove: HDevice?) -> some View {
        let isReady = glove?.isReadyForStimulation == true
        let isStimulating = glove.flatMap { vm.countdowns[$0.pos] } ?? 0 > 0
        let canBuzz = isReady && !isStimulating
        let battery = batteryForGlove(title: title, fallback: glove?.battery)

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

            if isReady, let battery {
                Label("\(battery)%", systemImage: battery <= 10 ? "battery.25" : "battery.100")
                    .font(.caption2)
                    .foregroundStyle(battery <= 10 ? .red : .secondary)
            }

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

    private func batteryForGlove(title: String, fallback: Int?) -> Int? {
        if let fallback {
            return fallback
        }

        let matchingGloves: [HDevice]
        if title.lowercased() == "left" {
            matchingGloves = vm.devices.filter { $0.isLeftGlove }
        } else {
            matchingGloves = vm.devices.filter { $0.isRightGlove }
        }

        return matchingGloves
            .compactMap(\.battery)
            .first
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
        vm.clearTimingCompromiseWarning()
        vm.totalSeconds = Double(currentSessionDurationSeconds)

        vm.startVibrationWithFingerCheck(positions: readyGloves.map(\.pos))

        patientSessionActive = true
        sessionWasStarted = true
        sessionMessage = nil
        missingActivePositions.removeAll()

        let entry = JournalEntry(
            type: .stimulation,
            note: "vCR session started with \(readyGloves.count) glove(s), plan: \(sessionPlanText)"
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
            let readyPositions = Set(readyGloves.map(\.pos))
            let positionsToResume = activePositions.filter { readyPositions.contains($0) }

            guard !positionsToResume.isEmpty else {
                sessionMessage = "Turn gloves on and scan again before resuming."
                if !vm.scanning {
                    vm.startScan(clearHistory: false)
                }
                return
            }

            for position in positionsToResume {
                vm.resumeVibration(position: position)
            }

            sessionMessage = nil
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
    
    private var currentSessionDurationSeconds: Int {
        vcrSessionPlan == "twoByTwo" ? 2 * 60 * 60 : 4 * 60 * 60
    }

    private var sessionPlanText: String {
        vcrSessionPlan == "twoByTwo" ? "2 h vCR session" : "4 h vCR session"
    }

    private var todayKey: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    private func completionMessageForCurrentPlan() -> String {
        guard vcrSessionPlan == "twoByTwo" else {
            return "Great job. Your vCR session is complete for today."
        }

        if vcrSplitCompletionDate != todayKey {
            vcrSplitCompletionDate = todayKey
            vcrSplitCompletionCount = 0
        }

        vcrSplitCompletionCount += 1

        if vcrSplitCompletionCount >= 2 {
            guard vcrSessionPlan == "twoByTwo" else {
                vcrFourHourCompletionDate = todayKey
                return "Great job. Your 4 h vCR session is complete for today."
            }
        }

        return "Great job. First vCR session complete. One more 2 h session remains today."
    }
    
    private var completedSplitSessionsToday: Int {
        vcrSplitCompletionDate == todayKey ? vcrSplitCompletionCount : 0
    }

    private var isVCRCompleteToday: Bool {
        if vcrSessionPlan == "twoByTwo" {
            return completedSplitSessionsToday >= 2
        }

        return vcrFourHourCompletionDate == todayKey
    }

    private var nextSplitSessionNumber: Int {
        min(completedSplitSessionsToday + 1, 2)
    }

    private var idleSessionTitle: String {
        if isVCRCompleteToday {
            return "vCR complete today"
        }

        if vcrSessionPlan == "twoByTwo" {
            return "vCR \(nextSplitSessionNumber) of 2"
        }

        return "vCR session"
    }

    private var idleSessionSubtitle: String {
        if isVCRCompleteToday {
            return vcrSessionPlan == "twoByTwo" ? "Both 2 h sessions done" : "4 h session done"
        }

        return vcrSessionPlan == "twoByTwo" ? "2 h" : "4 h"
    }

    private var startButtonTitle: String {
        isVCRCompleteToday ? "Complete today" : "Start"
    }
    
    private func setupStep(_ number: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.blue)
                .clipShape(Circle())

            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var headerStatusText: String {
        if isSessionPaused { return "Paused" }
        if isSessionRunning { return "Running" }
        if readyGloves.isEmpty { return "Not ready" }
        return "\(readyGloves.count) ready"
    }

    private var headerStatusColor: Color {
        if isSessionPaused { return .orange }
        if isSessionRunning { return .indigo }
        if readyGloves.isEmpty { return .secondary }
        return .green
    }

}
