//
//  GloveVM.swift
//  vCRGlove
//
//  Created by Tactile Glove on 03.09.25.
//

import Foundation
import BhapticsPlugin

// MARK: - HDevice model
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
        let n = (name ?? "").lowercased()
        let p = (position ?? "").lowercased()
        return p.contains("glove") || n.contains("tactglove")
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

// MARK: - Buzz pattern
enum BuzzPattern: String, CaseIterable {
    case constant = "Constant"
    case pulse = "Pulse"
    case intermittent = "Intermittent"
}

// MARK: - View Model
@MainActor
final class GloveVM: ObservableObject {
    @Published var scanning = false
    @Published var devices: [HDevice] = []
    @Published var log: [String] = []
    @Published var countdowns: [String: Int] = [:]
    @Published var pattern: BuzzPattern = .constant

    private var localState: [String: (connected: Bool?, paired: Bool?)] = [:]
    private var pollTimer: Timer?
    private var longBuzzTimers: [String: Timer] = [:]
    private var startedAt: [String: Date] = [:]
    private var vcrTimers: [String: Timer] = [:]

    // ---- Scan / Pair / Disconnect ----
    func startScan() {
        log.append("Scanning…")
        scanning = true
        BhapticsPlugin_scan()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    func stopScan() {
        scanning = false
        BhapticsPlugin_stopScan()
        pollTimer?.invalidate()
        pollTimer = nil
        refreshDevices()
    }

    func refreshDevices() {
        guard let cstr = BhapticsPlugin_getDevices() else { return }
        let raw = String(cString: cstr)

        var newDevices: [HDevice] = []
        if let data = raw.data(using: .utf8) {
            if let arr = try? JSONDecoder().decode([HDevice].self, from: data) {
                newDevices = arr
            } else {
                struct Wrapper: Decodable { let devices: [HDevice]? }
                newDevices = (try? JSONDecoder().decode(Wrapper.self, from: data))?.devices ?? []
            }
        }

        newDevices = newDevices.filter { $0.isGlove }
        var byId: [String: HDevice] = [:]
        for d in newDevices { byId[d.id] = d }
        var unique = Array(byId.values)

        unique = unique.map { dev in
            var m = dev
            if let override = localState[dev.id] {
                if m.isConnected != true { m.isConnected = override.connected ?? m.isConnected }
                if m.isPaired    != true { m.isPaired    = override.paired    ?? m.isPaired }
            }
            return m
        }

        self.devices = unique.sorted { ($0.position ?? "") < ($1.position ?? "") }
    }

    func pair(device: HDevice) {
        device.id.withCString { BhapticsPlugin_pair($0) }
        log.append("Pairing \(device.prettyName)")
        localState[device.id] = (connected: true, paired: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.refreshDevices()
            self.autoBuzz(position: device.pos)
        }
    }

    func disconnect(device: HDevice) {
        device.id.withCString { BhapticsPlugin_unpair($0) }
        stopLongBuzz(position: device.pos)
        localState[device.id] = (connected: false, paired: false)
        log.append("Disconnecting \(device.prettyName)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.refreshDevices() }
    }

    func disconnectAll() {
        for d in devices {
            d.id.withCString { BhapticsPlugin_unpair($0) }
            stopLongBuzz(position: d.pos)
            localState[d.id] = (connected: false, paired: false)
        }
        BhapticsPlugin_stop()
        log.append("Disconnect all requested")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.refreshDevices() }
    }

    private func autoBuzz(position pos: String) {
        sendMotors(position: pos, strength: 70)
        log.append("Auto-buzzed \(pos)")
    }

    // ---- Simple vibration ----
    func vibrateLeft(strength: UInt8 = 70) {
        sendMotors(position: "GloveL", strength: strength)
        log.append("Manual vibrate left (\(strength))")
    }

    func vibrateRight(strength: UInt8 = 70) {
        sendMotors(position: "GloveR", strength: strength)
        log.append("Manual vibrate right (\(strength))")
    }

    private func sendMotors(position: String, strength: UInt8) {
        var motors = [UInt8](repeating: strength, count: 20)
        motors.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            position.withCString { pstr in
                BhapticsPlugin_playMotors(pstr, motors.count, base)
            }
        }
    }

    // ---- Long buzz (1h toggle) ----
    func toggleLongBuzz(position: String, seconds: Int = 3600, pattern: BuzzPattern) {
        if longBuzzTimers[position] != nil {
            stopLongBuzz(position: position)
        } else {
            startLongBuzz(position: position, seconds: seconds, pattern: pattern)
        }
    }

    func startLongBuzz(position: String, seconds: Int = 3600, pattern: BuzzPattern) {
        stopLongBuzz(position: position)
        countdowns[position] = seconds
        startedAt[position] = Date()
        log.append("Started \(pattern.rawValue) buzz @ \(position)")

        let interval: TimeInterval = (pattern == .constant) ? 0.2 : 1.0

        longBuzzTimers[position] = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            guard let started = self.startedAt[position] else { return }

            let elapsed = Int(Date().timeIntervalSince(started))
            let remaining = max(seconds - elapsed, 0)
            self.countdowns[position] = remaining
            if remaining <= 0 {
                self.stopLongBuzz(position: position)
                return
            }

            switch pattern {
            case .constant:
                self.sendMotors(position: position, strength: 100)
            case .pulse:
                if elapsed % 2 == 0 { self.sendMotors(position: position, strength: 80) }
                else { self.sendMotors(position: position, strength: 0) }
            case .intermittent:
                if elapsed % 5 == 0 { self.sendMotors(position: position, strength: 70) }
            }
        }
    }

    private func stopLongBuzz(position: String) {
        longBuzzTimers[position]?.invalidate()
        longBuzzTimers[position] = nil
        if let start = startedAt[position] {
            let elapsed = Int(Date().timeIntervalSince(start))
            let mins = elapsed / 60, secs = elapsed % 60
            log.append("Stopped long buzz @ \(position) after \(mins)m \(secs)s")
        } else {
            log.append("Stopped long buzz @ \(position)")
        }
        countdowns[position] = 0
        startedAt[position] = nil
        BhapticsPlugin_stop()
    }

    func isLongBuzzing(_ position: String) -> Bool {
        return longBuzzTimers[position] != nil
    }

    // ---- vCR sequence (cycled bursts) ----
    func performVCRSequence(position: String,
                            strength: UInt8 = 70,
                            cycleHz: Double = 1.5,
                            burstMs: Int = 100,
                            motorsPerBurst: [Int] = [0,1,2,3]) {
        stopVCR(position: position)

        let cycleInterval = 1.0 / cycleHz
        vcrTimers[position] = Timer.scheduledTimer(withTimeInterval: cycleInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            let shuffled = motorsPerBurst.shuffled()
            for (i, motorIndex) in shuffled.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1) {
                    self.sendBurst(position: position,
                                   motorIndex: motorIndex,
                                   strength: strength,
                                   burstMs: burstMs)
                }
            }
            self.log.append("vCR cycle @ \(position)")
        }
    }

    func stopVCR(position: String) {
        vcrTimers[position]?.invalidate()
        vcrTimers[position] = nil
        log.append("Stopped vCR @ \(position)")
    }

    private func sendBurst(position: String, motorIndex: Int,
                           strength: UInt8, burstMs: Int) {
        var motors = [UInt8](repeating: 0, count: 20)
        if motorIndex < motors.count { motors[motorIndex] = strength }
        motors.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            position.withCString { pstr in
                BhapticsPlugin_playMotors(pstr, motors.count, base)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(burstMs)) {
            var motorsOff = [UInt8](repeating: 0, count: 20)
            motorsOff.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                position.withCString { pstr in
                    BhapticsPlugin_playMotors(pstr, motorsOff.count, base)
                }
            }
        }
    }
}
