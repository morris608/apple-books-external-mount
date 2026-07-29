#!/bin/zsh
# Build the SwiftUI Eject Books Drive.app into apps/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${ROOT}/apps/EjectBooksDriveUI"
APP="${ROOT}/apps/Eject Books Drive.app"
SDK="$(xcrun --show-sdk-path)"
MACOS_MIN="14.0"
ARCH="$(uname -m)"
OUTDIR="$(mktemp -d)"
BIN="${OUTDIR}/EjectBooksDrive"

print "Compiling Eject Books Drive (SwiftUI / Plate)…"
/usr/bin/swiftc -parse-as-library \
  -whole-module-optimization \
  -O \
  -target "${ARCH}-apple-macosx${MACOS_MIN}" \
  -sdk "${SDK}" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -o "${BIN}" \
  "${SRC}/DesignSystem.swift" \
  "${SRC}/EjectWindowView.swift" \
  "${SRC}/EjectController.swift" \
  "${SRC}/EjectBooksDriveApp.swift"

print "Assembling app bundle…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
mv "${BIN}" "${APP}/Contents/MacOS/EjectBooksDrive"
chmod +x "${APP}/Contents/MacOS/EjectBooksDrive"

if [[ -f "${ROOT}/apps/EjectBooksDrive.icns" ]]; then
  cp "${ROOT}/apps/EjectBooksDrive.icns" "${APP}/Contents/Resources/AppIcon.icns"
fi

cat >"${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>EjectBooksDrive</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.davidmorris.eject-books-drive</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Eject Books Drive</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>3.0</string>
	<key>CFBundleVersion</key>
	<string>3</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "${APP}" 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "${APP}" >/dev/null 2>&1 || true
rm -rf "${OUTDIR}"
print "Built: ${APP}"
