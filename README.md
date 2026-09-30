# dotfiles-bootstrap

Public bootstrap entrypoint for a private dotfiles repo.

## Run

```bash
curl -fsSL bootstrap.adi.zip | bash
```

`bootstrap.adi.zip` redirects to [`bootstrap.sh`](bootstrap.sh) in this repo.

## What it does

- Installs Homebrew if needed (asks for the sudo password once).
- Installs `git` and `gh`, logs `gh` in through the browser if it is not already, and makes `gh` git's credential helper.
- Checks `adisidev/dotfiles` out with `$HOME` as its work tree (`~/.git`), moving any clashing files to `~/.dotfiles-bootstrap-conflicts/<timestamp>/`. Plain `git status` in `~` then shows the tracked config.
- Runs `~/dotfiles/setup.sh`, which asks its questions up front (hostname, apps without a Homebrew cask, remote use) and then installs everything unattended. See the dotfiles README for what it sets up.

Re-running is safe: an existing `~/.git` is fetched and checked out again, and `setup.sh` skips finished steps.

## Optional env vars

```bash
DOTFILES_REPO="yourname/dotfiles"      # repo to check out (default adisidev/dotfiles)
SETUP_DIR="$HOME/dotfiles"             # where setup.sh lives in that repo
INSTALL_DIRECT_APPS=true REMOTE_ACCESS=true SET_HOSTNAME=false   # answer setup.sh's questions in advance
```
