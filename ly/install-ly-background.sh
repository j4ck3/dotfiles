#!/usr/bin/env bash
# Install Ly durdraw background and enable dur_file animation in /etc/ly/config.ini.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dur_name="${1:-blackhole-smooth.dur}"
dur_src="${repo_root}/ly/etc/ly/backgrounds/${dur_name}"
dur_dest="/etc/ly/backgrounds/${dur_name}"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo bash ly/install-ly-background.sh" >&2
  exit 1
fi

if [[ ! -f "${dur_src}" ]]; then
  echo "Missing ${dur_src}" >&2
  exit 1
fi

read -r dur_w dur_h dur_fill < <(
  python3 - "${dur_src}" <<'PY'
import gzip, json, sys
path = sys.argv[1]
with gzip.open(path, "rt") as f:
    data = json.load(f)
contents = data["DurMovie"]["frames"][0]["contents"]
width = max(len(line) for line in contents)
height = len(contents)
total = sum(len(line) for line in contents)
filled = sum(ch != " " for line in contents for ch in line)
fill = filled / total if total else 0
print(width, height, f"{fill:.3f}")
PY
)

echo "Source dur: ${dur_w}x${dur_h}, fill ${dur_fill}"

if python3 - "${dur_fill}" <<'PY'
import sys
fill = float(sys.argv[1])
raise SystemExit(0 if 0.08 <= fill <= 0.75 else 1)
PY
then
  :
else
  echo "Refusing install: fill ${dur_fill} looks wrong (want ~0.15-0.60)." >&2
  echo "Rebuild first: bash ly/rebuild-fractal-background.sh" >&2
  exit 1
fi

if [[ -x "${repo_root}/ly/scripts/ly-tty-size.sh" ]]; then
  if tty_size="$("${repo_root}/ly/scripts/ly-tty-size.sh" 2>/dev/null)"; then
  tty_w="${tty_size%x*}"
  tty_h="${tty_size#*x}"
  if [[ "${dur_w}" != "${tty_w}" || "${dur_h}" != "${tty_h}" ]]; then
    echo "Warning: dur is ${dur_w}x${dur_h} but Ly TTY is ${tty_size}." >&2
    echo "Rebuild: bash ly/rebuild-fractal-background.sh" >&2
  fi
  fi
fi

config=/etc/ly/config.ini
if [[ ! -f "${config}" ]]; then
  echo "Missing ${config} — is ly installed?" >&2
  exit 1
fi

# Real file under /etc (not a stow symlink into $HOME).
if [[ -L /etc/ly/backgrounds ]]; then
  rm -f /etc/ly/backgrounds
fi
install -d -m 755 /etc/ly/backgrounds
install -m 644 "${dur_src}" "${dur_dest}"

patch_ini() {
  local key="$1" value="$2"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${config}"; then
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "${config}"
  else
    printf '\n%s = %s\n' "${key}" "${value}" >>"${config}"
  fi
}

patch_ini animation dur_file
patch_ini dur_file_path "${dur_dest}"
patch_ini dur_offset_alignment topleft
patch_ini dur_x_offset 0
patch_ini dur_y_offset 0
patch_ini full_color true
patch_ini animation_frame_delay 3

# Ly reads config only at process start — logout is not enough.
mapfile -t ly_units < <(systemctl list-units --type=service --all 'ly@*.service' --no-legend 2>/dev/null | awk '{print $1}' || true)
if ((${#ly_units[@]} > 0)); then
  systemctl restart "${ly_units[@]}"
  echo "Restarted: ${ly_units[*]}"
else
  echo "No ly@*.service units found. Restart ly manually after logout." >&2
fi

echo "Ly background installed (${dur_dest}). Switch to login VT (Ctrl+Alt+F1/F2) to verify."
