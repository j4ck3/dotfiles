-- Autostart + window placement rules
-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
  -- Polkit: pkexec / privilege prompts. polkit-gnome alone often fails on Hyprland+uwsm; install hyprpolkitagent.
  -- Logs: $XDG_RUNTIME_DIR/polkit-agent.log
  hl.exec_cmd(
    "dbus-update-activation-environment --systemd WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP DISPLAY COLOR_SCHEME GTK_THEME GTK2_RC_FILES QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE 2>/dev/null || true"
  )
  hl.exec_cmd("apply-gnome-theme 2>/dev/null || true")
  hl.exec_cmd(scripts .. "/start-keyring")
  hl.exec_cmd(scripts .. "/start-polkit-agent")

  -- Quickshell as user service (survives shell exit; claims notifications)
  hl.exec_cmd("systemctl --user start quickshell.service")
  hl.exec_cmd("wl-paste --type text --watch cliphist store")
  hl.exec_cmd("wl-paste --type image --watch cliphist store")
  hl.exec_cmd("helium-browser")
  -- Software brightness + blue-light (hyprctl hyprsunset gamma|temperature)
  hl.exec_cmd("uwsm-app -- hyprsunset")
  -- Handy: background app for Super+V toggle (--toggle-transcription via Hypr bind).
  hl.exec_cmd("uwsm-app -- " .. scripts .. "/handy-start")
  hl.exec_cmd("enable-keyboard-wake")
  hl.exec_cmd(scripts .. "/kbd-unstick")

  -- Spotify resets sink-input volume on new tracks; user service survives hyprctl reload (exec-once does not)
  hl.exec_cmd("systemctl --user start spotify-volume-guard.service")
  -- Outlook OTP watcher (PowerMenu arm → Graph poll → bar chip)
  hl.exec_cmd("systemctl --user start qs-otp-watchd.service")

  -- Workspace 2 monocle mode - maximize and stack all windows
  hl.exec_cmd(scripts .. "/workspace2-monocle")

  -- Games (steam_app_*/cs2/gamescope) → free workspace >= 16; Super+G focuses them
  hl.exec_cmd(scripts .. "/game-snap-listener-watchdog")
end)

-- Normal app windows enter the 16:9 floating group before their first frame.
-- Initially-floating windows are dialogs/popups and keep their requested geometry.
-- Vertical bar (Theme.barWidth=56): full height minus gaps_out; pillarbox in remaining width.
local bar_width = 56 -- quickshell Theme.barWidth
local gaps_out = 4 -- looknfeel general.gaps_out
local gap_tb = gaps_out * 2
local bar_inset = bar_width + gaps_out * 2
hl.window_rule({
  name = "default-16-9",
  match = {
    class = ".*",
    float = false,
  },
  float = true,
  size = {
    string.format("(monitor_h - %d) * 16 / 9", gap_tb),
    string.format("monitor_h - %d", gap_tb),
  },
  move = {
    string.format(
      "%d + %d + (monitor_w - %d - (monitor_h - %d) * 16 / 9) / 2",
      bar_width,
      gaps_out,
      bar_inset,
      gap_tb
    ),
    tostring(gaps_out),
  },
  group = "set",
  no_anim = true,
})

-- Cursor → Workspace 2
hl.window_rule({
  name = "cursor-ws-2",
  match = { class = "^(cursor)$" },
  workspace = 2,
})

-- T3 Code → Workspace 2 (must match bindings.lua + webapp-launch)
hl.window_rule({
  name = "t3code-ws-2",
  match = { class = "^(t3code)$" },
  workspace = 2,
})

-- Spotify → Workspace 3
hl.window_rule({
  name = "spotify-ws-3",
  match = { class = "^(spotify)$" },
  workspace = 3,
})

-- Web apps / pinned apps → Workspaces 10–14 (must match bindings.lua + webapp-launch)

-- Trilium → Workspace 10
hl.window_rule({
  name = "trillium-ws-10",
  match = {
    class = "^(helium)$",
    title = ".*[Tt]rillium.*",
  },
  workspace = 10,
})

-- ChatGPT → Workspace 11
hl.window_rule({
  name = "chatgpt-ws-11",
  match = {
    class = "^(helium)$",
    title = ".*[Cc]hat[Gg][Pp][Tt].*",
  },
  workspace = 11,
})

-- YouTube → Workspace 12
hl.window_rule({
  name = "youtube-ws-12",
  match = {
    class = "^(helium)$",
    title = ".*[Yy]outube.*",
  },
  workspace = 12,
})

-- Discord → Workspace 13
hl.window_rule({
  name = "discord-ws-13",
  match = { class = "^(discord)$" },
  workspace = 13,
})

-- Steam → Workspace 14
hl.window_rule({
  name = "steam-ws-14",
  match = { class = "^(steam)$" },
  workspace = 14,
})

-- No catch-all rule for class helium. A rule like "all other helium → workspace 1"
-- also matched file-picker and print dialogs (same WM_CLASS, generic titles), so they
-- jumped to workspace 1. Generic browser windows stay on the workspace where they open.

-- Background Helium (homepage on ws 1, notifications, restarts) must not activate-focus
-- the compositor while you work on another workspace. Click-to-focus still works.
hl.window_rule({
  name = "helium-no-focus-steal",
  match = { class = "^(helium)$" },
  focus_on_activate = false,
  suppress_event = "activate activatefocus",
})
