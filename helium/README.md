# helium

Helium (Chromium) bookmarks for the main profile.

Helium saves `Bookmarks` by writing a temp file and renaming it over the original. That rename replaces a symlink, so the file cannot be stowed directly. Instead:

- `Bookmarks` is a snapshot of `~/.config/net.imput.helium/Default/Bookmarks`.
- The stowed user units `helium-bookmarks-sync.path` and `.service` copy the live file into this snapshot whenever Helium changes it.
- `restore-bookmarks.sh` copies the snapshot back into the profile on a new machine. Quit Helium before running it.

Setup:

```sh
stow -t ~ helium
systemctl --user daemon-reload
systemctl --user enable --now helium-bookmarks-sync.path
```
