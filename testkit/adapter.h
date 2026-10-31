/* Interface between the black-box test (blackbox.py) and an alarm-logic implementation.
 *
 * 1. Write one C file that implements the 6 functions below. Each function calls your code.
 * 2. Describe your alarm system in a copy of alarm.toml.
 * 3. Run:
 *     ALARM_CONFIG=my_alarm.toml JAVA=/path/to/java \
 *         uv run --no-project python blackbox.py my_adapter.c your_sources.c ...
 * The test makes the model for your configuration. It fires each event of the model on
 * your code, and compares your outputs with the outputs of the model. It does not read
 * the internal state of your code.
 * testkit/adapter_alarm.c is the adapter for the reference implementation alarm.c.
 * One tick is one clock period of your code: TA_TICK advances its time by that period.
 */
#ifndef TESTKIT_ADAPTER_H
#define TESTKIT_ADAPTER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Events, with their arg. Condition events take the condition number 0..n-1. */
enum {
    TA_COND_ON,     /* the cause of condition arg appears */
    TA_COND_OFF,    /* the cause of condition arg disappears */
    TA_ESCALATE,    /* the detector escalates condition arg to HIGH */
    TA_ACK,         /* operator acknowledges condition arg */
    TA_RESET,       /* operator: ALARM RESET */
    TA_PAUSE,       /* operator starts arg: TA_AUDIO_PAUSED or TA_ALARM_PAUSED */
    TA_OFF,         /* operator starts arg: TA_AUDIO_OFF or TA_ALARM_OFF */
    TA_CANCEL,      /* operator ends the inactivation state in force */
    TA_TICK,        /* one clock period passes */
    TA_POWER_CYCLE  /* power is interrupted and restored */
};
enum { TA_AUDIO_PAUSED = 1, TA_ALARM_PAUSED, TA_AUDIO_OFF, TA_ALARM_OFF };
enum { TA_LOW = 1, TA_MEDIUM, TA_HIGH };

/* The alarm system to set up, from the .toml file. Conditions are numbered 0..n-1 in file
 * order; between equal priorities the tone plays the lower number. Sets of conditions are
 * bit masks (bit c = condition c). */
typedef struct {
    int      n;              /* number of conditions, 1..32 */
    uint8_t  priority[32];   /* TA_LOW, TA_MEDIUM or TA_HIGH, before any escalation */
    uint32_t latching;       /* conditions whose signals latch until ALARM RESET */
    uint32_t escalating;     /* conditions the detector can escalate to HIGH */
    uint32_t timed;          /* conditions escalated to HIGH after escalate_ticks unresolved */
    int      pause_ticks;    /* length of AUDIO PAUSED and ALARM PAUSED */
    int      reminder_ticks; /* interval between reminders in AUDIO OFF and ALARM OFF */
    int      escalate_ticks;
    bool     low_audible;    /* true: LOW priority conditions sound */
} ta_config;

/* Start-up: a fresh alarm system set up as *cfg, with the conditions in `active` already
 * present. If your code fixes some of these settings at build time, check that they
 * match *cfg and abort if they do not. */
void ta_init(const ta_config *cfg, uint32_t active);

/* Fire one event. An event your code ignores or refuses must leave its state unchanged. */
void ta_event(int event, int arg);

/* Current outputs. lit: conditions with a visual signal. sounding: conditions that call
 * for an auditory signal. tone: the condition that the tone generator plays, -1 for none.
 * reminder: true if a reminder signal is given. lit and sounding are bit masks. */
void ta_outputs(uint32_t *lit, uint32_t *sounding, int *tone, bool *reminder);

/* Snapshot and restore of your alarm-logic state. The test uses snapshots to fire each
 * event from each state without replay. Do not include logs or free-running clocks. Two
 * snapshots must be equal byte for byte if, and only if, your code behaves the same from
 * them. */
size_t ta_state_size(void);
void ta_save(void *buf);
void ta_load(const void *buf);

#endif
