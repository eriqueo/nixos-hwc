#!/usr/bin/env bash
# grebuild — commit + rebuild NixOS in one shot
# Invoked via shell alias: rebuild
set -euo pipefail

REPO="/home/eric/.nixos"
AUTO_YES=false
SKIP_PUSH=false
COMMIT_MSG=""

# --- helpers ---
red() { printf '\033[0;31m%s\033[0m\n' "$*" >&2; }
green() { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m' "$*"; }

confirm() {
    local prompt="$1" default="${2:-n}"
    if [[ "$AUTO_YES" == true ]]; then return 0; fi
    if [[ "$default" == "y" ]]; then
        yellow "$prompt [Y/n] "; read -r ans
        [[ -z "$ans" || "$ans" =~ ^[Yy] ]]
    else
        yellow "$prompt [y/N] "; read -r ans
        [[ "$ans" =~ ^[Yy] ]]
    fi
}

# --- parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            cat <<'EOF'
Usage: rebuild [-m "msg"] [-y] [--skip-push] [-h]

Commit changes and rebuild NixOS.

  -m, --message "msg"  Set commit message (skip interactive prompt)
  -y, --yes            Skip all prompts (auto-commit, auto-push)
  --skip-push          Don't push and don't ask
  -h, --help           Show this help
EOF
            exit 0 ;;
        -y|--yes)       AUTO_YES=true; shift ;;
        --skip-push)    SKIP_PUSH=true; shift ;;
        -m|--message)   COMMIT_MSG="$2"; shift 2 ;;
        *) red "Unknown option: $1"; exit 2 ;;
    esac
done

# --- setup ---
cd "$REPO"
if [[ ! -f flake.nix ]]; then
    red "flake.nix not found in $REPO"
    exit 1
fi

HOST=$(hostname)
DID_COMMIT=false

# --- git commit (if changes exist) ---
if [[ -z "$(git status --porcelain)" ]]; then
    green "No changes to commit, proceeding to rebuild."
else
    git status --short
    echo

    git add -A

    if [[ -z "$COMMIT_MSG" ]]; then
        if [[ "$AUTO_YES" == true ]]; then
            COMMIT_MSG="nixos: rebuild $(date '+%Y-%m-%d %H:%M')"
        else
            yellow "Commit message (enter for default): "
            read -r COMMIT_MSG
            if [[ -z "$COMMIT_MSG" ]]; then
                COMMIT_MSG="nixos: rebuild $(date '+%Y-%m-%d %H:%M')"
            fi
        fi
    fi

    git commit -m "$COMMIT_MSG"
    DID_COMMIT=true
fi

# --- rebuild ---
REBUILD_OK=true
if ! sudo nixos-rebuild switch --flake ".#${HOST}"; then
    REBUILD_OK=false
    red "Rebuild failed (exit $?)."
    if [[ "$DID_COMMIT" == true && "$SKIP_PUSH" == false ]]; then
        if ! confirm "Push the commit anyway?"; then
            exit 1
        fi
    else
        exit 1
    fi
fi

# --- push ---
if [[ "$DID_COMMIT" == true && "$SKIP_PUSH" == false ]]; then
    if confirm "Push to remote?" "y"; then
        git push
    else
        echo "Skipping push. Don't forget to push later."
    fi
fi

# --- summary ---
if [[ "$DID_COMMIT" == true ]]; then
    SHORT=$(git rev-parse --short HEAD)
    MSG=$(git log -1 --format='%s' | cut -c1-50)
    if [[ "$REBUILD_OK" == true ]]; then
        green "Rebuilt ${HOST} — ${SHORT} — ${MSG}"
    else
        yellow "Committed ${SHORT} but rebuild failed — ${MSG}"
        echo
    fi
else
    if [[ "$REBUILD_OK" == true ]]; then
        green "Rebuilt ${HOST} — no new commit"
    fi
fi
