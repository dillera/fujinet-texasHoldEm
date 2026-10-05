# Desktop test for the wire reader and card art, against replies saved from
# the live server.
CFLAGS = -std=c89 -pedantic -Wall -Wextra -I.. -I../common

all: holdem_test
	./holdem_test

holdem_test: holdem_test.c ../common/holdem.c ../common/holdem.h ../cards.c ../cards.h ../cardart.h ../common/fn_types.h
	$(CC) $(CFLAGS) -o $@ holdem_test.c ../common/holdem.c ../cards.c

clean:
	rm -f holdem_test
