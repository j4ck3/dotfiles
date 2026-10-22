-- ASUS PG32UCWM on the RX 7900 XTX. The EDID preferred mode is only 60 Hz,
-- so select the advertised native 4K 240 Hz mode explicitly.
-- Scale 1.5 preserves 4K output and provides a 2560x1440 logical desktop.
hl.env("GDK_SCALE", "1")

-- Keep XWayland pixels sharp; Steam handles its own readable 200% UI scale.
hl.config({ xwayland = { force_zero_scaling = true } })
hl.env("STEAM_FORCE_DESKTOPUI_SCALING", "2")

hl.monitor({
  output = "desc:ASUSTek COMPUTER INC PG32UCWM",
  mode = "3840x2160@240.02",
  position = "0x0",
  scale = 1.5,
  bitdepth = 8,
  cm = "srgb",
  vrr = 0,
})

-- Use this display profile after a connector change. Other displays retain
-- their preferred mode and automatic positioning instead of old LG modes.
hl.monitor({
  output = "",
  mode = "preferred",
  position = "auto",
  scale = 1,
})
