# Run inside the palmdev image (see Makefile).
APP     = Holdem
NAME    = "FN Texas Hold'em"
CREATOR = ADTH
B       = build
CC      = m68k-palmos-gcc
CFLAGS  = -O2 -Wall -palmos3.5 -Icommon -I. '-DAPP_CREATOR_STR="$(CREATOR)"'
FNLIB  ?= ../../fujinet-palm-dev/fujinet-lib-palmos
CFLAGS += -I$(FNLIB)/include
LIBDIR  = $(FNLIB)/r2r/palmos
SOURCES = $(APP).c cards.c common/fujibus.c common/fnlink.c common/fnnet.c common/holdem.c

# DEMO=1: no network, plays the replies saved in tests/data (see the
# Makefile's demo target), as its own app so it can sit beside the real one.
ifdef DEMO
NAME    = "FN Hold'em Demo"
CREATOR = ADTD
B       = build/demo
CFLAGS += -DHOLDEM_DEMO -I$(B)
endif

$(B)/$(APP).prc: $(B)/$(APP) $(B)/resources.stamp
	build-prc -n $(NAME) -c $(CREATOR) -o $@ $(B)/$(APP) $(B)/*.bin

$(B)/$(APP): $(SOURCES) *.h common/*.h $(LIBDIR)/libfujinet.palmos.a
	$(CC) $(CFLAGS) -o $@ $(SOURCES) -L$(LIBDIR) -lfujinet.palmos

$(LIBDIR)/libfujinet.palmos.a:
	$(MAKE) -C $(FNLIB) palmos

$(B)/resources.stamp: $(APP).rcp $(APP)Rsc.h build/icon.bmp
	pilrc -q -I build $(APP).rcp $(B)
	touch $@
