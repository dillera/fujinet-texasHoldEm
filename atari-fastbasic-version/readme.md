# Texas Hold 'Em Client

This is an implementation of a client for Texas Hold 'Em, written in FastBasic. It is based on the 5 Card Stud client written by Eric Carr, converted to Texas Hold 'Em. It demonstrates using FujiNet to read/write **AppKeys** and parse **JSON** to communicate with the Texas Hold 'Em server, and should run on any Atari 8-bit with 48K memory or higher.

## Details

All game logic takes place at the server. This client simply requests and presents the state on the screen, accepting user input for moves when needed. Each player is dealt 2 hole cards, up to 5 community cards are dealt to the center of the table, and the best 5 card hand wins the pot.

## Building

Compile `texas.bas` with the [FastBasic](https://github.com/dmsc/fastbasic) cross compiler to produce an `.xex`.

## Credits

Original 5 Card Stud FastBasic client by Eric Carr.

## Resources
A source file for the font is also included, designed in [Atari FontMaker](http://matosimi.websupport.sk/atari/atari-fontmaker/).
