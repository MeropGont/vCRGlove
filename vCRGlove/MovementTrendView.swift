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
        case .frequency: return L10n("Speed")
        case .amplitude: return L10n("Amplitude")
        case .rhythm:    return L10n("Rhythm variability")
        case .decrement: return L10n("Amplitude decrement")
        case .pauses:    return L10n("Pauses")
        case .onset:     return L10n("Onset latency")
        case .quality:   return L10n("Quality index")
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
                Text(String(format: L10n("%@ over time"), metric.displayName))
            } footer: {
                if !points.isEmpty {
                    Text(L10n(metric.higherIsBetter
                         ? "Higher values indicate faster/larger movement."
                         : "Lower values indicate steadier movement."))
                }
            }

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

#Preview {
    NavigationStack { MovementTrendView() }
}
