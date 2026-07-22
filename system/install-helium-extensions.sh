#!/usr/bin/env bash
# Download Helium/Chromium extensions as external CRX + symlink into place.
# Survives extension-registry wipes; Helium loads from /usr/share/chromium/extensions/.
#
# CRX files are fetched through the Helium services extension proxy
# (https://services.helium.imput.net/ext/) so Google never sees your IP.
# Same Omaha GET protocol as clients2.google.com; the proxy redirects to an
# HMAC-signed one-hour URL that streams the CRX. Use --direct to fetch from
# Google directly if the proxy is down.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ext_dir="${repo_root}/system/usr/share/chromium/extensions"
policy_file="${repo_root}/system/etc/chromium/policies/managed/helium-managed.json"
ext_dest="/usr/share/chromium/extensions"
policy_dest="/etc/chromium/policies/managed/helium-managed.json"

dry_run=0
restart_helium=0
use_proxy=1

# Self-hosters: override with your own instance origin.
helium_services="${HELIUM_SERVICES_URL:-https://services.helium.imput.net}"

usage() {
  cat <<'EOF'
Usage: install-helium-extensions.sh [options]

Download extension CRX files into dotfiles, write external extension JSON,
and symlink them into /usr/share/chromium + /etc/chromium for Helium.

Downloads go through the Helium services extension proxy by default, so
Google does not see your IP. Set HELIUM_SERVICES_URL to use a self-hosted
instance.

Options:
  -n, --dry-run     Show actions without downloading or deploying
  -r, --restart     Quit Helium after install (does not auto-relaunch)
  -d, --direct      Download from clients2.google.com instead of Helium proxy
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) dry_run=1 ;;
    -r|--restart) restart_helium=1 ;;
    -d|--direct) use_proxy=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# id:name — external CRX descriptors; do NOT also list these in
# ExtensionInstallForcelist (broken force-install pipeline in Helium
# blocks the external CRX provider for the same IDs).
extensions=(
  hfjbmagddngcpeloejdejnfgbamkjaeg:'Vimium C'
  ponfpcnoihfmfllpaingbgckeeldkhle:'Enhancer for YouTube'
  mnjggcdmjocbbbhaepdhchncahnbgone:'SponsorBlock'
  eimadpbcbfnmbkopoojfekhnkhdbieeh:'Dark Reader'
  fgmjlmbojbkmdpofahffgcpkhkngfpef:'Startpage'
  nngceckbapebfimnlniiiahkandclblb:'Bitwarden'
  edibdbjcniadpccecjdfdjjppcpchdlm:"I still don't care about cookies"
  clngdbkpkpeebahjckkjfobafhncgmne:'Stylus'
)

chromium_version() {
  local helium_bin=""
  for candidate in /opt/helium-browser-bin/helium /usr/bin/helium-browser; do
    if [[ -x "$candidate" ]]; then
      helium_bin="$candidate"
      break
    fi
  done

  if [[ -n "$helium_bin" ]]; then
    "$helium_bin" --version 2>/dev/null | sed -n 's/.*(Chromium \([0-9.]*\)).*/\1/p'
    return
  fi

  echo "150.0.0.0"
}

crx_version() {
  local crx_path="$1"
  python3 - "$crx_path" <<'PY'
import struct, json, zipfile, io, sys

path = sys.argv[1]
data = open(path, "rb").read()
if not data.startswith(b"Cr24"):
    sys.exit("not a CRX3 file")
header_size = struct.unpack("<I", data[8:12])[0]
zip_data = data[12 + header_size :]
manifest = json.loads(zipfile.ZipFile(io.BytesIO(zip_data)).read("manifest.json"))
print(manifest["version"])
PY
}

download_crx() {
  local ext_id="$1"
  local out_path="$2"
  local prodversion="$3"
  local url

  if [[ "$use_proxy" -eq 1 ]]; then
    # Helium extension proxy speaks the same Omaha GET protocol;
    # it randomizes prodversion server-side and mixes requests with
    # other users' extension IDs before contacting Google.
    url="${helium_services}/ext/?response=redirect&acceptformat=crx2,crx3&x=id%3D${ext_id}%26installsource%3Dondemand%26uc"
  else
    url="https://clients2.google.com/service/update2/crx?response=redirect&prodversion=${prodversion}&acceptformat=crx2,crx3&x=id%3D${ext_id}%26installsource%3Dondemand%26uc"
  fi

  curl -fsSL --retry 3 --retry-delay 2 -o "$out_path" "$url"
}

write_json() {
  local ext_id="$1"
  local version="$2"
  local json_path="${ext_dir}/${ext_id}.json"

  cat >"$json_path" <<EOF
{
  "external_crx": "/usr/share/chromium/extensions/${ext_id}.crx",
  "external_version": "${version}"
}
EOF
}

prodversion="$(chromium_version)"
if [[ "$use_proxy" -eq 1 ]]; then
  echo "Downloading via Helium proxy: ${helium_services}/ext/"
else
  echo "Downloading directly from Google (prodversion ${prodversion})"
fi
mkdir -p "$ext_dir"

failed=()
for entry in "${extensions[@]}"; do
  ext_id="${entry%%:*}"
  name="${entry#*:}"
  crx_path="${ext_dir}/${ext_id}.crx"

  echo "==> ${name} (${ext_id})"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "    would download -> ${crx_path}"
    continue
  fi

  if ! download_crx "$ext_id" "$crx_path" "$prodversion"; then
    echo "    FAILED download" >&2
    failed+=("$name")
    continue
  fi

  version="$(crx_version "$crx_path")"
  write_json "$ext_id" "$version"
  echo "    ${version} -> ${crx_path}"
done

if [[ ! -f "$policy_file" ]]; then
  echo "WARN: policy file missing: ${policy_file}" >&2
elif grep -q ExtensionInstallForcelist "$policy_file"; then
  echo "WARN: ExtensionInstallForcelist found in ${policy_file}." >&2
  echo "      Force-install via Helium services is broken and blocks the" >&2
  echo "      external CRX provider for the same extension IDs. Remove it." >&2
fi

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo -E "$@"
  fi
}

echo
if [[ "$dry_run" -eq 1 ]]; then
  echo "Would link ${ext_dir} -> ${ext_dest}"
  echo "Would link ${policy_file} -> ${policy_dest}"
else
  run_root bash -c '
    set -euo pipefail
    ext_dir="$1"; ext_dest="$2"; policy_file="$3"; policy_dest="$4"
    mkdir -p "${ext_dest}" "$(dirname "${policy_dest}")"
    for f in "${ext_dir}"/*; do
      [[ -e "$f" ]] || continue
      ln -sfn "$f" "${ext_dest}/$(basename "$f")"
    done
    if [[ -f "$policy_file" ]]; then
      ln -sfn "$policy_file" "$policy_dest"
    fi
    echo "Linked extensions -> ${ext_dest}"
    [[ -f "$policy_file" ]] && echo "Linked policy -> ${policy_dest}"
  ' bash "$ext_dir" "$ext_dest" "$policy_file" "$policy_dest"
fi

if [[ ${#failed[@]} -gt 0 ]]; then
  echo
  echo "Failed:" >&2
  printf '  - %s\n' "${failed[@]}" >&2
  if [[ "$use_proxy" -eq 1 ]]; then
    echo "Retry with --direct if the Helium proxy is down." >&2
  fi
  exit 1
fi

echo
echo "Done. Quit Helium fully, then reopen."
echo "Check: helium://extensions"

if [[ "$restart_helium" -eq 1 && "$dry_run" -eq 0 ]]; then
  echo "Stopping Helium..."
  pkill -x helium 2>/dev/null || true
  echo "Start Helium manually when ready."
fi
