#!/bin/bash
# Prepara la versione da distribuire: app universale firmata Developer ID, DMG, notarizzazione Apple.
#
#   scripts/release.sh            firma, crea il DMG, lo notarizza e ci "attacca" il biglietto (staple)
#   scripts/release.sh --no-notarize   tutto tranne la notarizzazione (per provare)
#   SIGN_ID=- scripts/release.sh --no-notarize   prova senza certificato (firma ad-hoc: non distribuibile)
#
# Una volta sola, prima della prima notarizzazione, salvare le credenziali nel portachiavi:
#   xcrun notarytool store-credentials sdclone-notary --apple-id TUA@EMAIL --team-id TEAMID
# (chiede la password specifica per app creata su account.apple.com; non finisce mai nei file del progetto).
#
# Risultato in build/release/: "SD Clone.app" e SDClone-<versione>.dmg (+ .sha256). L'app in build/ non viene toccata.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTARIZE=1
[ "${1:-}" = "--no-notarize" ] && NOTARIZE=0
PROFILE="${NOTARY_PROFILE:-sdclone-notary}"

VERSION=$(sed -n 's/.*marketing = "\(.*\)".*/\1/p' Sources/SDCore/Version.swift)
OUT="build/release"
DMG="$OUT/SDClone-$VERSION.dmg"

# Certificato: SIGN_ID esplicito, altrimenti l'unico "Developer ID Application" nel portachiavi.
if [ -z "${SIGN_ID:-}" ]; then
    IDS=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | sort -u)
    COUNT=$(printf '%s' "$IDS" | grep -c . || true)
    if [ "$COUNT" != 1 ]; then
        echo "Certificati Developer ID Application trovati: $COUNT. Indica quale usare con SIGN_ID=\"Developer ID Application: Nome (TEAMID)\"." >&2
        [ -n "$IDS" ] && echo "$IDS" >&2
        exit 1
    fi
    SIGN_ID="$IDS"
fi
echo "Firma con: $SIGN_ID"

rm -rf "$OUT"
mkdir -p "$OUT"
if [ "$SIGN_ID" = "-" ]; then
    APP_DIR="$OUT" UNIVERSAL=1 scripts/build-app.sh release
else
    APP_DIR="$OUT" UNIVERSAL=1 SIGN_ID="$SIGN_ID" scripts/build-app.sh release
fi
APP="$OUT/SD Clone.app"
lipo -archs "$APP/Contents/MacOS/SDClone"

# DMG: l'app, il collegamento ad Applicazioni e la licenza.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applicazioni"
cp LICENSE "$STAGE/LICENSE.txt"
hdiutil create -volname "SD Clone $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
[ "$SIGN_ID" = "-" ] || codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

if [ "$NOTARIZE" = 1 ] && [ "$SIGN_ID" != "-" ]; then
    echo "Invio ad Apple per la notarizzazione (di solito pochi minuti)..."
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
else
    echo "Notarizzazione saltata: il DMG NON e' pronto per la distribuzione."
fi

(cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Pronto: $DMG"
cat "$DMG.sha256"
