#!/bin/zsh
# Builds a Developer ID signed + notarized CutVR.app, CutVR.zip (for the updater) and CutVR.dmg (for the web).
#
# One-time setup:
#   1. Developer ID Application certificate in the login keychain
#      (Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application).
#   2. Notary credentials (app-specific password from account.apple.com):
#      xcrun notarytool store-credentials CutVR --apple-id <apple-id> --team-id 395JXZ2H3J
#
# Usage: ./release-signed.sh             → signed + notarized output in ./release
#        ./release-signed.sh --publish   → same, then push and create GitHub release v<version>
set -euo pipefail
cd "$(dirname "$0")"

if [[ "${1:-}" == "--publish" ]]; then
  # The published build must be exactly a committed state (version = commit count).
  [[ -z "$(git status --porcelain --untracked-files=no)" ]] \
    || { echo "Commit your changes first – a published release must match a commit." >&2; exit 1; }
  command -v gh >/dev/null || { echo "GitHub CLI (gh) is required for --publish." >&2; exit 1; }
fi

TEAM_ID="${TEAM_ID:-395JXZ2H3J}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CutVR}"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
  | grep -o "\"Developer ID Application: .*($TEAM_ID)\"" | head -1 | tr -d '"')}"
[[ -n "$SIGN_IDENTITY" ]] || { echo "No 'Developer ID Application (…$TEAM_ID)' certificate in keychain." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null \
  || { echo "Notary profile '$NOTARY_PROFILE' missing – run notarytool store-credentials (see header)." >&2; exit 1; }
echo "Signing as: $SIGN_IDENTITY"

SIGN_IDENTITY="$SIGN_IDENTITY" ./build.sh
APP=dist/CutVR.app
OUT=release
rm -rf "$OUT"; mkdir -p "$OUT"

# 1) Notarize the app itself and staple the ticket, so it passes Gatekeeper even offline.
ditto -c -k --keepParent "$APP" "$OUT/notarize-app.zip"
xcrun notarytool submit "$OUT/notarize-app.zip" --keychain-profile "$NOTARY_PROFILE" --wait
rm "$OUT/notarize-app.zip"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# 2) Zip of the stapled app – asset the in-app updater downloads.
ditto -c -k --keepParent "$APP" "$OUT/CutVR.zip"

# 3) DMG with an Applications shortcut, signed, notarized and stapled.
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/CutVR.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname CutVR -srcfolder "$STAGE" -ov -format UDZO -fs APFS "$OUT/CutVR.dmg"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$OUT/CutVR.dmg"
xcrun notarytool submit "$OUT/CutVR.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$OUT/CutVR.dmg"

# 4) Gatekeeper check, exactly as on a user's Mac.
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$OUT/CutVR.dmg"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
echo "Done: $PWD/$OUT/CutVR.dmg and CutVR.zip ($VERSION)"

# 5) Optional: publish as GitHub release v<version> (the in-app updater installs the latest one).
if [[ "${1:-}" == "--publish" ]]; then
  git push origin HEAD
  PREV=$(git describe --tags --abbrev=0 2>/dev/null || true)
  {
    echo "## What's new"
    if [[ -n "$PREV" ]]; then git log --format='- %s' "$PREV..HEAD"; else git log --format='- %s'; fi
    echo
    echo "**Install:** download CutVR.dmg, open it and drag CutVR to Applications, then \`brew install ffmpeg exiftool\`."
    echo "Signed with Developer ID and notarized by Apple. Already installed? Use **CutVR → Check for Updates…**"
  } > "$OUT/notes.md"
  gh release create "v$VERSION" "$OUT/CutVR.dmg" "$OUT/CutVR.zip" \
    --title "CutVR $VERSION" --notes-file "$OUT/notes.md" --target "$(git rev-parse HEAD)"
  echo "Published v$VERSION"
fi
