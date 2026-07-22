# dotfiles

Hyprland desktop

Hyprland desktop alternate view

Personal configs for **CachyOS** (Arch-based).

**Dark mode:** `theme` stow package + Hypr `envs.conf` — see [`theme/README.md`](theme/README.md).

**Notifications:** Quickshell (`NotificationOSD`) — replaces Dunst. Test: `notify-send "Hi" "body"`.

**Desktop:** Hyprland, Quickshell (bar + launcher/clipboard/notifications/volume/media/power/shortcuts), UWSM, Helium Browser. Optional **hypr_htpc** profile still uses Waybar. Helium optional flags and notes on omnibox vs page fonts live in `[hypr/.config/helium-browser-flags.conf](hypr/.config/helium-browser-flags.conf)`.

**Shell & prompt:** Bash, Starship.

**Editors & coding:** Lazyvim, Zed (LazyVim-style keymaps), Cursor, t3code, Ghostty.

**Network / infra:** Docker, Netbird.

**Windows:** `winget-packages.txt` + `system/windows/install-apps.ps1` for bulk winget installs on a native Windows setup or VM.

## Hyprland keybinds

Source of truth: `[hypr/.config/hypr/bindings.conf](hypr/.config/hypr/bindings.conf)`. Below matches the descriptions in that file. Workspace keys use `odiaeresis` (ö on a Swedish layout) and `code:14`–`code:18` for 5–9; those map to physical keys depending on your layout.

### Applications and system


| Shortcut           | Action                                  |
| ------------------ | --------------------------------------- |
| Super+Enter        | Terminal (`xdg-terminal-exec` via uwsm) |
| Super+Backspace    | File manager (Nautilus)                 |
| Super+Shift+Alt+B  | Browser private window (Helium)         |
| Super+Shift+M      | Spotify                                 |
| Super+M            | Spotify, workspace 15                   |
| Super+K            | t3code workspace script                 |
| Super+N            | SSH devbox (Ghostty)                    |
| Super+Shift+N      | Cursor                                  |
| Super+Shift+D      | Lazydocker in terminal                  |
| Super+Ctrl+Shift+S | Suspend                                 |
| Ctrl+Alt+Shift+S   | Suspend                                 |
| Ctrl+Alt+Delete    | System monitor (btop)                   |
| Super+Shift+G      | GParted (sudo in terminal)              |


### Windows and launcher


| Shortcut      | Action                             |
| ------------- | ---------------------------------- |
| Super+W       | Close window (with confirm script) |
| Super+F       | Fullscreen                         |
| Super+←/→/↑/↓ | Move focus                         |
| Super+T       | Toggle 16:9 group stack            |
| Super+Space   | Quickshell app launcher            |
| Super+C       | Quickshell clipboard history       |


### Screenshots and color


| Shortcut                       | Action                                                       |
| ------------------------------ | ------------------------------------------------------------ |
| Super+left click (`mouse:272`) | Region screenshot → clipboard (`grim` + `slurp` + `wl-copy`) |
| Shift+Page Up                  | Region screenshot → Satty edit, then copy                    |
| Page Down                      | Full screen → clipboard                                      |
| Super+Page Up                  | Color picker (`hyprpicker`)                                  |


### Voice and OCR


| Shortcut      | Action                                                 |
| ------------- | ------------------------------------------------------ |
| Super+V       | Live dictation — type into focused window as you speak |
| Super+Shift+V | OCR region to clipboard                                |
| Super+Alt+V   | Text to speech                                         |


### Web apps (workspace launch / move window)


| Shortcut                | Action                                 |
| ----------------------- | -------------------------------------- |
| Super+I / Super+Shift+I | Trilium (ws 10) / move window to ws 10 |
| Super+U / Super+Shift+U | ChatGPT (ws 11) / move to ws 11        |
| Super+Y / Super+Shift+Y | YouTube (ws 12) / move to ws 12        |


### Workspaces (current monitor)


| Shortcut                          | Action                             |
| --------------------------------- | ---------------------------------- |
| Super+J                           | Workspace 1                        |
| Super+L                           | Workspace 3                        |
| Super+ö (`odiaeresis`)            | Workspace 4                        |
| Super+`code:14` … `code:18`       | Workspaces 5–9                     |
| Super+Shift+J / K / L             | Move window to workspace 1 / 2 / 3 |
| Super+Shift+ö                     | Move window to workspace 4         |
| Super+Shift+`code:14` … `code:18` | Move window to workspaces 5–9      |


### Focus cycle and media


| Shortcut                               | Action                               |
| -------------------------------------- | ------------------------------------ |
| Alt+Tab                                | Cycle next (group-aware)             |
| Alt+Shift+Tab / Alt+Shift+ISO_Left_Tab | Cycle previous                       |
| F7 / F8 / F9                           | Spotify previous / play-pause / next |
| F11 / F12                              | Spotify volume down / up             |


### Other


| Shortcut      | Action                                        |
| ------------- | --------------------------------------------- |
| Super+Shift+O | Open project in tmux (nvim + opencode script) |
