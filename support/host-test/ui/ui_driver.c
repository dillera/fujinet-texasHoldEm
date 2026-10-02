/* Host UI reproduction driver: replays a hand's frames through the REAL shared
 * rendering code (src/gamelogic.c) with a mock text-grid platform, printing the
 * table after each frame. Used to hunt down layout/clearing bugs without an
 * emulator.
 *
 * Build & run from repo root:
 *   cc -I support/host-test/ui -include support/host-test/ui/host_vars.h \
 *      src/gamelogic.c support/host-test/ui/mock_platform.c \
 *      support/host-test/ui/ui_driver.c -o /tmp/ui_test && /tmp/ui_test
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "../../../src/misc.h"
#include "../../../src/gamelogic.h"

/* ---- globals normally defined in main.c / misc.c ---- */
char serverEndpoint[50] = "";
char query[50] = "";
char playerName[12] = "you";
ClientState clientState;
char inputKey;
unsigned char prevPlayerCount, prevRound, currentCard, cardIndex,
    cursorX, cursorY, waitCount, wasViewing;
signed char inputDirX, inputDirY;
uint16_t prevPot, maxJifs;
bool noAnim, doAnim, finalFlip, inputTrigger;
char tempBuffer[128];
unsigned char h, i, j, k, x, y, xx;
unsigned char playerX[8], playerY[8], moveLoc[5];
signed char playerBetX[8], playerBetY[8], playerDir[8];
char *hand, *requestedMove;
char prefs[4];

#ifdef HOST_ADAM
/* Adam 32x24 master layout (mirror of src/adam/vars.c) */
unsigned char playerXMaster[] = { 11, 0, 0, 0, 11, 30, 30, 30 };
unsigned char playerYMaster[] = { 18, 18, 9, 2, 2, 2, 9, 18 };
char playerDirMaster[] = { 1,1,1,1,1,-1,-1,-1 };
char playerBetXMaster[] = { -3, 10, 1, 10, 3, -8, -1, -8 };
char playerBetYMaster[] = { -3, -3, 4, 4, 4, 4, 4, -3 };
#elif defined(HOST_COCO32)
/* CoCo 1/2 master layout (mirror of src/coco/vars.c, non-COCO3 branch) */
unsigned char playerXMaster[] = { 11,0, 0, 0, 11, 30,30, 30 };
unsigned char playerYMaster[] = { 18, 18,10,2, 2, 2,10,18 };
char playerDirMaster[] = { 1,1,1,1,1,-1,-1,-1 };
char playerBetXMaster[] = { 8,6,5,6,3,-6,-4,-3 };
char playerBetYMaster[] = { -3, -3, 3,5,5,5,3,-3 };
#elif defined(HOST_COCO3)
/* CoCo 3 master layout (mirror of src/coco/vars.c) */
unsigned char playerXMaster[] = { 17,1, 1, 1, 16, 37,37, 37 };
unsigned char playerYMaster[] = { 18, 18,10,2, 2, 2,10,18 };
char playerDirMaster[] = { 1,1,1,1,1,-1,-1,-1 };
char playerBetXMaster[] = { 7,10,8,10,3,-8,-3,-4 };
char playerBetYMaster[] = { -2, -2, 1,5,5,5,1,-3 };
#else
/* Apple II master layout (mirror of src/apple2/util.c) */
unsigned char playerXMaster[] = { 17,1, 1, 1, 15, 37,37, 37 };
unsigned char playerYMaster[] = { 18, 17, 10, 3, 3,3,10,17 };
char playerDirMaster[] = { 1,1,1,1,1,-1,-1,-1 };
char playerBetXMaster[] = { 7,10,8,10,4,-8,-3,-4 };
char playerBetYMaster[] = { -2, -2, 1,4,4,4,1,-3 };
#endif
char playerCountIndex[] = {0,4,0,0,0,0,0,0, 0,2,6,0,0,0,0,0, 0,2,4,6,0,0,0,0,
   0,2,3,5,6,0,0,0, 0,2,3,4,5,6,0,0,  0,2,3,4,5,6,7,0, 0,1,2,3,4,5,6,7};

/* ---- stubs for misc.c / screens.c pieces gamelogic references ---- */
void pause(unsigned char frames) { (void)frames; }
void clearCommonInput() { inputKey = 0; inputDirX = inputDirY = 0; inputTrigger = false; }
void readCommonInput() {}
void loadPrefs() {}
void savePrefs() {}
void showInGameMenuScreen() {}
void centerStatusText(const char *t) { drawStatusText(t); }

/* from mock_platform.c */
void dumpScreen(const char *label);
extern char screen[HEIGHT][WIDTH + 1];

unsigned char redrawGameScreen = 1; /* normally defined in screens.c */

/* Replicates showGameScreen() from src/screens.c (non-SINGLE_BUFFER path) */
static void frame(const char *label) {
#ifndef SINGLE_BUFFER_MODE
  redrawGameScreen = 1; /* apple2: full redraw every frame */
#endif

  checkIfSpectatorStatusChanged();
  checkIfPlayerCountChanged();
  animateChipsToPotOnRoundEnd();
  checkFinalFlip();

  if (redrawGameScreen) resetScreen();
  resetStateIfNewGame();

  drawPot();
  drawStreetLabel();

  if (state.playerCount > 1) {
    drawNamePurse();
    drawBets();
#ifdef SINGLE_BUFFER_MODE
    if (state.round < 5) drawCards(false);
#else
    drawCards(false);
#endif
  }

  drawGameStatus();
  drawBuffer();
  highlightActivePlayer();
#ifdef SINGLE_BUFFER_MODE
  redrawGameScreen = 0;
#endif
  prevRound = state.round;

  dumpScreen(label);
}

static void setPlayer(int n, const char *name, int status, int bet,
                      const char *move, int purse, const char *handStr) {
  strcpy(state.players[n].name, name);
  state.players[n].status = (uint8_t)status;
  state.players[n].bet = (uint16_t)bet;
  strcpy(state.players[n].move, move);
  state.players[n].purse = (uint16_t)purse;
  strcpy(state.players[n].hand, handStr);
}

static int expect(int row, int col, const char *want, const char *what) {
  if (strncmp(&screen[row][col], want, strlen(want)) != 0) {
    char got[16];
    strncpy(got, &screen[row][col], strlen(want));
    got[strlen(want)] = 0;
    printf("FAIL: %s: expected \"%s\" at (%d,%d), got \"%s\"\n", what, want, col, row, got);
    return 1;
  }
  printf("ok: %s\n", what);
  return 0;
}

/* Every seat's move and bet text must stay clear of every other seat's, at
 * every player count. Seats are reassigned as players join, so a layout that
 * is clean four-handed can still collide seven-handed - which is exactly how
 * the bottom seat ended up drawn on top of the bottom-right one. */
static int checkSeatOverlaps(void) {
  static const char *kind[4] = {"move", "bet", "name", "purse"};
  unsigned char count, n, seat[8];
  int row[8][4], lo[8][4], hi[8][4];
  int i, j, k, l, x, d, bad = 0;

  for (count = 2; count <= 8; count++) {
    for (n = 0; n < count; n++) {
      seat[n] = (unsigned char)playerCountIndex[(count - 2) * 8 + n];
      d = (seat[n] < 5) ? 1 : -1;
      /* move field: right-hand seats grow leftwards */
      lo[n][0] = playerXMaster[seat[n]] + playerBetXMaster[seat[n]]
                 - (d < 0 ? MOVE_FIELD_W : 0);
      hi[n][0] = lo[n][0] + MOVE_FIELD_W - 1;
      row[n][0] = playerYMaster[seat[n]] + playerBetYMaster[seat[n]];
      /* bet: the chip plus up to three digits */
      x = playerXMaster[seat[n]] + playerBetXMaster[seat[n]] + 1;
      if (d < 0) x -= 4;
      lo[n][1] = x - 1;
      hi[n][1] = x + 2;
      row[n][1] = row[n][0] + 1;
      /* name and purse, which the move text must also stay clear of */
      if (n == 0) {
        /* YOU: drawNamePurse() moves the purse for player 0 - down three rows
           and left two on wide screens, down one on narrow - and draws no
           name on narrow screens at all. */
        row[n][2] = -99; lo[n][2] = hi[n][2] = 0;
#if WIDTH >= 40
        row[n][3] = playerYMaster[seat[n]] + 1;
        lo[n][3] = playerXMaster[seat[n]] - 2;
#else
        row[n][3] = playerYMaster[seat[n]] - 1;
        lo[n][3] = playerXMaster[seat[n]];
#endif
        hi[n][3] = lo[n][3] + 4;
      } else if (d > 0) {
        row[n][2] = playerYMaster[seat[n]] - 1;
        lo[n][2] = playerXMaster[seat[n]];      hi[n][2] = lo[n][2] + 7;
        row[n][3] = playerYMaster[seat[n]] - 2;
        lo[n][3] = playerXMaster[seat[n]];      hi[n][3] = lo[n][3] + 4;
      } else {
        row[n][2] = playerYMaster[seat[n]] - 1;
        hi[n][2] = playerXMaster[seat[n]] + 1;  lo[n][2] = hi[n][2] - 7;
        row[n][3] = playerYMaster[seat[n]] - 2;
        hi[n][3] = playerXMaster[seat[n]] + 1;  lo[n][3] = hi[n][3] - 4;
      }
    }
    for (i = 0; i < count; i++)
      for (j = i + 1; j < count; j++)
        for (k = 0; k < 4; k++)
          for (l = 0; l < 4; l++) {
            if (row[i][k] == -99 || row[j][l] == -99) continue;
            if (row[i][k] == row[j][l] &&
                !(hi[i][k] < lo[j][l] || hi[j][l] < lo[i][k])) {
              printf("FAIL: %u players: seat%u %s row %d cols %d-%d overlaps "
                     "seat%u %s cols %d-%d\n",
                     count, seat[i], kind[k], row[i][k], lo[i][k], hi[i][k],
                     seat[j], kind[l], lo[j][l], hi[j][l]);
              bad++;
            }
          }
    /* A seat's own move and bet must also clear its own name and purse -
       skipping same-seat pairs is how seat 7's bet came to be drawn over
       its own name on every 40-column build. */
    for (i = 0; i < count; i++)
      for (k = 0; k < 2; k++)          /* move, bet */
        for (l = 2; l < 4; l++) {      /* name, purse */
          if (row[i][k] == -99 || row[i][l] == -99) continue;
          /* A seat's own bet and purse are both chip-and-number, so merely
             touching reads as one blob - require a clear column between them.
             Not on 32 columns: the bottom-right seat cannot have that gap
             without its bet overlapping the bottom seat's, and the bottom
             seat cannot move because the pot box is immediately left of it. */
#if WIDTH >= 40
          x = (k == 1 && l == 3) ? 1 : 0;
#else
          x = 0;
#endif
          if (row[i][k] == row[i][l] &&
              !(hi[i][k] + x < lo[i][l] || hi[i][l] + x < lo[i][k])) {
            printf("FAIL: %u players: seat%u own %s row %d cols %d-%d overlaps "
                   "its own %s cols %d-%d\n",
                   count, seat[i], kind[k], row[i][k], lo[i][k], hi[i][k],
                   kind[l], lo[i][l], hi[i][l]);
            bad++;
          }
        }
  }
  if (!bad)
    printf("ok: no seat's text overlaps another or itself, at any count\n");
  return bad;
}

int main(void) {
  int fails = 0;

  fails += checkSeatOverlaps();

  clearGameState();
  initGraphics();
  memset(&clientState, 0, sizeof(clientState));

  state.playerCount = 4;
  state.round = 1;
  state.pot = 15;
  state.activePlayer = 3;
  /* seat order: 0=YOU(bottom) 1=mid-left 2=top 3=mid-right */
  setPlayer(0, "you", 1, 0, "", 1000, "askh");
  setPlayer(1, "clyd bot", 1, 5, "post", 995, "????");
  setPlayer(2, "meg bot", 1, 10, "post", 990, "????");
  setPlayer(3, "jim bot", 1, 0, "", 1000, "????");

  frame("f1: pre-flop, blinds posted");

  /* CLYD folds, JIM calls */
  setPlayer(1, "clyd bot", 2, 5, "fold", 995, "??");
  setPlayer(3, "jim bot", 1, 10, "call", 990, "????");
  state.activePlayer = 0;
  frame("f2: clyd folded, jim called");

  /* another poll, same street (steady state) */
  frame("f3: same state, next poll");

  /* flop: bets collected, moves reset for live players, board dealt */
  state.round = 2;
  state.pot = 45;
  state.activePlayer = 1; /* seat rotation: whoever */
  state.activePlayer = 3;
  strcpy(state.community, "7dkcac");
  setPlayer(0, "you", 1, 0, "", 990, "askh");
  setPlayer(1, "clyd bot", 2, 0, "fold", 995, "??");
  setPlayer(2, "meg bot", 1, 0, "", 990, "????");
  setPlayer(3, "jim bot", 1, 0, "", 990, "????");
  frame("f4: flop dealt");

  frame("f5: flop, next poll (steady state)");

  /* YOU bet on the flop - exercises the bottom-center bet position, which on
   * 32-col platforms sits nearest the pot box. */
  setPlayer(0, "you", 1, 25, "bet", 965, "askh");
  state.activePlayer = 3;
  frame("f6: you bet 25");

  /* The folded player's FOLD label must survive every frame.
   * mid-left seat: move field at x=playerX+betX=1+8=9, row=playerY+betY=11 */
#if WIDTH >= 40
  fails += expect(11, 9, "FOLD", "mid-left FOLD visible on flop");
#endif

#if WIDTH >= 40
  /* mid-right seat move field: dir<0, x=37-3-5=29..33 */
  printf("mid-right field row11: \"%.10s\"\n", &screen[11][27]);
#endif

#ifdef HOST_ADAM
  /* Community board: 3 cards at 2-col pitch from (11,9); rank row is 10. */
  fails += expect(10, 11, "7DKCAC", "flop board at community row");
  /* Street label on the pot row, left of the box. */
  fails += expect(15, 0, "FLOP", "street label at (0,15)");
  fails += expect(15, 14, "45", "pot amount inside the box");
  /* YOU purse: x=11+1+6 right-justified by len(965), y=18-3+2. */
  fails += expect(17, 15, "965", "YOU purse right of center");
  /* YOU bet: left of the pot box (betX -3), clear of the box border. */
  fails += expect(16, 9, "25", "YOU bet left of pot box");
  fails += expect(16, POT_BOX_X, "+", "pot box corner intact");
  /* Folded mid-left seat: the second hole card's leftover columns (3-4)
   * must be blanked by drawCard's face-down clear. */
  fails += expect(9, 3, "  ", "mid-left fold residue erased");
  /* Live mid-right seat: second card's sliver at col 28 plus the first
   * card at 29-31 - both hole cards must be visible. */
  fails += expect(10, 28, "???", "right seat: both hole cards visible");
#endif

  /* Five-handed pre-flop. The bottom seat's move/bet text sits directly under
   * the pot, which drawPot() boxes at rows 14-16, columns 16-22. The bottom
   * seat must stay clear of that box: it previously overwrote the whole
   * bottom border, leaving the pot total in an open-ended frame. */
  clearGameState();
  initGraphics();
  memset(&clientState, 0, sizeof(clientState));

  state.playerCount = 5;
  state.round = 1;
  state.pot = 215;
  state.activePlayer = 0;
  state.community[0] = 0;

  /* seat order for 5 players -> master idx {0,2,3,5,6} =
     bottom, mid-left, top-left, top-right, mid-right */
  setPlayer(0, "you",      1, 50, "raise", 950, "asjs");
  setPlayer(1, "clyd bot", 1, 25, "hold", 1000, "????");
  setPlayer(2, "jim bot",  1, 70, "raise", 925, "????");
  setPlayer(3, "kirk bot", 2,  5, "fold",  985, "??");
  setPlayer(4, "hulk bot", 1,  0, "",      910, "????");

  frame("f6: five-handed pre-flop, pot 215");

  fails += expect(POT_BOX_TOP_Y, POT_BOX_X, "+------+", "pot box top border intact");
  fails += expect(POT_BOX_BOTTOM_Y, POT_BOX_X, "+------+", "pot box bottom border intact");

  {
    /* A four-figure pot must still fit inside the box. The old interior held
       a chip and three digits, so 1000+ wrote over the frame's right edge. */
    state.pot = 1000;
    redrawGameScreen = 1;
    drawPot();
    fails += expect(POT_BOX_TOP_Y, POT_BOX_X, "+------+", "pot box intact at 1000");
    fails += expect(POT_BOX_BOTTOM_Y, POT_BOX_X, "+------+", "pot box bottom intact at 1000");
    printf("    four-figure pot row: \"%.12s\"\n", &screen[POT_BOX_TOP_Y + 1][POT_BOX_X]);
    state.pot = 215;
    drawPot();
  }


#if WIDTH < 40
  {
    /* The street wording is only cut when an eighth player puts a status field
       beside it; below that it spells out in full. */
    unsigned char saved = state.playerCount;
    state.playerCount = 8;
    drawStreetLabel();
    fails += expect(12 + POT_Y_MODIFIER, 0, "PRE  ", "street cut at 8 players");
    state.playerCount = 7;
    drawStreetLabel();
    fails += expect(12 + POT_Y_MODIFIER, 0, "PRE-FLOP", "street spelled out below 8");
    state.playerCount = saved;
    drawStreetLabel();
  }
#endif

  {
    /* A mid-row seat's chip and bet must not land on its own cards, which are
       five rows tall and reach down into the seat's own status rows. */
    unsigned char betCol = (unsigned char)(playerXMaster[2] + playerBetXMaster[2]);
    unsigned char betRow = (unsigned char)(playerYMaster[2] + playerBetYMaster[2] + 1);
    fails += expect(betRow, betCol, "o25", "mid-left bet clear of its own cards");
  }

#if WIDTH >= 40
  /* Seats are reassigned when the player count changes. Four-handed, the third
   * player sits top-center and their move text lands at column 19; five-handed
   * they move to top-left, column 11. What he drew at the old seat has to go, or it
   * strands there - single-buffered platforms repaint only when asked to. */
  clearGameState();
  initGraphics();
  state.playerCount = 4;
  state.round = 2;
  state.pot = 60;
  state.activePlayer = 0;
  strcpy(state.community, "7dkcac");
  setPlayer(0, "you",      1, 0, "",      950, "asjs");
  setPlayer(1, "clyd bot", 1, 0, "",      995, "????");
  setPlayer(2, "meg bot",  1, 0, "check", 990, "????");
  setPlayer(3, "jim bot",  1, 0, "",      990, "????");
  frame("f7: four-handed, third seat top-center");
  {
    /* four-handed, the third player takes master seat 4; the move field sits
       at that seat's bet anchor, which differs per platform */
    unsigned char seatCol = (unsigned char)(playerXMaster[4] + playerBetXMaster[4]);
    unsigned char seatRow = (unsigned char)(playerYMaster[4] + playerBetYMaster[4]);

    fails += expect(seatRow, seatCol, "CHECK", "four-handed: move text at top-center seat");

    state.playerCount = 5;
    setPlayer(4, "hulk bot", 1, 0, "",      910, "????");
    frame("f8: fifth player joins, seats shuffle");
    fails += expect(seatRow, seatCol, "     ", "seat shuffle: vacated seat cleared");
  }
#endif

  /* Move menu. Call and raise share one label and one amount; the amount
   * sits in a fixed-width field so nothing to its right moves when it
   * changes, and nothing may be drawn in the countdown clock's columns. */
  {
    unsigned char timerCol = (unsigned char)(WIDTH - 3 - STATUS_TIMER_WIDTH);
    unsigned char c, allinCol1, allinCol2;

    clearStatusBar();
    state.validMoveCount = 5;
    strcpy(state.validMoves[0].move, "f");  strcpy(state.validMoves[0].name, "FOLD");
    strcpy(state.validMoves[1].move, "c");  strcpy(state.validMoves[1].name, "CALL 40");
    strcpy(state.validMoves[2].move, "r1"); strcpy(state.validMoves[2].name, "RAISE 60");
    strcpy(state.validMoves[3].move, "r2"); strcpy(state.validMoves[3].name, "RAISE 120");
    strcpy(state.validMoves[4].move, "a");  strcpy(state.validMoves[4].name, "ALL IN");

    layoutMoveMenu();
    cursorX = 1;                 /* the call half */
    drawMoveNumber();
    printf("--- move menu ---\n    0123456789012345678901234567890123456789\n"
           "  |%s|  cursor on CALL\n", screen[HEIGHT - 1]);

    fails += expect(HEIGHT - 1, PLAYER_MOVE_START_X, "FOLD", "menu: FOLD intact");
    for (c = 0; c + 10 <= WIDTH; c++)
      if (!strncmp(&screen[HEIGHT - 1][c], "CALL/RAISE", 10)) break;
    if (c + 10 <= WIDTH) printf("ok: menu: call and raise share one label\n");
    else { printf("FAIL: menu: no combined CALL/RAISE entry\n"); fails++; }
    allinCol1 = 0;
    for (c = 0; c + 6 <= WIDTH; c++)
      if (!strncmp(&screen[HEIGHT - 1][c], "ALL IN", 6)) { allinCol1 = c; break; }
    if (allinCol1) printf("ok: menu: ALL IN intact at col %u\n", allinCol1);
    else { printf("FAIL: menu: ALL IN missing or truncated\n"); fails++; }

    cursorX = 2;                 /* the raise half */
    drawMoveNumber();
    printf("  |%s|  cursor on RAISE\n", screen[HEIGHT - 1]);

    /* widest offered amount is 3 digits, so a 2-digit raise must not shift
       anything to its right */
    allinCol2 = 0;
    for (c = 0; c + 6 <= WIDTH; c++)
      if (!strncmp(&screen[HEIGHT - 1][c], "ALL IN", 6)) { allinCol2 = c; break; }
    if (allinCol1 && allinCol1 == allinCol2)
      printf("ok: menu: ALL IN does not move when the amount changes\n");
    else { printf("FAIL: menu: ALL IN shifted (%u -> %u)\n", allinCol1, allinCol2); fails++; }

    for (c = timerCol; c < WIDTH; c++) {
      if (screen[HEIGHT - 1][c] != ' ') {
        printf("FAIL: menu: text at col %u runs into the clock\n", c);
        fails++;
        break;
      }
    }
    if (c >= WIDTH)
      printf("ok: menu: clock columns (%u-%u) left clear\n", timerCol, WIDTH - 1);
  }

  return fails ? 1 : 0;
}
