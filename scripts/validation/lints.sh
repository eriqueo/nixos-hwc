#!/usr/bin/env bash
set -euo pipefail

echo "Lint: home profile must not import sys.nix"
! rg -n "sys\.nix" profiles/home.nix 2>/dev/null || true

echo "Lint: profiles must not import parts/*"
! rg -n "domains/home/.+/(parts|ui\.nix|behavior\.nix)" profiles 2>/dev/null || true

echo "Lint: host networking must be only in domains/system/networking.nix"
! rg -n "networking\." domains/infrastructure 2>/dev/null | grep -v container-networking.nix || true

echo "List files that set home.packages"
rg -n "home\.packages" domains 2>/dev/null | cut -d: -f1 | sort -u || echo "None found"

echo "List files that set environment.systemPackages"
rg -n "environment\.systemPackages" domains 2>/dev/null | cut -d: -f1 | sort -u || echo "None found"

echo "OK"