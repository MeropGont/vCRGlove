# Journal Review and Proposal

Reviewed 13 October 2026. This is a discussion proposal, not an implemented redesign or an approved study protocol. Only the varied Notes examples have been implemented in this change.

This document is the baseline review. Approved stages and current implementation progress are tracked in [Journal Redesign](JOURNAL_REDESIGN.md).

## Recommendation

Keep the calendar. Give the Journal one primary action: **Today's check-in**. Separate a brief daily reflection, optional event logging, a slightly fuller reflection on selected weekdays, and the licensed PDQ-8 assessment.

| Entry | Purpose | Suggested frequency | UX target to test |
| --- | --- | --- | --- |
| Quick check-in | Daily symptom impact and medication exceptions | Offered daily, preferably near the end of the day | 20-30 seconds |
| Fuller reflection | Important symptoms, their impact, and optional mood/sleep context | Two selected days, for example Monday and Thursday | About one minute including the quick check-in |
| PDQ-8 | Health-related quality of life over its specified recall period | Baseline and approximately every four weeks, subject to the study protocol | A short separate assessment |
| Medication, episode, note | A specific event or something the patient wishes to record | Whenever useful; not required to complete every day | One compact entry |

These frequencies and timings are proposed product targets, not validated requirements. Missing entries must remain missing, not be interpreted as symptom-free days or medication adherence.

## Current App Findings

| Area | Current behavior | Recommended correction |
| --- | --- | --- |
| Navigation | Home opens the daily log; another button opens the actual check-in. Four large entry cards compete for attention. | Open the check-in directly from the main action. Keep one secondary Add entry menu for events and notes. |
| Home summary | `JournalHomeView.lastEntry` selects any entry type for the Last check-in summary. | Filter to actual daily check-ins. Display other events in their own compact day summary. |
| Quick check-in | Mood and overall severity are required; a ten-symptom list follows. The reference period is not consistently explicit. | State Today explicitly, reduce the essential questions, and make mood and symptom details optional. |
| Inconsistent responses | Not present can coexist with selected symptoms. Episode severity also offers Not present. | Distinguish symptoms that occurred earlier from current symptoms, define each question's period, and prevent contradictory episode answers. |
| Medication | Usual/late/missed/extra and motor state are both required. Name and dose fields exist in the model but are not populated by this screen. | Make a real intake or exception simple to log. Add medication identity when needed. Do not infer individual doses from a daily summary. |
| Motor state | Dyskinesia is an exclusive alternative alongside ON and OFF. | If these details are collected, distinguish medication/mobility state from involuntary movements instead of forcing one combined choice. |
| Episodes | An episode-type enum includes OFF, dyskinesia and falls, but the symptom screen does not populate it. | Align the available choices with the intended episode data model and clinician-approved definitions. |
| PDQ-8 | Only an entry-type enum exists. There is no questionnaire, answer storage, scoring, or scheduling flow. | Treat this as not implemented. Obtain the necessary licensed material and permissions before adding it. |
| Time | A daily check-in uses the passed calendar date as its timestamp. Event screens combine the selected day with a chosen time. | Separate the day being described, the time an event occurred, and when the entry was saved or edited. Mark retrospective entries. |
| Saving | `JournalStore.add` appends to memory; disk errors are logged, but callers dismiss and a saved event is logged anyway. Writes are not atomic. | Confirm durable storage before success, retain the draft on failure, and use an atomic save. This is the first technical prerequisite. |
| Corrections | The store currently has no update/delete API; repeated check-ins append rather than edit a day's summary. | One editable daily check-in per day, with many separate event entries. Preserve a revision record if required by the protocol. |
| Localization | Some summaries display stored symptom strings and medication factor raw values directly. | Store stable codes, localize display labels, and preserve legacy decoding. |
| Calendar meaning | A journal marker means any journal entry. A stimulation marker can mean a logged start, not completion of the prescribed duration. | Give markers precise meanings; do not describe these as full daily completion or treatment adherence. |
| Scheduling | Journal notification weekdays already exist, defaulting to Monday/Wednesday/Friday. They do not select a different form for those days. | Reuse the reminder engine, but separate questionnaire schedules from notification preferences. |

These observations describe the current source, not failures seen in every patient session. No fixes to these behaviors have been made as part of this review.

## Suggested Questions

The wording below is a candidate custom diary, not a validated instrument or PDQ-8 wording. Review it with the study team and patients before adoption.

### Quick Check-In

1. **How much did your Parkinson's symptoms affect your usual activities today?**
   - Not at all / A little / Moderately / A lot / I could not do my usual activities.
   - Allow Not sure or Skip. Record these separately from the lowest impact answer.
2. **Was anything different with your Parkinson's medication today?**
   - As planned / Something changed / No medication planned today / Not sure.
   - Something changed reveals late dose, missed dose, extra dose, or another change. Offer an event time and medication selection when relevant.

Keep the response controls visible and text-labeled. Avoid sliders, emoji-only choices, and a long symptom checklist on the essential path. This medication question is a patient-reported daily summary, not proof of adherence.

After **Save check-in**, show **Saved** and a small **Add details** action. Optional details include which symptoms mattered, mood, a symptom episode, a medication event, or a note. Event logging must also be available without doing the daily check-in first.

Functional impact is not identical to the existing severity measure. If adopted, it needs a new stored field and question version; do not relabel or recode old severity values as impact.

### Fuller Reflection

On selected days, expand the same flow rather than opening another disconnected diary:

- Which symptoms bothered you most today? Use a short personalized list, with More available.
- How troublesome was the selected symptom? Ask about the same day and use clear labels.
- Optional mood, sleep, and free-text context. Do not ask everything merely because fields are available.

Reuse already-entered answers. Offer Continue, Later, or Skip. A saved quick check-in remains saved even if the fuller reflection is unfinished. The final question set should follow the study's actual outcomes, not an arbitrary desire for more data.

### Medication and Symptom Events

Daily reflection and real-time events serve different purposes. For medication-response analyses, an explicit intake time and identity are more useful than a general end-of-day answer. Preserve the existing movement task's patient-confirmed medication link; avoid asking the same information again or duplicating an intake automatically.

A symptom episode should identify what happened and when. Additional severity, duration, mobility state, and notes should appear only when useful for that episode. Allow corrections. Do not estimate OFF-time duration from a single daily check-in.

### PDQ-8

PDQ-8 concerns health-related quality of life and refers to the preceding month. It should not be used as a Monday/Thursday daily symptom form. Baseline plus approximately four-weekly follow-ups is the proposed starting point; the research team must confirm the actual assessment schedule. [Oxford PDQ information](https://innovation.ox.ac.uk/licence-details/parkinsons-disease-questionnaire-pdq-39-and-pdq-8), [official PDQ-8 sample](https://innovation.ox.ac.uk/sites/default/files/2026-04/Final_PDQ-8_English_UK-Sample-copy-do-not-use_0.pdf).

Before implementation, obtain authorized English/German versions, the scoring/manual instructions, and confirmation of the licence and electronic-administration requirements. Do not ship the sample copy, rewrite the items, or translate them ourselves. Use progress, resumable drafts and the licensed response format; handle missing answers according to the manual. [Oxford licensing portal](https://process.innovation.ox.ac.uk/clinical).

## Screen Design

### Journal Home

- Keep the current month calendar prominent.
- One primary action: **Today's check-in**, changing to **Edit today's check-in** once saved.
- One secondary **Add entry** menu: Medication, Symptom episode, Note. Include familiar icons and labels.
- A compact selected-day summary: check-in saved/not entered, recorded events, and any planned assessment.
- Put the day's timeline behind **View entries**, rather than stacking it under four large forms.

Tapping a calendar date shows that day's summary and the same actions. Historical dates say **Check-in for [date]**, not Today. Real-time events remain time-stamped independently.

### Calendar and Schedule

Do not use one color to mean both what is planned and what has happened:

- Keep existing recorded-data markers and their legend.
- Use a small outlined marker for planned fuller-reflection days, with text such as Fuller reflection planned in the selected-day summary.
- Use a distinct shape and label for a due PDQ-8 assessment; mark it completed only when the assessment is saved.
- Pair all color with shape/text and accessible labels. Missing days stay neutral, not red failures.
- Do not add a new full-day background color for every entry type. If desired, a very subtle schedule tint can be tested, but it must not obscure selected dates or existing data markers.

### Settings: Journal Routine

Offer reminder time, notification on/off, and selected fuller-reflection weekdays where the study permits patient choice. Show the PDQ-8 assessment schedule separately. Keep protocol-mandated assessment intervals distinct from optional reminders. Support snooze/skip and avoid stacked catch-up prompts.

## Evidence and Limits

- **StrivePD:** Its official flow separates once-daily whole-day reflection from medication/activity events, and lets users review and edit a check-in. This is a useful UX reference, not evidence that its exact questions or calendar colors are best for our study. [Daily Check-In guide](https://help.strive.group/hc/en-us/articles/24398292000653-Daily-Check-In).
- **Heijmans et al., 2019, npj Parkinson's Disease:** Twenty patients used seven daily prompts for two weeks; questionnaire completion averaged 79.1%. The authors cautioned that longer use could be too intensive. This supports testing burden, not a proven optimal Monday/Thursday schedule. [Feasibility study](https://www.nature.com/articles/s41531-019-0093-5).
- **Habets et al., 2020, JMIR mHealth and uHealth:** A 20-person EMA study collected affect, context, symptoms and performance. It supports considering functional/contextual experience alongside symptom intensity, but individual wearing-off validation remained limited. Our two-question retrospective diary would be a different, unvalidated measure. [EMA study](https://mhealth.jmir.org/2020/5/e15628/).
- **MyParkinson's, 2025, Frontiers in Neurology:** A short randomized crossover comparison analyzed 20 participants, with 65% preferring the digital diary. It supports accessible digital logging but cannot establish long-term completion or the ideal question frequency. [Digital versus paper diary study](https://www.frontiersin.org/journals/neurology/articles/10.3389/fneur.2025.1522721/full).

## Data Rules and Implementation Order

1. **Saving foundation:** Durable atomic saves, visible failures, edit support, correct check-in filtering, explicit day/event/save timestamps, and backward-compatible decoding. Test failed writes and interrupted navigation.
2. **Quick-flow prototype:** Calendar-first home, direct short check-in, optional expansion, event menu, precise EN/DE labels, VoiceOver and large-text layouts. No changes to stimulation or movement recording.
3. **Scheduling:** Separate planned/done/skipped/draft/missing states, configurable permitted weekdays, and reuse existing notifications. Store schedule effective dates so later preference changes do not rewrite historical obligations.
4. **PDQ-8:** Implement only after licence/materials, electronic requirements and protocol approval. Validate scoring and missing-response handling against the manual.
5. **Pilot:** Review with clinicians and approximately 5-8 patients/caregivers, then assess use over several weeks. Measure comprehension, time/taps, abandoned forms, corrections and skipped questions, not just the number of completed days.

Never automatically turn missing data into zero, infer medication adherence without a prescribed schedule, combine daily/monthly measures into one score, or interpret a custom check-in as a validated clinical score. Any new field needs explicit recall period, stable response codes, questionnaire version, and appropriate export metadata.

## Decisions Before App Changes

1. Does the study need a daily end-of-day summary, precisely time-stamped medication/symptom events, or both? Recommended default: a very brief offered daily summary plus optional events, with Monday/Thursday fuller reflections.
2. Does ICNS already hold a PDQ-8 licence and authorized English/German material covering this electronic use? If not, obtain these before implementing the questionnaire.
3. Confirm the required study outcomes and permitted reminder/assessment schedule with the study team. The proposed questions and frequencies should remain adjustable until that review.
