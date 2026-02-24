# dotfiles-bootstrap

Public bootstrap entrypoint for a private dotfiles repo.

## Run

```bash
curl -fsSL https://raw.githubusercontent.com/adisidev/dotfiles-bootstrap/main/bootstrap.sh | bash
```

## What it does

- Installs Homebrew if needed.
- Installs `git` and `gh`.
- Authenticates `gh` (web login when needed).
- Configures git to use `gh` auth by default.
- Clones or updates `adisidev/dotfiles`.
- Runs `setup.sh` from that repo.
- Prompts whether to include private/secret content.
- Optionally prompts to set macOS `HostName`, `LocalHostName`, and `ComputerName`.

## Optional env vars

```bash
# force private/secret content on/off
INSTALL_PRIVATE=true

# skip secondary protected repo sync
SKIP_PROTECTED=true

# make brew bundle failures fatal
BREW_BUNDLE_REQUIRED=true

# hostname setup
SET_HOSTNAME=true
TARGET_HOSTNAME="work-mbp"

# override target repo/path
DOTFILES_REPO="yourname/dotfiles"
DOTFILES_DIR="$HOME/github/dotfiles"
```
