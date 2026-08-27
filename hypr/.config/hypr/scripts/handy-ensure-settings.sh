#!/usr/bin/env bash
# Baseline Handy settings for Hyprland toggle dictation (Super+V via compositor).
set -euo pipefail

readonly SETTINGS="${XDG_DATA_HOME:-$HOME/.local/share}/com.pais.handy/settings_store.json"
readonly DEFAULT_MODEL="handy-computer/parakeet-unified-en-0.6b-gguf/parakeet-unified-en-0.6b-Q8_0.gguf"

command -v jq >/dev/null 2>&1 || exit 0
[[ -f "$SETTINGS" ]] || exit 0

tmp="$(mktemp)"
jq --arg model "$DEFAULT_MODEL" '
  .settings.push_to_talk = false
  | .settings.selected_language = "en"
  | .settings.typing_tool = "wtype"
  | .settings.paste_method = "direct"
  | .settings.start_hidden = true
  | .settings.autostart_enabled = false
  | if (.settings.selected_model | length) == 0 then
      .settings.selected_model = $model
    else .
    end
' "$SETTINGS" >"$tmp"
mv "$tmp" "$SETTINGS"
