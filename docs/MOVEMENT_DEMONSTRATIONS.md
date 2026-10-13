# Movement Demonstrations

The iPhone target bundles four video-only copies in
`vCRGlove/Resources/hand_videos`. No download, Photos permission, or Watch is required.
Originals remain in `updrs_tasks/hand_videos`; that folder and older attempts are
not bundled.

| Task | Hand | File | Duration |
| --- | --- | --- | --- |
| Finger tapping | Left | finger_tapping_left.mp4 | 35.99 s |
| Finger tapping | Right | finger_tapping_right.mp4 | 35.99 s |
| Hand opening/closing | Left | fist_right.mp4 | 35.03 s |
| Hand opening/closing | Right | fist_left.mp4 | 35.04 s |

All encoded pictures remain 854 x 480. The fist copies have lossless rotation
metadata: left counterclockwise, right clockwise. Their displayed size is
480 x 854, with fingers pointing up. Tapping copies remain landscape.
Only the fist clips use opposite filename-to-task mapping to match the patient's
camera viewpoint. Finger-tapping mapping stays unchanged. Upright fist demos use
a centered display-only crop (147 source pixels from each vertical edge), keeping
all fingers visible. Finger tapping remains aspect fit; no video is mirrored. AVFoundation
passthrough export removes audio without re-encoding the picture.
Original files remain unchanged, including their audio tracks. Playback is also
muted. Keep the app resource folder free of unrelated files, since its contents
ship with the app.
The four silent copies total about 16 MB.

## Interaction

- Before recording, the patient can play/pause the matching example.
- One centered play/pause control covers the video's whole tap area.
- Recording camera previews are 230 points tall with larger text, or 210 for open/close at
  standard text size. Its hand label shares the step header and instructions sit
  beside the demo, leaving room for the live rhythm. Larger text stays stacked
  and scrollable.
- Standard-size tapping keeps a stacked layout with a compact step/hand header,
  a 200-point camera, full-width instructions and a horizontal demo. The demo
  remains 240 points wide without cropping or rotation; live rhythm stays below it.
- Demos are smaller than the camera: tapping
  clips are at most 240 points wide during recording; upright fist clips
  are 170 points wide and about 198 points tall. Original assets are not cropped.
- Start Recording opens the existing three-second countdown. A fresh, silent
  demonstration starts automatically and loops during recording.
  The finishing flag resets before every countdown, including after completed takes.
- The countdown overlays the camera preview. Elapsed time and Stop remain in
  the bottom safe area. Larger-text content can scroll above these controls.
- Returning, skipping, retaking, or leaving a screen stops its demonstration.
  Backgrounding pauses playback; returning resumes only if it was playing.
- An unavailable video shows a short message without blocking the measurement.
- Watch pronation/supination has no video until a corresponding clip is supplied.
- Manual Stop disables repeated taps and pauses the demo while finishing.
  Recorder completion finalizes capture before opening results, including when
  Stop was tapped before camera recording started or any samples arrived.

Demonstrations are separate from the patient's camera capture and stored trial
videos. Playback does not change measurement duration, signal analysis, medication
context, recording-quality checks, or saving. The measurement remains 30 seconds;
the demonstration duration does not define a clinical test protocol.

## Validation

Automated tests cover task/hand resource mapping, absence of bundled audio,
decoding, aspect ratio,
orientation, silent/manual/automatic playback, looping, interruptions, cleanup,
missing-video fallback, and English/German task navigation. Physical iPhone
verification remains necessary for simultaneous live camera capture and playback.

## Clinical Context

The introduction uses ordinary numbered task labels, not completion indicators.
Allow about 5–7 minutes for six recordings plus navigation and preparation;
practice and breaks can take longer. A bilingual information sheet explains
which movement features are recorded without presenting clinical scores.

MDS-UPDRS Part III items 3.4–3.6 use ten repetitions per side, with an examiner's
rating of speed, amplitude and interruptions/decrement. Demonstration is before,
not alongside, scored performance. Our 30-second recordings and optional ongoing
demo are adaptations, not an equivalent MDS-UPDRS assessment. The recording
protocol is unchanged by these UI fixes.

Sources: [MDS-UPDRS, pages 20–21](https://www.uwo.ca/fhs/csd/smdl/docs/MDS-UPDRS_English_FINAL_Updated_August2019.pdf)
and [MDS permissions](https://www.movementdisorders.org/MDS/MDS-Clinical-Outcome-Assessment.htm).
Confirm institute permission for software use/adaptations before clinical deployment.
No scale scoring descriptions are reproduced in the app.

On-device check: try both hands for both camera tasks; preview/pause the example,
start recording, confirm the countdown and live camera remain smooth, then save
and review the patient's recording. The saved video must show the camera capture,
not the bundled example. No Watch clip or Watch recording behavior is changed.
