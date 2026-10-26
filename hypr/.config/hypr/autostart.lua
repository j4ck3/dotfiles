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
  -- S1-mini (Superwhisper): local STT normalizer for Handy post-process
  hl.exec_cmd("systemctl --user start s1-mini.service s1-mini-proxy.service")
  -- Handy: background app for Super+V toggle (--toggle-post-process via Hypr bind).
  hl.exec_cmd("uwsm-app -- " .. scripts .. "/handy-start")
  hl.exec_cmd("enable-keyboard-wake")
  hl.exec_cmd(scripts .. "/kbd-unstick")

  -- Spotify resets sink-input volume on new tracks; user service survives hyprctl reload (exec-once does not)
  hl.exec_cmd("systemctl --user start spotify-volume-guard.service")
  -- Easy Effects (hidden service) + "CS2 Footsteps" EQ preset (IE 200 correction + footstep tune)
  hl.exec_cmd(scripts .. "/start-easyeffects")
  -- Outlook OTP watcher (PowerMenu arm → Graph poll → bar chip)
  hl.exec_cmd("systemctl --user start qs-otp-watchd.service")
  -- NetBird: `netbird down` persists Idle; --disable-dns keeps mgmt URL off mesh DNS
  hl.exec_cmd("netbird up --management-url https://netbird.hjacke.com:443 --disable-dns || true")

  -- Workspace 2 monocle mode - maximize and stack all windows
  hl.exec_cmd(scripts .. "/workspace2-monocle")

  -- Games (steam_app_*/cs2/gamescope) → free workspace >= 16; Super+G focuses them
  hl.exec_cmd(scripts .. "/game-snap-listener-watchdog")
end)

-- Normal app windows open floating in a group before their first frame.
-- Initially-floating windows are dialogs/popups and keep their requested geometry.
-- Fill the usable area (monitor minus the vertical bar) with equal margins on
-- every side. Must match `margin` in scripts/16-9-lib.sh. Do not force 16:9:
-- on a 16:9 monitor the bar makes the usable area narrower than 16:9, so a
-- forced ratio overflows and the margins become uneven.
local bar_width = 56 -- quickshell Theme.barWidth
local margin = 5 -- keep in sync with scripts/16-9-lib.sh
hl.window_rule({
  name = "default-16-9",
  match = {
    class = ".*",
    float = false,
  },
  float = true,
  size = {
    string.format("monitor_w - %d", bar_width + margin * 2),
    string.format("monitor_h - %d", margin * 2),
  },
  move = {
    tostring(bar_width + margin),
    tostring(margin),
  },
  group = "set",
  no_anim = true,
})

-- T3 Code → Workspace 2 (must match bindings.lua + webapp-launch)
hl.window_rule({
  name = "t3code-ws-2",
  match = { class = "^(t3code)$" },
  workspace = 2,
})

-- Zed → Workspace 5 (must match bindings.lua + webapp-launch)
hl.window_rule({
  name = "zed-ws-5",
  match = { class = "^(dev.zed.Zed)$" },
  workspace = 5,
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
