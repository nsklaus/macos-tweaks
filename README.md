# macos-tweaks

Small Ammonia tweaks for macOS.
best used with [BackToCatalina](https://github.com/nfzerox/BackToCatalina)  
this runs on macos 27

## Tweaks

- [finderup](finder_up/): Back, Forward and Up buttons in the Finder toolbar and in Open/Save panels.
- [docklower](dock_lower/): middle-click a window's title bar to send it to the back, like on Linux.
- [itermtweaks](iterm_tweaks/): in iTerm2, a short context menu and tabs that fill the tab bar.
- [notestweaks](notes_tweaks/): in Notes, black body text, a bordered Markup button and an
  "Always Bold" toolbar button.
- [boldtext](bold_text/): bold text everywhere, like iOS's Bold Text option.
- [apptoggle](app_toggle/): click an app's Dock icon to show or hide it; selecting an app
  restores its minimized windows if there's none visible.

Check each tweak folder READMEs for details.

## Requirements

- Apple Silicon Mac, SIP disabled, [Ammonia](https://github.com/CoreBedtime/ammonia) installed
- Xcode Command Line Tools (`xcode-select --install`)
- [Hammerspoon](https://www.hammerspoon.org) for docklower
- cmake and ninja, only to rebuild Dobby (`shared/dobby/rebuild-dobby.sh`)

## Install

```
make install
```

Or one tweak at a time: `make install-<tweak>` (`finderup`, `docklower`, `itermtweaks`,
`notestweaks`, `boldtext`, `apptoggle`). Uninstall with `make uninstall`, or
`make uninstall-<tweak>`.

## Credits

C functions are hooked with [Dobby](https://github.com/jmpews/Dobby) (Apache-2.0), in `shared/dobby/`.
