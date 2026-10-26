# Task Video Storage Choice

Implemented 23 October 2026. One participant control in Settings > Data;
no duplicate control in Study team or study-information pages.

## Software Checks

- Default on; explicit off persists across defaults reload and app relaunch.
- Each take snapshots its choice. Changes affect the next take, not an active one.
- Disabled drafts have no URL or failure message and discard unexpected movies.
- Measurement-only saves survive store reload and do not queue video processing.
- Current-settings export allowlist includes the preference.
- English and extra-large German Data control, measurement/angle saving with
  video off, zero-video count and re-enable: simulator UI check.
- Existing video save/delete tests remain regression coverage.

Record actual test outcomes separately; simulator fixtures do not prove physical
camera behaviour or privacy performance.

Verified 23 October: all 22 `MovementVideoStorageTests` passed on rerun;
`testVideoStorageChoicePersistsAndKeepsMeasurementsEnglishGerman` passed after
correcting switch targeting and bounded scrolling in the test. Earlier UI runs
failed/interrupted on test navigation; no additional app changes were needed.
One older asynchronous video test failed on the first unit run, then passed on
rerun; background-worker behaviour was not changed in this task.

## iPhone Checks Still Required

- Turn off, record tapping and hand opening/closing in both guided/single-task
  flows. Confirm live camera, rhythm, angles and trends remain available.
- Confirm no new video/preparing/error row; relaunch and export measurements.
- Confirm an existing video remains playable/exportable/deletable.
- Re-enable, record and confirm masked video appears after preparation.
- Toggle while an older video is preparing: accepted video should finish;
  subsequent takes use the new choice. Check Watch and calibration unchanged.
