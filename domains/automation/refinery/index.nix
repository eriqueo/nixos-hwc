# domains/automation/refinery/index.nix
#
# Refinery — interactive engine board + intake (slices 01–08).
#
# The :8060 service now runs the ENGINE's HTTP shell (engine/src/shells/serve.ts),
# a node:http surface over the substance-agnostic core: it renders engine Items
# grouped by stageStatus, takes intake sentences (triaged into the enabled
# profiles), and supports amend / rewind / profile-toggle. The read-only gauntlet
# hopper view is folded in as the /hopper route.
#
# Build: the engine carries deps (zod, yaml), so we `npm ci` via buildNpmPackage
# (npmDepsHash dance — see project memory) and esbuild-bundle serve.ts into one
# dep-free server.js. Profiles are baked into the store from ./profiles; mutable
# state (items + the enabled overlay) lives in /var/lib/refinery (StateDirectory).
#
# NAMESPACE: hwc.automation.refinery.*
#
# DEPENDENCIES:
#   - hwc.paths.brain.server-replica / .vault (brain vault — /hopper route)
#   - Caddy route on port 8060 (domains/networking/routes.nix)
#   - a headless `claude` binary for triage (claude-cli provider) — cfg.claudeBin

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.refinery;
  paths = config.hwc.paths;

  vaultDefault =
    if paths.brain.server-replica != null
    then paths.brain.server-replica
    else paths.brain.vault;

  # buildNpmPackage installs deps (zod, yaml); esbuild then bundles serve.ts (and
  # its .js-specifier imports, which esbuild resolves to the .ts sources) into one
  # CJS file with the deps inlined, so the runtime needs only nodejs.
  board = pkgs.buildNpmPackage {
    pname = "refinery-engine-board";
    version = "0.1.0";
    src = ./engine;
    npmDepsHash = "sha256-FM9UojLOeKWb8Rer2oBYF6Qk3v3cgFewEVzDdsxBFrA=";
    nativeBuildInputs = [ pkgs.esbuild ];
    dontNpmBuild = true; # we don't need tsc output, just the bundle
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      esbuild src/shells/serve.ts \
        --bundle --platform=node --format=cjs \
        --outfile=$out/server.js
      runHook postInstall
    '';
  };

  # Profiles are data baked into the store (read-only at runtime); the enabled
  # overlay is written to mutable state, never back to these files.
  profilesDir = ./profiles;
in
{
  options.hwc.automation.refinery = {
    enable = lib.mkEnableOption "Refinery interactive engine board + intake";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8060;
      description = "HTTP port the board listens on (Caddy upstream)";
    };

    vaultDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = vaultDefault;
      description = "Brain vault root — nightly-builds card mirror + the queue write-back (status flip)";
    };

    srGauntletDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = "/home/eric/700_datax/sr_gauntlet";
      description = "sr_gauntlet dir — read-only mirror of its investigations/";
    };

    triageProvider = lib.mkOption {
      type = lib.types.str;
      default = "claude-cli";
      description = "LlmPort provider used to triage intake sentences (claude-cli | anthropic-api | ollama)";
    };

    claudeBin = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/etc/profiles/per-user/eric/bin/claude";
      description = "Headless claude binary for the claude-cli triage provider";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.refinery-board = {
      description = "Refinery interactive engine board + intake";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        User = lib.mkForce "eric";
        Group = "users";
        ExecStart = "${pkgs.nodejs}/bin/node ${board}/server.js";
        StateDirectory = "refinery"; # → /var/lib/refinery (items + enabled overlay)
        Environment = [
          "REFINERY_PORT=${toString cfg.port}"
          "REFINERY_PROFILES_DIR=${profilesDir}"
          "REFINERY_ITEMS_DIR=/var/lib/refinery/items"
          "REFINERY_PROFILE_STATE=/var/lib/refinery/profiles.json"
          # Per-gauntlet "max per run" caps the board edits; both run.sh files
          # read this same file (with their env value as fallback).
          "REFINERY_CAPS_FILE=/var/lib/refinery/caps.json"
          "REFINERY_TRIAGE_PROVIDER=${cfg.triageProvider}"
        ] ++ lib.optional (cfg.claudeBin != null) "REFINERY_CLAUDE_BIN=${cfg.claudeBin}"
          ++ lib.optional (cfg.vaultDir != null) "REFINERY_VAULT_DIR=${cfg.vaultDir}"
          ++ lib.optional (cfg.srGauntletDir != null) "REFINERY_SR_GAUNTLET_DIR=${cfg.srGauntletDir}";
        Restart = "on-failure";
        RestartSec = 5;
        # State in /var/lib/refinery (StateDirectory). Home is masked (tmpfs);
        # only the exact paths the board touches are bound back:
        #   - vault _inbox/nightly_builds: READ-WRITE (queue/unqueue flips card status)
        #   - vault runs/ + sr_gauntlet investigations/: READ-ONLY (mirror + REPORTs)
        # ProtectHome MUST be "tmpfs" (not true) so bind targets can be created
        # under the masked home.
        ProtectSystem = "strict";
        ProtectHome = lib.mkForce "tmpfs";
        # Leading "-" → systemd ignores a missing source rather than failing.
        BindPaths = lib.optional (cfg.vaultDir != null) "-${cfg.vaultDir}/_inbox/nightly_builds";
        BindReadOnlyPaths =
          (lib.optional (cfg.vaultDir != null) "-${cfg.vaultDir}/runs")
          ++ (lib.optional (cfg.srGauntletDir != null) "-${cfg.srGauntletDir}/investigations");
        PrivateTmp = true;
      };
    };
  };
}
