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
