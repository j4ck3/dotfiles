-- LG OLED65C44LA (65" C4) + GTX 1060 6GB (HDMI 2.0b)
-- Default: 1440p @ 120 Hz SDR. Fullscreen HDR content switches automatically.
-- Luminance tuning lives in hyprland-gui.lua (HyprMod, Lua-only fields).

hl.monitor({
    output = "desc:LG Electronics LG TV SSCR2",
    mode = "2560x1440@120",
    position = "0x0",
    scale = 1,
    bitdepth = 10,
    cm = "srgb",
})

hl.monitor({
    output = "DVI-D-1",
    disabled = true,
})

hl.config({
    render = {
        cm_auto_hdr = 1,
    },
})
