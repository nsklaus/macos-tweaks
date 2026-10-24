# docklower

A real "lower window", like on Linux: middle-click a window's title bar to send it to the
back of the window stack, without activating any other window.

- `libdocklower.dylib` runs inside the Dock, the only process allowed to reorder other apps' windows.
- `docklower.lua` (Hammerspoon) catches the middle-click and asks the Dock to lower the window.
  Brave browser's tab strip is left alone, so middle-click still closes tabs.

Install: `make install-docklower`, then copy `docklower.lua` to `~/.hammerspoon/` and add
`require("docklower")` to your `~/.hammerspoon/init.lua`.
