# fujinet-texasHoldEm

Multi-platform 8-bit **Texas Hold 'Em** client for [FujiNet](https://fujinet.online),
playing against the `texasholdem` server in
[dillera/servers](https://github.com/dillera/servers)
(`fujinet-game-system/texasholdem`). Derived from @ericcarrgh's
[fujinet-5cardstud](https://github.com/dillera/fujinet-5cardstud) client, which
continues separately as the 5 Card Stud game.

All game logic lives on the server. Clients poll `/state`, render it, and send
back server-supplied 2-character move codes — so the betting UI never needs
client-side poker rules.

## Platform status

| Platform | Status | Build | Output |
|----------|--------|-------|--------|
| Apple II | ✅ playable | `make apple2` | `r2r/apple2/texas.po` (boots straight into the game) |
| CoCo 1/2/3 | ✅ playable | `make coco-dist` | `r2r/coco/texas.dsk` (loader auto-picks TEXAS12/TEXAS3) |
| Atari 8-bit | ✅ playable | FastBasic, see below | `texas.xex` |
| MS-DOS | 🔨 builds, untested | `./make-exp msdos` | `r2r/msdos/texas.exe` + `texas.img` |
| Coleco Adam | 🔨 builds, untested | `./make-exp adam` (needs z88dk) | `r2r/adam/texas.ddp` |
| Intellivision | ✅ playable | `cd intv && make` | `intv/texas.rom` (jzIntv) + `texas.bin`/`.cfg` (SD via PiRTO II) |
| ColecoVision | ✅ playable (MAME) | `make FUJINET_LIB=<fujinet-lib-experimental dir> PLATFORMS=coleco coleco` | `r2r/coleco/texas.rom` (32K FujiNet cart) |
| NES | ✅ playable (MAME) | `make FUJINET_LIB=<fujinet-lib-experimental dir> PLATFORMS=nes nes` | `r2r/nes/texas.nes` (NROM FujiNet cart) |
| Bally Astrocade | ✅ playable | `cd astrocade && ./build.sh` | `astrocade/build/texas.bin` (8K FujiNet cart image) |
| C64 | ⬜ not yet converted | — | — |

## What changed from 5 Card Stud

* Packed `Game` struct gained `community[11]` (up to 5 shared cards). The
  binary layout must byte-for-byte match the server's `bin=1` serializer —
  locked by tests on both sides (`support/host-test/holdem_host_test.c` here,
  `bin_protocol_test.go` server-side).
* `drawCards()`: 2 hole cards per player with server-side masking (`????`
  until showdown, `??` folded), community board center-table with per-street
  reveal, showdown flip.
* Street indicator (`PRE-FLOP`/`FLOP`/`TURN`/`RIVER`/`SHOWDOWN`) on the pot row.
* Moves render in a fixed 5-character field; full table redraw at street
  transitions (single-buffer platforms).
* Rebranded logos/help; per-platform layout tuned so nothing overlaps the board.

## C client (Apple II, CoCo, MS-DOS, Coleco Adam, ColecoVision, NES, C64)

Shared core in `src/` + per-platform layer in `src/<platform>/`. Toolchains:
cc65 (Apple II/C64/NES), cmoc (CoCo), OpenWatcom v2 (MS-DOS), z88dk
(Adam/ColecoVision).

```bash
make apple2         # needs cc65, Java + AppleCommander ac/acx CLIs
make coco-dist      # needs cmoc, lwasm, toolshed decb
./make-exp msdos    # needs OpenWatcom v2: export WATCOM=...; INCLUDE=$WATCOM/h;
                    #   PATH=$WATCOM/binl:$PATH  (uses fujinet-lib-experimental)
./make-exp adam     # needs z88dk WITH Adam EOS support (eos.h/eos.lib - not
                    #   in upstream z88dk); e.g. `defoogi ./make-exp adam`
                    #   runs it in the fozztexx/defoogi docker toolchain
```

Adam card/frame tiles and the Namco font are generated from the MS-DOS CGA
master art: `python3 support/tms9918/convert-tiles.py` regenerates
`src/adam/font.bin` + `src/adam/udg.h` after any `src/msdos/charset.h` change.

The ColecoVision and NES ports are side-ported from fujinet-5cardstud's and
build against [fujinet-lib-experimental](https://github.com/FozzTexx/fujinet-lib-experimental)
(its `coleco-target` / `add-nes` branches; pass the checkout as a directory).
The NES has no per-cell colour, so `python3 src/nes/mkchr.py` bakes every
glyph+colour pair from the ColecoVision font and card art (`src/coleco/font.bin`,
`udg.h`) into NES tiles; rerun it after changing either. Headless MAME checks
against a live fujinet-pc: `make coleco-smoke` / `make nes-smoke` (see the
Makefile for `EXPECT=`/`SCRIPT=`), and `make nes-play` for a window.

## Atari client (FastBasic)

`atari-fastbasic-version/texas.bas` — standalone FastBasic client using
FujiNet's JSON parsing (no C core). Build with
[FastBasic](https://github.com/dmsc/fastbasic) v4.7+; the FujiNet `NOPEN`
syntax needs a target combining the Atari target with `fujinet.syn`
(e.g. copy `atari-int.tgt` to `atari-int-fn.tgt` and add `syntax: fujinet.syn`):

```bash
fastbasic -t:atari-int-fn texas.bas -o texas.xex
```

## Intellivision client (IntyBASIC)

`intv/` — standalone IntyBASIC client, converted from the
[fujinet-5cardstud](https://github.com/dillera/fujinet-5cardstud) `intv/`
client (whose source comments document the mailbox/rendering lessons in
detail). Talks to FujiNet through the PiRTO II cartridge's memory-mapped
mailbox at `$9C00`; parses the `bin=1` state in place out of the RX buffer.
Needs [IntyBASIC](https://github.com/nanochess/IntyBASIC) and `as1600`
(from jzIntv's SDK):

```bash
cd intv
make            # texas.rom (Intellicart, for jzIntv) + texas.bin/.cfg (SD)
./run.sh        # build + launch in a FujiNet-patched jzIntv over BoIP
                # (FUJINET_TARGET=localhost:9995 against fujinet-firmware)
```

Controls: disc + side button everywhere; keypad `CLEAR` = table menu,
`ENTER` (hold) = show purses. Hold'em deltas from the 5 Card Stud client:
wire offsets shift +11 past `viewing` (`community[11]` at 87), 2 hole cards
per seat, community board rows 4-5 with the street label above and pot/purse
below, and the move menu scales name width to the move count (Hold'em
routinely offers 4 moves).

## Astrocade client (Z80 assembly)

`astrocade/` — standalone Z80 client, converted from the
[fujinet-5cardstud](https://github.com/dillera/fujinet-5cardstud) `astrocade/`
client. Talks to FujiNet through the RP2040 cartridge's memory-mapped mailbox
and parses the `bin=1` state in place out of the reply window; nothing is
buffered. Needs `zmac` 1.3 (found on `PATH`, or at `~/Workspace/zmac-1.3`);
the ROM layout checker is vendored, so no firmware checkout is required.

```bash
cd astrocade
./build.sh      # build/texas.bin, exactly 8192 bytes, "FUJI" claim stamped
./run.sh        # build + launch in a FujiNet-patched MAME over BoIP
                # (FUJINET_TCP=127.0.0.1:9995 against a fujinet-pc)
make smoke      # headless end-to-end test, snapshots the table
DEMO=1 ./build.sh   # static mock table: every drawing path, zero network
```

Controls: stick/keypad arrows move, trigger selects, keypad `1`-`5` choose a
move, `0` polls now, `CE` leaves the table, `.` shows how to play. Hold'em
deltas from the 5 Card Stud client: the wire offsets shift +11 past `viewing`
(`community[11]` at 87), 2 hole cards per seat, a 5-card community board at
the centre of the table with the street label above it and the pot moved onto
the money row, and a move menu that squeezes server labels
(`raise 15` -> `R15`) onto a 40-column status bar — Hold'em routinely offers
five moves. See `astrocade/README.md` for the full list.

## Testing against a local server

```bash
cd <servers-repo>/fujinet-game-system/texasholdem/server
go run .          # listens on :8080
```

Clients default to `http://127.0.0.1:8080/` (the FujiNet device/bridge performs
the HTTP; a lobby appkey overrides the default when present). Pick a room from
the table list — the dev rooms (`?table=dev1..dev7`, 1-7 bots) are hidden from
the list but joinable directly. Different platforms can sit at the same table.

Host-side test tools (no emulator needed):

```bash
# Protocol E2E: plays real hands via the exact packed struct the clients read
cc -Wall -o /tmp/holdem_host_test support/host-test/holdem_host_test.c
/tmp/holdem_host_test http://localhost:8080 dev3 2

# UI harness: renders the real shared drawing code into a text grid,
# replaying hand frames in double-buffer and single-buffer modes
cc -std=gnu99 -Wno-implicit-function-declaration -I support/host-test/ui \
   -include support/host-test/ui/host_vars.h src/gamelogic.c \
   support/host-test/ui/mock_platform.c support/host-test/ui/ui_driver.c \
   -o /tmp/ui_test && /tmp/ui_test        # add -DHOST_COCO3 for CoCo mode
```

## Credits

Original 5 Card Stud client by Eric Carr (@ericcarrgh). Texas Hold 'Em
conversion built against the FujiNet game-system server.
