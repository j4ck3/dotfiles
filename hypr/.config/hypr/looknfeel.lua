-- Look and feel configuration
-- See https://wiki.hypr.land/Configuring/Basics/Variables/

local activeBorderColor = { colors = { "rgba(33ccffee)", "rgba(00ff99ee)" }, angle = 45 }
local inactiveBorderColor = "rgba(595959aa)"

hl.config({
  general = {
    gaps_in = 2,
    gaps_out = 4,
    border_size = 0,
    col = {
      active_border = activeBorderColor,
      inactive_border = inactiveBorderColor,
    },
    resize_on_border = false,
    -- Master switch; only windows with windowrule `immediate` actually tear (games-perf).
    allow_tearing = true,
    layout = "dwindle",
  },

  decoration = {
    rounding = 8,
    shadow = {
      -- Hyprland 0.56.1 can crash in CHyprDropShadowDecoration::updateWindow
      -- while destroying grouped windows (confirmed by coredump).
      enabled = false,
      range = 2,
      render_power = 3,
      color = "rgba(1a1a1aee)",
    },
    blur = {
      -- Blur at 3440x1440@240 on RX 7900 can flicker with Aquamarine atomic commits; re-enable
      -- after send_content_type/AQ_NO_ATOMIC fixes if you want the look back.
      enabled = false,
      size = 3,
      passes = 1,
    },
  },

  group = {
    col = {
      border_active = activeBorderColor,
      border_inactive = inactiveBorderColor,
      border_locked_active = activeBorderColor,
      border_locked_inactive = inactiveBorderColor,
    },
    groupbar = {
      enabled = false,
    },
  },

  animations = {
    enabled = false,
  },

  dwindle = {
    preserve_split = true,
    force_split = 2,
    -- single_window_aspect_ratio = { 1, 1 },
  },

  master = {
    new_status = "master",
  },

  -- Keep scanout path conservative while stabilizing Hyprland 0.56.x.
  -- send_content_type stays off — reporting every frame renegotiated DP / flickered LG @240.
  -- If scanout brings flicker back, set direct_scanout = 0.
  render = {
    direct_scanout = 0,
    send_content_type = false,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    focus_on_activate = false,
    anr_missed_pings = 3,
    vrr = 0, -- VRR/FreeSync off — vrr=1 flickered the desktop; vrr=2 still flickered on 240 Hz panel
    background_color = 0xff1e1e2e,
  },

  -- Logs off for FPS. Re-enable when debugging session-lock / crashes:
  --   hyprctl keyword debug:disable_logs false
  -- Read log:
  --   cat $XDG_RUNTIME_DIR/hypr/$(ls -t $XDG_RUNTIME_DIR/hypr/ | head -n 1)/hyprland.log
  debug = {
    disable_logs = true,
  },

  cursor = {
    -- Never auto-hide (idle / keys / touch).
    hide_on_key_press = false,
    hide_on_touch = false,
    hide_on_tablet = false,
    inactive_timeout = 0,
    -- AMDGPU @ high refresh: HW cursor plane often stops drawing until the pointer moves.
    no_hardware_cursors = 1,
  },
})

-- Curves kept even with animations disabled (ready if re-enabled).
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = false })

-- Style Gum confirm to match terminal theme
hl.env("GUM_CONFIRM_PROMPT_FOREGROUND", "6")
hl.env("GUM_CONFIRM_SELECTED_FOREGROUND", "0")
hl.env("GUM_CONFIRM_SELECTED_BACKGROUND", "2")
hl.env("GUM_CONFIRM_UNSELECTED_FOREGROUND", "0")
hl.env("GUM_CONFIRM_UNSELECTED_BACKGROUND", "8")

-- Layer rules
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true })
hl.layer_rule({ match = { namespace = "qs-launcher" }, no_anim = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "qs-clipboard" }, no_anim = true, ignore_alpha = 0.2 })
-- Quickshell bar: solid dark strip — no blur (cheaper on ultrawide).
hl.layer_rule({ match = { namespace = "quickshell-bar" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "qs-volume" }, ignore_alpha = 0.2, no_anim = true })
hl.layer_rule({ match = { namespace = "qs-power" }, no_anim = true })
hl.layer_rule({ match = { namespace = "qs-media" }, no_anim = true })
hl.layer_rule({ match = { namespace = "qs-shortcuts" }, ignore_alpha = 0, no_anim = true })
hl.layer_rule({ match = { namespace = "qs-notifications" }, no_anim = true, ignore_alpha = 0.2 })

-- Confirmation dialog for SUPER+W
hl.window_rule({
  name = "close-window-confirmation",
  match = { title = "^Close window\\?$" },
  float = true,
  center = true,
  pin = true,
})

-- Workspace 2: Monocle mode - windows maximized and stacked (handled by workspace2-monocle script)
-- Uses normal gaps/borders like other workspaces
