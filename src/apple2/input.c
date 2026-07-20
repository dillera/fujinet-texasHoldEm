#ifdef __APPLE2__

#include <joystick.h>

/* Lazily install cc65's static joystick driver (reads the analog stick via
 * the ROM paddle routines). If no joystick is present the install still
 * succeeds and the stick just reads centered; keyboard input is unaffected. */
static unsigned char joyState = 0; /* 0 = not tried, 1 = ok, 2 = unavailable */

unsigned char readJoystick() {
  if (joyState == 0) {
    joyState = (joy_install(joy_static_stddrv) == JOY_ERR_OK) ? 1 : 2;
  }
  if (joyState != 1) {
    return 0;
  }
  return joy_read(JOY_1);
}

#endif /* __APPLE2__ */
