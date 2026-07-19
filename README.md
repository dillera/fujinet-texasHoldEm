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

## C client (Apple II, CoCo, MS-DOS, C64)

Shared core in `src/` + per-platform layer in `src/<platform>/`. Toolchains:
cc65 (Apple II/C64), cmoc (CoCo), OpenWatcom v2 (MS-DOS).

```bash
make apple2         # needs cc65, Java + AppleCommander ac/acx CLIs
make coco-dist      # needs cmoc, lwasm, toolshed decb
./make-exp msdos    # needs OpenWatcom v2: export WATCOM=...; INCLUDE=$WATCOM/h;
                    #   PATH=$WATCOM/binl:$PATH  (uses fujinet-lib-experimental)
```

## Atari client (FastBasic)

`atari-fastbasic-version/texas.bas` — standalone FastBasic client using
FujiNet's JSON parsing (no C core). Build with
[FastBasic](https://github.com/dmsc/fastbasic) v4.7+; the FujiNet `NOPEN`
syntax needs a target combining the Atari target with `fujinet.syn`
(e.g. copy `atari-int.tgt` to `atari-int-fn.tgt` and add `syntax: fujinet.syn`):

```bash
fastbasic -t:atari-int-fn texas.bas -o texas.xex
```

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
