# domains/lib/deps-update.nix
#
# Shared helper for buildNpmPackage-built services.
#
# Returns a function taking `{ serviceName, serviceRel }` and producing a
# `pkgs.writeShellApplication` that automates the npmDepsHash update flow
# after `npm install` / `npm update` in the service's parts/src dir.
#
# After any package-lock.json change:
#
#   cd ~/.nixos/domains/<service>/parts/src
#   npm install <pkg>
#   <serviceName>-deps-update    # this CLI: prefetch + patch index.nix + git add
#   git -C ~/.nixos diff --cached # review
#   sudo nixos-rebuild switch --flake ~/.nixos#hwc-server
#
# Anchored on `config.hwc.paths.nixos` (Charter Law 3 — no hardcoded paths
# outside domains/paths/).
#
# History: shipped per-service as `hwc-notify-deps-update` in Phase 1.1
# (2026-05-31); lifted into this shared helper when hwc-leads (Phase 2.1,
# 2026-05-31) became the second buildNpmPackage-built service. See brain:
# wiki/nixos/nixos-buildnpmpackage-hash-workflow.md.

{ pkgs, config }:

{ serviceName, serviceRel }:

pkgs.writeShellApplication {
  name = "${serviceName}-deps-update";
  runtimeInputs = [
    pkgs.prefetch-npm-deps
    pkgs.gnused
    pkgs.git
    pkgs.coreutils
  ];
  text = ''
    set -euo pipefail

    nixos_root="${config.hwc.paths.nixos}"
    service_rel="${serviceRel}"
    service_dir="$nixos_root/$service_rel"
    lockfile="$service_dir/parts/src/package-lock.json"
    pkg_json="$service_dir/parts/src/package.json"
    index_nix="$service_dir/index.nix"

    # ── preconditions ──
    [ -f "$lockfile" ]  || { echo "error: lockfile missing: $lockfile" >&2; exit 1; }
    [ -f "$pkg_json" ]  || { echo "error: package.json missing: $pkg_json" >&2; exit 1; }
    [ -f "$index_nix" ] || { echo "error: index.nix missing: $index_nix" >&2; exit 1; }

    if ! grep -q 'npmDepsHash = "sha256-' "$index_nix"; then
      echo "error: no 'npmDepsHash = \"sha256-...\"' line in $index_nix" >&2
      exit 1
    fi

    # ── compute new hash ──
    echo "[deps-update] service: $service_rel"
    echo "[deps-update] reading $lockfile"
    new_hash=$(prefetch-npm-deps "$lockfile")
    echo "[deps-update] new npmDepsHash: $new_hash"

    # ── patch index.nix in-place ──
    sed -i "s|npmDepsHash = \"sha256-[A-Za-z0-9+/=]*\"|npmDepsHash = \"$new_hash\"|" "$index_nix"

    # ── stage for commit ──
    git -C "$nixos_root" add \
      "$service_rel/index.nix" \
      "$service_rel/parts/src/package.json" \
      "$service_rel/parts/src/package-lock.json"

    cat <<MSG
[deps-update] patched and staged:
  $service_rel/index.nix
  $service_rel/parts/src/package.json
  $service_rel/parts/src/package-lock.json

Next:
  git -C "$nixos_root" diff --cached
  sudo nixos-rebuild switch --flake "$nixos_root#hwc-server"
MSG
  '';
}
