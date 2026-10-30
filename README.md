# CycleTabs

A tiny macOS menu bar app that cycles one tab at a time in Google Chrome's
front window — with wrap-around at both ends.

- **Automatic** — switches to the next tab every 60 seconds by default, with a
  live countdown (60…1) in the menu bar
- **⌃⌥⇥** — next tab now (last tab wraps to the first)
- **⌃⌥⇧⇥** — previous tab now (first tab wraps to the last)

The shortcuts work system-wide, even while Chrome is in the background, and
they are swallowed by the app so Chrome never also sees `Control-Tab`.

## Build

Requires macOS 14+ and Xcode command line tools.

```sh
./build.sh          # builds dist/CycleTabs.app
open dist/CycleTabs.app
```

The app lives in the menu bar only (no Dock icon). For development you can also
run `swift run`, though the Automation permission prompt is attributed to the
app bundle, so prefer `./build.sh` + `open dist/CycleTabs.app`.

## Permissions

The first time the app switches a tab, macOS asks whether **CycleTabs** may
control **Google Chrome**. Choose **OK**.

If it was denied, the menu shows an error and an
**Open Automation Settings…** item that takes you to
System Settings › Privacy & Security › Automation.

## Menu

The menu bar item shows the countdown itself (for example `58`); it shows an
arrow icon while auto-cycling is paused.

- **Next tab in Ns · every 1 minute** — live status
- **Pause Auto-Cycle / Resume Auto-Cycle** — start or stop the timer
- **Cycle Every** — 10 s, 30 s, 1 m, 2 m, 5 m, 10 m (changing it restarts the
  countdown)
- **Next Tab Now / Previous Tab Now** — manual triggers
- **Bring Chrome to front** — activate Chrome after switching (default on).
  Turn it off to cycle tabs silently while another app stays focused.
- **Launch at Login** — registers the app as a login item via `SMAppService`
- **Quit CycleTabs**

Auto-cycling is on at launch and the interval defaults to 60 seconds. Both are
remembered between launches.

## Command line mode

Useful for testing, for setting the interval, or for wiring the app into
another hotkey tool (skhd, Karabiner, Hammerspoon, Raycast…):

```sh
dist/CycleTabs.app/Contents/MacOS/CycleTabs --next        # prints "Switched to tab N"
dist/CycleTabs.app/Contents/MacOS/CycleTabs --previous
open dist/CycleTabs.app --args --interval 30              # 5…3600 s, remembered
```

`--next` / `--previous` perform one switch and exit. `--interval <seconds>`
sets and persists the auto-cycle interval (it does not start a second
instance; the menu is the primary way to change it).

## How it works

- `Sources/CycleTabs/ChromeController.swift` — runs a small AppleScript against
  Chrome (`active tab index` of `front window`), computing the wrap-around in
  AppleScript so a switch is a single round trip. Runs on a private serial
  queue so the UI never blocks.
- `Sources/CycleTabs/HotKeyManager.swift` — global hot keys via Carbon
  `RegisterEventHotKey`, which needs no Accessibility permission and can
  consume the key press.
- `Sources/CycleTabs/AppModel.swift` — state, one-second timer, command line
  handling, login item.
- `Sources/CycleTabs/CycleTabsApp.swift` — `MenuBarExtra` UI, including the
  countdown label.

## Notes

- Chrome must already be running with at least two tabs; otherwise the menu
  surfaces a clear error. Automatic switches fail silently (no beep storm);
  manual switches beep once.
- macOS requires Chrome's AppleScript support, which is on by default. No
  "Allow JavaScript from Apple Events" setting is needed.
- The bundle is ad-hoc signed for local use. Rebuilding changes the signature
  and macOS may ask for Automation permission again.
