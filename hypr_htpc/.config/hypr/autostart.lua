local home = os.getenv("HOME")
local scripts = home .. "/.config/hypr/scripts"

hl.on("hyprland.start", function()
  hl.exec_cmd("swaybg -i " .. home .. "/Pictures/wallpaper.jpg -m fill")
  hl.exec_cmd(scripts .. "/quickshell-start")
  -- Gamma / blue-light via IPC (QS brightness slider). Prefer this over screen shaders.
  hl.exec_cmd("hyprsunset")

  -- Sunshine KMS capture conflicts with wayvnc on this HTPC.
  -- hl.exec_cmd("sleep 8 && systemctl --user restart sunshine.service")
end)
