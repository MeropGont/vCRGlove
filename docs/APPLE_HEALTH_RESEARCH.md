# Apple Health: Medication and Activity

Reviewed 14 October 2026. Discussion only: no HealthKit integration, scheduling or data transfer has been added.

## Recommendation

Try a small feasibility pilot before replacing in-app medication logging. A hybrid could let patients log doses in Apple Health while vCRGlove imports authorized records; retain manual logging for patients who do not use Health. Choose one logging source to avoid duplicate entry.

## What Is Possible

Health already provides medication schedules, reminders and taken/skipped logging, so duplicating the whole medication manager is not our first choice. Some medication features vary by region. [Apple's medication guide](https://support.apple.com/en-my/guide/iphone/iph811670c81/27/ios/27).

Apple's Medications API can read authorized medications and dose events, including taken/skipped status, quantities and scheduled versus actual times. Authorization is per medication. Records may be backdated, edited or deleted, so an importer must reconcile changes rather than append blindly. This is useful for medication context around movement tests, not proof that a dose was swallowed. [Apple's API walkthrough](https://developer.apple.com/videos/play/wwdc2025/321/).

The installed official SDK declares these medication types available from iOS 26. The app supports iOS 17, so integration would need an availability guard and a manual fallback. The relevant header is `HealthKit.framework/Headers/HKMedicationDoseEvent.h` in the Xcode iPhoneOS SDK.

HealthKit also supports reading activity data such as steps and recorded workouts. Availability depends on what the phone, Watch or other apps actually collect; a phone alone does not guarantee a complete sport history. [HealthKit overview](https://developer.apple.com/documentation/healthkit).

## Permissions and Research

HealthKit requires the person's explicit authorization for the data requested by our app. Permission can be withdrawn. An empty query must not be treated as a missed dose: access may be denied or data absent. Research sharing needs express permission and a clear privacy policy. [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy), [authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data).

Apple requires participant consent explaining the study, data handling/sharing and withdrawal, plus independent ethics-review approval for human-subject research. Plan any ICNS export with UKE's data-protection and study teams; do not build a research database in iCloud. [App Review, section 5.1.3](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research).

## Managed Research Phones

Apple lists Health data sharing between devices using the same Managed Apple Account as unavailable. This does not establish whether our proposed local medication workflow works on every managed configuration; test it on the actual study phone. [Managed Apple Account service access](https://support.apple.com/en-mide/guide/business/axm171b3ee95/web).

Device administration and HealthKit authorization are separate. Our conclusion from the permission model is that managing phones does not give vCRGlove automatic access to their health records. Use a participant-specific study ID and an explicitly approved export, not a shared Apple account as a research collection mechanism.

## Pilot Checklist

1. On one representative managed phone, check Health medication setup, reminders and logging; check the planned Watch configuration separately.
2. In an isolated prototype, request read access to one test medication and one minimal activity type. Confirm declining access leaves manual logging usable.
3. Verify taken versus scheduled times, edits/deletions, duplicate prevention and source labels. Import only data covered by the study consent.
4. Verify an approved export under the study ID and decide whether the extra app switching is worthwhile for patients before changing the production workflow.
