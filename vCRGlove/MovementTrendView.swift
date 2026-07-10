//
//  MovementTrendView.swift
//  vCRGlove
//
//  Patient-facing trend view (Task E): plots one chosen movement metric over
//  time from TaskSessionStore.history(task:side:), with recordings colored by
//  their stimulation context (baseline / before / after session) — a clear
//  before/after visualization without any guessed UPDRS score.
//

import SwiftUI
import Charts

// MARK: - Which metric to plot

enum TrendMetric: String, CaseIterable, Identifiable {
    case frequency, amplitude, rhythm, decrement, pauses, onset, quality

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .frequency: return "Speed"
        case .amplitude: return "Amplitude"
        case .rhythm:    return "Rhythm variability"
        case .decrement: return "Amplitude decrement"
        case .pauses:    return "Pauses"
        case .onset:     return "Onset latency"
        case .quality:   return "Quality index"
        }
    }

    var unit: String {
        switch self {
        case .frequency: return "Hz"
        case .amplitude: return ""
        case .rhythm:    return "CV"
        case .decrement: return "/cycle"
        case .pauses:    return "count"
        case .onset:     return "s"
        case .quality:   return "0–1"
        }
    }

    /// Whether higher values mean better performance (for the footer hint).
    var higherIsBetter: Bool {
        switch self {
        case .frequency, .amplitude, .quality: return true
        case .rhythm, .pauses, .onset:         return false
        case .decrement:                       return false // more negative = worse
        }
    }

    func value(from m: MovementMetrics) -> Double {
        switch self {
        case .frequency: return m.frequencyHz
        case .amplitude: return m.meanAmplitude
        case .rhythm:    return m.rhythmCV
        case .decrement: return m.amplitudeDecrementSlope
        case .pauses:    return Double(m.pauseCount)
        case .onset:     return m.onsetLatencySec
        case .quality:   return m.qualityIndex
        }
    }
}

// MARK: - Trend view

struct MovementTrendView: View {
    @ObservedObject private var store = TaskSessionStore.shared

    @State private var taskType: MovementTaskType = .fingerTap
    @State private var side: BodySide = .right
    @State private var metric: TrendMetric = .frequency
    #if DEBUG
    @State private var isSeeding = false
    #endif

    private var points: [(date: Date, context: StimulationContext, metrics: MovementMetrics)] {
        store.history(task: taskType, side: side)
    }

    var body: some View {
        Form {
            Section {
                Picker("Movement", selection: $taskType) {
                    ForEach(MovementTaskType.allCases) { t in
                        Text("\(t.rawValue)  \(t.displayName)").tag(t)
                    }
                }
                Picker("Hand", selection: $side) {
                    Text("Left").tag(BodySide.left)
                    Text("Right").tag(BodySide.right)
                }
                .pickerStyle(.segmented)
                Picker("Metric", selection: $metric) {
                    ForEach(TrendMetric.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
            }

            Section {
                if points.isEmpty {
                    ContentUnavailableView(
                        "No recordings yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Record a \(taskType.displayName) test with your \(side.rawValue) hand to see trends here.")
                    )
                    .frame(minHeight: 220)
                } else {
                    chart
                        .frame(minHeight: 260)
                        .padding(.vertical, 8)
                }
            } header: {
                Text("\(metric.displayName) over time")
            } footer: {
                if !points.isEmpty {
                    Text(metric.higherIsBetter
                         ? "Higher values indicate faster/larger movement."
                         : "Lower values indicate steadier movement.")
                }
            }

            #if DEBUG
            Section("Developer") {
                Button {
                    // Generating + analyzing 28 synthetic trials takes seconds —
                    // run off the main thread and show a labeled busy state.
                    isSeeding = true
                    let task = taskType, side = side
                    DispatchQueue.global(qos: .userInitiated).async {
                        TrendSampleDataSeeder.seed(task: task, side: side)
                        DispatchQueue.main.async { isSeeding = false }
                    }
                } label: {
                    if isSeeding {
                        Label { Text("Generating sample data…") } icon: { ProgressView() }
                    } else {
                        Text("Add sample data (14 days)")
                    }
                }
                .disabled(isSeeding)
            }
            #endif
        }
        .navigationTitle("Trends")
    }

    private var chart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(
                    x: .value("Date", p.date),
                    y: .value(metric.displayName, metric.value(from: p.metrics))
                )
                .foregroundStyle(.gray.opacity(0.4))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", p.date),
                    y: .value(metric.displayName, metric.value(from: p.metrics))
                )
                .foregroundStyle(by: .value("Context", contextLabel(p.context)))
                .symbolSize(80)
            }
        }
        .chartForegroundStyleScale([
            "Baseline": Color.gray,
            "Before session": Color.orange,
            "After session": Color.green,
            "Unspecified": Color.blue
        ])
        .chartYAxisLabel(metric.unit)
        .chartLegend(position: .bottom, spacing: 12)
    }

    private func contextLabel(_ c: StimulationContext) -> String {
        switch c {
        case .baseline:    return "Baseline"
        case .preStim:     return "Before session"
        case .postStim:    return "After session"
        case .unspecified: return "Unspecified"
        }
    }
}

// MARK: - DEBUG sample data

#if DEBUG
/// Seeds two weeks of plausible pre/post sessions so the trend chart can be
/// developed and demoed in the Simulator. DEBUG builds only.
enum TrendSampleDataSeeder {
    static func seed(task: MovementTaskType, side: BodySide, days: Int = 14) {
        let analyzer = MovementAnalyzer()
        let calendar = Calendar.current
        for day in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -(days - 1 - day), to: Date()) else { continue }
            // Gradual improvement over the study + acute post-stim benefit.
            let progress = Double(day) / Double(max(days - 1, 1))   // 0…1
            for (context, boost) in [(StimulationContext.preStim, 0.0),
                                     (StimulationContext.postStim, 0.25)] {
                var params = SyntheticSignalGenerator.Params.parkinsonian
                let improvement = min(progress * 0.5 + boost, 1.0)
                params.frequencyHz   = 2.2 + 2.0 * improvement
                params.decrementPerSec = 0.12 * (1 - improvement)
                params.jitterFraction  = 0.18 * (1 - improvement)
                params.pauseAtSec      = improvement > 0.4 ? [] : [3.5]
                var gen = SyntheticSignalGenerator(params: params,
                                                   seed: UInt64(day * 2 + (context == .postStim ? 1 : 0)))
                let samples = gen.generate()
                let trial = Trial(taskType: task, side: side, source: .synthetic,
                                  stopCondition: .tenReps, startedAt: date,
                                  samples: samples, metrics: analyzer.analyze(samples))
                let session = MovementSession(patientId: "sample", date: date,
                                              stimulationContext: context, trials: [trial])
                TaskSessionStore.shared.add(session)
            }
        }
    }
}
#endif

#Preview {
    NavigationStack { MovementTrendView() }
}
