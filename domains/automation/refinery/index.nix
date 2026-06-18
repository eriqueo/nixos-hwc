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
    nativeBuildInputs = [ pkgs.esbuild pkgs.makeWrapper ];
    dontNpmBuild = true; # we don't need tsc output, just the bundle
    # Two entry points, both esbuild-bundled the same way (CJS, deps inlined):
    #   server.js          — the :8060 HTTP board shell (serve.ts)
    #   morning-review.js  — the morning PR-review CLI (cli/morning-review.ts)
    # esbuild resolves the engine's `.js`-specifier imports to the `.ts` sources,
    # so both bundles are self-contained and need only nodejs at runtime.
    # A `refinery-morning-review` wrapper in $out/bin makes the CLI runnable from
    # a systemd unit (the nightly-builds-review.service) without hardcoding the
    # node/bundle paths in the unit.
    installPhase = ''
      runHook preInstall
      mkdir -p $out $out/bin
      esbuild src/shells/serve.ts \
        --bundle --platform=node --format=cjs \
        --outfile=$out/server.js
      esbuild src/cli/morning-review.ts \
        --bundle --platform=node --format=cjs \
        --outfile=$out/morning-review.js
      makeWrapper ${pkgs.nodejs}/bin/node $out/bin/refinery-morning-review \
        --add-flags "$out/morning-review.js"
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

    # Read-only handle to the built engine package. The board service consumes it
    # directly; OTHER domains (nightly-builds' morning-review pass) reference
    # `${config.hwc.automation.refinery.package}/bin/refinery-morning-review`
    # rather than rebuilding the engine — one bundle, one npmDepsHash, no
    # duplication. Always set (independent of `enable`) so the morning-review
    # pass can run even if the board itself is disabled on a host.
    package = lib.mkOption {
      type = lib.types.package;
      default = board;
      readOnly = true;
      description = "The built refinery engine package (board server.js + refinery-morning-review CLI).";
    };

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
          # The Run button / write-spec effector drops developed specs here.
          "REFINERY_SCRATCH_DIR=/var/lib/refinery/specs"
          # "▶ Run now" / IMMEDIATE mode drops a <goal> request file here; the
          # nightly-builds-runnow path unit (domains/automation/nightly-builds)
          # drains it and runs run.sh scoped to that project. Under the writable
          # StateDirectory, so the hardened board can write it without a bind.
          "REFINERY_RUNNOW_SPOOL=/var/lib/refinery/run-now"
          # SR "▶ re-investigate now" drops an <srId> request file here; the
          # sr-gauntlet-runnow path unit (domains/automation/sr-gauntlet) drains
          # it and runs `run.sh --id <srId>`. Also under the StateDirectory.
          "REFINERY_SR_RUNNOW_SPOOL=/var/lib/refinery/sr-run-now"
          "REFINERY_TRIAGE_PROVIDER=${cfg.triageProvider}"
          # claude-cli triage shells out to headless `claude`, which reads the
          # Claude subscription creds from $HOME/.claude (bound read-only below).
          "HOME=${paths.user.home}"
        ] ++ lib.optional (cfg.claudeBin != null) "REFINERY_CLAUDE_BIN=${cfg.claudeBin}"
          ++ lib.optional (cfg.vaultDir != null) "REFINERY_VAULT_DIR=${cfg.vaultDir}"
          ++ lib.optional (cfg.srGauntletDir != null) "REFINERY_SR_GAUNTLET_DIR=${cfg.srGauntletDir}";
        Restart = "on-failure";
        RestartSec = 5;
        # State in /var/lib/refinery (StateDirectory). Home is masked (tmpfs);
        # only the exact paths the board touches are bound back:
        #   - vault _inbox/nightly_builds: READ-WRITE (queue/unqueue flips card status)
        #   - vault runs/ + sr_gauntlet investigations/: READ-ONLY (mirror + REPORTs)
        #   - ~/.claude + ~/.claude.json: READ-ONLY (claude-cli triage creds)
        # ProtectHome MUST be "tmpfs" (not true) so bind targets can be created
        # under the masked home.
        ProtectSystem = "strict";
        ProtectHome = lib.mkForce "tmpfs";
        # Leading "-" → systemd ignores a missing source rather than failing.
        BindPaths = lib.optional (cfg.vaultDir != null) "-${cfg.vaultDir}/_inbox/nightly_builds";
        BindReadOnlyPaths =
          (lib.optional (cfg.vaultDir != null) "-${cfg.vaultDir}/runs")
          ++ (lib.optional (cfg.srGauntletDir != null) "-${cfg.srGauntletDir}/investigations")
          # claude-cli triage authenticates with Eric's Claude subscription (no
          # API key). Bind ~/.claude (creds + config) READ-ONLY back over the
          # masked home — the host refreshes the OAuth token in place and the dir
          # bind reflects it, so the service never needs write access. Only bound
          # when the triage provider actually needs it.
          ++ (lib.optionals (cfg.triageProvider == "claude-cli") [
               "-${paths.user.home}/.claude"
               "-${paths.user.home}/.claude.json"
             ]);
        PrivateTmp = true;
      };
    };
  };
}
