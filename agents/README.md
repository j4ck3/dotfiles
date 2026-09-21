# Agent skills (canonical copy)

All skills live in `agents/.agents/skills/`. Stow links them to `~/.agents/skills/`.

Pi reads the same tree via `settings.json` → `"skills": ["~/.agents/skills"]`.

Cursor/t3code need a **copy** (no symlinks): run `sync-cursor-skills` after changes.

## Install

```sh
cd ~/dotfiles
git submodule update --init pi/vendor/pi-config   # pi-config skill symlinks
stow -v -R -t "$HOME" agents
sync-cursor-skills
```

Restart Pi (`/reload`) or t3code after skill changes.

## pi-config skills

`analyze-sessions`, `pdf-reader`, `web-debug`, `youtube-transcript` are symlinks into `pi/vendor/pi-config`. Update with:

```sh
cd ~/dotfiles/pi/vendor/pi-config && git pull
```

Run `~/dotfiles/pi/install-deps.sh` after pi-config updates if PDF/browser deps changed.

## Add / update skills (Matt Pocock, skills.sh)

With stow active, global install lands in dotfiles:

```sh
npx skills add mattpocock/skills -g -a cursor -s '*' -y
sync-cursor-skills
git add agents/.agents/skills agents/.agents/.skill-lock.json
```

Or install elsewhere and copy into `agents/.agents/skills/<name>/`.

## Uninstall stow links only

```sh
stow -v -D -t "$HOME" agents
```

Skill files remain in `~/dotfiles/agents/.agents/skills/`.
