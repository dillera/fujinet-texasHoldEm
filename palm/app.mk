# Run inside the palmdev image (see Makefile).
APP     = Holdem
NAME    = "FN Texas Hold'em"
CREATOR = ADTH
CC      = m68k-palmos-gcc
CFLAGS  = -O2 -Wall -palmos3.5 -Icommon -I. '-DAPP_CREATOR_STR="$(CREATOR)"'
FNLIB  ?= ../../fujinet-palm-dev/fujinet-lib-palmos
CFLAGS += -I$(FNLIB)/include
LIBDIR  = $(FNLIB)/r2r/palmos
SOURCES = $(APP).c cards.c common/fujibus.c common/fnlink.c common/fnnet.c common/holdem.c

build/$(APP).prc: build/$(APP) build/resources.stamp
	build-prc -n $(NAME) -c $(CREATOR) -o $@ build/$(APP) build/*.bin

build/$(APP): $(SOURCES) *.h common/*.h $(LIBDIR)/libfujinet.palmos.a
	$(CC) $(CFLAGS) -o $@ $(SOURCES) -L$(LIBDIR) -lfujinet.palmos

$(LIBDIR)/libfujinet.palmos.a:
	$(MAKE) -C $(FNLIB) palmos

build/resources.stamp: $(APP).rcp $(APP)Rsc.h build/icon.bmp
	pilrc -q -I build $(APP).rcp build
	touch $@
