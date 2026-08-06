-- Games auto-snap to a free workspace (>= 16) via game-snap-listener.
-- Super+G focuses / cycles; Super+Shift+G moves active window to a free game ws.
-- Match: class steam_app_*, cs2, gamescope. Extend game-lib.sh for more.

-- FPS: must be Hyprland exclusive fullscreen ALONE on the workspace.
-- Floating / 16:9-grouped with Steam → compositor taxes every frame → stutters.
--
-- Aspect (no ultrawide FOV): fullscreen gamescope, pillarbox via -S integer
-- (black bars). Do not float a smaller window — that path is what killed FPS.
-- Requires general:allow_tearing = true (looknfeel.lua) for `immediate`.

hl.window_rule({
  name = "game-perf",
  match = { class = "^(cs2|gamescope(-wl)?|steam_app_.*)$" },

  fullscreen = true,
  no_anim = true,
  no_shadow = true,
  opaque = true,
  immediate = true,
  content = "game",
  tag = "+game",
})

hl.window_rule({
  name = "game-tag-perf",
  match = { tag = "game" },

  fullscreen = true,
  no_anim = true,
  no_shadow = true,
  opaque = true,
  immediate = true,
  content = "game",
})

-- Steam launch options (Properties → Launch Options):
-- -f exclusive. -W/-H = panel. -w/-h = play res. -S integer = black-bar pillarbox.
--   gamemoderun gamescope -f -w 2560 -h 1440 -W 3440 -H 1440 -r 240 -S integer -F nearest -b --force-grab-cursor --force-windows-fullscreen --immediate-flips -- %command% -novid +fps_max 260
-- Tighter: -w 1920 -h 1440
