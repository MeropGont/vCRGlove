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
        case .frequency: return L10n("Hz")
        case .amplitude: return ""
        case .rhythm:    return L10n("CV")
        case .decrement: return L10n("/cycle")
        case .pauses:    return L10n("count")
        case .onset:     return L10n("s")
        case .quality:   return L10n("0–1")
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
                Picker(L10n("Movement"), selection: $taskType) {
                    ForEach(MovementTaskType.allCases) { t in
                        Text("\(t.rawValue)  \(t.displayName)").tag(t)
                    }
                }
                Picker(L10n("Hand"), selection: $side) {
                    Text(BodySide.left.displayName).tag(BodySide.left)
                    Text(BodySide.right.displayName).tag(BodySide.right)
                }
                .pickerStyle(.segmented)
                Picker(L10n("Metric"), selection: $metric) {
                    ForEach(TrendMetric.allCases) { m in
                        Text(m.displayName).tag(m)
                    }
                }
            }

            Section {
                if points.isEmpty {
                    ContentUnavailableView(
                        L10n("No recordings yet"),
                        systemImage: "chart.xyaxis.line",
                        description: Text(String(format: L10n("Record a %@ test with your %@ hand to see trends here."), taskType.displayName, side.displayName))
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
        .navigationTitle(L10n("Trends"))
    }

    private var chart: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                LineMark(
                    x: .value(L10n("Date"), p.date),
                    y: .value(metric.displayName, metric.value(from: p.metrics))
                )
                .foregroundStyle(.gray.opacity(0.4))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value(L10n("Date"), p.date),
                    y: .value(metric.displayName, metric.value(from: p.metrics))
                )
                .foregroundStyle(by: .value(L10n("Context"), contextLabel(p.context)))
                .symbolSize(80)
            }
        }
        .chartForegroundStyleScale([
            contextLabel(.baseline): Color.gray,
            contextLabel(.preStim): Color.orange,
            contextLabel(.postStim): Color.green,
            contextLabel(.unspecified): Color.blue
        ])
        .chartYAxisLabel(metric.unit)
        .chartLegend(position: .bottom, spacing: 12)
    }

    private func contextLabel(_ c: StimulationContext) -> String {
        switch c {
        case .baseline:    return L10n("Baseline")
        case .preStim:     return L10n("Before session")
        case .postStim:    return L10n("After session")
        case .unspecified: return L10n("Unspecified")
        }
    }
}

#Preview {
    NavigationStack { MovementTrendView() }
}
