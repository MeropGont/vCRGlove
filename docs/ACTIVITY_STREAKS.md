# Activity Calendar and Streaks

## Stage 1: Implemented Foundation (23 October 2026)

`DailyActivityCalculator` derives daily summaries, current/longest streaks,
total active days and current-calendar-week participation from snapshots. It
does not write records, persist reward counters or change the calendar UI.
Recalculation therefore includes historical records, edits and deletions without
stale counters. Video deletion does not remove the underlying measurement.

An active day has a saved daily check-in, a genuine saved hardware movement
attempt, or a structured `stimulation_started` event. Ordinary notes, medication
and symptom entries remain visible in journal counts but do not qualify alone.
Repeated entries/takes do not earn multiple days. Movement UUIDs are deduplicated;
distinct retakes can increase attempt counts, not task/hand coverage or streaks.
Synthetic trials, empty stops and future records are excluded. Actual positive
recording duration qualifies regardless of tracking or motor scores; legacy
takes without duration need a positive span of finite signal timestamps. This
is participation evidence, not a clinical validity threshold.

Stimulation journal entries are start requests (possibly before finger checks).
They remain a separate **logged** flag, not evidence of actual start or completion.
Only the structured start event supplies the **recorded start** flag. Per-glove
starts/resumes do not become a session count. Neither prescribed duration nor
free-text completion messages prove delivered treatment. Historical completed
sessions, partial delivered duration and treatment adherence are deliberately
not inferred by this stage. Older journal-only vCR days may remain unverified.

Days use the activity's date: journal entry date, individual trial start, or
event timestamp, not session-container date or edit date. Backfilled entries
count on the selected historical date, not the day of entry. A cross-midnight
recording currently belongs to its start day; no duration is spread into another
day. Today can continue yesterday's run until midnight. After a missed full day,
the current run ends while totals and longest streak remain. Calendar date
arithmetic handles daylight saving, month/year boundaries and supplied week
starts; no 24-hour-second arithmetic is used.

Callers must supply `now`, a calendar/time zone and explicit movement participant
IDs (including only approved aliases). Journal/event records are device-scoped
and lack reliable historical participant ownership: callers must not combine a
reassigned phone's owners. Existing records lack a fixed activity time zone;
changing the supplied time zone re-buckets their instants. No travel-specific
timezone or study-break policy is introduced here.

`EventStore.recordedStimulationStartDates()` reads after pending log appends on
its serial utility queue. It accepts fractional/plain ISO timestamps, ignores
malformed/unrelated lines, and propagates file-read errors rather than presenting
them as an empty history. A missing log is empty. Source bytes are not changed.
Future UI integration must wait for loaded journal/tasks/events and handle load
failures rather than briefly displaying an incorrect zero streak.

## Stage 2: Calendar and Daily Records

The Journal now shows a compact routine summary (current run and active days
this week), followed by the month calendar. Active days have one soft teal tint
and checkmark; selection is a separate outline. Inactive days stay neutral.
The overlapping vCR/journal/movement colour legend is removed. Calendar controls
have capped Dynamic Type to keep the seven-column grid legible and stable;
VoiceOver reads full dates, activity and selection. Other Journal content keeps
the user's selected text size.

Selected-day check-in status/editing remains available. vCR and Movement rows
open date-specific records. vCR distinguishes a structured start from an
unverified journal start request; it does not claim a full treatment session.
Movement details use individual trial dates and scoped identities, not just the
parent session date. Per-glove stimulation starts within one minute are grouped
for display only, never interpreted as a completed session count.

The activity summary waits for movement loading and log reads. Read failures or
undecodable session lines withhold the streak instead of showing a false zero.
Event-read failures offer retry; blocked store loads ask for restart rather than
offering an ineffective retry. Existing session decoding/export behavior is
otherwise unchanged. Saved/edited journal entries, task snapshots, stimulation
starts and metadata changes refresh the summary. Foreground entry, significant
clock changes and a lightweight midnight check refresh date/week boundaries.
Cancelled refreshes cannot publish an older snapshot.

Only the current study ID's trials and explicitly approved display-only test
links are included. Known ID reassignments in metadata logs bound device-only
journal/vCR activity to the current assignment. If mixed owners exist without a
reliable assignment boundary, device-only activity is withheld from streaks;
the information sheet explains this limitation. Original records are unchanged.
This cannot reconstruct ownership when assignment logs and other evidence have
been removed; research-device reassignment still needs a deliberate data handover.

The information button explains participation versus treatment and retains total
active days/longest run. It does not add badges, scoring, confetti or incentives.

Stage 2 software verification passed on 23 October 2026: 15 focused activity tests,
English/German calendar navigation and a final extra-large German interface
check. Screenshots were reviewed on resuming 26 October. Physical iPhone review,
VoiceOver and live date/timezone transitions remain pending; see the checklist.

## Stage 3: Gentle Milestones (26 October 2026)

The routine summary briefly acknowledges 3 and 7 consecutive active days, then
30 total active days. These use the same participation rules as the calendar,
not treatment completion or movement scores. Earned milestones also appear in
the routine information sheet. No extra notifications, rankings, sounds,
haptics or moving effects are added; the static presentation respects Reduce
Motion without requiring an animation override.

General Settings has a milestone-acknowledgement toggle, enabled by default.
Acknowledgements appear only while the Journal is visible and the app is active,
with no stimulation session (including paused stimulation/finger checks) and no
movement recording or analysis in progress. Navigation changes cancel pending
display. The message replaces the weekly-count line temporarily, with a dismiss
button; the current streak remains visible. It clears after eight seconds, or
twenty seconds with VoiceOver running. Milestones remain available in the
information sheet after dismissal.

A local preference ledger remembers acknowledgements per study ID across app
relaunches. It records eligible milestones before display and shows only the
highest unseen achievement, avoiding a sequence of historical messages. A
disabled or unsafe display does not consume pending milestones. Corrupt ledger
data fail quietly rather than replaying messages. The ledger does not alter
research records and is not part of exported study data; the current toggle
preference is included in settings exports. This is per installation, not an
account-synchronised award system.

Focused software validation: 34 tests passed across milestone, activity-history
and recorder suites. English and extra-large German simulator checks passed for
the toggle, acknowledgement, dismissal and persistence; screenshots were
inspected. Remaining physical checks are tracked in the activity checklist.

## Not Implemented

- Completion/duration indicators need reliable structured evidence first; do
  not label a start as a completed 2-hour/4-hour session.
- No clinical schedule is inferred from reminder weekdays. No streak freezes,
  break allowances, notifications or changes to stimulation are introduced.

## Encouraging Existing Reminders (26 October 2026)

Existing vCR, Journal and movement reminders now use gentle invitation wording,
without missed-day warnings, streak-loss language, performance targets or
claims about health improvement. Repeating reminders deliberately contain no
dynamic streak count or completion claim that could become stale. Their enabled
settings and chosen weekdays/times remain user-controlled; no additional
milestone notification is scheduled.

Notification titles and bodies use the in-app English/German language. Existing
pending reminders are refreshed at launch, foreground entry and when the app
language changes, using the saved schedule. Already delivered notifications are
not rewritten.

### Varied Messages and Comfort Controls

There are 12 messages for each reminder type (36 English messages and their
German translations), without performance demands, guilt or promises of health
improvement. A calendar-day rotation chooses the next occurrence's message,
stable within that day and refreshed during app use. Seven repeating weekday
slots support different messages across the week; they do not expire if the app
is not opened. Without further app use, each weekday keeps its last scheduled
message rather than generating new text in the background. Counts/completion
claims are deliberately absent because repeating messages cannot keep them
reliably current.

At most 21 reminder requests are scheduled, one per enabled type/weekday.
Stable IDs replace pending requests; disabled weekday/type requests and the old
`vcr.daily` request are removed. There are no extra milestone alerts. Notifications
share an iOS grouping identifier to reduce lock-screen clutter; iOS controls the
actual presentation. Quiet hours now apply to all three reminder types, including
vCR, shifting the reminder (not treatment) to the quiet-hours end. The existing
sound behaviour is the default, with a new Reminder sounds switch for silent
alerts; that preference is included in settings exports.

After a break, the zero-current-streak heading welcomes the user back. Historical
active days and longest run remain intact. There are no lost-day warnings,
leaderboards or rewards for extra treatment. Reminders are not automatically
suppressed after a same-day activity; that would need a separate reliable
rescheduling/delivery design rather than assumptions about background execution.

Verification and pending checks: [activity checklist](../Testing/activity_streak_checklist.md).
