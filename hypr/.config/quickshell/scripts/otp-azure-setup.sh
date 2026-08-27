#!/usr/bin/env bash
# Create qs-otp Entra app + write ~/.config/qs-otp/config.toml via Azure CLI.
# Requires one browser approval (device code).
set -euo pipefail

AZ="${HOME}/.config/qs-otp/venv/bin/az"
PY="${HOME}/.config/qs-otp/venv/bin/python"
CONFIG_DIR="${HOME}/.config/qs-otp"
CONFIG="${CONFIG_DIR}/config.toml"
EMAIL_DEFAULT="jacobhallgren@live.se"
APP_NAME="qs-otp"

if [[ ! -x "$AZ" ]]; then
  echo "missing azure-cli in $AZ — pip install azure-cli into qs-otp venv first" >&2
  exit 1
fi

mkdir -p "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

echo "==> Login (browser / device code). Prefer personal Microsoft account."
echo "    If asked for directory, pick YOUR personal tenant — not byBrick/Pågengruppen."
"$AZ" login --use-device-code --allow-no-subscriptions

echo ""
echo "==> Current accounts/tenants:"
"$AZ" account list -o table || true

TENANT="$("$AZ" account show --query tenantId -o tsv 2>/dev/null || true)"
USER_EMAIL="$("$AZ" account show --query user.name -o tsv 2>/dev/null || true)"
EMAIL="${QS_OTP_EMAIL:-${USER_EMAIL:-$EMAIL_DEFAULT}}"

echo ""
echo "Using tenant: ${TENANT:-unknown}"
echo "Using email:  $EMAIL"

echo ""
echo "==> Creating public client app: $APP_NAME"
# signInAudience: AzureADandPersonalMicrosoftAccount covers live.se
CREATE_OUT="$("$AZ" ad app create \
  --display-name "$APP_NAME" \
  --sign-in-audience AzureADandPersonalMicrosoftAccount \
  --public-client-redirect-uris "http://localhost" \
  --enable-id-token-issuance false \
  --query "{appId:appId,objectId:id}" -o json)"

APP_ID="$(printf '%s' "$CREATE_OUT" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["appId"])')"
OBJ_ID="$(printf '%s' "$CREATE_OUT" | "$PY" -c 'import json,sys; print(json.load(sys.stdin)["objectId"])')"

echo "  appId:    $APP_ID"
echo "  objectId: $OBJ_ID"

echo ""
echo "==> Allow public client flows"
"$AZ" ad app update --id "$APP_ID" --set isFallbackPublicClient=true >/dev/null

echo "==> Add Microsoft Graph Mail.Read (delegated)"
# Graph resource appId is well-known: 00000003-0000-0000-c000-000000000000
# Mail.Read delegated permission id: 570282fd-fa9c-4558-8edb-c5d1bd7fb325
set +e
"$AZ" ad app permission add \
  --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --api-permissions 570282fd-fa9c-4558-8edb-c5d1bd7fb325=Scope
PERM_RC=$?
set -e
if [[ $PERM_RC -ne 0 ]]; then
  echo "  warn: permission add failed — add Mail.Read in portal if login fails" >&2
fi

# Best-effort grant (works in owned tenants; often fails as guest)
set +e
"$AZ" ad app permission grant \
  --id "$APP_ID" \
  --api 00000003-0000-0000-c000-000000000000 \
  --scope Mail.Read >/dev/null 2>&1
"$AZ" ad app permission admin-consent --id "$APP_ID" >/dev/null 2>&1
set -e

umask 077
cat >"$CONFIG" <<EOF
email = "$EMAIL"
client_id = "$APP_ID"
authority = "https://login.microsoftonline.com/consumers"
EOF
chmod 600 "$CONFIG"

echo ""
echo "==> Wrote $CONFIG"
cat "$CONFIG"
echo ""
echo "==> Next: device-code login for the OTP watcher itself:"
echo "    ${HOME}/.config/quickshell/scripts/otp-watch.sh login"
echo "    then: systemctl --user restart qs-otp-watchd.service"
