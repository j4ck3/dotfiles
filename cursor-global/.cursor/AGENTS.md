## Systems

- Main system (CachyOS): fish shell
- tower (remote server): bash shell

## Cursor / t3code skills

Matt Pocock and other agent skills live in `~/dotfiles/agents/.agents/skills/`, stowed to `~/.agents/skills/`. Pi uses the same path via `settings.json` → `"skills": ["~/.agents/skills"]`.

t3code reads `~/.cursor/skills/` (copies, not symlinks) — run after install or update:

```bash
sync-cursor-skills
# optional: also sync current repo
sync-cursor-skills --project "$PWD"
```

Install skills into dotfiles (with `agents` stowed, `-g` writes through the symlink):

```bash
npx skills add mattpocock/skills -g -a cursor -s '*' -y
sync-cursor-skills
git add agents/.agents/skills agents/.agents/.skill-lock.json
```

See [`agents/README.md`](../../agents/README.md) in dotfiles for full workflow.
