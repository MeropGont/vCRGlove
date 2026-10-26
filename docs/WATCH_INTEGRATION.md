# Watch Integration: Software Safeguards

Implemented on `codex/watch-integration`, 26 October 2026. This is not a
hardware-validated release. Install matching phone and Watch builds from this
branch; old untagged messages are intentionally incompatible with live capture.

## Implemented

- Both targets compile the same `WatchStreamProtocol` wire contract (version 1).
  Each capture has a UUID; each batch includes that UUID and a sequence number.
  The phone rejects wrong-version, wrong-ID, duplicate, out-of-order, oversized,
  malformed, non-finite and non-increasing sample batches.
- Start and Stop use acknowledgements. Start is never queued or retried after
  cancellation. The Watch rejects concurrent stream IDs and remembers recently
  ended IDs, so reordered stops cannot stop a newer stream. Only UUID-scoped
  Stop commands can use queued delivery after a connection failure.
- Capture readiness requires valid samples after the start acknowledgement.
  Missing samples time out after eight seconds, with localised English/German
  instructions. Cancellation invalidates timers and ignores late callbacks.
- Phone-side transport/capture state is main-actor isolated. Reachability changes
  update the task controls without requiring the user to leave and reopen them.
  Watch motion callbacks and command-state changes use the main queue; callbacks
  left over from a previous stream cannot append samples to a newer one.
- Manual Record/Stream controls cannot interrupt phone-controlled capture. The
  service also rejects a manual recording while streaming, not just the button.
- Phone-controlled streaming has a 45-second safety stop (three-second countdown,
  30-second task, teardown allowance). This limits an orphaned stream after a
  missed Stop; it is not proof that all data reached the phone.
- Extended runtime uses immediate `start()` with the `self-care` health-activity
  session type, not smart-alarm scheduling. It requires the Watch app to be active
  when starting. Leaving the app/backgrounding or runtime invalidation stops the
  stream. Self-care runtime is frontmost, not unrestricted background recording.
  Wrist-lowering behaviour requires real-device verification.

## Data and Timing Boundaries

The signal is still Watch x-axis rotation rate in radians/second. Task, hand,
participant ID, medication context and trial start are still attached by the
phone's existing recording/saving path. No journal, stimulation or camera signal
logic, task duration, measurement algorithm or historical records were changed.
The displayed hand is the requested hand; the app does not verify which wrist
actually wears the Watch. Both wrists/Watch orientation need a real movement test.

Watch-relative timestamp spacing is preserved. The newest sample of the initial
batch is anchored to phone receipt uptime, rather than projecting the remaining
batch into the future. This is an approximate arrival-based offset, not a
synchronised phone/Watch clock or a validated alignment to stimulation/EEG.

Live messages remain lossy on disconnection. There is no durable Watch copy of
the streamed rotation signal and no replay/final-drain guarantee. Sequence gaps
and raw timestamp gaps are not filled with invented samples. The current Watch
analysis remains v1 and does not gain camera-style gap segmentation in this pass.
The 30-second phone timer still finishes if the feed stalls; existing missing-
signal/recording feedback remains responsible for showing limited evidence.

The separate diagnostic acceleration CSV Record/Send workflow is not a backup
of the rotation stream. Its phone file-receive/import path remains unfinished.
No server uploads or new patient-consent assumptions are introduced.

## Validation and Next Stage

See [the Watch checklist](../Testing/watch_integration_checklist.md) for software
evidence and remaining device checks. Initial connection, sustained motion,
screen dimming, disconnection and exported-data review must pass on the Air's
Xcode 27 / watchOS 27 setup before treating this as patient-ready.

Apple reference: [extended runtime sessions](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions).
