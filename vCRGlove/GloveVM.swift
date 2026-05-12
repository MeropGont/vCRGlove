import Foundation
import SwiftUI
import UIKit
import BhapticsPlugin

// MARK: - Device Model
struct HDevice: Identifiable, Decodable, Equatable {
    let id: String
    let name: String?
    let position: String?
    var isConnected: Bool?
    var isPaired: Bool?
    var address: String?
    var battery: Int?

    var displayName: String { name ?? id }
    var pos: String { position ?? "" }

    var isGlove: Bool {
        let text = "\(position ?? "") \(name ?? "") \(id)".lowercased()

        return text.contains("tactglove")
            || text.contains("glovel")
            || text.contains("glover")
            || text.contains("glove left")
            || text.contains("glove right")
            || text.contains("left glove")
            || text.contains("right glove")
    }

    var prettyName: String {
        let p = (position ?? "").lowercased()
        if p.contains("glovel") { return "Glove Left" }
        if p.contains("glover") { return "Glove Right" }
        return displayName
    }

    enum CodingKeys: String, CodingKey {
        case id, name, position, isConnected, isPaired, address
        case connected, paired
        case is_connected, is_paired
        case battery, batteryLevel, batteryPercent
        case battery_level, battery_percent
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id        = try c.decode(String.self, forKey: .id)
        self.name      = try? c.decode(String.self, forKey: .name)
        self.position  = try? c.decode(String.self, forKey: .position)
        self.address   = try? c.decode(String.self, forKey: .address)

        let conn1 = try? c.decode(Bool.self, forKey: .isConnected)
        let conn2 = try? c.decode(Bool.self, forKey: .connected)
        let conn3 = try? c.decode(Bool.self, forKey: .is_connected)
        self.isConnected = conn1 ?? conn2 ?? conn3

        let pair1 = try? c.decode(Bool.self, forKey: .isPaired)
        let pair2 = try? c.decode(Bool.self, forKey: .paired)
        let pair3 = try? c.decode(Bool.self, forKey: .is_paired)
        self.isPaired = pair1 ?? pair2 ?? pair3
        
        let batteryInt =
            (try? c.decode(Int.self, forKey: .battery)) ??
            (try? c.decode(Int.self, forKey: .batteryLevel)) ??
            (try? c.decode(Int.self, forKey: .batteryPercent)) ??
            (try? c.decode(Int.self, forKey: .battery_level)) ??
            (try? c.decode(Int.self, forKey: .battery_percent))

        let batteryDouble =
            (try? c.decode(Double.self, forKey: .battery)) ??
            (try? c.decode(Double.self, forKey: .batteryLevel)) ??
            (try? c.decode(Double.self, forKey: .batteryPercent)) ??
            (try? c.decode(Double.self, forKey: .battery_level)) ??
            (try? c.decode(Double.self, forKey: .battery_percent))

        self.battery = batteryInt ?? batteryDouble.map { Int($0.rounded()) }

    }

    static func == (lhs: HDevice, rhs: HDevice) -> Bool { lhs.id == rhs.id }
}

extension HDevice {
    var isReadyForStimulation: Bool {
        if isConnected == true {
            return true
        }

        if isPaired == true && battery != nil && !pos.isEmpty {
            return true
        }

        return false
    }

    var connectionStatusText: String {
        if isReadyForStimulation {
            return "Ready"
        }

        if isPaired == true {
            return "Detected"
        }

        return "Disconnected"
    }


    var isLeftGlove: Bool {
        let p = (position ?? "").lowercased()
        let n = (name ?? "").lowercased()

        return p.contains("glovel")
            || p.contains("glove left")
            || n.contains("glove left")
            || n.contains("left glove")
    }

    var isRightGlove: Bool {
        let p = (position ?? "").lowercased()
        let n = (name ?? "").lowercased()

        return p.contains("glover")
            || p.contains("glove right")
            || n.contains("glove right")
            || n.contains("right glove")
    }


}


// MARK: - vCR Preset
enum VCRPreset {
    static let amplitude: Double = 70
    static let frequency: Double = 1.5
    static let pulseMs: Int = 100
    static let fingersPerCycle: Int = 4
}

// MARK: - ViewModel
@MainActor
final class GloveVM: ObservableObject {
    @Published var scanning = false
    @Published var devices: [HDevice] = []
    @Published var countdowns: [String: Int] = [:]
    @Published var pausedPositions: Set<String> = []
    
    // deal with possible interruptions
    @Published var timingCompromiseMessage: String?

    private var backgroundedDuringStimulationAt: Date?
    private var stimulationBackgroundTask: UIBackgroundTaskIdentifier = .invalid


    // Vibration params (manual mode)
    @Published var amplitude: Double = 70
    @Published var frequency: Double = 1.5
    @Published var pulseMs: Double = 100
    @Published var totalSeconds: Double = 4 * 60 * 60
    @Published var fingersPerCycle: Int = 4

    // vCR toggle
    @Published var vcrMode = false

    private var localState: [String: (connected: Bool?, paired: Bool?)] = [:]
    private var pollTimer: Timer?
    private var scanTimeoutTimer: Timer?
    private var vibTimers: [String: Timer] = [:]
    private var startedAt: [String: Date] = [:]
    private var activeStimPositions: Set<String> = []
    private var lastNoGloveCandidateLog: Date?
    

    private func updateIdleTimerLock() {
        UIApplication.shared.isIdleTimerDisabled = !activeStimPositions.isEmpty
    }
    
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            handleAppReturnedToForeground()

        case .background:
            handleAppEnteredBackground()

        case .inactive:
            if !activeStimPositions.isEmpty {
                Logger.shared.log("vCR", "App became inactive during active stimulation")
            }

        @unknown default:
            break
        }
    }

    func clearTimingCompromiseWarning() {
        timingCompromiseMessage = nil
    }

    private func handleAppEnteredBackground() {
        guard !activeStimPositions.isEmpty else { return }

        if backgroundedDuringStimulationAt == nil {
            backgroundedDuringStimulationAt = Date()
        }

        timingCompromiseMessage = "vCR timing may have been interrupted while the app was not open."
        Logger.shared.log("vCR", "Timing compromised: app entered background during active stimulation")

        beginStimulationBackgroundTaskIfNeeded()
    }

    private func handleAppReturnedToForeground() {
        guard let backgroundedAt = backgroundedDuringStimulationAt else { return }

        let duration = Date().timeIntervalSince(backgroundedAt)
        let activeText = activeStimPositions.isEmpty ? "stimulation not active" : "stimulation still active"

        Logger.shared.log(
            "vCR",
            "App returned to foreground after \(String(format: "%.1f", duration))s in background; \(activeText)"
        )

        backgroundedDuringStimulationAt = nil
        endStimulationBackgroundTaskIfNeeded()
    }

    private func beginStimulationBackgroundTaskIfNeeded() {
        guard stimulationBackgroundTask == .invalid else { return }

        stimulationBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "vCR stimulation") { [weak self] in
            Task { @MainActor in
                Logger.shared.log("vCR", "Background grace time expired during active stimulation")
                self?.endStimulationBackgroundTaskIfNeeded()
            }
        }
    }

    private func endStimulationBackgroundTaskIfNeeded() {
        guard stimulationBackgroundTask != .invalid else { return }

        UIApplication.shared.endBackgroundTask(stimulationBackgroundTask)
        stimulationBackgroundTask = .invalid
    }



    // MARK: - Scan
    private func clearKnownGloveHistory() {
        guard let cstr = BhapticsPlugin_getDevices() else { return }

        let raw = String(cString: cstr)
        var knownDevices: [HDevice] = []

        if let data = raw.data(using: .utf8) {
            if let arr = try? JSONDecoder().decode([HDevice].self, from: data) {
                knownDevices = arr
            } else {
                struct Wrapper: Decodable { let devices: [HDevice]? }
                knownDevices = (try? JSONDecoder().decode(Wrapper.self, from: data))?.devices ?? []
            }
        }

        let knownGloves = knownDevices.filter { $0.isGlove }

        for glove in knownGloves {
            glove.id.withCString { BhapticsPlugin_unpair($0) }
        }

        Logger.shared.log("BLE", "Cleared \(knownGloves.count) known glove record(s)")
    }


    func startScan(clearHistory: Bool = true) {
        Logger.shared.log("BLE", "Fresh scan started")
        scanning = true
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.stopScan()
                Logger.shared.log("BLE", "Scan stopped automatically after 60 seconds")
            }
        }


        pollTimer?.invalidate()
        pollTimer = nil

        if clearHistory {
            devices = []
            countdowns = [:]
            localState = [:]
        }

        BhapticsPlugin_stopScan()

        if clearHistory {
            clearKnownGloveHistory()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            BhapticsPlugin_scan()

            let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshDevices()
                }
            }

            RunLoop.main.add(timer, forMode: .common)
            self.pollTimer = timer

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.refreshDevices()
            }
        }
    }


    func stopScan() {
        Logger.shared.log("BLE", "Scan stopped")
        scanning = false
        BhapticsPlugin_stopScan()
        pollTimer?.invalidate()
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil

        pollTimer = nil
        refreshDevices()
    }


    func refreshDevices() {
        guard let cstr = BhapticsPlugin_getDevices() else { return }
        let raw = String(cString: cstr)
        Logger.shared.log("BLE_RAW", raw)


        var newDevices: [HDevice] = []
        if let data = raw.data(using: .utf8) {
            if let arr = try? JSONDecoder().decode([HDevice].self, from: data) {
                newDevices = arr
            } else {
                struct Wrapper: Decodable { let devices: [HDevice]? }
                newDevices = (try? JSONDecoder().decode(Wrapper.self, from: data))?.devices ?? []
            }
        }

        let gloveCandidates = newDevices.filter { $0.isGlove }
        if gloveCandidates.count != newDevices.count {
            let now = Date()
            if lastNoGloveCandidateLog == nil || now.timeIntervalSince(lastNoGloveCandidateLog!) > 5 {
                Logger.shared.log("BLE", "Showing \(newDevices.count) detected bHaptics device(s), \(gloveCandidates.count) clearly identified as glove(s)")
                lastNoGloveCandidateLog = now
            }
        }
        newDevices = gloveCandidates


        var byId: [String: HDevice] = [:]
        for d in newDevices { byId[d.id] = d }
        var unique = Array(byId.values)

        self.devices = unique.sorted { ($0.position ?? "") < ($1.position ?? "") }
    }

    func pair(device: HDevice) {
        device.id.withCString { BhapticsPlugin_pair($0) }

        Logger.shared.log("BLE", "Pair/connect requested for \(device.prettyName)")

        localState[device.id] = (connected: device.isConnected, paired: true)
        refreshDevices()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.refreshDevices()

            if let updated = self.devices.first(where: { $0.id == device.id }) {
                self.testBuzz(device: updated)
            } else {
                self.testBuzz(device: device)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.refreshDevices()
        }
    }

    
    func testBuzz(device: HDevice) {
        guard !device.pos.isEmpty else {
            Logger.shared.log("BLE", "Cannot buzz \(device.prettyName): missing position")
            return
        }

        sendBurstAll(position: device.pos, strength: 70, burstMs: 120)
        Logger.shared.log("BLE", "Test buzz sent to \(device.prettyName)")
    }


    func disconnect(device: HDevice) {
        device.id.withCString { BhapticsPlugin_unpair($0) }
        stopVibration(position: device.pos)
        Logger.shared.log("BLE", "Disconnecting \(device.prettyName)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.refreshDevices()
        }
    }


    func disconnectAll() {
        for d in devices {
            d.id.withCString { BhapticsPlugin_unpair($0) }
            stopVibration(position: d.pos)
            localState[d.id] = (connected: false, paired: false)
        }
        BhapticsPlugin_stop()
        activeStimPositions.removeAll()
        updateIdleTimerLock()
        Logger.shared.log("BLE", "All gloves disconnect")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshDevices() }
    }

    // MARK: - Vibration
    func startVibration(position: String, durationSeconds: Int? = nil) {
        stopVibration(position: position)

        let sessionSeconds = durationSeconds ?? Int(totalSeconds)
        startedAt[position] = Date()
        countdowns[position] = sessionSeconds

        let amp = vcrMode ? VCRPreset.amplitude : amplitude
        let freq = vcrMode ? VCRPreset.frequency : frequency
        let pMs = vcrMode ? VCRPreset.pulseMs : Int(pulseMs)
        let fingers = vcrMode ? VCRPreset.fingersPerCycle : max(1, min(4, fingersPerCycle))

        let cycleInterval = max(0.1, 1.0 / max(0.1, freq))
        let slots = max(1, fingers)
        let slotSpacing = cycleInterval / Double(slots)

        let timer = Timer(timeInterval: cycleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                let indices = Array(0..<slots).shuffled()
                for (i, motorIndex) in indices.enumerated() {
                    let when = Double(i) * slotSpacing
                    DispatchQueue.main.asyncAfter(deadline: .now() + when) {
                        if self.vcrMode {
                            self.sendBurst(position: position, motorIndex: motorIndex, strength: UInt8(amp), burstMs: pMs)
                        } else {
                            self.sendBurstAll(position: position, strength: UInt8(amp), burstMs: pMs)
                        }
                    }
                }

                if let start = self.startedAt[position] {
                    let elapsed = Int(Date().timeIntervalSince(start))
                    let remaining = max(sessionSeconds - elapsed, 0)
                    self.countdowns[position] = remaining

                    if remaining <= 0 {
                        self.stopVibration(position: position)
                    }
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        vibTimers[position] = timer
        activeStimPositions.insert(position)
        updateIdleTimerLock()

        Logger.shared.log("vCR", "Start vibration @ \(position) [total=\(sessionSeconds)s]")
    }

    func stopVibration(position: String) {
        vibTimers[position]?.invalidate()
        vibTimers[position] = nil
        countdowns[position] = 0
        startedAt[position] = nil
        activeStimPositions.remove(position)
        pausedPositions.remove(position)

        sendAllOff(position: position)

        if activeStimPositions.isEmpty {
            BhapticsPlugin_stop()
        }

        updateIdleTimerLock()
        
        if activeStimPositions.isEmpty {
            endStimulationBackgroundTaskIfNeeded()
        }

        Logger.shared.log("vCR", "Stopped vibration @ \(position)")
    }

    func resumeVibration(position: String) {
        guard pausedPositions.contains(position) else { return }
        guard let remaining = countdowns[position], remaining > 0 else {
            stopVibration(position: position)
            return
        }

        pausedPositions.remove(position)
        startVibration(position: position, durationSeconds: remaining)

        Logger.shared.log("vCR", "Resumed vibration @ \(position)")
    }

    
    func pauseVibration(position: String) {
        guard vibTimers[position] != nil else { return }

        vibTimers[position]?.invalidate()
        vibTimers[position] = nil
        activeStimPositions.remove(position)
        pausedPositions.insert(position)
        updateIdleTimerLock()

        sendAllOff(position: position)
        Logger.shared.log("vCR", "Paused vibration @ \(position)")
    }
    
    func startVibrationWithFingerCheck(positions: [String], durationSeconds: Int? = nil) {
        let cleaned = Array(Set(positions.filter { !$0.isEmpty }))
        guard !cleaned.isEmpty else { return }

        let sessionSeconds = durationSeconds ?? Int(totalSeconds)
        let fingerIndices = [0, 1, 2, 3, 4]
        let pulseMs: UInt64 = 450
        let gapMs: UInt64 = 150
        let strength: UInt8 = 70

        for position in cleaned {
            stopVibration(position: position)
            countdowns[position] = sessionSeconds
        }

        let orderedPositions = cleaned.sorted { lhs, rhs in
            if lhs.contains("GloveL") { return true }
            if rhs.contains("GloveL") { return false }
            return lhs < rhs
        }

        Task { @MainActor in
            Logger.shared.log("vCR", "Finger check started before vCR for \(cleaned.joined(separator: ", "))")

            for position in orderedPositions {
                for motorIndex in fingerIndices {
                    sendSingleMotorOn(position: position, motorIndex: motorIndex, strength: strength)

                    try? await Task.sleep(nanoseconds: pulseMs * 1_000_000)

                    sendAllOff(position: position)

                    try? await Task.sleep(nanoseconds: gapMs * 1_000_000)
                }
            }

            for position in cleaned {
                startVibration(position: position, durationSeconds: sessionSeconds)
            }
        }
    }




    // MARK: - Low-level motor helpers
    private func sendBurstAll(position: String, strength: UInt8, burstMs: Int) {
        var arr = [UInt8](repeating: strength, count: 20)
        position.withCString { pstr in
            arr.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    BhapticsPlugin_playMotors(pstr, arr.count, base)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(burstMs)) {
            self.sendAllOff(position: position)
        }
    }

    private func sendBurst(position: String, motorIndex: Int, strength: UInt8, burstMs: Int) {
        var motors = [UInt8](repeating: 0, count: 20)
        if motorIndex >= 0 && motorIndex < motors.count {
            motors[motorIndex] = strength
        }
        position.withCString { pstr in
            motors.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    BhapticsPlugin_playMotors(pstr, motors.count, base)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(burstMs)) {
            self.sendAllOff(position: position)
        }
    }
    
    private func sendSingleMotorOn(position: String, motorIndex: Int, strength: UInt8) {
        var motors = [UInt8](repeating: 0, count: 20)

        if motorIndex >= 0 && motorIndex < motors.count {
            motors[motorIndex] = strength
        }

        position.withCString { pstr in
            motors.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    BhapticsPlugin_playMotors(pstr, motors.count, base)
                }
            }
        }
    }


    private func sendAllOff(position: String) {
        var off = [UInt8](repeating: 0, count: 20)
        position.withCString { pstr in
            off.withUnsafeBufferPointer { buf in
                if let base = buf.baseAddress {
                    BhapticsPlugin_playMotors(pstr, off.count, base)
                }
            }
        }
    }
}
