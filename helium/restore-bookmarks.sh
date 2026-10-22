#!/usr/bin/env bash
# Restore the Helium bookmark snapshot from dotfiles into the live profile.
# Quit Helium completely first; it overwrites the file on exit otherwise.
set -euo pipefail
src="$(dirname "$(readlink -f "$0")")/Bookmarks"
dst="$HOME/.config/net.imput.helium/Default/Bookmarks"
if pgrep -x helium >/dev/null; then
  echo "Helium is running. Quit it first." >&2
  exit 1
fi
mkdir -p "$(dirname "$dst")"
[ -f "$dst" ] && cp "$dst" "$dst.pre-restore"
install -m 600 "$src" "$dst"
echo "Restored $dst"
