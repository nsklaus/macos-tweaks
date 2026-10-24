# apptoggle

`libapptoggle.dylib`, loaded in every app: an app's Dock icon works as a show/hide switch, and
selecting an app always shows its windows.

- Click the Dock icon of the app in front: it hides. Click it again: it comes back.
- If all of an app's windows are minimized, clicking its Dock icon or switching to it (⌘Tab,
  Spotlight...) restores them all, instead of showing the app with no window.
  An app macOS brings forward on its own, because the one in front was hidden or quit, keeps
  them minimized.
- If only some windows are minimized, they stay minimized. An app with no window opens one as
  usual.
- Install: `make install-apptoggle`, then relaunch the apps.
- Turn it off with `defaults write -g TweaksAppToggle -bool NO` (`YES` to turn it back on),
  then relaunch the apps.
