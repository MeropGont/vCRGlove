# Journal Redesign

Approved direction: 13 October 2026. Implement one stage at a time and obtain approval before starting the next major stage.

## Stages

| Stage | Scope | Status |
| --- | --- | --- |
| 1. Saving foundation | Atomic writes, visible failures, safe check-in editing, backward compatibility, accurate save times | Complete. Awaiting patient-device review |
| 2. Journal experience | Journal as second tab; calendar-first dashboard; two-question check-in and direct event links | Complete. Awaiting patient-device review |
| 3. Personal routine | User-selected reflection weekdays, calendar schedule markers, reminder time and notifications | Not started |
| 4. Monthly PDQ-8 | Configurable assessment date, authorized questionnaire versions, resumable answers and validated scoring | Needs licensed English/German material and electronic-use approval |
| 5. Pilot validation | Patient comprehension, accessibility, notification routing, missing data and export checks | Not started |

## Agreed Experience

- Tab order: vCR, Journal, Movement, Settings.
- Keep the calendar central and make the selected day's check-in one clear action.
- Quick questions, in order: feeling today and impact of Parkinson's symptoms on usual activities.
- Reuse the existing mood scale but give every response a readable and accessible label.
- Store activity impact as a new measure; never rename legacy symptom severity or convert it to an impact score.
- Keep medication, symptom episodes and notes in their own forms, with direct dashboard links and check-in shortcuts.
- Saved medication and symptom episodes are editable through View entries. Corrections preserve their identity, creation time, medication name/dose and unrelated metadata.
- Patients choose fuller-reflection weekdays; planned markers remain distinct from saved-entry markers.
- Offer monthly PDQ-8 separately, with its date configurable in Settings. Confirm the study schedule before activation.
- Do not interpret missing answers as normal health or medication adherence.

## Stage 1 Rules

- Keep `Documents/vcr/journal/journal_entries.json` and the existing JSON date representation.
- Publish saved entries only after an atomic write succeeds; on failure, keep the form and its answers visible.
- Refuse to overwrite an unreadable file or a file with duplicate entry IDs.
- Editing a daily check-in keeps its ID and other fields. Existing duplicate check-ins from older builds are retained; the latest one is editable.
- Preserve unrecognized stored metadata. New optional `createdAt` and `updatedAt` fields distinguish save/edit time from the existing day/event `date`.
- Leave unknown historical save times unknown. No old severity, medication, or symptom answers are recoded.
- The last-check-in summary includes only daily check-ins, not medication, notes, or stimulation events.
- Test files are isolated from ordinary journal files. No changes to stimulation control, movement recording, or notification schedules in this stage.

## Stage 1 Validation

- Full unit-test suite: 122 tests passed, including journal persistence and existing movement regressions.
- All eight journal persistence tests passed again after the final loading safeguard.
- Four targeted UI tests passed across the runs: editable/reopened check-ins, failed-save answers, retained note drafts and existing bilingual note examples. English and German were exercised, including extra-large German text.
- Reviewed simulator screenshots of reopened entries and localized save errors. No questionnaire or main Journal layout changes in this stage.
- On the iPhone, check that a saved check-in can be reopened, edited and retained after closing/reopening the app.

## Stage 2 Rules

- The home page has one selected-day summary, a primary check-in action, direct Medication, Symptom episode and Notes links, and a compact View entries link. Counts describe saved events, not adherence. Past days can be completed; future-day logging is disabled.
- The check-in asks only about mood and activity impact. One answer is enough to save. Medication and Log symptoms shortcuts open the existing event forms after saving any filled check-in answers. An unanswered shortcut creates no check-in; a failed save blocks navigation and retains the draft.
- New two-question records use `checkInVersion = 3`; existing records retain their version. Missing answers and uncertainty remain distinct. The activity-impact categories are diary responses, not a validated scale or a clinical score.
- The two-question editor changes only mood and activity impact. Legacy daily medication answers, symptom severity, symptoms, notes and unknown metadata remain intact, without inventing intake events. Full entry history retains those older answers; the dashboard's short check-in summary shows only the two current questions.
- Medication choices start unselected. A non-usual dose reveals a note field before the motor-state question. Existing or typed notes stay visible when switching answers; usual doses can also include a note through Add note.
- Medication and symptom corrections update the original record. They preserve the ID, creation time, medication name/dose, unrelated fields and exact event timestamp when the time is unchanged. Old records with missing answers can be corrected without inventing those answers.
- Failed writes leave the editor and draft visible. A check-in's last-save timestamp is shown only when known; old unknown save times are not presented as midnight.
- Normal and accessibility text sizes use scrollable layouts with reachable save actions. Reminder schedules, fuller-reflection weekdays and PDQ-8 are not implemented in this stage.
- Activity impact uses one vertical scale in increasing order, with Not sure separate. Mood and impact have gentle background shades, text labels and explicit selection indicators. Colour is not the only selection cue.
- Skip question is no longer offered. Unanswered questions stay missing; uncertainty remains an explicit answer. Hidden historical answers are preserved. No raw enum values or stored mood numbers are changed.

## Stage 2 Validation

- Full unit-test suite: 135 tests passed. Four new tests cover the two-question editor, hidden legacy answers, failed-save recovery and unknown versions; earlier event-editing and movement regressions remain covered.
- Six targeted simulator UI flows passed across focused runs in English/German, including extra-large German text. Coverage includes safe shortcuts, no empty check-in creation, saved/reopened answers and notes, medication/symptom edits, failed-save navigation blocking and historical/future dates.
- Reviewed screenshots of compact questions, ordered activity choices, the dashboard and conditional medication notes. The UI-test scroll helper now excludes the full symptom instruction footer so large-text tests tap visible controls rather than the overlay.
- Earlier Stage 2 checks covered note examples, calendar legends and movement context/navigation, including reachable Skip this measurement actions on all six task pages.
- Existing symptom-grid labels wrap heavily at the largest text setting. Review their readability on the patient device as part of accessibility QA; this refinement does not redesign the symptom form.
- Patient-device review: fill a check-in, open Medication or Log symptoms, then return and save. Confirm answers survive relaunch and each event appears once. Try an unanswered shortcut, direct dashboard links and conditional medication notes. Use View entries to edit saved medication/symptoms. Check a past date and confirm future-day entry is disabled.
- Stage 3 remains unstarted. Obtain approval before implementing reflection weekdays or notifications.

## PDQ-8 Prerequisite

ICNS licensing and authorized English/German materials are not confirmed (13 October 2026). Obtain the questionnaire, scoring rules and electronic-use approval before implementing stage 4. No PDQ-8 items have been copied into the app.

## References

The [original journal review](JOURNAL_REVIEW_PROPOSAL.md) describes the pre-redesign code and evidence.

The [Apple Health feasibility review](APPLE_HEALTH_RESEARCH.md) covers medication and activity imports, participant permissions and managed-phone testing before deciding on a medication schedule.

[StrivePD daily check-in](https://help.strive.group/hc/en-us/articles/24398292000653-Daily-Check-In) is a design reference for separating a daily reflection from event logging and allowing corrections. We are not copying its questionnaire or treating our diary as a validated instrument.

[Oxford PDQ information](https://innovation.ox.ac.uk/licence-details/parkinsons-disease-questionnaire-pdq-39-and-pdq-8) and the [licensing portal](https://process.innovation.ox.ac.uk/clinical/) provide the authoritative route to English/German questionnaires and electronic-use requirements. Public samples are not material to ship in the app.
