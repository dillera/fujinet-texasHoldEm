# Texas Hold 'Em for the Bally Astrocade

A standalone Z80 assembly client, in the `o2/` mold: the shared C core
cannot fit this machine, so the game is written to it. It talks to the
Texas Hold'em server through the FujiNet Astrocade cartridge — the RP2040
mailbox cart from `fujinet-firmware/pico/astrocade` — and renders with
the Lynx port's screen plan, because the Lynx's 160x102 display is this
hardware's exact resolution.

Converted from [fujinet-5cardstud](https://github.com/dillera/fujinet-5cardstud)'s
Astrocade client, whose README documents the network and rendering
lessons this one inherits. Built and tested against a live server in MAME
through a real fujinet-pc-rs232.

## Building and running

    ./build.sh                # build/texas.bin, exactly 8192 bytes
    ./run.sh                  # MAME with the fujinet cart device
    make smoke                # headless end-to-end test (see below)

Environment:

  * `ENDPOINT=` — game server, default `https://th.carr-designs.com/`.
    Regenerated into `build/endpoint.inc` on every build.
  * `DEMO=1` — assemble the static mock table (`demo.inc`) instead of the
    game: every drawing path with zero network, for art and layout work.
  * `ZMAC=` — assembler override. Otherwise zmac is taken from `PATH`,
    then `~/Workspace/zmac-1.3/zmac`, then `$FUJI_PICO/tools/zmac/zmac`.
  * `FUJI_PICO=` — the cartridge bring-up tree, only consulted as the last
    place to look for zmac.

Unlike the 5 Card Stud client, this port is self-contained: `tools/checkrom.py`
is vendored here and `fujilib.inc` / `HVGLIB.H` live in the port, so a build
needs no particular branch of the firmware tree checked out. Those three are
copies of the bring-up's `testrom/` files — keep them in step.

`run.sh` expects the MAME tree with the fujinet cart device grafted in
(`pico/astrocade/emu/apply.sh`) at `MAME_DIR` (default `~/Workspace/mame`)
and a fujinet-pc BoIP listener at `FUJINET_TCP` (default 127.0.0.1:9995).
At the on-screen menu, keypad **1** starts the game.

`make assets` regenerates `assets/font.inc` and `assets/cardart.inc` from
the Lynx port's art (`tools/mkfont.py`, `tools/mkcards.py`); the outputs
are committed, so this is only needed after art changes.

## The cartridge budget

The cart serves an 8K window; the mailbox owns 1B00H up, so code and data
end at 1AFFH — 6,912 bytes, enforced by `checkrom.py` and itemised by
`tools/checksize.py` on every build (the `MB_*` labels in `texas.asm` are
its module fences). `build.sh` stamps the `FUJI` claim signature at
1CFCH, so when this image is booted over the network the cart keeps the
mailbox alive for it.

RAM is screen RAM, full stop. 90 visible lines use 4000H–4E0FH and
everything above is the game's — see the map in `texas.asm`. Interrupts
stay off for the program's whole life (fujilib's contract: with I = 0,
refresh strays land in OS ROM and never hit the hotspots).

## The table

40x15 character cells over 160x90 at 2bpp, four colours: felt green,
black, red, white. Everything rides one alignment trick — at 2bpp four
pixels are one byte, and the whole layout lives on a 4-pixel grid, so no
blit in the game ever shifts.

```
r0    table name                                            ! (net error)
r1    top seat names
r2-4  top seat hands, with their bets in the gaps
r5    mid seat names/bets  |  STREET LABEL c16-23  |
r6-8  mid seat hands       |  COMMUNITY BOARD c14-24  |
r9-11 bottom seat hands (yours centre, on the board's own axis)
r12   bottom seat names/bets
r13   PURSE n  BET n  POT n                                 move clock
r14   move menu, or WAITING ON <name> / the last result
```

Cards are 12x17 pixels on an 8-pixel pitch, so a covered card shows its
left 8 pixels: the black seam column, the rank, and the suit. A two-card
hand is 20 pixels where 5 Card Stud's five-card one was 44, and that
reclaimed width is what the community board lives in.

## Deltas from 5 Card Stud

* **Wire format.** `community[11]` is inserted after `viewing` at offset
  87, shifting everything from `validMoveCount` on by +11: 98, 99, 164,
  165, and `sizeof(Game)` 418 -> 429. Because `net.inc` was written
  against the symbols, changing the EQUs in `fujinet.inc` was the whole
  protocol change — no code moved. `player.hand` keeps its 11-byte width
  but carries 2 hole cards: `????` masked, `??` folded, the real chars at
  the showdown.
* **The community board** is `DRWHND` again, five cards at row 6 col 14.
  The showdown flip needs no code at all: the server swaps `????` for the
  real characters and the same loop redraws whatever arrives.
* **A street label** (`PRE-FLOP`/`FLOP`/`TURN`/`RIVER`/`SHOWDOWN`)
  replaces the `ROUND n` indicator, as 8 space-padded bytes per round so
  `round*8` indexes straight in and `TXTN`'s fixed field self-clears.
  The round is clamped first — `VALID8` checks the reply *length*, never
  the round, and this indexes a table.
* **`DRWHND` lost its sliver path.** In stud the first `??` was the hole
  card peeking from under the face-up ones; Hold'em has no such card, so
  every masked card is a whole one and `DRWHLF`/`CARDHF` are gone.
* **Shrink handling.** Rendering is opaque, so only content that got
  *shorter* needs help, and `CHKNEW`'s full clear only fires on a new hand
  or a seat count change. Two Hold'em cases slip past it: a fold turning
  `????` into `??`, and the board emptying. `HNDBLK` blanks just the
  vacated tail — never anything still on screen, so nothing flickers.
* **The move menu had to be rebuilt.** The server offers five moves
  routinely (fold / call / two raise sizes / all-in) with labels up to 9
  characters, which wants 65 of this row's 40 columns. Names are squeezed
  the way the C clients' `compactMoveName()` does — `call 5` -> `C5`,
  `raise 15` -> `R15`, `all-in` -> `ALLIN` — and the stride comes from a
  table indexed by the move count, so five moves fill cols 0-39 exactly
  and shorter menus still show their names in full.
* **Choosing a move.** The menu has no digits: the highlighted entry
  (white on black) is moved with the stick, one step per push, or by
  twisting the knob, which splits the menu into equal arcs of its travel,
  and the trigger bets it. The cursor starts on the second move
  (call/check) each turn, as in the C clients. The knob only takes over
  once it has turned 6 steps from where it rested, so it neither jitters
  between neighbours nor snaps back over a choice made with the stick.
  Right is later: the pot reads higher twisting right (checked in MAME).
* **Sound.** Every cue in `src/platform-specific/sound.h` is here, with
  the Intellivision port's pitches: join, your turn, the tick of your move
  clock (each poll that changes it), cursor and cursor-at-an-end, select,
  a noise click per card dealt (seats and board), the chip sweep at a new
  street, player joined/left, and the showdown fanfare. Event cues are
  queued while `CHKNEW` examines the poll and played after the render, so
  the news is on screen when it sounds.
* **Seat geometry.** Two-card hands are re-anchored: the centre seats sit
  on the board's own axis (px 78), the right seats align to the right edge
  of their name field. The top seats' bets moved down onto their hand row,
  because row 1 cannot hold three lots of name + chip + amount (42 columns
  in 40) — an overlap inherited from 5 Card Stud that only showed when two
  particular seats both had live bets, but which Hold'em, where every seat
  in the hand bets on every street, would have painted constantly.

## Controls

    stick / keypad arrows   move through lists, turn the name wheel
    stick left/right, knob  move the highlight along the move menu
    trigger                 select / join / accept / bet the highlighted move
    keypad 0                poll now
    CE                      leave the table (name screen from the list)
    .                       how to play

## Testing

`make smoke` runs MAME headless with `emu/smoke.lua`: launch from the OS
menu, accept the default name, join a table by keypad digit, then every 3
seconds twist the knob and pull the trigger so some presses land inside
real move windows (the AI ROOM bots keep the hand moving), snapshot to
`build/astrocde/0000.png`.
`FUJINET_DEBUG=1` (default) logs every mailbox transaction; a `/state` for
an N-player table reads back exactly `165 + 33*N` bytes, and a `/move`
shows as an OPEN two bytes longer than `/state`'s.

`emu/resettest.lua` is the RESET-continuity check: join, soft-reset the
console mid-session, rejoin, and confirm the sequence numbers continue
instead of restarting — they come from the cart's persisted ACKSEQ, never
a local counter.

Against a local server:

```sh
cd <servers-repo>/fujinet-game-system/texasholdem/server && go run .
ENDPOINT=http://127.0.0.1:8080/ ./build.sh && ./run.sh
```

The dev rooms (`?table=dev1..dev7`, 1-7 bots) are hidden from the table
list but joinable directly, and are the quickest way to a table that
always has action.

## Status

Working end to end against a live server: table list, join, live rendering
of multi-player bot tables across every street, the community board, the
street label, moves, the showdown reveal, leave, the last-result banner,
the full cue set, and RESET continuity. Not yet done: appkey persistence
for the username and the lobby server override (the 5 Card Stud client
does not have them either), and nothing has run on real hardware, because
the cartridge itself has not been built.

## Bank switching

Firmware protocol v2 supports banked carts: `fujilib.inc` now carries the
`FNBKSEL`/`FNBKMAX` equates (one read maps a 4K image page into
2000H-2FFFH with the mailbox fully live; the high half never moves). This
client still fits the single 8K window and does not use them -- see
`firmware/include/fuji_mailbox.h` in fujinet-firmware for the scheme.
