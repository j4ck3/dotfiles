-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List: hyprctl monitors all

-- Safe defaults for the current AMD desktop (primary on DP-2; DP-1 is often empty).
hl.env("GDK_SCALE", "1")

-- LG 3440x1440: EDID advertises two different "preferred" 3440x1440 modes (~100 Hz and ~240 Hz).
-- Lock the exact peak mode so Hyprland never picks the wrong one.
-- (Kernel can still be verified with: modetest -M amdgpu -c | sed -n '/^DP-2/,/^[^ ]/p')
--
-- SDR 8-bit (no cm, hdr, or bitdepth 10): best text anti-aliasing in Helium/Electron.
-- HDR tonemapping made the desktop look brighter but crushed font edges; 10-bit also
-- correlates with Chromium glitches in this repo (see commit 77eb64a).
-- If the panel feels dim: raise brightness in the LG OSD and turn off the monitor's
-- "HDR" picture mode while the compositor stays in SDR.
-- Also disable FreeSync/Adaptive-Sync in the LG OSD when misc:vrr=0 (OSD VRR still flickers).
hl.monitor({
  output = "DP-2",
  mode = "3440x1440@240.09",
  position = "auto",
  scale = 1,
  vrr = 0,
})
-- Keep DP-1 rule in case the panel moves connectors after a cable swap.
hl.monitor({
  output = "DP-1",
  mode = "3440x1440@240.09",
  position = "auto",
  scale = 1,
  vrr = 0,
})

-- HDMI disabled — same panel may appear on HDMI when both cables are attached.
hl.monitor({ output = "HDMI-A-1", disabled = true })
hl.monitor({ output = "HDMI-A-2", disabled = true })
hl.monitor({ output = "HDMI-A-3", disabled = true })

-- Fallback for any other connector you plug in later.
hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = 1,
})

-- Optional: mild compositor HDR if SDR + OSD brightness is not enough (test text after enabling).
-- hl.monitor({
--   output = "DP-1",
--   mode = "3440x1440@240.09",
--   position = "auto",
--   scale = 1,
--   cm = "hdr",
--   sdrbrightness = 1.35,
--   sdrsaturation = 1.05,
-- })
