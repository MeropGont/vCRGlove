//
//  ResearchStudiesView.swift
//  vCRGlove
//
//  Created by Alexander Wiederhold on 01/06/2026.
//

import Foundation
import SwiftUI

// ---------------------------------------------------------------------
// MARK: Study Models
// ---------------------------------------------------------------------
// --> this is just to make cohort management easier -- TODO

struct StudyListDocument: Codable {
    var schemaVersion = 1
    var activeStudyId: UUID?
    var studies: [StudyDesign] = []
}

struct StudyDesign: Identifiable, Codable, Equatable {
    var id = UUID()
    var studyId: String
    var cohorts: [String] = []
    var ukeStudySupervisor: String?
    var statusLabels: [String] = []
    var pseudonymScheme: StudyIdentifierScheme?
    var createdAt = Date()
    var updatedAt = Date()

    init(
        id: UUID = UUID(),
        studyId: String,
        cohorts: [String] = [],
        ukeStudySupervisor: String? = nil,
        statusLabels: [String] = [],
        pseudonymScheme: StudyIdentifierScheme? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.studyId = studyId
        self.cohorts = cohorts
        self.ukeStudySupervisor = ukeStudySupervisor
        self.statusLabels = statusLabels
        self.pseudonymScheme = pseudonymScheme
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        studyId = try container.decode(String.self, forKey: .studyId)
        cohorts = try container.decodeIfPresent([String].self, forKey: .cohorts) ?? []
        ukeStudySupervisor = try container.decodeIfPresent(String.self, forKey: .ukeStudySupervisor)
        statusLabels = try container.decodeIfPresent([String].self, forKey: .statusLabels) ?? []
        pseudonymScheme = try container.decodeIfPresent(StudyIdentifierScheme.self, forKey: .pseudonymScheme)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

struct StudyIdentifierScheme: Codable, Equatable {
    var length: Int
    var startRule: StudyIdentifierStartRule?
    var prefix: String?
    var suffix: String?
    var countUp: StudyIdentifierCountUp?
}

struct StudyIdentifierStartRule: Codable, Equatable {
    var count: Int
    var kind: StudyIdentifierStartKind
}

enum StudyIdentifierStartKind: String, CaseIterable, Codable, Identifiable {
    case letters
    case numerals

    var id: String { rawValue }

    var label: String {
        switch self {
        case .letters: return "Letter(s)"
        case .numerals: return "Numerical(s)"
        }
    }
}

struct StudyIdentifierCountUp: Codable, Equatable {
    var startValue: Int
}

extension StudyIdentifierScheme {
    func exampleValue(allowsCountUp: Bool) -> String {
        generatedValue(allowsCountUp: allowsCountUp)
    }

    func generatedValue(allowsCountUp: Bool, countUpValue: Int? = nil) -> String {
        let core: String
        if allowsCountUp, let countUp {
            core = String(format: "%0\(length)d", countUpValue ?? countUp.startValue).suffix(length).description
        } else {
            core = randomCore()
        }

        return [prefix, core, suffix]
            .compactMap { $0?.nilIfBlank }
            .joined()
    }

    private func randomCore() -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let numerals = "0123456789"
        var value = ""

        if let startRule {
            let source = startRule.kind == .letters ? alphabet : numerals
            for _ in 0..<min(startRule.count, length) {
                value.append(source.randomElement() ?? "A")
            }
        }

        while value.count < length {
            let source = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            value.append(source.randomElement() ?? "0")
        }

        return String(value.prefix(length))
    }
}

// ---------------------------------------------------------------------
// MARK: Study Store
// ---------------------------------------------------------------------

@MainActor
final class StudyDesignStore: ObservableObject {
    @Published private(set) var studies: [StudyDesign] = []
    @Published private(set) var activeStudyId: UUID?
    @Published var errorMessage: String?

    init() {
        load()
    }

    var activeStudy: StudyDesign? {
        studies.first { $0.id == activeStudyId }
    }

    func load() {
        do {
            let url = try Self.studyListURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                studies = []
                activeStudyId = nil
                errorMessage = nil
                print("[Studies] No studylist JSON yet")
                return
            }

            let data = try Data(contentsOf: url)
            let document = try JSONDecoder.studyDecoder.decode(StudyListDocument.self, from: data)
            studies = document.studies.sorted { lhs, rhs in
                lhs.studyId.localizedStandardCompare(rhs.studyId) == .orderedAscending
            }
            activeStudyId = document.activeStudyId
            errorMessage = nil
            print("[Studies] Loaded \(studies.count) study design(s)")
        } catch {
            studies = []
            activeStudyId = nil
            errorMessage = "Could not load study list: \(error.localizedDescription)"
            print("[Studies] Load failed: \(error)")
        }
    }

    func save(_ study: StudyDesign) {
        var saved = study
        saved.updatedAt = Date()

        if let index = studies.firstIndex(where: { $0.id == saved.id }) {
            studies[index] = saved
        } else {
            studies.append(saved)
            if activeStudyId == nil {
                activeStudyId = saved.id
            }
        }

        studies.sort { lhs, rhs in
            lhs.studyId.localizedStandardCompare(rhs.studyId) == .orderedAscending
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        let deletedIds = offsets.map { studies[$0].id }
        studies.remove(atOffsets: offsets)
        if let activeStudyId, deletedIds.contains(activeStudyId) {
            self.activeStudyId = studies.first?.id
        }
        persist()
    }

    func delete(_ study: StudyDesign) {
        guard let index = studies.firstIndex(where: { $0.id == study.id }) else { return }
        delete(at: IndexSet(integer: index))
    }

    func setActive(_ study: StudyDesign) {
        activeStudyId = study.id
        persist()
    }

    private func persist() {
        do {
            let url = try Self.studyListURL()
            let document = StudyListDocument(activeStudyId: activeStudyId, studies: studies)
            let data = try JSONEncoder.studyEncoder.encode(document)
            try data.write(to: url, options: [.atomic])
            errorMessage = nil
            print("[Studies] Saved studylist JSON: \(url.path)")
        } catch {
            errorMessage = "Could not save study list: \(error.localizedDescription)"
            print("[Studies] Save failed: \(error)")
        }
    }

    private static func studyListURL() throws -> URL {
        let docs = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = docs.appendingPathComponent("Studies", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("studylist.json")
    }
}

private extension JSONDecoder {
    static var studyDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension JSONEncoder {
    static var studyEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

// ---------------------------------------------------------------------
// MARK: Studies List UI
// ---------------------------------------------------------------------

struct ResearchStudiesView: View {
    @StateObject private var store = StudyDesignStore()
    @State private var editingStudy: StudyDesign?
    @State private var creatingStudy = false

    var body: some View {
        List {
            if let errorMessage = store.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section {
                if store.studies.isEmpty {
                    ContentUnavailableView("No Studies", systemImage: "doc.text.magnifyingglass", description: Text("Add a study design to make it available here."))
                } else {
                    ForEach(store.studies) { study in
                        studyRow(study)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    store.delete(study)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    editingStudy = study
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                    }
                    .onDelete(perform: store.delete)
                }
            }
        }
        .navigationTitle("Studies")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingStudy = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Study")
            }
        }
        .sheet(isPresented: $creatingStudy) {
            StudyEditorSheet(study: nil) { study in
                store.save(study)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingStudy) { study in
            StudyEditorSheet(study: study) { saved in
                store.save(saved)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    private func studyRow(_ study: StudyDesign) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                store.setActive(study)
            } label: {
                Image(systemName: store.activeStudyId == study.id ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(store.activeStudyId == study.id ? .green : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.activeStudyId == study.id ? "Current Study" : "Set Current Study")

            VStack(alignment: .leading, spacing: 5) {
                Text(study.studyId)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                if !study.cohorts.isEmpty {
                    Text(study.cohorts.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if study.pseudonymScheme != nil {
                        Label("Pseudonym", systemImage: "person.text.rectangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button {
                editingStudy = study
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit Study")
        }
        .contentShape(Rectangle())
    }
}

// ---------------------------------------------------------------------
// MARK: Study Editor
// ---------------------------------------------------------------------

private struct StudyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let study: StudyDesign?
    let onSave: (StudyDesign) -> Void

    @State private var studyId = ""
    @State private var includeCohorts = false
    @State private var cohorts: [String] = [""]
    @State private var ukeStudySupervisor = ""
    @State private var includeStatusLabels = false
    @State private var statusLabels = Self.defaultStatusLabels
    @State private var includePseudonymScheme = false
    @State private var pseudonymScheme = StudyIdentifierSchemeDraft.pseudonymDefault

    private static let defaultStatusLabels = ["Erhebungsphase", "Beendet", "Ausgeschlossen", "Auswertung"]

    private var isSaveEnabled: Bool {
        !studyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Study") {
                    TextField("Study ID", text: $studyId)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)

                    optionalSelectionRow(isSelected: $includeCohorts) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Cohort")
                                Spacer()
                                Button {
                                    cohorts.append("")
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add Cohort")
                            }

                            ForEach(cohorts.indices, id: \.self) { index in
                                HStack {
                                    TextField("Cohort", text: cohortBinding(at: index))
                                        .submitLabel(.done)

                                    if cohorts.count > 1 {
                                        Button(role: .destructive) {
                                            cohorts.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Remove Cohort")
                                    }
                                }
                            }
                        }
                    }

                    TextField("UKE Study Supervisor Name", text: $ukeStudySupervisor)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    optionalSelectionRow(isSelected: statusLabelsSelectionBinding) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Status Labels")
                                Spacer()
                                Button {
                                    statusLabels.append("")
                                } label: {
                                    Image(systemName: "plus")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add Status Label")
                            }

                            ForEach(statusLabels.indices, id: \.self) { index in
                                HStack {
                                    TextField("Status Label", text: statusLabelBinding(at: index))
                                        .submitLabel(.done)

                                    if statusLabels.count > 1 {
                                        Button(role: .destructive) {
                                            statusLabels.remove(at: index)
                                        } label: {
                                            Image(systemName: "minus.circle")
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Remove Status Label")
                                    }
                                }
                            }
                        }
                    }
                }

                schemeSection(
                    title: "Pseudonym in Study Scheme",
                    isSelected: $includePseudonymScheme,
                    draft: $pseudonymScheme,
                    allowsCountUp: true,
                    previewTitle: "Example Pseudonym"
                )
            }
            .navigationTitle(study == nil ? "New Study" : "Edit Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(makeStudy())
                        dismiss()
                    }
                    .disabled(!isSaveEnabled)
                }
            }
            .onAppear(perform: loadStudy)
        }
    }

    @ViewBuilder
    private func schemeSection(
        title: String,
        isSelected: Binding<Bool>,
        draft: Binding<StudyIdentifierSchemeDraft>,
        allowsCountUp: Bool,
        previewTitle: String
    ) -> some View {
        Section {
            optionalSelectionRow(isSelected: isSelected) {
                Text(title)
            }

            if isSelected.wrappedValue {
                Stepper("Length: \(draft.wrappedValue.length)", value: draft.length, in: 4...16)

                Toggle("Start with", isOn: mutuallyExclusiveStartRuleBinding(for: draft, allowsCountUp: allowsCountUp))
                if draft.wrappedValue.includeStartRule {
                    Stepper("Characters: \(draft.wrappedValue.startCount)", value: draft.startCount, in: 1...3)
                    Picker("Type", selection: draft.startKind) {
                        ForEach(StudyIdentifierStartKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                }

                Toggle("Prefix", isOn: draft.includePrefix)
                if draft.wrappedValue.includePrefix {
                    TextField("Prefix", text: limitedText(draft.prefix, maxLength: 10))
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                }

                Toggle("Suffix", isOn: draft.includeSuffix)
                if draft.wrappedValue.includeSuffix {
                    TextField("Suffix", text: limitedText(draft.suffix, maxLength: 10))
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                }

                if allowsCountUp {
                    Toggle("Count Up", isOn: mutuallyExclusiveCountUpBinding(for: draft))
                    if draft.wrappedValue.includeCountUp {
                        Stepper("Start Value: \(draft.wrappedValue.countUpStart)", value: draft.countUpStart, in: 0...999_999)
                    }
                }

                LabeledContent(previewTitle) {
                    Text(draft.wrappedValue.preview(allowsCountUp: allowsCountUp))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private func optionalSelectionRow<Content: View>(
        isSelected: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                isSelected.wrappedValue.toggle()
            } label: {
                Image(systemName: isSelected.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(isSelected.wrappedValue ? .green : .secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected.wrappedValue ? "Included" : "Not included")

            content()
        }
    }

    private var statusLabelsSelectionBinding: Binding<Bool> {
        Binding(
            get: { includeStatusLabels },
            set: { isSelected in
                includeStatusLabels = isSelected
                if isSelected && cleanedStatusLabels().isEmpty {
                    statusLabels = Self.defaultStatusLabels
                }
            }
        )
    }

    private func cohortBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { cohorts.indices.contains(index) ? cohorts[index] : "" },
            set: { newValue in
                guard cohorts.indices.contains(index) else { return }
                cohorts[index] = newValue
                includeCohorts = true
            }
        )
    }

    private func statusLabelBinding(at index: Int) -> Binding<String> {
        Binding(
            get: { statusLabels.indices.contains(index) ? statusLabels[index] : "" },
            set: { newValue in
                guard statusLabels.indices.contains(index) else { return }
                statusLabels[index] = newValue
                includeStatusLabels = true
            }
        )
    }

    private func limitedText(_ binding: Binding<String>, maxLength: Int) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = String($0.prefix(maxLength)) }
        )
    }

    private func mutuallyExclusiveStartRuleBinding(
        for draft: Binding<StudyIdentifierSchemeDraft>,
        allowsCountUp: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.includeStartRule },
            set: { isOn in
                draft.wrappedValue.includeStartRule = isOn
                if allowsCountUp && isOn {
                    draft.wrappedValue.includeCountUp = false
                }
            }
        )
    }

    private func mutuallyExclusiveCountUpBinding(for draft: Binding<StudyIdentifierSchemeDraft>) -> Binding<Bool> {
        Binding(
            get: { draft.wrappedValue.includeCountUp },
            set: { isOn in
                draft.wrappedValue.includeCountUp = isOn
                if isOn {
                    draft.wrappedValue.includeStartRule = false
                }
            }
        )
    }

    private func loadStudy() {
        guard let study else { return }
        studyId = study.studyId
        cohorts = study.cohorts.isEmpty ? [""] : study.cohorts
        includeCohorts = !study.cohorts.isEmpty
        ukeStudySupervisor = study.ukeStudySupervisor ?? ""
        statusLabels = study.statusLabels.isEmpty ? Self.defaultStatusLabels : study.statusLabels
        includeStatusLabels = !study.statusLabels.isEmpty
        includePseudonymScheme = study.pseudonymScheme != nil
        pseudonymScheme = study.pseudonymScheme.map(StudyIdentifierSchemeDraft.init) ?? .pseudonymDefault
    }

    private func makeStudy() -> StudyDesign {
        let cleanedCohorts = cohorts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let cleanedStatusLabels = cleanedStatusLabels()

        return StudyDesign(
            id: study?.id ?? UUID(),
            studyId: studyId.trimmingCharacters(in: .whitespacesAndNewlines),
            cohorts: includeCohorts ? cleanedCohorts : [],
            ukeStudySupervisor: ukeStudySupervisor.nilIfBlank,
            statusLabels: includeStatusLabels ? cleanedStatusLabels : [],
            pseudonymScheme: includePseudonymScheme ? pseudonymScheme.makeScheme(allowsCountUp: true) : nil,
            createdAt: study?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    private func cleanedStatusLabels() -> [String] {
        statusLabels
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct StudyIdentifierSchemeDraft: Equatable {
    var length: Int
    var includeStartRule: Bool
    var startCount: Int
    var startKind: StudyIdentifierStartKind
    var includePrefix: Bool
    var prefix: String
    var includeSuffix: Bool
    var suffix: String
    var includeCountUp: Bool
    var countUpStart: Int

    static let pseudonymDefault = StudyIdentifierSchemeDraft(
        length: 6,
        includeStartRule: false,
        startCount: 1,
        startKind: .letters,
        includePrefix: false,
        prefix: "",
        includeSuffix: false,
        suffix: "",
        includeCountUp: true,
        countUpStart: 101
    )

    init(
        length: Int,
        includeStartRule: Bool,
        startCount: Int,
        startKind: StudyIdentifierStartKind,
        includePrefix: Bool,
        prefix: String,
        includeSuffix: Bool,
        suffix: String,
        includeCountUp: Bool,
        countUpStart: Int
    ) {
        self.length = length
        self.includeStartRule = includeStartRule
        self.startCount = startCount
        self.startKind = startKind
        self.includePrefix = includePrefix
        self.prefix = prefix
        self.includeSuffix = includeSuffix
        self.suffix = suffix
        self.includeCountUp = includeCountUp
        self.countUpStart = countUpStart
    }

    init(scheme: StudyIdentifierScheme) {
        length = scheme.length
        includeStartRule = scheme.startRule != nil
        startCount = scheme.startRule?.count ?? 1
        startKind = scheme.startRule?.kind ?? .letters
        includePrefix = scheme.prefix?.nilIfBlank != nil
        prefix = scheme.prefix ?? ""
        includeSuffix = scheme.suffix?.nilIfBlank != nil
        suffix = scheme.suffix ?? ""
        includeCountUp = scheme.countUp != nil
        countUpStart = scheme.countUp?.startValue ?? 101
    }

    func makeScheme(allowsCountUp: Bool) -> StudyIdentifierScheme {
        StudyIdentifierScheme(
            length: length,
            startRule: includeStartRule ? StudyIdentifierStartRule(count: startCount, kind: startKind) : nil,
            prefix: includePrefix ? prefix.nilIfBlank : nil,
            suffix: includeSuffix ? suffix.nilIfBlank : nil,
            countUp: allowsCountUp && includeCountUp ? StudyIdentifierCountUp(startValue: countUpStart) : nil
        )
    }

    func preview(allowsCountUp: Bool) -> String {
        let core: String
        if allowsCountUp && includeCountUp {
            core = String(format: "%0\(length)d", countUpStart).suffix(length).description
        } else {
            core = randomCore()
        }

        return [includePrefix ? prefix : nil, core, includeSuffix ? suffix : nil]
            .compactMap { $0?.nilIfBlank }
            .joined()
    }

    private func randomCore() -> String {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let numerals = "0123456789"
        var value = ""

        if includeStartRule {
            let source = startKind == .letters ? alphabet : numerals
            for offset in 0..<min(startCount, length) {
                let index = source.index(source.startIndex, offsetBy: offset % source.count)
                value.append(source[index])
            }
        }

        while value.count < length {
            let source = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            let offset = (value.count * 7 + length * 3) % source.count
            let index = source.index(source.startIndex, offsetBy: offset)
            value.append(source[index])
        }

        return String(value.prefix(length))
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
