import Foundation

/// Shared wire format. Old/untagged traffic must never enter a current trial.
enum WatchStreamProtocol {
    static let version = 1
    static let maximumBatchSize = 64

    static func command(_ type: String, id: UUID) -> [String: Any] {
        ["type": type, "streamID": id.uuidString, "protocolVersion": version]
    }

    static func streamID(in message: [String: Any]) -> UUID? {
        guard message["protocolVersion"] as? Int == version,
              let raw = message["streamID"] as? String else { return nil }
        return UUID(uuidString: raw)
    }

    static func validSamples(_ samples: [[Double]]) -> Bool {
        guard !samples.isEmpty, samples.count <= maximumBatchSize,
              samples.allSatisfy({ $0.count == 2 && $0[0].isFinite && $0[0] >= 0 && $0[1].isFinite }) else { return false }
        return zip(samples, samples.dropFirst()).allSatisfy { $0[0] < $1[0] }
    }
}

struct WatchStreamBatchCursor {
    let id: UUID
    private(set) var sequence = -1
    private(set) var lastTimestamp: Double?

    mutating func accept(_ message: [String: Any]) -> [[Double]]? {
        guard message["type"] as? String == "motionBatch",
              WatchStreamProtocol.streamID(in: message) == id,
              let next = message["sequence"] as? Int, next > sequence,
              let samples = message["samples"] as? [[Double]], WatchStreamProtocol.validSamples(samples),
              lastTimestamp.map({ samples[0][0] > $0 }) ?? true else { return nil }
        sequence = next
        lastTimestamp = samples.last?[0]
        return samples
    }
}

/// Late stops are harmless to a newer stream; stopped IDs cannot restart.
struct WatchStreamCommandGate {
    private(set) var activeID: UUID?
    private var ended: [UUID] = []

    mutating func start(_ id: UUID) -> Bool {
        guard !ended.contains(id), activeID == nil || activeID == id else { return false }
        activeID = id
        return true
    }

    @discardableResult mutating func end(_ id: UUID) -> Bool {
        if !ended.contains(id) {
            ended.append(id)
            if ended.count > 64 { ended.removeFirst() }
        }
        guard activeID == id else { return false }
        activeID = nil
        return true
    }
}
