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

Triggered automatically every time a movement task session is saved. Upload happens in the background; the patient does not need to interact.

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
| `stimulationContext` | string        | One of `baseline`, `preStim`, `postStim`, `unspecified`                     |
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
