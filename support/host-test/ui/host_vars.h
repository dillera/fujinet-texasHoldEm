/* Host mock platform defines (force-included before the shared sources).
 * Mirrors the Apple II 40x25 layout so the shared code renders identically. */
#ifndef HOST_VARS_H
#define HOST_VARS_H

#define _Packed
#define HOST_UI_TEST

/* not in the host libc */
char *itoa(int value, char *str, int base);

#define WIDTH 40
#ifdef HOST_COCO3
#define HEIGHT 24
#define SINGLE_BUFFER_MODE 1
#else
#define HEIGHT 25
#endif
#define QUERY_SUFFIX ""
#define POT_Y_MODIFIER 3

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
