---------------------------- MODULE AlarmSystem ----------------------------
(***************************************************************************)
(* Reference model of a medical-device alarm system, after IEC 60601-1-8: *)
(*   - latching alarm signals and ALARM RESET                              *)
(*   - inactivation states AUDIO PAUSED, ALARM PAUSED, AUDIO OFF,          *)
(*     ALARM OFF, and per-condition ACKNOWLEDGED                           *)
(*   - priority escalation, by the detector and by time                    *)
(*   - start-up with conditions already present, and power interruption    *)
(*   - reminder signals while an OFF state is in force                     *)
(*   - single-tone priority (a lower priority sound never covers a higher) *)
(*                                                                         *)
(* Concepts are paraphrased. This file contains no text of the standard.   *)
(* Clause numbers are provisional. They refer to IEC 60601-1-8:2006        *)
(* +AMD1:2012+AMD2:2020 and come from public samples of the standard.      *)
(*                                                                         *)
(* Layout: ENVIRONMENT variables are facts about the patient; DESIGN       *)
(* variables are the state an implementation keeps; OUTPUT variables are   *)
(* what it annunciates; MONITOR variables record history the requirements *)
(* need. Requirements read environment, outputs and monitors only, never   *)
(* design internals.                                                       *)
(***************************************************************************)
EXTENDS Naturals

CONSTANTS
    Conds,          \* alarm conditions
    Priority,       \* [Conds -> {"HIGH", "MEDIUM", "LOW"}], priority before escalation
    Latching,       \* conditions whose alarm signals latch
    Escalating,     \* conditions the detector can escalate to HIGH while they persist
    TimedEscalating,\* conditions the alarm system must escalate to HIGH after EscalateTicks
    EscalateTicks,  \* clock ticks a TimedEscalating condition persists before it escalates
    Index,          \* [Conds -> Nat], injective: tie-break order for the tone generator
    PauseTicks,     \* length of AUDIO PAUSED / ALARM PAUSED, in clock ticks
    ReminderTicks,  \* clock ticks between reminder signals in an OFF state
    LowAudible,     \* manufacturer choice: TRUE if LOW priority conditions sound
    Fault           \* injected implementation bug; "NONE" is the reference design

Faults == {"NONE", "NO_LATCH", "LATCH_ALL", "PAUSE_HIDES_VISUAL", "MEDIUM_SILENT",
           "GLOBAL_PAUSE", "STICKY_PAUSE_SET", "ENDLESS_PAUSE",
           "ACK_ALL", "ACK_STICKY", "ACK_HIDES", "ESC_KEEPS_ACK", "ESC_KEEPS_PAUSE",
           "NO_REMINDER", "FIFO_TONE", "LATCH_SILENT",
           "EDGE_TRIGGERED", "PERSIST_SILENCE", "NO_ESCALATION"}

ASSUME /\ Priority \in [Conds -> {"HIGH", "MEDIUM", "LOW"}]
       /\ Latching \subseteq Conds
       /\ Escalating \subseteq Conds
       /\ TimedEscalating \subseteq Conds
       /\ EscalateTicks \in Nat \ {0}
       /\ Index \in [Conds -> Nat]
       /\ \A c, d \in Conds : Index[c] = Index[d] => c = d
       /\ PauseTicks \in Nat \ {0}
       /\ ReminderTicks \in Nat \ {0}
       /\ LowAudible \in BOOLEAN
       /\ Fault \in Faults

States == {"NONE", "AUDIO_PAUSED", "ALARM_PAUSED", "AUDIO_OFF", "ALARM_OFF"}
Paused == {"AUDIO_PAUSED", "ALARM_PAUSED"}
Offs   == {"AUDIO_OFF", "ALARM_OFF"}

VARIABLES
    active,     \* ENVIRONMENT: conditions whose cause currently exists
    worse,      \* ENVIRONMENT/DESIGN: active conditions escalated to HIGH (detector or timer)
    latched,    \* DESIGN: latching conditions still signalled after their cause ended
    inact,      \* DESIGN: global inactivation state in force
    timer,      \* DESIGN: ticks left in a pause, or until the next reminder
    pausedSet,  \* DESIGN: conditions the current pause applies to
    acked,      \* DESIGN: conditions whose current occurrence is ACKNOWLEDGED
    age,        \* DESIGN: [TimedEscalating -> ticks the condition has persisted unescalated]
    lit,        \* OUTPUT: conditions with a visual alarm signal
    sounding,   \* OUTPUT: conditions calling for an auditory alarm signal
    tone,       \* OUTPUT: the condition whose sound the single tone generator plays
    reminder,   \* OUTPUT: a reminder signal is being given
    owed,       \* MONITOR: latching conditions owed a signal until ALARM RESET
    fresh,      \* MONITOR: conditions that (re)occurred or escalated during the current pause
    ackReq,     \* MONITOR: conditions the operator acknowledged, current occurrence only
    booted,     \* MONITOR: no operator silencing since start-up or the last restart
    heldFor     \* MONITOR: [TimedEscalating -> ticks held since onset or restart, capped]

vars == <<active, worse, latched, inact, timer, pausedSet, acked, age,
          lit, sounding, tone, reminder, owed, fresh, ackReq, booted, heldFor>>

\* Priority after escalation, given the set of escalated conditions.
Eff(c, wr) == IF c \in wr THEN "HIGH" ELSE Priority[c]
Rank(p)    == CASE p = "HIGH" -> 3 [] p = "MEDIUM" -> 2 [] OTHER -> 1
Min(a, b)  == IF a < b THEN a ELSE b

(***************************************************************************)
(* Design: annunciation.                                                   *)
(*                                                                         *)
(* A pause applies only to the conditions signalled when it started; a     *)
(* condition that (re)occurs or escalates during the pause leaves          *)
(* pausedSet. An acknowledgement applies to one occurrence of one          *)
(* condition and ends when the condition ends or escalates. The OFF states *)
(* apply to everything. The tone generator plays the highest priority      *)
(* sound, ties broken by Index.                                            *)
(***************************************************************************)
Scope(ps) == IF Fault = "GLOBAL_PAUSE" THEN Conds ELSE ps

Muted(ina, ps, ack) ==
    ack \cup CASE ina \in Offs   -> Conds
               [] ina \in Paused -> Scope(ps)
               [] OTHER          -> {}

Hidden(ina, ps, ack) ==
    (IF Fault = "ACK_HIDES" THEN ack ELSE {})
    \cup CASE ina = "ALARM_OFF"                                    -> Conds
           [] ina = "ALARM_PAUSED"                                 -> Scope(ps)
           [] ina = "AUDIO_PAUSED" /\ Fault = "PAUSE_HIDES_VISUAL" -> Scope(ps)
           [] OTHER                                                -> {}

Sounds(c, wr) ==
    IF Fault = "MEDIUM_SILENT" THEN Eff(c, wr) = "HIGH"
    ELSE Eff(c, wr) # "LOW" \/ LowAudible

\* Highest priority wins; equal priorities go to the lowest Index.
Top(S, wr) ==
    CHOOSE c \in S : \A d \in S :
        \/ Rank(Eff(c, wr)) > Rank(Eff(d, wr))
        \/ Rank(Eff(c, wr)) = Rank(Eff(d, wr)) /\ Index[c] <= Index[d]

Outputs(act, lat, ina, ps, ack, wr, tmr, prevTone) ==
    LET signalled == act \cup lat
        audible   == IF Fault = "LATCH_SILENT" THEN act ELSE signalled
        snd       == {c \in audible \ Muted(ina, ps, ack) : Sounds(c, wr)}
    IN  [lit      |-> signalled \ Hidden(ina, ps, ack),
         sounding |-> snd,
         tone     |-> IF snd = {} THEN "NONE"
                      ELSE IF Fault = "FIFO_TONE" /\ prevTone \in snd THEN prevTone
                      ELSE Top(snd, wr),
         reminder |-> (ina \in Offs /\ tmr = 0)]

Annunciate(act, lat, ina, ps, ack, wr, tmr) ==
    LET o == Outputs(act, lat, ina, ps, ack, wr, tmr, tone)
    IN  lit' = o.lit /\ sounding' = o.sounding /\ tone' = o.tone /\ reminder' = o.reminder

\* Timed-escalating conditions whose escalation clock is running.
Counting == (TimedEscalating \cap active) \ worse

(***************************************************************************)
(* Behaviour.                                                              *)
(***************************************************************************)
\* Start-up: any conditions may already exist (a monitor switched on next to a patient).
Init ==
    /\ active \in SUBSET Conds
    /\ worse = {}
    /\ latched = active \cap Latching
    /\ inact = "NONE" /\ timer = 0 /\ pausedSet = {} /\ acked = {}
    /\ age = [c \in TimedEscalating |-> 0]
    /\ LET o == Outputs(active, latched, "NONE", {}, {}, {}, 0, "NONE")
       IN  IF Fault = "EDGE_TRIGGERED"   \* annunciates only conditions that begin later
           THEN lit = {} /\ sounding = {} /\ tone = "NONE" /\ reminder = FALSE
           ELSE lit = o.lit /\ sounding = o.sounding /\ tone = o.tone /\ reminder = o.reminder
    /\ owed = active \cap Latching /\ fresh = {} /\ ackReq = {}
    /\ booted = TRUE /\ heldFor = [c \in TimedEscalating |-> 0]

\* Environment: a cause appears.
CondOn(c) ==
    /\ c \notin active
    /\ active' = active \cup {c}
    /\ latched' = IF c \in Latching \/ Fault = "LATCH_ALL"
                  THEN latched \cup {c} ELSE latched
    /\ pausedSet' = IF Fault = "STICKY_PAUSE_SET" THEN pausedSet ELSE pausedSet \ {c}
    /\ owed' = IF c \in Latching THEN owed \cup {c} ELSE owed
    /\ fresh' = IF inact \in Paused THEN fresh \cup {c} ELSE fresh
    /\ UNCHANGED <<worse, inact, timer, acked, ackReq, age, booted, heldFor>>
    /\ Annunciate(active', latched', inact, pausedSet', acked, worse, timer)

\* Environment: a cause disappears. A latching signal stays until ALARM RESET;
\* the acknowledgement and escalation of this occurrence end.
CondOff(c) ==
    /\ c \in active
    /\ active' = active \ {c}
    /\ worse' = worse \ {c}
    /\ latched' = IF Fault = "NO_LATCH" THEN latched \ {c} ELSE latched
    /\ acked' = IF Fault = "ACK_STICKY" THEN acked ELSE acked \ {c}
    /\ ackReq' = ackReq \ {c}
    /\ age' = [d \in TimedEscalating |-> IF d = c THEN 0 ELSE age[d]]
    /\ heldFor' = [d \in TimedEscalating |-> IF d = c THEN 0 ELSE heldFor[d]]
    /\ UNCHANGED <<inact, timer, pausedSet, owed, fresh, booted>>
    /\ Annunciate(active', latched', inact, pausedSet, acked', worse', timer)

\* Environment: a persisting condition escalates to HIGH. Escalation is a new event:
\* it is not covered by an earlier acknowledgement or pause.
Escalate(c) ==
    /\ c \in (active \cap Escalating) \ worse
    /\ worse' = worse \cup {c}
    /\ acked' = IF Fault = "ESC_KEEPS_ACK" THEN acked ELSE acked \ {c}
    /\ pausedSet' = IF Fault = "ESC_KEEPS_PAUSE" THEN pausedSet ELSE pausedSet \ {c}
    /\ ackReq' = ackReq \ {c}
    /\ fresh' = IF inact \in Paused THEN fresh \cup {c} ELSE fresh
    /\ UNCHANGED <<active, latched, inact, timer, owed, age, booted, heldFor>>
    /\ Annunciate(active, latched, inact, pausedSet', acked', worse', timer)

\* Operator: ACKNOWLEDGE one active condition (silences its sound, not its display).
Ack(c) ==
    /\ c \in active \ acked
    /\ acked' = IF Fault = "ACK_ALL" THEN acked \cup active ELSE acked \cup {c}
    /\ ackReq' = ackReq \cup {c}
    /\ booted' = FALSE
    /\ UNCHANGED <<active, worse, latched, inact, timer, pausedSet, owed, fresh, age, heldFor>>
    /\ Annunciate(active, latched, inact, pausedSet, acked', worse, timer)

\* Operator: ALARM RESET stops latched signals whose cause no longer exists.
Reset ==
    /\ latched' = latched \cap active
    /\ owed' = owed \cap active
    /\ UNCHANGED <<active, worse, inact, timer, pausedSet, acked, fresh, ackReq, age, booted, heldFor>>
    /\ Annunciate(active, latched', inact, pausedSet, acked, worse, timer)

\* Operator: start AUDIO PAUSED or ALARM PAUSED (time-limited).
Pause(kind) ==
    /\ inact = "NONE"
    /\ inact' = kind
    /\ timer' = PauseTicks
    /\ pausedSet' = active \cup latched
    /\ fresh' = {}
    /\ booted' = FALSE
    /\ UNCHANGED <<active, worse, latched, acked, owed, ackReq, age, heldFor>>
    /\ Annunciate(active, latched, kind, pausedSet', acked, worse, timer')

\* Operator: start AUDIO OFF or ALARM OFF (indefinite, with periodic reminders).
Off(kind) ==
    /\ inact = "NONE"
    /\ inact' = kind
    /\ timer' = ReminderTicks
    /\ pausedSet' = {}
    /\ booted' = FALSE
    /\ UNCHANGED <<active, worse, latched, acked, owed, fresh, ackReq, age, heldFor>>
    /\ Annunciate(active, latched, kind, {}, acked, worse, timer')

\* Operator: end whatever inactivation state is in force.
Cancel ==
    /\ inact # "NONE"
    /\ inact' = "NONE"
    /\ timer' = 0
    /\ pausedSet' = {}
    /\ fresh' = {}
    /\ UNCHANGED <<active, worse, latched, acked, owed, ackReq, age, booted, heldFor>>
    /\ Annunciate(active, latched, "NONE", {}, acked, worse, 0)

\* Clock: a pause counts down and ends when it runs out; an OFF state counts down to the
\* next reminder signal; a TimedEscalating condition escalates to HIGH once it has persisted
\* EscalateTicks ticks. Timed escalation is a new event, like detector escalation.
Tick ==
    /\ \/ inact \in Paused /\ timer > 0
       \/ inact \in Offs /\ Fault # "NO_REMINDER"
       \/ Counting # {}
    /\ LET due  == IF Fault = "NO_ESCALATION" THEN {}
                   ELSE {c \in Counting : age[c] + 1 >= EscalateTicks}
           ends == inact \in Paused /\ timer = 1 /\ Fault # "ENDLESS_PAUSE"
       IN  /\ timer' = CASE inact \in Paused /\ timer > 0              -> timer - 1
                          [] inact \in Offs /\ Fault # "NO_REMINDER" ->
                                 IF timer = 0 THEN ReminderTicks ELSE timer - 1
                          [] OTHER                                    -> timer
           /\ inact' = IF ends THEN "NONE" ELSE inact
           /\ worse' = worse \cup due
           /\ age' = IF Fault = "NO_ESCALATION" THEN age   \* the escalation clock freezes
                     ELSE [c \in TimedEscalating |-> IF c \in Counting \ due THEN age[c] + 1 ELSE 0]
           /\ acked' = acked \ due
           /\ ackReq' = ackReq \ due
           /\ pausedSet' = IF ends THEN {} ELSE pausedSet \ due
           /\ fresh' = IF ends THEN {} ELSE IF inact \in Paused THEN fresh \cup due ELSE fresh
    /\ heldFor' = [c \in TimedEscalating |->
                      IF c \in active THEN Min(heldFor[c] + 1, EscalateTicks) ELSE 0]
    /\ UNCHANGED <<active, latched, owed, booted>>
    /\ Annunciate(active, latched, inact', pausedSet', acked', worse', timer')

\* Environment: power is interrupted and restored. The patient's state and latched signals
\* survive; inactivation states, acknowledgements and escalation clocks do not.
\* Design decision. Clause 6.5.5 (provisional) restores the alarm settings after a short
\* interruption. This design keeps all configuration.
PowerCycle ==
    /\ inact' = IF Fault = "PERSIST_SILENCE" THEN inact ELSE "NONE"
    /\ timer' = IF Fault = "PERSIST_SILENCE" THEN timer ELSE 0
    /\ pausedSet' = IF Fault = "PERSIST_SILENCE" THEN pausedSet ELSE {}
    /\ acked' = IF Fault = "PERSIST_SILENCE" THEN acked ELSE {}
    /\ age' = [c \in TimedEscalating |-> 0]
    /\ heldFor' = [c \in TimedEscalating |-> 0]
    /\ fresh' = {} /\ ackReq' = {} /\ booted' = TRUE
    /\ UNCHANGED <<active, worse, latched, owed>>
    /\ Annunciate(active, latched, inact', pausedSet', acked', worse, timer')

Next ==
    \/ \E c \in Conds : CondOn(c) \/ CondOff(c) \/ Escalate(c) \/ Ack(c)
    \/ Reset
    \/ Pause("AUDIO_PAUSED") \/ Pause("ALARM_PAUSED")
    \/ Off("AUDIO_OFF")      \/ Off("ALARM_OFF")
    \/ Cancel
    \/ Tick
    \/ PowerCycle

\* Only the clock is assumed to make progress; the operator and the patient may do anything.
Spec == Init /\ [][Next]_vars /\ WF_vars(Tick)

(***************************************************************************)
(* Requirements.                                                           *)
(***************************************************************************)
TypeOK ==
    /\ active \subseteq Conds /\ worse \subseteq Escalating \cup TimedEscalating
    /\ latched \subseteq Conds /\ inact \in States
    /\ timer \in 0..(IF PauseTicks > ReminderTicks THEN PauseTicks ELSE ReminderTicks)
    /\ pausedSet \subseteq Conds /\ acked \subseteq Conds
    /\ lit \subseteq Conds /\ sounding \subseteq Conds
    /\ tone \in Conds \cup {"NONE"} /\ reminder \in BOOLEAN
    /\ owed \subseteq Latching /\ fresh \subseteq Conds /\ ackReq \subseteq Conds
    /\ age \in [TimedEscalating -> 0..EscalateTicks] /\ booted \in BOOLEAN
    /\ heldFor \in [TimedEscalating -> 0..EscalateTicks]

\* R1. An existing alarm condition is visually indicated, except under ALARM PAUSED
\*     or ALARM OFF. Acknowledging silences sound only. Clause 6.3.2, 6.8.1; 3.4, 3.5, 3.12, 3.13
Visible == \A c \in active : c \in lit \/ inact \in {"ALARM_PAUSED", "ALARM_OFF"}

\* R2. An existing HIGH or MEDIUM priority condition (after escalation) sounds unless
\*     an inactivation state is in force or the operator acknowledged this occurrence.
\*     Clause 6.3.3, 6.8.1; 6.1.2 (LOW may be silent)
Audible == \A c \in active :
              Eff(c, worse) \in {"HIGH", "MEDIUM"} =>
                  c \in sounding \/ inact # "NONE" \/ c \in ackReq

\* R3. A non-latching alarm signal stops once its cause is gone. Clause 6.10
NoStaleSignal == \A c \in (lit \cup sounding) \ active : c \in Latching

\* R4. A latching alarm signal persists until ALARM RESET. Clause 6.10, 6.9; 3.7
LatchHolds == \A c \in owed : c \in lit \/ inact \in {"ALARM_PAUSED", "ALARM_OFF"}

\* R9. A latched HIGH or MEDIUM priority signal sounds until ALARM RESET, unless an
\*     inactivation state is in force. R4 checks the visual signal; R9 checks the auditory
\*     signal. Clause 6.10.
\*     An acknowledgement applies to the conditions that exist. It ends for each condition
\*     when that condition ends (6.8.1, AMD1; Table 5, AMD2). Thus the latched signal of an
\*     acknowledged condition sounds again after the condition ends.
LatchSounds == \A c \in owed \ active :
                  Priority[c] \in {"HIGH", "MEDIUM"} => c \in sounding \/ inact # "NONE"

\* R5. Hazard-derived (ISO 14971 style), not a clause of 60601-1-8: a HIGH priority
\*     condition that begins or escalates during a pause is not silenced by that pause.
NewHighBreaksPause ==
    inact \in Paused =>
        \A c \in (fresh \cap active) \ ackReq : Eff(c, worse) = "HIGH" => c \in sounding

\* R6. AUDIO PAUSED and ALARM PAUSED are time-limited. Clause 3.5, 3.13; 6.8.4
PauseEnds == [](inact \in Paused => <>(inact \notin Paused))

\* R7. While AUDIO OFF or ALARM OFF is in force, reminder signals keep recurring.
\*     Clause 6.8.3. Applies to designs that give reminder signals.
RemindWhileOff == [](inact \in Offs => <>(reminder \/ inact \notin Offs))

\* R8. Hazard-derived, logic-level masking: with one tone generator, the sound played
\*     is never of lower priority than another condition calling for sound.
\*     Acoustic masking between different sounds is not in the scope of this model.
ToneIsTop ==
    /\ sounding = {} <=> tone = "NONE"
    /\ sounding # {} =>
          /\ tone \in sounding
          /\ \A d \in sounding : Rank(Eff(tone, worse)) >= Rank(Eff(d, worse))
\* R10. Hazard-derived; related clause 6.5.5 (recalls: Innokas 2014 start-up; Radiometer 2005 power
\*      cycling): from start-up or a restart until the operator next silences anything,
\*      every existing condition is shown, and HIGH and MEDIUM ones sound.
LiveAfterBoot ==
    booted => \A c \in active :
                  /\ c \in lit
                  /\ Eff(c, worse) \in {"HIGH", "MEDIUM"} => c \in sounding

\* R11. Hazard-derived; a note in clause 6.1.2 recommends escalation (recall: Spacelabs
\*      2022, escalation stopped after approximately 25 days). A TimedEscalating condition
\*      held for EscalateTicks ticks has escalated.
EscalatesOnTime ==
    \A c \in TimedEscalating : c \in active /\ heldFor[c] >= EscalateTicks => c \in worse
=============================================================================
