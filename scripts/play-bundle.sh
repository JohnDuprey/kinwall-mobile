#!/bin/sh
# Builds a signed Android App Bundle (.aab) to upload to Google Play. Play re-signs it with the app
# key it keeps (Play App Signing); this only signs with your upload key, which stays outside the repo.
#   scripts/play-bundle.sh                       # asks for the upload key password
#   KINWALL_UPLOAD_PASSWORD=... scripts/play-bundle.sh
#   UNSIGNED=1 scripts/play-bundle.sh            # no key at all; .github/workflows/play.yml signs it
#                                                # with jarsigner in a separate job
# Create the upload key once (keytool asks for a password; keep it and the file somewhere safe):
#   mkdir -p ~/.kinwall && keytool -genkeypair -v -keystore ~/.kinwall/kinwall-upload.jks -alias upload \
#     -keyalg RSA -keysize 4096 -validity 10000 -dname "CN=Kinwall"
set -eu
cd "$(dirname "$0")/.."
UNSIGNED="${UNSIGNED:-0}"
if [ "$UNSIGNED" != 1 ]; then
  KEYSTORE="${KEYSTORE:-$HOME/.kinwall/kinwall-upload.jks}"
  [ -f "$KEYSTORE" ] || { echo "No upload key at $KEYSTORE; see the top of $0 to create one." >&2; exit 1; }
  if [ -z "${KINWALL_UPLOAD_PASSWORD:-}" ]; then
    printf 'Upload key password: '; stty -echo; read -r KINWALL_UPLOAD_PASSWORD; stty echo; echo
  fi
  export KINWALL_UPLOAD_KEYSTORE="$KEYSTORE" KINWALL_UPLOAD_PASSWORD
fi
export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}" ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
# Minutes since 1970, like the iOS build number: every upload goes up, from any checkout.
VERSION_CODE="${VERSION_CODE:-$(( $(date -u +%s) / 60 ))}"
[ "${NPM_CI:-1}" = 0 ] || npm ci --silent
CI=1 npx expo prebuild -p android --clean >/dev/null
if [ "$UNSIGNED" = 1 ]; then
  # Drop the template's debug key from release builds (its keystore is public), leaving the bundle unsigned.
  perl -0pi -e '
    s/versionCode \d+/versionCode '"$VERSION_CODE"'/;
    s/(release \{.*?)\n\s*signingConfig signingConfigs\.debug\n/$1\n/s;
  ' android/app/build.gradle
  [ "$(grep -c 'signingConfig signingConfigs.debug' android/app/build.gradle)" = 1 ] || { echo "Couldn't drop the debug key from android/app/build.gradle" >&2; exit 1; }
else
  # Release builds sign with the upload key instead of the template's debug key.
  perl -0pi -e '
    s/versionCode \d+/versionCode '"$VERSION_CODE"'/;
    s/signingConfigs \{/signingConfigs {\n        upload {\n            storeFile file(System.getenv("KINWALL_UPLOAD_KEYSTORE"))\n            storePassword System.getenv("KINWALL_UPLOAD_PASSWORD")\n            keyAlias System.getenv("KINWALL_UPLOAD_ALIAS") ?: "upload"\n            keyPassword System.getenv("KINWALL_UPLOAD_PASSWORD")\n        }/;
    s/(release \{.*?)signingConfig signingConfigs\.debug/$1signingConfig signingConfigs.upload/s;
  ' android/app/build.gradle
  grep -q 'signingConfig signingConfigs.upload' android/app/build.gradle || { echo "Couldn't wire the upload key into android/app/build.gradle" >&2; exit 1; }
fi
(cd android && ./gradlew -q bundleRelease)
OUT="${OUT:-$HOME/Desktop/kinwall-$(node -p "require('./package.json').version")-$VERSION_CODE.aab}"
cp android/app/build/outputs/bundle/release/app-release.aab "$OUT"
echo "Version code $VERSION_CODE: $OUT"
