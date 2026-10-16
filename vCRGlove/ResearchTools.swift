import SwiftUI
import Combine

// MARK: - Shared Event Logger
final class Logger: ObservableObject {
    static let shared = Logger()
    @Published private(set) var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let tag: String
        let message: String
        var repeatCount: Int = 1

        var line: String {
            let repeatText = repeatCount > 1 ? "  x\(repeatCount)" : ""
            return "\(Logger.df.string(from: date)) [\(tag.uppercased())] \(message)\(repeatText)"
        }
    }

    private static let df: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    private let hiddenVisibleTags: Set<String> = [
        "BLE_RAW"
    ]

    private let hiddenVisibleMessageFragments: [String] = [
        "Showing ",
        "detected bHaptics device",
        "Scan stopped"
    ]

    func log(_ tag: String, _ message: String) {
        if shouldPersistToEventLog(tag: tag, message: message) {
            EventStore.shared.append(
                type: "app_event",
                tag: tag,
                message: message
            )
        }

        guard shouldShowInVisibleLog(tag: tag, message: message) else {
            return
        }

        DispatchQueue.main.async {
            if let last = self.entries.last,
               last.tag == tag,
               last.message == message {
                var updated = last
                updated.repeatCount += 1
                self.entries[self.entries.count - 1] = updated
            } else {
                self.entries.append(.init(date: Date(), tag: tag, message: message))
            }

            if self.entries.count > 300 {
                self.entries.removeFirst(self.entries.count - 300)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }

    private func shouldShowInVisibleLog(tag: String, message: String) -> Bool {
        if hiddenVisibleTags.contains(tag.uppercased()) {
            return false
        }

        for fragment in hiddenVisibleMessageFragments {
            if message.contains(fragment) {
                return false
            }
        }

        return true
    }

    private func shouldPersistToEventLog(tag: String, message: String) -> Bool {
        if UserDefaults.standard.bool(forKey: "debugVerboseBLELogging") {
            return true
        }

        let normalizedTag = tag.uppercased()

        if normalizedTag == "BLE_RAW" || normalizedTag == "BLE_NATIVE" {
            return false
        }

        if normalizedTag == "BLE" && message.contains("detected bHaptics device") {
            return false
        }

        if normalizedTag == "BLE" && message == "Scan stopped" {
            return false
        }

        return true
    }
}


// MARK: - Research Diagnostics
struct LogsPanel: View {
    @ObservedObject var logger: Logger

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L10n("Logs"), systemImage: "doc.plaintext")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    logger.clear()
                } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n("Clear Visible Log"))
            }

            Divider().padding(.top, -2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(logger.entries) { e in
                            Text(e.line)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 12)
                    .id("bottom")
                }
                .onChange(of: logger.entries.count) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .padding(10)
    }
}

struct ResearchUnlockView: View {
    @ObservedObject var vm: GloveVM
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var incorrectPassword = false

    var body: some View {
        NavigationStack {
            Form {
                SecureField(L10n("Password"), text: $password)
                    .textContentType(.password)
                    .accessibilityIdentifier("researchPassword")
                if incorrectPassword {
                    Text(L10n("Incorrect password"))
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("researchPasswordError")
                }
                Button(L10n("Unlock Research Mode")) {
                    if vm.unlockResearch(password: password) { dismiss() }
                    else { incorrectPassword = true }
                    password = ""
                }
                .disabled(password.isEmpty)
                .accessibilityIdentifier("researchUnlockConfirm")
            }
            .navigationTitle(L10n("research.staff"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n("Cancel")) { dismiss() }
                }
            }
        }
    }
}

struct ResearchStimulationControls: View {
    @ObservedObject var vm: GloveVM
    @State private var draft = StimulationProfile()
    @State private var expanded = false
    @State private var saveMessage: String?

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 18) {
                amplitudeControl("research.amplitude.left", value: $draft.leftAmplitude, id: "researchAmplitudeLeft")
                amplitudeControl("research.amplitude.right", value: $draft.rightAmplitude, id: "researchAmplitudeRight")

                Stepper(value: $draft.frequency, in: StimulationProfile.frequencyRange, step: 0.1) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("research.frequency"))
                        Text(draft.frequency, format: .number.precision(.fractionLength(1))) + Text(" Hz")
                    }
                }
                .accessibilityIdentifier("researchFrequency")

                Menu {
                    ForEach(StimulationPattern.allCases) { pattern in
                        Button {
                            draft.pattern = pattern
                        } label: {
                            if pattern == draft.pattern {
                                Label(L10n(pattern.titleKey), systemImage: "checkmark")
                            } else {
                                Text(L10n(pattern.titleKey))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Text(L10n(draft.pattern.titleKey))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .accessibilityLabel(L10n("research.pattern") + ", " + L10n(draft.pattern.titleKey))
                .accessibilityIdentifier("researchPattern")

                Text(L10n("research.pattern.explanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    saveMessage = vm.saveStimulationProfile(draft) ? "research.saved" : "research.saveFailed"
                } label: {
                    Label(L10n("research.save"), systemImage: "checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draft.isValid || (draft == vm.stimulationProfile && !vm.configurationNeedsReview))
                .accessibilityIdentifier("researchSaveParameters")
            }
            .disabled(vm.hasStimulationSession)
            .padding(.top, 12)

            if vm.hasStimulationSession {
                Text(L10n("research.stopToEdit"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let saveMessage {
                Text(L10n(saveMessage))
                    .font(.caption)
                    .accessibilityIdentifier("researchSaveMessage")
            }
        } label: {
            Label(L10n("research.parameters"), systemImage: "slider.horizontal.3")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("researchParameters")
        }
        .padding(.vertical, 8)
        .onAppear { draft = vm.stimulationProfile }
        .onChange(of: vm.stimulationProfile) { _, profile in draft = profile }
        .onChange(of: draft) { _, _ in saveMessage = nil }
    }

    private func amplitudeControl(_ title: String, value: Binding<Double>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n(title))
                Spacer()
                Text("\(Int(value.wrappedValue)) %")
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...100, step: 1)
                .accessibilityLabel(L10n(title))
                .accessibilityIdentifier(id)
        }
    }
}
