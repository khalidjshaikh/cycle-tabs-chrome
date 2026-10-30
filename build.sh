#!/bin/bash
# Builds CycleTabs and assembles a signed-for-local-use .app bundle in dist/.
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="CycleTabs"
BUNDLE_ID="com.kshaikh.cycletabs"
DIST="dist/${APP_NAME}.app"

echo "Building ${APP_NAME} (release)…"
swift build -c release --product "${APP_NAME}"

BIN=".build/release/${APP_NAME}"

rm -rf "${DIST}"
mkdir -p "${DIST}/Contents/MacOS" "${DIST}/Contents/Resources"

cp "${BIN}" "${DIST}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${DIST}/Contents/Info.plist"

# Ad-hoc signature: enough for local use, and gives the app a stable identity
# for the Automation (Apple Events) permission prompt.
codesign --force --sign - --identifier "${BUNDLE_ID}" "${DIST}"

echo "Built ${DIST}"
echo "Run it with: open ${DIST}"
