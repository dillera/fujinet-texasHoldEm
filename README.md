# fujinet-5cardstud → Texas Hold'em

Multi-platform 8-bit FujiNet poker client, originally @ericcarrgh's 5 Card Stud
client, migrated on this branch to play **Texas Hold'em** against the
`texasholdem` server in [dillera/servers](https://github.com/dillera/servers)
(`fujinet-game-system/texasholdem`).

## What changed for Texas Hold'em

* `src/misc.h` - the packed `Game` struct gained `char community[11]` (up to 5
  shared cards). The binary layout must byte-for-byte match the server's
  `bin=1` serializer; both sides carry tests that lock the layout.
* `src/gamelogic.c` - `drawCards()` rewritten: 2 hole cards per player
  (server-side masking - opponents arrive as `????` until showdown), community
  board rendered in the table center with per-street reveal animation.
* `src/apple2/vars.h` - pot display shifted below the community board.
* `src/screens.c` - help text now describes Hold'em.
* `src/main.c` - default endpoint points at a local server for development.

Betting UI needed no changes: move codes (`FO CH CA BL BH RL RH AI`) and labels
are entirely server-supplied.

## Building the Apple II client

Requirements: `cc65` on PATH, Java (for AppleCommander `ac`), and the
AppleCommander `acx` CLI.

```bash
make apple2
# produces r2r/apple2/fcs.po (bootable ProDOS disk)
```

## Testing against a local server

Start the server:

```bash
cd <servers-repo>/fujinet-game-system/texasholdem/server
go run .          # listens on :8080
```

Protocol end-to-end test on the host (plays real hands over the same binary
protocol the 8-bit clients use, using the exact packed struct layout):

```bash
cc -Wall -o /tmp/holdem_host_test support/host-test/holdem_host_test.c
/tmp/holdem_host_test http://localhost:8080 dev3 2   # play 2 hands on dev3
```

On real hardware or an emulator with a FujiNet device, boot `fcs.po`. The
default endpoint in `src/main.c` is `http://127.0.0.1:8080/` (the FujiNet `N:`
device performs the HTTP) - change it, or set the lobby appkey, to point
elsewhere.
