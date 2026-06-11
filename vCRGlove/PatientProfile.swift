//
//  PatientProfile.swift
//  vCRGlove
//
//  Created by Alexander Wiederhold on 05/06/2026.
//

import SwiftUI
import UIKit
import Foundation
import ParkinsonMetadata

// ---------------------------------------------------------------------
// MARK: Profile UI
// ---------------------------------------------------------------------
struct ProfileSettingsView: View {
    @Binding var patientID: String
    let requiresActivePatient: Bool

    @Environment(\.openURL) private var openURL
    @StateObject private var vm = PatientProfileViewModel()
    @StateObject private var studyStore = StudyDesignStore()
    @State private var isEditing = false
    @State private var showingError = false
    @State private var showingPatientSelection = false
    @State private var showingHoehnYahrInfo = false
    @State private var showingPDSubtypeInfo = false
    @State private var formScrollResetID = UUID()
    @State private var autoAppliedStudySupervisor: String?

    init(patientID: Binding<String>, requiresActivePatient: Bool = false) {
        _patientID = patientID
        self.requiresActivePatient = requiresActivePatient
    }

    var body: some View {
        Form {
            if requiresActivePatient && vm.activePatient == nil {
                Section {
                    Text("A patient profile is required before using vCRGlove.")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let patient = vm.activePatient, !isEditing {
                profileSummary(for: patient)

                Section {
                    Button {
                        vm.load(patient: patient)
                        applySelectedStudyScheme(resetPseudonymCount: true)
                        isEditing = true
                    } label: {
                        Label("Edit Patient", systemImage: "pencil")
                    }

                    Button {
                        vm.reload()
                        showingPatientSelection = true
                    } label: {
                        Label("New Patient", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            } else {
                patientForm
            }
        }
        .id(formScrollResetID)
        .navigationTitle("Profile")
        .overlay {
            if vm.isSaving {
                ProgressView("Saving patient...")
                    .padding()
                    .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear {
            studyStore.load()
            vm.reload()
            syncPatientID()
            clearStudyFieldsIfNeeded()
            applySelectedStudyScheme(resetPseudonymCount: true)
        }
        .onChange(of: vm.activePatient?.id?.numericId()) { _, _ in
            syncPatientID()
            isEditing = false
        }
        .onChange(of: isEditing) { _, isEditing in
            if isEditing {
                formScrollResetID = UUID()
            }
        }
        .alert("Could Not Save Patient", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(vm.errorMessage ?? "Unknown error")
        }
        .sheet(isPresented: $showingPatientSelection) {
            PatientSelectionSheet(
                vm: vm,
                isPresented: $showingPatientSelection,
                isEditing: $isEditing,
                showingError: $showingError,
                syncPatientID: syncPatientID
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var patientForm: some View {
        Group {
            Section("Identity") {
                TextField("Alias", text: $vm.alias)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)

                if hasAvailableStudies {
                    optionalSelectionRow(isSelected: $vm.includeStudyId) {
                        Picker("Study ID", selection: $vm.studyId) {
                            Text("Select Study").tag("")
                            ForEach(availableStudyIds, id: \.self) { studyId in
                                Text(studyId).tag(studyId)
                            }
                        }
                    }
                    .onChange(of: vm.studyId) { _, _ in
                        vm.includeStudyId = !vm.studyId.isEmpty
                        applySelectedStudyScheme(resetPseudonymCount: true)
                    }
                    .onChange(of: vm.includeStudyId) { _, isIncluded in
                        if isIncluded {
                            selectDefaultStudyIfNeeded()
                        } else {
                            vm.includeCohort = false
                            vm.includeStudyStatus = false
                            vm.includeUKEStudySupervisor = false
                        }
                        applySelectedStudyScheme(resetPseudonymCount: true)
                    }

                    optionalSelectionRow(isSelected: $vm.includeCohort) {
                        if selectedStudyCohorts.isEmpty {
                            TextField("Cohort", text: $vm.cohort)
                                .submitLabel(.done)
                        } else {
                            Picker("Cohort", selection: $vm.cohort) {
                                Text("Select Cohort").tag("")
                                ForEach(selectedStudyCohorts, id: \.self) { cohort in
                                    Text(cohort).tag(cohort)
                                }
                            }
                        }
                    }
                    .onChange(of: vm.cohort) { _, _ in
                        vm.includeCohort = !vm.cohort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .onChange(of: vm.includeCohort) { _, isIncluded in
                        if isIncluded {
                            selectDefaultCohortIfNeeded()
                        }
                    }

                    optionalSelectionRow(isSelected: $vm.includeStudyStatus) {
                        if selectedStudyStatusLabels.isEmpty {
                            TextField("Study Status", text: $vm.studyStatus)
                                .submitLabel(.done)
                        } else {
                            Picker("Study Status", selection: $vm.studyStatus) {
                                Text("Select Status").tag("")
                                ForEach(selectedStudyStatusLabels, id: \.self) { status in
                                    Text(status).tag(status)
                                }
                            }
                        }
                    }
                    .onChange(of: vm.studyStatus) { _, _ in
                        vm.includeStudyStatus = !vm.studyStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .onChange(of: vm.includeStudyStatus) { _, isIncluded in
                        if isIncluded {
                            selectDefaultStudyStatusIfNeeded()
                        }
                    }

                }

                if selectedStudy?.pseudonymScheme == nil {
                    TextField("Pseudonym in Study", text: $vm.additionalLabPseudonym)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                } else {
                    generatedPseudonymRow
                }

                if selectedStudy != nil {
                    if let selectedStudySupervisor {
                        profileRow("UKE Study Supervisor", selectedStudySupervisor)
                    } else {
                        TextField("UKE Study Supervisor", text: $vm.ukeStudySupervisor)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .onChange(of: vm.ukeStudySupervisor) { _, _ in
                                vm.includeUKEStudySupervisor = !vm.ukeStudySupervisor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            }
                    }
                }

                TextField("Soarian Case ID", text: $vm.scId)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)

                profileRow("Device ID", vm.deviceId)
                TextField("Device Name", text: $vm.deviceName)
                    .submitLabel(.done)

                Toggle("Consent Given", isOn: $vm.consent)
            }

            Section("Demographics") {
                optionalSelectionRow(isSelected: $vm.includeDateBirth) {
                    DatePicker("Date of Birth", selection: dateSelectionBinding($vm.dateBirth, isIncluded: $vm.includeDateBirth), displayedComponents: .date)
                }

                optionalSelectionRow(isSelected: $vm.includeSex) {
                    Picker("Sex", selection: $vm.sex) {
                        ForEach(vm.sexOptions, id: \.self) { sex in
                            Text(sex.label).tag(sex)
                        }
                    }
                }
                .onChange(of: vm.sex) { _, _ in
                    vm.includeSex = true
                }

                optionalSelectionRow(isSelected: $vm.includeHeight) {
                    Stepper("Height: \(vm.height) cm", value: $vm.height, in: 80...250)
                }
                .onChange(of: vm.height) { _, _ in
                    vm.includeHeight = true
                }

                optionalSelectionRow(isSelected: $vm.includeWeight) {
                    Stepper("Weight: \(vm.weight) kg", value: $vm.weight, in: 30...300)
                }
                .onChange(of: vm.weight) { _, _ in
                    vm.includeWeight = true
                }
            }

            Section("Symptoms") {
                optionalSelectionRow(isSelected: $vm.includeDateFirstSymptoms) {
                    DatePicker("First Symptoms", selection: dateSelectionBinding($vm.dateFirstSymptoms, isIncluded: $vm.includeDateFirstSymptoms), displayedComponents: .date)
                }

                optionalSelectionRow(isSelected: $vm.includeDateDiagnosis) {
                    DatePicker("Diagnosis Date", selection: dateSelectionBinding($vm.dateDiagnosis, isIncluded: $vm.includeDateDiagnosis), displayedComponents: .date)
                }

                optionalSelectionRow(isSelected: $vm.includePreferredHand) {
                    Picker("Preferred Hand", selection: $vm.preferredHand) {
                        ForEach(vm.sideOptions, id: \.self) { side in
                            Text(side.label).tag(side)
                        }
                    }
                }
                .onChange(of: vm.preferredHand) { _, _ in
                    vm.includePreferredHand = true
                }

                optionalSelectionRow(isSelected: $vm.includeMostAffectedSide) {
                    Picker("Most Affected Side", selection: $vm.mostAffectedSide) {
                        ForEach(vm.sideOptions, id: \.self) { side in
                            Text(side.label).tag(side)
                        }
                    }
                }
                .onChange(of: vm.mostAffectedSide) { _, _ in
                    vm.includeMostAffectedSide = true
                }

                TextField("Dominant Symptom", text: $vm.dominantSymptom)
                    .submitLabel(.done)

                optionalSelectionRow(isSelected: $vm.includePDSubtype) {
                    HStack {
                        Picker("PD Subtype", selection: $vm.pdSubtype) {
                            ForEach(vm.pdSubtypeOptions, id: \.self) { subtype in
                                Text(subtype).tag(subtype)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            showingPDSubtypeInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("PD subtype information")
                        .popover(isPresented: $showingPDSubtypeInfo, arrowEdge: .trailing) {
                            PDSubtypeInfoView(isPresented: $showingPDSubtypeInfo)
                                .presentationDetents([.medium, .large])
                                .presentationDragIndicator(.visible)
                                .presentationCompactAdaptation(.sheet)
                        }
                    }
                }
                .onChange(of: vm.pdSubtype) { _, _ in
                    vm.includePDSubtype = true
                }

                optionalSelectionRow(isSelected: $vm.includeHoehnYahr) {
                    HStack {
                        Picker("Hoehn & Yahr", selection: $vm.hoehnYahr) {
                            ForEach(vm.hoehnYahrOptions, id: \.self) { stage in
                                Text(vm.hoehnYahrLabel(stage)).tag(stage)
                            }
                        }
                        .pickerStyle(.menu)

                        Button {
                            showingHoehnYahrInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .imageScale(.large)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Hoehn and Yahr scale information")
                        .popover(isPresented: $showingHoehnYahrInfo, arrowEdge: .trailing) {
                            HoehnYahrInfoView(isPresented: $showingHoehnYahrInfo)
                                .presentationDetents([.medium, .large])
                                .presentationDragIndicator(.visible)
                                .presentationCompactAdaptation(.sheet)
                        }
                    }
                }
                .onChange(of: vm.hoehnYahr) { _, _ in
                    vm.includeHoehnYahr = true
                }

                optionalSelectionRow(isSelected: $vm.includePDFamilyHistory) {
                    Toggle("PD Family History", isOn: $vm.pdFamilyHistory)
                }
                .onChange(of: vm.pdFamilyHistory) { _, _ in
                    vm.includePDFamilyHistory = true
                }

                TextField("Comorbidities", text: $vm.comorbidities, axis: .vertical)
                    .lineLimit(2...4)

                optionalSelectionRow(isSelected: $vm.includeLastMocaScore) {
                    Stepper("Last MoCA Score: \(vm.lastMocaScore)", value: $vm.lastMocaScore, in: 0...30)
                }
                .onChange(of: vm.lastMocaScore) { _, _ in
                    vm.includeLastMocaScore = true
                }

                if vm.includeLastMocaScore {
                    optionalSelectionRow(isSelected: $vm.includeLastMocaDate) {
                        DatePicker("Last MoCA Date", selection: dateSelectionBinding($vm.lastMocaDate, isIncluded: $vm.includeLastMocaDate), displayedComponents: .date)
                    }
                }
            }

            Section("Treatment") {
                optionalSelectionRow(isSelected: $vm.includeDBS) {
                    Toggle("Deep Brain Stimulation", isOn: $vm.hasDBS)
                }
                .onChange(of: vm.hasDBS) { _, _ in
                    vm.includeDBS = true
                }
                if vm.includeDBS && vm.hasDBS {
                    optionalSelectionRow(isSelected: $vm.includeDBSDate) {
                        DatePicker("DBS Date", selection: dateSelectionBinding($vm.dbsDate, isIncluded: $vm.includeDBSDate), displayedComponents: .date)
                    }
                }

                optionalSelectionRow(isSelected: $vm.includeComplexTreatment) {
                    Toggle("Parkinson Komplexbehandlung (PKB)", isOn: $vm.complexTreatment)
                }
                .onChange(of: vm.complexTreatment) { _, _ in
                    vm.includeComplexTreatment = true
                }
                optionalSelectionRow(isSelected: $vm.includeTreatmentSetting) {
                    Picker("Treatment Setting", selection: $vm.treatmentSetting) {
                        ForEach(vm.treatmentSettingOptions, id: \.self) { setting in
                            Text(setting).tag(setting)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .onChange(of: vm.treatmentSetting) { _, _ in
                    vm.includeTreatmentSetting = true
                }

                optionalSelectionRow(isSelected: $vm.includeUseWearable) {
                    Toggle("Smart Watch", isOn: $vm.useWearable)
                }
                .onChange(of: vm.useWearable) { _, _ in
                    vm.includeUseWearable = true
                }
                if vm.includeUseWearable && vm.useWearable {
                    optionalSelectionRow(isSelected: $vm.includeWatchSide) {
                        Picker("Watch Side", selection: $vm.watchSide) {
                            ForEach(vm.sideOptions, id: \.self) { side in
                                Text(side.label).tag(side)
                            }
                        }
                    }
                    .onChange(of: vm.watchSide) { _, _ in
                        vm.includeWatchSide = true
                    }
                    TextField("Watch ID", text: $vm.watchId)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                    TextField("Watch Name", text: $vm.watchName)
                        .submitLabel(.done)
                }
                optionalSelectionRow(isSelected: $vm.includeUseCap) {
                    Toggle("Smart Cap (CAPture)", isOn: $vm.useCap)
                }
                .onChange(of: vm.useCap) { _, _ in
                    vm.includeUseCap = true
                }
                if vm.includeUseCap && vm.useCap {
                    TextField("Cap ID", text: $vm.capId)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                    TextField("Cap Name", text: $vm.capName)
                        .submitLabel(.done)
                }
                optionalSelectionRow(isSelected: $vm.includeUseGloves) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("vCR Gloves")
                            .font(.body)

                        Picker("vCR Gloves", selection: $vm.useGloves) {
                            ForEach(vm.gloveSideOptions, id: \.self) { side in
                                Text(side).tag(side)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .onChange(of: vm.useGloves) { _, _ in
                    vm.includeUseGloves = true
                }
                if vm.includeUseGloves {
                    TextField("Gloves ID", text: $vm.glovesId)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .submitLabel(.done)
                    TextField("Gloves Name", text: $vm.glovesName)
                        .submitLabel(.done)
                }

                TextField("UKE Neurologist Name", text: $vm.ukeNeurologist)
                    .submitLabel(.done)
            }

            Section("Lifestyle") {
                optionalSelectionRow(isSelected: $vm.includeIsSmoker) {
                    Toggle("Smoker", isOn: $vm.isSmoker)
                }
                .onChange(of: vm.isSmoker) { _, _ in
                    vm.includeIsSmoker = true
                }
                if vm.includeIsSmoker && vm.isSmoker {
                    Toggle("Quit Smoking", isOn: $vm.hasQuitDate)
                    if vm.hasQuitDate {
                        optionalSelectionRow(isSelected: $vm.includeQuitDate) {
                            DatePicker("Quit Date", selection: dateSelectionBinding($vm.quitDate, isIncluded: $vm.includeQuitDate), displayedComponents: .date)
                        }
                    }
                    optionalSelectionRow(isSelected: $vm.includeSmokedPacksPerYear) {
                        Stepper("Packs / Year: \(vm.smokedPacksPerYear)", value: $vm.smokedPacksPerYear, in: 0...100)
                    }
                    .onChange(of: vm.smokedPacksPerYear) { _, _ in
                        vm.includeSmokedPacksPerYear = true
                    }
                }

                optionalSelectionRow(isSelected: $vm.includeAlcohol) {
                    Toggle("Drinks Alcohol regularly", isOn: $vm.hasAlcohol)
                }
                .onChange(of: vm.hasAlcohol) { _, _ in
                    vm.includeAlcohol = true
                }
                if vm.includeAlcohol && vm.hasAlcohol {
                    optionalSelectionRow(isSelected: $vm.includeAlcoholPerWeek) {
                        Stepper("Drinks / Week: \(vm.alcoholPerWeek)", value: $vm.alcoholPerWeek, in: 0...50)
                    }
                    .onChange(of: vm.alcoholPerWeek) { _, _ in
                        vm.includeAlcoholPerWeek = true
                    }
                }

                optionalSelectionRow(isSelected: $vm.includeDrivesCar) {
                    Picker("Drives Car", selection: $vm.drivesCar) {
                        ForEach(vm.drivesCarOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: vm.drivesCar) { _, _ in
                    vm.includeDrivesCar = true
                }

                if vm.includeDrivesCar && vm.drivesCar == "Not anymore" {
                    optionalSelectionRow(isSelected: $vm.includeQuitDrivingDate) {
                        DatePicker("Quit Driving Date", selection: dateSelectionBinding($vm.quitDrivingDate, isIncluded: $vm.includeQuitDrivingDate), displayedComponents: .date)
                    }
                }
            }

            Section("Social & Work") {
                TextField("Address", text: $vm.address, axis: .vertical)
                    .lineLimit(2...4)

                TextField("Email Address", text: $vm.emailAddress)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .submitLabel(.done)
                if !vm.isEmailAddressValid {
                    Text("Please enter a valid email address.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("Phone Number", text: $vm.phoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .submitLabel(.done)

                TextField("Caregiver Name", text: $vm.caregiver)
                    .submitLabel(.done)

                TextField("Caregiver Phone Number", text: $vm.caregiverPhoneNumber)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .submitLabel(.done)

                TextField("Home Neurologist", text: $vm.homeNeurologist)
                    .submitLabel(.done)

                TextField("Languages", text: $vm.languages)
                    .submitLabel(.done)

                TextField("Job", text: $vm.job)
                    .submitLabel(.done)
                optionalSelectionRow(isSelected: $vm.includeLiving) {
                    Picker("Living Situation", selection: $vm.living) {
                        ForEach(vm.livingOptions, id: \.self) { living in
                            Text(living).tag(living)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: vm.living) { _, _ in
                    vm.includeLiving = true
                }

                optionalSelectionRow(isSelected: $vm.includeSocial) {
                    Picker("Social Status", selection: $vm.social) {
                        ForEach(vm.socialOptions, id: \.self) { social in
                            Text(social).tag(social)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .onChange(of: vm.social) { _, _ in
                    vm.includeSocial = true
                }

                optionalSelectionRow(isSelected: $vm.includeChildren) {
                    Stepper("Children: \(vm.children)", value: $vm.children, in: 0...20)
                }
                .onChange(of: vm.children) { _, _ in
                    vm.includeChildren = true
                }
            }

            Section("Notes") {
                TextField("Bemerkungen", text: $vm.notes, axis: .vertical)
                    .lineLimit(4...8)
            }

            Section {
                if let saveDisabledReason = vm.saveDisabledReason, !vm.isSaving {
                    Text(saveDisabledReason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task {
                        normalizeStudyFieldsForSave()
                        await vm.save(isEditing: vm.patientId != nil)
                        showingError = vm.errorMessage != nil
                        syncPatientID()
                        if vm.errorMessage == nil {
                            isEditing = false
                        }
                    }
                } label: {
                    Label(vm.patientId == nil ? "Save Patient" : "Update Patient", systemImage: "checkmark.circle")
                }
                .disabled(!vm.isFormValid || vm.isSaving)

                if vm.activePatient != nil && !requiresActivePatient {
                    Button("Cancel", role: .cancel) {
                        isEditing = false
                        vm.clearForm()
                    }
                }
            }
        }
    }

    private var hasAvailableStudies: Bool {
        !studyStore.studies.isEmpty
    }

    private var availableStudyIds: [String] {
        var ids = studyStore.studies.map(\.studyId)
        if !vm.studyId.isEmpty, !ids.contains(vm.studyId) {
            ids.append(vm.studyId)
        }
        return ids.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var selectedStudy: StudyDesign? {
        guard vm.includeStudyId else { return nil }
        return studyStore.studies.first { $0.studyId == vm.studyId }
    }

    private var selectedStudyCohorts: [String] {
        selectedStudy?.cohorts ?? []
    }

    private var selectedStudyStatusLabels: [String] {
        selectedStudy?.statusLabels ?? []
    }

    private var selectedStudySupervisor: String? {
        selectedStudy?.ukeStudySupervisor?.nilIfBlank
    }

    private func selectDefaultStudyIfNeeded() {
        guard vm.studyId.isEmpty else { return }
        vm.studyId = studyStore.activeStudy?.studyId ?? availableStudyIds.first ?? ""
    }

    private func clearStudyFieldsIfNeeded() {
        guard !hasAvailableStudies else { return }
        vm.studyId = ""
        vm.includeStudyId = false
        vm.cohort = ""
        vm.includeCohort = false
        vm.studyStatus = ""
        vm.includeStudyStatus = false
        vm.ukeStudySupervisor = ""
        vm.includeUKEStudySupervisor = false
    }

    private func normalizeStudyFieldsForSave() {
        clearStudyFieldsIfNeeded()
        guard selectedStudy == nil else { return }
        vm.ukeStudySupervisor = ""
        vm.includeUKEStudySupervisor = false
    }

    private func selectDefaultCohortIfNeeded() {
        guard vm.cohort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        vm.cohort = selectedStudyCohorts.first ?? ""
    }

    private func selectDefaultStudyStatusIfNeeded() {
        guard vm.studyStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        vm.studyStatus = selectedStudyStatusLabels.first ?? ""
    }

    private func applySelectedStudyScheme(resetPseudonymCount: Bool) {
        guard let selectedStudy else { return }

        if let scheme = selectedStudy.pseudonymScheme {
            if resetPseudonymCount, let countUp = scheme.countUp {
                vm.pseudonymCountUpValue = countUp.startValue + max(localPatientNumericIdForPseudonym() - 1, 0)
            }
            vm.additionalLabPseudonym = scheme.generatedValue(
                allowsCountUp: true,
                countUpValue: scheme.countUp == nil ? nil : vm.pseudonymCountUpValue
            )
        }

        if !selectedStudyCohorts.isEmpty, !selectedStudyCohorts.contains(vm.cohort) {
            vm.cohort = selectedStudyCohorts.first ?? ""
        }

        if !selectedStudyStatusLabels.isEmpty, !selectedStudyStatusLabels.contains(vm.studyStatus) {
            vm.studyStatus = selectedStudyStatusLabels.first ?? ""
        }

        if let selectedStudySupervisor {
            vm.ukeStudySupervisor = selectedStudySupervisor
            vm.includeUKEStudySupervisor = true
            autoAppliedStudySupervisor = selectedStudySupervisor
        } else {
            if vm.ukeStudySupervisor == autoAppliedStudySupervisor {
                vm.ukeStudySupervisor = ""
            }
            autoAppliedStudySupervisor = nil
            vm.includeUKEStudySupervisor = !vm.ukeStudySupervisor.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func localPatientNumericIdForPseudonym() -> Int {
        if let numericId = vm.patientId?.numericId(), numericId > 0 {
            return Int(numericId)
        }

        let maxExistingId = vm.availablePatients
            .compactMap { $0.id?.numericId() }
            .max() ?? 0
        return Int(maxExistingId + 1)
    }

    // ---------------------------------------------------------------------
    // MARK: Profile UI summary
    // ---------------------------------------------------------------------
    private func profileSummary(for patient: ParkinsonMetadata.Patient) -> some View {
        Group {
            Section {
                profileRow("Alias", patient.alias)
                profileCopyableOptionalRow("UUID", patient.id?.pseudonymString())
                profileOptionalRow("Study ID", patient.studyId)
                profileOptionalRow("Cohort", patient.cohort)
                profileOptionalRow("Study Status", patient.studyStatus)
                profileOptionalRow("UKE Study Supervisor", patient.ukeStudySupervisor)
                profileOptionalRow("Pseudonym in Study", patient.additionalLabPseudonym)
                profileOptionalRow("Soarian Case ID", patient.scId.map(String.init))
                profileRow("Consent", patient.consent ? "Given" : "Missing")
            }

            if patient.hasDemographicsSummary {
                Section("Demographics") {
                    profileOptionalRow("Date of Birth", patient.dateBirth?.toString())
                    profileOptionalRow("Sex", patient.sex?.label)
                    profileOptionalRow("Height", patient.height.map { "\($0.value()) cm" })
                    profileOptionalRow("Weight", patient.weight.map { "\($0.value()) kg" })
                }
            }

            if patient.hasSymptomsSummary {
                Section("Symptoms") {
                    profileOptionalRow("First Symptoms", patient.dateFirstSymptoms?.toString())
                    profileOptionalRow("Diagnosis Date", patient.dateDiagnosis?.toString())
                    profileOptionalRow("Most Affected Side", patient.mostAffectedSide?.label)
                    profileOptionalRow("Preferred Hand", patient.preferredHand?.label)
                    profileOptionalRow("Dominant Symptom", patient.dominantSymptom)
                    profileOptionalRow("PD Subtype", patient.pdSubtype)
                    profileOptionalRow("Hoehn & Yahr", patient.hoehnYahr.map(hoehnYahrDisplayValue))
                    profileOptionalRow("PD Family History", patient.pdFamilyHistory.map { $0 ? "Yes" : "No" })
                    profileOptionalRow("Last MoCA Score", patient.lastMocaScore.map(String.init))
                    profileOptionalRow("Last MoCA Date", patient.lastMocaDate?.toString())
                    profileCopyableOptionalRow("Comorbidities", patient.comorbidity)
                }
            }

            if patient.hasTreatmentSummary {
                Section("Treatment") {
                    profileOptionalRow("Deep Brain Stimulation", patient.dbsLabel.nilIfPlaceholder)
                    profileOptionalRow("Parkinson Komplexbehandlung (PKB)", patient.complexTreatment.map { $0 ? "Yes" : "No" })
                    profileOptionalRow("Ambulatory", patient.ambulatory.map { $0 ? "Yes" : "No" })
                    profileOptionalRow("Stationary", patient.stationary.map { $0 ? "Yes" : "No" })
                    profileOptionalRow("UKE Neurologist Name", patient.ukeNeurologist)
                    profileOptionalRow("Smart Watch", patient.watchLabel.nilIfPlaceholder)
                    profileOptionalRow("Smart Cap (CAPture)", patient.useCap.map { $0 ? "Yes" : "No" })
                    profileOptionalRow("vCR Gloves", patient.useGloves)
                    profileCopyableOptionalRow("Device ID", patient.deviceId)
                    profileOptionalRow("Watch", patient.watchDeviceLabel.nilIfPlaceholder)
                    profileOptionalRow("Cap Device", patient.capDeviceLabel.nilIfPlaceholder)
                    profileOptionalRow("Gloves", patient.glovesDeviceLabel.nilIfPlaceholder)
                }
            }

            if patient.hasLifestyleSummary {
                Section("Lifestyle") {
                    profileOptionalRow("Smoker", patient.isSmoker.map { $0 ? "Yes" : "No" })
                    profileOptionalRow("Drinks / Week", patient.alcoholConsumptionPerWeek.map(String.init))
                    profileOptionalRow("Drives Car", patient.drivesCar)
                    profileOptionalRow("Quit Driving Date", patient.quitDrivingDate?.toString())
                }
            }

            if patient.hasSocialSummary {
                Section("Social & Work") {
                    profileActionOptionalRow("Address", patient.address, systemImage: "map") { value in
                        openAddress(value)
                    }
                    profileActionOptionalRow("Email Address", patient.emailAddress, systemImage: "envelope") { value in
                        openEmail(value)
                    }
                    profileActionOptionalRow("Phone Number", patient.phoneNumber, systemImage: "phone") { value in
                        callPhoneNumber(value)
                    }
                    profileOptionalRow("Caregiver Name", patient.caregiver)
                    profileActionOptionalRow("Caregiver Phone Number", patient.caregiverPhoneNumber, systemImage: "phone") { value in
                        callPhoneNumber(value)
                    }
                    profileOptionalRow("Home Neurologist", patient.homeNeurologist)
                    profileOptionalRow("Languages", patient.languages)
                    profileOptionalRow("Job", patient.job)
                    profileOptionalRow("Living Situation", patient.living)
                    profileOptionalRow("Social Status", patient.social)
                    profileOptionalRow("Children", patient.children.map(String.init))
                }
            }

            if let notes = patient.notes, !notes.isEmpty {
                Section("Notes") {
                    profileCopyableRow("Notes", notes)
                }
            }
        }
    }

    @ViewBuilder
    private func profileOptionalRow(_ title: String, _ value: String?) -> some View {
        if let value = normalizedProfileValue(value) {
            profileRow(title, value)
        }
    }

    @ViewBuilder
    private func profileCopyableOptionalRow(_ title: String, _ value: String?) -> some View {
        if let value = normalizedProfileValue(value) {
            profileCopyableRow(title, value)
        }
    }

    @ViewBuilder
    private func profileActionOptionalRow(
        _ title: String,
        _ value: String?,
        systemImage: String,
        action: @escaping (String) -> Void
    ) -> some View {
        if let value = normalizedProfileValue(value) {
            LabeledContent {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        action(value)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(value)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                            Image(systemName: systemImage)
                                .imageScale(.small)
                        }
                    }
                    .buttonStyle(.plain)

                    copyButton(value)
                }
            } label: {
                Text(title)
            }
        }
    }

    private var generatedPseudonymRow: some View {
        LabeledContent {
            HStack(alignment: .center, spacing: 12) {
                Text(vm.additionalLabPseudonym)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)

                if selectedStudy?.pseudonymScheme?.countUp != nil {
                    Stepper("Pseudonym Number", value: $vm.pseudonymCountUpValue, in: 0...999_999)
                        .labelsHidden()
                        .onChange(of: vm.pseudonymCountUpValue) { _, _ in
                            applySelectedStudyScheme(resetPseudonymCount: false)
                        }
                }
            }
        } label: {
            Text("Pseudonym in Study")
        }
    }

    private func profileRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        } label: {
            Text(title)
        }
    }

    private func profileCopyableRow(_ title: String, _ value: String) -> some View {
        LabeledContent {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                copyButton(value)
            }
        } label: {
            Text(title)
        }
    }

    private func copyButton(_ value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
        } label: {
            Image(systemName: "doc.on.doc")
                .imageScale(.medium)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Copy")
    }

    private func normalizedProfileValue(_ value: String?) -> String? {
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        return nil
    }

    private func openEmail(_ emailAddress: String) {
        guard let encodedAddress = emailAddress.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "mailto:\(encodedAddress)") else { return }
        openURL(url)
    }

    private func callPhoneNumber(_ phoneNumber: String) {
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789*#")
        let normalized = String(phoneNumber.unicodeScalars.filter { allowedCharacters.contains($0) })
        guard !normalized.isEmpty, let url = URL(string: "tel://\(normalized)") else { return }
        openURL(url)
    }

    private func openAddress(_ address: String) {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "maps.apple.com"
        components.queryItems = [URLQueryItem(name: "q", value: address)]
        guard let url = components.url else { return }
        openURL(url)
    }

    private func dateSelectionBinding(_ date: Binding<Foundation.Date>, isIncluded: Binding<Bool>) -> Binding<Foundation.Date> {
        Binding(
            get: { date.wrappedValue },
            set: { newValue in
                date.wrappedValue = newValue
                isIncluded.wrappedValue = true
            }
        )
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
            .accessibilityHint("Double tap to toggle whether this value is saved")

            content()
        }
    }

    private func syncPatientID() {
        patientID = vm.activePatient?.displayID ?? ""
    }
}

// ---------------------------------------------------------------------
// MARK: Profile UI Info Views
// ---------------------------------------------------------------------
private struct HoehnYahrInfoView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("The Modified Hoehn and Yahr Scale")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Self.stages, id: \.stage) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stage \(item.stage)")
                                .font(.subheadline.weight(.semibold))
                            Text(item.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Hoehn & Yahr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private static let stages: [(stage: String, description: String)] = [
        ("1", "Unilateral (one-sided) involvement only, usually with minimal or no functional disability."),
        ("1.5", "Unilateral and axial (midline of the body) involvement."),
        ("2", "Bilateral or midline involvement without impairment of balance."),
        ("2.5", "Mild bilateral disease, with recovery on the pull test (a test checking for postural instability)."),
        ("3", "Mild to moderate bilateral disease; some postural instability, but the patient remains physically independent."),
        ("4", "Severe disability; the patient is still able to walk or stand unassisted, but significantly impaired."),
        ("5", "Wheelchair bound or bedridden unless aided.")
    ]
}

private struct PDSubtypeInfoView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Verlaufsformen der Parkinson-Krankheit")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Self.subtypes, id: \.title) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("PD Subtype")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private static let subtypes: [(title: String, description: String)] = [
        ("Hypokinetisch-rigider Typ", "Deutliche Überbetonung der hypokinetischen Symptome und des Rigors gegenüber dem Tremor."),
        ("Äquivalenz-Typ", "Ruhetremor, Hypokinese und Rigor etwa gleich stark ausgeprägt."),
        ("Tremordominanz-Typ", "Im Vordergrund stehender Ruhetremor bei vergleichsweise geringer Ausprägung von Hypokinese und Rigor."),
        ("Monosymptomatischer Ruhetremor", "Selten.")
    ]
}

// ---------------------------------------------------------------------
// MARK: Patient Seletion UI
// ---------------------------------------------------------------------
private struct PatientSelectionSheet: View {
    @ObservedObject var vm: PatientProfileViewModel
    @Binding var isPresented: Bool
    @Binding var isEditing: Bool
    @Binding var showingError: Bool
    let syncPatientID: () -> Void

    @State private var selectedPatientId: Int64?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    createPatientButton

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader

                        if vm.availablePatients.isEmpty {
                            emptyState
                        } else {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(vm.availablePatients, id: \.pickerId) { patient in
                                    patientRow(patient)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Patient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {
                vm.reload()
                selectedPatientId = vm.activePatient?.id?.numericId() ?? vm.availablePatients.first?.pickerId
            }
        }
    }

    private var createPatientButton: some View {
        Button {
            vm.clearForm()
            isEditing = true
            isPresented = false
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.title2)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Create New Patient")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Start a blank profile")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline)
            }
            .padding()
            .foregroundStyle(.white)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var sectionHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Saved Patients")
                .font(.headline)

            Text("Reopen a previous patient profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            Text("No saved patients available yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func patientRow(_ patient: ParkinsonMetadata.Patient) -> some View {
        let isSelected = selectedPatientId == patient.pickerId
        let isActive = vm.activePatient?.id?.numericId() == patient.pickerId

        return VStack(alignment: .leading, spacing: 12) {
            Button {
                selectedPatientId = patient.pickerId
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(patient.alias)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)

                            if isActive {
                                Text("Active")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.green.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(patient.pseudonymInStudyValue)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await vm.activatePatient(id: patient.pickerId)
                    showingError = vm.errorMessage != nil
                    if vm.errorMessage == nil {
                        syncPatientID()
                        isEditing = false
                        isPresented = false
                    }
                }
            } label: {
                Label(isActive ? "Current Patient" : "Select Patient", systemImage: isActive ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isActive || vm.isSaving)
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        }
    }
}

// ---------------------------------------------------------------------
// MARK: Profile ViewModel
// ---------------------------------------------------------------------
@MainActor
private final class PatientProfileViewModel: ObservableObject {
    @Published var activePatient: ParkinsonMetadata.Patient?
    @Published var isSaving = false
    @Published var errorMessage: String?

    @Published var patientId: ParkinsonMetadata.PatientId?
    @Published var alias = ""
    @Published var additionalLabPseudonym = ""
    @Published var pseudonymCountUpValue = 101
    @Published var scId = ""
    @Published var studyId = ""
    @Published var includeStudyId = false
    @Published var studyStatus = ""
    @Published var includeStudyStatus = false
    @Published var consent = false
    @Published var ukeNeurologist = ""
    @Published var includeUKENeurologist = false
    @Published var ukeStudySupervisor = ""
    @Published var includeUKEStudySupervisor = false

    @Published var dateBirth = Foundation.Date()
    @Published var dateDiagnosis = Foundation.Date()
    @Published var dateFirstSymptoms = Foundation.Date()
    @Published var includeDateBirth = false
    @Published var includeDateDiagnosis = false
    @Published var includeDateFirstSymptoms = false

    @Published var sex: ParkinsonMetadata.Sex = .male
    @Published var includeSex = false
    let sexOptions: [ParkinsonMetadata.Sex] = [.male, .female, .other]

    @Published var height = 180
    @Published var weight = 75
    @Published var includeHeight = false
    @Published var includeWeight = false

    @Published var hasDBS = false
    @Published var includeDBS = false
    @Published var dbsDate = Foundation.Date()
    @Published var includeDBSDate = false
    @Published var complexTreatment = false
    @Published var includeComplexTreatment = false
    @Published var useWearable = false
    @Published var includeUseWearable = false
    @Published var watchSide: ParkinsonMetadata.BodySide = .right
    @Published var includeWatchSide = false
    @Published var useCap = false
    @Published var includeUseCap = false
    @Published var useGloves = "Both"
    @Published var includeUseGloves = false
    let gloveSideOptions = ["Left", "Right", "Both"]
    @Published var deviceId = AppDeviceIdentifier.current
    @Published var deviceName = ""
    @Published var watchId = ""
    @Published var watchName = ""
    @Published var capId = ""
    @Published var capName = ""
    @Published var glovesId = ""
    @Published var glovesName = ""

    @Published var preferredHand: ParkinsonMetadata.BodySide = .right
    @Published var mostAffectedSide: ParkinsonMetadata.BodySide = .right
    @Published var includePreferredHand = false
    @Published var includeMostAffectedSide = false
    let sideOptions: [ParkinsonMetadata.BodySide] = [.left, .right, .both]

    @Published var dominantSymptom = ""
    @Published var pdSubtype = "Hypokinetisch-rigider Typ"
    @Published var includePDSubtype = false
    let pdSubtypeOptions = [
        "Hypokinetisch-rigider Typ",
        "Äquivalenz-Typ",
        "Tremordominanz-Typ",
        "Monosymptomatischer Ruhetremor"
    ]
    @Published var hoehnYahr = 1.0
    @Published var includeHoehnYahr = false
    let hoehnYahrOptions = [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0]
    @Published var pdFamilyHistory = false
    @Published var includePDFamilyHistory = false
    @Published var lastMocaScore = 0
    @Published var includeLastMocaScore = false
    @Published var lastMocaDate = Foundation.Date()
    @Published var includeLastMocaDate = false
    @Published var treatmentSetting = "Ambulatory"
    @Published var includeTreatmentSetting = false
    let treatmentSettingOptions = ["Ambulatory", "Stationary"]
    @Published var isSmoker = false
    @Published var includeIsSmoker = false
    @Published var hasQuitDate = false
    @Published var quitDate = Foundation.Date()
    @Published var includeQuitDate = false
    @Published var smokedPacksPerYear = 0
    @Published var includeSmokedPacksPerYear = false
    @Published var hasAlcohol = false
    @Published var includeAlcohol = false
    @Published var alcoholPerWeek = 0
    @Published var includeAlcoholPerWeek = false
    @Published var drivesCar = "Yes"
    @Published var includeDrivesCar = false
    let drivesCarOptions = ["Yes", "No License", "Not anymore"]
    @Published var quitDrivingDate = Foundation.Date()
    @Published var includeQuitDrivingDate = false
    @Published var comorbidities = ""
    @Published var emailAddress = ""
    @Published var includeEmailAddress = false
    @Published var phoneNumber = ""
    @Published var includePhoneNumber = false
    @Published var caregiverPhoneNumber = ""
    @Published var includeCaregiverPhoneNumber = false
    @Published var address = ""
    @Published var includeAddress = false
    @Published var homeNeurologist = ""
    @Published var includeHomeNeurologist = false
    @Published var caregiver = ""
    @Published var includeCaregiver = false
    @Published var languages = ""
    @Published var includeLanguages = false
    @Published var job = ""
    @Published var living = "Haus"
    @Published var includeLiving = false
    let livingOptions = ["Haus", "Wohnung", "Altenheim", "Betreutes Wohnen", "Community", "Krankenhaus", "Wohngemeinschaft", "Sonstiges"]
    @Published var social = "Single"
    @Published var includeSocial = false
    let socialOptions = ["Single", "Verheiratet", "Geschieden", "Verwitwet", "Partnerschaft", "Sonstiges"]
    @Published var children = 0
    @Published var includeChildren = false
    @Published var cohort = ""
    @Published var includeCohort = false
    @Published var notes = ""

    private var store: ParkinsonMetadataStore { .shared }

    var isFormValid: Bool {
        saveDisabledReason == nil
    }

    var saveDisabledReason: String? {
        if alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Alias is required to save."
        }

        if !consent {
            return "Consent must be given to save."
        }

        if !isEmailAddressValid {
            return "Please enter a valid email address."
        }

        return nil
    }

    var isEmailAddressValid: Bool {
        let trimmed = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return trimmed.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    var availablePatients: [ParkinsonMetadata.Patient] {
        store.allPatients.sorted { lhs, rhs in
            lhs.pickerLabel.localizedStandardCompare(rhs.pickerLabel) == .orderedAscending
        }
    }

    init() {
        reload()
    }

    func reload() {
        store.reloadPatients()
        activePatient = store.activePatient
    }

    func load(patient: ParkinsonMetadata.Patient) {
        patientId = patient.id
        alias = patient.alias
        additionalLabPseudonym = patient.additionalLabPseudonym ?? ""
        scId = patient.scId.map(String.init) ?? ""
        studyId = patient.studyId ?? ""
        includeStudyId = patient.studyId != nil
        studyStatus = patient.studyStatus ?? ""
        includeStudyStatus = patient.studyStatus != nil
        consent = patient.consent
        ukeNeurologist = patient.ukeNeurologist ?? ""
        includeUKENeurologist = patient.ukeNeurologist != nil
        ukeStudySupervisor = patient.ukeStudySupervisor ?? ""
        includeUKEStudySupervisor = patient.ukeStudySupervisor != nil
        dateBirth = patient.dateBirth?.toFoundationDate() ?? Foundation.Date()
        dateDiagnosis = patient.dateDiagnosis?.toFoundationDate() ?? Foundation.Date()
        dateFirstSymptoms = patient.dateFirstSymptoms?.toFoundationDate() ?? Foundation.Date()
        includeDateBirth = patient.dateBirth != nil
        includeDateDiagnosis = patient.dateDiagnosis != nil
        includeDateFirstSymptoms = patient.dateFirstSymptoms != nil
        sex = patient.sex ?? .male
        includeSex = patient.sex != nil
        height = patient.height.map { Int($0.value()) } ?? 180
        weight = patient.weight.map { Int($0.value()) } ?? 75
        includeHeight = patient.height != nil
        includeWeight = patient.weight != nil

        switch patient.deepBrainStimulation {
        case nil:
            hasDBS = false
            includeDBS = false
            includeDBSDate = false
        case .no:
            hasDBS = false
            includeDBS = true
            includeDBSDate = false
        case .yes(let date):
            hasDBS = true
            includeDBS = true
            dbsDate = date.toFoundationDate()
            includeDBSDate = true
        }

        complexTreatment = patient.complexTreatment ?? false
        includeComplexTreatment = patient.complexTreatment != nil
        switch patient.useWearable {
        case nil:
            useWearable = false
            includeUseWearable = false
            watchSide = .right
        case .no:
            useWearable = false
            includeUseWearable = true
        case .yes(let side):
            useWearable = true
            includeUseWearable = true
            watchSide = side
        }
        includeWatchSide = patient.useWearable != nil
        useCap = patient.useCap ?? false
        includeUseCap = patient.useCap != nil
        useGloves = patient.useGloves ?? "Both"
        includeUseGloves = patient.useGloves != nil
        deviceId = AppDeviceIdentifier.current
        deviceName = patient.deviceName ?? ""
        watchId = patient.watchId ?? ""
        watchName = patient.watchName ?? ""
        capId = patient.capId ?? ""
        capName = patient.capName ?? ""
        glovesId = patient.glovesId ?? ""
        glovesName = patient.glovesName ?? ""
        preferredHand = patient.preferredHand ?? .right
        mostAffectedSide = patient.mostAffectedSide ?? .right
        includePreferredHand = patient.preferredHand != nil
        includeMostAffectedSide = patient.mostAffectedSide != nil
        dominantSymptom = patient.dominantSymptom ?? ""
        pdSubtype = patient.pdSubtype ?? "Hypokinetisch-rigider Typ"
        includePDSubtype = patient.pdSubtype != nil
        hoehnYahr = patient.hoehnYahr.map(Self.hoehnYahrStage) ?? 1.0
        includeHoehnYahr = patient.hoehnYahr != nil
        pdFamilyHistory = patient.pdFamilyHistory ?? false
        includePDFamilyHistory = patient.pdFamilyHistory != nil
        lastMocaScore = Int(patient.lastMocaScore ?? 0)
        includeLastMocaScore = patient.lastMocaScore != nil
        lastMocaDate = patient.lastMocaDate?.toFoundationDate() ?? Foundation.Date()
        includeLastMocaDate = patient.lastMocaDate != nil
        treatmentSetting = patient.stationary == true ? "Stationary" : "Ambulatory"
        includeTreatmentSetting = patient.ambulatory != nil || patient.stationary != nil
        isSmoker = patient.isSmoker ?? false
        includeIsSmoker = patient.isSmoker != nil
        hasQuitDate = patient.quitSmoking != nil
        quitDate = patient.quitSmoking?.toFoundationDate() ?? Foundation.Date()
        includeQuitDate = patient.quitSmoking != nil
        smokedPacksPerYear = Int(patient.smokedPacksPerYear ?? 0)
        includeSmokedPacksPerYear = patient.smokedPacksPerYear != nil
        hasAlcohol = patient.alcoholConsumptionPerWeek != nil
        includeAlcohol = patient.alcoholConsumptionPerWeek != nil
        alcoholPerWeek = Int(patient.alcoholConsumptionPerWeek ?? 0)
        includeAlcoholPerWeek = patient.alcoholConsumptionPerWeek != nil
        drivesCar = Self.drivesCarOption(patient.drivesCar)
        includeDrivesCar = patient.drivesCar != nil
        quitDrivingDate = patient.quitDrivingDate?.toFoundationDate() ?? Foundation.Date()
        includeQuitDrivingDate = patient.quitDrivingDate != nil
        comorbidities = patient.comorbidity ?? ""
        emailAddress = patient.emailAddress ?? ""
        includeEmailAddress = patient.emailAddress != nil
        phoneNumber = patient.phoneNumber ?? ""
        includePhoneNumber = patient.phoneNumber != nil
        caregiverPhoneNumber = patient.caregiverPhoneNumber ?? ""
        includeCaregiverPhoneNumber = patient.caregiverPhoneNumber != nil
        address = patient.address ?? ""
        includeAddress = patient.address != nil
        homeNeurologist = patient.homeNeurologist ?? ""
        includeHomeNeurologist = patient.homeNeurologist != nil
        caregiver = patient.caregiver ?? ""
        includeCaregiver = patient.caregiver != nil
        languages = patient.languages ?? ""
        includeLanguages = patient.languages != nil
        job = patient.job ?? ""
        living = patient.living ?? "Haus"
        includeLiving = patient.living != nil
        social = patient.social ?? "Single"
        includeSocial = patient.social != nil
        children = patient.children.map { Int($0) } ?? 0
        includeChildren = patient.children != nil
        cohort = patient.cohort ?? ""
        includeCohort = patient.cohort != nil
        notes = patient.notes ?? ""
    }

    func save(isEditing: Bool) async {
        isSaving = true
        defer { isSaving = false }

        do {
            if !isEditing, var active = activePatient {
                active.isActive = false
                _ = try store.savePatient(active)
            }

            let patient = try buildPatient(isEditing: isEditing)
            let saved = try store.savePatient(patient)
            activePatient = saved
            load(patient: saved)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            print("[PatientProfile] Save failed: \(error)")
        }
    }

    func activatePatient(id: Int64) async {
        isSaving = true
        defer { isSaving = false }

        do {
            store.reloadPatients()

            guard var selected = store.allPatients.first(where: { $0.id?.numericId() == id }) else {
                errorMessage = "Selected patient could not be found."
                return
            }

            for var patient in store.allPatients where patient.id?.numericId() != id && patient.isActive == true {
                patient.isActive = false
                _ = try store.savePatient(patient)
            }

            selected.isActive = true
            let saved = try store.savePatient(selected)
            activePatient = saved
            load(patient: saved)
            errorMessage = nil
            print("[PatientProfile] Active patient selected: \(saved.displayID)")
        } catch {
            errorMessage = error.localizedDescription
            print("[PatientProfile] Patient selection failed: \(error)")
        }
    }

    func clearForm() {
        patientId = nil
        alias = ""
        additionalLabPseudonym = ""
        pseudonymCountUpValue = 101
        scId = ""
        studyId = ""
        includeStudyId = false
        studyStatus = ""
        includeStudyStatus = false
        consent = false
        ukeNeurologist = ""
        includeUKENeurologist = false
        ukeStudySupervisor = ""
        includeUKEStudySupervisor = false
        dateBirth = Foundation.Date()
        dateDiagnosis = Foundation.Date()
        dateFirstSymptoms = Foundation.Date()
        includeDateBirth = false
        includeDateDiagnosis = false
        includeDateFirstSymptoms = false
        sex = .male
        includeSex = false
        height = 180
        weight = 75
        includeHeight = false
        includeWeight = false
        hasDBS = false
        includeDBS = false
        dbsDate = Foundation.Date()
        includeDBSDate = false
        complexTreatment = false
        includeComplexTreatment = false
        useWearable = false
        includeUseWearable = false
        watchSide = .right
        includeWatchSide = false
        useCap = false
        includeUseCap = false
        useGloves = "Both"
        includeUseGloves = false
        deviceId = AppDeviceIdentifier.current
        deviceName = ""
        watchId = ""
        watchName = ""
        capId = ""
        capName = ""
        glovesId = ""
        glovesName = ""
        preferredHand = .right
        mostAffectedSide = .right
        includePreferredHand = false
        includeMostAffectedSide = false
        dominantSymptom = ""
        pdSubtype = "Hypokinetisch-rigider Typ"
        includePDSubtype = false
        hoehnYahr = 1.0
        includeHoehnYahr = false
        pdFamilyHistory = false
        includePDFamilyHistory = false
        lastMocaScore = 0
        includeLastMocaScore = false
        lastMocaDate = Foundation.Date()
        includeLastMocaDate = false
        treatmentSetting = "Ambulatory"
        includeTreatmentSetting = false
        isSmoker = false
        includeIsSmoker = false
        hasQuitDate = false
        quitDate = Foundation.Date()
        includeQuitDate = false
        smokedPacksPerYear = 0
        includeSmokedPacksPerYear = false
        hasAlcohol = false
        includeAlcohol = false
        alcoholPerWeek = 0
        includeAlcoholPerWeek = false
        drivesCar = "Yes"
        includeDrivesCar = false
        quitDrivingDate = Foundation.Date()
        includeQuitDrivingDate = false
        comorbidities = ""
        emailAddress = ""
        includeEmailAddress = false
        phoneNumber = ""
        includePhoneNumber = false
        caregiverPhoneNumber = ""
        includeCaregiverPhoneNumber = false
        address = ""
        includeAddress = false
        homeNeurologist = ""
        includeHomeNeurologist = false
        caregiver = ""
        includeCaregiver = false
        languages = ""
        includeLanguages = false
        job = ""
        living = "Haus"
        includeLiving = false
        social = "Single"
        includeSocial = false
        children = 0
        includeChildren = false
        cohort = ""
        includeCohort = false
        notes = ""
        errorMessage = nil
    }

    private func buildPatient(isEditing: Bool) throws -> ParkinsonMetadata.Patient {
        ParkinsonMetadata.Patient(
            id: isEditing ? patientId : nil,
            alias: alias.trimmingCharacters(in: .whitespacesAndNewlines),
            additionalLabPseudonym: additionalLabPseudonym.nilIfBlank,
            scId: UInt64(scId.trimmingCharacters(in: .whitespacesAndNewlines)),
            studyId: includeStudyId ? studyId.nilIfBlank : nil,
            dateBirth: includeDateBirth ? try dateBirth.toParkinsonMetadataDate() : nil,
            dateDiagnosis: includeDateDiagnosis ? try dateDiagnosis.toParkinsonMetadataDate() : nil,
            dateFirstSymptoms: includeDateFirstSymptoms ? try dateFirstSymptoms.toParkinsonMetadataDate() : nil,
            sex: includeSex ? sex : nil,
            height: includeHeight ? try ParkinsonMetadata.Centimeter(value: UInt16(height)) : nil,
            weight: includeWeight ? try ParkinsonMetadata.Kilograms(value: UInt16(weight)) : nil,
            deepBrainStimulation: includeDBS ? (hasDBS ? (includeDBSDate ? .yes(try dbsDate.toParkinsonMetadataDate()) : nil) : .no) : nil,
            complexTreatment: includeComplexTreatment ? complexTreatment : nil,
            useWearable: includeUseWearable ? (useWearable ? (includeWatchSide ? .yes(watchSide) : nil) : .no) : nil,
            useCap: includeUseCap ? useCap : nil,
            mostAffectedSide: includeMostAffectedSide ? mostAffectedSide : nil,
            dominantSymptom: dominantSymptom.trimmingCharacters(in: .whitespacesAndNewlines),
            consent: consent,
            isActive: true,
            preferredHand: includePreferredHand ? preferredHand : nil,
            isSmoker: includeIsSmoker ? isSmoker : nil,
            quitSmoking: includeIsSmoker && isSmoker && hasQuitDate && includeQuitDate ? try quitDate.toParkinsonMetadataDate() : nil,
            smokedPacksPerYear: includeIsSmoker && isSmoker && includeSmokedPacksPerYear ? UInt32(smokedPacksPerYear) : nil,
            alcoholConsumptionPerWeek: includeAlcohol && hasAlcohol && includeAlcoholPerWeek ? UInt32(alcoholPerWeek) : nil,
            job: job.nilIfBlank,
            living: includeLiving ? living : nil,
            social: includeSocial ? social : nil,
            comorbidity: comorbidities.nilIfBlank,
            notes: notes.nilIfBlank,
            useGloves: includeUseGloves ? useGloves : nil,
            deviceId: AppDeviceIdentifier.current,
            deviceName: deviceName.nilIfBlank,
            watchId: includeUseWearable && useWearable ? watchId.nilIfBlank : nil,
            watchName: includeUseWearable && useWearable ? watchName.nilIfBlank : nil,
            capId: includeUseCap && useCap ? capId.nilIfBlank : nil,
            capName: includeUseCap && useCap ? capName.nilIfBlank : nil,
            glovesId: includeUseGloves ? glovesId.nilIfBlank : nil,
            glovesName: includeUseGloves ? glovesName.nilIfBlank : nil,
            pdSubtype: includePDSubtype ? pdSubtype : nil,
            hoehnYahr: includeHoehnYahr ? Self.persistedHoehnYahrStage(hoehnYahr) : nil,
            children: includeChildren ? UInt32(children) : nil,
            cohort: includeCohort ? cohort.nilIfBlank : nil,
            emailAddress: emailAddress.nilIfBlank,
            phoneNumber: phoneNumber.nilIfBlank,
            caregiverPhoneNumber: caregiverPhoneNumber.nilIfBlank,
            address: address.nilIfBlank,
            ukeNeurologist: ukeNeurologist.nilIfBlank,
            ukeStudySupervisor: ukeStudySupervisor.nilIfBlank,
            ambulatory: includeTreatmentSetting ? treatmentSetting == "Ambulatory" : nil,
            stationary: includeTreatmentSetting ? treatmentSetting == "Stationary" : nil,
            homeNeurologist: homeNeurologist.nilIfBlank,
            drivesCar: includeDrivesCar ? drivesCar : nil,
            quitDrivingDate: includeDrivesCar && drivesCar == "Not anymore" && includeQuitDrivingDate ? try quitDrivingDate.toParkinsonMetadataDate() : nil,
            pdFamilyHistory: includePDFamilyHistory ? pdFamilyHistory : nil,
            lastMocaScore: includeLastMocaScore ? UInt32(lastMocaScore) : nil,
            lastMocaDate: includeLastMocaScore && includeLastMocaDate ? try lastMocaDate.toParkinsonMetadataDate() : nil,
            caregiver: caregiver.nilIfBlank,
            languages: languages.nilIfBlank,
            studyStatus: includeStudyStatus ? studyStatus.nilIfBlank : nil
        )
    }

    func hoehnYahrLabel(_ stage: Double) -> String {
        Self.hoehnYahrLabel(stage)
    }

    private static func hoehnYahrStage(from rawValue: UInt32) -> Double {
        switch rawValue {
        case 10: return 1.0
        case 15: return 1.5
        case 20: return 2.0
        case 25: return 2.5
        case 30: return 3.0
        case 40: return 4.0
        case 50: return 5.0
        default: return Double(rawValue)
        }
    }

    private static func persistedHoehnYahrStage(_ stage: Double) -> UInt32 {
        UInt32((stage * 10).rounded())
    }

    private static func hoehnYahrLabel(_ stage: Double) -> String {
        if stage.rounded() == stage {
            return "\(Int(stage))"
        }

        return String(format: "%.1f", stage).replacingOccurrences(of: ".", with: ",")
    }

    private static func drivesCarOption(_ value: String?) -> String {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty else {
            return "Yes"
        }

        switch normalized.lowercased() {
        case "yes", "true", "1", "ja":
            return "Yes"
        case "no license", "nolicense", "no_license":
            return "No License"
        case "not anymore", "no", "false", "0", "nein":
            return "Not anymore"
        default:
            return normalized
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfPlaceholder: String? {
        self == "Not set" ? nil : self
    }
}

private func hoehnYahrDisplayValue(_ rawValue: UInt32) -> String {
    switch rawValue {
    case 10: return "1"
    case 15: return "1,5"
    case 20: return "2"
    case 25: return "2,5"
    case 30: return "3"
    case 40: return "4"
    case 50: return "5"
    default: return "\(rawValue)"
    }
}

private extension ParkinsonMetadata.Sex {
    var label: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        }
    }
}

private extension ParkinsonMetadata.BodySide {
    var label: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .both: return "Both"
        }
    }
}

private extension ParkinsonMetadata.Patient {
    var dbsLabel: String {
        switch deepBrainStimulation {
        case nil:
            return "Not set"
        case .no:
            return "No"
        case .yes(let date):
            return "Yes, \(date.toString())"
        }
    }

    var watchLabel: String {
        switch useWearable {
        case nil:
            return "Not set"
        case .no:
            return "No"
        case .yes(let side):
            return "Yes, \(side.label)"
        }
    }

    var deviceLabel: String {
        joinedDeviceLabel(name: deviceName, id: deviceId)
    }

    var watchDeviceLabel: String {
        joinedDeviceLabel(name: watchName, id: watchId)
    }

    var capDeviceLabel: String {
        joinedDeviceLabel(name: capName, id: capId)
    }

    var glovesDeviceLabel: String {
        joinedDeviceLabel(name: glovesName, id: glovesId)
    }

    var hasDemographicsSummary: Bool {
        dateBirth != nil
            || sex != nil
            || height != nil
            || weight != nil
    }

    var hasSymptomsSummary: Bool {
        dateFirstSymptoms != nil
            || dateDiagnosis != nil
            || mostAffectedSide != nil
            || preferredHand != nil
            || dominantSymptom?.nilIfBlank != nil
            || pdSubtype?.nilIfBlank != nil
            || hoehnYahr != nil
            || pdFamilyHistory != nil
            || lastMocaScore != nil
            || lastMocaDate != nil
            || comorbidity?.nilIfBlank != nil
    }

    var hasTreatmentSummary: Bool {
        deepBrainStimulation != nil
            || complexTreatment != nil
            || ambulatory != nil
            || stationary != nil
            || ukeNeurologist?.nilIfBlank != nil
            || useWearable != nil
            || useCap != nil
            || useGloves?.nilIfBlank != nil
            || deviceLabel.nilIfPlaceholder != nil
            || watchDeviceLabel.nilIfPlaceholder != nil
            || capDeviceLabel.nilIfPlaceholder != nil
            || glovesDeviceLabel.nilIfPlaceholder != nil
    }

    var hasLifestyleSummary: Bool {
        isSmoker != nil
            || alcoholConsumptionPerWeek != nil
            || drivesCar?.nilIfBlank != nil
            || quitDrivingDate != nil
    }

    var hasSocialSummary: Bool {
        address?.nilIfBlank != nil
            || emailAddress?.nilIfBlank != nil
            || phoneNumber?.nilIfBlank != nil
            || caregiver?.nilIfBlank != nil
            || caregiverPhoneNumber?.nilIfBlank != nil
            || homeNeurologist?.nilIfBlank != nil
            || languages?.nilIfBlank != nil
            || job?.nilIfBlank != nil
            || living?.nilIfBlank != nil
            || social?.nilIfBlank != nil
            || children != nil
    }

    private func joinedDeviceLabel(name: String?, id: String?) -> String {
        let parts = [name, id]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " / ")
    }

    var pickerId: Int64 {
        id?.numericId() ?? -1
    }

    var pickerLabel: String {
        "\(pseudonymInStudyValue) (\(alias))"
    }

    var pseudonymInStudyValue: String {
        additionalLabPseudonym ?? "Pseudonym in Study not set"
    }
}

