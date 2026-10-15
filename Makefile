# macos-tweaks - build and install the Ammonia tweaks
#   make            build everything into build/
#   make install    copy dylibs and whitelists, restart Finder and Dock
#   make uninstall  remove them
#   make clean      remove build/

CC         := clang
FLAGS      := -arch arm64 -arch arm64e -dynamiclib -fobjc-arc -O2 -Wall -framework Foundation
TWEAKS_DIR := /var/ammonia/core/tweaks
BUILD      := build

DYLIBS     := $(BUILD)/libfinderup.dylib $(BUILD)/libpanelnav.dylib $(BUILD)/libdocklower.dylib
WHITELISTS := finder_up/libfinderup.dylib.whitelist \
              finder_up/libpanelnav.dylib.whitelist \
              dock_lower/libdocklower.dylib.whitelist

all: $(DYLIBS)

$(BUILD):
	mkdir -p $@

$(BUILD)/libfinderup.dylib: finder_up/FinderUp.m finder_up/FUShared.h | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libpanelnav.dylib: finder_up/PanelNav.m finder_up/FUShared.h | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libdocklower.dylib: dock_lower/docklower.m | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

install: all
	sudo install -m 644 $(DYLIBS) $(WHITELISTS) $(TWEAKS_DIR)/
	killall Finder Dock || true
	@echo "Open/Save panels pick up the change the next time a panel opens."

uninstall:
	sudo rm -f $(addprefix $(TWEAKS_DIR)/,$(notdir $(DYLIBS) $(WHITELISTS)))
	killall Finder Dock || true

clean:
	rm -rf $(BUILD)

.PHONY: all install uninstall clean