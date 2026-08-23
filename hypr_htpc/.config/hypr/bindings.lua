local var_terminal = "ghostty"

-- Application bindings

-- Quickshell application launcher - SUPER+Space
hl.bind("SUPER + SPACE", hl.dsp.exec_cmd("qs ipc call shell toggleLauncher"))

-- Terminal
hl.bind("SUPER + RETURN", hl.dsp.exec_cmd(var_terminal))
hl.bind("SUPER + BackSpace", hl.dsp.exec_cmd("nautilus --new-window"))
hl.bind("SUPER + SHIFT + D", hl.dsp.exec_cmd(var_terminal .. " -e lazydocker"))

-- System
hl.bind("SUPER + CTRL + SHIFT + S", hl.dsp.exec_cmd("/usr/bin/systemctl suspend"))
hl.unbind("CTRL + ALT + DELETE")
hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd(var_terminal .. " -e btop"))

-- Screenshot/Color picker
hl.bind("SUPER + CTRL + S", hl.dsp.exec_cmd("pkill hyprpicker || hyprpicker -a"))

-- Close window
hl.bind("SUPER + W", hl.dsp.window.close())

-- Switch workspaces SUPER + J/K/L/Ö (Swedish, current monitor only)
hl.unbind("SUPER + J")
hl.unbind("SUPER + K")
hl.bind("SUPER + J", hl.dsp.focus({ workspace = 1, on_current_monitor = true }))
hl.bind("SUPER + K", hl.dsp.focus({ workspace = 2, on_current_monitor = true }))
hl.bind("SUPER + L", hl.dsp.focus({ workspace = 3, on_current_monitor = true }))
hl.bind("SUPER + odiaeresis", hl.dsp.focus({ workspace = 4, on_current_monitor = true }))
hl.bind("SUPER + code:14", hl.dsp.focus({ workspace = 5, on_current_monitor = true }))
hl.bind("SUPER + code:15", hl.dsp.focus({ workspace = 6, on_current_monitor = true }))
hl.bind("SUPER + code:16", hl.dsp.focus({ workspace = 7, on_current_monitor = true }))
hl.bind("SUPER + code:17", hl.dsp.focus({ workspace = 8, on_current_monitor = true }))
hl.bind("SUPER + code:18", hl.dsp.focus({ workspace = 9, on_current_monitor = true }))

-- Move window SUPER+SHIFT + J/K/L/Ö
hl.bind("SUPER + SHIFT + J", hl.dsp.window.move({ workspace = 1 }))
hl.bind("SUPER + SHIFT + K", hl.dsp.window.move({ workspace = 2 }))
hl.bind("SUPER + SHIFT + L", hl.dsp.window.move({ workspace = 3 }))
hl.bind("SUPER + SHIFT + odiaeresis", hl.dsp.window.move({ workspace = 4 }))
hl.bind("SUPER + SHIFT + code:14", hl.dsp.window.move({ workspace = 5 }))
hl.bind("SUPER + SHIFT + code:15", hl.dsp.window.move({ workspace = 6 }))
hl.bind("SUPER + SHIFT + code:16", hl.dsp.window.move({ workspace = 7 }))
hl.bind("SUPER + SHIFT + code:17", hl.dsp.window.move({ workspace = 8 }))
hl.bind("SUPER + SHIFT + code:18", hl.dsp.window.move({ workspace = 9 }))

-- Move focus
hl.bind("SUPER + left", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + right", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + up", hl.dsp.focus({ direction = "up" }))
hl.bind("SUPER + down", hl.dsp.focus({ direction = "down" }))

-- ALT+TAB
hl.unbind("ALT + TAB")
hl.unbind("ALT + SHIFT + TAB")
hl.bind("ALT + TAB", hl.dsp.window.cycle_next())
hl.bind("ALT + SHIFT + TAB", hl.dsp.window.cycle_next())

-- Exit
hl.bind("SUPER + SHIFT + E", hl.dsp.exit())

-- YouTube kiosk mode (flags from ~/.config/helium-browser-flags.conf)
hl.bind("SUPER + A", hl.dsp.exec_cmd("helium-browser --start-fullscreen https://youtube.com"))

-- YouTube TV (spoofed user agent)
hl.bind("SUPER + Q", hl.dsp.exec_cmd("helium-browser --start-fullscreen --user-data-dir=$HOME/.config/helium-tv --user-agent=\"Mozilla/5.0 (SMART-TV; Linux; Tizen 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Version/5.0 TV Safari/537.36\" https://youtube.com/tv"))

-- Fullscreen
hl.bind("SUPER + F", hl.dsp.window.fullscreen())

-- Display mode: 4K60 desktop ↔ 4K24 movie (GTX 1060 + LG C4)
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("hypr-display-mode toggle"))
