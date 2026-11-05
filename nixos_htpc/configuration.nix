# NixOS HTPC "tv": mirrors the CachyOS HTPC VM (Hyprland + Quickshell on a
# GTX 1060 passed through from tower, LG C4 OLED over HDMI).
# User-level config (~/.config/hypr, quickshell, systemd user units, ...) is
# carried over from the CachyOS home as-is; this file supplies the system part.
{ config, lib, pkgs, helium, ... }:

let
  # Helium from the oxcl flake. Its wrapper pins FONTCONFIG_FILE to a CJK-only
  # fonts.conf (hides system and ~/.local/share fonts) and passes the
  # NIXOS_OZONE_WL expression through unexpanded; drop both lines.
  heliumPkg = (helium.packages.${pkgs.stdenv.hostPlatform.system}.helium).overrideAttrs (old: {
    preFixup = lib.concatStringsSep "\n"
      (lib.filter (l: !(lib.hasInfix "FONTCONFIG_FILE" l || lib.hasInfix "NIXOS_OZONE_WL" l))
        (lib.splitString "\n" old.preFixup));
  });

  # The AUR helium-browser-bin wrapper reads /etc and ~/.config/helium-browser-flags.conf;
  # the upstream .deb wrapper does not, so do it here under the Arch command name.
  heliumBrowser = pkgs.writeShellScriptBin "helium-browser" ''
    flags=()
    for conf in /etc/helium-browser-flags.conf "''${XDG_CONFIG_HOME:-$HOME/.config}/helium-browser-flags.conf"; do
      [ -r "$conf" ] || continue
      while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        read -ra parts <<< "$line"
        flags+=("''${parts[@]}")
      done < "$conf"
    done
    exec ${heliumPkg}/bin/helium "''${flags[@]}" "$@"
  '';

  # Arch's spotify-launcher reads ~/.config/spotify-flags.conf; nixpkgs' spotify does not.
  spotifyLauncher = pkgs.writeShellScriptBin "spotify" ''
    flags=()
    conf="''${XDG_CONFIG_HOME:-$HOME/.config}/spotify-flags.conf"
    if [ -r "$conf" ]; then
      while IFS= read -r line; do
        case "$line" in ""|"#"*) continue ;; esac
        flags+=($line)
      done < "$conf"
    fi
    exec ${pkgs.spotify}/bin/spotify "''${flags[@]}" "$@"
  '';
  spotifyWithFlags = pkgs.symlinkJoin {
    name = "spotify-with-flags";
    paths = [ (lib.hiPrio spotifyLauncher) pkgs.spotify ];
  };

  # Paths that the carried-over scripts, units and configs hard-code.
  fhsLinks = {
    "/usr/bin/helium-browser" = "${heliumBrowser}/bin/helium-browser";
    "/usr/bin/python3" = "${pkgs.python3}/bin/python3";
    "/usr/bin/python" = "${pkgs.python3}/bin/python3";
    "/usr/bin/systemctl" = "${pkgs.systemd}/bin/systemctl";
    "/usr/bin/npx" = "${pkgs.nodejs}/bin/npx";
    "/usr/bin/node" = "${pkgs.nodejs}/bin/node";
    "/usr/bin/npm" = "${pkgs.nodejs}/bin/npm";
    "/usr/bin/wayvnc" = "${pkgs.wayvnc}/bin/wayvnc";
    "/usr/bin/dolphin" = "${pkgs.kdePackages.dolphin}/bin/dolphin";
    "/bin/bash" = "${pkgs.bashInteractive}/bin/bash";
  };
in
{
  imports = lib.optional (builtins.pathExists ./secrets.nix) ./secrets.nix;

  system.stateVersion = "26.11";

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "tv" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Weekly unattended update, same slot as the CachyOS topgrade timer (Sun 06:00).
  system.autoUpgrade = {
    enable = true;
    flake = "/etc/nixos#nixos-tv";
    flags = [ "--recreate-lock-file" "-L" ]; # refresh nixpkgs + helium each run
    dates = "Sun *-*-* 05:30:00";
    randomizedDelaySec = "5min";
    allowReboot = false;
  };

  # ---------------------------------------------------------------- boot/kernel
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.kernelParams = [ "quiet" "splash" "nowatchdog" "nvidia_drm.modeset=1" "nvidia_drm.fbdev=1" ];
  boot.consoleLogLevel = 3;
  boot.plymouth.enable = true;
  boot.kernel.sysctl = {
    # cachyos-settings defaults that matter on a 6 GB zram box
    "vm.swappiness" = 100;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_bytes" = 268435456;
    "vm.dirty_background_bytes" = 67108864;
    "vm.page-cluster" = 0;
    "kernel.nmi_watchdog" = 0;
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
  };

  # ---------------------------------------------------------------- graphics
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = [ pkgs.nvidia-vaapi-driver ];
  };
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    open = false; # Pascal (GP106) needs the proprietary kernel module
    modesetting.enable = true;
    nvidiaSettings = true;
    powerManagement.enable = false;
  };

  # ---------------------------------------------------------------- locale
  time.timeZone = "Europe/Stockholm";
  i18n.defaultLocale = "sv_SE.UTF-8";
  i18n.supportedLocales = [ "sv_SE.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];
  console.keyMap = "sv-latin1";
  services.xserver.xkb = { layout = "se"; options = "caps:escape"; };

  # ---------------------------------------------------------------- network
  networking.hostName = "nixos-tv";
  networking.networkmanager.enable = true;
  services.resolved.enable = true;
  services.timesyncd.enable = true;
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    settings.publish = { publish-addresses = true; publish-workstation = true; };
  };
  services.netbird.enable = true;
  services.openssh.enable = true;

  # Same rules as ufw on CachyOS: ssh, Sunshine/Moonlight, wayvnc.
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 47984 47989 47990 48010 5900 ];
    allowedUDPPorts = [ 47998 47999 48000 48002 48010 ];
    trustedInterfaces = [ "wt0" ];
  };

  # ---------------------------------------------------------------- services
  services.qemuGuest.enable = true;
  services.dbus.implementation = "broker";
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  security.rtkit.enable = true;
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
  services.udisks2.enable = true;
  services.gvfs.enable = true;
  services.flatpak.enable = true;
  services.locate = { enable = true; package = pkgs.plocate; };
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;
  };
  systemd.oomd.enable = true;

  services.sunshine = {
    enable = true;
    autoStart = false; # disabled on CachyOS too (conflicts with wayvnc KMS capture)
    capSysAdmin = true;
    openFirewall = true;
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = false; # installed but not running on CachyOS
  };

  # NuPhy Air60 V2 dongle: drop the HID base interface so keybinds hit the keyboard one.
  services.udev.extraRules = ''
    SUBSYSTEM=="hid", DEVPATH=="*:1.0/*19F5*3247*", ACTION=="add", RUN+="/bin/sh -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind'"
  '';

  # Flathub + Stremio, the only Flatpak on the CachyOS box.
  systemd.services.flatpak-apps = {
    description = "Install Flatpak apps carried over from CachyOS";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.flatpak ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak install --system --noninteractive --or-update flathub com.stremio.Stremio || true
    '';
  };

  # ---------------------------------------------------------------- session
  # tty1 autologin, then ~/.bash_profile runs `exec start-hyprland` (no display manager).
  services.getty.autologinUser = "tv";

  programs.hyprland = {
    enable = true;
    withUWSM = false; # started directly with start-hyprland, as on CachyOS
    xwayland.enable = true;
  };
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
  };
  programs.dconf.enable = true;
  security.polkit.enable = true;

  # Light Adwaita everywhere; ~/.config/environment.d/99-theme.conf sets the Qt vars.
  qt.enable = false;
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
      noto-fonts-color-emoji
      dejavu_fonts
      liberation_ttf
      vista-fonts
      cantarell-fonts
      open-sans
      adwaita-fonts
      font-awesome
      corefonts
      nerd-fonts.meslo-lg
      nerd-fonts.symbols-only
      nerd-fonts.fantasque-sans-mono
      bakoma_ttf
      ttf-bitstream-vera
    ];
  };

  # Binaries downloaded into $HOME (cursor-agent, pi, uv-managed Python, cargo topgrade).
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib zlib zstd openssl curl glib libGL libpulseaudio alsa-lib
      dbus expat libxkbcommon nss nspr icu libuuid libffi util-linux systemd
    ];
  };

  systemd.tmpfiles.rules = lib.mapAttrsToList (path: target: "L+ ${path} - - - - ${target}") fhsLinks;

  # ---------------------------------------------------------------- users
  users.users.tv = {
    isNormalUser = true;
    uid = 1000;
    description = "tv";
    shell = pkgs.bashInteractive;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" "render" "lp" "storage" "users" ];
    openssh.authorizedKeys.keyFiles = [ ./authorized_keys ];
  };
  users.groups.tv.gid = 1000;
  users.users.tv.group = "tv";

  security.sudo.wheelNeedsPassword = true;
  # Mirrors the pacman/yay NOPASSWD rule used by unattended updates.
  security.sudo.extraRules = [{
    users = [ "tv" ];
    commands = [
      { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
      { command = "/run/current-system/sw/bin/nix-collect-garbage"; options = [ "NOPASSWD" ]; }
    ];
  }];

  programs.bash.completion.enable = true;
  programs.fish.enable = true;
  programs.git.enable = true;
  programs.neovim.enable = true;
  programs.tmux.enable = true;
  environment.variables.EDITOR = "micro";

  # ---------------------------------------------------------------- packages
  environment.systemPackages = with pkgs; [
    # desktop
    quickshell hyprsunset hypridle hyprlock hyprpicker swaybg uwsm hyprmod
    ghostty
    heliumPkg heliumBrowser spotifyWithFlags code-cursor t3code
    kdePackages.dolphin nautilus kdePackages.polkit-kde-agent-1
    pavucontrol playerctl wireplumber pulseaudio brightnessctl libnotify
    grim slurp satty wl-clipboard wayvnc yad overskride sunsetr
    mpv vlc ffmpeg ffmpegthumbnailer
    gst_all_1.gst-libav gst_all_1.gst-plugins-bad gst_all_1.gst-plugins-ugly gst_all_1.gst-plugins-good
    adwaita-icon-theme gnome-themes-extra gsettings-desktop-schemas
    # cli
    btop fastfetch duf ncdu glances lazydocker lazygit yazi micro nano vim
    ripgrep fd jq rsync wget curl unzip unrar p7zip socat pv tree file lsof
    git stow topgrade meld tmux
    nodejs bun uv python3 cmake gcc gnumake
    tesseract
    # system
    pciutils usbutils lshw hwinfo dmidecode smartmontools hdparm ethtool
    efibootmgr btrfs-progs e2fsprogs exfatprogs dosfstools ntfs3g
    mesa-demos libva-utils vulkan-tools nvtopPackages.nvidia
    bind inetutils netbird
  ];
}
