# vCRGlove — Backend Integration Guide for UKE

This document describes the backend integration surface that the vCRGlove iOS app expects. The UKE backend team can implement the server side against this contract and configure the app by editing `vCRGlove/Info.plist` only.

## Configuration

Open `vCRGlove/Info.plist` and set the two custom keys:

| Key                          | Value example                       | Purpose                  |
| ---------------------------- | ----------------------------------- | ------------------------ |
| `VCRGLOVE_BACKEND_URL`       | `https://vcr.uke.de/api`            | Base URL of the backend  |
| `VCRGLOVE_BACKEND_API_KEY`   | `REPLACE_WITH_UKE_API_KEY`          | API key / Bearer token   |

For local development, set `VCRGLOVE_BACKEND_URL` to `http://localhost:8000`.
To disable automatic upload, remove either key from `Info.plist`.

The app reads these keys at launch in `vCRGloveApp.swift` and calls `SessionUploader.shared.configure(baseURL:apiKey:)`.

## Authentication

Every upload request includes the API key as a Bearer token:

```
Authorization: Bearer {VCRGLOVE_BACKEND_API_KEY}
```

UKE can change the authentication scheme in `vCRGlove/SessionUploader.swift` if needed.

## Upload Endpoint

### `POST {VCRGLOVE_BACKEND_URL}/sessions`

Guided sets save locally after each accepted recording and upload when the patient finishes the set. Single-task sessions upload when saved. Upload happens in the background; the patient does not need to interact.

Headers:

```
Content-Type: application/json
Authorization: Bearer {VCRGLOVE_BACKEND_API_KEY}
```

Body: a single JSON-encoded `MovementSession`.

### Response expectations

- `200 OK` or `201 Created` — upload succeeded, the session is removed from the retry queue.
- Any other status code or network error — the upload is retried with exponential back-off (`1 s, 2 s, 4 s, 8 s, 16 s, 32 s, 64 s`).
- After the final attempt fails, the session is stored in a `UserDefaults` pending queue and retried the next time the app comes to the foreground.

## Payload Schema

The `MovementSession` model in `vCRGlove/MovementModels.swift` is `Codable` and serializes to the following JSON structure:

```json
{
  "id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "patientId": "P-12345",
  "date": "2026-08-06T07:34:02.123Z",
  "stimulationContext": "postStim",
  "trials": [
    {
      "id": "f47ac10b-58cc-4372-a567-0e02b2c3d480",
      "taskType": "3.4",
      "side": "right",
      "source": "camera",
      "stopCondition": {
        "mode": "duration",
        "targetReps": 10,
        "targetDuration": 15
      },
      "startedAt": "2026-08-06T07:34:02.456Z",
      "startUptime": 1234567.89,
      "samples": [
        { "t": 0.0, "value": 0.12 },
        { "t": 0.033, "value": 0.14 }
      ],
      "metrics": {
        "cycleCount": 8,
        "frequencyHz": 1.2,
        "meanAmplitude": 0.56,
        "amplitudeDecrementSlope": -0.02,
        "rhythmCV": 0.13,
        "pauseCount": 0,
        "onsetLatencySec": 0.45,
        "qualityIndex": 0.78
      }
    }
  ]
}
```

### Field reference

**`MovementSession`**

| Field                | Type          | Description                                                                 |
| -------------------- | ------------- | --------------------------------------------------------------------------- |
| `id`                 | UUID string   | Unique session identifier                                                   |
| `patientId`          | string        | Pseudonymized patient ID entered in Settings                                |
| `date`               | ISO-8601      | Session recording time                                                      |
| `stimulationContext` | string        | New recordings: `preStim`, `postStim`, `noStimPlanned`. Historical values: `baseline`, `unspecified` |
| `trials`             | array         | One or more `Trial` objects recorded in this session                        |

**`Trial`**

| Field           | Type    | Description                                                                 |
| --------------- | ------- | --------------------------------------------------------------------------- |
| `id`            | UUID    | Unique trial identifier                                                     |
| `taskType`      | string  | MDS-UPDRS-III item number: `3.4`, `3.5`, `3.6`                               |
| `side`          | string  | `left` or `right`                                                           |
| `source`        | string  | `camera` (Vision hand pose), `watchMotion` (Apple Watch), `synthetic`         |
| `stopCondition` | object  | `{ mode: "repetitions" \| "duration", targetReps, targetDuration }`          |
| `startedAt`     | ISO-8601| Wall-clock start time                                                       |
| `startUptime`   | double  | Device uptime at start; used to align sensors that timestamp in uptime       |
| `samples`       | array   | `{ t: seconds, value: signal }` — the raw 1-D signal                         |
| `metrics`       | object  | Computed movement metrics                                                   |
| `medicationTiming` | optional object | Patient-confirmed last intake context for this individual recording     |

### Stimulation and medication context

- `noStimPlanned` means **no stimulation planned today**. It must not replace or reinterpret historical `baseline` records.
- `preStim` and `postStim` refer to stimulation only, not medication. `unspecified` remains readable for older recordings but is not offered as a new patient choice.
- `Trial.startedAt` remains the automatic recording timestamp. Medication timing does not change sample timing or movement metrics.
- An absent `medicationTiming` means unanswered/legacy, **not** no medication taken.

The optional `medicationTiming` object contains:

| Field | Meaning |
| ----- | ------- |
| `status` | `takenAt`, `noneToday`, or `unsure` |
| `takenAt` | ISO-8601 last intake timestamp; only present for `takenAt` |
| `confirmedAt` | ISO-8601 time when the patient entered or confirmed this context |
| `journalEntryID` | Optional UUID when the patient explicitly confirms a journal intake |
| `medicationName`, `medicationDose` | Optional original journal values; never inferred |

Missed doses and ambiguous journal entries are not offered as intake suggestions. A `noneToday` answer does not carry into a recording on the next calendar day. There is no automatic medication ON/OFF classification or clinical time-window rule.

JSON/JSONL exports retain this object. Metrics CSV appends seven columns after the existing 21: `medication_status`, `medication_taken_at`, `seconds_since_medication`, `medication_confirmed_at`, `medication_journal_entry_id`, `medication_name`, `medication_dose`. Elapsed seconds are calculated from each trial's `startedAt`; raw-sample CSV is unchanged.

**Backend integration pending:** the bundled backend currently accepts stimulation context as a string but does not model or persist `medicationTiming`. Server-side storage of these fields must be implemented before relying on uploads as a complete copy of local recordings.

**`MovementMetrics`**

| Field                     | Type   | Description                                                                |
| ------------------------- | ------ | -------------------------------------------------------------------------- |
| `cycleCount`              | int    | Completed movement cycles                                                  |
| `frequencyHz`             | double | Cycles per second                                                          |
| `meanAmplitude`           | double | Mean peak-to-peak amplitude                                                |
| `amplitudeDecrementSlope` | double | Amplitude slope over cycles (negative = fatiguing)                         |
| `rhythmCV`                | double | Coefficient of variation of cycle durations                                |
| `pauseCount`              | int    | Number of abnormal pauses / freezing episodes                              |
| `onsetLatencySec`         | double | Delay before movement starts                                               |
| `qualityIndex`            | double | 0–1 heuristic for UI trends; not a validated UPDRS score                   |

## Important Notes

- The app currently uploads **movement measurement data only**, not the recorded video.
- Measurement videos are saved to the device Photo Library with embedded metadata (task, side, context, patient ID, timestamp). If the backend needs the actual video files, that must be implemented as a separate upload step (e.g. from the device Photos, or by prompting the user to share).
- Data is also persisted locally as JSONL in `Documents/vcr/tasks/sessions.jsonl` and can be exported from the app as JSON or CSV.
- The `MovementModels.swift` file is the source of truth for the payload shape. Any changes to the backend contract should be reflected there.
