# Activity Foundation Checks

Stages 1, 2 and 3. Stimulation scheduling is unchanged.

Focused suite: `DailyActivitySummaryTests`.

23 October 2026: all 11 focused tests passed in the iOS simulator; app build
and `git diff --check` passed. No UI/hardware verification is claimed for this stage.

- Empty history and ordinary journal entries do not create an active day.
- Today remains open; gaps end the current streak but preserve totals/best.
- Mixed activities, duplicate UUIDs and repeated per-glove starts earn one day.
- Individual take dates and explicit participant scope govern movement days.
- Low/no movement scores and tracking loss do not penalize real attempts.
- Empty stops, synthetic sources, invalid durations and future data are excluded.
- Edits/backfilled check-ins use historical entry dates, not edit dates.
- DST spring/autumn, year boundaries, week starts and time zones are deterministic.
- Historical log parsing ignores text messages, finger checks and malformed lines.
- The asynchronous log reader sees pending appends and handles missing files.

## Later UI/Device Checks

- Do not show zero streaks while data are loading or unreadable.
- Check seven-month history, reassigned-phone ownership and timezone policy.
- No completed-treatment/dose label without reliable evidence.
- English/German, large text, VoiceOver, midnight refresh and saved-data changes.
- Confirm existing recording, journal editing and stimulation controls unchanged.

## Stage 2 Software Coverage

Verified 23 October 2026; final screenshots reviewed 26 October after resuming:
all 15 focused activity tests passed. The English/German calendar UI test passed,
followed by a successful extra-large German check of the final shortened labels
and fixed-size icons. Calendar and selected-day screenshots were inspected.
`git diff --check` is clean. These are simulator/software checks, not physical
iPhone, VoiceOver or real midnight-transition validation.

- Mixed-owner histories withhold unassigned journal/events; approved trial links
  are display-only; confirmed reassignment bounds device-only history.
- Event-read failure cannot become a zero streak. Missing, unreadable and
  malformed movement histories have distinct loading outcomes.
- `testActivityCalendarEnglishGermanLargeText`: isolated three-day fixture,
  current date selection/activity, no old legend, day-specific movement/vCR
  navigation, historical selection and disabled future check-in.
- Inspect the calendar and day-summary screenshots in English and extra-large
  German. Confirm readable date cells, checkmarks and selected outline.

Live iPhone midnight/timezone changes, VoiceOver and long-history/reassigned-phone
checks remain manual verification, not simulator assertions.

## Stage 3: Milestones

26 October 2026: all 34 tests passed across `RoutineMilestoneTests`,
`DailyActivitySummaryTests` and `TrialRecorderTests`.

- Thresholds: 3/7 consecutive days and 30 total active days.
- Highest unseen milestone only; lower eligible milestones are absorbed.
- Persistence after relaunch, independent study IDs, corrupt-ledger fail-quiet.
- Disabled/blocked display does not consume pending milestones.
- Overlapping recording gates and a recorder's real start/completion lifecycle.

`testRoutineMilestonesEnglishGerman` passed in the simulator, including
extra-large German text: toggle off/on, no acknowledgement while disabled,
three-day acknowledgement, manual dismissal and no replay after relaunch.
English/German calendar and General Settings screenshots were inspected;
the acknowledgement and dismiss button fit without overlap. The initial
test exposed inherited container accessibility identifiers; removing the
container identifier fixed the individual text/button queries. Final result:
`/tmp/vcr-milestones-ui-final-20261026.xcresult`.

Pending physical checks: the user currently has no iPhone available. Review
calendar/milestone appearance, General Settings toggle, VoiceOver readability,
and navigation during real stimulation/recording. Software gate tests are not
hardware validation. No animation is used, including with Reduce Motion enabled.

## Encouraging Reminder Copy

26 October 2026: app build and `EncouragingReminderCopyTests` passed, with
both English/German parameter cases. Catalog JSON and `git diff --check` passed.

- Bundled English/German invitation wording verified by `EncouragingReminderCopyTests`.
- On the iPhone, enable an existing reminder and verify its next delivered title
  and body follow the in-app language, including after a language change.
- Confirm saved days/times and disabled reminder choices are retained. Quiet hours
  now also shift vCR reminders; no extra milestone or missed-day alerts should appear.
- Delivery timing, iOS permission behaviour and lock-screen presentation remain
  physical-device checks; localisation tests do not establish notification delivery.

### Message Variation and Comfort Controls

26 October 2026: final build and all 24 tests passed across reminder-copy,
milestone and activity-history suites. Catalog JSON and `git diff --check` passed.
The rotation test caught and verified a fix for within-day ordinal changes:
selection now uses the start of the local calendar day.

- All 36 messages are distinct within their type, translated in English/German
  and at most 140 characters; twelve consecutive calendar days cover each set.
- Rotation is stable within a local day and tested across the autumn clock change.
- Request factory produces at most 21 distinct repeating weekday IDs; migration
  includes removal of `vcr.daily`. Empty/invalid weekday choices add no requests.
- Quiet-hour adjustment tested for overnight/daytime windows and when disabled,
  including vCR. Sound-off/on and the shared notification group are verified.
- On the iPhone, verify toggling Reminder sounds, enabled weekdays and app language
  replaces pending reminders without duplicates; observe the next actual alert.
- After a break, review the welcoming Journal heading and retained total/best run.
  This new copy/control layout has not yet had physical-device or VoiceOver review.
- Without app use, weekday reminders keep repeating their last scheduled text;
  foregrounding refreshes the next occurrences' varied messages. Verify this
  lifecycle and lock-screen grouping on-device; unit tests cover request contents,
  not iOS delivery or permission handling.
