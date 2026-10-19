#!/bin/bash
# Archives Kinwall (iPhone/iPad app with its widgets and Watch app) and uploads it to App Store
# Connect for TestFlight. Signing is automatic through the Apple account signed in to Xcode
# (Xcode → Settings → Accounts); it creates the certificates, App IDs and profiles it needs.
#   TEAM=ABCDE12345 scripts/testflight.sh            # archive + upload
#   TEAM=ABCDE12345 UPLOAD=0 scripts/testflight.sh   # archive + export an .ipa only
set -euo pipefail
: "${TEAM:?Set TEAM to your Apple Developer team ID (developer.apple.com → Membership)}"
cd "$(dirname "$0")/.."
# Outside ~/Documents (codesign trips over Finder metadata there), and one per checkout: two worktrees
# building at once into one folder mix their apps (one installed the other's build once).
OUT="${OUT:-/tmp/kinwall-testflight-$(basename "$PWD")}"
VERSION=$(node -p "require('./package.json').version")
# Same rule as .github/workflows/testflight.yml: "<major*10000 + minor*100 + patch>.<minutes since
# 1970>", so uploads from here or from CI always go up within a version.
BUILD="${BUILD:-$(node -p "const [a,b,c]=require('./package.json').version.split('.').map(Number); a*10000+b*100+c").$(( $(date -u +%s) / 60 ))}"
rm -rf "$OUT" && mkdir -p "$OUT"
# Generate ios/ from app.json, plugins/ and targets/ (CocoaPods needs a UTF-8 locale).
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
npm ci --silent
CI=1 npx expo prebuild -p ios --clean >/dev/null
xcodebuild archive -workspace ios/Kinwall.xcworkspace -scheme Kinwall -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/Kinwall.xcarchive" -derivedDataPath "$OUT/dd" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TEAM" MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" | tail -3
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([ "${UPLOAD:-1}" = 1 ] && echo upload || echo export)</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/Kinwall.xcarchive" -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" -allowProvisioningUpdates | tail -3
echo "Build $BUILD: $([ "${UPLOAD:-1}" = 1 ] && echo 'uploaded; it shows in TestFlight once processed (about 10-30 minutes)' || echo "$OUT/export")"
