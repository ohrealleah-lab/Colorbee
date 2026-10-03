#!/bin/zsh
# Builds the beta for testers: signed with this Mac's Developer ID certificate, notarized by Apple,
# stapled, and zipped with the Start Here note into build/Beta. Nothing account-specific is stored
# in the repo: the Team ID comes from the certificate, the notary login from the keychain profile.
#
# One-time setup (Leah types the app-specific password herself):
#   xcrun notarytool store-credentials colorbee-notary --apple-id <Apple ID> --team-id <Team ID>
set -euo pipefail
cd "${0:A:h}/.."

profile="${NOTARY_PROFILE:-colorbee-notary}"
identity=$(security find-identity -v -p codesigning | grep '"Developer ID Application' | head -1 || true)
if [[ -z "$identity" ]]; then
    echo "No Developer ID Application certificate in the keychain." >&2
    exit 1
fi
team=$(print -r -- "$identity" | sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/')

derived=build/BetaBuild
out=build/Beta
app=$derived/Build/Products/Release/Colorbee.app

xcodegen generate --quiet
xcodebuild -project Colorbee.xcodeproj -scheme Colorbee -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" -quiet \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp \
    clean build
codesign --verify --strict --deep "$app"

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app/Contents/Info.plist")
rm -rf "$out"
mkdir -p "$out/Colorbee $version"

echo "Sending Colorbee $version ($build) to Apple for notarization. This usually takes a few minutes."
ditto -c -k --keepParent "$app" "$out/notarize.zip"
xcrun notarytool submit "$out/notarize.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
spctl --assess --type execute "$app"

cp -R "$app" "$out/Colorbee $version/"
cp "Docs/Beta/Start Here.txt" "$out/Colorbee $version/"
ditto -c -k --keepParent "$out/Colorbee $version" "$out/Colorbee-$version-$build.zip"
rm "$out/notarize.zip"
echo "Ready: $out/Colorbee-$version-$build.zip"
