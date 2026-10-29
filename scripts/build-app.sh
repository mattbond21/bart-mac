#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

identity="${BART_SIGNING_IDENTITY:-B40CB955889DB7495C4FF42E613B710E3880786D}"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
installed="$HOME/Applications/Bart.app"
product="$PWD/.build/xcode-derived/Build/Products/Release/Bart.app"
legacy_installed="$HOME/Applications/Orinda Bar.app"
widget=Contents/PlugIns/BartWidget.appex
legacy_widget=Contents/PlugIns/OrindaWidget.appex
sparkle=Contents/Frameworks/Sparkle.framework/Versions/B

unregister() {
    local bundle="$1"
    if [[ -d "$bundle" ]]; then
        "$lsregister" -u "$bundle" || true
        for extension in "$widget" "$legacy_widget"; do
            if [[ -d "$bundle/$extension" ]]; then
                pluginkit -r "$bundle/$extension" || true
            fi
        done
    fi
}

bundle_version() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist" 2>/dev/null || print 0
}

next_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Configuration/Bart-Info.plist)
for bundle in "$installed" "$product" "$legacy_installed"; do
    if [[ -d "$bundle" ]]; then
        version=$(bundle_version "$bundle")
        if [[ "$version" == <-> && "$version" -gt "$next_version" ]]; then
            next_version="$version"
        fi
    fi
done
next_version=$((next_version + 1))

unregister "$product"
rm -rf "$product"
if [[ ! -f dist/AppIcon.icns || scripts/make-icon.swift -nt dist/AppIcon.icns ]]; then
    mkdir -p dist
    swift scripts/make-icon.swift "$PWD/dist"
    iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
fi

tuist generate --no-open
xcodebuild -quiet -workspace Bart.xcworkspace -scheme Bart \
    -configuration Release -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$PWD/.build/xcode-derived" CODE_SIGNING_ALLOWED=NO build

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_version" "$product/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_version" "$product/$widget/Contents/Info.plist"
# Sign inside-out: Sparkle's helpers, then the widget, then the app.
codesign --force --sign "$identity" "$product/$sparkle/XPCServices/Installer.xpc"
codesign --force --sign "$identity" --preserve-metadata=entitlements "$product/$sparkle/XPCServices/Downloader.xpc"
codesign --force --sign "$identity" "$product/$sparkle/Autoupdate"
codesign --force --sign "$identity" "$product/$sparkle/Updater.app"
codesign --force --sign "$identity" "$product/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$identity" --entitlements Configuration/BartWidget.entitlements "$product/$widget"
codesign --force --sign "$identity" --entitlements Configuration/Bart.entitlements "$product"
codesign --verify --deep --strict "$product"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    pkill -x Bart || true
    pkill -x BartWidget || true
    pkill -x OrindaWidget || true
    unregister "$installed"
    unregister "$legacy_installed"
    rm -rf "$installed"
    rm -rf "$legacy_installed"
    ditto "$product" "$installed"
    "$lsregister" -f "$installed"
    pluginkit -a "$installed/$widget"
    # WidgetKit can retain an old bundle stub until its user services restart.
    killall chronod NotificationCenter 2>/dev/null || true
    open "$installed"
    print "Installed and launched: $installed (build $next_version)"
else
    print "Built: $product (build $next_version)"
fi
