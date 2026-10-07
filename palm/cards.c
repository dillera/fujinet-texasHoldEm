#include "cards.h"
#include "cardart.h"

#define UNKNOWN 13

void card_table(fn_u8 rank, fn_u8 suit, fn_u16 rows[CARD_H])
{
    fn_u8 y;
    const fn_u16 *top, *mid, *bottom;

    if (rank >= UNKNOWN || suit >= 4) {
        top = artBack;
        mid = artBack;
        bottom = artBack;
    } else {
        top = artRank[rank];
        mid = artMiddle;
        bottom = artSuit[suit];
    }
    rows[0] = artEdge;
    for (y = 0; y < ART_PIECE_H; y++) {
        rows[1 + y] = top[y];
        rows[1 + ART_PIECE_H + y] = mid[y];
        rows[1 + 2 * ART_PIECE_H + y] = bottom[y];
    }
    rows[CARD_H - 1] = artEdge;
}

void card_mini(fn_u8 rank, fn_u8 suit, fn_u16 rows[MINI_H])
{
    fn_u8 y;

    if (rank >= UNKNOWN || suit >= 4) {
        for (y = 0; y < MINI_H; y++)
            rows[y] = artMiniBack[y];
        return;
    }
    for (y = 0; y < MINI_H; y++)
        rows[y] = artMiniFace[y];
    /* Rank in the top half, two px in from the left edge; suit below. */
    for (y = 0; y < ART_PIECE_H; y++)
        rows[1 + y] |= (fn_u16)artMiniRank[rank][y] << 6;
    for (y = 0; y < ART_MINI_SUIT_H; y++)
        rows[10 + y] |= (fn_u16)artMiniSuit[suit][y] << 5;
}

void card_mini_half(fn_u16 rows[MINI_H])
{
    fn_u8 y;

    for (y = 0; y < MINI_H; y++)
        rows[y] = (fn_u16)artMiniHalf[y] << 8;
}

void card_chip(fn_u16 rows[8])
{
    fn_u8 y;

    for (y = 0; y < 8; y++)
        rows[y] = (fn_u16)artChip[y] << 8;
}

void card_suit(fn_u8 suit, fn_u16 rows[6])
{
    fn_u8 y;

    for (y = 0; y < ART_MINI_SUIT_H; y++)
        rows[y] = suit < 4 ? (fn_u16)artMiniSuit[suit][y] << 8 : 0;
}

/* The ink of a card: black, red for diamonds and hearts, or the back's. */
static fn_u8 InkOf(fn_u8 rank, fn_u8 suit)
{
    if (rank >= UNKNOWN || suit >= 4)
        return CP_BACK;
    return (suit == 1 || suit == 2) ? CP_RED : CP_INK;
}

void card_table_px(fn_u8 rank, fn_u8 suit, fn_u8 px[CARD_H][16])
{
    fn_u16 rows[CARD_H], felt, bit;
    fn_u8 x, y, ink = InkOf(rank, suit);

    card_table(rank, suit, rows);
    for (y = 0; y < CARD_H; y++) {
        /* Felt is the left column and the two padding columns, and the
         * rounded corners of the edge rows; the rest of a set bit is ink. */
        felt = (y == 0 || y == CARD_H - 1) ? artEdge : 0x8003;
        for (x = 0; x < 16; x++) {
            bit = 0x8000 >> x;
            if (felt & bit)
                px[y][x] = CP_FELT;
            else if (rows[y] & bit)
                px[y][x] = ink;
            else
                px[y][x] = CP_PAPER;
        }
    }
}

/* A mini card's outline is the face's, whatever is drawn inside it. */
void card_mini_px(fn_u8 rank, fn_u8 suit, fn_u8 px[MINI_H][MINI_W])
{
    fn_u16 rows[MINI_H], bit;
    fn_u8 x, y, ink = InkOf(rank, suit);

    card_mini(rank, suit, rows);
    for (y = 0; y < MINI_H; y++)
        for (x = 0; x < MINI_W; x++) {
            bit = 0x8000 >> x;
            if (artMiniFace[y] & bit)
                px[y][x] = CP_INK;
            else if (rows[y] & bit)
                px[y][x] = ink;
            else
                px[y][x] = CP_PAPER;
        }
}

void card_mini_half_px(fn_u8 px[MINI_H][MINI_HALF_W])
{
    fn_u16 rows[MINI_H], bit;
    fn_u8 x, y;

    card_mini_half(rows);
    for (y = 0; y < MINI_H; y++)
        for (x = 0; x < MINI_HALF_W; x++) {
            bit = 0x8000 >> x;
            if (artMiniFace[y] & bit)
                px[y][x] = CP_INK;
            else if (rows[y] & bit)
                px[y][x] = CP_BACK;
            else
                px[y][x] = CP_PAPER;
        }
}
