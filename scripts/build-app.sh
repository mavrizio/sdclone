#!/bin/bash
# Costruisce "build/SD Clone.app": l'app SwiftUI piu' l'eseguibile sdclone usato come helper.
# Uso: scripts/build-app.sh [release|debug]
# Di serie la firma e' ad-hoc (basta per usarla su questo Mac). Variabili per la distribuzione (le usa scripts/release.sh):
#   APP_DIR=cartella      dove creare l'app (default: build)
#   UNIVERSAL=1           eseguibili per Apple Silicon e Intel
#   SIGN_ID="Developer ID Application: ..."   firma Developer ID con hardened runtime e marca temporale
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
ARCHS=()
[ "${UNIVERSAL:-0}" = 1 ] && ARCHS=(--arch arm64 --arch x86_64)
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --product SDCloneApp
swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --product sdclone
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"

# Versione: unica fonte in Sources/SDCore/Version.swift.
VERSION=$(sed -n 's/.*marketing = "\(.*\)".*/\1/p' Sources/SDCore/Version.swift)
BUILD=$(sed -n 's/.*build = "\(.*\)".*/\1/p' Sources/SDCore/Version.swift)
[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "versione non trovata in Version.swift" >&2; exit 1; }
YEAR=$(date +%Y)

APP="${APP_DIR:-build}/SD Clone.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SDCloneApp" "$APP/Contents/MacOS/SDClone"
cp "$BIN/sdclone" "$APP/Contents/MacOS/sdclone-cli"

# Icona: generata da scripts/make-icon.swift, solo se manca o lo script e' piu' recente.
ICON="Resources/AppIcon.icns"
if [ ! -f "$ICON" ] || [ scripts/make-icon.swift -nt "$ICON" ]; then
    mkdir -p Resources
    ICONSET="$(mktemp -d)/AppIcon.iconset"
    swift scripts/make-icon.swift "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ICON"
fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SD Clone</string>
    <key>CFBundleDisplayName</key><string>SD Clone</string>
    <key>CFBundleIdentifier</key><string>com.mavrizio.sdclone</string>
    <key>CFBundleExecutable</key><string>SDClone</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>it</string>
    <key>NSHumanReadableCopyright</key><string>© $YEAR Maurizio Tolfa</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>SD Clone legge e scrive le schede SD per fare backup e ripristini.</string>
    <!-- "Apri con SD Clone" per le immagini: si aprono in Ripristina, senza fare nulla da sole. -->
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Immagine disco Raspberry Pi</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>CFBundleTypeExtensions</key><array><string>img</string><string>xz</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

if [ -n "${SIGN_ID:-}" ]; then
    # Prima l'eseguibile interno, poi il pacchetto (niente --deep: Apple lo sconsiglia per firmare).
    for target in "$APP/Contents/MacOS/sdclone-cli" "$APP"; do
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$target"
    done
    codesign --verify --deep --strict "$APP"
else
    codesign --force --deep --sign - "$APP" >/dev/null
fi
echo "Creata: $APP  (versione $VERSION, build $BUILD)"
