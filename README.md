# Countdown

A small countdown timer that lives in the macOS menu bar and shows the remaining time live (`1:24:59`, `4:05`).

Requires macOS 15 or later (Apple Silicon or Intel).

## Install

### Homebrew

```sh
brew install --cask larjudge/tap/countdown
open -a Countdown
```

### Download

Grab `Countdown-x.y.z.zip` from the [latest release](https://github.com/larjudge/countdown/releases/latest), unzip it, and move `Countdown.app` to `/Applications`. The app isn't notarized, so macOS will block the first launch. Either right-click the app and choose **Open**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/Countdown.app
```

### From source

```sh
./build.sh install     # builds, copies to /Applications, and launches
```

Needs Xcode or the Command Line Tools (`xcode-select --install`). If Xcode is installed but its license hasn't been accepted, the script uses the Command Line Tools instead.

Other commands: `./build.sh run` (build and launch from `build/`), `./build.sh test`, `./build.sh release` (universal zip for a GitHub release), `./build.sh uninstall`, `./build.sh icon`, `./build.sh clean`.

## Use

- **Click** the timer icon to set hours and minutes (type, use the arrows, or ↑/↓ keys) and press **Start** or Return. The quick-start buttons start common durations immediately.
- While running: pause/resume, add 1 or 5 minutes, or cancel. The popover shows a progress bar and the end time.
- **Right-click** (or Control-click) the menu bar item for pause, +5 min, cancel, and quit without opening the popover.
- When time's up, the menu bar shows a bell, a chime plays a few times, and a notification appears. Snooze, restart, or click Done.
- Tick **Launch at login** in the popover to start it automatically.

The countdown runs against an absolute end time, so it stays accurate across sleep.

## Layout

- `Sources/CountdownModel.swift`: timer state machine and formatting
- `Sources/AppDelegate.swift`: menu bar item, right-click menu, alarm and notifications
- `Sources/PopoverView.swift`: SwiftUI popover
- `Sources/LoginItem.swift`: launch at login
- `Tests/main.swift`: model tests (no XCTest needed)
- `scripts/make-icon.swift`: generates `Resources/AppIcon.icns`

## Releasing

1. Bump `CFBundleShortVersionString` in `Resources/Info.plist`.
2. `./build.sh release`, then `gh release create vX.Y.Z build/Countdown-X.Y.Z.zip`.
3. Update `version` and `sha256` in `Casks/countdown.rb` in [larjudge/homebrew-tap](https://github.com/larjudge/homebrew-tap).

## License

MIT
