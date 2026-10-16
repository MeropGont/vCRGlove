//
//  JournalModels.swift
//  vCRGlove
//
//  Created by Tactile Glove on 22.04.26.
//

import Foundation

enum MoodRating: String, CaseIterable, Codable {
    case veryBad = "Very Bad"
    case bad = "Bad"
    case neutral = "Neutral"
    case good = "Good"
    case veryGood = "Very Good"

    var displayName: String { L10n(rawValue) }

    var checkInLabel: String { self == .neutral ? L10n("Okay") : displayName }
}

enum SymptomSeverity: String, CaseIterable, Codable {
    case notPresent
    case mild
    case moderate
    case severe

    var label: String {
        switch self {
        case .notPresent: return L10n("Not present")
        case .mild:       return L10n("Mild")
        case .moderate:   return L10n("Moderate")
        case .severe:     return L10n("Severe")
        }
    }
}

enum SymptomTag: String, CaseIterable, Codable, Identifiable {
    case tremor = "Tremor"
    case stiffness = "Stiffness"
    case slowness = "Slowness"
    case freezing = "Freezing"
    case balance = "Balance"
    case swallowing = "Swallowing"
    case cramps = "Cramps"
    case fatigue = "Fatigue"
    case sleep = "Sleep"
    case concentration = "Concentration"
    case moodLow = "Low Mood"
    case anxiety = "Anxiety"
    case dizziness = "Dizziness"
    case pain = "Pain"

    var id: String { rawValue }
    var displayName: String { L10n(rawValue) }
}

enum MedicationEvent: String, CaseIterable, Codable, Identifiable {
    case usual = "Took usual medication"
    case late = "Took medication late"
    case missed = "Missed medication"
    case extra = "Took extra/rescue medication"

    var id: String { rawValue }
    var displayName: String { L10n(rawValue) }
}

enum DailyActivityImpact: String, CaseIterable, Codable {
    case notAtAll, little, moderate, large, unable, unsure, skipped

    static let ratingChoices: [Self] = [.notAtAll, .little, .moderate, .large, .unable]

    var label: String {
        switch self {
        case .notAtAll: return L10n("Not at all")
        case .little: return L10n("A little")
        case .moderate: return L10n("Moderately")
        case .large: return L10n("A lot")
        case .unable: return L10n("Could not do my usual activities")
        case .unsure: return L10n("Not sure")
        case .skipped: return L10n("Skip question")
        }
    }
}

enum DailyMedicationSummary: String, CaseIterable, Codable {
    case asPlanned, changed, nonePlanned, unsure, skipped

    var label: String {
        switch self {
        case .asPlanned: return L10n("As planned")
        case .changed: return L10n("Something changed")
        case .nonePlanned: return L10n("No medication planned")
        case .unsure: return L10n("Not sure")
        case .skipped: return L10n("Skip question")
        }
    }
}

enum DailyMedicationChange: String, CaseIterable, Codable {
    case late, missed, extra, other

    var label: String {
        switch self {
        case .late: return L10n("Late dose")
        case .missed: return L10n("Missed dose")
        case .extra: return L10n("Extra dose")
        case .other: return L10n("Another change")
        }
    }
}

enum MotorState: String, CaseIterable, Codable, Identifiable {
    case on = "ON / medication working"
    case off = "OFF / symptoms are back"
    case dyskinesia = "Dyskinesia / too much movement"
    case unsure = "Not sure"

    var id: String { rawValue }
    var displayName: String { L10n(rawValue) }
}

enum MedicationFactor: String, CaseIterable, Codable, Identifiable {
    case food = "With food"
    case protein = "High-protein meal"
    case stress = "Stress"
    case poorSleep = "Poor sleep"
    case constipation = "Constipation"
    case activity = "Exercise/activity"

    var id: String { rawValue }
    var displayName: String { L10n(rawValue) }
}

enum SymptomEpisodeType: String, CaseIterable, Codable, Identifiable {
    case off = "OFF episode"
    case dyskinesia = "Dyskinesia"
    case freezing = "Freezing"
    case fall = "Fall / near fall"
    case tremor = "Tremor episode"
    case anxiety = "Anxiety / panic"
    case pain = "Pain"
    case deviceIssue = "Device issue"

    var id: String { rawValue }
    var displayName: String { L10n(rawValue) }
}

enum JournalEntryType: String, Codable {
    case dailyCheckIn
    case medication
    case symptom
    case note
    case stimulation
    case pdq8

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "symptm":
            self = .symptom
        default:
            guard let type = JournalEntryType(rawValue: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unknown journal entry type: \(value)"
                )
            }

            self = type
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}


struct JournalEntry: Identifiable, Codable {
    let id: UUID
    var date: Date
    let type: JournalEntryType
    var mood: Int?
    var symptomSeverity: SymptomSeverity?
    var symptoms: [String]
    let medicationName: String?
    let medicationDose: String?
    var note: String?
    var medicationEvent: MedicationEvent?
    var motorState: MotorState?
    var medicationFactors: [MedicationFactor]
    let symptomEpisodeType: SymptomEpisodeType?
    var createdAt: Date?
    var updatedAt: Date?
    var checkInVersion: Int?
    var activityImpact: DailyActivityImpact?
    var medicationSummary: DailyMedicationSummary?
    var medicationChanges: [DailyMedicationChange]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, date, type, mood, symptomSeverity, symptoms
        case medicationName, medicationDose, note, medicationEvent, motorState
        case medicationFactors, symptomEpisodeType, createdAt, updatedAt
        case checkInVersion, activityImpact, medicationSummary, medicationChanges
    }

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        type: JournalEntryType,
        mood: Int? = nil,
        symptomSeverity: SymptomSeverity? = nil,
        symptoms: [String] = [],
        medicationName: String? = nil,
        medicationDose: String? = nil,
        note: String? = nil,
        medicationEvent: MedicationEvent? = nil,
        motorState: MotorState? = nil,
        medicationFactors: [MedicationFactor] = [],
        symptomEpisodeType: SymptomEpisodeType? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        checkInVersion: Int? = nil,
        activityImpact: DailyActivityImpact? = nil,
        medicationSummary: DailyMedicationSummary? = nil,
        medicationChanges: [DailyMedicationChange] = []
    )
    {
        self.id = id
        self.date = date
        self.type = type
        self.mood = mood
        self.symptomSeverity = symptomSeverity
        self.symptoms = symptoms
        self.medicationName = medicationName
        self.medicationDose = medicationDose
        self.note = note
        self.medicationEvent = medicationEvent
        self.motorState = motorState
        self.medicationFactors = medicationFactors
        self.symptomEpisodeType = symptomEpisodeType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checkInVersion = checkInVersion
        self.activityImpact = activityImpact
        self.medicationSummary = medicationSummary
        self.medicationChanges = medicationChanges
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        date = try values.decode(Date.self, forKey: .date)
        type = try values.decode(JournalEntryType.self, forKey: .type)
        mood = try values.decodeIfPresent(Int.self, forKey: .mood)
        symptomSeverity = try values.decodeIfPresent(SymptomSeverity.self, forKey: .symptomSeverity)
        symptoms = try values.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        medicationName = try values.decodeIfPresent(String.self, forKey: .medicationName)
        medicationDose = try values.decodeIfPresent(String.self, forKey: .medicationDose)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        medicationEvent = try values.decodeIfPresent(MedicationEvent.self, forKey: .medicationEvent)
        motorState = try values.decodeIfPresent(MotorState.self, forKey: .motorState)
        medicationFactors = try values.decodeIfPresent([MedicationFactor].self, forKey: .medicationFactors) ?? []
        symptomEpisodeType = try values.decodeIfPresent(SymptomEpisodeType.self, forKey: .symptomEpisodeType)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt)
        checkInVersion = try values.decodeIfPresent(Int.self, forKey: .checkInVersion)
        activityImpact = try values.decodeIfPresent(DailyActivityImpact.self, forKey: .activityImpact)
        medicationSummary = try values.decodeIfPresent(DailyMedicationSummary.self, forKey: .medicationSummary)
        medicationChanges = try values.decodeIfPresent([DailyMedicationChange].self, forKey: .medicationChanges) ?? []
    }

    var title: String {
        switch type {
        case .dailyCheckIn: return L10n("Daily check-in")
        case .medication: return L10n("Medication")
        case .symptom: return L10n("Symptom episode")
        case .note: return L10n("Note")
        case .stimulation: return L10n("vCR stimulation")
        case .pdq8: return L10n("PDQ-8")
        }
    }

    var iconName: String {
        switch type {
        case .dailyCheckIn: return "heart.text.square"
        case .medication: return "pills"
        case .symptom, .stimulation: return "waveform.path.ecg"
        case .note: return "note.text"
        case .pdq8: return "list.clipboard"
        }
    }

    var detailSummary: String {
        var parts: [String] = []
        if let mood, (1...5).contains(mood) { parts.append(MoodRating.allCases[mood - 1].displayName) }
        if let activityImpact, activityImpact != .skipped {
            parts.append(String(format: L10n("Activity impact: %@"), activityImpact.label))
        }
        if let medicationSummary, medicationSummary != .skipped {
            parts.append(String(format: L10n("Medication: %@"), medicationSummary.label))
        }
        parts += medicationChanges.map(\.label)
        if let symptomSeverity { parts.append(symptomSeverity.label) }
        if let medicationEvent { parts.append(medicationEvent.displayName) }
        if let medicationName { parts.append(medicationName) }
        if let medicationDose { parts.append(medicationDose) }
        if let motorState { parts.append(motorState.displayName) }
        parts += medicationFactors.map(\.displayName)
        parts += symptoms.map { L10n($0) }
        if let note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? L10n("No details") : parts.joined(separator: " · ")
    }

    var checkInSummary: String {
        var parts: [String] = []
        if let mood, (1...5).contains(mood) { parts.append(MoodRating.allCases[mood - 1].checkInLabel) }
        if let activityImpact, activityImpact != .skipped {
            parts.append(String(format: L10n("Activity impact: %@"), activityImpact.label))
        }
        return parts.joined(separator: " · ")
    }
}
