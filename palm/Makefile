# FN Texas Hold'em for Palm OS. Builds in the palmdev Docker image (docker/Dockerfile).
# FNLIB is fujinet-lib's palmos branch (nwah/fujinet-lib-experimental),
# mounted into the container beside this directory.
IMAGE  = palmdev
FNLIB ?= $(abspath $(CURDIR)/../../fujinet-palm-dev/fujinet-lib-palmos)
DOCKER = docker run --rm --platform linux/amd64 -v $(CURDIR):/src -v $(FNLIB):/fnlib -w /src $(IMAGE)

all: build/icon.bmp
	$(DOCKER) make -f app.mk FNLIB=/fnlib

# build/demo/Holdem.prc, "FN Hold'em Demo": no network, plays the saved
# replies in tests/data. Name a table "turn" or "show" for those states.
demo: build/icon.bmp tools/make_demo.py
	python3 tools/make_demo.py build/demo/demo_data.h
	$(DOCKER) make -f app.mk FNLIB=/fnlib DEMO=1

# The icon is drawn on the host; the toolchain image has no Python.
build/icon.bmp: tools/make_icon.py
	mkdir -p build
	python3 tools/make_icon.py $@

# Regenerates cardart.h from this repo's Apple II and Lynx card art. Not a
# build dependency (the output is checked in); rerun after art changes.
cards:
	python3 tools/make_cards.py ..

image:
	docker build --platform linux/amd64 -t $(IMAGE) docker

test:
	$(MAKE) -C tests

clean:
	rm -rf build
	$(MAKE) -C tests clean

.PHONY: all demo cards image test clean
