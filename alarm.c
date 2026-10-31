/* Reference implementation of AlarmSystem.tla. See alarm.h. */
#include "alarm.h"

#define BIT(c) ((alarm_set)1u << (c))

static bool valid(const alarm_sys *s, int c) { return c >= 0 && c < s->n; }

static bool paused(const alarm_sys *s)
{
    return s->inact == ALARM_AUDIO_PAUSED || s->inact == ALARM_ALARM_PAUSED;
}

static bool off(const alarm_sys *s)
{
    return s->inact == ALARM_AUDIO_OFF || s->inact == ALARM_ALARM_OFF;
}

static alarm_set all(const alarm_sys *s)
{
    return s->n == ALARM_MAX_CONDS ? ~(alarm_set)0 : BIT(s->n) - 1;
}

/* Priority after escalation. */
static uint8_t eff(const alarm_sys *s, int c)
{
    return (s->worse & BIT(c)) ? ALARM_HIGH : s->prio[c];
}

/* Outputs from state. A pause applies to the conditions signalled when it
 * started; an acknowledgement to one occurrence; the OFF states to everything.
 * The tone generator plays the highest priority, ties to the lowest number. */
static void annunciate(alarm_sys *s)
{
    alarm_set signalled = s->active | s->latched;
    alarm_set muted = s->acked, hidden = 0;

    switch (s->inact) {
    case ALARM_AUDIO_OFF:    muted = all(s); break;
    case ALARM_ALARM_OFF:    muted = all(s); hidden = all(s); break;
    case ALARM_AUDIO_PAUSED: muted |= s->paused_set; break;
    case ALARM_ALARM_PAUSED: muted |= s->paused_set; hidden = s->paused_set; break;
    default: break;
    }

    s->lit = signalled & ~hidden;
    s->sounding = 0;
    s->tone = -1;
    for (int c = 0; c < s->n; c++) {
        if (!(signalled & ~muted & BIT(c)))
            continue;
        if (eff(s, c) == ALARM_LOW && !s->low_audible)
            continue;
        s->sounding |= BIT(c);
        if (s->tone < 0 || eff(s, c) > eff(s, s->tone))
            s->tone = (int8_t)c;
    }
    s->reminder = off(s) && s->timer == 0;
}

bool alarm_init(alarm_sys *s)
{
    if (s->n < 1 || s->n > ALARM_MAX_CONDS || s->pause_ticks < 1 || s->reminder_ticks < 1)
        return false;
    for (int c = 0; c < s->n; c++)
        if (s->prio[c] < ALARM_LOW || s->prio[c] > ALARM_HIGH)
            return false;
    if (s->escalate_ticks < 1 || ((s->latching | s->escalating | s->timed_escalating | s->active) & ~all(s)))
        return false;

    s->worse = 0;
    s->latched = s->active & s->latching;
    s->paused_set = s->acked = 0;
    s->inact = ALARM_INACT_NONE;
    s->timer = 0;
    for (int c = 0; c < ALARM_MAX_CONDS; c++)
        s->age[c] = 0;
    annunciate(s);
    return true;
}

bool alarm_cond_on(alarm_sys *s, int c)
{
    if (!valid(s, c) || (s->active & BIT(c)))
        return false;
    s->active |= BIT(c);
    if (s->latching & BIT(c))
        s->latched |= BIT(c);
    s->paused_set &= ~BIT(c); /* a new occurrence is not covered by an earlier pause */
    annunciate(s);
    return true;
}

bool alarm_cond_off(alarm_sys *s, int c)
{
    if (!valid(s, c) || !(s->active & BIT(c)))
        return false;
    s->active &= ~BIT(c);
    s->worse &= ~BIT(c);
    s->acked &= ~BIT(c); /* the acknowledgement ends with the occurrence */
    s->age[c] = 0;
    annunciate(s);
    return true;
}

bool alarm_escalate(alarm_sys *s, int c)
{
    if (!valid(s, c) || !(s->active & s->escalating & ~s->worse & BIT(c)))
        return false;
    s->worse |= BIT(c);
    s->acked &= ~BIT(c);      /* escalation is a new event: neither an earlier */
    s->paused_set &= ~BIT(c); /* acknowledgement nor an earlier pause covers it */
    annunciate(s);
    return true;
}

bool alarm_ack(alarm_sys *s, int c)
{
    if (!valid(s, c) || !(s->active & ~s->acked & BIT(c)))
        return false;
    s->acked |= BIT(c);
    annunciate(s);
    return true;
}

bool alarm_reset(alarm_sys *s)
{
    s->latched &= s->active;
    annunciate(s);
    return true;
}

bool alarm_pause(alarm_sys *s, int kind)
{
    if (s->inact != ALARM_INACT_NONE || (kind != ALARM_AUDIO_PAUSED && kind != ALARM_ALARM_PAUSED))
        return false;
    s->inact = (uint8_t)kind;
    s->timer = s->pause_ticks;
    s->paused_set = s->active | s->latched;
    annunciate(s);
    return true;
}

bool alarm_off(alarm_sys *s, int kind)
{
    if (s->inact != ALARM_INACT_NONE || (kind != ALARM_AUDIO_OFF && kind != ALARM_ALARM_OFF))
        return false;
    s->inact = (uint8_t)kind;
    s->timer = s->reminder_ticks;
    s->paused_set = 0;
    annunciate(s);
    return true;
}

bool alarm_cancel(alarm_sys *s)
{
    if (s->inact == ALARM_INACT_NONE)
        return false;
    s->inact = ALARM_INACT_NONE;
    s->timer = 0;
    s->paused_set = 0;
    annunciate(s);
    return true;
}

bool alarm_tick(alarm_sys *s)
{
    alarm_set counting = s->active & s->timed_escalating & ~s->worse, due = 0;

    if (!(paused(s) && s->timer > 0) && !off(s) && !counting)
        return false;
    /* age never exceeds escalate_ticks, so a long-running device cannot wrap it */
    for (int c = 0; c < s->n; c++) {
        if (!(counting & BIT(c))) {
            s->age[c] = 0;
        } else if (++s->age[c] >= s->escalate_ticks) {
            s->age[c] = 0;
            due |= BIT(c);
        }
    }
    if (paused(s) && s->timer > 0) {
        if (--s->timer == 0) {
            s->inact = ALARM_INACT_NONE;
            s->paused_set = 0;
        }
    } else if (off(s)) {
        s->timer = s->timer == 0 ? s->reminder_ticks : (uint16_t)(s->timer - 1);
    }
    s->worse |= due;
    s->acked &= ~due;      /* timed escalation is a new event, like alarm_escalate */
    s->paused_set &= ~due;
    annunciate(s);
    return true;
}

bool alarm_power_cycle(alarm_sys *s)
{
    s->inact = ALARM_INACT_NONE;
    s->timer = 0;
    s->paused_set = s->acked = 0;
    for (int c = 0; c < ALARM_MAX_CONDS; c++)
        s->age[c] = 0;
    annunciate(s);
    return true;
}

size_t alarm_sys_size(void) { return sizeof(alarm_sys); }
