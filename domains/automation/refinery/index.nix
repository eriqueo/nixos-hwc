# domains/automation/refinery/index.nix
#
# Refinery — read-only Kanban board for the gauntlet hopper.
#
# Renders every card across the brain vault's _inbox/nightly_builds/ goal
# folders (plus raw _ideas.md ideas) as a live board, grouped by status. This
# is slice 01+02 of the refinery build (see brain:
# tech/development/builds/refinery/refinery_engine_design.md) — the read-only
# viewer; the engine + interactivity (amend/rewind) come later.
#
# The TypeScript app (app/src/*.ts) is bundled to a single JS file by esbuild
# at build time (no npm / node_modules / npmDepsHash dance — zero runtime deps,
# pure node:http). The service reads the vault read-only as eric.
#
# NAMESPACE: hwc.automation.refinery.*
#
# DEPENDENCIES:
#   - hwc.paths.brain.server-replica / .vault (Syncthing'd brain vault)
#   - Caddy route on port 8060 (domains/networking/routes.nix)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.refinery;
  paths = config.hwc.paths;

  vaultDefault =
    if paths.brain.server-replica != null
    then paths.brain.server-replica
    else paths.brain.vault;

  # esbuild bundles the TS entrypoint (+ its relative imports) into one CJS file.
  # Pass the whole src/ dir (not just server.ts) so esbuild can resolve the
  # sibling ./parse.ts / ./render.ts imports.
  appSrc = ./app/src;
  board = pkgs.runCommand "refinery-board" {
    nativeBuildInputs = [ pkgs.esbuild ];
  } ''
    mkdir -p $out
    esbuild ${appSrc}/server.ts \
      --bundle --platform=node --format=cjs \
      --outfile=$out/server.js
  '';
in
{
  options.hwc.automation.refinery = {
    enable = lib.mkEnableOption "Refinery read-only Kanban board for the gauntlet hopper";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8060;
      description = "HTTP port the board listens on (Caddy upstream)";
    };

    vaultDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = vaultDefault;
      description = "Brain vault root (contains _inbox/nightly_builds/)";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vaultDir != null;
        message = "hwc.automation.refinery.vaultDir must resolve — set hwc.paths.brain.* or override vaultDir.";
      }
    ];

    systemd.services.refinery-board = {
      description = "Refinery gauntlet hopper board (read-only)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = "users";
        ExecStart = "${pkgs.nodejs}/bin/node ${board}/server.js";
        Environment = [
          "REFINERY_PORT=${toString cfg.port}"
          "REFINERY_VAULT_DIR=${cfg.vaultDir}"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        # Read-only viewer: it only ever reads the vault. Mask the whole home
        # tree, then bind just the vault back in read-only — the service sees
        # nothing else under /home (defense in depth beyond ProtectSystem).
        ProtectSystem = "strict";
        ProtectHome = lib.mkForce true;
        BindReadOnlyPaths = [ cfg.vaultDir ];
        PrivateTmp = true;
      };
    };
  };
}
