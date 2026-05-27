export type Shortcut = { keys: string; desc: string }
export type Section = { title: string; items: Shortcut[] }
export type ShortcutTab = { id: string; label: string; sections: Section[] }

export const SHORTCUT_TABS: ShortcutTab[] = [
  {
    id: "apps",
    label: "Apps",
    sections: [
      {
        title: "Launch & open",
        items: [
          { keys: "Super Space", desc: "App launcher (Walker)" },
          { keys: "Super Return", desc: "Terminal (16:9)" },
          { keys: "Super Backspace", desc: "File manager" },
          { keys: "Super Shift N", desc: "Cursor editor" },
          { keys: "Super N", desc: "SSH devbox (Ghostty)" },
          { keys: "Super Shift D", desc: "Docker (lazydocker)" },
          { keys: "Super Shift O", desc: "Open project (tmux + nvim + opencode)" },
        ],
      },
      {
        title: "Clipboard (Super C)",
        items: [
          { keys: "Super C", desc: "Clipboard history (Walker)" },
          { keys: "j / Down", desc: "Next entry" },
          { keys: "k / Up", desc: "Previous entry" },
          { keys: "Enter / l", desc: "Copy selected entry" },
          { keys: "Ctrl D", desc: "Remove entry" },
          { keys: "Ctrl Shift D", desc: "Clear all history" },
          { keys: "Ctrl I", desc: "Toggle images only / text only / all" },
          { keys: "Ctrl Shift P", desc: "Pause / unpause recording" },
          { keys: "Ctrl P", desc: "Pin / unpin entry" },
          { keys: "Ctrl O", desc: "Edit entry" },
          { keys: "Ctrl Shift L", desc: "LocalSend" },
          { keys: "Esc", desc: "Close clipboard history" },
        ],
      },
      {
        title: "Web apps",
        items: [
          { keys: "Super I", desc: "Trilium (workspace 10)" },
          { keys: "Super U", desc: "ChatGPT (workspace 11)" },
          { keys: "Super Y", desc: "YouTube (workspace 12)" },
          { keys: "Super M", desc: "Spotify (workspace 15)" },
          { keys: "Super Shift M", desc: "Spotify (Flatpak, any workspace)" },
          { keys: "Super Shift Alt B", desc: "Browser (private window)" },
        ],
      },
      {
        title: "Walker (launcher)",
        items: [
          { keys: "j / Down", desc: "Next item" },
          { keys: "k / Up", desc: "Previous item" },
          { keys: "Enter", desc: "Activate selection" },
          { keys: "Esc", desc: "Close Walker" },
        ],
      },
    ],
  },
  {
    id: "windows",
    label: "Windows",
    sections: [
      {
        title: "Focus & layout",
        items: [
          { keys: "Super ←↑→↓", desc: "Move focus" },
          { keys: "Super W", desc: "Close window (confirm)" },
          { keys: "Super F", desc: "Fullscreen" },
          { keys: "Super T", desc: "Toggle 16:9 group stack" },
          { keys: "Alt Tab", desc: "Cycle next (group-aware)" },
          { keys: "Alt Shift Tab", desc: "Cycle previous" },
        ],
      },
      {
        title: "Workspaces (current monitor)",
        items: [
          { keys: "Super J", desc: "Workspace 1" },
          { keys: "Super K", desc: "Workspace 2" },
          { keys: "Super L", desc: "Workspace 3" },
          { keys: "Super Ö", desc: "Workspace 4" },
          { keys: "Super 5–9", desc: "Workspaces 5–9 (top row keys)" },
          { keys: "Super Shift J…9", desc: "Move window to workspace" },
          { keys: "Super Shift I/U/Y", desc: "Move window to web-app workspace" },
        ],
      },
      {
        title: "Waybar workspace icons",
        items: [
          { keys: "j", desc: "Workspace 1" },
          { keys: "k", desc: "Workspace 2" },
          { keys: "l", desc: "Workspace 3" },
          { keys: "ö", desc: "Workspace 4" },
          { keys: "i / u / y", desc: "Workspaces 10 / 11 / 12" },
          { keys: "m", desc: "Workspace 15 (Spotify)" },
        ],
      },
    ],
  },
  {
    id: "tools",
    label: "Tools",
    sections: [
      {
        title: "Screenshots & screen",
        items: [
          { keys: "Super Mouse1", desc: "Screenshot region → clipboard" },
          { keys: "Shift PgUp", desc: "Screenshot region → Satty editor" },
          { keys: "PgDn", desc: "Full screen → clipboard" },
          { keys: "Super PgUp", desc: "Color picker (hyprpicker)" },
        ],
      },
      {
        title: "Speech to text (Super V)",
        items: [
          { keys: "Super V", desc: "Toggle live dictation (type as you speak)" },
          { keys: "Esc", desc: "Stop dictation while active" },
        ],
      },
      {
        title: "Text to speech (Super Alt V)",
        items: [
          { keys: "Super Alt V", desc: "Read clipboard aloud (Piper TTS)" },
        ],
      },
      {
        title: "OCR & capture",
        items: [
          { keys: "Super Shift V", desc: "OCR region → clipboard" },
        ],
      },
      {
        title: "System",
        items: [
          { keys: "Ctrl Alt Del", desc: "System monitor (btop)" },
          { keys: "Super Ctrl Shift S", desc: "Suspend" },
          { keys: "Super Shift G", desc: "GParted (sudo)" },
          { keys: "Super ?", desc: "This shortcuts guide" },
        ],
      },
    ],
  },
  {
    id: "media",
    label: "Media",
    sections: [
      {
        title: "Spotify (keyboard)",
        items: [
          { keys: "F7", desc: "Previous track" },
          { keys: "F8", desc: "Play / pause" },
          { keys: "F9", desc: "Next track" },
          { keys: "F11", desc: "Volume down" },
          { keys: "F12", desc: "Volume up" },
        ],
      },
      {
        title: "Waybar",
        items: [
          { keys: "Click media", desc: "Play / pause default player" },
          { keys: "Right-click media", desc: "Spotify play / pause" },
          { keys: "Scroll on media", desc: "Spotify volume" },
          { keys: "Click speaker", desc: "Volume mixer popup" },
          { keys: "Click power", desc: "Power menu" },
        ],
      },
    ],
  },
]
