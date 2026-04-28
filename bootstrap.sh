#!/usr/bin/env bash
# Bootstrap a new machine: install prereqs, bare-clone dotfiles into $HOME,
# then hand off to the setup script in ~/dotfiles/setup.sh.
#
# Usage: curl -fsSL bootstrap.adi.zip | bash

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-adisidev/dotfiles}"
DOTFILES_GIT_DIR="${DOTFILES_GIT_DIR:-$HOME/.local/share/dotfiles.git}"
SETUP_DIR="${SETUP_DIR:-$HOME/dotfiles}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.dotfiles-bootstrap-conflicts}"

log() {
  printf "[bootstrap] %s\n" "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_brew_shellenv() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

install_homebrew_if_missing() {
  if have_cmd brew; then
    ensure_brew_shellenv
    return
  fi
  log "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ensure_brew_shellenv
}

install_formula_if_missing() {
  local pkg="$1"
  if ! brew list --formula "$pkg" >/dev/null 2>&1; then
    log "Installing $pkg"
    brew install "$pkg"
  fi
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    return
  fi
  log "GitHub CLI is not authenticated. Starting login flow..."
  gh auth login --hostname github.com --git-protocol https --web
  gh auth setup-git >/dev/null 2>&1 || log "Could not configure git with gh auth automatically."
}

# Wrapper: every git op against the bare dotfiles repo.
df_git() {
  git --git-dir="$DOTFILES_GIT_DIR" --work-tree="$HOME" "$@"
}

bare_clone_dotfiles() {
  if [[ -d "$DOTFILES_GIT_DIR" ]]; then
    log "Bare repo already exists at $DOTFILES_GIT_DIR; fetching latest."
    df_git fetch origin
    return
  fi

  log "Bare-cloning $DOTFILES_REPO into $DOTFILES_GIT_DIR"
  git clone --bare "https://github.com/$DOTFILES_REPO.git" "$DOTFILES_GIT_DIR"

  # Quiet status: $HOME has thousands of untracked files; we only want
  # tracked/modified noise.
  df_git config status.showUntrackedFiles no

  # Make `git ls-files` and friends work the same as a regular repo.
  df_git config core.bare false
}

# Move any pre-existing files in $HOME that would conflict with checkout
# into a backup directory, so checkout can proceed cleanly.
backup_conflicts() {
  local conflicts
  conflicts="$(df_git checkout 2>&1 | sed -n 's/^	//p' | grep -v '^$' || true)"
  if [[ -z "$conflicts" ]]; then
    return
  fi

  local stamp="$(date +%Y%m%d-%H%M%S)"
  local dest="$BACKUP_ROOT/$stamp"
  mkdir -p "$dest"
  log "Moving $(echo "$conflicts" | wc -l | tr -d ' ') conflicting files to $dest"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    mkdir -p "$dest/$(dirname "$f")"
    mv "$HOME/$f" "$dest/$f"
  done <<< "$conflicts"
}

checkout_dotfiles() {
  if ! df_git checkout 2>/dev/null; then
    log "Initial checkout had conflicts — backing them up and retrying."
    backup_conflicts
    df_git checkout
  fi

  # Bring up the server submodule (others are phantom and skipped).
  df_git -c submodule.server.update=checkout submodule update --init dotfiles/server 2>/dev/null || true
}

main() {
  install_homebrew_if_missing
  install_formula_if_missing git
  install_formula_if_missing gh

  ensure_gh_auth
  bare_clone_dotfiles
  checkout_dotfiles

  local setup_script="$SETUP_DIR/setup.sh"
  if [[ -x "$setup_script" ]]; then
    log "Running setup script: $setup_script"
    DOTFILES_GIT_DIR="$DOTFILES_GIT_DIR" SETUP_DIR="$SETUP_DIR" bash "$setup_script"
  else
    log "Setup script not found or not executable at $setup_script — skipping."
    log "Once you've airdropped your secrets and run $setup_script manually, you're done."
  fi

  log "Bootstrap complete. Use the 'dotfiles' alias for git operations:"
  log "  source ~/.aliases   # or open a new shell"
  log "  dotfiles status"
}

main "$@"
