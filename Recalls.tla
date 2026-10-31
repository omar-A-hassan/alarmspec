---------------------------- MODULE Recalls ----------------------------
(***************************************************************************)
(* Replays the event sequence of a real FDA recall against the model. The *)
(* reference design must satisfy every requirement along the script; the  *)
(* fault named for the recall must violate the named requirement. A step  *)
(* the design refuses makes TLC report a deadlock, so a script cannot      *)
(* pass by silently not running.                                           *)
(***************************************************************************)
EXTENDS AlarmSystem, Sequences

CONSTANTS
    Script,       \* << <<action>> or <<action, argument>>, ... >>
    StartActive   \* conditions already present at start-up

VARIABLE step

Do(s) ==
    CASE s[1] = "CondOn"   -> CondOn(s[2])
      [] s[1] = "CondOff"  -> CondOff(s[2])
      [] s[1] = "Escalate" -> Escalate(s[2])
      [] s[1] = "Ack"      -> Ack(s[2])
      [] s[1] = "Pause"    -> Pause(s[2])
      [] s[1] = "Off"      -> Off(s[2])
      [] s[1] = "Reset"    -> Reset
      [] s[1] = "Cancel"   -> Cancel
      [] s[1] = "Tick"     -> Tick
      [] s[1] = "PowerCycle" -> PowerCycle

ReplayNext ==
    \/ step < Len(Script) /\ Do(Script[step + 1]) /\ step' = step + 1
    \/ step = Len(Script) /\ UNCHANGED <<vars, step>>   \* script finished

Replay == Init /\ active = StartActive /\ step = 0 /\ [][ReplayNext]_<<vars, step>>
=============================================================================
