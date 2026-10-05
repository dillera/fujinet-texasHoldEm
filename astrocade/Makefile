# Texas Hold'em for the Bally Astrocade. Standalone, outside mekkogx, in the
# o2/ mold: the build is build.sh (zmac + the layout checks), this file is
# the convenience wrapper.

SRCS := texas.asm HVGLIB.H fujinet.inc fujilib.inc \
        $(wildcard *.inc) $(wildcard assets/*.inc)

all: build/texas.bin

build/texas.bin: $(SRCS) build.sh tools/checksize.py
	./build.sh

run: build/texas.bin
	./run.sh

MAME_DIR ?= $(HOME)/Workspace/mame

# Headless end-to-end test: launch, join the first table, play presses,
# snapshot to build/astrocde/0000.png. Needs a running fujinet-pc-rs232
# (BoIP on 127.0.0.1:9995) with internet access.
smoke: build/texas.bin
	rm -rf build/astrocde
	FUJINET_DEBUG=$${FUJINET_DEBUG:-1} $(MAME_DIR)/mame astrocde \
	    -rompath $(MAME_DIR)/roms \
	    -cartslot fujinet -cart $(CURDIR)/build/texas.bin \
	    -autoboot_script emu/smoke.lua -video none -sound none \
	    -seconds_to_run 70 -snapshot_directory $(CURDIR)/build
	@ls build/astrocde/

# Regenerate the committed art from the Lynx sources. Not a build
# dependency (the outputs are checked in); rerun after art changes.
assets:
	python3 tools/mkfont.py
	python3 tools/mkcards.py

clean:
	rm -rf build

.PHONY: all run assets clean
