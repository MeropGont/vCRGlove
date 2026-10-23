# Study Information in Settings

Implementation dated 15 October 2026, following the user's content approval and contact/video clarifications. This is an information-only feature, not a consent or permissions workflow.

23 October: the non-legal Devices/app video explanation now describes the approved
hand-focused crop and measurement-only fallback when no reliable crop is available,
in English and German. The German legal notice and its approved translation are unchanged.

## Patient Pages

Settings > Information about the study (Informationen zur Studie) opens six topics: the study, participation, devices/app, safety and voluntary participation, data protection, and finally Contact. Devices and app also contains the factual app-data/video explanation. Native scrolling pages support the app's English/German language choice and text-size setting.

The primary Settings order is Profile, General, Instructions, vCR Settings, Reminders, Data, and Information about the study. General contains language and text size. The former Privacy & Data page had no controls; its menu entry was removed and all factual text retained. The separate troubleshooting entry remains available. A discreet staff entry below it unlocks researcher controls on the shared vCR tab and staff logs; see the [development guide](DEVELOPMENT_GUIDE.md#shared-vcr-and-researcher-controls). This does not change the study-information or legal text.

General copy is neutral: everyday usability, the agreed individual plan, a home phase of up to six months, device use, possible discomfort and voluntary withdrawal. It does not promise benefit, coach outcomes or assign clinical meaning to movement values. This overview supplements study documents and discussion with the study team; it does not replace informed consent.

Names appear only in the legal privacy notice. Contact opens a dedicated contact-only page with the existing phone/email and institutional address: UKE, ICNS, Building W36, Martinistraße 52, 20246 Hamburg. There is no troubleshooting picker, problem-related introduction or Still Need Help? heading on this page. It shares the contact rows with the unchanged troubleshooting screen to prevent contact details drifting apart. Renaming the main Settings Need Help? entry remains a separate task.

## Legal Source and Translation

- Source: `Formulare/Einwilligung_Info_Blatt_vCR_V02_20260414.docx`, Version 02 dated 14 April 2026. It was selected by the newest date in matching Word filenames, not modification time. The synopsis/protocol informed the shorter general pages; they are not the legal-text authority.
- Source SHA-256: `f91db985b35cf7b07b98c64cc73b970baaab3a0bcbe7e74be3d1cd9efb104b51`.
- German privacy headings, paragraphs, rights, contacts, definitions and closing statement are copied from Word. The only content omission is the whole lab motor-examination video paragraph, explicitly requested by the user. The contact table is stacked into two readable blocks and the split definition is reflowed without changing its words. Existing source wording, including imprecise terminology or dates, is not silently corrected.
- At the user's request, every page has a paired English translation. The privacy translation aims to retain the source meaning, legal references, exceptions and contact details. It is not a certified translation or evidence of institutional legal approval. The study team/data-protection office should review both the adaptation and English wording before patient deployment.
- All patient-facing copy lives in `vCRGlove/Localizable.xcstrings`. `StudyInformationTopic` in `SettingsView.swift` defines the section order. No external document download is needed at runtime.

Local comparison materials and source paths remain in Git-ignored `QA/study_information_review/`. Earlier PDF-based review drafts there are superseded by this Word-based implementation. No PDF-copy or internal review commentary appears in the app.

## App Videos and Consent Boundaries

The Devices and app topic separately explains actual app behaviour: silent camera-task movies, private local storage, no automatic Photos copy/upload, exclusion from automatic backup, explicit sharing and deletion that keeps movement measurements. Calibration and Watch tasks do not save movies. This text is separate from the reproduced legal privacy notice.

Removing lab-video text does not remove app-video recording or establish consent for it. Opening the Movement tab is not recorded research consent. This information feature adds no consent acceptance, withdrawal action, video opt-out, upload or retention policy. App-video consent/ethics coverage and the pending patient controls must be resolved before deployment.

22 October: the separate face-masking pipeline adds a bilingual factual paragraph
to Devices and app. It describes new-video on-device masking, temporary-original
deletion, measurement-only saving on processing failure, unchanged older videos
and the absence of any anonymity guarantee. Retained German legal wording and
its approved English translation are unchanged. See
[video storage](MOVEMENT_VIDEO_STORAGE.md#face-masking-22-october-2026).

## Verification

Source comparison checks all retained German Word blocks, including the contact table and definitions. Only the requested lab-video block is omitted. All 60 new strings have explicit English/German values; all 772 pre-existing catalog entries remain unchanged. The contact-page refinement changes only the contact title and adds a localized enquiry-email subject; it does not rewrite legal or storage text.

Unit tests cover topic order, unique content identifiers, retained app-storage explanations and privacy-rights sections. A focused UI test covers the primary Settings order, every topic, contact-only navigation, phone/email availability, the privacy notice's end and relocated video text in English and German, including the largest app text size. See the [testing checklist](../Testing/vCRGlove_testing_checklist.md#17-study-information-and-app-privacy) for the physical review.

The refined 15 October working snapshot passed 139 unit tests and the focused bilingual UI test on the iPhone 17e simulator, iOS 26.5. Result bundles: `/tmp/vcr-settings-refinement-unit.xcresult` and `/tmp/vcr-settings-refinement-ui-verified.xcresult`. Long address text may scroll at accessibility sizes; phone/email actions must be fully reachable. These are software/layout checks, not legal approval or a physical-device review.
