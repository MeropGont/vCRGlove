import Foundation

enum StimulationPattern: String, Codable, CaseIterable, Identifiable {
    case shuffled
    case simultaneous

    var id: String { rawValue }
    var titleKey: String { "research.pattern.\(rawValue)" }
}

struct StimulationProfile: Codable, Equatable {
    var version = 1
    var leftAmplitude: Double = 70
    var rightAmplitude: Double = 70
    var frequency: Double = 1.5
    var pattern: StimulationPattern = .shuffled

    static let pulseMs = 100
    static let slotsPerCycle = 4
    // Four non-overlapping 100 ms slots fit at most 2.5 cycles/second.
    static let frequencyRange = 0.5...2.5

    var isValid: Bool {
        version == 1 && leftAmplitude.isFinite && rightAmplitude.isFinite && frequency.isFinite
            && (0...100).contains(leftAmplitude) && (0...100).contains(rightAmplitude)
            && leftAmplitude.rounded() == leftAmplitude && rightAmplitude.rounded() == rightAmplitude
            && Self.frequencyRange.contains(frequency)
    }

    var cycleInterval: Double { 1 / frequency }
    var slotSpacing: Double { cycleInterval / Double(Self.slotsPerCycle) }

    func amplitude(for position: String) -> Double? {
        let position = position.lowercased()
        if position.contains("glovel") || position.contains("glove left") { return leftAmplitude }
        if position.contains("glover") || position.contains("glove right") { return rightAmplitude }
        return nil
    }

    func motorIndices(order: [Int]) -> [[Int]] {
        pattern == .shuffled ? order.map { [$0] } : order.map { _ in Array(0..<20) }
    }

    var eventDetails: [String: String] {
        ["profileVersion": String(version), "leftAmplitude": String(leftAmplitude),
         "rightAmplitude": String(rightAmplitude), "cycleFrequencyHz": String(frequency),
         "pattern": pattern.rawValue, "pulseMs": String(Self.pulseMs),
         "slotsPerCycle": String(Self.slotsPerCycle)]
    }
}

struct StimulationProfileStore {
    static let key = "vcrStimulationProfile.v1"
    let defaults: UserDefaults

    func load() throws -> StimulationProfile {
        guard let value = defaults.object(forKey: Self.key) else { return StimulationProfile() }
        guard let data = value as? Data else { throw ProfileError.invalid }
        let profile = try JSONDecoder().decode(StimulationProfile.self, from: data)
        guard profile.isValid else { throw ProfileError.invalid }
        return profile
    }

    func save(_ profile: StimulationProfile) throws {
        guard profile.isValid else { throw ProfileError.invalid }
        defaults.set(try JSONEncoder().encode(profile), forKey: Self.key)
    }

    enum ProfileError: Error { case invalid }
}
