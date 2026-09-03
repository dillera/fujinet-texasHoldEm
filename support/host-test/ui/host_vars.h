/* Host mock platform defines (force-included before the shared sources).
 * Mirrors the Apple II 40x25 layout so the shared code renders identically. */
#ifndef HOST_VARS_H
#define HOST_VARS_H

#define _Packed
#define HOST_UI_TEST

/* not in the host libc */
char *itoa(int value, char *str, int base);

#ifdef HOST_COCO32
/* CoCo 1/2: 32-column hires layout */
#define WIDTH 32
#define HEIGHT 24
#define SINGLE_BUFFER_MODE 1
#define PLAYER_MOVE_START_X 0
#define LEFT_JUSTIFY_PLAYER_PURSE 99
#define STATUS_TIMER_WIDTH 1
#else
#define WIDTH 40
#ifdef HOST_COCO3
#define HEIGHT 24
#define SINGLE_BUFFER_MODE 1
#else
#define HEIGHT 25
#endif
/* matches the default in gamelogic.c; the menu test needs it too */
#define STATUS_TIMER_WIDTH 2
#endif
#define QUERY_SUFFIX ""
#define POT_Y_MODIFIER 3

/* mirrors gamelogic.c so the seat-overlap check measures the real field */
#if WIDTH >= 40
#define MOVE_FIELD_W 5
#else
#define MOVE_FIELD_W 4
#endif

/* mirrors the default in gamelogic.c so the menu test can locate the entries */
#ifndef PLAYER_MOVE_START_X
#define PLAYER_MOVE_START_X 1
#endif

/* drawPot() boxes the total at drawBox(WIDTH/2-3, ...), whose frame corners
   land here; the border must survive whatever the seats draw nearby. */
#define POT_BOX_X (WIDTH / 2 - 5)
#define POT_BOX_TOP_Y (11 + POT_Y_MODIFIER)
#define POT_BOX_BOTTOM_Y (POT_BOX_TOP_Y + 2)

#define KEY_LEFT_ARROW 1
#define KEY_RIGHT_ARROW 2
#define KEY_UP_ARROW 3
#define KEY_DOWN_ARROW 4
#define KEY_RETURN 13
#define KEY_ESCAPE 27
#define KEY_ESCAPE_ALT 26
#define KEY_BACKSPACE 8
#define KEY_SPACE 32

#endif
