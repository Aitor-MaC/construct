#!/usr/bin/env bash
# Construct: archiva, firma con Developer ID, empaqueta en DMG, notariza con Apple y grapa el ticket.
#
# Uso:
#   scripts/notarize.sh                 # proceso completo → build/notarize/Construct-<versión>.dmg
#   scripts/notarize.sh --no-notarize   # todo menos el envío a Apple (sirve para probar la firma)
#   scripts/notarize.sh --setup         # guarda las credenciales en el Llavero (una sola vez)
#
# Variables: APPLE_ID (obligatoria solo con --setup), TEAM_ID (por defecto, el del certificado
# «Developer ID Application» del Llavero) y NOTARY_PROFILE (por defecto, construct-notary).
# La contraseña específica de app NUNCA se pasa por argumentos ni se guarda en el repo:
# `--setup` la pide de forma interactiva y notarytool la guarda en el Llavero.
set -euo pipefail

APPLE_ID="${APPLE_ID:-}"
TEAM_ID="${TEAM_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-construct-notary}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="$ROOT/Macterminal.xcworkspace"
SCHEME="Macterminal"
APP_NAME="Construct"
OUT="$ROOT/build/notarize"
ARCHIVE="$OUT/$APP_NAME.xcarchive"
EXPORT_DIR="$OUT/export"
EXPORT_OPTIONS="$ROOT/scripts/ExportOptions-DeveloperID.plist"
IDENTITY="Developer ID Application"

NOTARIZE=1
step() { printf '\n\033[1;32m▸ %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

# Sin TEAM_ID explícito se usa el equipo del (primer) certificado Developer ID del Llavero.
resolve_team_id() {
  [[ -n "$TEAM_ID" ]] && return 0
  TEAM_ID="$(security find-identity -v -p codesigning \
    | sed -n "s/.*\"$IDENTITY: .*(\([A-Z0-9]\{10\}\))\".*/\1/p" | head -1)"
  [[ -n "$TEAM_ID" ]] || fail "No hay ningún certificado «$IDENTITY» en el Llavero (o define TEAM_ID)."
}

setup_credentials() {
  [[ -n "$APPLE_ID" ]] || fail "Define tu Apple ID: APPLE_ID=tu@correo scripts/notarize.sh --setup"
  resolve_team_id
  step "Guardando credenciales de notarización en el Llavero (perfil «$NOTARY_PROFILE»)"
  echo "Necesitas una contraseña específica de app para $APPLE_ID."
  echo "Créala en https://account.apple.com → Inicio de sesión y seguridad → Contraseñas específicas de app."
  echo "notarytool te la pedirá ahora; no se mostrará ni se guardará en el proyecto."
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID"
  echo "Listo. Ya puedes ejecutar: scripts/notarize.sh"
}

case "${1:-}" in
  --setup) setup_credentials; exit 0 ;;
  --no-notarize) NOTARIZE=0 ;;
  "") ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  *) fail "Opción desconocida: $1 (usa --help)" ;;
esac

step "Comprobaciones previas"
command -v xcodebuild >/dev/null || fail "Falta xcodebuild (instala Xcode)."
resolve_team_id
# Se firma por la huella SHA-1: el nombre del certificado lleva acentos y codesign no lo resuelve bien.
IDENTITY_LINE="$(security find-identity -v -p codesigning | grep "\"$IDENTITY: .*($TEAM_ID)\"" | head -1 || true)"
[[ -n "$IDENTITY_LINE" ]] || fail "No hay un certificado «$IDENTITY» del equipo $TEAM_ID en el Llavero."
SIGNING_HASH="$(awk '{print $2}' <<<"$IDENTITY_LINE")"
SIGNING_IDENTITY="$(sed -E 's/^[^"]*"(.*)"$/\1/' <<<"$IDENTITY_LINE")"
if [[ $NOTARIZE -eq 1 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "No hay credenciales guardadas en el perfil «$NOTARY_PROFILE». Ejecuta primero: scripts/notarize.sh --setup"
fi
echo "Certificado: $SIGNING_IDENTITY"

rm -rf "$OUT"
mkdir -p "$OUT"

step "Archivando (Release)"
xcodebuild archive \
  -workspace "$WORKSPACE" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  -skipPackagePluginValidation DEVELOPMENT_TEAM="$TEAM_ID" -quiet \
  || fail "Falló el archivado."

step "Exportando con firma Developer ID"
# La plantilla no lleva equipo: se rellena con el de este Mac.
OPTIONS="$OUT/ExportOptions.plist"
cp "$EXPORT_OPTIONS" "$OPTIONS"
/usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$OPTIONS"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" -quiet \
  || fail "Falló la exportación."
APP="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP" ]] || fail "No se encontró $APP tras exportar."

step "Verificando la firma de la app"
codesign --verify --deep --strict --verbose=2 "$APP"
SIGN_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q "Authority=$IDENTITY" <<<"$SIGN_INFO" || fail "La app no está firmada con $IDENTITY."
grep -q "flags=.*runtime" <<<"$SIGN_INFO" || fail "Falta Hardened Runtime (obligatorio para notarizar)."
grep -q "Timestamp=" <<<"$SIGN_INFO" || fail "La firma no lleva sello de tiempo seguro."
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q "get-task-allow"; then
  fail "La app lleva el entitlement get-task-allow (Apple la rechazaría)."
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "Firma OK · $APP_NAME $VERSION ($BUILD)"

step "Creando el DMG"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
DMG_ASSETS="$ROOT/scripts/dmg"
if command -v uvx >/dev/null && [[ -f "$DMG_ASSETS/background.tiff" ]]; then
  # DMG personalizado: fondo Matrix, ventana fija, iconos colocados e icono de volumen (dmgbuild fijado).
  uvx --from 'dmgbuild==1.6.5' dmgbuild -s "$DMG_ASSETS/settings.py" \
    -D app="$APP" -D assets="$DMG_ASSETS" "$APP_NAME" "$DMG" >/dev/null 2>&1 \
    || fail "No se pudo crear el DMG personalizado (dmgbuild)."
else
  echo "uvx no disponible: se crea un DMG sencillo sin fondo personalizado."
  STAGING="$OUT/dmg"
  mkdir -p "$STAGING"
  ditto "$APP" "$STAGING/$APP_NAME.app"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null 2>&1 \
    || fail "No se pudo crear el DMG."
  rm -rf "$STAGING"
fi
codesign --force --sign "$SIGNING_HASH" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"
echo "DMG: $DMG"

if [[ $NOTARIZE -eq 0 ]]; then
  step "Sin notarizar (--no-notarize)"
  echo "La firma y el DMG están listos. Para notarizar, ejecuta el script sin --no-notarize."
  exit 0
fi

step "Enviando a Apple para notarizar (puede tardar unos minutos)"
RESULT="$OUT/notary-result.json"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json >"$RESULT" \
  || true
STATUS="$(/usr/bin/python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "$RESULT" 2>/dev/null || true)"
SUBMISSION_ID="$(/usr/bin/python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1])).get("id",""))' "$RESULT" 2>/dev/null || true)"
echo "Envío $SUBMISSION_ID → $STATUS"
if [[ "$STATUS" != "Accepted" ]]; then
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" "$OUT/notary-log.json" || true
    echo "Informe de Apple: $OUT/notary-log.json"
  fi
  fail "Apple no aceptó la notarización (estado: ${STATUS:-desconocido})."
fi

step "Grapando el ticket"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"
xcrun stapler validate "$DMG"

step "Comprobando con Gatekeeper"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

step "Hecho"
echo "DMG notarizado: $DMG"
echo "App notarizada: $APP"
