#!/bin/bash
# Usage: ./build.sh [app|run|test|install|uninstall|release|icon|clean]   (default: app)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME=Countdown
BUILD=build
APP="$BUILD/$APP_NAME.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
MIN_MACOS=15.0
ARCHS=(arm64 x86_64)
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# Fall back to the Command Line Tools when Xcode is unusable (e.g. license not accepted).
if ! xcrun swiftc --version >/dev/null 2>&1; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

icon() {
    mkdir -p "$BUILD"
    swiftc -O scripts/make-icon.swift -o "$BUILD/make-icon"
    "$BUILD/make-icon" Resources/AppIcon.icns
}

app() {
    [[ -f Resources/AppIcon.icns ]] || icon
    rm -rf "$APP"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    # Universal binary: build each architecture, then merge.
    local slices=()
    for arch in "${ARCHS[@]}"; do
        swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" Sources/*.swift -o "$BUILD/$APP_NAME-$arch"
        slices+=("$BUILD/$APP_NAME-$arch")
    done
    lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
    cp Resources/Info.plist "$APP/Contents/Info.plist"
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    codesign --force --sign - "$APP"
    echo "Built $APP"
}

quit_running() {
    pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
}

case "${1:-app}" in
    app) app ;;
    run) app; quit_running; open "$APP" ;;
    test)
        mkdir -p "$BUILD"
        swiftc -swift-version 5 -target "$(uname -m)-apple-macos$MIN_MACOS" Sources/CountdownModel.swift Tests/main.swift -o "$BUILD/tests"
        "$BUILD/tests"
        ;;
    install)
        app
        quit_running
        rm -rf "${INSTALL_DIR:?}/$APP_NAME.app"
        cp -R "$APP" "$INSTALL_DIR/"
        open "$INSTALL_DIR/$APP_NAME.app"
        echo "Installed to $INSTALL_DIR/$APP_NAME.app"
        ;;
    uninstall)
        quit_running
        rm -rf "${INSTALL_DIR:?}/$APP_NAME.app"
        echo "Removed $INSTALL_DIR/$APP_NAME.app"
        ;;
    release)
        # Zip for GitHub releases / the Homebrew cask.
        app
        zip="$BUILD/$APP_NAME-$VERSION.zip"
        rm -f "$zip"
        ditto -c -k --keepParent "$APP" "$zip"
        echo "Created $zip"
        shasum -a 256 "$zip"
        ;;
    icon) icon ;;
    clean) rm -rf "$BUILD" ;;
    *) echo "Usage: $0 [app|run|test|install|uninstall|release|icon|clean]" >&2; exit 1 ;;
esac
