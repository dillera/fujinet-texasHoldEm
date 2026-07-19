/* Mock platform layer: renders the shared client code into a char grid so the
 * exact table layout can be inspected on the host. Cards are drawn as 2-wide
 * markers occupying 5 rows, like the real platforms. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "../../../src/platform-specific/graphics.h"
#include "../../../src/platform-specific/util.h"
#include "../../../src/platform-specific/sound.h"
#include "../../../src/platform-specific/appkey.h"

char screen[HEIGHT][WIDTH + 1];
bool always_render_full_cards = true;
unsigned char colorMode = 1;

static void put(unsigned char x, unsigned char y, char c) {
  if (x < WIDTH && y < HEIGHT)
    screen[y][x] = c;
}

void dumpScreen(const char *label) {
  int r, c;
  printf("--- %s\n", label);
  printf("    0123456789012345678901234567890123456789\n");
  for (r = 0; r < HEIGHT; r++) {
    /* trim trailing spaces for readability */
    char row[WIDTH + 1];
    memcpy(row, screen[r], WIDTH);
    row[WIDTH] = 0;
    for (c = WIDTH - 1; c >= 0 && row[c] == ' '; c--) row[c] = 0;
    printf("%2d|%s\n", r, row);
  }
}

void resetScreen() {
  int r, c;
  for (r = 0; r < HEIGHT; r++) {
    for (c = 0; c < WIDTH; c++) screen[r][c] = ' ';
    screen[r][WIDTH] = 0;
  }
}

void enableDoubleBuffer() {}
void disableDoubleBuffer() {}
void drawBuffer() {}
void clearStatusBar() {
  int c;
  for (c = 0; c < WIDTH; c++) screen[HEIGHT - 1][c] = ' ';
}
void drawStatusTextAt(unsigned char x, const char *s) {
  while (*s) put(x++, HEIGHT - 1, *s++);
}
void drawStatusText(const char *s) { clearStatusBar(); drawStatusTextAt(0, s); }
void drawStatusTimer() {}
void drawTextAt(unsigned char x, unsigned char y, const char *s) {
  while (*s) put(x++, y / 8, *s++);
}
void drawText(unsigned char x, unsigned char y, const char *s) {
  while (*s) {
    char c = *s++;
    if (c >= 'a' && c <= 'z') c -= 32;
    put(x++, y, c);
  }
}
/* A card: 2 columns x 5 rows. Top/bottom edges '#', middle rows carry the
 * rank/suit or '?' for face-down. */
void drawCard(unsigned char x, unsigned char y, unsigned char partial, const char *s, unsigned char isHidden) {
  unsigned char r;
  (void)partial;
  for (r = 0; r < 5; r++) {
    char l = '#', rr = '#';
    if (r == 1) { l = isHidden ? '?' : s[0]; rr = isHidden ? '?' : s[1]; }
    if (r == 2 || r == 3) { l = '#'; rr = '#'; }
    if (l >= 'a' && l <= 'z') l -= 32;
    if (rr >= 'a' && rr <= 'z') rr -= 32;
    put(x, y + r, l);
    put(x + 1, y + r, rr);
  }
}
void drawChip(unsigned char x, unsigned char y) { put(x, y, 'o'); }
void drawBlank(unsigned char x, unsigned char y) { put(x, y, ' '); }
void drawLine(unsigned char x, unsigned char y, unsigned char w) {
  while (w--) put(x++, y, '_');
}
void hideLine(unsigned char x, unsigned char y, unsigned char w) {
  while (w--) put(x++, y, ' ');
}
void drawBox(unsigned char x, unsigned char y, unsigned char w, unsigned char h) {
  unsigned char c;
  for (c = 0; c <= w; c++) { put(x + c, y, '-'); put(x + c, y + h + 1, '-'); }
  put(x - 1, y, '+'); put(x + w + 1, y, '+');
  for (c = 1; c <= h; c++) { put(x - 1, y + c, '|'); put(x + w + 1, y + c, '|'); }
  put(x - 1, y + h + 1, '+'); put(x + w + 1, y + h + 1, '+');
}
void drawBorder() {}
void drawLogo() {}
void initGraphics() { resetScreen(); }
void resetGraphics() {}
void waitvsync() {}
uint8_t cycleNextColor() { return 0; }
void setColorMode() {}

char *itoa(int value, char *str, int base) {
  (void)base;
  sprintf(str, "%d", value);
  return str;
}

/* util */
static int mockTime = 0;
void resetTimer() { mockTime = 0; }
int getTime() { return mockTime += 100000; } /* expire timers instantly */
void quit() {}

/* sound */
void initSound() {}
void soundDealCard() {}
void soundCursor() {}
void soundCursorInvalid() {}
void soundSelectMove() {}
void soundMyTurn() {}
void soundGameDone() {}
void soundJoinGame() {}
void soundPlayerJoin() {}
void soundPlayerLeft() {}
void soundTakeChip(uint16_t counter) { (void)counter; }
void soundTick() {}

/* appkey */
void read_appkey(unsigned int creator_id, unsigned char app_id, unsigned char key_id, char *data) {
  (void)creator_id; (void)app_id; (void)key_id; data[0] = 0;
}
void write_appkey(unsigned int creator_id, unsigned char app_id, unsigned char key_id, const char *data) {
  (void)creator_id; (void)app_id; (void)key_id; (void)data;
}
