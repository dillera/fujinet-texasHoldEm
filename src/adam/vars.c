/**
 * @brief   Global variables for the Coleco Adam
 * @author  Thomas Cherryhomes
 * @email   thom dot cherryhomes at gmail dot com
 * @license gpl v. 3, see LICENSE for details
 */

#ifdef __ADAM__

// 32x24 Texas Hold'em seat layout. Cards are 3 cells wide by 5 rows tall,
// so the mid seats sit at y=9 to keep their bottom row clear of the pot
// box top at row 14; their bets drop to betY 4 to stay on rows 14/7.
unsigned char playerXMaster[] = { 11, 0, 0, 0, 11, 30, 30, 30 };
unsigned char playerYMaster[] = { 18, 18, 9, 2, 2, 2, 9, 18 };

char playerDirMaster[] = { 1, 1, 1, 1, 1, -1, -1, -1 };
// betX[0] is -3 (not CoCo's 3) so YOU's bet lands left of the pot box
// instead of punching a hole in its bottom border on row 16.
char playerBetXMaster[] = { -3, 10, 1, 10, 3, -8, -1, -8 };
char playerBetYMaster[] = { -3, -3, 4, 4, 4, 4, 4, -3 };

//                               2                3                4
char playerCountIndex[] = {0,4,0,0,0,0,0,0, 0,2,6,0,0,0,0,0, 0,2,4,6,0,0,0,0,
// 5                6                 7                8
    0,2,3,5,6,0,0,0, 0,2,3,4,5,6,0,0,  0,2,3,4,5,6,7,0, 0,1,2,3,4,5,6,7};

#endif /* __ADAM__ */
