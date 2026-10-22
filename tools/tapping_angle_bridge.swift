// Offline research CLI only. Compiled beside the actual app models/analyzer, never added to the app target.
import Foundation

// Unused UI/journal dependencies of MovementModels; no alternate measurement implementation.
func L10n(_ key: String) -> String { key }
enum AppSettings {
    enum Language: String { case en }
    struct Shared { let language = Language.en }
    static let shared = Shared()
}
struct JournalEntry {
    enum Kind { case medication }
    enum Event { case usual, late, extra }
    let type: Kind
    let date: Date
    let medicationEvent: Event?
}

struct Input: Decodable { let key: String; let samples: [TimestampedSample] }
struct Output: Encodable {
    let key: String
    let metrics: MovementMetrics
    let intervalCount: Int
    let amplitudeComparisonCount: Int
    let cycleEventTimes: [Double]
    let maximumSampleGapSeconds: Double
    let measurementVersion: String
}
do {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    let inputs = try JSONDecoder().decode([Input].self, from: data)
    let analyzer = MovementAnalyzer(config: .camera)
    let results = inputs.map { input in
        let evidence = analyzer.analyzeWithEvidence(input.samples)
        return Output(key: input.key, metrics: evidence.metrics, intervalCount: evidence.intervalCount,
                      amplitudeComparisonCount: evidence.amplitudeComparisonCount,
                      cycleEventTimes: evidence.cycleEventTimes,
                      maximumSampleGapSeconds: analyzer.config.maximumSampleGap ?? 0,
                      measurementVersion: MovementMeasurementVersion.camera)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    FileHandle.standardOutput.write(try encoder.encode(results))
} catch {
    FileHandle.standardError.write(Data("Offline analyzer failed: \(error)\n".utf8))
    exit(1)
}
