#!/bin/zsh
# Builds the beta for testers: signed with this Mac's Developer ID certificate, notarized by Apple,
# stapled, and zipped with the Start Here note into build/Beta. Nothing account-specific is stored
# in the repo: the Team ID comes from the certificate, the notary login from the keychain profile.
#
# One-time setup (Leah types the app-specific password herself):
#   xcrun notarytool store-credentials colorbee-notary --apple-id <Apple ID> --team-id <Team ID>
#
# On GitHub (.github/workflows/build-release.yml) it notarizes with an App Store Connect API key instead:
# NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER. MARKETING_VERSION and BUILD_NUMBER, when set, override
# project.yml's version (a release tag sets them).
set -euo pipefail
cd "${0:A:h}/.."

profile="${NOTARY_PROFILE:-colorbee-notary}"
identity=$(security find-identity -v -p codesigning | grep '"Developer ID Application' | head -1 || true)
if [[ -z "$identity" ]]; then
    echo "No Developer ID Application certificate in the keychain." >&2
    exit 1
fi
team=$(print -r -- "$identity" | sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/')

versioning=()
[[ -n "${MARKETING_VERSION:-}" ]] && versioning+=("MARKETING_VERSION=$MARKETING_VERSION")
[[ -n "${BUILD_NUMBER:-}" ]] && versioning+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
if [[ -n "${NOTARY_KEY_PATH:-}" ]]; then
    notary=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
    notary=(--keychain-profile "$profile")
fi

derived=build/BetaBuild
out=build/Beta
app=$derived/Build/Products/Release/Colorbee.app

xcodegen generate --quiet
xcodebuild -project Colorbee.xcodeproj -scheme Colorbee -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath "$derived" -quiet \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$team" \
    ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    "${versioning[@]}" clean build
codesign --verify --strict --deep "$app"
# Apple refuses apps that allow debugger attachment.
if codesign -d --entitlements - --xml "$app" 2>/dev/null | grep -q get-task-allow; then
    echo "The app still allows debugging (get-task-allow); Apple would reject it." >&2
    exit 1
fi

version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app/Contents/Info.plist")
rm -rf "$out"
mkdir -p "$out/Colorbee $version"

echo "Sending Colorbee $version ($build) to Apple for notarization. This usually takes a few minutes."
ditto -c -k --keepParent "$app" "$out/notarize.zip"
result=$(xcrun notarytool submit "$out/notarize.zip" "${notary[@]}" --wait)
print -r -- "$result"
if ! print -r -- "$result" | grep -q "status: Accepted"; then
    id=$(print -r -- "$result" | sed -nE 's/^ *id: ([0-9a-f-]+).*/\1/p' | head -1)
    echo "Apple didn't accept it. Its reasons: xcrun notarytool log $id ${notary[*]}" >&2
    exit 1
fi
xcrun stapler staple "$app"
spctl --assess --type execute "$app"

cp -R "$app" "$out/Colorbee $version/"
cp "Docs/Beta/Start Here.txt" "$out/Colorbee $version/"
ditto -c -k --keepParent "$out/Colorbee $version" "$out/Colorbee-$version-$build.zip"
rm "$out/notarize.zip"
# Only the zip is for testers. Keep these copies from becoming the Colorbee that opens images on this
# Mac when Leah double-clicks one; the everyday build should.
rm -rf "$out/Colorbee $version"
lsregister=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$lsregister" -u "$PWD/$app" 2>/dev/null || true
[[ -d build/Build/Products/Release/Colorbee.app ]] && "$lsregister" -f "$PWD/build/Build/Products/Release/Colorbee.app"
echo "Ready: $out/Colorbee-$version-$build.zip"
