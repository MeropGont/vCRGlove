# Recording plots

The patient plot shows one point per saved trial, using the trial's start time.
Tasks, hands and capture sources remain separate. All points use one colour.
There are no connecting lines, daily averages, reference ranges or treatment-effect
claims. There is no duplicate Recording details block or point-selection overlay.
Recording history opens a
separate, newest-first list of matching recordings, initially limited to 50 rows;
Show older recordings loads another 50. The Data toolbar shortcut opens stored
measurements, export and private-video management.

Meaningful multi-day lines are the next agreed design decision. Daily summaries
versus individual-recording lines have not yet been implemented. See
[the trend proposal and score research](MOVEMENT_COMPOSITE_RESEARCH.md).

## Values

- Rate uses the existing frequency calculation, shown as taps or repetitions per
  second rather than Hz. It is not a clinical score or a good/bad threshold.
- Rhythm variability shows the existing interval coefficient of variation as a
  percentage (CV multiplied by 100). Lower means more even intervals, not better
  health. Zero is valid when the calculation has sufficient input.
- Missing signal, insufficient cycles and non-finite values remain unavailable,
  never invented zero points. The recording is still retained.
- Short recordings remain individual observations. Details show actual duration
  when stored and warn about detected signal gaps. Historical recordings without
  duration are not assigned an estimated duration.

The existing analyser, saved metrics, raw signals and export schema are unchanged.
Velocity and other new calculations require a separate validation task.

## Filters

The default includes all dates and contexts. The 7/30-day options include today
and the previous 6/29 calendar days. Filtering uses trial time, not session time.

Stimulation filters match saved categories exactly. Historical Baseline and
unspecified records are retained, never relabelled as no stimulation planned.
The filter does not imply an actual stimulation dose or elapsed stimulation time.

Medication filters use patient-reported metadata at recording start. The optional
inclusive hour window is descriptive, not an inferred medication ON/OFF state.
Missing, unsure, invalid future-dose and stale 'none today' reports are unknown.
'None today' is distinct from unknown. Filters never modify saved data.

Comparing treatment conditions requires a future agreed protocol: matching task,
hand, duration, acquisition setup, relevant timing and capture adequacy. The
current plot deliberately does not estimate treatment effects across conditions.
