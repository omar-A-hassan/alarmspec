/* Reference implementation of the alarm system in AlarmSystem.tla.
 *
 * conformance.py compares this implementation with the model in each reachable
 * state and on each transition, in both directions.
 *
 * Conditions have the numbers 0..n-1. The number is also the tone tie-break order
 * (Index in the model). Sets of conditions are bit masks. The code uses no dynamic
 * memory.
 */
#ifndef ALARM_H
#define ALARM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define ALARM_MAX_CONDS 32

typedef uint32_t alarm_set; /* bit c set = condition c is a member */

enum { ALARM_LOW = 1, ALARM_MEDIUM = 2, ALARM_HIGH = 3 };

enum {
    ALARM_INACT_NONE,
    ALARM_AUDIO_PAUSED,
    ALARM_ALARM_PAUSED,
    ALARM_AUDIO_OFF,
    ALARM_ALARM_OFF
};

typedef struct {
    /* Configuration: set before alarm_init, constant afterwards. */
    uint8_t   n;                     /* number of conditions, 1..ALARM_MAX_CONDS */
    uint8_t   prio[ALARM_MAX_CONDS]; /* priority before escalation */
    alarm_set latching;              /* conditions whose signals latch */
    alarm_set escalating;            /* conditions the detector can escalate to HIGH */
    alarm_set timed_escalating;      /* conditions this system escalates to HIGH after escalate_ticks */
    uint16_t  pause_ticks;           /* length of a pause, >= 1 */
    uint16_t  reminder_ticks;        /* ticks between reminders in an OFF state, >= 1 */
    uint16_t  escalate_ticks;        /* ticks a timed_escalating condition persists before escalating, >= 1 */
    bool      low_audible;           /* true: LOW priority conditions sound */

    /* Inputs: the patient's state, as reported by the detection layer. */
    alarm_set active;                /* conditions whose cause exists; may be nonempty at alarm_init */
    alarm_set worse;                 /* active conditions escalated to HIGH, by the detector or by time */

    /* Design state. */
    alarm_set latched;               /* latched signals whose cause may have ended */
    alarm_set paused_set;            /* conditions the current pause applies to */
    alarm_set acked;                 /* acknowledged occurrences */
    uint8_t   inact;                 /* ALARM_INACT_NONE .. ALARM_ALARM_OFF */
    uint16_t  timer;                 /* ticks left in a pause, or to the next reminder */
    uint16_t  age[ALARM_MAX_CONDS];  /* ticks a timed_escalating condition has persisted unescalated */

    /* Outputs, recomputed after every accepted event. */
    alarm_set lit;                   /* visual alarm signals */
    alarm_set sounding;              /* conditions calling for sound */
    int8_t    tone;                  /* condition the tone generator plays, -1 = none */
    bool      reminder;              /* true: give a reminder signal */
} alarm_sys;

/* Checks the configuration. Clears all state except active, the conditions present at
 * start-up, and annunciates them. Returns false if the configuration is not valid. */
bool alarm_init(alarm_sys *s);

/* Events. Each returns false, leaving *s untouched, if the event is not allowed
 * in the current state or its argument is out of range. */
bool alarm_cond_on(alarm_sys *s, int c);   /* a cause appears */
bool alarm_cond_off(alarm_sys *s, int c);  /* a cause disappears */
bool alarm_escalate(alarm_sys *s, int c);  /* a persisting condition becomes HIGH */
bool alarm_ack(alarm_sys *s, int c);       /* operator: ACKNOWLEDGE */
bool alarm_reset(alarm_sys *s);            /* operator: ALARM RESET */
bool alarm_pause(alarm_sys *s, int kind);  /* operator: ALARM_AUDIO_PAUSED or ALARM_ALARM_PAUSED */
bool alarm_off(alarm_sys *s, int kind);    /* operator: ALARM_AUDIO_OFF or ALARM_ALARM_OFF */
bool alarm_cancel(alarm_sys *s);           /* operator: end the inactivation state */
bool alarm_tick(alarm_sys *s);             /* clock */

/* Restart after a power interruption. Before the call, restore the configuration, the
 * inputs and latched from non-volatile memory. The call clears the inactivation state,
 * the acknowledgements and the escalation clocks. Returns true. */
bool alarm_power_cycle(alarm_sys *s);

/* sizeof(alarm_sys), so foreign-function bindings can check their layout. */
size_t alarm_sys_size(void);

#endif
