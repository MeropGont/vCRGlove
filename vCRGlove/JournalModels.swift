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
}

enum SymptomSeverity: String, CaseIterable, Codable {
    case notPresent
    case mild
    case moderate
    case severe
    
    var label: String {
        switch self {
        case .notPresent: return "Not present"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
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
}

enum MedicationEvent: String, CaseIterable, Codable, Identifiable {
    case usual = "Took usual medication"
    case late = "Took medication late"
    case missed = "Missed medication"
    case extra = "Took extra/rescue medication"

    var id: String { rawValue }
}

enum MotorState: String, CaseIterable, Codable, Identifiable {
    case on = "ON / medication working"
    case off = "OFF / symptoms are back"
    case dyskinesia = "Dyskinesia / too much movement"
    case unsure = "Not sure"

    var id: String { rawValue }
}

enum MedicationFactor: String, CaseIterable, Codable, Identifiable {
    case food = "With food"
    case protein = "High-protein meal"
    case stress = "Stress"
    case poorSleep = "Poor sleep"
    case constipation = "Constipation"
    case activity = "Exercise/activity"

    var id: String { rawValue }
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
}

enum JournalEntryType: String, Codable {
    case dailyCheckIn
    case medication
    case symptm
    case note
    case pdq8
}

struct JournalEntry: Identifiable, Codable {
    let id: UUID
    let date: Date
    let type: JournalEntryType
    let mood: Int?
    let symptomSeverity: SymptomSeverity?
    let symptoms: [String]
    let medicationName: String?
    let medicationDose: String?
    let note: String?
    let medicationEvent: MedicationEvent?
    let motorState: MotorState?
    let medicationFactors: [MedicationFactor]
    let symptomEpisodeType: SymptomEpisodeType?



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
        symptomEpisodeType: SymptomEpisodeType? = nil

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
    }
}
