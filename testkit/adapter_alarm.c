/* Adapter for the reference implementation alarm.c: the worked example for adapter.h. */
#include <stdlib.h>
#include <string.h>

#include "adapter.h"
#include "../alarm.h"

static alarm_sys s;

void ta_init(const ta_config *cfg, uint32_t active)
{
    memset(&s, 0, sizeof s); /* zeroes padding too, so snapshots compare byte for byte */
    s.n = (uint8_t)cfg->n;
    memcpy(s.prio, cfg->priority, sizeof s.prio); /* TA_ and ALARM_ priorities agree */
    s.latching = cfg->latching;
    s.escalating = cfg->escalating;
    s.timed_escalating = cfg->timed;
    s.pause_ticks = (uint16_t)cfg->pause_ticks;
    s.reminder_ticks = (uint16_t)cfg->reminder_ticks;
    s.escalate_ticks = (uint16_t)cfg->escalate_ticks;
    s.low_audible = cfg->low_audible;
    s.active = active;
    if (!alarm_init(&s))
        abort(); /* alarm.c rejected the configuration */
}

void ta_event(int event, int arg)
{
    switch (event) {
    case TA_COND_ON:     alarm_cond_on(&s, arg); break;
    case TA_COND_OFF:    alarm_cond_off(&s, arg); break;
    case TA_ESCALATE:    alarm_escalate(&s, arg); break;
    case TA_ACK:         alarm_ack(&s, arg); break;
    case TA_RESET:       alarm_reset(&s); break;
    case TA_PAUSE:       alarm_pause(&s, arg); break; /* TA_ and ALARM_ state numbers agree */
    case TA_OFF:         alarm_off(&s, arg); break;
    case TA_CANCEL:      alarm_cancel(&s); break;
    case TA_TICK:        alarm_tick(&s); break;
    case TA_POWER_CYCLE: alarm_power_cycle(&s); break;
    default: break;
    }
}

void ta_outputs(uint32_t *lit, uint32_t *sounding, int *tone, bool *reminder)
{
    *lit = s.lit;
    *sounding = s.sounding;
    *tone = s.tone;
    *reminder = s.reminder;
}

size_t ta_state_size(void) { return sizeof s; }
void ta_save(void *buf) { memcpy(buf, &s, sizeof s); }
void ta_load(const void *buf) { memcpy(&s, buf, sizeof s); }
