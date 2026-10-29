#!/bin/zsh
# Usage: scripts/release.sh 2.3.0 ["What changed"]
# Builds Bart, packages a DMG, signs it for Sparkle, and publishes a GitHub release.
# Installed copies find the update through releases/latest/download/appcast.xml.
set -euo pipefail
cd "${0:A:h:h}"

version="${1:?Usage: scripts/release.sh <version> [notes]}"
notes="${2:-Bart $version}"
repo=mattbond21/bart-mac
tag="v$version"
dmg="dist/Bart-$version.dmg"
appcast=dist/appcast.xml
product=.build/xcode-derived/Build/Products/Release/Bart.app
sign_update=.build/xcode-derived/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update

if [[ -n "$(git status --porcelain)" ]]; then
    print "Commit or stash your changes before releasing." >&2
    exit 1
fi
if git rev-parse "$tag" >/dev/null 2>&1; then
    print "$tag already exists." >&2
    exit 1
fi

for plist in Configuration/Bart-Info.plist Configuration/BartWidget-Info.plist; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
done
./scripts/build-app.sh
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$product/Contents/Info.plist")
# Record the build number so the next release, from any Mac, numbers above it.
for plist in Configuration/Bart-Info.plist Configuration/BartWidget-Info.plist; do
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$plist"
done

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
ditto "$product" "$staging/Bart.app"
ln -s /Applications "$staging/Applications"
rm -f "$dmg"
hdiutil create -quiet -volname Bart -srcfolder "$staging" -fs HFS+ -format UDZO "$dmg"

signature=$("$sign_update" "$dmg")
cat > "$appcast" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Bart</title>
    <item>
      <title>Bart $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:fullReleaseNotesLink>
      <description><![CDATA[<p>${notes}</p>]]></description>
      <enclosure url="https://github.com/$repo/releases/download/$tag/Bart-$version.dmg" type="application/octet-stream" $signature />
    </item>
  </channel>
</rss>
EOF

git commit -q -am "Release $version"
git tag "$tag"
git push -q origin HEAD "$tag"
gh release create "$tag" "$dmg" "$appcast" --repo "$repo" --title "Bart $version" --notes "$notes"
print "Released $tag (build $build)"
