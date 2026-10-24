# macos-tweaks - build and install the Ammonia tweaks
#   make                     build everything into build/
#   make <tweak>             build one tweak
#   make install             install every tweak
#   make install-<tweak>     install one tweak
#   make uninstall           remove every tweak
#   make uninstall-<tweak>   remove one tweak
#   make clean               remove build/
# Tweaks: finderup docklower itermtweaks notestweaks boldtext apptoggle

CC         := clang
FLAGS      := -arch arm64 -arch arm64e -dynamiclib -fobjc-arc -O2 -Wall -framework Foundation
TWEAKS_DIR := /var/ammonia/core/tweaks
BUILD      := build

TWEAKS     := finderup docklower itermtweaks notestweaks boldtext apptoggle

# Per tweak: its dylibs, their whitelists, and what to run after (un)installing it.
finderup_DYLIBS        := $(BUILD)/libfinderup.dylib $(BUILD)/libpanelnav.dylib
finderup_WHITELISTS    := finder_up/libfinderup.dylib.whitelist finder_up/libpanelnav.dylib.whitelist
finderup_RESTART       := killall Finder || true; echo "Open/Save panels: close them, then killall -9 com.apple.appkit.xpc.openAndSavePanelService."

docklower_DYLIBS       := $(BUILD)/libdocklower.dylib
docklower_WHITELISTS   := dock_lower/libdocklower.dylib.whitelist
docklower_RESTART      := killall Dock || true

itermtweaks_DYLIBS     := $(BUILD)/libitermtweaks.dylib
itermtweaks_WHITELISTS := iterm_tweaks/libitermtweaks.dylib.whitelist
itermtweaks_RESTART    := echo "Restart iTerm2 for libitermtweaks."

notestweaks_DYLIBS     := $(BUILD)/libnotestweaks.dylib
notestweaks_WHITELISTS := notes_tweaks/libnotestweaks.dylib.whitelist
notestweaks_RESTART    := echo "Restart Notes for libnotestweaks."

boldtext_DYLIBS        := $(BUILD)/libboldtext.dylib
boldtext_WHITELISTS    := bold_text/libboldtext.dylib.whitelist
boldtext_RESTART       := launchctl kickstart -k gui/$$(id -u)/com.apple.MenuBarAgent; killall Dock DockHelper "Siri AI" ControlCenter || true; echo "Relaunch apps (or log out and in) for libboldtext. Open/Save panels: close them, then killall -9 com.apple.appkit.xpc.openAndSavePanelService."

apptoggle_DYLIBS       := $(BUILD)/libapptoggle.dylib
apptoggle_WHITELISTS   := app_toggle/libapptoggle.dylib.whitelist
apptoggle_RESTART      := echo "Relaunch apps (or log out and in) for libapptoggle."

all: $(TWEAKS)

$(BUILD):
	mkdir -p $@

$(BUILD)/libfinderup.dylib: finder_up/FinderUp.m finder_up/FUShared.h shared/Tweak.h | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libpanelnav.dylib: finder_up/PanelNav.m finder_up/FUShared.h shared/Tweak.h | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libdocklower.dylib: dock_lower/docklower.m | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libitermtweaks.dylib: iterm_tweaks/iTermTweaks.m shared/Tweak.h | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libnotestweaks.dylib: notes_tweaks/NotesTweaks.m shared/Tweak.h | $(BUILD)
	$(CC) $(FLAGS) -o $@ $<

$(BUILD)/libboldtext.dylib: bold_text/BoldText.m shared/dobby/dobby.h shared/dobby/libdobby.a | $(BUILD)
	$(CC) $(FLAGS) -framework CoreText -o $@ $< shared/dobby/libdobby.a -lc++

$(BUILD)/libapptoggle.dylib: app_toggle/AppToggle.m | $(BUILD)
	$(CC) $(FLAGS) -framework CoreServices -o $@ $<

# <tweak>, install-<tweak> and uninstall-<tweak>, for every tweak in TWEAKS.
define TWEAK_RULES
$(1): $$($(1)_DYLIBS)

install-$(1): $$($(1)_DYLIBS)
	sudo install -m 644 $$($(1)_DYLIBS) $$($(1)_WHITELISTS) $$(TWEAKS_DIR)/
	@$$($(1)_RESTART)

uninstall-$(1):
	sudo rm -f $$(addprefix $$(TWEAKS_DIR)/,$$(notdir $$($(1)_DYLIBS) $$($(1)_WHITELISTS)))
	@$$($(1)_RESTART)

.PHONY: $(1) install-$(1) uninstall-$(1)
endef
$(foreach t,$(TWEAKS),$(eval $(call TWEAK_RULES,$(t))))

install: $(addprefix install-,$(TWEAKS))

uninstall: $(addprefix uninstall-,$(TWEAKS))

clean:
	rm -rf $(BUILD)

.PHONY: all install uninstall clean
