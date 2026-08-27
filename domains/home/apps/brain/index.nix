# domains/home/apps/brain/index.nix
#
# `brain` — the vault janitor/fixer CLI, on PATH.
#
# Pattern: the same "code lives in its own ~/600_apps checkout, Nix only supplies the
# environment" shape as domains/automation/brain-sweep and domains/server/native/ai/brainvec.
# Nix does NOT build this app. It wraps the checkout's pre-built dist/bin/brain.js.
#
# Why this module exists: package.json declares `"bin": { "brain": "dist/bin/brain.js" }`, and
# the repo README documents every command as `brain <cmd>`. No such executable was ever on PATH
# on either machine, so every real invocation had to be `node .../dist/bin/brain.js`. The
# documented name and the usable name disagreed until 2026-08-27.
#
# SIBLINGS RULED OUT (Charter §0.13 precondition 1 — why no existing module could hold this):
#   - domains/automation/brain-sweep — the closest fit, and it already declares repoDir/vaultDir
#     for this same checkout. Rejected on Law 16 (layer purity): it is the SYSTEM lane, a systemd
#     timer running ONE subcommand as a service. `brain` is an interactive user command and needs
#     home.packages, which is the HM lane. The two defaults are therefore duplicated on purpose;
#     brain-sweep is server-only, this module is every machine, and the system/HM boundary is
#     what forbids one producer here. If a third consumer appears, promote the paths to
#     domains/paths and let both read them.
#   - domains/home/apps/doctl — a CLI wrapper, but it wraps a NIXPKGS binary and injects an
#     agenix secret. `brain` has neither a nixpkgs package nor a secret.
#   - domains/home/apps/dxlog — nearest in shape, but it wraps a script VENDORED into this repo
#     (./parts/dxlog.sh). The brain CLI's code lives outside the repo in ~/600_apps and must not
#     be copied in; Nix schedules and wraps it, never builds it.
#   - domains/home/core/shell — declares an `mcp.brain` entry. That is the brain MCP HTTP server,
#     a different artifact from this CLI. No name collision.
#
# NAMESPACE: hwc.home.apps.brain.*
# DEPENDENCIES: the built checkout at cfg.repoDir (dist/bin/brain.js + node_modules)

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.brain;

  # nodejs runs the CLI. The CLI itself shells out to three more binaries, so the wrapper must
  # supply them rather than trust the caller's PATH:
  #   git       — lib/fix-store.ts commitFixes()
  #   flock     — lib/fix-store.ts reexecUnderLock(), the vault's shared .sync.lock
  #   du        — lib/vault-store.ts stversionsMb()
  brainScript = pkgs.writeShellApplication {
    name = "brain";
    runtimeInputs = [ pkgs.nodejs_22 pkgs.git pkgs.util-linux pkgs.coreutils ];
    text = ''
      REPO=${lib.escapeShellArg cfg.repoDir}
      BRAIN_VAULT=${lib.escapeShellArg cfg.vaultDir}
      export BRAIN_VAULT

      # Fail LOUD, unlike brain-sweep, which exits 0 on a missing build so a rebuild degrades
      # gracefully. A human typed this command; a silent success would be a lie.
      if [ ! -f "$REPO/dist/bin/brain.js" ]; then
        echo "brain: no build at $REPO/dist/bin/brain.js" >&2
        echo "       clone the hub and build it:" >&2
        echo "         git clone server:/home/eric/git/brain.git $REPO" >&2
        echo "         cd $REPO && npm ci && npm run build" >&2
        exit 1
      fi

      exec node "$REPO/dist/bin/brain.js" "$@"
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.brain = {
    enable = lib.mkEnableOption "brain — the vault janitor/fixer CLI (Nix only puts the checkout on PATH)";

    repoDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/600_apps/brain";
      description = "The brain CLI checkout (built: dist/bin/brain.js + node_modules).";
    };

    vaultDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/900_vaults/brain";
      description = "The Obsidian vault the CLI reads; exported as BRAIN_VAULT.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ brainScript ];
  };
}
