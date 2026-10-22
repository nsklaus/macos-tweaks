# macos-tweaks

Personal Ammonia tweaks for macOS 27 "Golden Gate" on an M2 Pro.
Repo: github.com/nsklaus/macos-tweaks, branch `master`.

## Ammonia

Ammonia 1.5 (github.com/CoreBedtime/ammonia) loads tweaks into processes. Requires SIP
disabled and the boot-arg `-arm64e_preview_abi`. Installed in `/var/ammonia/core/`.

How it picks tweaks (from `opener/opener.m`, tag 1.5): at process start, `libopener.dylib`
goes through every file in `/var/ammonia/core/tweaks/` and `dlopen`s it if:
- `<file>.whitelist` exists and one of its lines is a substring of the process's full
  executable path (`strstr`), or
- there is no whitelist, `<file>.blacklist` exists and none of its lines matches.
- With neither file, the dylib is not loaded.

Consequences:
- A bare app name matches more than the app: `Dock` also matched `DockHelper` and
  `com.apple.dock.extra` (both inside Dock.app), `Notes` matches Notes' Spotlight extension.
  So whitelist lines are the end of the executable path (`Notes.app/Contents/MacOS/Notes`),
  and every tweak's constructor still checks the bundle ID.
- Never leave an empty line in a whitelist: it matches every process.
- A tweak may export `void LoadFunction(void *interceptor)` to get Ammonia's Frida Gum
  interceptor; ours don't use it.
- Skipped processes log "Process … is not whitelisted for <dylib>." (info level).

BackToCatalina (libBackToCatalina, blacklist; libBackToCatalinaDock, whitelist) is installed
through Ammonia too. It restyles AppKit controls, so measure our UI against its rendering,
not stock macOS.

A tweak takes effect when its target process starts: restart the app after installing.

## Conventions for a tweak

- Everything in the code (comments, log messages, identifiers) is in English.
- One folder per tweak, one `.m` per dylib, a `.whitelist` per dylib holding the end of the
  target's executable path (check it with `ps -axo comm | grep -F -- "<line>"`: one match).
  A tweak meant for every app (boldtext) uses `.app/Contents/MacOS/`, which matches all apps
  and no daemon or XPC service.
- Build `arm64` + `arm64e`, link only Foundation (AppKit is looked up at runtime with
  `NSClassFromString`; `<AppKit/AppKit.h>` is imported for types only).
- The constructor checks the bundle ID before doing anything (see Ammonia above); a tweak
  meant for every app checks that it is an AppKit app (`NSApplication` exists).
- Hook with `TWHook(cls, sel, block, &orig)` from `shared/Tweak.h` (header only, compiled into
  each dylib, so tweaks stay independent). It adds the method on `cls` when it is inherited,
  so a superclass is never changed. For a class method, pass `object_getClass(cls)`.
  If it returns NO (class or method missing), log and install nothing.
- When the target classes may not be registered when the dylib loads, install through
  `TWOnLaunch(install)`, which retries at NSApplicationWillFinishLaunching; `install` must
  then guard itself with a `done` flag.
- A dylib that includes `shared/Tweak.h` lists it among its Makefile prerequisites.
- Log with `NSLog(@"[TweakName] ...")`.
- At the top of each file, a "Findings from lldb" comment records the classes, selectors and
  measurements the hook relies on, so it can be re-checked after a macOS update.
- Hook the single place that owns a behaviour, so every path benefits, rather than patching
  each view.

## Tweaks

What each tweak does is in the README; how it does it, in the header of its `.m` file.

- `finder_up/` — `libfinderup.dylib` (Finder) and `libpanelnav.dylib` (Open/Save panels):
  Back, Forward and Up buttons. Button table shared by both in `FUShared.h`.
- `dock_lower/` — `libdocklower.dylib` (Dock) + `docklower.lua` (Hammerspoon): lower a window.
- `iterm_tweaks/` — `libitermtweaks.dylib` (iTerm2): short context menu, full-height tabs.
- `notes_tweaks/` — `libnotestweaks.dylib` (Notes): black body text, bordered Markup button,
  Always Bold toolbar toggle.
- `bold_text/` — `libboldtext.dylib` (every app, MenuBarAgent, Open/Save panel service):
  semibold system fonts; off with `defaults write -g TweaksBoldText -bool NO`.

## Build and install

```
make                      # build everything into build/
make <tweak>              # build one: finderup docklower itermtweaks notestweaks boldtext
make install              # install every tweak (sudo)
make install-<tweak>      # install one
make uninstall            # remove every tweak
make uninstall-<tweak>    # remove one
make clean
```

Each tweak restarts only its own process (Finder, Dock, MenuBarAgent) or prints a reminder to
restart the app (iTerm2, Notes, every app for boldtext). `sudo` needs the user's password:
ask them to run `! make install-<tweak>`.
A new tweak is added in the Makefile with its `<tweak>_DYLIBS`, `<tweak>_WHITELISTS` and
`<tweak>_RESTART` variables, its build rule, and its name in `TWEAKS`; then a README section.

Pitfalls when reloading a tweak:
- Never overwrite a loaded dylib in place (`cp`): the kernel keeps its old code signature,
  and the next process loading it is killed ("Code Signature Invalid", "Invalid Page").
  `install` writes a new file and renames it; by hand, `rm` first.
- Open/Save panel services (`com.apple.appkit.xpc.openAndSavePanelService`) stay alive
  between panels and ignore SIGTERM: with no panel open, `killall -9` them.
- `killall MenuBarAgent` leaves it stopped (launchd starts it only on demand): restart it with
  `launchctl kickstart -k gui/$(id -u)/com.apple.MenuBarAgent`.

## Logs

- In zsh, `log` is a shell builtin: use `/usr/bin/log`.
- `/usr/bin/log show --last 1h --info --predicate 'eventMessage CONTAINS "[NotesTweaks]"' --style compact`
- AMFI logs "Unrecoverable CT signature issue" for every tweak (ad-hoc signed): harmless,
  the dylibs load anyway.

## Inspecting an app with lldb

- `lldb -p $(pgrep -x App) --batch -s script.lldb`, with `expr -l objc -O -- ...` lines.
- `expr -l objc -- @import Foundation` (and `ObjectiveC`) first, for runtime calls and blocks.
- View tree: `[[[window contentView] superview] _subtreeDescription]`.
- `_shortMethodDescription` is UIKit-only on macOS: use `class_copyMethodList` instead.
- To see who calls a method, a Python SB API script with an auto-continue breakpoint set
  by name worked; breakpoints set by address (stripped or Swift code) never fired.
- To check that a method builds or returns something, call it directly in lldb
  (e.g. ask a toolbar delegate for an item): faster and more reliable than tracing.
- Resolve a dynamic color under an appearance with `+[NSAppearance setCurrentAppearance:]`
  then `colorUsingColorSpace:`.
