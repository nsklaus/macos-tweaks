# macos-tweaks

Small Ammonia tweaks that bring back behaviours macOS is missing.

## finderup

Separate buttons for : Back, Forward and Up (Enclosing Folder), in two places:

- **Finder toolbar** (`libfinderup.dylib`): three buttons offered in View > Customize Toolbar.
- **Open/Save panels** (`libpanelnav.dylib`): replace the Back/Forward combo with 3 buttons.

![Finder toolbar](screenshots/finder_up.png)

![Open/Save panel](screenshots/panel_up.png)

## docklower

A real "lower window", like on Linux: middle-click a window's title bar to send it to the
back of the window stack, without activating any other window.

- `libdocklower.dylib` runs inside the Dock, the only process allowed to reorder other apps' windows.
- `docklower.lua` (Hammerspoon) catches the middle-click and asks the Dock to lower the window.
  Brave's tab strip is left alone, so middle-click still closes tabs.

## Requirements

- Apple Silicon Mac, SIP disabled, [Ammonia](https://github.com/CoreBedtime/ammonia) installed
- Xcode Command Line Tools (`xcode-select --install`)
- [Hammerspoon](https://www.hammerspoon.org) for docklower

## Install

```
make install
```

For docklower, also copy `dock_lower/docklower.lua` to `~/.hammerspoon/` and add
`require("docklower")` to your `~/.hammerspoon/init.lua`.

Uninstall with `make uninstall`.
