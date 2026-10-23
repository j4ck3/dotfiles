# Pi agent config (amosblomqvist/pi-config)

Extensions from [amosblomqvist/pi-config](https://github.com/amosblomqvist/pi-config), vendored as a submodule and stowed into `~/.pi/agent`.

Skills live in the unified [`agents`](agents/README.md) package, not here.

Does **not** replace `auth.json`, `settings.json` (except add `"skills": ["~/.agents/skills"]` yourself), sessions, or `npm/` packages.

## Install

```sh
cd ~/dotfiles
git submodule update --init pi/vendor/pi-config
stow -v -R -t "$HOME" agents pi
~/dotfiles/pi/install-deps.sh
```

Restart `pi` or run `/reload`.

## Claude Code provider

[pi-claude-bridge](https://github.com/elidickinson/pi-claude-bridge) runs Claude models in pi through the Claude Code Agent SDK, billed against the Claude subscription that `claude` is logged into. Pi's tools, TUI, and skills stay in charge.

```sh
claude auth login           # once, if `claude auth status` shows loggedIn: false
pi install npm:pi-claude-bridge
```

Then pick a model with `/model`, for example `claude-bridge/claude-opus-5-5` or `claude-bridge/claude-haiku-4-5`. Config lives in `.pi/agent/claude-bridge.json` (stowed). Set `provider.plan` to `"max"` after upgrading the subscription. Debug with `CLAUDE_BRIDGE_DEBUG=1`; logs go to `~/.pi/agent/claude-bridge.log`.

## What gets linked

| Type | Items |
|------|--------|
| Extensions | `ask-user-question`, `bash-guard`, `browser`, `custom-header`, `prompt-snippets`, `web-fetch`, `web-search` |

Stubs (`interactive-subagents`, `observational-memory`) omitted.

## Optional setup

- **Browser:** `/browser on`; Playwright via `install-deps.sh`
- **Web search:** `extensions/web-search/auth.json` from `auth.example.json`
- **YouTube transcript:** `yt-dlp`, `ffmpeg`
- **PDF reader:** venv via `install-deps.sh`

## Uninstall

```sh
stow -v -D -t "$HOME" pi
```
