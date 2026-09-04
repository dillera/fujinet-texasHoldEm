' texas.bas -- Texas Hold'em for Intellivision, entry point + state machine.
'
' Converted from fujinet-5cardstud/intv/5card.bas the same way the C and
' FastBasic clients were converted: wire offsets shift +11 past viewing
' (community[11] inserted at 87, see state.bas), 2 hole cards per seat
' instead of 5, a 5-card community board center-table, and a street label
' (PRE-FLOP/FLOP/TURN/RIVER/SHOWDOWN). The betting UI is unchanged -- move
' codes and labels are server-supplied, so the client needs no poker rules.
'
' Screen flow (simplified from the C clients' full parity, see the plan's
' Risks section): name entry (disc letter picker, falls back to it whenever
' the appkey read fails or comes back empty) -> table select (always shown
' at boot; the server endpoint is a compiled-in default rather than an
' appkey-persisted URL, since table select runs every boot anyway) -> game
' loop -> in-game menu (keypad CLEAR: quit table or resume).
'
' Rendering only fully clears the screen when the table layout actually
' changes (see render_game); otherwise it updates cells in place, matching
' the CoCo/MSX C clients' SINGLE_BUFFER mode -- IntyBASIC has no true
' page-flip double buffering, so avoiding a per-poll CLS is what keeps the
' screen from flashing blank on every state refresh.
'
' GOTO boot_start jumps over every INCLUDE below before any of it runs.
' This isn't optional: fujinet.bas/gfx.bas are libraries whose PROCEDURE
' (and gfx.bas's DATA) bodies are meant to be reached only via GOSUB, per
' the IntyBASIC manual's warning that falling into a PROCEDURE or DATA
' block by straight-line execution corrupts the return stack. Since
' INCLUDE pastes their text in at this point, and this file's own
' DATA/PROCEDURE blocks (below) have the same requirement, the single
' cheapest fix is to never let the CPU reach any of it except via GOSUB --
' hence jumping straight to boot_start before the includes even begin.
    GOTO boot_start

    INCLUDE "constants.bas"
    INCLUDE "input.bas"
    INCLUDE "fujinet.bas"
    INCLUDE "gfx.bas"
    INCLUDE "state.bas"
    INCLUDE "sound.bas"

    CONST ROWCELLS = 20
    CONST STATUS_ROW = 220

    CONST COL_NAME  = FG_WHITE + BG_DARKGREEN
    CONST COL_HILITE = FG_YELLOW + BG_DARKGREEN
    CONST COL_STATUS = FG_WHITE + BG_BLACK

' Seat base offsets (name row), seat 0 is always you (bottom-center).
seat_name_off:
    DATA 167, 140, 80, 20, 7, 34, 94, 154

' playerCountIndex: for a given playerCount (2-8, row = playerCount-2),
' the seat assigned to server player index i (array position i). 255 =
' unused. Ported unchanged from the C client's seat-assignment table.
seatmap:
    DATA 0,4,255,255,255,255,255,255       ' 2 players
    DATA 0,2,6,255,255,255,255,255         ' 3
    DATA 0,2,4,6,255,255,255,255           ' 4
    DATA 0,2,3,5,6,255,255,255             ' 5
    DATA 0,2,3,4,5,6,255,255               ' 6
    DATA 0,2,3,4,5,6,7,255                 ' 7
    DATA 0,1,2,3,4,5,6,7                   ' 8

lit_n_colon: DATA 78,58
' "https://th.carr-designs.com/" -- the public Texas Hold'em server
' (src/main.c's serverEndpoint default).
lit_https: DATA 104,116,116,112,115,58,47,47,116,104,46,99,97,114,114,45,100,101,115,105,103,110,115,46,99,111,109,47
lit_tables: DATA 116,97,98,108,101,115
lit_state: DATA 115,116,97,116,101
lit_move: DATA 109,111,118,101,47
lit_leave: DATA 108,101,97,118,101
' "&be=1" (big-endian) dropped: the Go server's binary.BigEndian path is
' the road much less travelled (CoCo, 6809, is the only other client that
' ever requests it -- everything else in this client family is little-
' endian x86/6502/Z80), and pot/bet corruption that always landed on
' exact multiples of 256 (i.e. a real small value sitting in the high
' byte, low byte zero) pointed straight at a byte-order mismatch on that
' path specifically. Little-endian is what the rest of the ecosystem
' exercises constantly.
lit_qbin: DATA 63,98,105,110,61,49
lit_abin: DATA 38,98,105,110,61,49
lit_qtable: DATA 63,116,97,98,108,101,61
lit_aplayer: DATA 38,112,108,97,121,101,114,61

' Street labels, 8 space-padded ASCII bytes per round value (round*8
' indexes straight into this), drawn via draw_field like every other
' text field. Row 0 (round=0, waiting) is deliberately blank so the
' label cell range self-clears between hands without special-casing.
street_names:
    DATA 32,32,32,32,32,32,32,32           ' 0 waiting
    DATA 80,82,69,45,70,76,79,80           ' 1 PRE-FLOP
    DATA 70,76,79,80,32,32,32,32           ' 2 FLOP
    DATA 84,85,82,78,32,32,32,32           ' 3 TURN
    DATA 82,73,86,69,82,32,32,32           ' 4 RIVER
    DATA 83,72,79,87,68,79,87,78           ' 5 SHOWDOWN

    CONST LEN_HTTPS = 28

    ' Lobby appkey: creator 1 / app 1, key = this game's registered slot.
    ' Texas Hold'em is lobby appkey 8 (see fujinet-texasHoldEm/src/misc.h
    ' AK_LOBBY_KEY_SERVER -- 5 Card Stud's was 1; using 8 here means table
    ' selection can't overwrite the 5CS lobby hand-off URL). The name key
    ' (creator 1 / app 1 / key 0) is the lobby-shared username, unchanged.
    ' The C clients' prefs appkey (creator $BEBE / app 1) only stores
    ' help-seen/color-mode flags for screens this client doesn't have, so
    ' it's deliberately unused here.
    CONST AK_LOBBY_KEY_SERVER = 8

    ' Selected table id, 9 bytes (8 + NUL). SC_ENDPT used to double as this
    ' buffer, but it's now needed for the full lobby-supplied endpoint, so
    ' the table id gets its own slot -- free RAM just past fujinet.bas's
    ' own SC_* buffers (which stop at SC_QUERY $9150 + 48 = $9180) and
    ' well below the $9C00 mailbox.
    CONST SC_TABLE = $9180

' ---------------------------------------------------------------------------
' Globals
' ---------------------------------------------------------------------------
    DIM gs_i, gs_j, #gs_c
    DIM ne_cur, ne_len
    DIM ne_buf(8)
    DIM tbl_count, tbl_sel
    DIM sel_seat, sel_i
    DIM poll_wait
    DIM mv_sel, mv_count
    DIM mv_col(5)
    DIM mvcode_a, mvcode_b
    DIM has_move
    DIM #tmp_addr
    DIM #tmp_num
    DIM #prev_pot
    DIM #prev_purse
    DIM prev_bet(8)
    DIM prev_cards(8)
    DIM prev_community
    DIM street_redraw
    DIM deal_count
    DIM #tmp_expect
    DIM #tmp_hash
    DIM #prev_result_hash
    DIM first_poll
    DIM prev_active, turn_changed

    DIM df_pos, df_len, #df_color, df_i, df_c, df_stop
    DIM #df_src

    ' split_room_url locals (see procedure below)
    DIM sp_i, sp_found, sp_ok, sp_j, sp_k, sp_c, sp_valid, sp_m

' ---------------------------------------------------------------------------
' draw_field: render df_len ASCII bytes from #df_src onto the screen at
' BACKTAB offset df_pos, in color #df_color. Uppercases (MODE 1 has no
' lowercase GROM; the wire is lowercase anyway), stops at a NUL and pads
' the rest of the field with spaces, and clamps anything outside the
' printable GROM range (32-95) to a space rather than drawing garbage.
' ---------------------------------------------------------------------------
' ---------------------------------------------------------------------------
' fill_bg: felt-table background -- green everywhere except the status row
' (which stays black). Call right after every CLS.
' ---------------------------------------------------------------------------
fill_bg: PROCEDURE
    FOR gs_i = 0 TO STATUS_ROW - 1
        #BACKTAB(gs_i) = COL_NAME
    NEXT gs_i
END

draw_field: PROCEDURE
    df_stop = 0
    FOR df_i = 0 TO df_len - 1
        df_c = PEEK(#df_src + df_i) AND 255
        IF df_c = 0 THEN df_stop = 1
        IF df_stop THEN
            df_c = 32
        ELSEIF df_c >= 97 AND df_c <= 122 THEN
            df_c = df_c - 32
        END IF
        IF df_c < 32 OR df_c > 95 THEN df_c = 32
        #BACKTAB(df_pos + df_i) = (df_c - 32) * 8 + #df_color
    NEXT df_i
END

' ---------------------------------------------------------------------------
' compose_url: build "N:<endpoint><path...><suffix>" directly into FN_TX.
' Callers set gs_path (0=tables 1=state 2=move 3=leave) and, for move,
' mvcode_a/mvcode_b (the 2-char move code) beforehand.
' ---------------------------------------------------------------------------
    DIM gs_path
compose_url: PROCEDURE
    #fn_txlen = 0
    #fn_src = VARPTR lit_n_colon(0) : fn_len = 2 : GOSUB fn_putstr
    #fn_src = SC_ENDPT : ls_max = 65 : GOSUB fn_strlen : GOSUB fn_putstr

    IF gs_path = 0 THEN
        #fn_src = VARPTR lit_tables(0) : fn_len = 6 : GOSUB fn_putstr
        #fn_src = VARPTR lit_qbin(0) : fn_len = 6 : GOSUB fn_putstr
    ELSE
        IF gs_path = 1 THEN
            #fn_src = VARPTR lit_state(0) : fn_len = 5 : GOSUB fn_putstr
        ELSEIF gs_path = 2 THEN
            #fn_src = VARPTR lit_move(0) : fn_len = 5 : GOSUB fn_putstr
            POKE (FN_TX + #fn_txlen), mvcode_a : #fn_txlen = #fn_txlen + 1
            POKE (FN_TX + #fn_txlen), mvcode_b : #fn_txlen = #fn_txlen + 1
        ELSE
            #fn_src = VARPTR lit_leave(0) : fn_len = 5 : GOSUB fn_putstr
        END IF

        #fn_src = VARPTR lit_qtable(0) : fn_len = 7 : GOSUB fn_putstr
        #fn_src = SC_TABLE : ls_max = 9 : GOSUB fn_strlen : GOSUB fn_putstr   ' table id, NUL-terminated within its 9-byte field
        #fn_src = VARPTR lit_aplayer(0) : fn_len = 8 : GOSUB fn_putstr
        #fn_src = SC_NAME : ls_max = 9 : GOSUB fn_strlen : GOSUB fn_putstr    ' player name, likewise
        #fn_src = VARPTR lit_abin(0) : fn_len = 6 : GOSUB fn_putstr
    END IF
END

' ---------------------------------------------------------------------------
' split_room_url: given a lobby-supplied "https://host/?table=xyz" value
' already sitting in SC_ENDPT with its length in fn_len (as left by
' appkey_read), split it into the bare endpoint (SC_ENDPT, truncated at
' the '?') and the table id (SC_TABLE). Mirrors the C clients'
' welcomeActionVerifyServerDetails() '?' scan. Leaves SC_TABLE empty (a
' leading NUL) if there's no '?', the query isn't "table=...", or the id
' contains anything other than A-Z/a-z/0-9 -- it goes straight into a
' rebuilt query string unescaped, same reasoning as the username check
' above.
' ---------------------------------------------------------------------------
split_room_url: PROCEDURE
    POKE SC_TABLE, 0

    sp_found = 255 ' sentinel: not found (mirrors st_boot.bas's bt_slash convention)
    sp_i = 0
    WHILE sp_i < fn_len
        IF (PEEK(SC_ENDPT + sp_i) AND 255) = 63 THEN ' '?'
            sp_found = sp_i
            EXIT WHILE
        END IF
        sp_i = sp_i + 1
    WEND
    IF sp_found = 255 THEN RETURN

    ' Truncate the endpoint at the '?' regardless of what follows.
    POKE (SC_ENDPT + sp_found), 0

    ' Require "table=" (6 bytes) right after the '?'.
    sp_ok = 0
    IF sp_found + 7 <= fn_len THEN
        sp_ok = 1
        IF (PEEK(SC_ENDPT + sp_found + 1) AND 255) <> 116 THEN sp_ok = 0 ' t
        IF (PEEK(SC_ENDPT + sp_found + 2) AND 255) <> 97  THEN sp_ok = 0 ' a
        IF (PEEK(SC_ENDPT + sp_found + 3) AND 255) <> 98  THEN sp_ok = 0 ' b
        IF (PEEK(SC_ENDPT + sp_found + 4) AND 255) <> 108 THEN sp_ok = 0 ' l
        IF (PEEK(SC_ENDPT + sp_found + 5) AND 255) <> 101 THEN sp_ok = 0 ' e
        IF (PEEK(SC_ENDPT + sp_found + 6) AND 255) <> 61  THEN sp_ok = 0 ' =
    END IF
    IF sp_ok = 0 THEN RETURN

    ' Copy the id: up to 8 bytes, stopping at NUL or '&'.
    sp_j = sp_found + 7
    sp_k = 0
    WHILE sp_k < 8 AND sp_j < fn_len
        sp_c = PEEK(SC_ENDPT + sp_j) AND 255
        IF sp_c = 0 OR sp_c = 38 THEN EXIT WHILE ' NUL or '&'
        POKE (SC_TABLE + sp_k), sp_c
        sp_k = sp_k + 1
        sp_j = sp_j + 1
    WEND
    POKE (SC_TABLE + sp_k), 0

    ' Validate: A-Z/a-z/0-9 only.
    sp_valid = 1
    FOR sp_m = 0 TO sp_k - 1
        sp_c = PEEK(SC_TABLE + sp_m) AND 255
        IF (sp_c < 65 OR sp_c > 90) AND (sp_c < 97 OR sp_c > 122) AND (sp_c < 48 OR sp_c > 57) THEN sp_valid = 0
    NEXT sp_m
    IF sp_valid = 0 THEN POKE SC_TABLE, 0
END

' ---------------------------------------------------------------------------
' write_room_appkey: persist SC_ENDPT + "?table=" + SC_TABLE back to the
' lobby server appkey slot, so a reboot without going back through the
' lobby rejoins the same room (mirrors the C clients' "Update server app
' key in case of reboot"). Builds the payload directly in FN_TX and writes
' it from there -- appkey_write's byte-by-byte copy from #fn_src into
' FN_TX is a safe no-op when #fn_src is FN_TX itself.
' ---------------------------------------------------------------------------
write_room_appkey: PROCEDURE
    #fn_txlen = 0
    #fn_src = SC_ENDPT : ls_max = 65 : GOSUB fn_strlen : GOSUB fn_putstr
    #fn_src = VARPTR lit_qtable(0) : fn_len = 7 : GOSUB fn_putstr
    #fn_src = SC_TABLE : ls_max = 9 : GOSUB fn_strlen : GOSUB fn_putstr

    ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1
    ak_key = AK_LOBBY_KEY_SERVER : ak_mode = 1
    GOSUB appkey_open
    IF fn_ok THEN
        fn_len = #fn_txlen : #fn_src = FN_TX
        GOSUB appkey_write
        GOSUB appkey_close
    END IF
END

' ---------------------------------------------------------------------------
' clear_room_appkey: blank the lobby server appkey slot on a deliberate
' leave, so a later reboot lands on table select instead of silently
' rejoining a table the player just quit.
' ---------------------------------------------------------------------------
clear_room_appkey: PROCEDURE
    ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1
    ak_key = AK_LOBBY_KEY_SERVER : ak_mode = 1
    GOSUB appkey_open
    IF fn_ok THEN
        fn_len = 0 : #fn_src = FN_TX
        GOSUB appkey_write
        GOSUB appkey_close
    END IF
    POKE SC_TABLE, 0
END

' ===========================================================================
' Boot
' ===========================================================================
boot_start:
    MODE 1
    CLS
    GOSUB fill_bg
    GOSUB gfx_init

    PRINT AT 0 COLOR COL_STATUS, "TEXAS HOLDEM"
    PRINT AT 20, "IN GAME, PRESS KEYPAD"
    PRINT AT 40, "CLEAR FOR THE MENU"
    PRINT AT 60, "CONNECTING TO FUJINET"
    GOSUB fn_wait_mailbox
    IF fn_ok = 0 THEN
        PRINT AT 60, "NO CARTRIDGE MAILBOX"
        GOTO halt
    END IF

' ---------------------------------------------------------------------------
' Name: try the lobby appkey first; fall back to the disc letter picker if
' the transaction fails or the stored name is empty.
' ---------------------------------------------------------------------------
    ' Every other network call in this game gets an implicit retry via the
    ' outer poll loop; this one-shot boot-time appkey read didn't, so a
    ' single cold-connection timeout (the RP2040/ESP32 link needing a
    ' moment right after the mailbox first comes up -- the same thing
    ' that made the very first transaction after boot occasionally time
    ' out earlier in testing) meant falling back to manual name entry for
    ' the whole session even though a name was genuinely stored. Retry
    ' once before giving up.
    gs_i = 0
    FOR ak_try = 0 TO 1
        ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1 : ak_key = 0 : ak_mode = 0
        GOSUB appkey_open
        IF fn_ok THEN EXIT FOR
    NEXT ak_try
    IF fn_ok THEN
        #fn_src = SC_NAME : ls_max = 9 : GOSUB appkey_read
        GOSUB appkey_close
        IF fn_len > 0 THEN
            ' Validate every character -- the appkey slot (creator=1,
            ' app=1, key=0) is the *shared* lobby username used by every
            ' FujiNet client on this server, so it can hold stale or
            ' outright incompatible data left by other testing (this
            ' repo's own earlier test runs included). Our name-entry
            ' screen can only ever produce A-Z/0-9, so anything outside
            ' that -- a space, punctuation, an '&' or '?' -- is untrusted:
            ' it goes straight into the /state URL's query string
            ' unescaped, and a stray reserved character there is exactly
            ' the kind of thing that gets the request rejected by the
            ' server (seen as an HTTP 400 page landing in FN_RX, which
            ' render_game then tries to draw as if it were game data).
            gs_i = 1
            FOR gs_j = 0 TO fn_len - 1
                gs_char = PEEK(SC_NAME + gs_j) AND 255
                IF gs_char >= 97 AND gs_char <= 122 THEN gs_char = gs_char - 32 ' fold to uppercase for the check
                IF (gs_char < 65 OR gs_char > 90) AND (gs_char < 48 OR gs_char > 57) THEN gs_i = 0
            NEXT gs_j
        END IF
    END IF
    IF gs_i = 0 THEN GOSUB name_entry_screen

' ---------------------------------------------------------------------------
' Room: check the lobby server appkey (creator 1 / app 1 / key
' AK_LOBBY_KEY_SERVER). If the lobby wrote a room there, split it into
' SC_ENDPT/SC_TABLE and skip straight past table select. Seed the
' compiled-in default endpoint first so SC_ENDPT is always valid even if
' the appkey is empty or the read fails -- compose_url relies on it from
' here on for every request, not just /tables.
' ---------------------------------------------------------------------------
    FOR gs_i = 0 TO LEN_HTTPS - 1
        POKE (SC_ENDPT + gs_i), PEEK(VARPTR lit_https(0) + gs_i) AND 255
    NEXT gs_i
    POKE (SC_ENDPT + LEN_HTTPS), 0
    POKE SC_TABLE, 0

    FOR ak_try = 0 TO 1
        ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1
        ak_key = AK_LOBBY_KEY_SERVER : ak_mode = 0
        GOSUB appkey_open
        IF fn_ok THEN EXIT FOR
    NEXT ak_try
    IF fn_ok THEN
        #fn_src = SC_ENDPT : ls_max = 65 : GOSUB appkey_read
        GOSUB appkey_close
        IF fn_len > 0 THEN
            GOSUB split_room_url
        ELSE
            ' appkey_read always NUL-terminates at fn_len, even when
            ' empty, which would otherwise wipe out the default just
            ' seeded above -- restore it.
            FOR gs_i = 0 TO LEN_HTTPS - 1
                POKE (SC_ENDPT + gs_i), PEEK(VARPTR lit_https(0) + gs_i) AND 255
            NEXT gs_i
            POKE (SC_ENDPT + LEN_HTTPS), 0
        END IF
    END IF

    IF (PEEK(SC_TABLE) AND 255) <> 0 THEN GOTO table_joined

' ===========================================================================
' Table select (re-entered after leaving a table)
' ===========================================================================
table_select:
    CLS
    GOSUB fill_bg
    PRINT AT 0 COLOR COL_STATUS, "CHOOSE A TABLE"
    PRINT AT 40, "REFRESHING..."

    gs_path = 0 : GOSUB compose_url
    #net_readlen = TABLES_MAXLEN
    GOSUB api_call

    ' As with /state: the mailbox transaction can report success (the
    ' RP2040 relayed *a* reply) even when the HTTP request itself was
    ' rejected -- an error page's bytes would otherwise get misread as a
    ' Tables struct. Validate the response length against what the
    ' reported count actually implies before trusting it.
    IF fn_ok = 1 THEN
        #tmp_expect = 1 + (PEEK(FN_RX) AND 255) * TABLE_STRIDE
        IF #net_gotlen < #tmp_expect THEN fn_ok = 0
    END IF

    IF fn_ok = 0 THEN
        PRINT AT 40, "SERVER UNREACHABLE  "
        ' TEMP DEBUG: show the exact outgoing URL so a repeat failure is
        ' diagnosable from a screenshot instead of needing another round trip.
        #df_src = FN_TX : df_pos = 60 : df_len = 20 : #df_color = COL_STATUS
        GOSUB draw_field
        #df_src = FN_TX + 20 : df_pos = 80 : df_len = 20 : #df_color = COL_STATUS
        GOSUB draw_field
        #df_src = FN_TX + 40 : df_pos = 100 : df_len = 20 : #df_color = COL_STATUS
        GOSUB draw_field
        poll_wait = 90
        WHILE poll_wait > 0
            poll_wait = poll_wait - 1
            WAIT
        WEND
        GOTO table_select
    END IF

    tbl_count = PEEK(FN_RX) AND 255
    IF tbl_count > 6 THEN tbl_count = 6
    IF tbl_count = 0 THEN
        PRINT AT 40, "NO TABLES AVAILABLE "
        poll_wait = 90
        WHILE poll_wait > 0
            poll_wait = poll_wait - 1
            WAIT
        WEND
        GOTO table_select
    END IF

    CLS
    GOSUB fill_bg
    PRINT AT 0 COLOR COL_STATUS, "CHOOSE A TABLE"
    FOR gs_i = 0 TO tbl_count - 1
        #tmp_addr = table_addr(gs_i)
        #df_src = #tmp_addr + TBL_NAME : df_pos = 20 + gs_i * 20 + 1 : df_len = 14 : #df_color = COL_NAME
        GOSUB draw_field
        #df_src = #tmp_addr + TBL_PLAYERS : df_pos = 20 + gs_i * 20 + 15 : df_len = 5 : #df_color = COL_NAME
        GOSUB draw_field
    NEXT gs_i

    tbl_sel = 0
    inp_lock = 0
tbl_input:
    WAIT
    GOSUB read_input
    FOR gs_i = 0 TO tbl_count - 1
        #gs_c = COL_NAME
        IF gs_i = tbl_sel THEN #gs_c = COL_HILITE
        #BACKTAB(20 + gs_i * 20) = (62 - 32) * 8 + #gs_c ' '>' cursor glyph
    NEXT gs_i

    IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO tbl_input

    IF inp_dir AND DISC_DOWN THEN
        tbl_sel = tbl_sel + 1
        IF tbl_sel >= tbl_count THEN tbl_sel = 0
        inp_lock = 8
        GOSUB sound_cursor
        GOTO tbl_input
    END IF
    IF inp_dir AND DISC_UP THEN
        IF tbl_sel = 0 THEN tbl_sel = tbl_count
        tbl_sel = tbl_sel - 1
        inp_lock = 8
        GOSUB sound_cursor
        GOTO tbl_input
    END IF
    IF inp_btn_hit = 0 THEN GOTO tbl_input
    GOSUB sound_select

    #tmp_addr = table_addr(tbl_sel)
    FOR gs_i = 0 TO 8
        POKE (SC_TABLE + gs_i), PEEK(#tmp_addr + TBL_ID + gs_i) AND 255
    NEXT gs_i

    ' Update the lobby server appkey so a reboot without going back
    ' through the lobby rejoins this table.
    GOSUB write_room_appkey

table_joined:
' ===========================================================================
' Main game loop
' ===========================================================================
    GOSUB sound_join
    has_move = 0
    poll_wait = 0
    force_redraw = 0
    prev_round = 255      ' sentinel: forces a full CLS on the first render_game
    prev_playercount = 255
    #prev_pot = 65535
    #prev_purse = 65535
    #prev_result_hash = 65535 ' sentinel: max possible real hash is 20*255=5100
    prev_active = 255 ' sentinel: forces the turn cue if we sit down mid-turn
    first_poll = 1 ' arm the baseline on the first poll instead of showing it --
                    ' lastResult can already hold a message from a hand that
                    ' finished before we joined/sat down, which isn't "new"
    prev_community = 0
    FOR gs_i = 0 TO 7
        prev_bet(gs_i) = 255
        prev_cards(gs_i) = 0
    NEXT gs_i

game_loop:
    WAIT
    GOSUB read_input

    IF poll_wait > 0 THEN
        poll_wait = poll_wait - 1
        GOTO input_check
    END IF

    IF has_move THEN
        gs_path = 2
    ELSE
        gs_path = 1
    END IF
    GOSUB compose_url
    #net_readlen = GAME_MAXLEN
    GOSUB api_call
    has_move = 0

    ' A short read means FN_RX beyond #net_gotlen still holds stale bytes
    ' from a previous, larger response -- render_game trusts fixed offsets
    ' deep into the buffer, so rendering it would show corrupted-looking
    ' data (a garbage pot/bet value, or a stray card glyph) instead of
    ' just skipping this poll. GAME_MINLEN alone isn't tight enough: it's
    ' only the 0-player floor, so a 7-8 player game's response could land
    ' anywhere from 165 bytes up to its true ~400 bytes and still pass
    ' that check while genuinely truncated partway through the player
    ' array. playerCount (offset 164) is read from before where any
    ' truncation could have happened, so it's safe to use here to compute
    ' the *exact* expected length for this specific response.
    ' A malformed request (e.g. a stray character somewhere it shouldn't
    ' be) can get rejected by the server with an HTTP error page instead
    ' of a Game struct -- our mailbox transaction still reports "OK" (the
    ' RP2040 got *a* reply, just not the one we wanted), so round/
    ' playerCount are the cheapest smoke test: neither should ever be
    ' implausible for a real response, and checking them here means a
    ' bogus response gets treated as a failed poll instead of being
    ' handed to render_game as if it were valid.
    IF fn_ok = 1 AND #net_gotlen >= GAME_MINLEN THEN
        IF (PEEK(FN_RX + GAME_ROUND) AND 255) > 5 OR (PEEK(FN_RX + GAME_PLAYERCOUNT) AND 255) > 8 THEN fn_ok = 0
    END IF

    IF fn_ok = 1 AND #net_gotlen >= GAME_MINLEN THEN
        #tmp_expect = GAME_PLAYERS + (PEEK(FN_RX + GAME_PLAYERCOUNT) AND 255) * PLAYER_STRIDE
        IF #net_gotlen < #tmp_expect THEN fn_ok = 0
    END IF

    IF fn_ok = 0 OR #net_gotlen < GAME_MINLEN THEN
        poll_wait = 30
        GOTO input_check
    END IF

    ' Render *before* checking for a new result message: this is the one
    ' poll whose response actually carries the showdown's revealed hands
    ' (masked "????" flips to the real hole cards only for this response --
    ' by the next poll the server has usually already started a new hand
    ' and reset them). Rendering first means the reveal lands on screen
    ' before the message overlay below covers the bottom two rows; doing
    ' it the other way around (as before) meant the reveal was drawn *at
    ' the earliest* 4 seconds later, by which point it was already gone,
    ' so it never actually appeared.
    GOSUB render_game

    ' The server sends a one-shot message (e.g. "Fry BOT won with Pair,
    ' Sixes") in lastResult at the end of a round/hand, but it's normally
    ' only shown in the single-line status row -- easy to miss entirely
    ' since bots move fast and the round can already have advanced past
    ' it by the next poll. Detect a new (changed, non-empty) message via
    ' a cheap byte-sum "hash" and, when one shows up, black out the
    ' bottom two rows to display it prominently and hold it there for a
    ' few seconds before resuming play.
    #tmp_hash = 0
    FOR gs_i = 0 TO 19
        #tmp_hash = #tmp_hash + (PEEK(FN_RX + GAME_LASTRESULT + gs_i) AND 255)
    NEXT gs_i
    IF first_poll THEN
        first_poll = 0
        #prev_result_hash = #tmp_hash ' arm the baseline silently; whatever's
                                        ' already there predates us sitting down
    ELSEIF (PEEK(FN_RX + GAME_LASTRESULT) AND 255) <> 0 AND #tmp_hash <> #prev_result_hash THEN
        #prev_result_hash = #tmp_hash
        FOR gs_i = STATUS_ROW - ROWCELLS TO STATUS_ROW + ROWCELLS - 1
            #BACKTAB(gs_i) = COL_STATUS
        NEXT gs_i
        #df_src = FN_RX + GAME_LASTRESULT : df_pos = STATUS_ROW - ROWCELLS : df_len = 2 * ROWCELLS : #df_color = COL_STATUS
        GOSUB draw_field
        GOSUB sound_gamedone
        force_redraw = 1 ' restore the felt background under row 10 once play resumes
        poll_wait = 240
        GOTO input_check
    END IF
    poll_wait = 20

    ' Turn edge: activePlayer differs from the previous poll's. move_ui is
    ' re-entered on every poll where it's still your turn -- bail to the
    ' in-game menu and resume and you land back in it -- so activePlayer
    ' alone can't tell "your turn just began" from "still your turn", and
    ' the cue would replay each time. Deliberately updated here rather than
    ' at the end of the loop: the GOTO input_check early exits above (short
    ' read, and the 4-second result-overlay hold) leave prev_active alone,
    ' so a poll that never got as far as the move UI doesn't eat the edge.
    ' Each betting street you act on is a real activePlayer transition, so
    ' the cue fires once per street rather than once per hand.
    turn_changed = 0
    IF active_player <> prev_active THEN turn_changed = 1
    prev_active = active_player

    IF active_player = 0 AND (PEEK(FN_RX + GAME_VIEWING) AND 255) = 0 THEN
        GOSUB move_ui
        IF has_move THEN poll_wait = 0
    END IF

input_check:
    IF inp_key_hit = 10 THEN GOSUB ingame_menu
    IF inp_key_hit = 11 THEN GOSUB show_purses
    IF want_leave THEN
        want_leave = 0
        GOTO table_select
    END IF

    GOTO game_loop

' ===========================================================================
' render_game: redraw the table from the Game struct in FN_RX.
'
' IntyBASIC/the STIC have no true page-flip (unlike the C clients' Apple2/
' C64 double buffer or CoCo/MSX's SINGLE_BUFFER differential-only mode) --
' BACKTAB is read live every frame, so a CLS visibly blanks the screen for
' a frame before the redraw lands. Since state only changes ~once per poll
' (not per frame), the fix that matters is simply not clearing the whole
' screen on every poll: a full CLS only happens on the first render after
' entering the game, or when the player count or hand round regresses
' (i.e. a new hand started) -- both mean the previous frame's layout is no
' longer valid. Every other poll only touches the specific cells whose
' values can actually change (pot digits, bet digits, name/card cells,
' community board, street label, status row), matching the CoCo/MSX
' approach since we're in the same no-real-double-buffer boat they were.
'
' Center layout (all inside the c6-13 corridor no seat's art reaches):
'   row 3   cells  66-73   street label
'   row 4-5 cells  87-91   community cards (tops r4, suit bottoms r5)
'   row 6   cells 127-131  "$" + 4-digit pot
'   row 7   cells 147-151  "P" + 4-digit purse
' ---------------------------------------------------------------------------
render_game: PROCEDURE
    round = PEEK(FN_RX + GAME_ROUND) AND 255
    tmp_pc = PEEK(FN_RX + GAME_PLAYERCOUNT) AND 255

    IF (tmp_pc <> prev_playercount) OR (round < prev_round) OR force_redraw THEN
        CLS
        GOSUB fill_bg
        ' Center block, rows 6-7: pot ("$" + value) and your own purse ("P"
        ' + value) stacked directly beneath it, both pushed down two rows
        ' from where 5 Card Stud kept them so the community board and its
        ' street label own rows 3-5 above.
        PRINT AT 127 COLOR COL_NAME, "$"
        PRINT AT 147 COLOR COL_NAME, "P"
        #prev_pot = 65535   ' force the pot to redraw too on a full layout reset
        #prev_purse = 65535 ' likewise for purse
        street_redraw = 1   ' the CLS wiped the label; force_redraw is consumed
                            ' right below, so capture the need-to-redraw here
        force_redraw = 0
        ' A new hand means every seat's hand -- and the community board --
        ' is starting over. Without this, a seat that had cards last hand
        ' would treat this hand's first cards as "already dealt" and skip
        ' animating them, and the next flop would land silently.
        IF round < prev_round THEN
            FOR gs_i = 0 TO 7
                prev_cards(gs_i) = 0
            NEXT gs_i
            prev_community = 0
        END IF
    END IF

    ' prev_playercount=255 is the boot sentinel (first render ever) -- skip
    ' the join/leave cue then, there's nothing to compare against yet.
    IF prev_playercount <> 255 THEN
        IF tmp_pc > prev_playercount THEN GOSUB sound_player_join
        IF tmp_pc < prev_playercount THEN GOSUB sound_player_left
    END IF
    IF round < prev_round THEN GOSUB sound_deal
    IF round <> prev_round THEN street_redraw = 1

    prev_playercount = tmp_pc
    prev_round = round

    ' Street label, row 3 centered above the community board. street_names
    ' is 8 space-padded bytes per round value (round already validated <= 5
    ' before render_game runs), so drawing it both writes the new label and
    ' blanks the remainder of the field -- no stale text possible.
    IF street_redraw THEN
        #df_src = VARPTR street_names(0) + round * 8
        df_pos = 66 : df_len = 8 : #df_color = COL_NAME
        GOSUB draw_field
        street_redraw = 0
    END IF

    ' Real hardware/accurate emulation only guarantees a BACKTAB write is
    ' tear-free if it lands within the vblank window; a full-table redraw
    ' (dozens of cells plus several PRINT calls, each involving a slow
    ' division loop for the digits) can run long enough to spill into
    ' active display, and a live screenshot can catch that half-written
    ' state -- seen as a stray non-digit glyph where only a digit could
    ' ever legitimately be. Skipping the PRINT entirely when the value
    ' hasn't changed since the last poll is what keeps the common-case
    ' redraw (most fields static from one poll to the next) small enough
    ' to actually fit in one vblank, rather than trying to chase tearing
    ' after the fact.
    #tmp_num = u16be(FN_RX + GAME_POT)
    IF #tmp_num <> #prev_pot THEN
        IF #tmp_num > #prev_pot AND #prev_pot <> 65535 THEN GOSUB sound_chip
        PRINT AT 128 COLOR COL_NAME, <.4>#tmp_num
        #prev_pot = #tmp_num
    END IF

    ' Your own purse (wire index 0 is always you, per the server's rotation
    ' -- see state.bas), directly under the pot.
    #tmp_num = u16be(player_addr(0) + PL_PURSE)
    IF #tmp_num <> #prev_purse THEN
        PRINT AT 148 COLOR COL_NAME, <.4>#tmp_num
        #prev_purse = #tmp_num
    END IF

    ' Community board: up to 5 cards, drawn every poll exactly like the
    ' seat hands below (so the flop/turn/river land in place without a
    ' CLS); only the deal click is gated on prev_community. The scan bound
    ' is 5 slots (offsets 87-96 -- byte 97 is the field's NUL, never a 6th
    ' card), and cards fill contiguously from index 0, so the count dealt
    ' is 1 + the highest nonzero index.
    deal_count = 0
    FOR mv_sel = 0 TO 4
        card = PEEK(FN_RX + GAME_COMMUNITY + mv_sel * 2) AND 255
        IF card <> 0 THEN deal_count = mv_sel + 1
    NEXT mv_sel
    ' The board can shrink without an intervening CLS: the server sends a
    ' masked "??" board in some transitional states (seen live: one card
    ' back drawn at pre-flop right after joining a table mid-hand), and
    ' once the wire reverts to empty the draw loop below simply stops at
    ' deal_count -- nothing else ever touches the leftover cells. Blank
    ' any cell we drew last poll that has no card this poll back to felt
    ' (same bare color-word idiom as fill_bg).
    IF deal_count < prev_community THEN
        FOR mv_sel = deal_count TO prev_community - 1
            #BACKTAB(87 + mv_sel) = COL_NAME
            #BACKTAB(107 + mv_sel) = COL_NAME
        NEXT mv_sel
    END IF
    FOR mv_sel = 0 TO deal_count - 1
        card = PEEK(FN_RX + GAME_COMMUNITY + mv_sel * 2) AND 255
        suit = PEEK(FN_RX + GAME_COMMUNITY + mv_sel * 2 + 1) AND 255
        IF mv_sel >= prev_community THEN GOSUB sound_deal
        conv_in = card : GOSUB card_from_ascii : card = conv_out
        conv_in = suit : GOSUB suit_from_ascii : suit = conv_out
        p = 87 + mv_sel
        GOSUB print_card
    NEXT mv_sel
    prev_community = deal_count
    ' Same one-vblank-budget reasoning as the per-seat WAIT below: yield a
    ' frame after the board so a flop's 5 fresh cells plus the seat loop's
    ' first seat can't pile into the same vblank.
    WAIT

    gs_j = tmp_pc - 2
    IF gs_j < 0 THEN gs_j = 0
    IF gs_j > 6 THEN gs_j = 6

    FOR gs_i = 0 TO tmp_pc - 1
        sel_seat = PEEK(VARPTR seatmap(0) + gs_j * 8 + gs_i) AND 255
        IF sel_seat <> 255 THEN
            sel_i = PEEK(VARPTR seat_name_off(0) + sel_seat) AND 255

            #gs_c = COL_NAME
            IF gs_i = active_player THEN #gs_c = COL_HILITE

            #tmp_addr = player_addr(gs_i)
            #df_src = #tmp_addr + PL_NAME : df_pos = sel_i : df_len = 4 : #df_color = #gs_c
            GOSUB draw_field

            #tmp_num = u16be(#tmp_addr + PL_BET)
            ' Clamp to 99: the bet field is 2 cells wide (a 3-digit PRINT
            ' would spill a digit past it -- for the right-edge seats,
            ' whose bet sits in the row's last 2 columns, that digit wraps
            ' to the next row on top of another seat's card cell), and it
            ' keeps the value inside prev_bet's 8-bit range for the
            ' change-detection compare. Hold'em raises pass 100 routinely,
            ' unlike 5 Card Stud where this was only latent.
            IF #tmp_num > 99 THEN #tmp_num = 99
            IF #tmp_num <> prev_bet(sel_seat) THEN
                PRINT AT sel_i + 4 COLOR #gs_c, <2>#tmp_num
                prev_bet(sel_seat) = #tmp_num
            END IF

            ' Hole cards (2 in Hold'em) fill the hand contiguously from
            ' index 0 (never a gap), so the count currently dealt is just
            ' 1 + the highest nonzero index. Comparing that against what
            ' this seat showed last poll (prev_cards) is what tells a
            ' genuinely new card apart from one we've already drawn on
            ' every previous poll.
            deal_count = 0
            FOR mv_sel = 0 TO 1
                card = PEEK(#tmp_addr + PL_HAND + mv_sel * 2) AND 255
                IF card <> 0 THEN deal_count = mv_sel + 1
            NEXT mv_sel

            ' Same shrink-without-CLS gap as the community board above: a
            ' fold shrinks "????" (2 backs) to "??" (1 back), and the
            ' draw loop below would leave the second back on screen
            ' forever. Blank the cells this seat showed last poll but not
            ' this one.
            IF deal_count < prev_cards(sel_seat) THEN
                FOR mv_sel = deal_count TO prev_cards(sel_seat) - 1
                    #BACKTAB(sel_i + 20 + mv_sel) = COL_NAME
                    #BACKTAB(sel_i + 40 + mv_sel) = COL_NAME
                NEXT mv_sel
            END IF

            FOR mv_sel = 0 TO deal_count - 1
                card = PEEK(#tmp_addr + PL_HAND + mv_sel * 2) AND 255
                suit = PEEK(#tmp_addr + PL_HAND + mv_sel * 2 + 1) AND 255
                ' A card index this seat hasn't shown before is a fresh
                ' deal -- the click (and its own built-in pause) stands in
                ' for the "card landing on the table" beat, instead of
                ' every new card just popping in silently and instantly
                ' like the C clients' animated deal never happens here.
                IF mv_sel >= prev_cards(sel_seat) THEN GOSUB sound_deal
                ' card=0/suit=0 after conversion (an unrecognized wire
                ' char, e.g. "??" for a folded/masked hand) is itself a
                ' valid "hidden" input to print_card -- draws the card-
                ' back glyph, which is what keeps a folded/masked card
                ' from leaving stale rank art on screen instead of just
                ' going quiet. The showdown flip needs no code at all:
                ' the server swaps "????" for the real chars in this
                ' response and this same loop redraws whatever arrives.
                conv_in = card : GOSUB card_from_ascii : card = conv_out
                conv_in = suit : GOSUB suit_from_ascii : suit = conv_out
                p = sel_i + 20 + mv_sel
                GOSUB print_card
            NEXT mv_sel
            prev_cards(sel_seat) = deal_count

            ' One seat's worth of pokes (name + bet digits + 2 cards) is
            ' small enough to reliably land within a single vblank; the
            ' full ~8-seat redraw as one unbroken burst isn't, and that's
            ' what let a screenshot catch a genuinely half-written frame
            ' (garbage that looked like data corruption but wasn't -- nothing
            ' in FN_RX was wrong, the *display* was mid-update). Yielding a
            ' frame between seats bounds the tear to at most one seat's
            ' fields at a time instead of the whole table, at the cost of
            ' a full new-hand redraw taking up to ~8 extra frames (moot;
            ' that only happens once per hand, not every poll).
            WAIT
        END IF
    NEXT gs_i

    GOSUB draw_status
END

' ---------------------------------------------------------------------------
' show_purses: while KEYPAD ENTER is held, overwrite every seated player's
' name cells with their purse value instead. Reuses tmp_pc/seatmap/
' seat_name_off exactly as render_game's own seat loop does -- tmp_pc is a
' global left holding the last poll's player count, so this works between
' polls without needing a fresh network round-trip. Releasing the key just
' asks for a full redraw on the next poll (the same trick the win-message
' overlay uses) rather than restoring each name field by hand here.
' ---------------------------------------------------------------------------
show_purses: PROCEDURE
    gs_j = tmp_pc - 2
    IF gs_j < 0 THEN gs_j = 0
    IF gs_j > 6 THEN gs_j = 6

    FOR gs_i = 0 TO tmp_pc - 1
        sel_seat = PEEK(VARPTR seatmap(0) + gs_j * 8 + gs_i) AND 255
        IF sel_seat <> 255 THEN
            sel_i = PEEK(VARPTR seat_name_off(0) + sel_seat) AND 255
            #tmp_addr = player_addr(gs_i)
            #tmp_num = u16be(#tmp_addr + PL_PURSE)
            IF #tmp_num > 9999 THEN #tmp_num = 9999
            PRINT AT sel_i COLOR COL_HILITE, <.4>#tmp_num
        END IF
    NEXT gs_i

sp_wait:
    WAIT
    GOSUB read_input
    IF inp_key = 11 THEN GOTO sp_wait ' level, not an edge -- this is hold-to-view

    force_redraw = 1 ' restore names (and everything else) on the next poll
END

' ---------------------------------------------------------------------------
' card_from_ascii / suit_from_ascii: translate the wire's lowercase ASCII
' rank/suit chars (conv_in) into print_card's expected numeric codes
' (conv_out; 0 = unrecognized/blank).
' ---------------------------------------------------------------------------
card_from_ascii: PROCEDURE
    IF conv_in = 50 THEN
        conv_out = 2
    ELSEIF conv_in = 51 THEN
        conv_out = 3
    ELSEIF conv_in = 52 THEN
        conv_out = 4
    ELSEIF conv_in = 53 THEN
        conv_out = 5
    ELSEIF conv_in = 54 THEN
        conv_out = 6
    ELSEIF conv_in = 55 THEN
        conv_out = 7
    ELSEIF conv_in = 56 THEN
        conv_out = 8
    ELSEIF conv_in = 57 THEN
        conv_out = 9
    ELSEIF conv_in = 116 THEN
        conv_out = 10
    ELSEIF conv_in = 106 THEN
        conv_out = 11
    ELSEIF conv_in = 113 THEN
        conv_out = 12
    ELSEIF conv_in = 107 THEN
        conv_out = 13
    ELSEIF conv_in = 97 THEN
        conv_out = 14
    ELSE
        conv_out = 0
    END IF
END

suit_from_ascii: PROCEDURE
    IF conv_in = 100 THEN
        conv_out = DIAMONDS
    ELSEIF conv_in = 104 THEN
        conv_out = HEARTS
    ELSEIF conv_in = 99 THEN
        conv_out = CLUBS
    ELSEIF conv_in = 115 THEN
        conv_out = SPADES
    ELSE
        conv_out = 0
    END IF
END

' ---------------------------------------------------------------------------
' draw_status: status row (row 11). Your turn is handled separately by
' move_ui (which overwrites this row); otherwise show "WAIT <name>" while
' someone else acts, or the truncated lastResult otherwise.
' ---------------------------------------------------------------------------
draw_status: PROCEDURE
    IF active_player > 0 THEN
        PRINT AT STATUS_ROW COLOR COL_STATUS, "WAIT "
        #tmp_addr = player_addr(active_player)
        #df_src = #tmp_addr + PL_NAME : df_pos = STATUS_ROW + 5 : df_len = 4 : #df_color = COL_STATUS
        GOSUB draw_field
        ' "WAIT <name>" only fills 9 of the row's 20 cells -- without a
        ' full CLS between polls, blank out the rest so a previous,
        ' longer status line (the lastResult branch below, or a move
        ' menu) can't leave stale characters past column 8.
        FOR gs_i = STATUS_ROW + 9 TO STATUS_ROW + ROWCELLS - 1
            #BACKTAB(gs_i) = COL_STATUS
        NEXT gs_i
    ELSE
        #df_src = FN_RX + GAME_LASTRESULT : df_pos = STATUS_ROW : df_len = ROWCELLS : #df_color = COL_STATUS
        GOSUB draw_field
    END IF
END

' ===========================================================================
' move_ui: your turn. List valid moves on the status row, disc left/right
' to choose, action button to submit. Sets has_move + mvcode_a/mvcode_b.
' ===========================================================================
move_ui: PROCEDURE
    mv_count = PEEK(FN_RX + GAME_VALIDMOVECOUNT) AND 255
    IF mv_count > 5 THEN mv_count = 5
    IF mv_count = 0 THEN RETURN

    mv_sel = 0
    IF mv_count > 1 THEN mv_sel = 1 ' default to the second move (not Fold), matching the C client
    ' Only on the poll where the turn actually changed hands -- see the
    ' turn_changed comment in the game loop. Kept below the mv_count guard
    ' so a state that says it's your turn but carries no moves to make
    ' stays silent (the edge is spent either way, matching Fujitzee: the
    ' server always attaches validMoves with the turn, so a zero count is
    ' a malformed response rather than a turn worth announcing).
    IF turn_changed THEN GOSUB sound_myturn

    ' Without a per-poll CLS, the status row can be carrying over a
    ' previous, wider draw_status message (lastResult fills all 20
    ' cells) -- move_ui only pokes the exact columns its move names
    ' occupy, so blank the whole row once up front rather than leaving
    ' stale text past the last move.
    FOR gs_i = STATUS_ROW TO STATUS_ROW + ROWCELLS - 1
        #BACKTAB(gs_i) = COL_STATUS
    NEXT gs_i
    ' Stopwatch icon (cardbot's 7th/last glyph, screen code 276 -- the
    ' only one of that set that's a clock face) in the last 3 columns of
    ' the move row, poked directly rather than through print_card since
    ' this isn't a playing card.
    #BACKTAB(STATUS_ROW + 17) = 276 * 8 + COL_STATUS

    ' moveTime (server-computed, already net of a network round-trip
    ' grace period -- see gameLogic.go) is our countdown's starting
    ' point; we count it down locally frame-by-frame rather than
    ' re-polling the server every second.
    mv_timeleft = PEEK(FN_RX + GAME_MOVETIME) AND 255
    mv_framecount = 0
    PRINT AT STATUS_ROW + 18 COLOR COL_STATUS, <2>mv_timeleft

    ' Columns 0-16 are the move menu's budget (the stopwatch + timer own
    ' 17-19). 5 Card Stud's fixed 5-col spacing with a clamp at 12 let a
    ' 4th move overwrite half the 3rd ("RAIS"/"ALL-" rendering as
    ' "RAALL-") -- rare there, but Hold'em offers FOLD/CHECK/RAISE/ALL-IN
    ' routinely, so scale the spacing to the move count instead and show
    ' as many name chars as fit in it: 1-3 moves get 5 cols / 4 chars
    ' (unchanged), 4 get 4/3, 5 get 3/2. Never overlaps, never reaches
    ' the timer.
    mv_gap = 16 / mv_count
    IF mv_gap > 5 THEN mv_gap = 5
    mv_len = mv_gap - 1
    IF mv_len > 4 THEN mv_len = 4

    inp_lock = 0
mu_loop:
    gs_j = 0
    FOR gs_i = 0 TO mv_count - 1
        mv_col(gs_i) = gs_j
        #gs_c = COL_STATUS
        IF gs_i = mv_sel THEN #gs_c = COL_HILITE
        #tmp_addr = move_addr(gs_i)
        #df_src = #tmp_addr + MOVE_NAME : df_pos = STATUS_ROW + gs_j : df_len = mv_len : #df_color = #gs_c
        GOSUB draw_field
        gs_j = gs_j + mv_gap
    NEXT gs_i

    WAIT
    GOSUB read_input

    mv_framecount = mv_framecount + 1
    IF mv_framecount >= 60 THEN
        mv_framecount = 0
        IF mv_timeleft > 0 THEN mv_timeleft = mv_timeleft - 1
        PRINT AT STATUS_ROW + 18 COLOR COL_STATUS, <2>mv_timeleft
        ' Timed out -- submit whatever's currently highlighted (the
        ' default move if the player never touched the disc, matching
        ' the C clients' timeout behavior of submitting the highlighted
        ' selection rather than always folding).
        IF mv_timeleft = 0 THEN GOTO mu_confirm
    END IF

    IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO mu_loop

    IF inp_dir AND DISC_RIGHT THEN
        mv_sel = mv_sel + 1
        IF mv_sel >= mv_count THEN mv_sel = 0
        inp_lock = 8
        GOSUB sound_cursor
        GOTO mu_loop
    END IF
    IF inp_dir AND DISC_LEFT THEN
        IF mv_sel = 0 THEN mv_sel = mv_count
        mv_sel = mv_sel - 1
        inp_lock = 8
        GOSUB sound_cursor
        GOTO mu_loop
    END IF
    ' Bail to the in-game menu without moving. The edge isn't consumed by
    ' returning -- input_check runs next and sees the same inp_key_hit, which
    ' is what actually opens the menu.
    IF inp_key_hit = 10 THEN RETURN
    IF inp_btn_hit = 0 THEN GOTO mu_loop
    GOSUB sound_select

mu_confirm:
    #tmp_addr = move_addr(mv_sel)
    mvcode_a = PEEK(#tmp_addr + MOVE_CODE) AND 255
    mvcode_b = PEEK(#tmp_addr + MOVE_CODE + 1) AND 255
    has_move = 1
END

' ===========================================================================
' ingame_menu: keypad CLEAR overlay. Disc up/down to choose, action button
' to confirm, matching every other screen's controls (Clear itself also
' cancels, for a quick way back in without touching the disc). Defaults
' to RESUME so an accidental Clear press can't quit a hand by surprise.
' ===========================================================================
ingame_menu: PROCEDURE
    im_sel = 0
    inp_lock = 0
im_loop:
    PRINT AT 80 COLOR COL_STATUS, "                    "
    PRINT AT 100 COLOR COL_STATUS, "                    "
    PRINT AT 120 COLOR COL_STATUS, "                    "
    PRINT AT 86 COLOR COL_STATUS, "TABLE MENU"
    #gs_c = COL_STATUS
    IF im_sel = 0 THEN #gs_c = COL_HILITE
    PRINT AT 106 COLOR #gs_c, "RESUME"
    #gs_c = COL_STATUS
    IF im_sel = 1 THEN #gs_c = COL_HILITE
    PRINT AT 126 COLOR #gs_c, "QUIT TABLE"

    WAIT
    GOSUB read_input
    IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO im_loop

    IF inp_dir AND (DISC_UP OR DISC_DOWN) THEN
        im_sel = 1 - im_sel
        inp_lock = 10
        GOSUB sound_cursor
        GOTO im_loop
    END IF
    ' Clear again cancels straight back to RESUME. Safe to test on the frame
    ' the menu opens: inp_key_hit is an edge, so the still-held press that
    ' got us here reads as "no key" until it's released and pressed again.
    IF inp_key_hit = 10 THEN GOTO im_done
    IF inp_btn_hit = 0 THEN GOTO im_loop
    GOSUB sound_select

    IF im_sel = 1 THEN
        gs_path = 3 : GOSUB compose_url
        #net_readlen = 8
        GOSUB api_call
        GOSUB clear_room_appkey
        want_leave = 1
    END IF
im_done:
    force_redraw = 1
END

' ===========================================================================
' name_entry_screen: disc letter picker, max 8 chars. Disc up/down cycles
' the character under the cursor through A-Z, 0-9, space; left/right moves
' the cursor; the action button accepts (at least 1 non-space char).
' ===========================================================================
name_entry_screen: PROCEDURE
    CLS
    GOSUB fill_bg
    PRINT AT 0 COLOR COL_STATUS, "ENTER YOUR NAME"
    FOR ne_i = 0 TO 7
        ne_buf(ne_i) = 36 ' space
    NEXT ne_i
    ne_cur = 0
    inp_lock = 0

ne_loop:
    FOR ne_i = 0 TO 7
        #gs_c = COL_NAME
        IF ne_i = ne_cur THEN #gs_c = COL_HILITE
        ne_j = ne_buf(ne_i)
        IF ne_j < 26 THEN
            gs_j = 65 + ne_j
        ELSEIF ne_j < 36 THEN
            gs_j = 48 + ne_j - 26
        ELSE
            gs_j = 95 ' underscore stands in for a visible blank
        END IF
        #BACKTAB(60 + 6 + ne_i) = (gs_j - 32) * 8 + #gs_c
    NEXT ne_i

    WAIT
    GOSUB read_input
    IF inp_lock > 0 THEN inp_lock = inp_lock - 1 : GOTO ne_loop

    IF inp_dir AND DISC_RIGHT THEN
        ne_cur = ne_cur + 1
        IF ne_cur > 7 THEN ne_cur = 0
        inp_lock = 8
        GOSUB sound_cursor
        GOTO ne_loop
    END IF
    IF inp_dir AND DISC_LEFT THEN
        IF ne_cur = 0 THEN ne_cur = 8
        ne_cur = ne_cur - 1
        inp_lock = 8
        GOSUB sound_cursor
        GOTO ne_loop
    END IF
    IF inp_dir AND DISC_UP THEN
        ne_buf(ne_cur) = ne_buf(ne_cur) + 1
        IF ne_buf(ne_cur) > 36 THEN ne_buf(ne_cur) = 0
        inp_lock = 6
        GOSUB sound_cursor
        GOTO ne_loop
    END IF
    IF inp_dir AND DISC_DOWN THEN
        IF ne_buf(ne_cur) = 0 THEN ne_buf(ne_cur) = 37
        ne_buf(ne_cur) = ne_buf(ne_cur) - 1
        inp_lock = 6
        GOSUB sound_cursor
        GOTO ne_loop
    END IF
    IF inp_btn_hit = 0 THEN GOTO ne_loop
    GOSUB sound_select

    ne_len = 8
    WHILE ne_len > 0 AND ne_buf(ne_len - 1) = 36
        ne_len = ne_len - 1
    WEND
    IF ne_len = 0 THEN GOTO ne_loop

    FOR ne_i = 0 TO ne_len - 1
        ne_j = ne_buf(ne_i)
        IF ne_j < 26 THEN
            gs_j = 65 + ne_j
        ELSE
            gs_j = 48 + ne_j - 26
        END IF
        POKE (SC_NAME + ne_i), gs_j
    NEXT ne_i
    POKE (SC_NAME + ne_len), 0

    ak_creator_lo = 1 : ak_creator_hi = 0 : ak_app = 1 : ak_key = 0 : ak_mode = 1
    GOSUB appkey_open
    IF fn_ok THEN
        #fn_src = SC_NAME : fn_len = ne_len
        GOSUB appkey_write
        ' A failed write used to be silent -- looked identical to success
        ' from here, even though the name would never come back on the
        ' next boot (e.g. if the backend has no SD/appkey storage mounted).
        IF fn_ok = 0 THEN
            PRINT AT 100 COLOR COL_STATUS, "NAME NOT SAVED FOR "
            PRINT AT 120 COLOR COL_STATUS, "NEXT TIME           "
            poll_wait = 90
            WHILE poll_wait > 0
                poll_wait = poll_wait - 1
                WAIT
            WEND
        END IF
        GOSUB appkey_close
    END IF
END

halt:
    WAIT
    GOTO halt
