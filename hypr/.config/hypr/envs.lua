-- Extra env variables
-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

local home = os.getenv("HOME")

-- Wrapper in ~/.local/bin must win over /usr/bin/helium-browser (Walker, Elephant, .desktop).
hl.env("PATH", home .. "/.local/bin:/usr/local/bin:/usr/bin:/bin")

-- AMD / Hyprland stability defaults.
hl.env("__GL_VRR_ALLOWED", "0")
-- Aquamarine can attach connector/content_type state to every atomic page-flip;
-- sensitive panels (incl. LG ultrawide @240 Hz) then flicker or blank briefly.
-- Hyprland wiki: prefer render:send_content_type=0 first; use this if flicker remains.
hl.env("AQ_NO_ATOMIC", "1")
-- Leave HDR-related flags off until the basic display path is stable.

-- Force Aquamarine to composite on the RX 7900 (the GPU DP-1 is attached to),
-- with the Intel iGPU as a fallback only when its udev symlink exists. Without
-- this Hyprland was rendering on the Intel iGPU and bouncing buffers to AMD for
-- scanout, capping the debug overlay at ~50 FPS on the 3440x1440 panel even
-- though the mode is 240 Hz.
--
-- AQ_DRM_DEVICES splits on ':' which collides with the colons in
-- /dev/dri/by-path/pci-0000:03:00.0-card (Aquamarine issue #167), so an earlier
-- attempt that used the by-path entries here made Hyprland crash inside
-- CCompositor::initServer. Reference stable, colon-free symlinks created by
-- system/etc/udev/rules.d/70-amdgpu-symlinks.rules instead -- those map to the
-- PCI slot, so they survive cardN re-numbering across reboots.
--
-- Only list devices that exist: a missing path (e.g. intel-card when iGPU has
-- no drm card node) makes Aquamarine error "Explicit device ... not found".
local drm_devices = {}
for _, path in ipairs({ "/dev/dri/amd-card", "/dev/dri/intel-card" }) do
  local f = io.open(path, "r")
  if f then
    f:close()
    drm_devices[#drm_devices + 1] = path
  end
end
if #drm_devices > 0 then
  hl.env("AQ_DRM_DEVICES", table.concat(drm_devices, ":"))
end

-- GTK/Qt/portal; gtk-*.ini in theme stow package.
hl.env("COLOR_SCHEME", "prefer-light")
hl.env("GTK_THEME", "Adwaita")
hl.env("GTK2_RC_FILES", home .. "/.gtkrc-2.0")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("QT_STYLE_OVERRIDE", "Fusion")

-- Keyboard: always Swedish, Caps Lock = Escape. Inherited by Xwayland and
-- nested compositors (gamescope for CS2), which otherwise fall back to "us".
hl.env("XKB_DEFAULT_LAYOUT", "se")
hl.env("XKB_DEFAULT_OPTIONS", "caps:escape")
