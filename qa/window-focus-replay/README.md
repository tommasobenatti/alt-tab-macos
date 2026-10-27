# Native focus-record replay

This is a local regression probe for the event sender in PR #6150. It opens its
own windows, replays the production sender, then closes them and restores the
previous application. It does not operate on documents or other apps' controls.

Requires Xcode command-line tools, Python 3 and SDL3 headers/library:

```sh
brew install sdl3
python3 qa/window-focus-replay/run.py
```

To test the exact SDL library extracted from a Minecraft LWJGL native JAR:

```sh
python3 qa/window-focus-replay/run.py --sdl-library /path/to/libSDL3.dylib --sdl-include /opt/homebrew/include
```

The fixed sender should exit 0. The SDL pending-focus-click count, AppKit actions,
game mouse-button events, WebKit mouse events and focus errors should all be zero;
the AppKit window frame should be unchanged.

The probe activates its owned SDL/AppKit windows natively before replaying the
sender. It checks input state and event leakage, not AltTab's entire window
discovery or selection UI.

In a Git checkout, `--baseline` reads the original sender from commit `c500294`.
That run is expected to exit 1 with a pending SDL focus click.

## Optional Electron/Chromium replay

The `electron/` folder contains the renderer test used during verification. It
alternates between framed and borderless windows, invokes the same production
bridge and the window's accessibility raise handler, then checks focus and DOM
button-event counts.

First run the native probe with `--keep-build`. Use the printed bridge directory
as `BRIDGE` below. Node.js headers must be installed; adjust `NODE_INCLUDE` for
your Node installation.

```sh
cd qa/window-focus-replay/electron
npm install
BRIDGE=/path/printed/by/the/probe
NODE_INCLUDE=/opt/homebrew/include/node
clang++ -std=c++17 -fobjc-arc -bundle -undefined dynamic_lookup -I"$NODE_INCLUDE" focus.mm -L"$BRIDGE" -lGeneralProbeBridge -framework Cocoa -Wl,-rpath,"$BRIDGE" -o focus.node
npx electron main.js
```

Expected output: 24 switches, zero focus failures and zero `mousedown`, `mouseup`
or `click` events in either renderer. These tests have been run on macOS 27.0.1
on Apple Silicon. They are not claims of testing every application or macOS release.
