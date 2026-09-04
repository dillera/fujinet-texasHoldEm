#ifdef _CMOC_VERSION_
#include <cmoc.h>
#include <coco.h>
//#define true 1
//#define false 0
//typedef BOOL bool;
#else
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#endif /* _CMOC_VERSION_ */

#include "platform-specific/graphics.h"
#include "platform-specific/sound.h"
#include "platform-specific/util.h"
#include "gamelogic.h"
#include "misc.h"
#include "stateclient.h"
#include "screens.h"
#include "platform-specific/appkey.h"

extern unsigned char redrawGameScreen;
#ifndef POT_Y_MODIFIER
#define POT_Y_MODIFIER 0
#endif

#ifndef STATUS_TIMER_WIDTH
#define STATUS_TIMER_WIDTH 2
#endif

#ifndef PLAYER_MOVE_START_X
#define PLAYER_MOVE_START_X 1
#endif

#ifndef LEFT_JUSTIFY_PLAYER_PURSE
#define LEFT_JUSTIFY_PLAYER_PURSE 0
#endif

/* 32 columns only fit four, clipping RAISE/CHECK to RAIS/CHEC. */
#ifndef MOVE_FIELD_W
#if WIDTH >= 40
#define MOVE_FIELD_W 5
#else
#define MOVE_FIELD_W 4
#endif
#endif

// Texas Hold'em community card board position (5 cards, 2 columns each)
#ifndef COMMUNITY_X
#define COMMUNITY_X (WIDTH/2-5)
#endif
#ifndef COMMUNITY_Y
#define COMMUNITY_Y 9
#endif

void progressAnim(unsigned char y) {
  for(i=0;i<3;++i) {
    pause(10);
    drawChip(WIDTH/2-2+i*2,y);
    drawBuffer();
  }
}

void drawPot() {

  if (redrawGameScreen) {
    /* One wider than 5 Card Stud's: its interior held only three digits. */
    drawBox(WIDTH/2-4,11+POT_Y_MODIFIER,5,1);
    drawChip(WIDTH/2-3,12+POT_Y_MODIFIER);
  }
  itoa(state.pot, tempBuffer, 10);
  /* padded, so a shrinking pot leaves no stale digit */
  for (k=(unsigned char)strlen(tempBuffer); k<4; k++)
    tempBuffer[k]=' ';
  tempBuffer[4]=0;
  drawText(WIDTH/2-2,12+POT_Y_MODIFIER, tempBuffer);
}

// Texas Hold'em street indicator, drawn on the pot row just left of the pot
// box - the one spot that is clear of player names/purses on every platform.
// Labels are padded to a fixed width so each one fully overwrites the previous.
#if WIDTH >= 40
#define STREET_X (WIDTH/2-13)
static const char* streetNames[6] = {
  "         ", "PRE-FLOP ", "FLOP     ", "TURN     ", "RIVER    ", "SHOWDOWN "
};
#else
#define STREET_X 0
/* 32 columns: an eighth player puts a status field at columns 6-9, so the
   wording is cut to five there and only there. One table holds both forms -
   rows 0-5 spelled out, rows 6-11 cut - to save a second static on the
   tightest build. */
static const char streetNames[12][10] = {
  "         ", "PRE-FLOP ", "FLOP     ", "TURN     ", "RIVER    ", "SHOWDOWN ",
  "     ",     "PRE  ",     "FLOP ",     "TURN ",     "RIVER",     "SHOW "
};
#endif

void drawStreetLabel() {
  if (state.round > 5 || state.playerCount < 2)
    return;
#if WIDTH >= 40
  drawText(STREET_X, 12+POT_Y_MODIFIER, streetNames[state.round]);
#else
  drawText(STREET_X, 12+POT_Y_MODIFIER,
           streetNames[state.round + (state.playerCount > 7 ? 6 : 0)]);
#endif
}

void resetStateIfNewGame() {
  if (state.round >= prevRound)
    return;

  // Reset status bar and vars for a new game
  if (prevRound != 99) {

   // @SetStatusBarHeight 1
   clearStatusBar();
  } else {

    // Force empty screen if coming from another screen.
    // This is mainly to avoid color glitches on c64
    // when setting the color memory - which is not (YET?) double buffered -
    // before the screen is drawn. There may be a better solution.
    drawBuffer();
  }

  currentCard=0;
  cardIndex=0;
  cursorY=246;
  cursorX=128;
  prevPot=0;
  if (!redrawGameScreen) {
    redrawGameScreen=1;
    resetScreen();
  }

  // If the round is already past 1, we are joining a game in progress. Skip animation this update
  if (state.round>1)
    noAnim=1;
}


void drawNamePurse() {

  for (i=0;i<state.playerCount;i++) {
    // Print name, left or right justified based on direction
    y = playerY[i]-1;
    x = playerX[i];
    if (playerDir[i]<0)
      x++;

    if (i>0 || state.viewing) {
      xx=x;

      // Reverse print right side players
      if (playerDir[i]<0)
        xx-=(unsigned char)strlen(state.players[i].name)-1;

      drawText(xx, y, state.players[i].name);

      if (state.activePlayer!=i) {
        hideLine(xx, y+1, (unsigned char)strlen(state.players[i].name));
      } else {
        cursorX=xx;
        cursorY=y;
      }
    } else {
      // Draw YOU player name
      #if WIDTH>=40
        drawText(x-5, playerY[i]+2, (const char *)" YOU");
      #else
        // Squeezed for horizontal space, so shift above cards
        // drawText(x+3, playerY[i]-1, (const char *)" YOU");
      #endif
    }

    // Print purse (chip count)
    x++;
    y--;

    // Override Purse position for YOU player
    if (i==0) {
      #if WIDTH>=40
        x-=2;
        y+=3;
      #else
        x+=6*(LEFT_JUSTIFY_PLAYER_PURSE==0);
        y+=1;
      #endif
    }

    itoa(state.players[i].purse, tempBuffer, 10);

    if (playerDir[i]<0 || i==LEFT_JUSTIFY_PLAYER_PURSE) {
      x-=(unsigned char)strlen(tempBuffer);
      drawText(x-2,y," "); // Cover case when chip count drops from 100 to 99
    } else {
      drawText(x+strlen(tempBuffer),y," "); // Cover case when chip count drops from 100 to 99
    }

    drawText(x,y, tempBuffer);
    drawChip(x-1,y);
    
  }
}


void drawBets() {
  if (state.round <1 || state.round>4)
    return;

  for (i=state.playerCount-1;i<255;i--) {
    y = playerY[i]+playerBetY[i]+1;

    // Draw bet amount
    if (state.players[i].bet>0) {
      x= playerX[i]+playerBetX[i]+1;

      itoa(state.players[i].bet, tempBuffer, 10);
      if (playerDir[i]<0)
        x-=(unsigned char)strlen(tempBuffer)+1;

      drawText(x, y, tempBuffer);
      drawChip(x-1,y );
    } 

    // Fixed-width field so a shorter move fully overwrites a longer one
#if WIDTH < 40
    /* No room beside seat 7 on 32 columns, and it only exists at seven. */
    if (i==0 && state.playerCount > 6) continue;
#endif
    x= playerX[i]+playerBetX[i];
    y--;

    k=(unsigned char)strlen(state.players[i].move);
    if (k>MOVE_FIELD_W) k=MOVE_FIELD_W;
    memcpy(tempBuffer, "     ", MOVE_FIELD_W);
    tempBuffer[MOVE_FIELD_W]=0;
    if (playerDir[i]<0) {
      x-=MOVE_FIELD_W;
      memcpy(tempBuffer+MOVE_FIELD_W-k, state.players[i].move, k);
    } else {
      memcpy(tempBuffer, state.players[i].move, k);
    }

    drawText(x, y, tempBuffer);

  }
}

void checkFinalFlip() {
  if (prevRound<state.round && state.round == 5)
    drawCards(true);
}

// Texas Hold'em card rendering. Each player has 2 hole cards; up to 5 shared
// community cards sit in the middle of the table. Masking is server-side:
// opponents' hands arrive as "????" until the showdown reveals them, and a
// folded hand is just "??" (drawn as a single face-down card).
void drawCards(bool finalFlip) {
  static unsigned char cc;

  if (state.round<1)
    return;

  // Hole cards: animate the deal only when they first appear this hand
  doAnim = !noAnim && !cardIndex && !finalFlip;
  if (doAnim)
    disableDoubleBuffer();

  for (j=0;j<2;j++) {
    for (h=1;h<=state.playerCount;h++) {
      i = h % state.playerCount;
      hand = state.players[i].hand;
      if (strlen(hand)>j*2+1) {
        /* A one-card hand is a fold: the renderer wipes the empty slot. */
        drawCard(playerX[i]+(j*2)*playerDir[i], playerY[i],
                 (unsigned char)(strlen(hand) > 3 ? FULL_CARD
                                                  : (FULL_CARD | CARD_CLEAR_NEXT)),
                 hand+j*2, false);

        if (doAnim) {
          soundDealCard();
          pause(5);
        }
      }
    }
  }
  cardIndex=1;

  // Community cards: animate each newly revealed street
  cc = (unsigned char)strlen(state.community)>>1;
  for (j=0;j<cc;j++) {
    doAnim = !noAnim && j>=currentCard;
    if (doAnim) {
      disableDoubleBuffer();
      pause(10);
    }

    drawCard(COMMUNITY_X+j*2, COMMUNITY_Y, FULL_CARD, state.community+j*2, false);

    if (doAnim)
      soundDealCard();
  }
  currentCard=cc;

  // Showdown: flip each surviving opponent's revealed hand with a beat between
  if (finalFlip) {
    drawBuffer();
    disableDoubleBuffer();

    for (h=1;h<state.playerCount;h++) {
      // Don't flip a player that doesn't have a visible hand
      if (state.players[h].status != 1 || state.players[h].hand[0]=='?')
        continue;

      for (j=0;j<2;j++) {
        drawCard(playerX[h]+(j*2)*playerDir[h], playerY[h], FULL_CARD, state.players[h].hand+j*2, false);
      }

      soundDealCard();

      pause(35);
    }
  }

  drawBuffer();
  enableDoubleBuffer();
  noAnim=false;
}

void checkIfSpectatorStatusChanged() {
  if (state.viewing == wasViewing)
    return;

  // Temp hack due to server not always sending correct viewing flag when not full
  if (state.playerCount<8)
    state.viewing=0;

  wasViewing = state.viewing;

  if (state.viewing) {
    drawStatusText("TABLE FULL: WATCHING AS A SPECTATOR");
    drawBuffer();
    pause(80);
  } else if (
    state.players[0].status == 0 ||
    (state.round == 1 && state.players[0].status == 1 && state.activePlayer != 0 )
    ) {
    /* Display intro text if player is joining the table on
     * the opening round or sitting down to wait for the next round.
     * Otherwise, they are re-joining due to connection error, so we do not delay
     */

    centerStatusText("YOU SIT DOWN AT THE TABLE");
    drawBuffer();

    soundJoinGame();

    pause(50);
  }
}

void checkIfPlayerCountChanged() {
  if (state.playerCount == prevPlayerCount)
    return;

  // Seats move below, so whatever they drew at the old ones must be cleared
  redrawGameScreen = 1;

  // Handle if player joins mid game
  if (state.playerCount>1 && prevPlayerCount > 0) {
    if (state.playerCount < prevPlayerCount) {

      drawStatusText("A PLAYER LEFT THE TABLE");
      drawBuffer();

      soundPlayerLeft();

      // for j=8 to 2 step -2
      //   sound 1,255-j*j,10,j:pause 2:sound:pause 8
      // next
    } else {
      strcpy(state.lastResult, "A NEW PLAYER JOINS THE TABLE");
      drawStatusText(state.lastResult);
      drawBuffer();

      soundPlayerJoin();

    }

    pause(40);
    if (state.round > 1)
      noAnim = true;
  }

  prevPlayerCount = state.playerCount;

  // Don't shuffle player locations until multple players exist
  if (state.playerCount<2)
    return;

  i=0;
  k=(state.playerCount-1)*8;
  for (j=(state.playerCount-2)*8;j<k;j++) {
    h=playerCountIndex[j];
    playerX[i] = playerXMaster[h];
    playerY[i] = playerYMaster[h];
    playerDir[i] = playerDirMaster[h];
    playerBetX[i] = playerBetXMaster[h];
    playerBetY[i] = playerBetYMaster[h];
    i++;
  }
}

void drawStatusTimeLeft() {
  drawStatusTimer();
  tempBuffer[0]=' ';
  itoa(state.moveTime, tempBuffer+1, 10);
  drawStatusTextAt( (unsigned char)(WIDTH-strlen(tempBuffer)-STATUS_TIMER_WIDTH), tempBuffer);
  drawBuffer();
}

void highlightActivePlayer() {
 if (state.activePlayer>0 && state.playerCount>1) {
   i=(unsigned char)strlen(state.players[state.activePlayer].name);
    for (j=2;j<=i;j++) {
      drawLine(cursorX, cursorY+1, j);
      drawBuffer();
    }
  }
}

void animateChipsToPotOnRoundEnd() {
  if (state.round <= prevRound || state.pot == 0)
    return;

  // A new street begins: request a full clean redraw of the table after the
  // chip animation. The incremental bet/move erasing below uses fixed widths
  // and can leave text fragments (varying-length moves, chip columns) that
  // used to be harmless but now sit next to the community board.
  // Not done for the showdown transition (round 5), where the final card
  // flip must stay on screen on SINGLE_BUFFER platforms. (Double-buffered
  // platforms fully redraw every frame anyway; this matters for the CoCo.)
  if (state.round < 5)
    redrawGameScreen=1;

  clearStatusBar();
  pause(50);

  // Hide moves
  #if WIDTH>=40
  for (i=0;i<state.playerCount;i++) {
    y = playerY[i]+playerBetY[i];
    x = playerX[i]+playerBetX[i];

    if (playerDir[i]<0)
        x-=5;
    
    drawText(x, y, "     ");    
  }

  #endif

  drawBuffer();
  pause(30);

  // Don't animate bets if the pot hasn't changed
  if (prevPot == state.pot)
    return;

  prevPot = state.pot;
  disableDoubleBuffer();

  // Clear bets off screen
  for (i=0;i<state.playerCount;i++) {
    y = playerY[i]+playerBetY[i]+1;
    x= playerX[i]+playerBetX[i];

    if (playerDir[i]<0)
      x-=3;

    drawText(x, y, "   ");

    soundTakeChip(i);

  }

  drawPot();
  drawBuffer();
  enableDoubleBuffer();

  pause(45);
}


void drawGameStatus() {
  if (state.activePlayer == 0)
    return;

  if (state.activePlayer>0) {
    strcpy(tempBuffer,"WAITING ON ");
    strcat(tempBuffer, state.players[state.activePlayer].name);
    drawStatusText(tempBuffer);

  } else if (state.activePlayer< 0 && (state.round == 5 || state.round == 0)) {
    // End of (or in between) games
    drawStatusText(state.lastResult);


    if (state.round==5 && prevRound != state.round) {
      drawBuffer();

      soundGameDone();

      pause(30);
    }
  }


  // Waiting for a player to join - show animation
  if (state.round == 0) {
    waitCount = (waitCount + 1) % 3;
    drawStatusTextAt(26+waitCount," .  ");
    pause(40);
  }

}

/* The server's five moves will not fit a 40-column status bar beside the
   countdown clock, so call and raise share one label and one amount. Folding
   them together is display only: each stop still sends its own move code. */

#define MV_OTHER 0
#define MV_FOLD  1
#define MV_CALL  2      /* call or check */
#define MV_RAISE 3      /* raise or bet  */
#define MV_ALLIN 4

static unsigned char moveLen[5];    /* underline width per cursor stop     */
static unsigned char moveRef[5];    /* validMoves index per cursor stop    */
static unsigned char raiseIdx[5];   /* validMoves index of each raise      */
static unsigned char stopCount, raiseStop, raiseCount, raiseSel, callRef;
static unsigned char numCol, numWidth, menuX, menuEnd;

static unsigned char moveClass(const char *n) {
  switch (n[0]) {
    case 'F': case 'f': return MV_FOLD;
    case 'C': case 'c': return MV_CALL;
    case 'R': case 'r':
    case 'B': case 'b': return MV_RAISE;
    case 'A': case 'a': return MV_ALLIN;
  }
  return MV_OTHER;
}

/* Offset of the trailing amount within a name, or 0 if it carries none. */
static unsigned char amountAt(const char *n) {
  static unsigned char p, sp;
  sp = 0;
  for (p = 0; n[p]; p++)
    if (n[p] == ' ')
      sp = p;
  if (sp && n[sp + 1] >= '0' && n[sp + 1] <= '9')
    return (unsigned char)(sp + 1);
  return 0;
}

/* Clamped so the menu can never reach the clock's columns. */
static unsigned char emit(const char *s, unsigned char len) {
  if ((unsigned char)(menuX + len) > (unsigned char)(menuEnd + 1))
    len = (menuX > menuEnd) ? 0 : (unsigned char)(menuEnd + 1 - menuX);
  if (len) {
    memcpy(tempBuffer, s, len);
    tempBuffer[len] = 0;
    drawStatusTextAt(menuX, tempBuffer);
  }
  menuX = (unsigned char)(menuX + len);
  return len;
}

static void addStop(unsigned char col, unsigned char len, unsigned char ref) {
  moveLoc[stopCount] = col;
  moveLen[stopCount] = len;
  moveRef[stopCount] = ref;
  stopCount++;
}

/* The raise while its half is selected, otherwise the call. */
void drawMoveNumber() {
  static unsigned char src, a, n;
  if (!numWidth)
    return;
  src = (raiseStop != 255 && cursorX == raiseStop) ? raiseIdx[raiseSel] : callRef;
  a = amountAt(state.validMoves[src].name);
  n = 0;
  if (a)
    while (state.validMoves[src].name[a + n]) {
      tempBuffer[n] = state.validMoves[src].name[a + n];
      n++;
    }
  while (n < numWidth)
    tempBuffer[n++] = ' ';
  tempBuffer[n] = 0;
  drawStatusTextAt(numCol, tempBuffer);
}

void layoutMoveMenu() {
  static unsigned char i, n, gap, fold, allin, start, tot;
  static unsigned char cls[5], vlen[5], amt[5];

  menuEnd = (unsigned char)(WIDTH - 5 - STATUS_TIMER_WIDTH);
  stopCount = 0;
  raiseStop = 255;
  raiseCount = 0;
  raiseSel = 0;
  numWidth = 0;
  callRef = 255;
  fold = 255;
  allin = 255;
  menuX = PLAYER_MOVE_START_X;

  for (i = 0; i < state.validMoveCount; i++) {
    cls[i] = moveClass(state.validMoves[i].name);
    amt[i] = amountAt(state.validMoves[i].name);
    n = (unsigned char)strlen(state.validMoves[i].name);
    vlen[i] = amt[i] ? (unsigned char)(amt[i] - 1) : n;
    if (cls[i] == MV_FOLD) {
      if (fold == 255) fold = i;
    } else if (cls[i] == MV_CALL) {
      if (callRef == 255) callRef = i;
      if (amt[i] && (unsigned char)(n - amt[i]) > numWidth)
        numWidth = (unsigned char)(n - amt[i]);
    } else if (cls[i] == MV_RAISE) {
      raiseIdx[raiseCount++] = i;
      if (amt[i] && (unsigned char)(n - amt[i]) > numWidth)
        numWidth = (unsigned char)(n - amt[i]);
    } else if (cls[i] == MV_ALLIN) {
      if (allin == 255) allin = i;
    }
  }

  /* Nothing to fold together: one entry per move, still clamped. */
  if (callRef == 255 || !raiseCount) {
    numWidth = 0;
    for (i = 0; i < state.validMoveCount; i++) {
      start = menuX;
      n = emit(state.validMoves[i].name,
               (unsigned char)strlen(state.validMoves[i].name));
      addStop(start, n, i);
      menuX = (unsigned char)(menuX + 2);
    }
    return;
  }

  tot = (unsigned char)(PLAYER_MOVE_START_X + vlen[callRef] + 1
                        + vlen[raiseIdx[0]] + numWidth);
  gap = 2;
  n = 2;
  if (fold != 255) n++;
  if (allin != 255) { n++; tot = (unsigned char)(tot + vlen[allin]); }
  if (fold != 255) tot = (unsigned char)(tot + vlen[fold]);
  if ((unsigned char)(tot + 2 * (n - 1) - 1) > menuEnd)
    gap = 1;

  if (fold != 255) {
    start = menuX;
    n = emit(state.validMoves[fold].name, vlen[fold]);
    addStop(start, n, fold);
    menuX = (unsigned char)(menuX + gap);
  }

  start = menuX;
  n = emit(state.validMoves[callRef].name, vlen[callRef]);
  addStop(start, n, callRef);

  emit("/", 1);

  start = menuX;
  n = emit(state.validMoves[raiseIdx[0]].name, vlen[raiseIdx[0]]);
  raiseStop = stopCount;
  addStop(start, n, raiseIdx[0]);
  menuX = (unsigned char)(menuX + gap);

  numCol = menuX;
  if ((unsigned char)(numCol + numWidth) > (unsigned char)(menuEnd + 1))
    numWidth = (numCol > menuEnd) ? 0 : (unsigned char)(menuEnd + 1 - numCol);
  menuX = (unsigned char)(menuX + numWidth);

  if (allin != 255) {
    menuX = (unsigned char)(menuX + gap);
    start = menuX;
    n = emit(state.validMoves[allin].name, vlen[allin]);
    addStop(start, n, allin);
  }
}


void requestPlayerMove() {
  requestedMove=NULL;

  if (state.viewing || state.activePlayer != 0)
    return;

  // Draw the moves on the status bar
  clearStatusBar();
  layoutMoveMenu();

  // The shared amount depends on where the cursor lands, so paint it after
  cursorX = stopCount > 1;
  drawMoveNumber();

  // Prepare the countdown timer
  drawStatusTimeLeft();

  drawBuffer();
  disableDoubleBuffer();

  // Zoom in the cursor
  i=moveLen[cursorX];
  h=moveLoc[cursorX];

 

// Animate the line. If needed, can add #if around instead
// of checking render full cards
//if (always_render_full_cards) {
  drawLine(0,HEIGHT-1, h+h+i);
  pause(5);
  for (j=h;j>0;--j) {
    hideLine(h-j,HEIGHT-1,1);
    hideLine(h+i+j-1,HEIGHT-1,1);
    pause(2);
  }
//}

  drawLine(h,HEIGHT-1,i);
  soundMyTurn();


  maxJifs = 60;
  maxJifs *=state.moveTime;
  waitCount=0;
  clearCommonInput();
  resetTimer();

  // Move selection loop
  while (state.moveTime>0 && !inputTrigger) {
    waitvsync();

    // Tick counter once per second
    if (++waitCount>2) {
      waitCount=0;
      i = (unsigned char)((maxJifs-getTime())/60);
      if (i!= state.moveTime) {
        state.moveTime =i;
        drawStatusTimeLeft();
        soundTick();

      }
    }

    // Move cursor, retricting to bounds
    readCommonInput();

    if (inputDirX !=0 ) {
      cursorX+=inputDirX;
      if (cursorX<stopCount) {
        hideLine(moveLoc[cursorX-inputDirX],HEIGHT-1,moveLen[cursorX-inputDirX]);
        drawLine(moveLoc[cursorX],HEIGHT-1,moveLen[cursorX]);
        drawMoveNumber();

        soundCursor();

      } else {
        cursorX-=inputDirX;

        soundCursorInvalid();

      }
      getTime();
    }

    // Up is -1, and picks the larger raise
    if (inputDirY != 0) {
      if (raiseStop != 255 && cursorX == raiseStop &&
          (unsigned char)(raiseSel - inputDirY) < raiseCount) {
        raiseSel = (unsigned char)(raiseSel - inputDirY);
        moveRef[raiseStop] = raiseIdx[raiseSel];
        drawMoveNumber();

        soundCursor();

      } else {

        soundCursorInvalid();

      }
      getTime();
    }

    // Pressed Esc
    switch (inputKey) {
      case KEY_ESCAPE:
      case KEY_ESCAPE_ALT:
        showInGameMenuScreen();
        return;
    }
  }
  clearStatusBar();
  enableDoubleBuffer();

  // Request the highlighted move
  if (cursorX<255) {
    requestedMove = state.validMoves[moveRef[cursorX]].move;
    clearStatusBar();
    menuX = moveLoc[cursorX];
    menuEnd = (unsigned char)(WIDTH - 1);
    emit(state.validMoves[moveRef[cursorX]].name,
         (unsigned char)strlen(state.validMoves[moveRef[cursorX]].name));
    drawBuffer();

    soundSelectMove();


    // For some unknown reason, if I don't delay for a bit here,
    // the selectMove sound plays twice in the AppleWin emulator.
    pause(30);

  }

}

void clearGameState() {
  // Reset some variables
  prevRound = 99;
  prevPlayerCount = 0;
  wasViewing = 255;
  waitCount = -1;
}
