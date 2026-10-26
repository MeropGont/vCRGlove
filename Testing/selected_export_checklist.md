# Bundled and Selected Data Exports

Implemented 23 October 2026. Use disposable test records, not participant data.

## Software Checks

- [x] Snapshot all seven groups into one ZIP, with no movie copies or persistent CSV exports.
- [x] Match selected session/trial IDs across JSON, metrics, samples and angles.
- [x] Preserve unknown JSON fields, stored metrics and source files.
- [x] Date range includes start, excludes end; complete matching sessions stay together.
- [x] Manual selection limits journal/events to selected local days, excluding intervening days.
- [x] Handle event `ts`, Watch `ts_phone`, Foundation journal dates and empty angle channels.
- [x] Fail closed for stale session selection or unreadable scoped records.
- [x] Preserve original full-device export behavior and failure cleanup.
- [x] English and large-text German file selection, session selection and native share sheet.

Evidence: 32 focused tests passed (28 Swift Testing cases and 4 archive XCTest
cases), including settings-only exports and an empty device. Bilingual simulator
sharing/cancellation passed. An extracted selected-session ZIP independently
passed all ten file hashes and ID/date-range checks; movies, credentials and
out-of-range pending uploader payloads were absent. These are software checks,
not physical transfer/clinical validation.

Data-browser follow-up: English and extra-large German UI checks passed for
JSON, metrics, raw-sample and angle text previews, app/share chooser dismissal,
and removal of Last export. The summary/files/sharing order was visually checked.

## Physical iPhone Checks (Pending)

- [ ] Share all non-video data from Data; unzip externally and check manifest hashes/counts.
- [ ] Share one session and a custom fortnight; compare exported IDs/timestamps across files.
- [ ] Verify custom dates and calendar-day scope across local midnight/DST.
- [ ] Cancel and retry sharing. Original records/videos remain available.
- [ ] Native AirDrop/Files destination receives the full ZIP before any source deletion.
- [ ] Active/paused/starting stimulation blocks export preparation.
- [ ] Large multi-month history remains responsive; check free-space/error handling.
- [ ] Data summary is first, files/videos share one block, and Sharing is last.
- [ ] JSON, metrics, samples and angles open in-app; the preview's app chooser offers installed compatible apps.
- [ ] No Last export section returns after opening a file. Existing exports remain accessible in Files.

No automatic upload, institutional receipt or encrypted-archive guarantee is implemented.
