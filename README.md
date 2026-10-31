# AlarmSpec

AlarmSpec is a TLA+ specification of the alarm-system logic of a medical device. It also contains a test kit that compares an alarm-logic implementation with the specification. The model follows the alarm concepts of IEC 60601-1-8.

AlarmSpec is an engineering tool. It is not a medical device and it is not certified. It does not show compliance with a standard.

## Scope

The specification covers these functions:

- Alarm conditions with HIGH, MEDIUM and LOW priority
- Latching and non-latching alarm signals, and ALARM RESET
- AUDIO PAUSED, ALARM PAUSED, AUDIO OFF and ALARM OFF
- Acknowledgement of one alarm condition
- Escalation by the detector, and escalation by time
- Reminder signals
- One tone generator that plays the highest priority
- Start-up with alarm conditions present, and interruption of the power supply

The specification does not cover condition detection, alarm-signal generation delay, sound patterns, distributed alarm systems or logging.

## Contents

| File | Contents |
|------|----------|
| `AlarmSystem.tla` | The specification: design, 11 requirements (R1 to R11), and 18 faults for fault injection |
| `alarm.toml` | The configuration of the alarm system: conditions, priorities and timers |
| `MC.tla`, `MC.cfg`, `Recalls.cfg` | The model instance for TLC. `check.sh` makes these files from `alarm.toml` |
| `Recalls.tla`, `MCRecalls.tla` | Event scripts from 7 FDA recalls |
| `alarm.h`, `alarm.c` | Reference implementation in C11, without dynamic memory |
| `testkit/adapter.h` | The interface between the test kit and an implementation: 6 functions |
| `testkit/adapter_alarm.c` | The adapter for the reference implementation |
| `blackbox.py` | Black-box test of an implementation through the adapter |
| `conformance.py` | White-box test of the reference implementation in each reachable state |
| `check.sh` | Runs all checks |
| `mutants.sh` | Puts 5 known faults into the reference implementation, and makes sure that both tests find each fault |
| `tools/tla2tools.jar` | The TLA+ tools build that the verification used, TLC 2026.10.28 (MIT License). `check.sh` downloads it from the release `tla2tools-2026.10.28` and checks its SHA-256 |

## Requirements

- Java 11 or later
- A C11 compiler
- [uv](https://docs.astral.sh/uv/)
- Internet access on the first run, to download the TLA+ tools

## Run the checks

```sh
JAVA=/path/to/java ./check.sh
JAVA=/path/to/java ./mutants.sh
```

If all checks pass, no output line starts with `FAIL`, and each script exits with status 0. On an Apple M-series computer, `check.sh` takes 4 to 7 minutes and `mutants.sh` takes approximately 9 minutes.

## Test an implementation

1. Copy `alarm.toml` to a new file, for example `my_alarm.toml`.
2. In `my_alarm.toml`, write one condition for each type of alarm condition in your device. A type is a combination of priority, latching, detector escalation and timed escalation.
3. Copy `testkit/adapter_alarm.c` to a new file, for example `my_adapter.c`.
4. In `my_adapter.c`, change the 6 functions so that they call your implementation.
5. Run the test:

   ```sh
   ALARM_CONFIG=my_alarm.toml JAVA=/path/to/java \
       uv run --no-project python blackbox.py my_adapter.c your_alarm.c
   ```

The test makes the model for your configuration with TLC. Then it sends each event from each reachable state to your implementation, and compares the outputs with the model. For each difference, it shows the shortest sequence of events that causes the difference:

```
FAIL  start-up with {m1}, Ack(m1), Escalate(m1): outputs lit={m1} sounding={} tone=NONE reminder=False, model lit={m1} sounding={m1} tone=m1 reminder=False
```

In this example, the operator acknowledged condition `m1`. Then `m1` escalated to HIGH priority, and the implementation did not sound it.

Keep the configuration small. The number of model states increases quickly with the number of conditions:

| Conditions | Model states | Time on an Apple M-series computer |
|------------|--------------|------------------------------------|
| 4 (`alarm.toml`) | 53,940 | 1.5 minutes for `blackbox.py` |
| 5 | 358,260 | 7 minutes for TLC |

## How it works

1. TLC examines each reachable state of the model and checks the 11 requirements.
2. TLC writes the state graph. Each edge has the name of its event, for example `CondOn(h1)`.
3. `blackbox.py` and `conformance.py` use the state graph as the expected result.

The expected results come from the model. They do not come from the reference implementation.

## Results

Configuration `alarm.toml`, 2026-10-31:

| Check | Result |
|-------|--------|
| Model check of R1 to R11 | Pass, 53,940 states |
| Fault injection | 18 of 18 faults found |
| Recall event scripts | 8 of 8 pass |
| `conformance.py`, reference implementation | 0 differences in 250,941 transitions |
| `blackbox.py`, reference implementation | 0 differences in 1,294,560 events |
| `mutants.sh` | 5 of 5 faults found by both tests |

## Limitations

- The checks are exhaustive only for the configuration in the configuration file.
- The tests compare logical outputs. They do not examine sound, timing on the target hardware or concurrency.
- This repository does not contain text from IEC 60601-1-8. The clause numbers in the documentation pack are provisional. They come from public samples of the standard.

## Documentation

The IEC 62304 documentation pack for AlarmSpec is sold separately. It contains the traceability matrix, the detailed design of the reference implementation, the unit verification report and the tool validation evidence.

## License

Apache License 2.0. See `LICENSE`. The TLA+ tools in `tools/tla2tools.jar` have their own license (MIT).
