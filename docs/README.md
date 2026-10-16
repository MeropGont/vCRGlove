# Project Documentation

Current implementation reference, reviewed 16 October 2026. Start here for development and team handover. Patient guidance lives inside the app.

Prefer a document reader? Open the [PDF handbook](vCRGlove_Handbook.pdf). It contains the overview, setup, data formats, release and testing chapters, with a clickable contents page. Markdown remains the editable source.

## Start Here

| Need | Reference |
| --- | --- |
| Understand the app | [Project overview](../README.md) |
| Set up Xcode, find the relevant code, run tests | [Development guide](DEVELOPMENT_GUIDE.md) |
| Understand saved records, timestamps and exports | [Data formats](DATA_FORMATS.md) |
| Prepare a reproducible TestFlight build | [Release checklist](RELEASE_CHECKLIST.md) |
| Test on an iPhone, gloves and Watch | [Physical testing checklist](../Testing/vCRGlove_testing_checklist.md) |

## Feature References

| Area | Reference | Status |
| --- | --- | --- |
| Movement instructions and videos | [Demonstrations](MOVEMENT_DEMONSTRATIONS.md) | Implemented; hardware checks remain important |
| Researcher stimulation settings | [Shared vCR controls](DEVELOPMENT_GUIDE.md#shared-vcr-and-researcher-controls) | Implemented; per-hand setup and timing require physical validation |
| Manual full-device data sharing | [ZIP contents and limits](DATA_FORMATS.md#researcher-full-data-zip) | Researcher-only manual export; verified backup/consent-based transfer remain separate |
| Daily trends and filters | [Results](MOVEMENT_RESULTS.md) | Implemented; camera/clinical validation remains pending |
| Private recordings and deletion | [Video storage](MOVEMENT_VIDEO_STORAGE.md) | Implemented; verified backup and retention remain pending |
| Task-specific composite measures | [Research review](MOVEMENT_COMPOSITE_RESEARCH.md) | Proposal, not a validated score |
| Journal redesign | [Stages and verification](JOURNAL_REDESIGN.md) | Stages 1/2 implemented; device review pending |
| Journal design rationale | [Original proposal](JOURNAL_REVIEW_PROPOSAL.md) | Design history, not the current screen specification |
| Medication/activity integration | [Apple Health review](APPLE_HEALTH_RESEARCH.md) | Decision pending; no integration added |
| Study information in Settings | [Content and source](STUDY_INFORMATION.md) | Bilingual information pages; legal review/patient controls remain separate |
| Backend interface | [Integration reference](../BACKEND_INTEGRATION.md) | Dormant client path; incomplete server fields/consent workflow |

## Working Backlog

The shared planning file is `QA/app_improvement_backlog.xlsx`, maintained separately from Git. Use its stable IDs, such as `MOV-005` or `JRN-002`, when discussing work. A missing workbook in a fresh clone is expected; obtain the current copy from the project team.

Keep existing formatting and manual statuses when updating it. Close Excel before file-based edits. Record what was implemented, what was verified, and what still needs a device check or approval. Do not mark an entire staged redesign complete after finishing only one stage.

## Historical Material

These records explain earlier decisions; their commands, test counts and feature descriptions may be outdated:

- [Original movement-module handoff](../DEVIN_HANDOFF_vCRGlove.md).
- [July analyzer test report](Task-A_Unit-Tests_MovementAnalyzer.md).
- [July camera changelog](CHANGELOG_Notion.md).
- [July Watch changelog](CHANGELOG_2026-07-09_Notion.md).
- [Backend prototype](../backend/README.md) and [clinic prototype](../clinic/README.md). These are not a deployed patient-data service.

Synthetic examples and tests are software fixtures, not clinical reference populations or validation of a score.

## Keeping This Useful

- Update the relevant feature document and checklist with the code change. Link from this index instead of copying the same explanation into several files.
- For storage/schema changes, update [Data formats](DATA_FORMATS.md) and add compatibility/failure tests before migrating data.
- Record release-specific evidence in the [release record](RELEASE_CHECKLIST.md#release-record). Passing tests for an older commit are not evidence for a later build.
- Keep proposals clearly separate from implemented behaviour. Code and reproducible tests resolve implementation discrepancies; approved study documents govern clinical and privacy requirements.
- Keep patient data, identity mappings, consent forms, credentials and signing keys out of the repository. Store sensitive operational documents in approved institutional storage.

### Rebuild the PDF

After a major change, update the affected source chapters and regenerate the PDF. Use the bundled workspace Node/Python runtimes, with Marked, ReportLab and pypdf available. The builder resolves those dependencies beside the bundled Node executable; `CODEX_NODE_MODULES` and `CODEX_PYTHON` can override their locations.

Run from the repository root, replacing the example date with the actual review date:

```zsh
node tools/build_documentation.mjs --date 2026-10-15
node tools/build_documentation.mjs --date 2026-10-15 --check
```

The check compares the PDF's source fingerprint with all included Markdown chapters. It detects stale source content, not layout or correctness. Render and inspect the rebuilt pages before delivery. The PDF contains no ethics source documents or patient records.
