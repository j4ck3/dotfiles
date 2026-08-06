#!/usr/bin/env bash
# Shared helpers for game snap / Super+G focus.
# Games: steam_app_*, cs2, gamescope (+ already tagged "game").

# Reserved for pinned apps / daily workspaces — games start at 16+.
GAME_WS_MIN=16
GAME_WS_MAX=99
GAME_TAG=game

# jq filter: true if client object is a game window
GAME_JQ_FILTER='
  (.class // "" | test("^(steam_app_|cs2$|gamescope(-wl)?$)"))
  or (.initialClass // "" | test("^(steam_app_|cs2$|gamescope(-wl)?$)"))
  or ((.tags // []) | index("game") != null)
  or ((.tags // []) | index("game*") != null)
'

is_game_json() {
	jq -e "$GAME_JQ_FILTER" >/dev/null 2>&1 <<<"$1"
}

list_game_clients_json() {
	hyprctl clients -j 2>/dev/null | jq -c --argjson min "$GAME_WS_MIN" "
		[.[] | select($GAME_JQ_FILTER)]
		| sort_by(.focusHistoryID // 9999)
	"
}

# Lowest empty workspace in GAME_WS_MIN..GAME_WS_MAX
# Optional extra occupied ids (space-separated) for multi-move assignment.
find_free_game_workspace() {
	local extra="${1:-}"
	local id
	id=$(hyprctl clients -j 2>/dev/null | jq -r --argjson min "$GAME_WS_MIN" --argjson max "$GAME_WS_MAX" --arg extra "$extra" '
		([.[].workspace.id] + ($extra | split(" ") | map(select(length > 0) | tonumber)))
		| unique as $taken
		| first(range($min; $max + 1) | select(. as $id | ($taken | index($id)) == null))
		// $min
	')
	echo "${id:-$GAME_WS_MIN}"
}

tag_game_window() {
	local addr="$1"
	[[ "$addr" != 0x* ]] && addr="0x$addr"
	hyprctl dispatch tagwindow "+${GAME_TAG},address:$addr" >/dev/null 2>&1 || true
}

# Break out of 16:9 / tab groups so the game can exclusive-fullscreen alone.
ungroup_game_window() {
	local addr="$1"
	[[ "$addr" != 0x* ]] && addr="0x$addr"
	local n
	n=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" \
		'.[] | select(.address == $a) | (.grouped // []) | length' || echo 0)
	[[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 ]] || return 0
	hyprctl dispatch focuswindow "address:$addr" >/dev/null 2>&1 || true
	hyprctl dispatch moveoutofgroup >/dev/null 2>&1 || true
}

move_game_to_workspace() {
	local addr="$1"
	local ws="$2"
	[[ "$addr" != 0x* ]] && addr="0x$addr"
	ungroup_game_window "$addr"
	hyprctl dispatch movetoworkspacesilent "$ws,address:$addr" >/dev/null 2>&1 || true
}
