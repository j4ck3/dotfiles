-- Application bindings
-- See https://wiki.hypr.land/Configuring/Basics/Binds/

local terminal = "uwsm-app -- xdg-terminal-exec"
local browser = "helium-browser"
local scripts = os.getenv("HOME") .. "/.config/hypr/scripts"

local function bind(keys, dispatcher, opts)
  hl.bind(keys, dispatcher, opts)
end

local function desc(text)
  return { description = text }
end

local function desc_release(text)
  return { description = text }
end

local function desc_release_inhibit(text)
  return { description = text, dont_inhibit = true }
end

local function desc_locked(text)
  return { description = text, locked = true }
end

local function desc_locked_repeat(text)
  return { description = text, locked = true, repeating = true }
end

-- Voyager layer keys act as modifiers — ignore_mods so layer-2 media keys still fire.
local function desc_media(text)
  return { description = text, ignore_mods = true, locked = true }
end

local function desc_media_repeat(text)
  return { description = text, ignore_mods = true, locked = true, repeating = true }
end

-- Detach from group if needed, then move active window (stay on current workspace).
local function move_active_to_workspace(ws)
  return function()
    local win = hl.get_active_window()
    if not win then
      return
    end
    if win.group then
      hl.dispatch(hl.dsp.window.move({ out_of_group = true, window = win }))
    end
    hl.dispatch(hl.dsp.window.move({ workspace = ws, follow = false, window = win }))
  end
end

-- Apps
bind("SUPER + RETURN", hl.dsp.exec_cmd(scripts .. "/launch-terminal-16-9"), desc_release("Terminal"))
bind("SUPER + BackSpace", hl.dsp.exec_cmd("uwsm-app -- /home/jacke/.local/bin/dolphin"), desc_release("File manager"))
bind("SUPER + SHIFT + ALT + B", hl.dsp.exec_cmd(browser .. " --private"), desc_release("Browser (private)"))
bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("uwsm-app -- flatpak run com.spotify.Client"), desc_release("Music"))
bind("SUPER + M", hl.dsp.exec_cmd(scripts .. "/spotify-workspace 15"), desc_release("Spotify (workspace 15)"))
bind("SUPER + K", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 2"), desc_release("Switch/cycle workspace 2"))
bind("SUPER + SHIFT + N", hl.dsp.exec_cmd("uwsm-app -- cursor"), desc_release("Editor"))
bind(
  "SUPER + N",
  hl.dsp.exec_cmd(scripts .. "/webapp-launch 5 dev.zed.Zed uwsm-app -- zed"),
  desc_release("Zed (workspace 5)")
)
bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(terminal .. " -e lazydocker"), desc_release("Docker"))
-- Lock (Super+L is workspace 3). hyprlock — QS WlSessionLock crashed Hyprland.
bind("SUPER + CTRL + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"), desc_release("Lock screen"))

-- System sleep
bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd(scripts .. "/session-action suspend"), desc_release("Sleep/Suspend"))
bind("CTRL + ALT + SHIFT + S", hl.dsp.exec_cmd(scripts .. "/session-action suspend"), desc("Sleep/Suspend"))

-- System monitor
bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd(terminal .. " -e btop"), desc("System monitor"))

-- Stuck Ctrl/modifiers (no Ctrl in chord — use when Ctrl is stuck)
bind("SUPER + ALT + U", hl.dsp.exec_cmd(scripts .. "/kbd-unstick"), desc_release("Unstick keyboard"))
bind("Scroll_Lock", hl.dsp.exec_cmd(scripts .. "/kbd-unstick"), desc("Unstick keyboard"))

-- Games: Super+G focuses/cycles; Super+Shift+G moves games → free game ws (>=16)
bind("SUPER + G", hl.dsp.focus({ workspace = "name:g" }), desc_release("Game workspace g"))
-- dont_inhibit = bypass app keybind inhibitors (NOT ignore_mods — that eats bare G)
bind("SUPER + SHIFT + G", hl.dsp.exec_cmd(scripts .. "/game-move-active"), desc_release_inhibit("Move games to game workspace"))

-- Window management
bind("SUPER + W", hl.dsp.exec_cmd(scripts .. "/confirm-close-window"), desc_release("Close window"))
bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), desc_release("Full screen"))

-- Switch focus with SUPER + arrow keys
bind("SUPER + LEFT", hl.dsp.focus({ direction = "left" }), desc_release("Move focus left"))
bind("SUPER + RIGHT", hl.dsp.focus({ direction = "right" }), desc_release("Move focus right"))
bind("SUPER + UP", hl.dsp.focus({ direction = "up" }), desc_release("Move focus up"))
bind("SUPER + DOWN", hl.dsp.focus({ direction = "down" }), desc_release("Move focus down"))
-- Fullscreen games use keyboard inhibitors; keep 16:9 recovery bind available.
bind("SUPER + T", hl.dsp.exec_cmd(scripts .. "/toggle-group-workspace"), desc_release_inhibit("Apply 16:9 group view"))

-- Keyboard shortcuts guide (Super+? — Quickshell ShortcutsPopup)
-- Swedish: ? is Shift on the + key. US: ? is Shift+/.
bind("SUPER + SHIFT + plus", hl.dsp.exec_cmd("qs ipc call shell toggleShortcuts"), desc_release("Keyboard shortcuts (Super+?)"))
bind("SUPER + SHIFT + slash", hl.dsp.exec_cmd("qs ipc call shell toggleShortcuts"), desc_release("Keyboard shortcuts (Super+?)"))
bind("SUPER + SHIFT + question", hl.dsp.exec_cmd("qs ipc call shell toggleShortcuts"), desc_release("Keyboard shortcuts (Super+?)"))

-- App launcher + session menu + clipboard (Quickshell)
bind("SUPER + SPACE", hl.dsp.exec_cmd("qs ipc call shell toggleLauncher"), desc_release("Launch apps"))
bind("SUPER + SHIFT + SPACE", hl.dsp.exec_cmd("qs ipc call shell toggleSession"), desc_release("Session menu"))
bind("SUPER + C", hl.dsp.exec_cmd("qs ipc call shell toggleClipboard"), desc_release("Clipboard history"))

-- Screenshot bindings - using grim + slurp + satty
bind(
  "SUPER + mouse:272",
  hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'),
  { description = "Screenshot region to clipboard", mouse = true }
)
bind(
  "SHIFT + Prior",
  hl.dsp.exec_cmd(
    "grim -g \"$(slurp)\" - | satty --filename - --output-filename ~/Pictures/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png --early-exit --copy-command 'wl-copy'"
  ),
  desc("Screenshot with editing")
)
bind("Next", hl.dsp.exec_cmd("grim - | wl-copy"), desc("Screenshot full screen"))
bind("SUPER + Prior", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"), desc_release("Color picker"))

-- Voice / OCR / TTS
-- Handy: Super+V toggles record ↔ stop→transcribe (Hypr bind; Wayland has no global shortcuts).
bind(
  "SUPER + V",
  hl.dsp.exec_cmd(scripts .. "/handy-toggle"),
  desc_release("Handy dictation toggle")
)
bind(
  "Escape",
  hl.dsp.exec_cmd(scripts .. "/handy-cancel"),
  { description = "Cancel Handy dictation", non_consuming = true }
)
bind("SUPER + SHIFT + V", hl.dsp.exec_cmd(scripts .. "/ocr-region"), desc_release("OCR region to clipboard"))
bind("SUPER + ALT + V", hl.dsp.exec_cmd(scripts .. "/tts-speak"), desc_release("Text to speech (TTS)"))

-- Move windows to their corresponding pinned-app workspaces
bind("SUPER + SHIFT + K", move_active_to_workspace(2), desc_release("Move active window to workspace 2"))

-- SUPER I: Trilium (workspace 10)
bind(
  "SUPER + I",
  hl.dsp.exec_cmd(
    scripts .. "/webapp-launch 10 helium helium-webapp --new-window https://trilium.netbird.hjacke.com/"
  ),
  desc_release("Trilium (workspace 10)")
)
bind("SUPER + SHIFT + I", move_active_to_workspace(10), desc_release("Move active window to workspace 10"))

-- SUPER U: ChatGPT (workspace 11)
bind(
  "SUPER + U",
  hl.dsp.exec_cmd(scripts .. "/webapp-launch 11 helium helium-webapp --new-window https://chatgpt.com"),
  desc_release("ChatGPT (workspace 11)")
)
bind("SUPER + SHIFT + U", move_active_to_workspace(11), desc_release("Move active window to workspace 11"))

-- SUPER Y: YouTube (workspace 12)
bind(
  "SUPER + Y",
  hl.dsp.exec_cmd(scripts .. "/webapp-launch 12 helium helium-webapp --new-window https://youtube.com"),
  desc_release("YouTube (workspace 12)")
)
bind("SUPER + SHIFT + Y", move_active_to_workspace(12), desc_release("Move active window to workspace 12"))

-- SUPER H: Discord (workspace 13)
bind(
  "SUPER + H",
  hl.dsp.exec_cmd(scripts .. "/webapp-launch 13 discord uwsm-app -- flatpak run com.discordapp.Discord"),
  desc_release("Discord (workspace 13)")
)
bind("SUPER + SHIFT + H", move_active_to_workspace(13), desc_release("Move active window to workspace 13"))

-- SUPER B: Steam (workspace 14)
bind(
  "SUPER + B",
  hl.dsp.exec_cmd(scripts .. "/webapp-launch 14 steam uwsm-app -- steam"),
  desc_release("Steam (workspace 14)")
)
bind("SUPER + SHIFT + B", move_active_to_workspace(14), desc_release("Move active window to workspace 14"))

-- Switch workspaces with SUPER + [1-9] (press again to cycle windows there)
bind("SUPER + J", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 1"), desc_release("Switch/cycle workspace 1"))
bind("SUPER + L", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 3"), desc_release("Switch/cycle workspace 3"))
bind("SUPER + odiaeresis", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 4"), desc_release("Switch/cycle workspace 4"))
bind("SUPER + 5", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 5"), desc_release("Switch/cycle workspace 5"))
bind("SUPER + 6", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 6"), desc_release("Switch/cycle workspace 6"))
bind("SUPER + 7", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 7"), desc_release("Switch/cycle workspace 7"))
bind("SUPER + 8", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 8"), desc_release("Switch/cycle workspace 8"))
bind("SUPER + 9", hl.dsp.exec_cmd(scripts .. "/workspace-or-cycle 9"), desc_release("Switch/cycle workspace 9"))

-- Move active window to a workspace with SUPER + SHIFT + letter/number
-- Swedish Ö: Shift may report Odiaeresis — bind both.
bind("SUPER + SHIFT + J", move_active_to_workspace(1), desc_release("Move active window to workspace 1"))
-- SUPER + SHIFT + K: defined with workspace 2 binds above
bind("SUPER + SHIFT + L", move_active_to_workspace(3), desc_release("Move active window to workspace 3"))
bind("SUPER + SHIFT + odiaeresis", move_active_to_workspace(4), desc_release("Move active window to workspace 4"))
bind("SUPER + SHIFT + Odiaeresis", move_active_to_workspace(4), desc_release("Move active window to workspace 4"))
bind("SUPER + SHIFT + 5", move_active_to_workspace(5), desc_release("Move active window to workspace 5"))
bind("SUPER + SHIFT + 6", move_active_to_workspace(6), desc_release("Move active window to workspace 6"))
bind("SUPER + SHIFT + 7", move_active_to_workspace(7), desc_release("Move active window to workspace 7"))
bind("SUPER + SHIFT + 8", move_active_to_workspace(8), desc_release("Move active window to workspace 8"))
bind("SUPER + SHIFT + 9", move_active_to_workspace(9), desc_release("Move active window to workspace 9"))

-- ALT+TAB: group-aware cycling (tabs when grouped, windows otherwise)
bind("ALT + TAB", hl.dsp.exec_cmd(scripts .. "/smart-cycle"), desc("Cycle next (group-aware)"))
-- Shift+Tab reports ISO_Left_Tab, not TAB — bind both (hyprwm/Hyprland#266)
bind("ALT + SHIFT + TAB", hl.dsp.exec_cmd(scripts .. "/smart-cycle prev"), desc("Cycle prev (group-aware)"))
bind("ALT + SHIFT + ISO_Left_Tab", hl.dsp.exec_cmd(scripts .. "/smart-cycle prev"), desc("Cycle prev (group-aware)"))

-- Media controls (F-keys + XF86 for Voyager layer 2 / consumer HID)
bind("F7", hl.dsp.exec_cmd("playerctl --player=spotify previous"), desc_media("Spotify previous track"))
bind("F8", hl.dsp.exec_cmd("playerctl --player=spotify play-pause"), desc_media("Spotify play/pause"))
bind("F9", hl.dsp.exec_cmd("playerctl --player=spotify next"), desc_media("Spotify next track"))
bind("F11", hl.dsp.exec_cmd(scripts .. "/spotify-volume down"), desc_media_repeat("Spotify volume down"))
bind("F12", hl.dsp.exec_cmd(scripts .. "/spotify-volume up"), desc_media_repeat("Spotify volume up"))

bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl --player=spotify previous"), desc_media("Spotify previous track"))
bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl --player=spotify next"), desc_media("Spotify next track"))
bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl --player=spotify play-pause"), desc_media("Spotify play/pause"))
bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl --player=spotify play-pause"), desc_media("Spotify play/pause"))
bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl --player=spotify stop"), desc_media("Spotify stop"))
bind(
  "XF86AudioRaiseVolume",
  hl.dsp.exec_cmd("wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"),
  desc_media_repeat("Volume up")
)
bind(
  "XF86AudioLowerVolume",
  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
  desc_media_repeat("Volume down")
)
bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), desc_media("Mute toggle"))
bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), desc_media("Mic mute toggle"))

-- Display steering (Quickshell DisplayPopup sliders via qs ipc target "display")
-- F1/F2 brightness ±5%, F3/F4 blue-light filter: down = cooler, up = warmer.
bind("F1", hl.dsp.exec_cmd("qs ipc call display brightnessUp"), desc_media("Brightness up"))
bind("F2", hl.dsp.exec_cmd("qs ipc call display brightnessDown"), desc_media("Brightness down"))
bind("F3", hl.dsp.exec_cmd("qs ipc call display filterDown"), desc_media("Blue-light filter down"))
bind("F4", hl.dsp.exec_cmd("qs ipc call display filterUp"), desc_media("Blue-light filter up"))

-- Open project in tmux with nvim and opencode
bind("SUPER + SHIFT + O", hl.dsp.exec_cmd(scripts .. "/open-project-tmux"), desc_release("Open project (tmux+nvim+opencode)"))
