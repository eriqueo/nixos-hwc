#!/usr/bin/env bash
# Phased cleanup from docs/audit/2026-06-09-server-audit.md
# NOT meant to be run blind end-to-end. Run phase by phase, read the comments.
set -euo pipefail
cd ~/.nixos

phase1_reclaim() {
  # -- 1a. Unused container images (~19.4 GB). All re-pullable. Containers keep running.
  sudo podman image prune -a -f

  # -- 1b. Orphaned native-ollama state (17 GB). The ollama *unit* no longer
  #        exists on this host (systemctl is-enabled ollama -> not-found); the
  #        live ollama is the container with its own model store.
  #        Models are re-downloadable if the native module is ever re-enabled.
  sudo du -sh /var/lib/private/ollama   # eyeball first
  sudo rm -rf /var/lib/private/ollama

  # -- 1c. Certain-dead repo items (audit §2.1). Tracked files are git-revertible.
  git rm -r domains/ai/.nanoclaw-disabled domains/home/apps/.wayvnc-disabled
  rm -rf heartwood-site   # untracked, contains ONLY node_modules, no source
  # Per Law 12: add changelog lines to domains/ai/README.md + domains/home/README.md
  git commit -m "chore: remove dead modules (nanoclaw, wayvnc) + heartwood-site artifact

Audit: docs/audit/2026-06-09-server-audit.md §2.1"
}

phase2_config() {
  # Each item: edit -> commit -> sudo nixos-rebuild switch --flake .#hwc-server
  #
  # 2a. PG dumps: replace the hand-rolled dump block around
  #     machines/server/config.nix:423 with services.postgresqlBackup
  #     (compression built in), or minimally pipe pg_dump through gzip.
  #     Saves ~18 GB across the 14-day window. Also retire the second dump
  #     script writing to /home/eric/backups/postgres (no rotation).
  #
  # 2b. Make image accumulation structural-impossible:
  #     virtualisation.podman.autoPrune = {
  #       enable = true; flags = [ "--all" ]; dates = "weekly";
  #     };
  #
  # 2c. flake.nix input cruft:
  #     - delete `legacy-config` input (repo importing itself; migration done)
  #     - delete `agenix-stable` (identical URL to `agenix`) and point stable
  #       machine config at `agenix` directly
  #     - on next `nix flake update`: check `nix eval nixpkgs#tailscale.version`
  #       >= 1.98.2, then delete the `nixpkgs-tailscale` input + overlay
  :
}

phase3_refactors() {
  # One commit each. Run the chestertons-fence skill before each deletion.
  #
  # 3a. protonmail-bridge: two modules define systemd.services.protonmail-bridge
  #     (domains/mail/bridge/sys.nix vs domains/mail/protonmail-bridge/sys.nix).
  #     Find which option is enabled, consolidate, delete the other.
  #
  # 3b. Stale duplicates in domains/server/containers/_shared/:
  #     caddy.nix duplicates domains/networking/reverseProxy.nix;
  #     network.nix duplicates domains/networking/podman-network.nix.
  #
  # 3c. Migrate 16 leftover options.nix files into their index.nix (Law 10).
  #     List: rg -l 'mkOption' domains --glob '**/options.nix'
  #
  # 3d. Hardcoded-path sweep (35 hits): start with domains/system/mcp/index.nix
  #     (11), then routes.nix:288,301. Lint:
  #     rg '"/mnt/|"/home/eric/|"/opt/' domains --type nix --glob '!domains/paths/**'
  :
}

phase4_optional() {
  # 4a. Probably-dead dirs (review then archive/delete): domains/business/n8n,
  #     domains/business/receipts, ai_agents/, workspace/ (all but
  #     nixos-dev/add-home-app.sh and nixos/graph/),
  #     domains/server/native/.immich-native-reference/
  #
  # 4b. Git history rewrite (saves ~600 MB; REWRITES ALL HASHES — every clone
  #     must re-clone; force-push required):
  #     git filter-repo --strip-blobs-bigger-than 5M
  #
  # 4c. Wire charter lints into `nix flake check` + add CI (audit §4.1-4.2).
  :
}

echo "Source this file and run phases individually: phase1_reclaim, etc."
