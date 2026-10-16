# Release Checklist

Use this for each deliberate TestFlight release. It documents the process; it does not authorize an upload or patient deployment.

## Version and Build

Version names a milestone; build identifies an uploaded binary. For example, `0.5.0 (2)` can contain fixes after `0.5.0 (1)` without changing the milestone. Setting a version does not freeze development.

The current project snapshot has phone and Watch version `0.5.0`, build `1`. This is not a record of the latest App Store Connect upload. Check the actual uploaded build before choosing the next number. Keep shipped phone/Watch version and build aligned in Debug and Release; test bundles have separate version settings.

Use a new, increasing build for each upload; do not reuse a previously uploaded number for that version. Apple associates uploads using bundle ID, version and build. Record the final uploaded values if Xcode manages/increments them during distribution. See [Apple's upload guidance](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## Before Archiving

- [ ] Agree on the release scope and tester group. No unapproved clinical/privacy changes.
- [ ] Review `git status --short` and the diff. Include intended source, bundled assets, tests and documentation; exclude raw source videos, patient exports, credentials and personal workspace settings.
- [ ] Update version/build and release notes. Confirm ICNS signing, bundle IDs and embedded Watch identity.
- [ ] Run relevant unit/UI tests using the [development guide](DEVELOPMENT_GUIDE.md). Record their exact commit and results; do not carry forward old passes as new verification.
- [ ] Perform the applicable [physical smoke tests](../Testing/vCRGlove_testing_checklist.md), including English/German, largest app text, early Stop, saving/relaunch, playback/export and deletion cancellation. Mark Watch/glove tests deferred if not actually performed.
- [ ] Verify both hands' saved stimulation amplitudes and approved pattern/frequency in person before handover. Research unlock must not create another tab, and patient Start/reconnect must not restore the old preset. Check startup cancellation and hardware pulse timing; software tests alone do not validate delivery.
- [ ] Verify update compatibility on disposable data. Preserve IDs, old journal fields, recordings and deleted-video markers. Do not delete a study app to resolve an install error without a verified data copy.
- [ ] Review known limitations and privacy/consent requirements before adding patients. A successful build/upload is not study deployment approval.

## Commit and Tag

The order to remember is **inspect, stage, inspect staged, commit, inspect, push**. Run from the repository root. Select paths deliberately instead of using `git add .` on a mixed working tree.

```zsh
git status --short
git diff --stat
git diff
git add path/to/changed-file
git diff --cached --stat
git diff --cached
git commit -m "Describe the tested change"
git log --oneline -3
git status --short
git push
```

Replace `path/to/changed-file` with the intended files before running the staging command. Unrelated untracked files may remain, but must not be included accidentally. A release archive should correspond to a committed snapshot without uncommitted tracked app changes.

After verifying the release commit, create an annotated tag, for example `v0.5.0-build.2`. The tag identifies the source used, not proof of clinical validation. Do not move a published tag to another commit.

```zsh
git tag -a v0.5.0-build.2 -m "TestFlight 0.5.0 build 2"
git push origin v0.5.0-build.2
git rev-parse HEAD
```

Use the actual version/build, check that the tag is new, and push only the intended tag. If distribution changes the final build number, reconcile the release record/tag before sharing the build.

## Archive and Distribute

1. In Xcode select the `vCRGlove` scheme and a generic physical iOS destination, then Product > Archive. Review the archive's version/build and embedded Watch app.
2. In Organizer validate the archive and review warnings. A missing vendor dSYM affects crash symbolication; obtain symbols matching the framework UUID from the vendor rather than inventing an empty dSYM. Keep the archive and available symbols in approved storage.
3. For internal/external TestFlight flexibility choose **App Store Connect** (called **TestFlight & App Store** in some Xcode flows). **TestFlight Internal Only** restricts that upload to internal testers. Uploading does not publish the app publicly. See [Apple's distribution tutorial](https://developer.apple.com/tutorials/develop-in-swift/test-your-beta-app).
4. After processing, verify the actual version/build in App Store Connect. Review encryption declarations against all bundled dependencies; the current project sets `ITSAppUsesNonExemptEncryption = NO`, which is not a claim that the OS uses no encryption.
5. Add the build to the agreed TestFlight group with concise "What to Test" notes and known limitations. Do not give patients developer/admin roles merely to distribute a build. Internal testers require appropriate App Store Connect access; external testing is a separate workflow. See [Apple's internal testing guide](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers).
6. Install the distributed build and perform a short smoke check. Record the uploaded binary's identity and distribution result, not just the local Xcode run.

## Rollback Without Data Loss

Stop broader rollout when a regression is discovered and keep the failing build/logs for diagnosis. Do not uninstall a study app or clear its container as a rollback step.

Prefer a reviewed fix or `git revert` on a new branch/commit, then release with a new build number. Check persisted-data compatibility: reversing code does not reverse a storage migration. Test recovery against a copy before touching patient data. Avoid `git reset --hard`, force-pushing shared history or moving published release tags.

An older TestFlight build is an option only if still available and compatible with the current stored data. Verify that on disposable data first; never assume it restores lost records or videos.

## Release Record

Keep one completed record per distributed build alongside team release notes. Store device logs/screenshots and archives in approved institutional storage, not patient data in Git.

```text
Version/build:
Source commit/tag:
Release date and responsible reviewer:
Xcode/macOS and SDK:
Phone/Watch models and OS tested:
Automated tests (command/result location/commit):
Physical checks (pass/fail/deferred and evidence):
Changes to test:
Known limitations and deferred checks:
Data compatibility/export checks:
Archive/symbols location:
App Store Connect processing result and actual uploaded build:
Tester group and distribution date:
Follow-up issues/backlog IDs:
```
