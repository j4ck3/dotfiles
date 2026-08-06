-- Control your input devices
-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
  input = {
    -- Use multiple keyboard layouts and switch between them with Left Alt + Right Alt
    -- kb_layout = "us,dk,eu",
    kb_layout = "se",
    kb_options = "caps:escape", -- Caps Lock sends Escape

    -- Change speed of keyboard repeat
    repeat_rate = 40,
    repeat_delay = 600,

    -- Start with numlock on by default
    numlock_by_default = true,

    -- DPI 800→1600: flat factor = 1+sensitivity → -0.5 = 0.5x = same physical speed
    -- (adaptive sensitivity only tweaks accel curve, not base 1:1 speed)
    accel_profile = "flat",
    sensitivity = -0.5,

    touchpad = {
      -- natural_scroll = true,
      -- clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})

-- Phantom HID keyboards (consumer/system control) can leave Ctrl/Shift stuck after USB glitches.

-- Razer mouse dongle
hl.device({ name = "razer-razer-viper-ultimate-dongle-keyboard", enabled = false })
hl.device({ name = "razer-razer-viper-ultimate-dongle-1", enabled = false })
hl.device({ name = "razer-razer-viper-ultimate-keyboard", enabled = false })
hl.device({ name = "razer-razer-viper-ultimate", enabled = false })

-- Keychron Q1 (keep keychron-keychron-q1-keyboard)
hl.device({ name = "keychron-keychron-q1-consumer-control", enabled = false })
hl.device({ name = "keychron-keychron-q1-system-control", enabled = false })
hl.device({ name = "keychron-keychron-q1", enabled = false })

-- ZSA Voyager (keep zsa-technology-labs-voyager-keyboard)
hl.device({ name = "zsa-technology-labs-voyager", enabled = false })
hl.device({ name = "zsa-technology-labs-voyager-system-control", enabled = false })
hl.device({ name = "zsa-technology-labs-voyager-consumer-control", enabled = false })
