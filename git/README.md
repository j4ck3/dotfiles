# Git global identity

Sets `user.name` and `user.email` in `~/.gitconfig` for every repository on the machine.

### Windows

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME\dotfiles\git\install-git-identity.ps1"
```

### Linux

```sh
bash ~/dotfiles/git/install-git-identity.sh
```
