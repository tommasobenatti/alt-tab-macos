# My AltTab build

This branch contains the general window-focus fix submitted in
[upstream PR #6150](https://github.com/lwouis/alt-tab-macos/pull/6150).
The upstream patch is also available on `fix/balanced-window-focus` without any
personal build settings.

The fix completes every synthetic focus press with its release and keeps both
coordinate fields outside content. It does not look for Minecraft, Java, window
titles, bundle IDs, or version numbers.

## Personal Release

`ai/build-mcexp.sh` produces an optimized arm64 Release for my Apple Silicon Mac.
It defines `MCEXP_PINNED_BUILD`, which rejects Sparkle's scheduled background checks
and installations. Manual update checks and informational checks remain available.
No saved update preferences, license code, API endpoints, bundle identifiers, or
official signing settings are changed.

The personal update restriction is not part of the upstream pull request.
Use a manual update check once an official release includes the fix.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash ai/build-mcexp.sh
```

The default output is `DerivedData/MCExpDistribution`. Set `MCEXP_OUTPUT_DIR` to
choose another output directory. Builds use a local ad-hoc signature by default;
`MCEXP_CODE_SIGN_IDENTITY` can select an available signing identity.

The package is not an official AltTab release and is not Apple-notarized. On my
Mac it is built locally and macOS may ask for Accessibility and Screen Recording
permission again. It includes the source revision and GPL licence. The source at
the matching GitHub release tag is the corresponding source for the binary.

## Verification

- Debug and Release builds succeed with Xcode 27.1.
- All 32 focused XCTest cases pass, including seven new wire-record tests.
- The new event sender has 24/24 executable lines covered.
- The production sender was replayed against SDL 3.4.14, AppKit, WebKit, and
  Electron 45 / Chromium 156. The tests check pending focus-click state, window
  focus, accidental mouse events, and window resizing.
- A full en-US run passed 1,594 tests after temporarily constructing three
  grave-key fixtures by physical key code. The original fixture files were then
  restored. The stock fixtures assume an unmodified backtick exists in the active
  keyboard layout and crash on Italian-Pro; that also occurs on unchanged 11.10.1.

The native tests ran on macOS 27.0.1 / Apple Silicon. Older macOS versions and the
specific affected Figma and Telegram versions have not been tested.
