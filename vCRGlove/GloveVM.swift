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
    }

    static func == (lhs: HDevice, rhs: HDevice) -> Bool { lhs.id == rhs.id }
}

extension HDevice {
    var isReadyForStimulation: Bool {
        isConnected == true || isPaired == true
    }

    var connectionStatusText: String {
        if isConnected == true || isPaired == true {
            return "Ready"
        }

        return "Not ready"
    }

    var isLeftGlove: Bool {
        let text = "\(position ?? "") \(name ?? "") \(id)".lowercased()
        return text.contains("glovel")
            || text.contains("glove left")
            || text.contains("left glove")
            || text.contains("left")
    }

    var isRightGlove: Bool {
        let text = "\(position ?? "") \(name ?? "") \(id)".lowercased()
        return text.contains("glover")
            || text.contains("glove right")
            || text.contains("right glove")
            || text.contains("right")
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

    // Vibration params (manual mode)
    @Published var amplitude: Double = 70
    @Published var frequency: Double = 1.5
    @Published var pulseMs: Double = 100
    @Published var totalSeconds: Double = 2 * 60 * 60
    @Published var fingersPerCycle: Int = 4

    // vCR toggle
    @Published var vcrMode = false

    private var localState: [String: (connected: Bool?, paired: Bool?)] = [:]
    private var pollTimer: Timer?
    private var vibTimers: [String: Timer] = [:]
    private var startedAt: [String: Date] = [:]
    private var activeStimPositions: Set<String> = []
    private var lastNoGloveCandidateLog: Date?

    private func updateIdleTimerLock() {
        UIApplication.shared.isIdleTimerDisabled = !activeStimPositions.isEmpty
    }


    // MARK: - Scan
    func startScan() {
        Logger.shared.log("BLE", "Fresh scan started")
        scanning = true

        pollTimer?.invalidate()
        pollTimer = nil

        devices = []
        countdowns = [:]
        localState = [:]

        BhapticsPlugin_stopScan()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
    func startVibration(position: String) {
        stopVibration(position: position)
        startedAt[position] = Date()
        countdowns[position] = Int(totalSeconds)

        let amp    = vcrMode ? VCRPreset.amplitude : amplitude
        let freq   = vcrMode ? VCRPreset.frequency : frequency
        let pMs    = vcrMode ? VCRPreset.pulseMs : Int(pulseMs)
        let fingers = vcrMode ? VCRPreset.fingersPerCycle : max(1, min(4, fingersPerCycle))

        let cycleInterval = max(0.1, 1.0 / max(0.1, freq))
        let pulseSec      = max(0.02, Double(pMs) / 1000.0)
        let slots         = max(1, fingers)
        let slotSpacing   = cycleInterval / Double(slots)

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
                    let remaining = max(Int(self.totalSeconds) - elapsed, 0)
                    self.countdowns[position] = remaining
                    if remaining <= 0 { self.stopVibration(position: position) }
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        vibTimers[position] = timer
        activeStimPositions.insert(position)
        updateIdleTimerLock()
        
        Logger.shared.log("vCR", "Start vibration @ \(position) [amp=\(Int(amp))%, freq=\(String(format: "%.2f", freq))Hz, pulse=\(pMs)ms, fingers=\(fingers), total=\(Int(totalSeconds))s]")

    }

    func stopVibration(position: String) {
        vibTimers[position]?.invalidate()
        vibTimers[position] = nil
        countdowns[position] = 0
        startedAt[position] = nil
        activeStimPositions.remove(position)
        updateIdleTimerLock()

        BhapticsPlugin_stop()
        Logger.shared.log("vCR", "Stopped vibration @ \(position)")
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
