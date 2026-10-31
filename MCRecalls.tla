---- MODULE MCRecalls ----
\* Recall scripts, paraphrased from FDA recall reason statements (openFDA, 2026-10-30).
\* Same conditions as MC.tla: h1 HIGH latching, h2 HIGH, m1 MEDIUM latching escalating, l1 LOW.
EXTENDS MC, Recalls

NoneActive == {}

\* Draeger 2013-12-10: a medium SpO2 alarm was paused; SpO2 then fell to the life-threatening
\* limit and the high alarm did not activate. Two readings: the same condition escalates, or a
\* separate high condition begins.
DragerEscalates == << <<"CondOn", m1>>, <<"Pause", "AUDIO_PAUSED">>, <<"Escalate", m1>> >>
DragerSeparate  == << <<"CondOn", m1>>, <<"Pause", "AUDIO_PAUSED">>, <<"CondOn", h2>> >>

\* Terumo 2006-10-16: the pump stopped without an audible tone because the alarm condition
\* cleared quickly. Replayed assuming the condition is latching; the generation delay that
\* made it "quick" is not modelled.
TerumoTransient == << <<"CondOn", h1>>, <<"CondOff", h1>> >>

\* GE 2006 (CIC and ApexPro central stations): with a lower-level alarm already present, the
\* higher-level alarm did not annunciate. A distributed-system recall; only the arbitration
\* mechanism is replayed here, on a single device with LOW alarms audible.
GEMasking == << <<"CondOn", l1>>, <<"CondOn", h2>> >>

\* Innokas 2014-12-03: a limit already violated when monitoring starts raised no alarm.
\* Start-up with h2 present; no events needed.
InnokasStart   == {h2}
InnokasStartup == << >>

\* Radiometer 2005-02-02: rapid power off/on left the alarm silent when it later tripped.
\* Interpretation: a silence state survives the restart.
RadiometerRestart == << <<"Off", "AUDIO_OFF">>, <<"PowerCycle">>, <<"CondOn", h2>> >>

\* Spacelabs 2022-05-31: technical alarm escalation stopped occurring (after ~25 days).
\* l1 is LOW and must escalate after EscalateTicks = 2 ticks.
SpacelabsEscalation == << <<"CondOn", l1>>, <<"Tick">>, <<"Tick">> >>
====
