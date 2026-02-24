#!/usr/bin/env bash
set -euo pipefail

DOTFILES_REPO="${DOTFILES_REPO:-adisidev/dotfiles}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/github/dotfiles}"
PROTECTED_DOTFILES_REPO="${PROTECTED_DOTFILES_REPO:-}"
SKIP_PROTECTED="${SKIP_PROTECTED:-false}"
INSTALL_PRIVATE="${INSTALL_PRIVATE:-ask}"
BREW_BUNDLE_REQUIRED="${BREW_BUNDLE_REQUIRED:-false}"

log() {
  printf "[bootstrap] %s\n" "$*"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

brew_formula_installed() {
  brew list --formula "$1" >/dev/null 2>&1
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
  if ! brew_formula_installed "$pkg"; then
    log "Installing formula: $pkg"
    brew install "$pkg"
  fi
}

normalize_install_private() {
  local value="${1:-ask}"
  value="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$value" in
    yes|y|true|1)
      printf "true"
      ;;
    no|n|false|0)
      printf "false"
      ;;
    ask|"")
      printf "ask"
      ;;
    *)
      printf "invalid"
      ;;
  esac
}

prompt_yes_no_default_no() {
  local prompt="$1"
  local answer

  if [[ ! -r /dev/tty ]]; then
    return 1
  fi

  while true; do
    printf "%s [y/N]: " "$prompt" > /dev/tty
    if ! IFS= read -r answer < /dev/tty; then
      return 1
    fi

    answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      y|yes)
        printf "true"
        return
        ;;
      n|no|"")
        printf "false"
        return
        ;;
    esac

    printf "Please answer y or n.\n" > /dev/tty
  done
}

resolve_install_private_preference() {
  local normalized
  normalized="$(normalize_install_private "$INSTALL_PRIVATE")"

  if [[ "$normalized" == "invalid" ]]; then
    log "Invalid INSTALL_PRIVATE value '$INSTALL_PRIVATE'. Falling back to interactive prompt."
    normalized="ask"
  fi

  if [[ "$normalized" == "ask" ]]; then
    if INSTALL_PRIVATE="$(prompt_yes_no_default_no "Install private/secret dotfiles content when detected?")"; then
      :
    else
      INSTALL_PRIVATE="false"
      log "Could not prompt interactively; defaulting private/secret install to 'no'."
    fi
  else
    INSTALL_PRIVATE="$normalized"
  fi

  log "Private/secret content enabled: $INSTALL_PRIVATE"
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    return
  fi

  log "GitHub CLI is not authenticated. Starting login flow..."
  gh auth login --hostname github.com --git-protocol https --web
}

clone_or_update_dotfiles_repo() {
  mkdir -p "$(dirname "$DOTFILES_DIR")"

  if [[ -d "$DOTFILES_DIR/.git" ]]; then
    log "Updating dotfiles at $DOTFILES_DIR"
    if ! git -C "$DOTFILES_DIR" pull --ff-only; then
      log "Could not fast-forward $DOTFILES_DIR; continuing with current checkout."
    fi
    return
  fi

  log "Cloning dotfiles repo to $DOTFILES_DIR"
  gh repo clone "$DOTFILES_REPO" "$DOTFILES_DIR"
}

main() {
  install_homebrew_if_missing

  install_formula_if_missing git
  install_formula_if_missing gh

  resolve_install_private_preference
  ensure_gh_auth
  clone_or_update_dotfiles_repo

  local setup_script="$DOTFILES_DIR/setup.sh"
  if [[ ! -f "$setup_script" ]]; then
    log "Missing setup script: $setup_script"
    exit 1
  fi

  DOTFILES_REPO="$DOTFILES_REPO" \
    DOTFILES_DIR="$DOTFILES_DIR" \
    PROTECTED_DOTFILES_REPO="$PROTECTED_DOTFILES_REPO" \
    SKIP_PROTECTED="$SKIP_PROTECTED" \
    INSTALL_PRIVATE="$INSTALL_PRIVATE" \
    BREW_BUNDLE_REQUIRED="$BREW_BUNDLE_REQUIRED" \
    bash "$setup_script"
}

main "$@"
