/*
 * Host-side end-to-end test for the Texas Hold'em binary protocol.
 *
 * Mirrors the exact packed struct layout from src/misc.h and plays complete
 * hands against a running server over HTTP, consuming /state?bin=1 exactly the
 * way the 8-bit clients do (fixed-layout blob read straight into the struct)
 * and posting the server-supplied 2-character move codes to /move/<code>.
 *
 * Build & run (from repo root, server running on localhost:8080):
 *   cc -o /tmp/holdem_host_test support/host-test/holdem_host_test.c
 *   /tmp/holdem_host_test http://localhost:8080 dev3 2
 *
 * Exits 0 only if the requested number of hands complete with a sane state
 * at every step.
 */
#include <assert.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ------------------------------------------------------------------ */
/* Packed structs - MUST byte-for-byte match src/misc.h               */
/* ------------------------------------------------------------------ */
#pragma pack(push, 1)

typedef struct {
  char table[9];
  char name[21];
  char players[6];
} Table;

typedef struct {
  char name[9];
  uint8_t status;
  uint16_t bet;
  char move[8];
  uint16_t purse;
  char hand[11];
} Player;

typedef struct {
  char move[3];
  char name[10];
} ValidMove;

typedef struct {
  char lastResult[81];
  uint8_t round;
  uint16_t pot;
  int8_t activePlayer;
  uint8_t moveTime;
  uint8_t viewing;
  char community[11];
  uint8_t validMoveCount;
  ValidMove validMoves[5];
  uint8_t playerCount;
  Player players[8];
} Game;

typedef struct {
  uint8_t count;
  Table table[10];
} Tables;

#pragma pack(pop)

/* Lock the layout: these are the offsets the server serializes to. If one of
 * these fires, src/misc.h and the server's bin serializer have diverged. */
_Static_assert(sizeof(ValidMove) == 13, "ValidMove size");
_Static_assert(sizeof(Player) == 33, "Player size");
_Static_assert(sizeof(Table) == 36, "Table size");
_Static_assert(offsetof(Game, round) == 81, "round offset");
_Static_assert(offsetof(Game, pot) == 82, "pot offset");
_Static_assert(offsetof(Game, activePlayer) == 84, "activePlayer offset");
_Static_assert(offsetof(Game, community) == 87, "community offset");
_Static_assert(offsetof(Game, validMoveCount) == 98, "validMoveCount offset");
_Static_assert(offsetof(Game, validMoves) == 99, "validMoves offset");
_Static_assert(offsetof(Game, playerCount) == 164, "playerCount offset");
_Static_assert(offsetof(Game, players) == 165, "players offset");
_Static_assert(sizeof(Game) == 429, "Game size");

/* ------------------------------------------------------------------ */

static char urlBuffer[512];

/* Fetch a URL with curl, filling buf; returns bytes read or -1 */
static long fetchBinary(const char *url, void *buf, size_t maxLen) {
  char cmd[600];
  snprintf(cmd, sizeof(cmd), "curl -sf --max-time 10 '%s'", url);
  FILE *p = popen(cmd, "r");
  if (!p) return -1;
  size_t n = fread(buf, 1, maxLen, p);
  int rc = pclose(p);
  if (rc != 0) return -1;
  return (long)n;
}

static const char *base, *table;

static long apiCall(const char *path, const char *extra, void *buf, size_t maxLen) {
  snprintf(urlBuffer, sizeof(urlBuffer), "%s/%s?table=%s&player=hosttest%s&bin=1",
           base, path, table, extra);
  return fetchBinary(urlBuffer, buf, maxLen);
}

static int fail(const char *msg) {
  fprintf(stderr, "FAIL: %s\n", msg);
  exit(1);
}

int main(int argc, char **argv) {
  base = argc > 1 ? argv[1] : "http://localhost:8080";
  table = argc > 2 ? argv[2] : "dev3";
  int wantHands = argc > 3 ? atoi(argv[3]) : 1;

  Game game;
  Tables tables;

  /* 1. Table list must parse into the Tables struct */
  long n;
  snprintf(urlBuffer, sizeof(urlBuffer), "%s/tables?dev=1&bin=1", base);
  n = fetchBinary(urlBuffer, &tables, sizeof(tables));
  if (n < 1 || tables.count == 0) fail("could not fetch table list");
  if (n != 1 + tables.count * (long)sizeof(Table)) fail("tables blob size mismatch");
  printf("tables ok: %d tables, first=%s (%s) players=%s\n",
         tables.count, tables.table[0].table, tables.table[0].name, tables.table[0].players);

  /* 2. Play hands */
  int hands = 0, moves = 0, sawFlop = 0;
  int prevRound = -1;
  for (int iter = 0; iter < 100000 && hands < wantHands; iter++) {
    memset(&game, 0, sizeof(game));
    n = apiCall("state", "", &game, sizeof(game));
    if (n < 165) fail("state blob too short");
    if (n != 165 + game.playerCount * (long)sizeof(Player)) fail("state blob size mismatch");

    if (game.round > 5) fail("round out of range");
    if (game.playerCount > 8) fail("player count out of range");
    if (game.validMoveCount > 5) fail("valid move count out of range");

    if (game.round != prevRound) {
      printf("round %d | pot %-4d | board '%s' | you '%s'\n",
             game.round, game.pot, game.community, game.players[0].hand);
      prevRound = game.round;
    }

    /* Street/board consistency, exactly what the client renders */
    size_t cc = strlen(game.community);
    if (cc % 2) fail("community string has odd length");
    if (game.round == 2 && cc != 6) fail("flop must show 3 community cards");
    if (game.round == 3 && cc != 8) fail("turn must show 4 community cards");
    if (game.round == 4 && cc != 10) fail("river must show 5 community cards");
    if (cc >= 6) sawFlop = 1;

    /* Hole cards: ours visible (4 chars, no '?'), opponents masked pre-showdown */
    if (game.round >= 1 && game.round <= 4 && game.players[0].status == 1) {
      if (strlen(game.players[0].hand) != 4 || strchr(game.players[0].hand, '?'))
        fail("own hole cards must be visible");
      for (int i = 1; i < game.playerCount; i++)
        if (game.players[i].status == 1 && strcmp(game.players[i].hand, "????") != 0)
          fail("opponent hole cards must be masked in-hand");
    }

    if (game.round == 5) {
      hands++;
      printf("== hand %d complete: %s\n", hands, game.lastResult);
      if (!game.lastResult[0]) fail("no result text at hand end");
      if (hands >= wantHands) break;
      /* wait until the next hand actually starts before counting again */
      do {
        usleep(300000);
        n = apiCall("state", "", &game, sizeof(game));
        if (n < 165) fail("state blob too short between hands");
      } while (game.round == 5 || game.round == 0);
      prevRound = -1;
      continue;
    }

    /* Our turn: pick check/call/fold from the server-sent codes, like
     * requestPlayerMove does (it never hardcodes codes) */
    if (game.activePlayer == 0 && game.validMoveCount > 0 && !game.viewing) {
      const char *code = NULL;
      for (int pass = 0; pass < 2 && !code; pass++)
        for (int i = 0; i < game.validMoveCount; i++) {
          const char *m = game.validMoves[i].move;
          if ((pass == 0 && strcmp(m, "ch") == 0) || (pass == 1 && strcmp(m, "ca") == 0)) {
            code = m;
            break;
          }
        }
      if (!code) code = game.validMoves[0].move; /* fold */
      char path[16];
      snprintf(path, sizeof(path), "move/%s", code);
      if (apiCall(path, "", &game, sizeof(game)) < 0) fail("move call failed");
      moves++;
    }

    usleep(150000); /* poll ~6x/sec like a FujiNet client */
  }

  if (hands < wantHands) fail("did not complete requested hands in time");
  printf("PASS: %d hand(s), %d move(s) made, flop seen: %s\n",
         hands, moves, sawFlop ? "yes" : "no");
  return 0;
}
