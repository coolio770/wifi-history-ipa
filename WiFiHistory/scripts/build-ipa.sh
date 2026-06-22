#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/WiFiHistory.xcarchive"
DERIVED_DATA="${BUILD_DIR}/DerivedData"
IPA_PATH="${BUILD_DIR}/WiFiHistory.ipa"
SCHEME="WiFiHistory"
PROJECT="${ROOT_DIR}/WiFiHistory.xcodeproj"
ENTITLEMENTS="${ROOT_DIR}/WiFiHistory/entitlements.plist"

mkdir -p "${BUILD_DIR}"

echo "==> Building Release (generic iOS device)"
set +e
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Release \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="" \
  archive
ARCHIVE_STATUS=$?
set -e

APP_PATH=""
if [[ ${ARCHIVE_STATUS} -eq 0 && -d "${ARCHIVE_PATH}/Products/Applications/WiFiHistory.app" ]]; then
  APP_PATH="${ARCHIVE_PATH}/Products/Applications/WiFiHistory.app"
else
  echo "==> Archive failed or incomplete; falling back to derived-data build"
  rm -rf "${DERIVED_DATA}"
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination "generic/platform=iOS" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_IDENTITY="" \
    build
  APP_PATH="$(find "${DERIVED_DATA}" -path '*/Build/Products/Release-iphoneos/WiFiHistory.app' -type d | head -n 1)"
fi

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "ERROR: WiFiHistory.app was not produced."
  exit 1
fi

BINARY="${APP_PATH}/WiFiHistory"
if [[ ! -f "${BINARY}" ]]; then
  echo "ERROR: App binary missing at ${BINARY}"
  exit 1
fi

if command -v ldid >/dev/null 2>&1; then
  echo "==> Applying jailbreak entitlements with ldid"
  ldid -S"${ENTITLEMENTS}" "${BINARY}"
else
  echo "WARNING: ldid not found. Password keychain access may not work until re-signed on device."
fi

echo "==> Packaging IPA"
PAYLOAD_DIR="${BUILD_DIR}/Payload"
rm -rf "${PAYLOAD_DIR}" "${IPA_PATH}"
mkdir -p "${PAYLOAD_DIR}"
cp -R "${APP_PATH}" "${PAYLOAD_DIR}/"
(cd "${BUILD_DIR}" && zip -qr "WiFiHistory.ipa" Payload)
rm -rf "${PAYLOAD_DIR}"

echo "Done: ${IPA_PATH}"
ls -lh "${IPA_PATH}"
