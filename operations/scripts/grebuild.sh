#!/usr/bin/env bash
# Wrapper for quick nixos-rebuild commands
sudo nixos-rebuild "$@" --flake .#$(hostname)
