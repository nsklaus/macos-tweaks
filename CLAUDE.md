# macos-tweaks

Tweaks that patch macOS 27 "Golden Gate" (Apple Silicon) to bring back missing behaviours,
used together with [BackToCatalina](https://github.com/nfzerox/BackToCatalina) (Catalina look).
Repo: github.com/nsklaus/macos-tweaks, branch `master`.

## Tools

- [Ammonia](https://github.com/CoreBedtime/ammonia) 1.5 loads each tweak (a dylib) into the
  processes listed in its `.whitelist`. Needs SIP disabled and the boot-arg `-arm64e_preview_abi`.
- Tweaks are Objective-C dylibs built with clang (`arm64` + `arm64e`), linking only Foundation;
  methods are hooked through the ObjC runtime (`shared/Tweak.h`), C functions with
  [Dobby](https://github.com/jmpews/Dobby) (`shared/dobby/`).
- lldb to inspect the target apps; `/usr/bin/log` to read the tweaks' `NSLog` output.
- Hammerspoon for docklower's mouse handling.

## Layout

One folder per tweak: its `.m` file(s), whitelist(s) and a README with what it does. The header
of each `.m` explains how it works and what was found with lldb, to re-check after a macOS update.
Code, comments and logs are in English.

## Build and install

```
make                      # build everything into build/
make <tweak>              # build one
make install              # install every tweak (sudo)
make install-<tweak>      # install one
make uninstall[-<tweak>]  # remove all, or one
make clean
```

A tweak takes effect when its target process starts: install restarts system processes
(Finder, Dock...) or reminds you to relaunch the apps.
