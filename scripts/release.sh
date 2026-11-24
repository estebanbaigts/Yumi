#!/usr/bin/env bash
# Builds, signs, notarizes and staples Yumi.app, then zips it with its install guides.
#
# Usage:
#   YUMI_TEAM_ID=XXXXXXXXXX ./scripts/release.sh <version> [--publish]
#
# <version> is YumiDisplayVersion in Yumi/project.yml: 0.1.0, 0.1.0-beta.1. Pre-release
# words are lowercase ("beta", not "BETA"): Yumi compares them to tell testers a newer
# version is out.
#
# Without --publish the script stops once the notarized zip is ready: nothing is
# tagged, pushed or uploaded. With --publish it also pushes the tag v<version> and opens
# a draft GitHub release (a pre-release for a -beta or -alpha version), with the zip and
# SHA256SUMS.txt. The author reads the draft and publishes it by hand.
#
# Environment:
#   YUMI_TEAM_ID         Apple Developer team ID (10 characters). Required.
#   YUMI_NOTARY_PROFILE  notarytool keychain profile. Default: yumi-notary.
#                        Create it once with:
#                          xcrun notarytool store-credentials yumi-notary \
#                            --apple-id <apple id> --team-id <team id>
#   YUMI_REPO            GitHub repository for --publish. Default: estebanbaigts/Yumi.
#
# Requires a "Developer ID Application" certificate for that team in the keychain.
set -euo pipefail

VERSION=""
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    -h|--help) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "error: unknown option $arg" >&2; exit 2 ;;
    *)  VERSION="$arg" ;;
  esac
done

die() { echo "error: $*" >&2; exit 1; }

[ -n "$VERSION" ] || die "usage: YUMI_TEAM_ID=XXXXXXXXXX $0 <version> [--publish]"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-z]+\.[0-9]+)?$ ]] \
  || die "version must look like 1.2.3 or 1.2.3-beta.1 (lowercase), got '$VERSION'"
CORE_VERSION="${VERSION%%-*}"
PRERELEASE=0
[ "$CORE_VERSION" != "$VERSION" ] && PRERELEASE=1

TEAM_ID="${YUMI_TEAM_ID:-}"
NOTARY_PROFILE="${YUMI_NOTARY_PROFILE:-yumi-notary}"
REPO="${YUMI_REPO:-estebanbaigts/Yumi}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build/release-$VERSION"
APP="$BUILD_DIR/Yumi.app"
ZIP="$BUILD_DIR/Yumi-$VERSION.zip"
STAGE="$BUILD_DIR/stage/Yumi"
SUMS="$BUILD_DIR/SHA256SUMS.txt"
TAG="v$VERSION"

# ── 1. Preflight ──────────────────────────────────────────────────────────────
[ -n "$TEAM_ID" ] || die "YUMI_TEAM_ID is not set. The signing team has to be provided before the first release (see docs/journal.md)."
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "YUMI_TEAM_ID must be the 10-character team ID, got '$TEAM_ID'"

for tool in xcodegen xcodebuild xcrun codesign ditto; do
  command -v "$tool" >/dev/null || die "$tool not found"
done

cd "$REPO_ROOT"
# Files git does not track (videos, notes) are not built: only changes to tracked files block.
[ -z "$(git status --porcelain --untracked-files=no)" ] || die "the working tree has uncommitted changes. Commit or discard them first."

# The git remote of $REPO, whatever its name ("origin" may point to another copy).
REMOTE=$(git remote -v | awk -v repo="$REPO" '$2 ~ ("github\\.com[:/]" repo "(\\.git)?$") && $3 == "(push)" { print $1; exit }')

if [ "$PUBLISH" -eq 1 ]; then
  command -v gh >/dev/null || die "gh not found (needed for --publish)"
  [ -n "$REMOTE" ] || die "no git remote points to github.com/$REPO"
  git fetch --quiet "$REMOTE" main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse "$REMOTE/main")" ] || die "HEAD is not $REMOTE/main: publish from the latest main"
  git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$TAG" >/dev/null 2>&1 && die "tag $TAG already exists on $REMOTE"
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "tag $TAG already exists locally"
fi

IDENTITY=$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*('"$TEAM_ID"')\)".*/\1/p' | head -1 || true)
[ -n "$IDENTITY" ] || die "no 'Developer ID Application' certificate for team $TEAM_ID in the keychain. Install it from Xcode, Settings, Accounts."
echo "Signing with: $IDENTITY"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "notarytool profile '$NOTARY_PROFILE' not found or not valid. See the header of this script."

if ! ls "$REPO_ROOT"/Yumi/Resources/sounds/*.wav >/dev/null 2>&1; then
  echo "warning: Yumi/Resources/sounds has no WAV file, this build will be silent." >&2
fi
if ! ls "$REPO_ROOT"/Yumi/Assets.xcassets/AppIcon.appiconset/*.png >/dev/null 2>&1; then
  echo "warning: the app icon set has no PNG, this build will have no icon." >&2
fi

# ── 2. Generate the project and check the version ─────────────────────────────
cd "$REPO_ROOT/Yumi"
xcodegen generate

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DISPLAY_VERSION=$(/usr/libexec/PlistBuddy -c "Print :YumiDisplayVersion" Resources/Info.plist 2>/dev/null || echo "$PLIST_VERSION")
[ "$DISPLAY_VERSION" = "$VERSION" ] && [ "$PLIST_VERSION" = "$CORE_VERSION" ] \
  || die "project.yml says $DISPLAY_VERSION ($PLIST_VERSION), you asked for $VERSION. Update YumiDisplayVersion, CFBundleShortVersionString and CFBundleVersion in Yumi/project.yml, commit, then retry."

# ── 3. Release build, signed with the Developer ID ────────────────────────────
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

# The app carries iCloud (the link with the iPhone), which needs a Developer ID
# provisioning profile: Xcode makes and embeds it when it exports the archive.
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO keeps get-task-allow out of the
# signature: notarization rejects it.
ARCHIVE="$BUILD_DIR/Yumi.xcarchive"
xcodebuild \
  -project Yumi.xcodeproj \
  -scheme Yumi \
  -configuration Release \
  archive \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO

EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM_ID</string>
</dict></plist>
PLIST
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

[ -d "$APP" ] || die "build finished but $APP is missing"

# ── 4. Check the signature before sending anything to Apple ───────────────────
codesign --verify --deep --strict --verbose=2 "$APP"

SIGN_INFO=$(codesign -d --verbose=4 "$APP" 2>&1)
echo "$SIGN_INFO" | grep -q "TeamIdentifier=$TEAM_ID" || die "the app is not signed by team $TEAM_ID"
echo "$SIGN_INFO" | grep -Eq "flags=.*runtime"         || die "the hardened runtime is not enabled"
echo "$SIGN_INFO" | grep -q "^Timestamp="              || die "the signature has no secure timestamp"

ENTITLEMENTS=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
echo "$ENTITLEMENTS" | grep -q "iCloud.app.yumi" \
  || die "the iCloud entitlement (link with the iPhone) is missing from the signature"
echo "$ENTITLEMENTS" | grep -q "com.apple.security.automation.apple-events" \
  || die "the apple-events entitlement is missing from the signature"
if echo "$ENTITLEMENTS" | grep -q "get-task-allow"; then
  die "the signature carries get-task-allow, notarization would reject it"
fi

# ── 5. Zip and notarize ───────────────────────────────────────────────────────
ditto -c -k --keepParent "$APP" "$ZIP"

SUBMISSION=$(xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
SUBMISSION_ID=$(echo "$SUBMISSION" | plutil -extract id raw -o - - 2>/dev/null || true)
STATUS=$(echo "$SUBMISSION" | plutil -extract status raw -o - - 2>/dev/null || true)
echo "Notarization: ${STATUS:-unknown} (${SUBMISSION_ID:-no id})"

if [ "$STATUS" != "Accepted" ]; then
  if [ -n "$SUBMISSION_ID" ]; then
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fi
  die "notarization failed"
fi

# ── 6. Staple and verify ──────────────────────────────────────────────────────
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -t exec -vv "$APP"

# ── 7. Zip again: the stapled app and the install guides, in a Yumi folder ───────
rm "$ZIP"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Yumi.app"
for guide in LISEZ-MOI.txt README.txt; do
  sed "s/{{VERSION}}/$VERSION/g" "$REPO_ROOT/release/$guide" > "$STAGE/$guide"
done
(cd "$BUILD_DIR/stage" && ditto -c -k --sequesterRsrc --keepParent Yumi "$ZIP")
(cd "$BUILD_DIR" && shasum -a 256 "$(basename "$ZIP")" > "$SUMS")
echo "Release zip ready: $ZIP"
cat "$SUMS"

# ── 8. Tag and GitHub release (only with --publish) ───────────────────────────
if [ "$PUBLISH" -ne 1 ]; then
  echo
  echo "Nothing was tagged or published. To publish this build, run again with --publish."
  exit 0
fi

cd "$REPO_ROOT"
git tag "$TAG"
git push "$REMOTE" "$TAG"

PRE_FLAG=""
[ "$PRERELEASE" -eq 1 ] && PRE_FLAG="--prerelease"
SUM=$(cut -d' ' -f1 "$SUMS")
NOTES_FILE="$BUILD_DIR/notes.md"
cat > "$NOTES_FILE" <<NOTES
## Installer / Install

Télécharge **Yumi-$VERSION.zip**, décompresse-le et glisse **Yumi.app** dans Applications. L'app est signée et notarisée par Apple : elle s'ouvre d'un double-clic.

Download **Yumi-$VERSION.zip**, unzip it and move **Yumi.app** to Applications. The app is signed and notarized by Apple: it opens with a double-click.

macOS 15 ou plus récent, idéalement avec une notch. / macOS 15 or later, ideally with a notch.

SHA-256 : \`$SUM\`
NOTES

# $PRE_FLAG is left unquoted on purpose: empty, it adds no argument.
# shellcheck disable=SC2086
gh release create "$TAG" "$ZIP" "$SUMS" \
  --repo "$REPO" \
  --draft $PRE_FLAG \
  --title "Yumi $VERSION" \
  --notes-file "$NOTES_FILE"

echo "$TAG drafted: https://github.com/$REPO/releases/tag/$TAG (publish it by hand once read)"
