#!/usr/bin/env bash
# Baseline Handy settings for Hyprland toggle dictation (Super+V via compositor).
# Post-process via local S1-mini (Superwhisper) OpenAI proxy on :18180.
set -euo pipefail

readonly SETTINGS="${XDG_DATA_HOME:-$HOME/.local/share}/com.pais.handy/settings_store.json"
readonly PASTE_SCRIPT="${HANDY_PASTE_SCRIPT:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/handy-paste}"
readonly DEFAULT_MODEL="handy-computer/parakeet-unified-en-0.6b-gguf/parakeet-unified-en-0.6b-Q8_0.gguf"
readonly S1_PROMPT_ID="s1_mini_normalize"
readonly S1_PROMPT='${output}'
readonly S1_BASE_URL="http://127.0.0.1:18180/v1"

command -v jq >/dev/null 2>&1 || exit 0
[[ -f "$SETTINGS" ]] || exit 0

tmp="$(mktemp)"
jq \
  --arg model "$DEFAULT_MODEL" \
  --arg prompt_id "$S1_PROMPT_ID" \
  --arg prompt "$S1_PROMPT" \
  --arg base_url "$S1_BASE_URL" \
  --arg paste_script "$PASTE_SCRIPT" \
  '
  .settings.push_to_talk = false
  | .settings.selected_language = "en"
  | .settings.typing_tool = "ydotool"
  # External paste: refocus + wl-copy + ydotool Ctrl+V. Built-in wtype Ctrl+V
  # misses Electron inputs (t3code). Direct wtype still garbles on sv-SE layout.
  | .settings.paste_method = "external_script"
  | .settings.external_script_path = $paste_script
  | .settings.clipboard_handling = "dont_modify"
  | .settings.start_hidden = true
  | .settings.autostart_enabled = false
  | .settings.experimental_enabled = true
  | .settings.post_process_enabled = true
  | .settings.post_process_provider_id = "custom"
  | .settings.post_process_models.custom = "s1-mini"
  | .settings.post_process_api_keys.custom = "local"
  | .settings.post_process_selected_prompt_id = $prompt_id
  | .settings.post_process_providers = (
      (.settings.post_process_providers // [])
      | map(
          if .id == "custom" then
            .base_url = $base_url
            | .allow_base_url_edit = true
            | .supports_structured_output = false
          else .
          end
        )
    )
  | .settings.post_process_prompts = (
      ((.settings.post_process_prompts // []) | map(select(.id != $prompt_id)))
      + [{
          id: $prompt_id,
          name: "S1-mini (Superwhisper)",
          prompt: $prompt
        }]
    )
  | if (.settings.selected_model | length) == 0 then
      .settings.selected_model = $model
    else .
    end
' "$SETTINGS" >"$tmp"
mv "$tmp" "$SETTINGS"
