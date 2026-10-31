"""Black-box conformance test: an alarm-logic implementation against AlarmSystem.tla.

The test uses only the interface in testkit/adapter.h. It does not read the internal
state of the implementation.

1. TLC writes the full state graph of the model. Each edge has the name of its event.
2. The test sends each event from each reachable state to the implementation.
3. After each event, the test compares the outputs (lit, sounding, tone, reminder) with
   the model. If the model refuses the event, the implementation state must not change.

The test identifies implementation states by snapshot. Thus it also finds a difference
in internal state that shows in the outputs only after more events. For each failure,
the test shows the shortest sequence of events that causes it.

alarm.toml describes the alarm system. ALARM_CONFIG can name a different file.

Run: ALARM_CONFIG=my_alarm.toml JAVA=/path/to/java \
         uv run --no-project python blackbox.py my_adapter.c your_sources.c ...
"""
import ctypes
import subprocess
import sys
import tempfile
from collections import deque
from pathlib import Path

from conformance import (CONDS, ESCALATE_TICKS, ESCALATING, HERE, INACT, LATCHING, LOW_AUDIBLE,
                         PAUSE_TICKS, PRIO, REMINDER_TICKS, TIMED_ESCALATING, mask, model_graph)

# (model action label, adapter event, arg); event numbers follow the enum in adapter.h.
EVENTS = ([(f"{a}({c})", e, i) for e, a in enumerate(("CondOn", "CondOff", "Escalate", "Ack"))
           for i, c in enumerate(CONDS)]
          + [("Reset", 4, 0)]
          + [(f'Pause("{INACT[k]}")', 5, k) for k in (1, 2)]
          + [(f'Off("{INACT[k]}")', 6, k) for k in (3, 4)]
          + [("Cancel", 7, 0), ("Tick", 8, 0), ("PowerCycle", 9, 0)])
LIMIT = 20  # maximum number of implementation states for each model state


class Config(ctypes.Structure):  # mirrors ta_config in testkit/adapter.h
    _fields_ = [("n", ctypes.c_int), ("priority", ctypes.c_uint8 * 32),
                ("latching", ctypes.c_uint32), ("escalating", ctypes.c_uint32), ("timed", ctypes.c_uint32),
                ("pause_ticks", ctypes.c_int), ("reminder_ticks", ctypes.c_int),
                ("escalate_ticks", ctypes.c_int), ("low_audible", ctypes.c_bool)]


def build(tmp, sources):
    lib = Path(tmp, "libta.so")
    subprocess.run(["cc", "-std=c11", "-O2", "-shared", "-fPIC", "-I", str(HERE / "testkit"),
                    "-o", str(lib), *sources], check=True)
    lib = ctypes.CDLL(str(lib))
    lib.ta_state_size.restype = ctypes.c_size_t
    return lib


def expected(st):
    tone = -1 if st["tone"] == "NONE" else CONDS.index(st["tone"])
    return mask(st["lit"]), mask(st["sounding"]), tone, st["reminder"]


def show(out):
    names = lambda m: "{" + ",".join(c for i, c in enumerate(CONDS) if m >> i & 1) + "}"
    lit, snd, tone, rem = out
    return f"lit={names(lit)} sounding={names(snd)} tone={CONDS[tone] if tone >= 0 else 'NONE'} reminder={rem}"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    with tempfile.TemporaryDirectory() as tmp:
        lib = build(tmp, [str(Path(f).resolve()) for f in sys.argv[1:]])
        states, _, inits, acts = model_graph(tmp)

        cfg = Config(len(CONDS), (ctypes.c_uint8 * 32)(*PRIO), mask(LATCHING), mask(ESCALATING),
                     mask(TIMED_ESCALATING), PAUSE_TICKS, REMINDER_TICKS, ESCALATE_TICKS, LOW_AUDIBLE)
        buf = ctypes.create_string_buffer(lib.ta_state_size())
        lit, snd, tone, rem = ctypes.c_uint32(), ctypes.c_uint32(), ctypes.c_int(), ctypes.c_bool()

        def outputs():
            lib.ta_outputs(ctypes.byref(lit), ctypes.byref(snd), ctypes.byref(tone), ctypes.byref(rem))
            return lit.value, snd.value, tone.value, rem.value

        def save():
            lib.ta_save(buf)
            return buf.raw

        def load(snap):
            ctypes.memmove(buf, snap, len(snap))
            lib.ta_load(buf)

        # Nodes pair a model state with a snapshot of your code; parent links give the trace.
        parent, queue, bad, checked = {}, deque(), [], 0
        for i in inits:
            lib.ta_init(ctypes.byref(cfg), mask(states[i]["active"]))
            node = (i, save())
            if outputs() != expected(states[i]):
                bad.append((node, None, f"outputs {show(outputs())}, model {show(expected(states[i]))}"))
            parent[node] = None
            queue.append(node)

        while queue:
            node = queue.popleft()
            sid, snap = node
            for label, ev, arg in EVENTS:
                load(snap)
                lib.ta_event(ev, arg)
                got, new = outputs(), save()
                checked += 1
                tid = acts.get(sid, {}).get(label)
                if tid is None:
                    if new != snap:
                        bad.append((node, label, "your state changed, but the model refuses this event"))
                elif got != expected(states[tid]):
                    bad.append((node, label, f"outputs {show(got)}, model {show(expected(states[tid]))}"))
                elif (tid, new) not in parent:
                    parent[(tid, new)] = (node, label)
                    queue.append((tid, new))
            if len(parent) > LIMIT * len(states):
                sys.exit("STOP  too many implementation states: remove logs and free-running clocks from ta_save")

        def trace(node, label):  # start-up conditions, then the events that reach the failure
            steps = [label] if label else []
            while parent[node]:
                node, step = parent[node]
                steps.insert(0, step)
            return "{" + ", ".join(c for c in CONDS if c in states[node[0]]["active"]) + "}", steps

        print(f"{len(states)} model states, {len(parent)} states of your code, {checked} events checked")
        failures = sorted(((*trace(n, l), w) for n, l, w in bad), key=lambda f: len(f[1]))
        for start, steps, why in failures[:5]:
            print(f"FAIL  start-up with {start}" + "".join(f", {s}" for s in steps) + f": {why}")
        print("FAIL" if bad else "PASS", f"{len(bad)} failing event(s)")
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
