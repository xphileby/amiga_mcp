/*
 * Metroid Quest - Input: Joystick port 2 + keyboard
 */
#include <hardware/custom.h>
#include <hardware/cia.h>
#include "input.h"

/* Hardware registers */
extern volatile struct Custom custom;
extern volatile struct CIA ciaa;

/* Keyboard state */
static UWORD key_state = 0;

void input_key_down(UWORD code)
{
    switch (code) {
        case 0x4F: key_state |= INPUT_LEFT;  break;  /* cursor left */
        case 0x4E: key_state |= INPUT_RIGHT; break;  /* cursor right */
        case 0x4C: key_state |= INPUT_UP;    break;  /* cursor up */
        case 0x4D: key_state |= INPUT_DOWN;  break;  /* cursor down */
        case 0x20: key_state |= INPUT_LEFT;  break;  /* A */
        case 0x22: key_state |= INPUT_RIGHT; break;  /* D */
        case 0x11: key_state |= INPUT_UP;    break;  /* W */
        case 0x31: key_state |= INPUT_DOWN;  break;  /* S (actually Z key, reuse for down) */
        case 0x60: key_state |= INPUT_FIRE;  break;  /* left alt (fire) */
        case 0x64: key_state |= INPUT_FIRE;  break;  /* right alt */
        case 0x40: key_state |= INPUT_FIRE;  break;  /* space */
        case 0x45: key_state |= INPUT_ESC;   break;  /* escape */
        case 0x44: key_state |= INPUT_START; break;  /* return */
    }
}

void input_key_up(UWORD code)
{
    switch (code) {
        case 0x4F: key_state &= ~INPUT_LEFT;  break;
        case 0x4E: key_state &= ~INPUT_RIGHT; break;
        case 0x4C: key_state &= ~INPUT_UP;    break;
        case 0x4D: key_state &= ~INPUT_DOWN;  break;
        case 0x20: key_state &= ~INPUT_LEFT;  break;
        case 0x22: key_state &= ~INPUT_RIGHT; break;
        case 0x11: key_state &= ~INPUT_UP;    break;
        case 0x31: key_state &= ~INPUT_DOWN;  break;
        case 0x60: key_state &= ~INPUT_FIRE;  break;
        case 0x64: key_state &= ~INPUT_FIRE;  break;
        case 0x40: key_state &= ~INPUT_FIRE;  break;
        case 0x45: key_state &= ~INPUT_ESC;   break;
        case 0x44: key_state &= ~INPUT_START; break;
    }
}

void input_reset(void)
{
    key_state = 0;
}

UWORD input_read(void)
{
    UWORD result = key_state;
    UWORD joy;

    /* Read joystick port 2 (JOY1DAT register) */
    joy = custom.joy1dat;

    /* Joystick decoding for digital joystick:
     * JOY1DAT low byte = X counter, high byte = Y counter.
     * For a digital joystick:
     *   Right: bit1=1, bit0=0  (low byte = 0x02)
     *   Left:  bit1=0, bit0=1  (low byte = 0x01)
     *   Down:  bit9=1, bit8=0  (high byte = 0x02)
     *   Up:    bit9=0, bit8=1  (high byte = 0x01)
     */
    {
        UWORD h = joy & 3;        /* horizontal bits */
        UWORD v = (joy >> 8) & 3; /* vertical bits */

        if (h == 2) result |= INPUT_RIGHT;
        if (h == 1) result |= INPUT_LEFT;
        if (v == 1) result |= INPUT_UP;
        if (v == 2) result |= INPUT_DOWN;
    }

    /* Fire button: CIA-A PRA bit 7, active low (port 2) */
    if (!(ciaa.ciapra & 0x80))
        result |= INPUT_FIRE;

    return result;
}
