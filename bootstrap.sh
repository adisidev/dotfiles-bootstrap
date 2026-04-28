#!/usr/bin/env bash
# Bootstrap a new machine: install prereqs, clone dotfiles into $HOME,
# then hand off to ~/dotfiles/setup.sh.
#
# Usage: curl -fsSL bootstrap.adi.zip | bash
#
# The dotfiles repo is checked out with $HOME as its work-tree and
# $HOME/.git as its git dir, so plain `git status` from $HOME just works.

set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-adisidev/dotfiles}"
DOTFILES_URL="${DOTFILES_URL:-https://github.com/$DOTFILES_REPO.git}"
SETUP_DIR="${SETUP_DIR:-$HOME/dotfiles}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.dotfiles-bootstrap-conflicts}"

log()      { printf "[bootstrap] %s\n" "$*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_brew_shellenv() {
  if   [[ -x /opt/homebrew/bin/brew              ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew                 ]]; then eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -x /home/linuxbrew/.linuxbrew/bin/brew ]]; then eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
}

install_homebrew_if_missing() {
  if have_cmd brew; then ensure_brew_shellenv; return; fi
  log "Installing Homebrew..."
  log "(prompting for sudo password — needed to chown /opt/homebrew on first install)"
  # NONINTERACTIVE=1 makes Homebrew skip prompts AND skip sudo-credential
  # bootstrap, so we cache them ourselves first. sudo reads from /dev/tty
  # by default, so this works under curl|bash too.
  if ! sudo -v; then
    log "Could not cache sudo credentials. Run 'sudo -v' yourself, then re-run bootstrap."
    exit 1
  fi
  # Keep sudo credentials alive in the background until Homebrew install finishes.
  ( while true; do sudo -n true; sleep 50; done ) 2>/dev/null &
  local sudo_keep_pid=$!
  trap 'kill "$sudo_keep_pid" 2>/dev/null || true' EXIT

  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  kill "$sudo_keep_pid" 2>/dev/null || true
  trap - EXIT
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
  if gh auth status >/dev/null 2>&1; then return; fi
  log "GitHub CLI not authenticated — starting login flow..."
  gh auth login --hostname github.com --git-protocol https --web
  gh auth setup-git >/dev/null 2>&1 || log "(could not configure git with gh auth automatically)"
}

# Initialize $HOME as the work-tree of the dotfiles repo.
# Idempotent: re-runs cleanly if $HOME/.git already exists.
init_dotfiles_repo() {
  if [[ -d "$HOME/.git" ]]; then
    log "$HOME/.git already exists — fetching latest."
    git -C "$HOME" fetch origin main
    return
  fi

  log "Initializing dotfiles repo at \$HOME/.git"
  cd "$HOME"
  git init -q
  git remote add origin "$DOTFILES_URL"
  git config status.showUntrackedFiles no
  git fetch origin main
}

# Move any pre-existing files in $HOME that would conflict with checkout
# into a timestamped backup directory.
backup_conflicts() {
  local conflicts
  conflicts="$(git -C "$HOME" -c advice.detachedHead=false checkout -B main FETCH_HEAD 2>&1 \
                 | sed -n 's/^\t//p' | grep -v '^$' || true)"
  if [[ -z "$conflicts" ]]; then
    return
  fi

  local stamp dest
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="$BACKUP_ROOT/$stamp"
  mkdir -p "$dest"
  log "Moving $(echo "$conflicts" | wc -l | tr -d ' ') conflicting files to $dest"
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    mkdir -p "$dest/$(dirname "$f")"
    mv "$HOME/$f" "$dest/$f"
  done <<< "$conflicts"
}

checkout_dotfiles() {
  if git -C "$HOME" checkout -B main FETCH_HEAD 2>/dev/null; then
    :
  else
    log "Initial checkout had conflicts — backing them up and retrying."
    backup_conflicts
    git -C "$HOME" checkout -B main FETCH_HEAD
  fi
  git -C "$HOME" branch --set-upstream-to=origin/main main 2>/dev/null || true

  # Server submodule (others are phantom — registered as gitlinks but missing
  # from .gitmodules — and are skipped automatically).
  git -C "$HOME" -c submodule.server.update=checkout submodule update --init dotfiles/server 2>/dev/null || true
}

main() {
  install_homebrew_if_missing
  install_formula_if_missing git
  install_formula_if_missing gh

  ensure_gh_auth
  init_dotfiles_repo
  checkout_dotfiles

  local setup_script="$SETUP_DIR/setup.sh"
  if [[ -x "$setup_script" ]]; then
    log "Running $setup_script"
    SETUP_DIR="$SETUP_DIR" bash "$setup_script"
  else
    log "$setup_script not found or not executable — skipping."
  fi

  log ""
  log "Bootstrap complete."
  log "Plain 'git status' works from \$HOME (the repo lives at \$HOME/.git)."
  log "Open a new shell or 'source ~/.zshrc' to pick up aliases and plugins."
}

main "$@"
