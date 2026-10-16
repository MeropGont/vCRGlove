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
        isConnected == true && !pos.isEmpty
    }

    var connectionStatusText: String {
        if isReadyForStimulation {
            return L10n("Ready")
        }

        if isPaired == true {
            return L10n("Detected")
        }

        return L10n("Disconnected")
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


// MARK: - ViewModel
@MainActor
final class GloveVM: ObservableObject {
    @Published var scanning = false
    @Published var devices: [HDevice] = []
    @Published var countdowns: [String: Int] = [:]
    @Published var pausedPositions: Set<String> = []
    
    // deal with possible interruptions
    @Published var timingCompromiseMessage: LocalizedStringKey?

    private var backgroundedDuringStimulationAt: Date?
    private var stimulationBackgroundTask: UIBackgroundTaskIdentifier = .invalid


    @Published private(set) var stimulationProfile: StimulationProfile
    @Published private(set) var configurationNeedsReview = false
    @Published private(set) var researchUnlocked = false
    @Published private(set) var isCheckingFingers = false
    @Published var totalSeconds: Double = 4 * 60 * 60
    var patientSessionWasStarted = false
    var patientSessionPausedForNoGloves = false

    private let profileStore: StimulationProfileStore
    private let motorOutput: (String, [UInt8]) -> Void
    private let stopOutput: () -> Void
    private let recordEvent: (String, [String: String]) -> Void
    private(set) var sessionProfile: StimulationProfile?
    // Reject delayed callbacks from an earlier run or pulse after stop/restart.
    private var runIDs: [String: UUID] = [:]
    private var pulseIDs: [String: UUID] = [:]
    private var fingerCheckTask: Task<Void, Never>?
    private var fingerCheckID: UUID?

    var hasStimulationSession: Bool {
        isCheckingFingers || countdowns.values.contains { $0 > 0 }
    }

    init(defaults: UserDefaults? = nil,
         motorOutput: @escaping (String, [UInt8]) -> Void = { position, motors in
             position.withCString { pstr in
                 motors.withUnsafeBufferPointer { buffer in
                     if let base = buffer.baseAddress { BhapticsPlugin_playMotors(pstr, motors.count, base) }
                 }
             }
         },
         stopOutput: @escaping () -> Void = { BhapticsPlugin_stop() },
         recordEvent: @escaping (String, [String: String]) -> Void = { type, details in
             EventStore.shared.append(type: type, tag: "vCR", message: type, details: details)
         }) {
        profileStore = StimulationProfileStore(defaults: defaults ?? Self.profileDefaults())
        self.motorOutput = motorOutput
        self.stopOutput = stopOutput
        self.recordEvent = recordEvent
        do { stimulationProfile = try profileStore.load() }
        catch {
            stimulationProfile = StimulationProfile()
            configurationNeedsReview = true
        }
    }

    private static func profileDefaults() -> UserDefaults {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--ui-test-stimulation-profile"), index + 1 < arguments.count,
           let suite = UserDefaults(suiteName: "stimulation-ui-\(arguments[index + 1])") {
            return suite
        }
        #endif
        return .standard
    }

    @discardableResult
    func unlockResearch(password: String) -> Bool {
        guard password == "vcr2026" else { return false }
        researchUnlocked = true
        recordEvent("research_unlocked", [:])
        return true
    }

    func lockResearch() {
        researchUnlocked = false
        recordEvent("research_locked", [:])
    }

    @discardableResult
    func saveStimulationProfile(_ profile: StimulationProfile) -> Bool {
        guard researchUnlocked, !hasStimulationSession, profile.isValid else { return false }
        do {
            let previous = stimulationProfile
            try profileStore.save(profile)
            stimulationProfile = profile
            configurationNeedsReview = false
            var details = profile.eventDetails
            for (key, value) in previous.eventDetails { details["previous_\(key)"] = value }
            recordEvent("stimulation_profile_saved", details)
            return true
        } catch { return false }
    }

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
        let clearHistory = clearHistory && !hasStimulationSession
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
    
    private func deviceMergeScore(_ device: HDevice) -> Int {
        var score = 0

        if device.isConnected == true { score += 1000 }
        if device.isPaired == true { score += 100 }
        if device.battery != nil { score += 25 }
        if !device.pos.isEmpty { score += 10 }
        if device.isLeftGlove || device.isRightGlove { score += 5 }

        return score
    }

    private func mergeDuplicateDevices(_ candidates: [HDevice]) -> [HDevice] {
        var byId: [String: HDevice] = [:]

        for device in candidates {
            guard !device.id.isEmpty else { continue }

            if let existing = byId[device.id] {
                byId[device.id] = deviceMergeScore(device) >= deviceMergeScore(existing) ? device : existing
            } else {
                byId[device.id] = device
            }
        }

        return Array(byId.values)
    }


    func refreshDevices() {
        guard let cstr = BhapticsPlugin_getDevices() else { return }
        let raw = String(cString: cstr)

        if UserDefaults.standard.bool(forKey: "debugVerboseBLELogging") {
            Logger.shared.log("BLE_RAW", raw)
        }


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


        let unique = mergeDuplicateDevices(newDevices)

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
        guard !hasStimulationSession, !configurationNeedsReview else { return }
        guard let amplitude = stimulationProfile.amplitude(for: device.pos) else {
            Logger.shared.log("BLE", "Cannot buzz \(device.prettyName): unknown glove position")
            return
        }

        sendPulse(position: device.pos, indices: Array(0..<20), strength: UInt8(amplitude), burstMs: 120)
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
    func startVibration(position: String, durationSeconds: Int? = nil, logEvent: Bool = true) {
        let profile = sessionProfile ?? stimulationProfile
        guard !configurationNeedsReview, profile.isValid,
              let amp = profile.amplitude(for: position) else { return }
        let sessionSeconds = durationSeconds ?? Int(totalSeconds)
        guard sessionSeconds > 0 else { return }
        stopVibration(position: position, logEvent: false)
        sessionProfile = profile
        startedAt[position] = Date()
        countdowns[position] = sessionSeconds
        let runID = UUID()
        runIDs[position] = runID

        let timer = Timer(timeInterval: profile.cycleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.runIDs[position] == runID,
                      let start = self.startedAt[position] else { return }
                let remaining = max(sessionSeconds - Int(Date().timeIntervalSince(start)), 0)
                self.countdowns[position] = remaining
                guard remaining > 0 else {
                    self.stopVibration(position: position)
                    return
                }

                let order = Array(0..<StimulationProfile.slotsPerCycle).shuffled()
                for (slot, indices) in profile.motorIndices(order: order).enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(slot) * profile.slotSpacing) { [weak self] in
                        guard let self, self.runIDs[position] == runID,
                              Date().timeIntervalSince(start) < Double(sessionSeconds) else { return }
                        self.sendPulse(position: position, indices: indices, strength: UInt8(amp),
                                       burstMs: StimulationProfile.pulseMs)
                    }
                }
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        vibTimers[position] = timer
        activeStimPositions.insert(position)
        updateIdleTimerLock()

        if logEvent {
            Logger.shared.log("vCR", "Start vibration @ \(position) [total=\(sessionSeconds)s]")
        }
        var details = profile.eventDetails
        details["position"] = position
        details["effectiveAmplitude"] = String(amp)
        details["durationSeconds"] = String(sessionSeconds)
        recordEvent("stimulation_started", details)
    }

    func stopVibration(position: String, logEvent: Bool = true) {
        cancelFingerCheck()
        runIDs[position] = nil
        vibTimers[position]?.invalidate()
        vibTimers[position] = nil
        countdowns[position] = 0
        startedAt[position] = nil
        activeStimPositions.remove(position)
        pausedPositions.remove(position)

        sendAllOff(position: position)

        if activeStimPositions.isEmpty {
            stopOutput()
        }

        updateIdleTimerLock()
        
        if activeStimPositions.isEmpty {
            endStimulationBackgroundTaskIfNeeded()
        }
        if !hasStimulationSession { sessionProfile = nil }

        if logEvent {
            Logger.shared.log("vCR", "Stopped vibration @ \(position)")
        }
    }

    func resumeVibration(position: String) {
        guard pausedPositions.contains(position) else { return }
        guard let remaining = countdowns[position], remaining > 0 else {
            stopVibration(position: position)
            return
        }

        pausedPositions.remove(position)
        startVibration(position: position, durationSeconds: remaining, logEvent: false)

        Logger.shared.log("vCR", "Resumed vibration @ \(position)")
    }

    
    func pauseVibration(position: String) {
        cancelFingerCheck()
        guard vibTimers[position] != nil else { return }
        runIDs[position] = nil
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
        let profile = stimulationProfile
        guard !hasStimulationSession, !configurationNeedsReview, profile.isValid,
              !cleaned.isEmpty, cleaned.allSatisfy({ profile.amplitude(for: $0) != nil }) else { return }
        let sessionSeconds = durationSeconds ?? Int(totalSeconds)
        guard sessionSeconds > 0 else { return }
        let fingerIndices = [0, 1, 2, 3, 4]
        let pulseMs: UInt64 = 450
        let gapMs: UInt64 = 150

        for position in cleaned {
            stopVibration(position: position, logEvent: false)
            countdowns[position] = sessionSeconds
        }
        sessionProfile = profile
        let checkID = UUID()
        fingerCheckID = checkID
        isCheckingFingers = true
        activeStimPositions.formUnion(cleaned)
        updateIdleTimerLock()

        let orderedPositions = cleaned.sorted { lhs, rhs in
            let left = lhs.lowercased().contains("glovel") || lhs.lowercased().contains("glove left")
            let right = rhs.lowercased().contains("glovel") || rhs.lowercased().contains("glove left")
            if left != right { return left }
            return lhs < rhs
        }

        fingerCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            Logger.shared.log("vCR", "Finger check started before vCR for \(cleaned.joined(separator: ", "))")
            self.recordEvent("finger_check_started", profile.eventDetails)

            for position in orderedPositions {
                guard let amplitude = profile.amplitude(for: position) else { return }
                let strength = UInt8(amplitude)
                for motorIndex in fingerIndices {
                    guard !Task.isCancelled, self.fingerCheckID == checkID else { return }
                    self.sendSingleMotorOn(position: position, motorIndex: motorIndex, strength: strength)
                    do { try await Task.sleep(nanoseconds: pulseMs * 1_000_000) }
                    catch { return }
                    guard self.fingerCheckID == checkID else { return }
                    self.sendAllOff(position: position)
                    do { try await Task.sleep(nanoseconds: gapMs * 1_000_000) }
                    catch { return }
                }
            }
            guard !Task.isCancelled, self.fingerCheckID == checkID else { return }
            self.fingerCheckID = nil
            self.fingerCheckTask = nil
            self.isCheckingFingers = false
            for position in cleaned {
                self.startVibration(position: position, durationSeconds: sessionSeconds)
            }
        }
    }

    private func cancelFingerCheck() {
        guard fingerCheckID != nil else { return }
        fingerCheckTask?.cancel()
        fingerCheckTask = nil
        fingerCheckID = nil
        isCheckingFingers = false
        for position in activeStimPositions {
            pausedPositions.insert(position)
            sendAllOff(position: position)
        }
        activeStimPositions.removeAll()
        updateIdleTimerLock()
        recordEvent("finger_check_cancelled", [:])
    }

    // MARK: - Low-level motor helpers
    private func sendPulse(position: String, indices: [Int], strength: UInt8, burstMs: Int) {
        let pulseID = UUID()
        pulseIDs[position] = pulseID
        var motors = [UInt8](repeating: 0, count: 20)
        for index in indices where motors.indices.contains(index) { motors[index] = strength }
        motorOutput(position, motors)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(burstMs)) { [weak self] in
            guard let self, self.pulseIDs[position] == pulseID else { return }
            self.sendAllOff(position: position)
        }
    }
    
    private func sendSingleMotorOn(position: String, motorIndex: Int, strength: UInt8) {
        var motors = [UInt8](repeating: 0, count: 20)

        if motorIndex >= 0 && motorIndex < motors.count {
            motors[motorIndex] = strength
        }

        motorOutput(position, motors)
    }


    private func sendAllOff(position: String) {
        pulseIDs[position] = nil
        motorOutput(position, [UInt8](repeating: 0, count: 20))
    }
}
