#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KEYCHAIN_ACCOUNT="HxinY499"
KEYCHAIN_SERVICE="LigyTally Android Release Keystore"
KEYSTORE_PATH="${LIGY_KEYSTORE_PATH:-$HOME/.android/ligy-tally-release.jks}"
KEY_ALIAS="${LIGY_KEY_ALIAS:-ligy-tally}"
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"

if [[ ! -f "$KEYSTORE_PATH" ]]; then
  echo "Release keystore not found: $KEYSTORE_PATH" >&2
  exit 1
fi

if ! STORE_PASSWORD="$(security find-generic-password \
  -a "$KEYCHAIN_ACCOUNT" \
  -s "$KEYCHAIN_SERVICE" \
  -w 2>/dev/null)"; then
  echo "Release password not found in macOS Keychain." >&2
  exit 1
fi

export LIGY_KEYSTORE_PATH="$KEYSTORE_PATH"
export LIGY_STORE_PASSWORD="$STORE_PASSWORD"
export LIGY_KEY_PASSWORD="$STORE_PASSWORD"
export LIGY_KEY_ALIAS="$KEY_ALIAS"

cd "$ROOT_DIR"

VERSION="$(awk '/^version:/ {print $2}' pubspec.yaml)"
VERSION_NAME="${VERSION%%+*}"
SYMBOLS_DIR="${LIGY_SYMBOLS_DIR:-$HOME/Documents/LigyTally-release-symbols/$VERSION_NAME}"

flutter pub get
flutter analyze
flutter test --timeout 30s

BUILD_DIR="$(mktemp -d /tmp/ligy-tally-release.XXXXXX)"
trap 'rm -rf -- "$BUILD_DIR"' EXIT

rsync -a \
  --exclude='.git/' \
  --exclude='.dart_tool/' \
  --exclude='.idea/' \
  --exclude='build/' \
  --exclude='dist/' \
  "$ROOT_DIR/" "$BUILD_DIR/"

mkdir -p "$SYMBOLS_DIR"
chmod 700 "$(dirname "$SYMBOLS_DIR")" "$SYMBOLS_DIR"

cd "$BUILD_DIR"
export PUB_CACHE="$BUILD_DIR/.pub-cache"
flutter pub get
flutter build apk --release \
  --obfuscate \
  --split-debug-info="$SYMBOLS_DIR"

DIST_DIR="$ROOT_DIR/dist"
APK_PATH="$DIST_DIR/LigyTally-$VERSION_NAME.apk"
SHA_PATH="$APK_PATH.sha256"
APKSIGNER="$HOME/Library/Android/sdk/build-tools/36.0.0/apksigner"

mkdir -p "$DIST_DIR"
cp "$BUILD_DIR/build/app/outputs/flutter-apk/app-release.apk" "$APK_PATH"

"$APKSIGNER" verify --verbose --print-certs "$APK_PATH"

if LC_ALL=C grep -a -q -E 'file:///Users/|/Users/|lotsohe' "$APK_PATH"; then
  echo "Release APK contains an absolute user path; refusing to publish." >&2
  exit 1
fi

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$APK_PATH")" > "$(basename "$SHA_PATH")"
)

unset STORE_PASSWORD LIGY_STORE_PASSWORD LIGY_KEY_PASSWORD

echo "Release APK: $APK_PATH"
echo "SHA-256:    $SHA_PATH"
echo "Symbols:    $SYMBOLS_DIR"
