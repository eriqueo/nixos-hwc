# nixos-hwc/flake.nix
#
# Flake: HWC NixOS Configuration (Roles Architecture)
# Single source of truth for the fleet: the `machines` registry maps each
# machine to a channel + role list. Glue resolves roles to
# profiles/<role>/{sys,home}.nix halves; machines/<m>/ holds hardware +
# genuine one-offs only.
#
# DEPENDENCIES (Upstream):
#   - nixpkgs (nixos-unstable), nixpkgs-stable (26.05)
#   - home-manager / home-manager-stable (follow their nixpkgs)
#   - agenix / agenix-stable (follow their nixpkgs)
#
# OUTPUTS (generated from the machines registry):
#   - nixosConfigurations.hwc-<m>        (all machines)
#   - homeConfigurations."eric@hwc-<m>"  (all machines, standalone HM lane)
#
# USAGE:
#   sudo nixos-rebuild switch --flake .#hwc-<machine>
#   home-manager switch --flake .#eric@hwc-<machine>   (alias: hms)

{
  #============================================================================
  # INPUTS - Pin sources
  #============================================================================
  description = "HWC NixOS Configuration - Modular Architecture";

  inputs = {
    meals = { url = "github:eriqueo/meals"; inputs.nixpkgs.follows = "nixpkgs"; };
    # Fleet map UI and read-only capture tools have their own app lifecycle.
    fleet-map = { url = "github:eriqueo/fleet-map"; flake = false; };

    # Ingest code deploys with the system generation, never from a timer pull.
    brainvec = { url = "github:eriqueo/brainvec"; flake = false; };
    refinery = { url = "github:eriqueo/refinery"; flake = false; };
    # Tether: iPhone messages over Bluetooth for the laptop (domains/home/apps/tether).
    # Its nixpkgs is unused: the module builds the package with ours.
    tether = {
      url = "github:zackb/tether";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    screenshot-renamer = {
      url = "github:eriqueo/screenshot-renamer";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    nixpkgs.url         = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url  = "github:NixOS/nixpkgs/nixos-26.05";
    # TS-2026-011 needs Tailscale >= 1.102.3; stable 26.05 has 1.98.10.
    # Remove this temporary pin when both Nixpkgs inputs provide >= 1.102.3.
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/4975466d324710c576dc11ad614684e6bd8cad8e";

    # Static agent policy and adapters. Mutable memories and the mistakes
    # ledger live in ~/800_agents/state and never enter this Nix input.
    agent-harness = {
      url = "github:eriqueo/claude-config";
      flake = false;
    };
    # Third-party Agent Skills adopted into the one shared skill set
    # (hwc.home.apps.agent-harness.adoptedSkills). A bump is a skill diff to read.
    cloudflare-skills = {
      url = "github:cloudflare/skills";
      flake = false;
    };

    # System One owns the typed Laya mail-classifier runtime.
    system-one = {
      url = "github:eriqueo/system-one";
      flake = false;
    };

    nixvirt = {
        url = "github:AshleyYakeley/NixVirt";
        inputs.nixpkgs.follows = "nixpkgs";
      };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-stable = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # NOT a duplicate of `agenix`: same source, but follows nixpkgs-stable so
    # the server's agenix CLI/module deps stay on the stable channel.
    agenix-stable = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    codex = {
      url = "github:openai/codex?ref=rust-v0.101.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-cowork = {
      # Cowork-capable Claude Desktop for Linux. Replaces aaddrick's
      # claude-desktop-debian, whose buildFHSEnv wrapper left Electron's
      # main-process networking dead inside the sandbox (net::ERR_FAILED on
      # OAuth) — chat worked via the renderer's own Chromium stack, but Cowork's
      # main-process OAuth could never start a session. This port takes a
      # different approach: it extracts the macOS app, stubs the macOS-native
      # modules (@ant/claude-swift, @ant/claude-native) in JS, translates VM
      # /sessions paths to host paths in-process, and runs Claude Code directly
      # under bubblewrap (no VM, no FHS wrapper) against nixpkgs electron_41.
      # Research preview — may need a version bump when Claude Desktop updates.
      url = "github:johnzfitch/claude-cowork-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # INVARIANT (all 600_apps app inputs below): `github:` only — NEVER git+file/
    # path. Their checkouts must be single `origin → git@github.com:eriqueo/<name>`
    # on every machine (no local-hub remotes, no stray ~/git/<app>.git hubs).
    # Enforced by ~/600_apps/productivity-scripts/repo-remote-audit.sh (run on
    # laptop AND server). See memory `repo-remote-invariant`.
    #
    # Owned Voxtype fork. App code is published to the shared private remote
    # before this input is locked and the desktop is switched.
    hwc-dictation = {
      url = "github:eriqueo/hwc-dictation?ref=hwc/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # todui — standalone VTODO task TUI (todoman-free, own engine). Sourced from a
    # SHARED REMOTE (private GitHub repo), NOT a local clone: a github: input pins a
    # rev that exists on every machine, so it can't ghost-rev like the old
    # git+file:///600_apps clone did. Ship a change: push to eriqueo/todui →
    # `nix flake update todui` → rebuild. Iterate live via the repo's devShell
    # (`nix develop` + `python -m todui`) — no rebuild to test code. Private fetch
    # uses the github-flake-token (agenix, root-readable, in nix.extraOptions).
    # See memory feedback_app_dev_build_pattern.
    todui = {
      url = "github:eriqueo/todui";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # courier — our iPhone messages app over tetherd (domains/home/apps/courier).
    # Same shared-remote model as todui: private github: input, never git+file.
    courier = {
      url = "github:eriqueo/courier";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # vectorcraft — our fork of storytold/vectorcraft (domains/home/apps/vectorcraft),
    # tailored for GIS map finishing. hwc/main carries the flake and our changes;
    # the fork's main tracks upstream. Ship: push hwc/main → `nix flake update vectorcraft`.
    vectorcraft = {
      url = "github:eriqueo/vectorcraft?ref=hwc/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # khalt — forked khal/ikhal calendar TUI (zoomable agenda/quarter/month views +
    # space-leader keybindings). Same shared-remote model as todui: private GitHub
    # repo via a github: input (no local-clone ghost-rev). Ship: push to
    # eriqueo/khalt → `nix flake update khalt` → rebuild. Iterate via its devShell.
    khalt = {
      url = "github:eriqueo/khalt";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # workbench — Textual TUI ops host, zellij-orchestrated, consumed by
    # domains/home/apps/workbench. Same shared-remote model as todui/khalt: private
    # GitHub repo via a github: input (no local-clone ghost-rev). Ship: push to
    # eriqueo/workbench → `nix flake update workbench` → rebuild. Iterate via its devShell.
    workbench = {
      url = "github:eriqueo/workbench";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Firefly Explorer — full-history recurring-payment review UI and guarded
    # edit API. Private first-party app, pinned by flake.lock like the other
    # shared app inputs; the server module consumes its default package.
    pnc-statement-pipeline = {
      url = "github:eriqueo/pnc-statement-pipeline";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    # aerc — forked notmuch mail TUI (which-key leader popup + msglist column
    # headers, config-gated default-off). Same shared-remote model as
    # todui/khalt/workbench: private GitHub repo via a github: input. The flake
    # packages via overrideAttrs on nixpkgs' aerc @ 0.21.0, so filters/stylesets/
    # man pages come out identical. Ship: push to eriqueo/aerc →
    # `nix flake update aerc` → rebuild. Iterate via its devShell (nix develop →
    # make → ./aerc), no rebuild to test code.
    # Pinned to /main explicitly: eriqueo/aerc is a true GitHub fork of
    # rjarry/aerc, so its default branch is `master` (upstream lineage). Our
    # flake + feature work lives on `main`.
    aerc = {
      url = "github:eriqueo/aerc/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # pave-query-builder — trap-safe Pave (JobTread API) query builder, TUI + CLI,
    # consumed by domains/home/apps/pave-query-builder. Same shared-remote model as
    # todui/khalt/workbench: private GitHub repo via a github: input. Ship: push to
    # eriqueo/pave-query-builder → `nix flake update pave-query-builder` → rebuild.
    # Iterate via its devShell (`nix develop` + `python -m pave`).
    pave-query-builder = {
      url = "github:eriqueo/pave-query-builder";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # tetro — terminal tetromino-stacking game (TUI), consumed by
    # domains/home/apps/tetro. UPSTREAM third-party repo (Strophox/tetro-tui), not
    # a first-party eriqueo app, so there is no local-clone build pattern here —
    # the flake's own packages.<system>.default builds the binary via rust-overlay.
    # Bump: `nix flake update tetro` → rebuild.
    tetro = {
      url = "github:Strophox/tetro-tui";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # bloxels-cv — CV pipeline: phone photo of the printed 13×13 Bloxels grid →
    # classified color matrix (grid.json + debug.png). Consumed by
    # domains/server/services/bloxels-cv (systemd path watcher on the phone's
    # inbox-mobile Syncthing share). Same shared-remote model as
    # todui/khalt/workbench: private GitHub repo via a github: input. Ship: push
    # to eriqueo/bloxels-cv → `nix flake update bloxels-cv` → rebuild. Iterate
    # via its devShell (`nix develop` + `python test_pipeline.py`).
    bloxels-cv = {
      url = "github:eriqueo/bloxels-cv";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # zellij-which — custom zellij plugin (Rust→wasm): the meta-layer which-key
    # card. Its own private repo + flake (rust-overlay wasm toolchain), consumed
    # by domains/home/apps/zellij as the floating meta menu. Ship: push to
    # eriqueo/zellij-which → `nix flake update zellij-which` → rebuild.
    zellij-which = {
      url = "github:eriqueo/zellij-which";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  #============================================================================
  # OUTPUTS - Define systems; delegate implementation to machine configs
  #============================================================================

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, home-manager-stable, agenix, agenix-stable, ... }@inputs:
  let
    system = "x86_64-linux";

    # Suppress upstream nixpkgs deprecation warnings for renamed pkgs attributes.
    # pkgs.hostPlatform and pkgs.system are warnAlias'd in aliases.nix; upstream
    # packages still use them, firing 4+ warnings per build.  Overriding them
    # here replaces the warnAlias thunk with the plain value so no warn fires.
    silenceDeprecatedAliases = final: prev: {
      hostPlatform = prev.stdenv.hostPlatform;
      system       = prev.stdenv.hostPlatform.system;
    };

    # Add the overlay here - this is the safest approach
    mkPkgs = system: nixpkgsInput: extraOverlays:
      import nixpkgsInput {
        inherit system;
        config = {
          allowUnfree = true;
          # Accept NVIDIA license for legacy driver support
          nvidia.acceptLicense = true;
          # Allow insecure qtwebengine for jellyfin-media-player
          permittedInsecurePackages = [
            "qtwebengine-5.15.19"
          ];
        };
        overlays = [
          silenceDeprecatedAliases
          gitCleanupOverlay
          pandasStubsOverlay   # TEMP: skip pandas-stubs tests (upstream pytest-9.1.1 breakage)
          nodejsSecurityOverlay  # TEMP: Node Oct-2026 security release + brotli CVE fix
          # Expose the cowork-capable Claude Desktop package (package-only flake,
          # no overlay of its own) under pkgs for the home app module.
          (final: prev: {
            claude-cowork-linux =
              inputs.claude-cowork.packages.${prev.stdenv.hostPlatform.system}.default;
          })
        ] ++ extraOverlays;
      };

    # Server-specific overlay for CUDA support
    # Uses cache.nixos-cuda.org for pre-built binaries (avoid 8+ hour local builds)
    serverOverlay = final: prev: {
      # Let nixpkgs.config.cudaSupport handle CUDA globally
      # No per-package overrides needed with binary cache
    };

    # Claude Code overlay - backport from unstable to stable
    claudeCodeOverlay = import ./overlays/claude-code.nix { nixpkgs-unstable = nixpkgs; };

    # Cloudflared overlay - backport from unstable to stable
    # Stable 26.05 lags upstream cloudflared releases; the daemon needs to track
    # current Cloudflare edge protocol to keep the tunnel healthy.
    cloudflaredOverlay = import ./overlays/cloudflared.nix { nixpkgs-unstable = nixpkgs; };

    tailscaleOverlay = final: prev: {
      tailscale = inputs.nixpkgs-tailscale.legacyPackages.${prev.stdenv.hostPlatform.system}.tailscale;
    };

    # Ghidra overlay — TEMPORARY (tracked). REA accepts only Ghidra 12.1.x;
    # stable 26.05 has 12.0.4. See the file header for the removal condition.
    ghidraOverlay = import ./overlays/ghidra.nix { nixpkgs-unstable = nixpkgs; };

    # pandas-stubs overlay — TEMPORARY (tracked). Skips pandas-stubs' failing test
    # phase on the 2026-07-25 nixpkgs (upstream pytest-9.1.1 deprecation-as-error
    # that otherwise fails the whole HM user-environment). See the file header for
    # the removal condition.
    pandasStubsOverlay = import ./overlays/pandas-stubs.nix;
    # TEMP: native Git pack cleanup on cancellation; removal test in the overlay.
    gitCleanupOverlay = import ./overlays/git.nix;
    # Node.js security overlay — TEMPORARY (tracked). Node 24.22.1 / 22.23.4
    # with brotli CVE-2026-111497 fix, ahead of both channels. See the file
    # header for the removal condition.
    nodejsSecurityOverlay = import ./overlays/nodejs-security.nix;

    # TEMPORARY: server modules select corrected runtimes without feeding them
    # back into Nixpkgs' package fixed point (which rebuilds Chromium/CUDA torch).
    # Remove with nodejs-security.nix after the pinned packages pass its manifest.
    mkNodeRuntimeScope = original:
      let
        buildPkgs = import original.path {
          inherit (original) system config;
          overlays = map (overlay: final: prev:
            let result = overlay final prev; in
            if result ? nodejsRuntime_22 && result ? nodejsRuntime_24 then
              builtins.removeAttrs result [ "nodejs-slim_22" "nodejs-slim_24" ]
            else result) original.overlays;
        };
        runtime22 = buildPkgs.nodejsRuntime_22;
        runtime24 = buildPkgs.nodejsRuntime_24;
        defaultRuntime = { "22" = runtime22; "24" = runtime24; }.${lib.versions.major buildPkgs.nodejs.version};
      in {
        inherit buildPkgs;
        pkgs = buildPkgs // {
          nodejs = defaultRuntime;
          nodejs_22 = runtime22;
          nodejs_24 = runtime24;
          nodejs-slim = defaultRuntime;
          nodejs-slim_22 = runtime22;
          nodejs-slim_24 = runtime24;
        };
      };

    # Pkgs helper with optional overlays (server uses this)
    # CUDA enabled - using cache.nixos-cuda.org for pre-built binaries
    mkPkgsWithOverlays = system: nixpkgsInput: extraOverlays:
      import nixpkgsInput {
        inherit system;
        overlays = [ silenceDeprecatedAliases gitCleanupOverlay pandasStubsOverlay nodejsSecurityOverlay claudeCodeOverlay cloudflaredOverlay ] ++ extraOverlays;
        config = {
          allowUnfree = true;
          nvidia.acceptLicense = true;
          cudaSupport = true;  # Binary cache should provide pre-built CUDA packages
          permittedInsecurePackages = [
            "qtwebengine-5.15.19"
          ];
        };
      };

    # CHARTER v9.0: Use unstable for laptop (latest features), stable for server (production stability)
    pkgs = mkPkgs system nixpkgs [];
    pkgs-laptop = mkPkgs system nixpkgs [ tailscaleOverlay ];

    # Stable package set with the temporary Tailscale security update.
    pkgs-stable = mkPkgs system nixpkgs-stable [ tailscaleOverlay ghidraOverlay ];

    # pkgs-stable with CUDA overlay for server (Immich ML GPU acceleration)
    pkgs-stable-cuda = mkPkgsWithOverlays system nixpkgs-stable [ serverOverlay tailscaleOverlay ghidraOverlay ];

    serverRuntimeScope = mkNodeRuntimeScope pkgs-stable;
    serverCudaRuntimeScope = mkNodeRuntimeScope pkgs-stable-cuda;

    # Firestick is the one aarch64 machine
    pkgs-firestick = mkPkgs "aarch64-linux" nixpkgs [];

    lib = nixpkgs.lib;

    #========================================================================
    # MACHINE REGISTRY — single source of truth for the fleet
    #========================================================================
    # channel picks the nixpkgs/home-manager/agenix flavor; roles resolve to
    # profiles/<role>/{sys,home}.nix lane halves (a half that does not exist
    # is silently skipped). The pkgs fields name the EXISTING per-machine
    # package sets defined above — the overlay story stays explicit here
    # rather than being derived from `channel`.
    machines = {
      home = {
        channel   = "stable";
        roles     = [ "base" "server" ];
        nixosPkgs = serverCudaRuntimeScope.pkgs; # CUDA build packages, explicit native Node
        hmPkgs    = serverRuntimeScope.pkgs;     # standalone HM stays plain stable
        scopedNodeRuntime = true;
      };
      work = {
        channel   = "stable";
        roles     = [ "base" "server" "mail" "business" "monitoring" ];
        nixosPkgs = serverRuntimeScope.pkgs;
        hmPkgs    = serverRuntimeScope.pkgs;
        scopedNodeRuntime = true;
      };
      laptop = {
        channel   = "unstable";
        roles     = [ "base" "desktop" ];
        nixosPkgs = pkgs-laptop;
        hmPkgs    = pkgs-laptop;
        hmBackupExt  = "hm-bak";
        extraModules = [ inputs.nixvirt.nixosModules.default ];
      };
      xps = {
        channel   = "stable";
        roles     = [ "base" "desktop" "server" ];
        nixosPkgs = pkgs-stable;
        hmPkgs    = pkgs-stable;
      };
      kids = {
        channel   = "unstable";
        roles     = [ "base" "gaming" ];
        nixosPkgs = pkgs;
        hmPkgs    = pkgs;
      };
      firestick = {
        system    = "aarch64-linux";
        channel   = "unstable";
        roles     = [ "base" "appliance" ];
        nixosPkgs = pkgs-firestick;
        hmPkgs    = pkgs-firestick;
      };
    };

    # channel → toolchain flavor
    channels = {
      stable = {
        nixosSystem = nixpkgs-stable.lib.nixosSystem;
        hm          = home-manager-stable;
        agenix      = agenix-stable;
        apiVersion  = "stable";
      };
      unstable = {
        nixosSystem = nixpkgs.lib.nixosSystem;
        hm          = home-manager;
        agenix      = agenix;
        apiVersion  = "unstable";
      };
    };

    # Role → lane halves. Missing halves are skipped (e.g. roles with no HM
    # content have no home.nix; appliance/mail-style roles have one half).
    roleHalves = lane: roles:
      builtins.filter builtins.pathExists
        (map (r: ./profiles + "/${r}/${lane}") roles);

    # Both Home Manager lanes receive the same system-owned values: the capture
    # path, and the Tether package (built once by the system half; without it
    # standalone `hms` dropped the tetherd unit).
    homeSpecialArgs = name: ch:
      let sysConfig = self.nixosConfigurations."hwc-${name}".config; in {
        inherit inputs;
        nixosApiVersion = ch.apiVersion;
        screenshotRoot = lib.attrByPath [ "hwc" "paths" "screenshots" ] null sysConfig;
        tetherPackage =
          if lib.attrByPath [ "hwc" "system" "apps" "tether" "enable" ] false sysConfig
          then sysConfig.hwc.system.apps.tether.package
          else null;
      };

    # NixOS lane: framework modules + role sys halves + machine one-offs +
    # HM-as-module wiring (home halves + machine home.nix as users.eric).
    mkNixos = name: m:
      let
        ch     = channels.${m.channel};
        sysArch = m.system or system;
      in ch.nixosSystem {
        pkgs = m.nixosPkgs;
        specialArgs = {
          inherit inputs;
          nixosApiVersion = ch.apiVersion;
        };
        modules = [
          ({ lib, ... }: {
            nixpkgs.hostPlatform = sysArch;
            # nixpkgs.pkgs is re-extended by the framework, losing a shallow
            # runtime view. Its documented module-argument override preserves it.
            _module.args = lib.optionalAttrs (m.scopedNodeRuntime or false) {
              pkgs = lib.mkForce m.nixosPkgs;
            };
          })
          # Record the git rev the system was built from → /run/current-system/
          # configuration-revision. Feeds the morning-briefing config-drift tile
          # (deployed-vs-HEAD); null on dirty-tree builds, which is itself signal.
          { system.configurationRevision = self.rev or self.dirtyRev or null; }
          ch.agenix.nixosModules.default
        ] ++ (m.extraModules or [ ]) ++ [
          ch.hm.nixosModules.home-manager
        ] ++ roleHalves "sys.nix" m.roles ++ [
          (./machines + "/${name}/config.nix")
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = m.hmBackupExt or "backup";
              users.eric.imports =
                roleHalves "home.nix" m.roles
                ++ [ (./machines + "/${name}/home.nix") ];
              extraSpecialArgs = homeSpecialArgs name ch;
            };
          }
        ];
      };

    # HM lane (standalone, `hms`): same home halves + machine home.nix,
    # built directly so user-level rebuilds skip the system eval (~5-10s).
    mkHome = name: m:
      let ch = channels.${m.channel}; in
      ch.hm.lib.homeManagerConfiguration {
        pkgs = m.hmPkgs;
        extraSpecialArgs = homeSpecialArgs name ch;
        modules =
          roleHalves "home.nix" m.roles
          ++ [
            (./machines + "/${name}/home.nix")
            { home.username = "eric"; home.homeDirectory = "/home/eric"; }
            ({ lib, ... }: {
              _module.args = lib.optionalAttrs (m.scopedNodeRuntime or false) {
                pkgs = lib.mkForce m.hmPkgs;
              };
            })
          ];
      };

    # Helper: hwc-graph package
    hwc-graph-pkg = pkgs.writeScriptBin "hwc-graph" ''
      #!${pkgs.python3}/bin/python3
      import sys
      import os

      # Add the graph directory to Python path
      graph_dir = "${self}/workspace/nixos-dev/graph"
      sys.path.insert(0, graph_dir)

      # Change to repo root for scanning
      os.chdir("${self}")

      # Import and run main
      from hwc_graph import main
      main()
    '';

    keymapDocs = pkgs.writeText "KEYMAP.md" (import ./domains/home/keymap/parts/to-docs.nix {
      inherit lib;
      grammar = import ./domains/home/keymap/grammar.nix { inherit lib; };
    });
    keymapDocsApp = pkgs.writeShellApplication {
      name = "keymap-docs";
      runtimeInputs = [ pkgs.python3 ];
      text = ''
        python3 - "$@" <<'PY'
        import argparse, pathlib, sys
        parser = argparse.ArgumentParser(description="Generate keymap docs in the current checkout")
        parser.add_argument("--brain", type=pathlib.Path)
        args = parser.parse_args()
        output = pathlib.Path("domains/home/keymap/KEYMAP.md")
        if not output.parent.is_dir() or not pathlib.Path("flake.nix").is_file():
            sys.exit("keymap-docs: run from the checkout root")
        rendered = pathlib.Path("${keymapDocs}").read_bytes()
        if args.brain:
            if args.brain.resolve() == output.resolve():
                sys.exit("keymap-docs: brain target must differ from KEYMAP.md")
            original = args.brain.read_bytes()
            begin, end = b"<!-- keymap:begin -->", b"<!-- keymap:end -->"
            lines = original.splitlines(keepends=True)
            starts = [i for i, line in enumerate(lines) if line.rstrip(b"\r\n") == begin]
            ends = [i for i, line in enumerate(lines) if line.rstrip(b"\r\n") == end]
            if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
                sys.exit("keymap-docs: expected one ordered pair of exact keymap:begin/keymap:end marker lines")
            if not lines[starts[0]].endswith(b"\n"):
                sys.exit("keymap-docs: begin marker must end with a newline")
            replacement = b"".join(lines[:starts[0]+1]) + rendered + b"".join(lines[ends[0]:])
        output.write_bytes(rendered)
        if args.brain:
            args.brain.write_bytes(replacement)
        PY
      '';
    };
  in {
    # Apps - CLI utilities
    apps.${system} = {
      keymap-docs = { type = "app"; program = "${keymapDocsApp}/bin/keymap-docs"; };
      hwc-graph = {
        type = "app";
        program = "${hwc-graph-pkg}/bin/hwc-graph";
        meta = {
          description = "NixOS HWC dependency graph CLI";
          license = lib.licenses.mit;
        };
      };
    };

    # Packages - Make hwc-graph available as a package too
    packages.${system} = {
      hwc-graph = hwc-graph-pkg;
    };

    #========================================================================
    # CHECKS — Charter §3.1 lints wired into `nix flake check` (§3.3, v12.3).
    # Each check runs a "must return empty" lint over the flake source and
    # fails the build on any hit. Only laws whose lints are currently clean
    # are wired (green on day one); Laws 3/5/12/13 join as their backlogs
    # are burned down (see workspace/plans/2026-07-05-phase-plan-handoff.md).
    #========================================================================
    checks.${system} = let
      keymapGrammar = import ./domains/home/keymap/grammar.nix { inherit lib; };
      keymapValidator = pkgs.writeText "keymap-validator.py" ''
        import json, pathlib, sys, tomllib

        def validate(chords, groups, space=False, legacy_help=False):
            seen = set()
            for chord in chords:
                chord = tuple(chord)
                assert chord and all(chord), f"empty chord: {chord}"
                assert chord not in seen, f"duplicate chord: {chord}"
                seen.add(chord)
                if not space or chord[0] == "<Space>":
                    offset = 1 if space else 0
                    if not (legacy_help and chord == ("?",)):
                        assert len(chord) > offset and chord[offset] in groups, f"unknown group: {chord}"
            for chord in seen:
                for length in range(1, len(chord)):
                    assert chord[:length] not in seen, f"prefix: {chord[:length]} shadows {chord}"

        def grammar_contexts(grammar):
            apps = set(grammar.get("apps", {})) | set(grammar.get("major", {}))
            apps |= {app for row in grammar["shared"] for app in row.get("cmd", {})}
            for app in sorted(apps - {"aerc"}):
                rows = [r for r in grammar["shared"] if app in r.get("cmd", {})]
                rows += grammar.get("apps", {}).get(app, [])
                chords = [r["keys"].split(" ") for r in rows]
                major = grammar.get("major", {}).get(app, [])
                if isinstance(major, list):
                    chords += [["m"] + r["keys"].split(" ") for r in major]
                yield app, chords
            # Use the production adapter's context selection, including global rows.
            for context, scopes in {
                "messages": {"global", "account", "message"},
                "view": {"global", "account", "message", "view", "closable"},
                "terminal": {"global", "closable"},
            }.items():
                yield "aerc/" + context, [r["keys"].split(" ") for r in grammar["aerc"]["bindings"]
                                           if r["scope"] in scopes]

        def self_test(groups):
            for fixture in ([["invalid", "x"]], [["g", "x"], ["g", "x"]],
                            [["g", "x"], ["g", "x", "y"]]):
                try:
                    validate(fixture, groups)
                except AssertionError:
                    pass
                else:
                    raise AssertionError(f"invalid fixture accepted: {fixture}")
            validate([["g", "x"], ["f", "x"]], groups)
            for fixture in ([["<Space>", "invalid", "x"]], [["y"], ["y", "y"]],
                            [["j"], ["j"]]):
                try:
                    validate(fixture, groups, space=True)
                except AssertionError:
                    pass
                else:
                    raise AssertionError(f"invalid TOML chord fixture accepted: {fixture}")
            print("seeded group, duplicate and prefix violations rejected")

        grammar = json.loads(pathlib.Path(sys.argv[1]).read_text())
        groups = grammar["groups"]
        self_test(groups)
        if len(sys.argv) == 2:
            # Check declarations even when a row has no current consumer.
            for row in grammar["shared"] + [r for rows in grammar.get("apps", {}).values() for r in rows]:
                validate([row["keys"].split(" ")], groups)
            for context, chords in grammar_contexts(grammar):
                try:
                    # Aerc's existing Space ? help is explicitly outside its group table
                    # (to-aerc excludes it from activeGroups). Keep it until regrouping.
                    validate(chords, groups, legacy_help=context.startswith("aerc/"))
                except AssertionError as error:
                    raise AssertionError(f"{context}: {error}") from error
                print(f"{context}: {len(chords)} grammar chords pass")
        else:
            data = tomllib.loads(pathlib.Path(sys.argv[2]).read_text())
            for context, section in data.items():
                chords = [r["on"] for field in ("prepend_keymap", "keymap", "append_keymap")
                          for r in section.get(field, [])]
                validate(chords, groups, space=True)
                assert all("run" in r for r in section.get("prepend_keymap", [])), context
                print(f"{context}: {len(chords)} TOML chords pass")
            # A grammar command must survive the actual Home Manager wiring.
            expected = {tuple(["<Space>"] + r["keys"].split(" "))
                        for r in grammar["shared"] + grammar.get("apps", {}).get("yazi", [])
                        if "yazi" in r.get("cmd", {})}
            actual = {tuple(r["on"]) for r in data["mgr"]["prepend_keymap"] if r["on"][0] == "<Space>"}
            assert actual == expected, f"Space wiring mismatch: missing {expected - actual}, extra {actual - expected}"
            manager = data["mgr"]["prepend_keymap"]
            space_commands = {r["run"] for r in manager if r["on"][0] == "<Space>"}
            native_commands = {r["run"] for r in manager if r["on"][0] != "<Space>"}
            assert native_commands <= space_commands, f"manager actions without Space path: {native_commands - space_commands}"
      '';
      keymapGrammarFile = pkgs.writeText "keymap-grammar.json" (builtins.toJSON keymapGrammar);
      # Resolve mail checks from the capability owner. The service split moved
      # mail off hwc-home; a literal host left the checks with no subject.
      mailMachines = lib.filterAttrs (_: machine: lib.elem "mail" machine.roles) machines;
      mailHost = assert lib.assertMsg (lib.length (builtins.attrNames mailMachines) == 1)
        "mail checks: expected one mail-role owner";
        "hwc-${builtins.head (builtins.attrNames mailMachines)}";
      # Runtime mail controls depend on osConfig; inspect the deployed integrated
      # HM configuration rather than the standalone evaluation without that port.
      mailHome = self.nixosConfigurations.${mailHost}.config.home-manager.users.eric;
      mkCharterLint = name: cmds: pkgs.runCommand "charter-${name}" {
        nativeBuildInputs = [ pkgs.ripgrep pkgs.fd ];
      } ''
        cd ${self}
        fail=0
        ${lib.concatMapStringsSep "\n" (cmd: ''
          hits=$(${cmd} || true)
          if [ -n "$hits" ]; then
            echo "CHARTER LINT ${name} FAILED — must return empty:" >&2
            echo "  \$ ${lib.escapeShellArg cmd}" >&2
            echo "$hits" >&2
            fail=1
          fi
        '') cmds}
        [ "$fail" = 0 ] || exit 1
        touch $out
      '';
    in {
      node-runtime-wiring =
        let
          server = host: self.nixosConfigurations."hwc-${host}";
          runtime22 = serverRuntimeScope.pkgs.nodejsRuntime_22;
          runtime24 = serverRuntimeScope.pkgs.nodejsRuntime_24;
          scope = host: if host == "home" then serverCudaRuntimeScope else serverRuntimeScope;
          hasRuntime = packages: lib.any (package: package.outPath == runtime24.outPath) packages;
          hostValid = host:
            let system = server host; baseline = (scope host).buildPkgs; in
            system.pkgs.nodejs.outPath == runtime24.outPath
            && system.pkgs.nodejs_22.outPath == runtime22.outPath
            && system.pkgs.chromium.browser.drvPath == baseline.chromium.browser.drvPath
            && system.pkgs.python3Packages.torch.drvPath == baseline.python3Packages.torch.drvPath
            && system.pkgs.python3Packages.torchvision.drvPath == baseline.python3Packages.torchvision.drvPath
            && hasRuntime system.config.home-manager.users.eric.hwc.home.apps.t3code.serve.packages
            && hasRuntime self.homeConfigurations."eric@hwc-${host}".config.hwc.home.apps.t3code.serve.packages;
          commandUsesRuntime = unit:
            lib.hasPrefix "${runtime22}/bin/node "
              (server "work").config.systemd.services.${unit}.serviceConfig.ExecStart;
        in
        assert lib.assertMsg (lib.all hostValid [ "work" "home" ])
          "Server Node runtime selection, Home Manager parity or no-cascade contract failed";
        assert lib.assertMsg (lib.all commandUsesRuntime [ "hwc-notify" "hwc-sys-mcp" "heartwood-cms" "hwc-leads" ])
          "Native Node22 service command did not select the corrected runtime";
        pkgs.runCommand "node-runtime-wiring" { } ''
          touch "$out"
        '';

      screenshot-renamer = let
        c = self.nixosConfigurations.hwc-home.config;
        worker = c.systemd.services.screenshot-renamer.serviceConfig;
        laptop = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
        binds = laptop.wayland.windowManager.hyprland.settings.bind;
        pi = pkgs.callPackage ./domains/home/apps/pi/parts/package.nix {};
        python = pkgs.python3.withPackages (ps: [ ps.pillow ]);
      in
      assert lib.assertMsg (lib.length (lib.filter (host: lib.attrByPath [ "hwc" "automation" "screenshotRenamer" "enable" ] false host.config)
          (lib.attrValues self.nixosConfigurations)) == 1
        && c.hwc.automation.screenshotRenamer.enable
        && c.hwc.automation.screenshotRenamer.mode == "apply"
        && c.hwc.automation.screenshotRenamer.operatorReview
        && lib.elem "${c.hwc.paths.user.inbox}/screenshots" worker.BindPaths
        && !(lib.elem "${c.hwc.paths.user.inbox}/screenshots" worker.BindReadOnlyPaths)
        && lib.hasInfix " dispatch" worker.ExecStart
        && !(c.systemd.timers ? screenshot-renamer)
        && c.systemd.paths.screenshot-renamer.pathConfig.PathChanged == [ "${c.hwc.paths.user.inbox}/screenshots" "${c.hwc.paths.user.inbox}/screenshots/.screenshot-policy" ]
        && worker.Restart == "no"
        && worker.RestartForceExitStatus == [ 75 ]
        && worker.RestartSec == "30s"
        && lib.elem "${c.hwc.paths.user.inbox}/screenshots" c.services.borgbackup.jobs.hwc-backup.paths
        && lib.elem "${c.hwc.paths.state}/screenshot-renamer/work-*" c.services.borgbackup.jobs.hwc-backup.exclude
        && lib.elem "${c.hwc.paths.state}/screenshot-renamer/ledger.sqlite*" c.services.borgbackup.jobs.hwc-backup.exclude
        && c.systemd.timers.screenshot-renamer-check.wantedBy == [ "timers.target" ]
        && c.systemd.services.screenshot-renamer-check.serviceConfig.BindReadOnlyPaths == []
        && lib.any (b: lib.hasInfix "hwc-screenshot" b && lib.hasInfix "--private" b) binds
        && lib.any (b: lib.hasInfix "hwc-screenshot" b && lib.hasInfix "--private" b)
          self.homeConfigurations."eric@hwc-laptop".config.wayland.windowManager.hyprland.settings.bind)
        "screenshot wiring must apply with explicit operator review, monitoring and capture privacy";
      pkgs.runCommand "screenshot-renamer-contract" {
        nativeBuildInputs = [ python pi pkgs.tesseract ];
      } ''
        export PYTHONDONTWRITEBYTECODE=1
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        cd ${inputs.screenshot-renamer}
        python3 -m unittest -v screenshot_renamer_checks test_worker
        python3 - <<'PY'
        from pathlib import Path
        import dataclasses, tempfile, socket
        from PIL import Image, ImageDraw, ImageFont
        import screenshot_renamer as r
        with tempfile.TemporaryDirectory() as d:
            p = Path(d)
            font = ImageFont.truetype("${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf", 32)
            image = Image.new("RGB", (900, 220), "white")
            ImageDraw.Draw(image).text((20, 35), "Quarterly sales report\nRevenue growth planning", font=font, fill="black")
            image.save(p / "shot.png")
            cfg = r.Config(p, p / "state", owner=socket.gethostname())
            text = r.ocr(cfg, p / "shot.png", p)
            assert "Quarterly sales report" in text, text
        PY
        touch "$out"
      '';

      mqtt-webhook-contract = let
        module = import ./domains/automation/mqtt/index.nix {
          inherit pkgs lib;
          config.hwc = {
            paths.state = "/tmp";
            automation.mqtt = {
              enable = true;
              port = 18884;
              dataDir = "/tmp/mqtt";
              webhookBridge = {
                enable = true;
                topic = "fixture/events";
                eventTypes = [ "end" ];
                webhookUrl = "http://127.0.0.1:18386/capture";
              };
            };
          };
        };
        bridge = module.config.content.systemd.services.mqtt-webhook-bridge.content.serviceConfig.ExecStart;
      in pkgs.runCommand "mqtt-webhook-contract" {
        nativeBuildInputs = [ pkgs.python3 pkgs.mosquitto ];
      } ''
        python3 ${./domains/automation/mqtt/test_bridge.py} ${bridge}
        touch $out
      '';
      frigate-contract = let
        server = self.nixosConfigurations.hwc-home.config;
        frigate = server.hwc.media.frigate;
        fixture = pkgs.writeText "frigate-contract.json" (builtins.toJSON {
          settings = frigate._settings;
          inherit (frigate) port;
          configTemplate = frigate._configTemplate;
          configScript = server.systemd.services.frigate-config.script;
          credentials = server.systemd.services.frigate-config.serviceConfig.LoadCredential;
          inherit (server.systemd.services.podman-frigate) requires restartTriggers;
          inherit (server.virtualisation.oci-containers.containers.frigate) ports volumes extraOptions;
          startupTimeout = server.systemd.services.podman-frigate.serviceConfig.TimeoutStartSec;
          exporterPresent = server.virtualisation.oci-containers.containers ? frigate-exporter;
          scrapes = server.hwc.monitoring.prometheus.scrapeConfigs;
          rules = import ./domains/monitoring/prometheus/parts/alerts.nix { inherit lib; };
          # Exported for the central Prometheus (another host since wave 3).
          configurationRules = server.hwc.monitoring.prometheus.rules;
        });
      in pkgs.runCommand "frigate-contract" {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.onnx p.pillow ])) pkgs.prometheus.cli ];
      } ''
        python3 ${./domains/media/frigate/parts/test_config.py} ${fixture} ${./domains/media/frigate/parts/labelmap.py}
        touch $out
      '';
      # Credential checks use fake secrets; no server or real secret is accessed.
      # Runs on every host that syncs calendar + tasks and pins the rendered
      # wiring: Radicale is the only CalDAV backend, and todoman reads the vdir
      # the tasks pair writes. The server kept a dead iCloud tasks pair (and a
      # todoman path over it) until 2026-09-24 because only the laptop was checked.
      radicale-client-auth = let
        hosts = builtins.attrNames (lib.filterAttrs (_: home:
          lib.attrByPath [ "hwc" "mail" "calendar" "enable" ] false home.config
        ) self.homeConfigurations);
        fixture = pkgs.writeText "radicale-client-config.json" (builtins.toJSON (map (host:
          let home = self.homeConfigurations.${host}.config;
          in {
            inherit host;
            todui = lib.optionalAttrs home.programs.todui.enable {
              command = home.programs.todui.radicale.passwordCommand;
              username = home.programs.todui.radicale.username;
            };
            sync = home.xdg.configFile."vdirsyncer/config".text;
            todoman = home.xdg.configFile."todoman/config.py".text;
          }) hosts));
      in assert lib.assertMsg (hosts != []) "radicale-client-auth: no enabled calendar client";
      pkgs.runCommand "radicale-client-auth" {
        nativeBuildInputs = [ pkgs.python3 pkgs.gawk ];
      } ''
        python3 - ${fixture} <<'PY'
        import configparser, json, pathlib, re, shlex, subprocess, sys
        for cfg in json.loads(pathlib.Path(sys.argv[1]).read_text()):
            host = cfg["host"]
            assert "caldav.icloud.com" not in cfg["sync"], f"{host}: vdirsyncer still syncs iCloud"
            sync = configparser.RawConfigParser()
            sync.read_string(cfg["sync"])
            pairs = sorted(s.split(" ", 1)[1] for s in sync.sections() if s.startswith("pair "))
            assert pairs == ["calendar_radicale", "contacts_radicale", "tasks_radicale"], \
                f"{host}: expected only the three Radicale pairs, got {pairs}"
            tasks_dir = json.loads(sync["storage tasks_radicale_local"]["path"])
            todo_path = re.search(r'^\s*path = "(.*)"$', cfg["todoman"], re.M).group(1)
            assert todo_path == tasks_dir.rstrip("/") + "/*", \
                f"{host}: todoman reads {todo_path}, tasks pair writes {tasks_dir}"
            print(f"{host}: Radicale-only; todoman reads the tasks pair's vdir")
            clients = []
            if cfg["todui"]:
                clients.append(("todui", cfg["todui"]["username"], cfg["todui"]["command"]))
            for name in ("tasks", "calendar", "contacts"):
                section = sync[f"storage {name}_radicale_remote"]
                fetch = json.loads(section["password.fetch"])
                assert fetch.pop(0) == "command"
                clients.append((name, json.loads(section["username"]), fetch))
            users = sorted({user for _, user, _ in clients})
            secret = pathlib.Path("secret fixture'quoted")
            expected = {user: f"fixture:{i}:with spaces" for i, user in enumerate(users)}
            secret.write_text("unrelated:other\n" + "".join(
                f"{user}:{password}\n" for user, password in expected.items()
            ) + "unrelated-last:other-last\n")
            for name, user, command in clients:
                if isinstance(command, str):
                    original = shlex.split(command)[-1]
                    command = command.replace(shlex.quote(original), shlex.quote(str(secret)))
                    result = subprocess.run(command, shell=True, capture_output=True, text=True)
                else:
                    command[-1] = str(secret)
                    result = subprocess.run(command, capture_output=True, text=True)
                assert result.returncode == 0, f"{host} {name}: credential command failed"
                assert result.stdout == expected[user] + "\n", f"{host} {name}: wrong user's password"
                print(f"{host} {name}: selected only its user's complete password")
        PY
        touch $out
      '';

      keymap-docs = pkgs.runCommand "keymap-docs" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
        diff -u ${./domains/home/keymap/KEYMAP.md} ${keymapDocs}
        touch "$out"
      '';

      keymap-grammar = pkgs.runCommand "keymap-grammar" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        python3 ${keymapValidator} ${keymapGrammarFile}
        touch "$out"
      '';

      khalt-keymap = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        appPkgs = inputs.khalt.inputs.nixpkgs.legacyPackages.x86_64-linux;
        python = appPkgs.python3.withPackages (ps: [
          ps.click ps.click-log ps.icalendar ps.urwid ps.pyxdg
          ps.pytz ps.python-dateutil ps.configobj ps.tzlocal
        ]);
        generated = pkgs.writeText "khalt-keymap.json"
          home.xdg.configFile."khalt/keymap.json".text;
        runner = pkgs.writeText "khalt-keymap-check.py" ''
          import copy, importlib.util, json, logging, os, pathlib
          from types import SimpleNamespace
          # Import the real loader without khal's build-generated version.py.
          spec = importlib.util.spec_from_file_location("khalt_leader",
              "${inputs.khalt}/khal/ui/khalt_leader.py")
          leader = importlib.util.module_from_spec(spec)
          spec.loader.exec_module(leader)

          class FailFallback(logging.Handler):
              def emit(self, record):
                  raise AssertionError(record.getMessage())
          leader.logger.addHandler(FailFallback())
          view = SimpleNamespace(_conf={"keybindings": {
              "new": ["a"], "delete": ["d"], "view": ["enter"], "leader": [" "]}})
          def check(path):
              os.environ["KHALT_LEADER_TREE"] = str(path)
              entries = leader.build_keymap(view)
              assert entries, "loader returned an empty tree"
              data = json.loads(pathlib.Path(path).read_text())
              for leaf in data["bindings"].values():
                  if leaf.startswith("call:"):
                      assert leaf[5:] in leader.LEADER_ACTION_NAMES, leaf
                  else:
                      assert leaf.startswith("key:") and leaf[4:] in leader.COMMAND_KEYS, leaf
              assert data["bindings"] == leader.DEFAULT_TREE["bindings"], "default bindings drift"
          check("${generated}")
          bad = copy.deepcopy(json.loads(pathlib.Path("${generated}").read_text()))
          bad["bindings"]["w a"] = "call:invalid_seed"
          seed = pathlib.Path("bad-keymap.json")
          seed.write_text(json.dumps(bad))
          try:
              check(seed)
          except AssertionError as error:
              assert "invalid_seed" in str(error), error
              print("khalt-keymap: bad leaf rejected:", error)
          else:
              raise AssertionError("bad leaf seed accepted")
          seed.unlink()
          check("${generated}")
          print("khalt-keymap: real loader accepted generated bindings; defaults match")
        '';
      in
      assert lib.assertMsg (home.home.sessionVariables.KHALT_LEADER_TREE
        == "${home.xdg.configHome}/khalt/keymap.json") "khalt-keymap: session path is not wired";
      assert lib.assertMsg (lib.hasInfix "new = a"
        home.programs.khalt.configText && lib.hasInfix "delete = d"
        home.programs.khalt.configText && lib.hasInfix "view = enter"
        home.programs.khalt.configText) "khalt-keymap: native aliases are not wired";
      pkgs.runCommand "khalt-keymap" { nativeBuildInputs = [ python ]; } ''
        export PYTHONPATH=${inputs.khalt}
        python ${runner}
        touch "$out"
      '';

      todui-keymap = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        appPkgs = inputs.todui.inputs.nixpkgs.legacyPackages.x86_64-linux;
        python = appPkgs.python3.withPackages (ps: [ ps.textual ps.icalendar ps.python-dateutil ]);
        generated = pkgs.writeText "todui-keymap.json"
          home.xdg.configFile."todui/keymap.json".text;
        runner = pkgs.writeText "todui-keymap-check.py" ''
          import copy, json, logging, os, pathlib
          from todui import keymap

          class FailFallback(logging.Handler):
              def emit(self, record):
                  raise AssertionError(record.getMessage())
          keymap.log.addHandler(FailFallback())
          def check(path):
              os.environ["TODUI_KEYMAP"] = str(path)
              loaded = keymap.load_keymap()
              data = json.loads(pathlib.Path(path).read_text())
              assert loaded == data, "loader did not return generated file"
              assert all(leaf.startswith("call:") and leaf[5:] in keymap.LEADER_ACTIONS
                         for leaf in loaded["bindings"].values()), "unregistered action"
              assert loaded["bindings"] == keymap.DEFAULT_KEYMAP["bindings"], "default bindings drift"
          check("${generated}")
          bad = copy.deepcopy(json.loads(pathlib.Path("${generated}").read_text()))
          bad["bindings"]["c c"] = "call:invalid_seed"
          seed = pathlib.Path("bad-keymap.json")
          seed.write_text(json.dumps(bad))
          try:
              check(seed)
          except AssertionError as error:
              assert "invalid_seed" in str(error), error
              print("todui-keymap: bad leaf rejected:", error)
          else:
              raise AssertionError("bad leaf seed accepted")
          seed.unlink()
          check("${generated}")
          print("todui-keymap: real loader accepted generated bindings; defaults match")
        '';
      in pkgs.runCommand "todui-keymap" { nativeBuildInputs = [ python ]; } ''
        export PYTHONPATH=${inputs.todui}/src
        python ${runner}
        touch "$out"
      '';

      nvim-keymap = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        grammar = home.hwc.home.keymap.grammar;
        rendered = import ./domains/home/keymap/parts/to-nvim.nix { inherit lib grammar; };
        generated = pkgs.writeText "nvim-leader.lua"
          home.xdg.configFile."nvim/lua/core/leader.lua".text;
        expected = pkgs.writeText "nvim-keymap.json" (builtins.toJSON {
          inherit (grammar) groups leader;
          rows = rendered.rows;
        });
        runner = pkgs.writeText "nvim-keymap-check.lua" ''
          local spec = vim.json.decode(table.concat(vim.fn.readfile("${expected}"), "\n"))
          vim.g.mapleader = spec.leader
          vim.opt.rtp:append("${pkgs.vimPlugins.which-key-nvim}")
          dofile("${./domains/home/apps/nvim/parts/lua/core/keymaps.lua}")
          dofile("${generated}")
          local function validate()
            for _, mode in ipairs({ "n", "x", "v" }) do
              local chords = {}
              for _, entry in ipairs(vim.api.nvim_get_keymap(mode)) do
                if entry.lhs:sub(1, #spec.leader) == spec.leader then
                  local key = entry.lhs:sub(#spec.leader + 1)
                  assert(spec.groups[key:sub(1, 1)], "unknown leader group: " .. key)
                  table.insert(chords, key)
                end
              end
              for i, a in ipairs(chords) do
                for j, b in ipairs(chords) do
                  assert(i == j or b:sub(1, #a) ~= a, "duplicate/prefix: " .. a .. " / " .. b)
                end
              end
            end
            for _, row in ipairs(spec.rows) do
              local modes = row.nvim and row.nvim.mode or { "n" }
              for _, mode in ipairs(modes) do
                local lhs = spec.leader .. row.keys:gsub(" ", "")
                assert(vim.fn.maparg(lhs, mode) ~= "", "missing grammar row: " .. row.keys)
              end
            end
          end
          validate()
          -- Seed a forbidden group through the real runtime map, then remove it.
          vim.keymap.set("n", spec.leader .. "!z", "<Nop>")
          assert(not pcall(validate), "unknown-group seed was accepted")
          vim.keymap.del("n", spec.leader .. "!z")
          vim.keymap.set("n", spec.leader .. "g", "<Nop>")
          assert(not pcall(validate), "strict-prefix seed was accepted")
          vim.keymap.del("n", spec.leader .. "g")
          validate()
          -- Parse handwritten plugin modules without bootstrapping/network access.
          for _, path in ipairs(vim.fn.glob("${./domains/home/apps/nvim/parts/lua}/**/*.lua", false, true)) do
            assert(loadfile(path))
          end
          print("nvim-keymap: runtime rows present; groups/prefixes pass; both seeds rejected")
        '';
      in
      assert lib.assertMsg (lib.hasInfix ''require("core.leader")''
        (home.programs.neovim.initLua or home.programs.neovim.extraLuaConfig))
        "nvim-keymap: generated leader module is not sourced";
      pkgs.runCommand "nvim-keymap" {
        nativeBuildInputs = [ pkgs.neovim-unwrapped ];
      } ''
        export HOME="$TMPDIR"
        nvim --headless -u NONE -i NONE -l ${runner}
        touch "$out"
      '';

      workbench-keymap = let
        contract = mailHome.hwc.mail.classifier.contract;
        output = import ./domains/home/keymap/parts/to-workbench.nix {
          inherit lib; grammar = keymapGrammar; mailContract = contract;
        };
        fixture = pkgs.writeText "workbench-keymap.json" (builtins.toJSON {
          grammar = keymapGrammar; registry = output.registry; inherit contract;
          launchers = self.homeConfigurations."eric@hwc-laptop".config.programs.workbench.launchers;
          binds = mailHome.home.file.".config/aerc/binds.conf".text;
        });
      in pkgs.runCommand "workbench-keymap" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        export PYTHONPATH=${inputs.workbench}/src
        python3 - ${fixture} ${./domains/system/mcp/src/src/tools/mail-triage.ts} ${inputs.workbench}/hubs/mail.toml <<'PY'
        import copy, json, pathlib, re, sys, tomllib
        from workbench.adapters.manifest_loader import TomlHubProvider
        from workbench.config import _parse_keymap, parse_hub_keymaps
        from workbench.core.errors import ManifestError, ValidationError
        data = json.loads(pathlib.Path(sys.argv[1]).read_text())
        grammar, registry = data['grammar'], data['registry']
        hub = registry['hubs']['mail']
        source = pathlib.Path(sys.argv[2]).read_text()
        producer = source.split('const THREAD_VERBS = ', 1)[1].split(';', 1)[0]
        verbs = set(re.findall(r'"([^"\n]+)"', producer))
        verbs.update('state-' + s for s in data['contract']['states'])
        verbs.update('domain-' + d for d in data['contract']['domains'])
        manifest = tomllib.loads(pathlib.Path(sys.argv[3]).read_text())
        manifest_chords = [a['key'] for a in manifest.get('action', [])]
        for tile in manifest.get('tile', []):
            manifest_chords.extend(tile.get('item_actions', {}))
            manifest_chords.extend(tile.get('board_actions', {}))
        def validate(payload):
            rows = payload['hubs']['mail']['bindings']
            chords = [r['chord'] for r in rows]
            for row in grammar['aerc']['bindings']:
                if 'omit' not in row['wb']:
                    assert any(c == row['keys'] or c.startswith(row['keys'] + ' ') for c in chords), row
            paths = [c.split() for c in chords + [r['chord'] for r in payload['bindings']]]
            assert len({tuple(p) for p in paths}) == len(paths)
            assert not any(p != q and q[:len(p)] == p for p in paths for q in paths)
            merged = [c.split() for c in dict.fromkeys(chords + manifest_chords
                      + [r['chord'] for r in payload['bindings']])]
            assert not any(p != q and q[:len(p)] == p for p in merged for q in merged)
            assert all(r['intent'] in verbs for r in rows if r['target'] == 'item')
            assert all(data['launchers'].get(r['intent']) for r in rows if r['target'] == 'handoff'), 'missing launcher'
            global_paths = [r['chord'].split() for r in payload['bindings']]
            global_paths += [['q'], ['?'], ['R'], ['a']] + [['g', str(n)] for n in range(1, 10)]
            def overlaps(p, q):
                return p[:len(q)] == q or q[:len(p)] == p
            assert not any(overlaps(r['chord'].split(), g) for r in rows for g in global_paths), 'global shadow'
            assert not any(overlaps([r['key']], g) for r in payload['hubs']['mail']['bare'] for g in [['q'], ['?'], ['R']]), 'bare global shadow'
            bare = {r['key']: r['intent'] for r in payload['hubs']['mail']['bare']}
            expected = {(k if isinstance(k, str) else k['key']):
                        (r['wb']['verb'] if isinstance(k, str) else k['verb'])
                        for r in grammar['aerc']['bindings'] for k in r.get('bare', {}).get('list', []) if 'verb' in r['wb'] or r['wb'].get('menu') == 'read-status'}
            assert bare == expected
            item_intents = {r['intent'] for r in rows if r['target'] == 'item'}
            assert all(r['intent'] in item_intents for r in payload['hubs']['mail']['bare'])
            assert not item_intents.intersection({'move', 'fact-add', 'fact-clear'}), 'unavailable item parameters'
            sections = data['binds'].split('[messages]', 1)[1].split('[view]', 1)[0]
            for key in bare:
                assert re.search(r'^\s*' + re.escape(key) + r' = ', sections, re.M), key
        validate(registry)
        def load_hubs(payload):
            globals_ = _parse_keymap(payload, where='generated keymap')
            assert globals_ is not None, 'registry rejected by Workbench parser'
            overlays = parse_hub_keymaps(payload, where='generated keymap')
            manifests = sorted(pathlib.Path(sys.argv[3]).parent.glob('*.toml'))
            assert manifests, 'no Workbench manifests'
            provider = TomlHubProvider(str(manifests[0].parent), groups=payload['groups'],
                                       globals_=globals_, hub_keymaps=overlays)
            # reload skips invalid manifests; call the real single-file loader
            # too, so ManifestError/ValidationError fail this build directly.
            loaded = [provider._load_file(str(path)) for path in manifests]
            assert len(provider.list_hubs()) == len(loaded), 'a hub was skipped'
            return loaded
        loaded = load_hubs(registry)
        print('real Workbench loader accepted hubs: ' + ', '.join(h.id for h in loaded))
        bad = copy.deepcopy(registry)
        bad['hubs']['mail']['bare'].append({'key': 'c', 'intent': 'compose'})
        try:
            load_hubs(bad)
        except (ManifestError, ValidationError) as exc:
            assert 'every item_keys action requires a Space path' in str(exc), str(exc)
            print('seeded original bare compose regression rejected: ' + str(exc))
        else:
            raise AssertionError('real loader accepted bare compose regression')
        for kind in ('coverage', 'bare', 'prefix', 'verb', 'launcher', 'global', 'bare-global'):
            bad = copy.deepcopy(registry)
            if kind == 'coverage':
                bad['hubs']['mail']['bindings'] = []
            elif kind == 'bare':
                bad['hubs']['mail']['bare'] = []
            elif kind == 'prefix':
                bad['bindings'].append({'chord': 'a a x'})
            elif kind == 'launcher':
                bad['hubs']['mail']['bindings'].append({'chord': 'o Z', 'intent': 'missing-launcher', 'target': 'handoff'})
            elif kind == 'global':
                bad['hubs']['mail']['bindings'].append({'chord': 'q q', 'intent': 'compose', 'target': 'handoff'})
            elif kind == 'bare-global':
                bad['hubs']['mail']['bare'].append({'key': 'R', 'intent': 'compose'})
            else:
                bad['hubs']['mail']['bindings'].append({'chord': 'm Z', 'intent': 'invalid-verb', 'target': 'item'})
            try:
                validate(bad)
            except AssertionError:
                print('seeded ' + kind + ' violation rejected')
            else:
                raise AssertionError('accepted seeded ' + kind)
        PY
        touch "$out"
      '';

      yazi-keymap = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        keymap = pkgs.writeText "yazi-keymap.toml" home.xdg.configFile."yazi/keymap.toml".text;
      in pkgs.runCommand "yazi-keymap" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        python3 ${keymapValidator} ${keymapGrammarFile} ${keymap}
        touch "$out"
      '';

      # Exercise the actual laptop module wiring, not a second layout renderer.
      workbench-navigation = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        navigation = import ./domains/home/apps/zellij/parts/tabs.nix {
          inherit lib; hubRegistry = registry;
        };
        layout = home.xdg.configFile."zellij/layouts/workbench.kdl".text;
        configKdl = home.xdg.configFile."zellij/config.kdl".text;
        captures = pattern: text: map builtins.head
          (builtins.filter builtins.isList (builtins.split pattern text));
        names = captures ''tab name="([^"]+)"'' layout;
        hubCommands = captures ''args "--hub" "([^"]+)"'' layout;
        focused = captures ''tab name="([^"]+)" focus=true'' layout;
        grammar = home.hwc.home.keymap.grammar;
        # Hub digits come from rail positions, tools/nav from the grammar.
        jumps = lib.filter (entry: entry ? target) grammar.meta ++ navigation.hubJumps;
        destinationFor = key: (builtins.head (lib.filter (entry: entry.key == key) jumps)).target;
        acceptsRegistry = registry: (builtins.tryEval (builtins.deepSeq
          (import ./domains/home/apps/zellij/parts/tabs.nix { inherit lib; hubRegistry = registry; }) true)).success;
        # Seed digit keys in the grammar to verify the reserved hub namespace.
        acceptsKeys = candidateGrammar: (builtins.tryEval (builtins.deepSeq
          (import ./domains/home/keymap/parts/to-zellij.nix {
            inherit lib;
            grammar = candidateGrammar;
            tabs = navigation;
          }).keybinds true)).success;
        registry = inputs.workbench.hubRegistryFor {
          order = home.hwc.home.apps.workbench.hubOrder;
          hidden = home.hwc.home.apps.workbench.hiddenHubs;
        };
      in
      assert lib.assertMsg (!acceptsRegistry (registry // { schemaVersion = 3; }))
        "workbench check: retired registry schema 3 accepted";
      assert lib.assertMsg (!acceptsRegistry (registry // { hubs = registry.hubs ++ [ (builtins.head registry.hubs) ]; }))
        "workbench check: duplicate registry hub accepted";
      assert lib.assertMsg (lib.all (key: !acceptsKeys (grammar // {
          meta = grammar.meta ++ [ { inherit key; target = "tool:todui"; desc = "Reserved digit"; } ];
        })) [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" ])
        "workbench check: a digit key in grammar.meta was accepted";
      assert lib.assertMsg (acceptsKeys grammar)
        "workbench check: the shipped registry's hub keys are rejected";
      assert lib.assertMsg (names == [ "workbench" ] ++ map (tab: tab.name) navigation.toolTabs
          && focused == [ "workbench" ] && hubCommands == [ ]
          && lib.all (jump: navigation.tabFor.${jump.target} == navigation.tabFor.workbench) navigation.hubJumps)
        "workbench check: one landing workbench tab, no per-hub tabs, every hub digit targets it";
      assert lib.assertMsg (names == map (tab: tab.name) navigation.destinations)
        "workbench check: generated tab names/order differ from navigation";
      assert lib.assertMsg (home.programs.workbench.defaultHub == navigation.landingHub
        && home.programs.workbench.tabs == navigation.launcherTabs
        && home.programs.workbench.hubOrder == home.hwc.home.apps.workbench.hubOrder
        && home.programs.workbench.hiddenHubs == home.hwc.home.apps.workbench.hiddenHubs)
        "workbench check: launcher destinations differ from layout";
      assert lib.assertMsg (lib.versionAtLeast home.hwc.home.apps.zellij.package.version "0.45.1"
        && lib.elem home.hwc.home.apps.zellij.package home.programs.workbench.extraRuntimePackages
        && lib.elem home.hwc.home.apps.zellij.package home.home.packages)
        "workbench check: shell and wrapper must share the graphics-capable pane host";
      assert lib.assertMsg (lib.all (entry: lib.hasInfix
        (if lib.hasPrefix "hub:" entry.target
          then "${entry.key}|goto-hub|${toString navigation.tabFor.${entry.target}}:${lib.removePrefix "hub:" entry.target}|${entry.desc}"
          else "${entry.key}|goto-tab|${toString navigation.tabFor.${entry.target}}|${entry.desc}") configKdl) jumps)
        "workbench check: generated meta entries (goto-tab tools, goto-hub hubs) differ from navigation";
      assert lib.assertMsg (destinationFor "1" == "hub:${(builtins.head
        (lib.sort (a: b: a.order < b.order) registry.hubs)).slug}")
        "workbench check: digit 1 must target the first visible hub";
      assert lib.assertMsg (lib.all (entry: builtins.match "[0-9]" entry.key == null) grammar.meta)
        "workbench check: grammar.meta contains a reserved digit";
      assert lib.assertMsg (destinationFor "t" == "tool:todui" && destinationFor "c" == "tool:khalt"
        && destinationFor "m" == "tool:aerc" && destinationFor "f" == "tool:yazi"
        && destinationFor "e" == "tool:nvim" && destinationFor "a" == "tool:herdr")
        "workbench check: tool shortcuts changed destination";
      pkgs.runCommand "workbench-navigation" {} ''
        ${lib.getExe home.hwc.home.apps.zellij.package} --version
        touch "$out"
      '';

      # Seed failures through the same taxonomy helper used by Sieve and the
      # Gmail janitor. Force the views: tryEval alone only checks the outer set.
      mail-trash-guard = let
        data = import ./domains/mail/taxonomy/data.nix;
        taxonomy = import ./domains/mail/taxonomy/lib.nix { inherit lib data; };
        accepts = trash: protection: (builtins.tryEval (builtins.deepSeq
          (import ./domains/mail/taxonomy/lib.nix {
            inherit lib;
            data = data // { senders = data.senders // {
              inherit trash;
              protected = protection;
            }; };
          }).derived true)).success;
        badEntries = [
          "comms.contractorcto.com" "x@iheartwoodcraft.com" "proton.me"
          "news.proton.me" "alerts@limitloginattempts.com" "mail.instagram.com"
          "Contractorcto@gmail.com" "gmail.com" "com" "@junk.example"
          { sender = "semrush.com"; scope = "gmail"; }
          { list = "@business-noreply@mail.instagram.com"; }
          { list = "list@support@sub.limitloginattempts.com"; }
          { list = "@ContractorCTO@GMAIL.COM"; }
          { sender = "junk.example"; scope = "protno"; }
          { list = "@noise@junk.example"; scope = "both"; }
          { list = "@noise@junk.example"; scope = "gmail"; }
          { sender = "junk.example"; list = "@noise@junk.example"; }
          { scope = "proton"; }
          { sender = "junk.example"; typo = true; }
          { sender = "@noise@junk.example"; }
          { sender = ""; } { sender = 42; } { list = ""; }
          { sender = "junk.example\nother.example"; } 42
        ];
        upperProtection = lib.mapAttrs (_: map lib.toUpper) data.senders.protected;
        clean = [ "other@gmail.com" { sender = "noise.example"; scope = "proton"; }
          { list = "@help@profitabletradie.com"; } "no-reply@news.proton.me" ];
        home = mailHome;
        system = self.nixosConfigurations.${mailHost}.config;
        filters = import ./domains/mail/aerc/parts/sieve-filters.nix { inherit lib; };
      in
      assert lib.assertMsg (lib.all (entry: !accepts [ entry ] data.senders.protected) badEntries)
        "mail-trash-guard: unsafe or malformed trash entry accepted";
      assert lib.assertMsg (!accepts [ "comms.contractorcto.com" ] upperProtection
        && !accepts [ { list = "@business-noreply@mail.instagram.com"; } ] upperProtection)
        "mail-trash-guard: protection is case-sensitive";
      assert lib.assertMsg (accepts clean data.senders.protected)
        "mail-trash-guard: narrow reviewed entries rejected";
      assert lib.assertMsg (lib.length taxonomy.derived.trashSenders == 15
        && builtins.fromJSON system.systemd.services.mail-janitor.environment.MJ_DENY == taxonomy.derived.trashSenders)
        "mail-trash-guard: Gmail janitor projection changed beyond reviewed removals";
      assert lib.assertMsg (lib.all (name: home.home.file.".config/aerc/sieve/${name}".text == filters.${name})
        (builtins.attrNames filters)
        && !(home.home.file ? ".config/aerc/sieve/filters/bundle.sieve"))
        "mail-trash-guard: Home Manager does not deploy the two generated filters";
      pkgs.runCommand "mail-trash-guard" {} ''touch "$out"'';

      # Parse and replay the actual Home Manager files, not a parallel renderer.
      mail-proton-sieve = let
        home = mailHome;
        filters = lib.genAttrs [ "01-junk.sieve" "02-routing.sieve" ]
          (name: home.home.file.".config/aerc/sieve/${name}".text);
        fixture = pkgs.writeText "proton-sieve.json" (builtins.toJSON filters);
      in pkgs.runCommand "mail-proton-sieve" {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.sievelib ])) ];
      } ''
        python3 - ${fixture} <<'PY'
        import fnmatch
        import json
        import pathlib
        import sys
        from email.utils import getaddresses

        from sievelib import commands
        from sievelib.parser import Parser

        # sievelib omits RFC 5235's spamtest and numeric comparator. Register only
        # their grammar; fixtures below supply a score/threshold, never call Proton.
        commands.comparator['extra_arg']['values'].append('"i;ascii-numeric"')


        class SpamtestCommand(commands.TestCommand):
            extension = 'spamtest'
            args_definition = [commands.comparator, commands.match_type,
                               {'name': 'value', 'type': ['string'], 'required': True}]


        commands.add_commands(SpamtestCommand)


        def strings(value):
            return [json.loads(v).lower() for v in (value if isinstance(value, list) else [value])]


        def matches(test, headers, spam):
            args = test.arguments
            if test.name == 'not':
                return not matches(args['test'], headers, spam)
            if test.name in ('allof', 'anyof'):
                values = [matches(t, headers, spam) for t in args['tests']]
                return all(values) if test.name == 'allof' else any(values)
            if test.name == 'environment':
                return True  # Proton provides the configured spam threshold.
            if test.name == 'spamtest':
                return spam
            if test.name not in ('header', 'address'):
                raise AssertionError(f'Unhandled test: {test.name}')
            fields = strings(args['header-list' if test.name == 'address' else 'header-names'])
            values = [headers[field].lower() for field in fields if field in headers]
            if test.name == 'address':
                values = [addr for _, addr in getaddresses(values)]
                if args.get('address-part') == ':domain':
                    values = [addr.rsplit('@', 1)[-1] for addr in values]
            keys = strings(args['key-list'])
            mode = args.get('match-type', ':is')
            compare = {':is': lambda v, k: v == k,
                       ':contains': lambda v, k: k in v,
                       ':matches': lambda v, k: fnmatch.fnmatchcase(v, k)}[mode]
            return any(compare(value, key) for value in values for key in keys)


        def actions(tree, headers, spam=False):
            result = set()
            for node in tree:
                if node.name == 'require':
                    continue
                assert node.name == 'if'
                if not matches(node.arguments['test'], headers, spam):
                    continue
                for action in node.children:
                    if action.name == 'stop':
                        return result, True
                    assert action.name in ('fileinto', 'addflag'), action.name
                    result.update((action.name, value) for value in strings(next(iter(action.arguments.values()))))
            return result, False


        filters = json.loads(pathlib.Path(sys.argv[1]).read_text())
        parsed = {}
        # Sieve retains folder/read effects; System One alone assigns @ labels.
        allowed = {'trash', 'archive', 'hide_my_email'}


        def check_targets(tree):
            for node in tree:
                if node.name == 'fileinto':
                    assert set(strings(node.arguments['mailbox'])) <= allowed
                check_targets(node.children)


        for name, text in filters.items():
            parser = Parser()
            assert parser.parse(text), getattr(parser, 'error', name)
            parsed[name] = parser.result
            check_targets(parser.result)
            for node in parser.result:
                for action in node.children:
                    if action.name == 'fileinto':
                        assert set(strings(action.arguments['mailbox'])) <= allowed
                    if action.name == 'addflag':
                        assert '\\flagged' not in strings(next(iter(action.arguments.values())))
            print(f'{name}: syntax and targets pass')
        parser = Parser()
        assert not parser.parse('require ["fileinto"]; if true { fileinto "Trash" }')
        for target in ['work', '@hwc']:
            parser = Parser()
            assert parser.parse('require ["fileinto"]; if true { fileinto "' + target + '"; }')
            try:
                check_targets(parser.result)
            except AssertionError:
                pass
            else:
                raise AssertionError('label target guard accepted ' + target)


        def deliver(**headers):
            result = set()
            spam = headers.pop('spam', False)
            for name in sorted(parsed):
                part, stopped = actions(parsed[name], headers, spam)
                result |= part
                if stopped:
                    break
            return result


        def expect(expected, **headers):
            actual = deliver(**headers)
            wanted = {('addflag', '\\seen') if value == 'Seen' else ('fileinto', value.lower())
                      for value in expected}
            assert actual == wanted, (headers, actual, wanted)


        expect([], to='eric@iheartwoodcraft.com')
        expect([], to='eriqueo@proton.me')
        expect([], to='eric@contractorcto.com')
        expect([], **{'from': 'hi@xotara.us'})
        expect([], **{'from': 'tony.fraserjones@profitabletradie.com'})
        expect([], **{'x-pm-list-identifier': '@certification@narihq.org'})
        expect([], **{'from': 'hello@classdojo.com'})
        expect([], **{'from': 'hello@classdojo.com', 'spam': True})
        expect([], **{'from': 'position-tracking@semrush.com'})
        expect([], **{'x-pm-list-identifier': '@billing@limitloginattempts.com'})
        expect(['Seen'], **{'from': 'notifications@github.com'})
        expect([], **{'x-pm-list-identifier': '@business-noreply@mail.instagram.com'})
        expect([], **{'from': 'alerts@notify.wellsfargo.com'})
        expect([], **{'from': 'onlinebanking@ealerts.bankofamerica.com'})
        expect([], **{'from': 'statefarmservice@statefarmservice.com'})
        expect([], **{'x-pm-list-identifier': '@nicole.dray@farther.com'})
        expect([], **{'from': 'office@kenyonnoble.com'})
        expect(['Seen'], **{'from': 'no-reply@accounts.google.com'})
        expect(['Archive', 'Seen'], **{'x-pm-list-identifier': '@vimeo@vimeo.com'})
        expect(['Archive', 'Seen'], **{'from': 'builds@sr.ht'})
        expect(['Archive', 'Seen'], **{'from': 'dmarc@example.net'})
        expect(['Archive', 'Seen'], **{'from': 'support@comms.datax.to',
               'to': 'hello@contractorcto.com', 'subject': 'New demo request → Example'})
        expect([], **{'from': 'support@comms.datax.to', 'to': 'hello@contractorcto.com',
               'subject': 'Customer needs a reply'})
        expect(['hide_my_email'], to='camelcity.derail128@passmail.com')
        expect(['Trash', 'Seen'], **{'from': 'noise@sub.angi.com', 'to': 'eric@iheartwoodcraft.com'})
        expect(['Trash', 'Seen'], **{'x-pm-list-identifier': '@team@emails.hostinger.com'})
        expect(['Trash', 'Seen'], **{'x-pm-list-identifier': '@help@profitabletradie.com'})
        expect([], **{'from': 'tom@thecontractorfight.com', 'spam': True})
        expect([], **{'from': 'tom@thecontractorfight.com'})
        expect([], **{'from': 'sales@klingspor.com'})
        expect([], **{'from': 'person@otherangi.com'})
        expect([], **{'from': 'other@gmail.com'})
        print('32 delivery fixtures pass; seeded broken syntax and label targets rejected')
        PY
        touch "$out"
      '';

      # ── Aerc's human workflow stays smaller than its mail taxonomy ─────
      # The taxonomy intentionally retains automation and legacy tags, but the
      # generated which-key surface must not flatten that whole vocabulary into
      # one menu. Exercise the exact server Home Manager output consumed by the
      # live aerc process, including noinherit tab contexts and tag commands.
      aerc-bindings = let
        home = mailHome;
        binds = home.home.file.".config/aerc/binds.conf".text;
        lines = lib.splitString "\n" binds;
        directMarkLines = lib.filter
          (line: builtins.match "[[:space:]]*<Space>m. =.*" line != null)
          lines;
        contract = home.hwc.mail.classifier.contract;
        tags = import ./domains/mail/aerc/parts/tags.nix { inherit lib; mailContract = contract; };
        required = [
          "/ = :filter<space>"
          "<Space>fa = :query -f -n mail-search<space>"
          "<Space>fa = :close<Enter>:query -f -n mail-search<space>"
          "<Space>ff = :close<Enter>:filter<space>"
          "<Space>wi = :pipe -s -m"
          "<Space>wn = :next-part<Enter>"
          "<Space>wp = :prev-part<Enter>"
          "<Space>oc = :pipe -m email-to-khal<Enter>"
          "<A-h> = :prev-tab<Enter>"
          "<A-l> = :next-tab<Enter>"
          "<A-J> = :next-tab<Enter>"
          "<A-K> = :prev-tab<Enter>"
          "<A-S-j> = :next-tab<Enter>"
          "<A-S-k> = :prev-tab<Enter>"
          "<Space>ft = :filter tag:"
          "<Space>fT = :query -f -n tag-search tag:"
          "<Space>fc = :clear -s<Enter>"
          "<Space>mu = :unsubscribe -s<Enter>"
          "D = :pipe -b -m mail-classifier transition --outcome trash<Enter>"
          "pipe -b -m mail-classifier correct --state do"
          "pipe -b -m mail-classifier correct --state did"
          "pipe -b -m mail-classifier correct --state dont-know"
          "<Space>gk = :cf DONT KNOW<Enter>"
          "<Space>gb = :cf Bulk<Enter>"
          "pipe -b -m mail-classifier correct --domain datax"
          "pipe -m mail-classifier route-review"
          "term mail-classifier route-manage"
        ];
        missing = lib.filter (needle: !(lib.hasInfix needle binds)) required;
      in
      assert lib.assertMsg (missing == [])
        "aerc-bindings: generated server binds are missing ${lib.concatStringsSep ", " missing}";
      assert lib.assertMsg (lib.length directMarkLines <= 22)
        "aerc-bindings: first mark popup has ${toString (lib.length directMarkLines)} entries across list/view (limit 22)";
      assert lib.assertMsg (!(lib.hasInfix "<Space>m! =" binds) && !(lib.hasInfix "<Space>m? =" binds))
        "aerc-bindings: action/pending leaked back into the human mark menu";
      assert lib.assertMsg (!(lib.hasInfix "-keep" tags.clearFlagsCmd) && !(lib.hasInfix "-keep" tags.clearAllCmd))
        "aerc-bindings: a bulk clear can remove the protected keep tag";
      assert lib.assertMsg (builtins.all (tag: !(lib.elem "-${tag}" (lib.splitString " " tags.clearAllCmd)))
        ([ "flagged" "starred" "keep" "work" "finance" "family" "action" "pending" ]
          ++ map (domain: "${contract.domainTagPrefix}${domain}") contract.domains))
        "aerc-bindings: metadata clear strips stars, historical tags or Domain";
      assert lib.assertMsg (lib.hasInfix "modify-labels ${tags.clearAllCmd}" binds
        && lib.hasInfix "modify-labels +ads" binds
        && !(lib.hasInfix "+work -" binds))
        "aerc-bindings: optional facts or safe-clear production wiring changed";
      assert lib.assertMsg (let
        registry = import ./domains/mail/notmuch/parts/searches.nix {
          inherit lib; cfg = home.hwc.mail.notmuch; mailContract = contract;
        };
        aercQueries = home.home.file.".config/aerc/notmuch-queries".text;
        deployed = home.xdg.configFile."notmuch/searches".text;
      in deployed == registry.text
        && builtins.all (name: lib.hasInfix "${lib.replaceStrings [ ":" ] [ "/" ] name}=${registry.searches.${name}}" aercQueries)
          (builtins.attrNames registry.searches)
        && registry.searches."fact:finance" == "tag:${contract.traitTagPrefix}finance"
        && registry.searches."state:dont-know" == "tag:${contract.stateTagPrefix}dont-know"
        && registry.searches."view:bulk" == contract.viewQueries.bulk
        && registry.searches."domain:family" == "tag:${contract.domainTagPrefix}family"
        && registry.searches."history:family" == "tag:family"
        && !(registry.searches ? business) && !(registry.searches ? money)
        && !(registry.searches ? "label:finance"))
        "aerc-bindings: current axes and historical search registry drifted";
      pkgs.runCommand "aerc-bindings" {
        nativeBuildInputs = [ pkgs.python3 pkgs.notmuch pkgs.tmux pkgs.bash
          (lib.findFirst (p: (p.pname or "") == "aerc") null home.home.packages) ];
        queries = home.home.file.".config/aerc/notmuch-queries".source;
        bindsFile = home.home.file.".config/aerc/binds.conf".source;
        configFile = home.home.file.".config/aerc/aerc.conf".source;
        stylesFile = home.home.file.".config/aerc/stylesets/hwc".source;
      } ''
        python3 - "$queries" "$bindsFile" "$configFile" "$stylesFile" <<'PY'
        import json, os, pathlib, shlex, subprocess, sys, tempfile, time
        queries = dict(line.split('=', 1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
                       if line and not line.startswith('#'))
        assert all(':' not in name for name in queries), queries
        binds = pathlib.Path(sys.argv[2]).read_text()
        # Match the macro parser's backslash decoding before parsing commands.
        def command_text(value):
            return value.replace(chr(92) * 2, chr(92))
        # Check the generated production config, including viewer noinherit.
        sections = {}
        section = 'global'
        for line in binds.splitlines():
            line = line.strip()
            if line.startswith('['):
                section = line
            elif '=' in line and not line.startswith(('#', '$')):
                key = line.split('=', 1)[0].strip()
                current = sections.setdefault(section, {})
                assert key not in current, (section, key)
                current[key] = line
        for section, rows in sections.items():
            keys = [k for k in rows if k.startswith('<Space>')]
            for key in keys:
                assert not any(other != key and other.startswith(key) for other in keys), (section, key)
            assert 'i' not in rows and 'I' not in rows, (section, 'retired shortcuts')
        for section in ['[messages]', '[view]']:
            for key in ['mc', 'mr', 'mf']:
                if key == 'mr':
                    assert ':choose ' not in sections[section].get("<Space>" + key, "")
                else:
                    assert '<Space>' + key not in sections[section]
            for key in ['cc', 'cr', 'ca', 'cf']:
                assert '<Space>' + key in sections[section]
        for section, aliases in {
            '[messages]': {'a': 'ma', 'd': 'dd', 'D': 'dd',
                           'J': 'mj', 'K': 'mk', 'c': 'cc', 'C': 'ca', 'X': 'mx', 'Y': 'ym'},
            '[view]': {'r': 'cr', 'R': 'ca', 'f': 'cf', 'a': 'ma', 'd': 'dd',
                       'u': 'ol', 't': 'ot', 'p': 'op'},
        }.items():
            for bare, chord in aliases.items():
                command = lambda line: line.split(' = ', 1)[1].split(' # ', 1)[0]
                wanted = command(sections[section]['<Space>' + chord])
                if section == '[view]' and bare in ('a', 'd'):
                    wanted += ':close<Enter>'
                assert command(sections[section][bare]) == wanted, (section, bare, chord)
        assert ':read<Enter>' in sections['[messages]']['r']
        assert ':unread<Enter>' in sections['[messages]']['u']
        # Explicit accepted viewer exceptions: r replies; u opens the URL picker.
        assert ':reply<Enter>' in sections['[view]']['r']
        assert 'urlscan' in sections['[view]']['u']
        assert '<Space>bc' not in sections['[messages]']
        assert '<Space>wi' in sections['[view]'] and '<Space>wi' not in sections['[messages]']
        for key in ['<Space>ms', '<Space>md', '<Space>mt', '<Space>ml', '<Space>mv', '<Space>fd']:
            for section in ['[messages]', '[view]']:
                line = sections[section][key]
                options = shlex.split(command_text(line.split(':choose ', 1)[1].split('<Enter>', 1)[0]))
                assert len(options) % 4 == 0
                choices = [options[i+1] for i in range(0, len(options), 4)]
                assert len(choices) == len(set(choices)) and 0 < len(choices) <= 12, choices
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            mail = root / 'mail'
            for folder in ['inbox', 'archive']:
                for part in ['cur', 'new', 'tmp']:
                    (mail / folder / part).mkdir(parents=True)
            config = root / 'notmuch-config'
            config.write_text(f'[database]\npath={mail}\n[user]\nname=Test\nprimary_email=test@example.com\n[new]\ntags=\n[maildir]\nsynchronize_flags=true\n')
            os.environ['NOTMUCH_CONFIG'] = str(config)
            def nm(*args):
                return subprocess.check_output(['notmuch', *args], text=True).strip()
            for mid in ['old', 'current']:
                (mail / 'inbox' / 'cur' / f'{mid}:2,F').write_text(
                    f'From: sender@example.com\nTo: test@example.com\nMessage-ID: <{mid}@example.com>\nSubject: {mid}\nDate: Thu, 1 Oct 2026 12:00:00 -0600\n\nfixture\n')
            (mail / 'archive' / 'cur' / 'copy:2,F').write_text((mail / 'inbox' / 'cur' / 'current:2,F').read_text())
            nm('new')
            nm('tag', '+inbox', '+work', '+family', '+finance', '--', 'id:old@example.com')
            nm('tag', '+inbox', '+state/do', '+domain/hwc', '+trait/finance', '+ads', '+keep', '--', 'id:current@example.com')
            assert nm('count', queries['domain/hwc']) == '1'
            assert nm('count', queries['finance']) == '1'
            assert nm('count', queries['history/business']) == '1'
            assert nm('count', queries['history/family']) == '1'
            assert nm('count', queries['domain/family']) == '0'
            clear = next(line for line in binds.splitlines() if '<Space>mt =' in line)
            options = shlex.split(command_text(clear.split('= :choose ', 1)[1].split('<Enter>', 1)[0]))
            command = next(options[i+3] for i in range(0, len(options), 4) if options[i+1] == 'x')
            assert command.startswith('modify-labels '), command
            operations = shlex.split(command)[1:]
            before = nm('search', '--output=files', 'id:current@example.com').splitlines()
            nm('tag', *operations, '--', 'id:current@example.com')
            tags = set(nm('search', '--output=tags', 'id:current@example.com').splitlines())
            assert {'flagged', 'keep', 'state/do', 'domain/hwc', 'inbox'} <= tags, tags
            assert 'trait/finance' not in tags and 'ads' not in tags, tags
            after = nm('search', '--output=files', 'id:current@example.com').splitlines()
            assert len(before) == len(after) == 2 and set(before) == set(after)
            assert all(path.endswith(':2,F') for path in after), after
            old_tags = set(nm('search', '--output=tags', 'id:old@example.com').splitlines())
            assert {'work', 'family', 'finance', 'flagged'} <= old_tags, old_tags
            # Exercise the real key decoder and native dialogs on isolated mail.
            # This catches Notmuch's native thread fetch ignoring sort criteria.
            for idx, subject in enumerate(['Zebra needle', 'Alpha', 'Middle']):
                (mail / 'inbox' / 'cur' / f'remap-{idx}:2,').write_text(
                    f'From: sender@example.com\nTo: test@example.com\nMessage-ID: <remap-{idx}@example.com>\nSubject: {subject}\nDate: Thu, 1 Oct 2026 12:0{idx}:00 -0600\n\nfixture body\n')
            (mail / 'inbox' / 'cur' / 'remap-reply:2,').write_text(
                'From: sender@example.com\nTo: test@example.com\nMessage-ID: <remap-reply@example.com>\nIn-Reply-To: <remap-1@example.com>\nReferences: <remap-1@example.com>\nSubject: Re: Alpha\nDate: Thu, 1 Oct 2026 12:03:00 -0600\n\nfixture reply\n')
            nm('new')
            for mid in ['remap-0', 'remap-1', 'remap-2', 'remap-reply']:
                nm('tag', '+remap-fixture', '+state/do', '--', f'id:{mid}@example.com')
            assert nm('count', 'tag:remap-fixture') == '4'
            querymap = root / 'querymap'
            querymap.write_text('do=tag:remap-fixture\n')
            accounts = root / 'accounts.conf'
            accounts.write_text(f'[fixture]\nsource=notmuch://{mail}\nfrom=Test <test@example.com>\nquery-map={querymap}\nfolders=do\ndefault=do\n')
            conf = root / 'aerc.conf'
            # Parse the actual production styles, including the spaced State
            # alias, in the isolated client rather than hiding style failures.
            style_dir = root / 'stylesets'; style_dir.mkdir()
            (style_dir / 'hwc').write_text(pathlib.Path(sys.argv[4]).read_text())
            conf.write_text(pathlib.Path(sys.argv[3]).read_text().replace('styleset-name = hwc', 'styleset-name = hwc\nstylesets-dirs = ' + str(style_dir)))
            socket = str(root / 'tmux.sock')
            def tm(*args):
                return subprocess.check_output(['tmux', '-S', socket, '-f', '/dev/null', *args], text=True)
            def screen():
                return tm('capture-pane', '-p', '-t', 'fixture')
            def keys(value):
                tm('send-keys', '-t', 'fixture', '-l', value)
                time.sleep(0.7)
                return screen()
            def special(value):
                tm('send-keys', '-t', 'fixture', value)
                time.sleep(0.7)
                return screen()
            command = shlex.join(['aerc', '-I', '-C', str(conf), '-B', sys.argv[2], '-A', str(accounts)])
            os.environ['SHELL'] = '${pkgs.bash}/bin/bash'
            os.environ['TERM'] = 'xterm-256color'
            os.environ['TZ'] = 'UTC'
            # Exercise production bindings without touching the live ledger.
            # A noisy successful child exposes foreground terminal regressions.
            fixture_bin = root / 'bin'
            fixture_bin.mkdir()
            call_file = root / 'quiet-call.json'
            failure_file = root / 'quiet-failure'
            classifier = fixture_bin / 'mail-classifier'
            classifier.write_text(
                '#!${pkgs.python3}/bin/python3\n'
                'import json, pathlib, sys\n'
                f'call = pathlib.Path({str(call_file)!r})\n'
                'message = sys.stdin.read()\n'
                'call.write_text(json.dumps({"args": sys.argv[1:], "message": message}))\n'
                'print("QUIET_ACTION_RESULT")\n'
                f'sys.exit(42 if pathlib.Path({str(failure_file)!r}).exists() else 0)\n')
            classifier.chmod(0o755)
            os.environ['PATH'] = str(fixture_bin) + os.pathsep + os.environ['PATH']
            def quiet_action(chord, expected, option=None):
                call_file.unlink(missing_ok=True)
                keys(chord)
                if option is not None:
                    keys(option)
                    special('Enter')
                for _ in range(30):
                    if call_file.exists():
                        break
                    time.sleep(0.1)
                assert call_file.exists(), screen()
                call = json.loads(call_file.read_text())
                assert call['args'] == expected, call
                assert 'Message-ID: <remap-0@example.com>' in call['message'], call
                time.sleep(0.1)
                output = screen()
                assert 'QUIET_ACTION_RESULT' not in output and 'mail-classifier <' not in output, output
                assert 'Zebra needle' in output, output
                return output
            try:
                tm('new-session', '-d', '-s', 'fixture', '-x', '150', '-y', '40', command)
                for _ in range(20):
                    time.sleep(0.3)
                    if 'Zebra needle' in screen():
                        break
                assert 'Zebra needle' in screen(), screen()
                output = keys(' sa')
                assert output.index('Alpha') < output.index('Middle') < output.index('Zebra needle'), output
                keys(':select 0')
                special('Enter')
                output = keys(' tt')
                assert '{2}Alpha' in output and '└─>' not in output, output
                output = keys(' tt')
                assert '{2}Alpha' not in output and '└─>' in output, output
                assert ':filter' in keys(' ff')
                special('Escape')
                assert ':query -f -n mail-search' in keys(' fa')
                keys('needle')
                output = special('Enter')
                assert 'Zebra needle' in output and 'Alpha' not in output, output
                assert 'fixture body' in special('Enter')
                assert 'local image preview' in keys(' w').lower()
                special('Escape')
                output = keys(' ms')
                assert all(word in output for word in ['DO', 'DONT KNOW', 'DID', 'LOOK', 'JUNK']), output
                special('Escape')
                output = keys(' mt')
                assert 'Clear optional facts' in output, output
                keys('a')
                output = special('Enter')
                assert '+ads' in output and '+receipts' in output, output
                keys('g')
                special('Enter')
                assert 'ads' in nm('search', '--output=tags', 'id:remap-0@example.com').splitlines()
                keys(' mt')
                keys('x')
                special('Enter')
                current = nm('search', '--output=tags', 'id:remap-0@example.com').splitlines()
                assert 'ads' not in current and 'state/do' in current, current
                assert ':filter' in keys(' ff')
                special('Escape')
                for chord, outcome in [('a', 'done'), ('d', 'trash'), ('D', 'trash'),
                                       (' ma', 'done'), (' dd', 'trash')]:
                    quiet_action(chord, ['transition', '--outcome', outcome])
                quiet_action(' ms', ['correct', '--state', 'look'], 'l')
                quiet_action(' ms', ['correct', '--state', 'dont-know'], 'k')
                quiet_action(' md', ['correct', '--domain', 'personal'], 'p')
                for chord, outcome in [('a', 'done'), ('d', 'trash')]:
                    assert 'fixture body' in special('Enter')
                    output = quiet_action(chord, ['transition', '--outcome', outcome])
                    assert 'fixture body' not in output, output
                failure_file.touch()
                output = quiet_action('a', ['transition', '--outcome', 'done'])
                assert 'exit status 42' in output, output
            finally:
                subprocess.run(['tmux', '-S', socket, 'kill-server'], capture_output=True)

            # Actual spaced alias/default parsing and Bulk partition. These
            # synthetic messages never use the real ledger or remote mail.
            samples = {
                'unknown-direct': ('Need sorting', ['state/dont-know']),
                'unknown-bulk': ('Newsletter seed', ['state/dont-know', 'trait/newsletter']),
                'unknown-security': ('Security seed', ['state/dont-know', 'trait/newsletter', 'trait/security']),
                'confirmed-promo': ('Confirmed action seed', ['state/do', 'trait/newsletter']),
            }
            for mid, (subject, tags) in samples.items():
                (mail / 'inbox' / 'cur' / f'{mid}:2,').write_text(
                    f'From: sender@example.com\nTo: test@example.com\nMessage-ID: <{mid}@example.com>\nSubject: {subject}\nDate: Thu, 1 Oct 2026 13:00:00 -0600\n\nfixture body\n')
            nm('new')
            for mid, (subject, tags) in samples.items():
                nm('tag', '+inbox', *('+' + tag for tag in tags), '--', f'id:{mid}@example.com')
            querymap.write_text(pathlib.Path(sys.argv[1]).read_text())
            assert nm('count', queries['DONT KNOW']) == '2'
            assert nm('count', queries['Bulk']) == '1'
            assert nm('count', queries['state/dont-know']) == '3'
            accounts.write_text(f'[fixture]\nsource=notmuch://{mail}\nfrom=Test <test@example.com>\nquery-map={querymap}\nfolders=DO,DONT KNOW,DID,LOOK,JUNK,Bulk\ndefault=DONT KNOW\n')
            try:
                tm('new-session', '-d', '-s', 'fixture', '-x', '150', '-y', '40', command)
                for _ in range(20):
                    time.sleep(0.3)
                    if 'Need sorting' in screen(): break
                output = screen()
                assert 'Need sorting' in output and 'DONT KNOW' in output and 'Security seed' in output, output
                assert 'Newsletter seed' not in output and 'Confirmed action seed' not in output, output
                output = keys(' gb')
                assert 'Newsletter seed' in output and 'Need sorting' not in output and 'Security seed' not in output, output
                output = keys(' gk')
                assert 'Need sorting' in output and 'Newsletter seed' not in output, output
                output = keys(' gi')
                assert 'Confirmed action seed' in output and 'Need sorting' not in output, output
            finally:
                subprocess.run(['tmux', '-S', socket, 'kill-server'], capture_output=True)
        print('generated views, real metadata clear, quiet action tabs and visible failures pass')
        PY
        touch "$out"
      '';

      # The calm reading view prefers the sender-authored plain part. HTML is
      # still available with the MIME-part keys when layout carries meaning.
      aerc-rendering = let
        home = mailHome;
        aercConf = home.home.file.".config/aerc/aerc.conf".text;
        imageWiring = pkgs.writeText "aerc-image-wiring.json" (builtins.toJSON {
          binds = home.home.file.".config/aerc/binds.conf".text;
          conf = aercConf;
        });
        plainFilterLine = builtins.head (lib.filter
          (line: lib.hasPrefix "text/plain = " line)
          (lib.splitString "\n" aercConf));
        plainFilter = lib.removePrefix "text/plain = " plainFilterLine;
        filterRunner = pkgs.writeShellScript "test-aerc-plain-filter" plainFilter;
        longUrl = "https://tracking.example/campaign/abcdefghijklmnopqrstuvwxyz0123456789/abcdefghijklmnopqrstuvwxyz0123456789?recipient=fixture";
        fixture = pkgs.writeText "aerc-plain-message.txt" ''
          Nicole sent you a new request.



          The useful message stays visible, while this tracking machinery does not: <${longUrl}>

          This paragraph is intentionally long enough to prove that the configured aerc wrap stage uses a calm reading measure instead of expanding prose across a very wide terminal window where it becomes hard to scan.
        '';
      in
      assert lib.assertMsg (lib.hasInfix "alternatives = text/plain,text/html" aercConf)
        "aerc-rendering: plain text is not the default MIME alternative";
      pkgs.runCommand "aerc-rendering" {} ''
        export TERM=xterm-256color
        export LC_ALL=C.UTF-8
        ${filterRunner} < ${fixture} > rendered
        ${pkgs.python3}/bin/python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b[31muntrusted\x1b[0m\n")' \
          | ${filterRunner} > sanitized
        ${pkgs.python3}/bin/python3 - rendered sanitized ${lib.escapeShellArg longUrl} <<'PY'
        import pathlib
        import re
        import sys

        rendered = pathlib.Path(sys.argv[1]).read_bytes()
        sanitized = pathlib.Path(sys.argv[2]).read_bytes()
        target = sys.argv[3].encode()
        expected_link = b"\x1b]8;;" + target + b"\x1b\\"
        assert expected_link in rendered, "long URL target was not preserved in OSC 8 link"
        assert b"\x1b" not in sanitized, "untrusted terminal control reached the viewer"

        visible = re.sub(rb"\x1b]8;;.*?\x1b\\(.*?)\x1b]8;;\x1b\\", rb"\1", rendered)
        text = visible.decode()
        assert target not in visible, "long tracking URL remains visible"
        assert "↗ tracking.example" in text, "compact link label is missing"
        assert "\n\n\n" not in text, "excess blank lines remain"
        assert max(map(len, text.splitlines())) <= 100, "visible line exceeds reading measure"
        assert text.count("Nicole sent you a new request.") == 1, "message content changed or duplicated"
        PY
        ${pkgs.python3}/bin/python3 - ${imageWiring} <<'PY'
        import json, re, shlex, struct, subprocess, sys, zlib
        from email.message import EmailMessage
        from email import policy
        from pathlib import Path

        wiring = json.loads(Path(sys.argv[1]).read_text())
        def image_command(binds):
            view = binds.split('[view]\n', 1)[1].split('[view::', 1)[0]
            line = next(line.strip() for line in view.splitlines() if line.strip().startswith('<Space>wi = '))
            assert line.startswith('<Space>wi = :pipe -s -m '), 'image view must receive full MIME and close on pager exit'
            return line.removeprefix('<Space>wi = :pipe -s -m ').split('<Enter>', 1)[0]
        command = image_command(wiring['binds'])
        for broken in [re.sub(r'^\s*<Space>wi = .*$', "", wiring['binds'], flags=re.M),
                       wiring['binds'].replace('<Space>wi = :pipe -s -m ', '<Space>wi = :pipe -s -p ')]:
            assert broken != wiring['binds'], 'seeded wiring mutation did not match'
            try:
                image_command(broken)
            except (StopIteration, AssertionError):
                pass
            else:
                raise AssertionError('image wiring check accepted a removed or part-only binding')
        assert not re.search(r'^image/\*\s*=', wiring['conf'].split('[filters]', 1)[1].split('[openers]', 1)[0], re.M)
        # Run the generated binding, replacing only its interactive pager.
        pager_pattern = r'/nix/store/[^\s]+/bin/less -R -~'
        assert len(re.findall(pager_pattern, command)) == 1
        command = re.sub(pager_pattern, '${pkgs.coreutils}/bin/cat', command)
        def chunk(kind, data):
            return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(b'\0\xff\0\0\0\0\xff' * 2)) + chunk(b'IEND', b"")
        def message(data=png, narrow=False):
            msg = EmailMessage()
            picture = '<img src="cid:picture" alt="Fixture">'
            if narrow:
                picture = '<table width="8"><tr><td>' + picture + '</td></tr></table>'
            msg.set_content('<p>Before picture</p>' + picture +
                '<p>After picture</p><img src="https://tracking.invalid/pixel" alt="Remote">'
                '<img src="cid:missing" alt="Missing">'
                '<p>\x1b[31muntrusted\x1b[0m</p>'
                '<a href="https://example.invalid/?a=1&amp;b=2">Action</a>', subtype='html')
            msg.add_related(data, maintype='image', subtype='png', cid='<picture>')
            return msg.as_bytes(policy=policy.SMTP)
        def run(raw):
            result = subprocess.run(shlex.split(command), input=raw, capture_output=True, timeout=30)
            assert result.returncode == 0, result.stderr
            return result.stdout.decode()
        output = run(message())
        assert all(label in output for label in ['Before picture', '[Fixture]', 'After picture']), repr(output)
        assert output.index('Before picture') < output.index('[Fixture]') < output.index('After picture')
        assert '\x1b[' in output, 'real chafa must produce colored image cells'
        assert '\x1b[31m' not in output, 'sender terminal controls escaped sanitization'
        assert 'Remote: remote image blocked' in output
        assert 'Missing: attached image missing' in output
        assert 'https://example.invalid/?a=1&b=2' in output, 'HTML action URL changed'
        for _ in range(5):
            narrow_output = run(message(narrow=True))
            assert '[Fixture]' in narrow_output, 'narrow layout or bounded decoding lost the image'
        assert 'image could not be displayed' in run(message(b'not a PNG'))
        plain = EmailMessage()
        plain.set_content('Plain message\n\x1b[31muntrusted\x1b[0m')
        assert '\x1b' not in run(plain.as_bytes())
        many = EmailMessage()
        many.set_content('<img src="cid:missing">' * 40, subtype='html')
        bounded = run(many.as_bytes())
        assert bounded.count('attached image missing') == 32
        assert 'Image limit reached' in bounded
        oversized = subprocess.run(shlex.split(command), input=b'x' * (32 * 1024 * 1024 + 1),
                                   capture_output=True, timeout=30)
        assert oversized.returncode != 0 and b'Use the normal view' in oversized.stderr
        print('aerc image binding: MIME ordering, real image output, links, blocked remote images, missing/corrupt images, and control sanitization pass')
        PY
        touch "$out"
      '';

      # Workflow state drives the sidebar; Domain and factual tags are columns
      # and filters. Laya is the sole automatic content classifier.
      mail-classifier-tests = pkgs.runCommand "mail-classifier-tests" {} ''
        # Exercise the packaged Python boundary, not only the host's Python.
        ${pkgs.python3}/bin/python3 ${inputs.system-one}/scripts/mail_classifier_test.py
        touch "$out"
      '';

      mail-health-lanes = pkgs.runCommand "mail-health-lanes" {} ''
        ${pkgs.python3}/bin/python3 - ${mailHome.home.file.".local/bin/mail-health-check".source} <<'PYTEST'
        import copy, json, os, pathlib, re, shlex, sqlite3, subprocess, sys, tempfile, time
        source = pathlib.Path(sys.argv[1]).read_text()
        fresh = {'state':'healthy','lastOutcome':'success','exitCode':0,'lastSuccessEpoch':time.time()}
        base = {'schemaVersion':2,'lanes':{key:copy.deepcopy(fresh) for key in ['fetch/proton','index','commands','labels','residency']}}
        review = copy.deepcopy(base)
        review['lanes']['commands'].update(pendingCount=1,oldestPendingAgeSeconds=1801)
        review['lanes']['labels'].update(state='degraded',conflictCount=1)

        def runner(text, root, infrastructure=False):
            # Run the generated producer, routing, cards and publisher. Local
            # probe ports are controlled; no real credentials or services run.
            for name in ['check_gpg','check_pass','check_bridge','check_freshness']:
                injected = 'infra fixture-auth-failed "Fixture authentication is unavailable."' if name=='check_gpg' and infrastructure else ':'
                text,count = re.subn(r'(?m)^\s*'+name+r'\s*$',injected,text)
                assert count==1,(name,count)
            bindings={'SYNC_STATUS':str(root/'status.json'),'TRACKER_FILE':str(root/'tracker.json'),
                      'HOST':'fixture','STALE_SECONDS':'0','ESCALATE_SECONDS':'1800'}
            for name,value in bindings.items():
                text,count=re.subn(r'(?m)^\s*'+name+r'=.*$',name+'='+shlex.quote(value),text)
                assert count==1,(name,count)
            ports='send_webhook() { printf "A:%s\\n" "$*"; }\nsend_notify() { printf "N:%s\\n" "$*"; }\n'
            needle='if ! REPORT=$('
            assert text.count(needle)==1
            return text.replace(needle,ports+needle,1)

        def run(script, root, status):
            (root/'status.json').write_text(json.dumps(status))
            result=subprocess.run(['${pkgs.bash}/bin/bash','-c',script],capture_output=True,text=True,
                env={**os.environ,'HOME':str(root),'XDG_STATE_HOME':str(root/'state')})
            assert result.returncode==0,result.stderr
            summary=json.loads((root/'state/mail-health/summary.json').read_text())
            assert summary['checker']=='ok'
            return result.stdout.splitlines(),summary

        def notifications(lines,prefix):return sum(line.startswith(prefix) for line in lines)
        sentinel={'id':'human-card','done':False,'context':'Preserve the human decision.'}
        with tempfile.TemporaryDirectory() as directory:
            root=pathlib.Path(directory);(root/'tracker.json').write_text(json.dumps({'cards':[sentinel]}))
            script=runner(source,root)
            first,summary=run(script,root,review)
            assert {(i['lane'],i['outcome']) for i in summary['issues']}=={('commands','warning'),('labels','warning')},summary
            assert notifications(first,'A:')==2 and notifications(first,'N:')==0,first
            repeated,_=run(script,root,review)
            assert notifications(repeated,'A:')==notifications(repeated,'N:')==0,repeated
            cards=json.loads((root/'tracker.json').read_text())['cards']
            assert sentinel in cards and len([c for c in cards if c['id'].startswith('MH-')])==2,cards
            stale=copy.deepcopy(review);stale['lanes']['index']['lastSuccessEpoch']=1
            opened,summary=run(script,root,stale)
            assert ('index','critical') in {(i['lane'],i['outcome']) for i in summary['issues']},summary
            assert notifications(opened,'N:')==1,opened
            repeated,_=run(script,root,stale)
            assert notifications(repeated,'A:')==notifications(repeated,'N:')==0,repeated
            closed,summary=run(script,root,base)
            assert summary['issues']==[],summary
            assert notifications(closed,'A:')==3 and notifications(closed,'N:')==0,closed
            cards=json.loads((root/'tracker.json').read_text())['cards']
            assert sentinel in cards and all(c['done'] for c in cards if c['id'].startswith('MH-')),cards
            missing,summary=run(script,root,{})
            assert ('availability','critical') in {(i['lane'],i['outcome']) for i in summary['issues']},summary
            assert notifications(missing,'N:')>=1,missing
            db=sqlite3.connect(root/'state/mail-health/cases.sqlite')
            assert db.execute('SELECT count(*) FROM health_judgments').fetchone()[0]>6
            db.close()

        def check_infrastructure(text):
            with tempfile.TemporaryDirectory() as directory:
                root=pathlib.Path(directory);(root/'tracker.json').write_text(json.dumps({'cards':[sentinel]}))
                script=runner(text,root,infrastructure=True)
                lines,summary=run(script,root,base)
                issue=next((i for i in summary['issues'] if i['code']=='fixture-auth-failed'),None)
                assert issue and issue['outcome']=='warning',summary
                db=sqlite3.connect(root/'state/mail-health/cases.sqlite')
                db.execute('UPDATE health_judgments SET at=? WHERE case_id=?',(time.time()-1900,issue['caseId']))
                db.commit();db.close()
                lines,summary=run(script,root,base)
                issue=next(i for i in summary['issues'] if i['code']=='fixture-auth-failed')
                assert issue['outcome']=='critical' and notifications(lines,'N:')==1,(lines,summary)
                lines,_=run(script,root,base)
                assert notifications(lines,'A:')==notifications(lines,'N:')==0,lines
        check_infrastructure(source)
        needle='--extra-issues "$ISSUES_FILE"'
        assert source.count(needle)==1
        try:check_infrastructure(source.replace(needle,"",1))
        except AssertionError:pass
        else:raise AssertionError('removed infrastructure input passed the generated health check')
        print('generated health: one case store, warnings, missing/stale delivery, escalation, transition alerts and bounded cards pass')
        PYTEST
        touch "$out"
      '';

      mail-residency-shadow = let
        home = mailHome;
        standalone = self.homeConfigurations."eric@${mailHost}".config;
        system = self.nixosConfigurations.${mailHost}.config;
        ownerDir = builtins.dirOf system.hwc.paths.user.mailSyncStatus;
        producers = with system.systemd.services; [ morning-briefing mail-retriage ];
        transportChannels = (import ./domains/mail/mbsync/parts/render.nix { config = home; inherit lib pkgs; }).transportChannels;
        fixture = pkgs.writeText "mail-residency-shadow.json" (builtins.toJSON {
          inherit transportChannels;
          script = home.home.file.".local/bin/sync-mail".text;
          standaloneScript = standalone.home.file.".local/bin/sync-mail".text;
          mbsyncrc = home.home.file.".mbsyncrc".text;
          afew = home.xdg.configFile."afew/config".text;
          command = home.hwc.mail.classifier.residency.command;
          projection = home.hwc.mail.classifier.projection.command;
          statusFile = home.hwc.mail.mbsync.statusFile;
          maildirRoot = home.hwc.mail.notmuch.maildirRoot;
          triage = builtins.readFile ./domains/business/morning-briefing/triage-mail.sh;
        });
      in
      assert lib.assertMsg (lib.all (service:
        service.environment.MAIL_SYNC_LOCK_FILE == "${ownerDir}/sync.lock"
        && builtins.elem ownerDir service.serviceConfig.ReadWritePaths) producers
        && system.systemd.services.mail-retriage.serviceConfig.SuccessExitStatus == 75)
        "mail-residency-shadow: scheduled classification must share the writable mail owner lock and defer busy runs";
      assert lib.assertMsg (standalone.hwc.mail.classifier.residency.enable
        && standalone.hwc.mail.classifier.projection.enable
        && lib.hasInfix "coordinate" standalone.home.file.".local/bin/sync-mail".text)
        "mail-residency-shadow: standalone client activation must retain mail reconciliation and projection";
      assert lib.assertMsg home.hwc.mail.classifier.residency.enable
        "mail-residency-shadow: mail host must observe in shadow";
      pkgs.runCommand "mail-residency-shadow" {} ''
        ${pkgs.python3}/bin/python3 - ${fixture} <<'PY'
        import json
        import os
        import pathlib
        import re
        import shlex
        import subprocess
        import sys
        import tempfile

        fixture = json.loads(pathlib.Path(sys.argv[1]).read_text())
        original = fixture['script']
        # Exercise the actual scheduled producer against a held kernel lock.
        # Removing its lock integration must reach the fake effect and fail.
        import fcntl
        import socket
        def classifier_busy(source):
            with tempfile.TemporaryDirectory() as tmp:
                root = pathlib.Path(tmp)
                script = root / 'triage-mail.sh'
                script.write_text(source.replace('/run/current-system/sw/bin/flock', '${pkgs.util-linux}/bin/flock'))
                (root / 'output').mkdir()
                (root / 'output' / 'briefing.json').write_text('{}')
                (root / 'output' / 'mail-triage.json').write_text('{"generated_at":"retained-report","threads_by_state":{}}')
                effect = root / 'effect'
                classifier = root / 'classifier'
                classifier.write_text('#!/bin/sh\ntouch "$CALLS"\nexit 0\n')
                classifier.chmod(0o755)
                model = socket.socket(socket.AF_UNIX)
                model.bind(str(root / 'model.sock'))
                with open(root / 'sync.lock', 'w') as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX)
                    env = {**os.environ, 'PATH': '${lib.makeBinPath [ pkgs.coreutils pkgs.jq ]}', 'CLASSIFIER_BIN': str(classifier),
                        'MAIL_CLASSIFIER_SOCKET': str(root / 'model.sock'),
                        'MAIL_SYNC_LOCK_FILE': str(root / 'sync.lock'), 'CALLS': str(effect)}
                    result = subprocess.run(['${pkgs.bash}/bin/bash', str(script), 'delta'], env=env, capture_output=True, timeout=10)
                    assert result.returncode == 75 and not effect.exists(), result.stderr
                    published = json.loads((root / 'dashboard' / 'briefing.json').read_text())
                    assert published['mail_triage']['generated_at'] == 'retained-report'
                model.close()
        classifier_busy(fixture['triage'])
        stripped = fixture['triage'].replace('/run/current-system/sw/bin/flock -n -E 75 "$' + '{MAIL_SYNC_LOCK_FILE:?mail owner lock binding required}" ', "")
        assert stripped != fixture['triage']
        try:
            classifier_busy(stripped)
        except AssertionError:
            pass
        else:
            raise AssertionError('removed scheduled classifier lock escaped its effect test')
        import copy, importlib.util
        runtime = '${inputs.system-one}/scripts/mail_classifier.py'
        spec = importlib.util.spec_from_file_location('mail', runtime)
        mail = importlib.util.module_from_spec(spec); spec.loader.exec_module(mail)
        def configuration(wrapper):
            return json.loads(pathlib.Path(re.search(r'--config (\S+)',wrapper)[1]).read_text())
        config = configuration(original)
        def wiring(candidate):
            steps = dict(candidate['commandSteps'])
            assert list(steps) == ['flags','apply','mirror','index','ack','final-index']
            assert '--push-flags' in steps['flags']
            assert steps['flags'][-len(fixture['transportChannels']):] == fixture['transportChannels']
            assert '--phase apply' in steps['apply'][-1]
            assert '--phase ack' in steps['ack'][-1]
            assert '--pull-gone' in steps['mirror']
            assert fixture['command'] == candidate['observation'][-1]
            assert fixture['projection'] == candidate['labels'][-1]
            assert candidate['accounts']['proton']['upload'][-2:] == ['proton-drafts','proton-sent']
            assert '[MailMover]' not in fixture['afew']
        wiring(config); wiring(configuration(fixture['standaloneScript']))
        for step in ['flags','mirror','apply','ack']:
            broken=copy.deepcopy(config);broken['commandSteps']=[row for row in broken['commandSteps'] if row[0]!=step]
            try: wiring(broken)
            except AssertionError: pass
            else: raise AssertionError('removed owner wiring passed: '+step)
        broken=copy.deepcopy(config);broken['commandSteps'].append(['mover',['afew','-m','-a']])
        try: wiring(broken)
        except AssertionError: pass
        else: raise AssertionError('competing mover escaped wiring test')
        for failed in ["", 'fetch/proton','fetch/gmail-personal','index','commands/apply','labels','residency']:
            status={};calls=[]
            def execute(argv, timeout):
                calls.append(argv)
                if failed.startswith('fetch/'):
                    return 23 if argv == config['accounts'][failed.split('/')[1]]['fetch'] else 0
                actual = config['index'] if failed=='index' else dict(config['commandSteps']).get(failed.removeprefix('commands/')) if failed.startswith('commands/') else config.get('observation' if failed=='residency' else failed)
                return 23 if actual and argv==actual else 0
            rc=mail.coordinate_mail(config,'core',status,execute,lambda:10000,lambda _:None,
                lambda:{'commands':[],'unknownEffects':[]})
            assert rc == (23 if failed.startswith('fetch/') or failed=='index' else 0)
            assert config['index'] in calls
            assert status['lanes']['fetch/gmail-business']['state']=='healthy'
            if failed=='commands/apply':
                assert status['lanes']['core']['state']=='healthy'
                assert status['lanes']['commands']['state']=='degraded'
        with tempfile.TemporaryDirectory() as directory:
            rcfile=pathlib.Path(directory)/'mbsyncrc';rcfile.write_text(fixture['mbsyncrc'])
            parsed=subprocess.run(['${pkgs.isync}/bin/mbsync','-c',str(rcfile),'nonexistent-fixture-channel'],capture_output=True,text=True)
            assert parsed.returncode==1 and "No channel or group named 'nonexistent-fixture-channel' defined." in parsed.stderr, parsed.stderr
            assert 'global options' not in parsed.stderr, parsed.stderr
        blocks=fixture['mbsyncrc'].split('Channel ')
        proton=next(block for block in blocks if block.startswith('proton-wildcards\n'))
        assert 'Sync Pull PushFlags' in proton and 'Expunge Near' in proton
        assert 'Expunge Both' not in proton and 'Create Both' not in proton
        assert all('!"'+name+'"' in proton for name in ['Trash','Drafts','Sent'])
        print('actual coordinator configuration: independent fetch, physical owner, ancillary parity, parser and seeded wiring failures pass')
        PY
        touch "$out"
      '';

      mail-workflow-v2 = let
        home = mailHome;
        identity = home.programs.notmuch.extraConfig.user;
        ownAddresses = [ identity.primary_email ] ++ lib.splitString ";" identity.other_email;
        controls = lib.findFirst (package: lib.getName package == "mail-classifier")
          (throw "mail-workflow-v2: classifier controls missing") home.home.packages;
        binds = home.home.file.".config/aerc/binds.conf".text;
        aercConf = home.home.file.".config/aerc/aerc.conf".text;
        queries = home.home.file.".config/aerc/notmuch-queries".text;
        queryHas = name: query: lib.elem "${name}=${query}" (lib.splitString "\n" queries);
        hook = home.home.file."/home/eric/400_mail/Maildir/.notmuch/hooks/post-new".text;
        bindLines = lib.splitString "\n" binds;
        bindCount = needle: lib.length (lib.filter (line: lib.hasInfix needle line) bindLines);
        archiveDisposition = "      a = :pipe -b -m mail-classifier transition --outcome done<Enter>";
        trashDisposition = "      d = :pipe -b -m mail-classifier transition --outcome trash<Enter>";
        requiredBinds = [
          "<Space>gA = :cf all<Enter>"
          "<Space>sf = :sort from -r date<Enter>"
          "<Space>sa = :sort subject<Enter>"
          "<Space>ss = :sort subject -r date<Enter>"
        ];
        missingBinds = lib.filter (needle: !(lib.hasInfix needle binds)) requiredBinds;
        hookFixture = pkgs.writeText "mail-post-new-hook" hook;
        afewTest = import ./domains/mail/afew/package.nix { inherit lib pkgs; cfg = home.hwc.mail.afew; };
        afewFixture = pkgs.writeText "mail-afew-config" home.xdg.configFile."afew/config".text;
      in
      assert lib.assertMsg (lib.all (address: lib.elem address ownAddresses)
        [ "eric@iheartwoodcraft.com" "office@iheartwoodcraft.com" "admin@iheartwoodcraft.com" "eric@contractorcto.com" ])
        "mail-workflow-v2: declared identities miss Eric's aliases; self-learning guard would be incomplete";
      assert lib.assertMsg (missingBinds == [])
        "mail-workflow-v2: generated server binds are missing ${lib.concatStringsSep ", " missingBinds}";
      assert lib.assertMsg (bindCount archiveDisposition == 2 && bindCount trashDisposition == 2
        && !(lib.hasInfix ":unmark -a<Enter>:mark -T<Enter>:modify-labels" binds))
        "mail-workflow-v2: archive/trash must preserve marked-message bulk selections";
      assert lib.assertMsg (bindCount "<Space>tt = :fold -t<Enter>" == 1
        && bindCount "<Space>ta = :fold -a<Enter>" == 1
        && !(lib.hasInfix ":toggle-threads<Enter>" binds))
        "mail-workflow-v2: thread fold controls changed unexpectedly";
      assert lib.assertMsg (bindCount "<Space>ma = :pipe -b -m mail-classifier transition --outcome done<Enter>" == 2
        && bindCount "<Space>dd = :pipe -b -m mail-classifier transition --outcome trash<Enter>" == 2)
        "mail-workflow-v2: marked-message archive/trash controls changed unexpectedly";
      assert lib.assertMsg (lib.hasInfix "sort = -r date" aercConf)
        "mail-workflow-v2: newest-first is not the default sort";
      assert lib.assertMsg (queryHas "do" "tag:state/do"
        && queryHas "dont-know" "tag:state/dont-know"
        && queryHas "did" "tag:state/did"
        && queryHas "look" "tag:state/look"
        && queryHas "junk" "tag:state/junk")
        "mail-workflow-v2: workflow state views regressed";
      assert lib.assertMsg (!(lib.hasInfix "category/" queries)
        && !(lib.hasInfix "attention/" queries)
        && !(lib.hasInfix "tag:queue" queries)
        && queryHas "all" "NOT tag:trash")
        "mail-workflow-v2: legacy workflow/category folders returned";
      assert lib.assertMsg (lib.hasInfix "index-columns = from<20,subject<*,date<10,domain<9,state<9,tags<24" aercConf
        && lib.hasInfix "column-domain" aercConf
        && lib.hasInfix "column-state" aercConf
        && lib.hasInfix "column-tags" aercConf)
        "mail-workflow-v2: workflow columns regressed";
      assert lib.assertMsg (!(lib.hasInfix ")(exclude" aercConf))
        "mail-workflow-v2: generated aerc template operands must be whitespace-separated";
      pkgs.runCommand "mail-workflow-v2" {} ''
        ${pkgs.python3}/bin/python3 - ${hookFixture} ${controls}/bin/mail-classifier ${afewFixture} <<'PY'
        import fnmatch
        import json
        import os
        import pathlib
        import shlex
        import subprocess
        import sys
        import tempfile

        hook = pathlib.Path(sys.argv[1]).read_text()
        managed_prefix = ${builtins.toJSON mailHome.hwc.mail.classifier.contract.protonSync.managedLabelPrefix}
        managed_mailbox = ${builtins.toJSON mailHome.hwc.mail.classifier.contract.protonSync.labelMailboxPrefix}
        mbsyncrc = ${builtins.toJSON mailHome.home.file.".mbsyncrc".text}
        label_exclusion = '!"' + managed_mailbox + '*"'
        assert label_exclusion in mbsyncrc


        def check_label_isolation(text):
            patterns = shlex.split(next(line for line in text.splitlines()
                                        if line.startswith('Patterns ')))[1:]
            def selected(name):
                result = False
                for pattern in patterns:
                    excluded = pattern.startswith('!')
                    if fnmatch.fnmatchcase(name, pattern[1:] if excluded else pattern):
                        result = not excluded
                return result
            for name in ['work', 'finance', managed_prefix + 'hwc']:
                assert not selected(managed_mailbox + name), name
            for name in ['INBOX', 'Archive', 'Folders/hide_my_email']:
                assert selected(name), name


        check_label_isolation(mbsyncrc)
        try:
            check_label_isolation(mbsyncrc.replace(label_exclusion, ""))
        except AssertionError:
            pass
        else:
            raise AssertionError('removed label exclusion passed its wiring check')
        folder_state = hook.index("+inbox +state/dont-know")
        remove_new = hook.index("# Remove transient new tag", folder_state)
        assert folder_state < remove_new, "new mail loses its DONT KNOW State"
        assert "mail-rule" not in hook, "retired sender-rule writer returned"
        assert "tag:new AND NOT tag:keep" not in hook, "legacy sender placement returned"

        def check_arrival_states(source):
            with tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory); mail = root / 'Maildir'
                for folder in ['inbox', 'Sent']:
                    for part in ['cur', 'new', 'tmp']: (mail / 'proton' / folder / part).mkdir(parents=True)
                config = root / 'notmuch.conf'
                config.write_text('[database]\npath=' + str(mail) + '\n[user]\nname=Fixture\nprimary_email=fixture@example.invalid\n[new]\ntags=new;unread;\n[maildir]\nsynchronize_flags=true\n')
                env = {**os.environ, 'NOTMUCH_CONFIG': str(config), 'XDG_CONFIG_HOME': str(root / 'config')}
                hp = mail / '.notmuch' / 'hooks' / 'post-new'; hp.parent.mkdir(parents=True)
                hp.write_text(source.replace('export NOTMUCH_CONFIG="$HOME/.notmuch-config"', 'export NOTMUCH_CONFIG=' + shlex.quote(str(config))))
                hp.chmod(0o700)
                def nm(*args): return subprocess.check_output(['${pkgs.notmuch}/bin/notmuch', *args], env=env, text=True)
                def tags(mid): return set(json.loads(nm('search', '--format=json', '--output=tags', 'id:' + mid + '@example.invalid')))
                for mid, folder, sender in [('arrival', 'inbox', 'sender@example.invalid'), ('selfsent', 'Sent', 'office@iheartwoodcraft.com')]:
                    (mail / 'proton' / folder / 'cur' / (mid + ':2,F')).write_text(
                        'Message-ID: <' + mid + '@example.invalid>\nFrom: ' + sender + '\nTo: eric@iheartwoodcraft.com\nSubject: Synthetic\nDate: Thu, 01 Oct 2026 12:00:00 +0000\n\nFixture\n')
                nm('new')
                for mid in ['arrival', 'selfsent']:
                    assert {'inbox', 'state/dont-know', 'flagged'} <= tags(mid), tags(mid)
                    assert 'state/do' not in tags(mid), tags(mid)
                nm('tag', '+state/do', '-state/dont-know', '--', 'id:selfsent@example.invalid')
                nm('new')
                assert {'inbox', 'state/do', 'flagged'} <= tags('selfsent'), tags('selfsent')
                assert 'state/dont-know' not in tags('selfsent'), tags('selfsent')
        check_arrival_states(hook)
        try:
            check_arrival_states(hook.replace('+state/dont-know', '+state/do'))
        except AssertionError:
            pass
        else:
            raise AssertionError('removed unknown arrival wiring passed its real-tool replay')

        def check_remote_reopen(source):
            with tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                mail = root / 'Maildir'
                for folder in ['inbox', 'Archive', 'Trash', 'Spam']:
                    for part in ['cur', 'new', 'tmp']:
                        (mail / 'proton' / folder / part).mkdir(parents=True)
                config = root / 'notmuch.conf'
                config.write_text('[database]\npath=' + str(mail) + '\n[user]\nname=Fixture\nprimary_email=fixture@example.invalid\n[new]\ntags=new;unread;\n[maildir]\nsynchronize_flags=true\n')
                env = {**os.environ, 'NOTMUCH_CONFIG': str(config),
                       'XDG_CONFIG_HOME': str(root / 'config'), 'PATH': '${pkgs.notmuch}/bin:' + os.environ.get('PATH', "")}
                afew = root / 'config' / 'afew' / 'config'
                afew.parent.mkdir(parents=True)
                afew.write_text(pathlib.Path(sys.argv[3]).read_text().replace('${home.hwc.mail.notmuch.maildirRoot}', str(mail)))
                hp = mail / '.notmuch' / 'hooks' / 'post-new'
                hp.parent.mkdir(parents=True)
                hp.write_text(source.replace('export NOTMUCH_CONFIG="$HOME/.notmuch-config"', 'export NOTMUCH_CONFIG=' + shlex.quote(str(config))))
                hp.chmod(0o700)
                def nm(*args):
                    return subprocess.check_output(['${pkgs.notmuch}/bin/notmuch', *args], env=env, text=True)
                archived = mail / 'proton' / 'Archive' / 'cur' / 'fixture:2,S'
                raw = 'Message-ID: <reopen@example.invalid>\nFrom: sender@example.invalid\nTo: fixture@example.invalid\nSubject: Fixture\nDate: Wed, 30 Sep 2026 12:00:00 +0000\n\nSynthetic content\n'
                archived.write_text(raw); nm('new')
                nm('tag', '+workflow/done', '+mail-classified-v2', '+archive', '-inbox', '--', 'id:reopen@example.invalid')
                # The fetched remote move creates another filename for the same
                # known ID. It is not fresh message content or a human correction.
                for path in (mail / 'proton' / 'Archive' / 'cur').iterdir(): path.unlink()
                (mail / 'proton' / 'inbox' / 'cur' / 'reopened:2,S').write_text(raw)
                for _ in range(3):
                    nm('new')
                    subprocess.run(['${afewTest}/bin/afew', '-t', '-a'], env=env, check=True, capture_output=True)
                    tags = json.loads(nm('search', '--format=json', '--output=tags', 'id:reopen@example.invalid'))
                    assert 'inbox' in tags and 'archive' not in tags, tags
                    assert 'workflow/done' in tags, 'transport repair must not promote S1'
                    assert len(list((mail / 'proton' / 'inbox' / 'cur').iterdir())) == 1
        check_remote_reopen(hook)
        reopen_line = next(line for line in hook.splitlines() if 'tag +inbox -archive -trash -spam -sent -draft' in line)
        try:
            check_remote_reopen(hook.replace(reopen_line, ""))
        except AssertionError:
            pass
        else:
            raise AssertionError('removed remote-reopen wiring passed its real-tool replay')

        def check_phone_trash(source):
            assert '[MailMover]' not in source, 'retired mailbox writer returned'
            with tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory); mail = root / 'Maildir'
                for folder in ['inbox', 'Archive', 'Trash', 'Spam']:
                    for part in ['cur', 'new', 'tmp']: (mail / 'proton' / folder / part).mkdir(parents=True)
                config = root / 'notmuch.conf'
                config.write_text('[database]\npath=' + str(mail) + '\n[user]\nname=Fixture\nprimary_email=fixture@example.invalid\n[new]\ntags=new;unread;inbox;\n[maildir]\nsynchronize_flags=true\n')
                env = {**os.environ, 'NOTMUCH_CONFIG': str(config), 'XDG_CONFIG_HOME': str(root / 'config'), 'PATH':'${pkgs.notmuch}/bin:' + os.environ.get("PATH", "")}
                afew = root / 'config' / 'afew' / 'config'; afew.parent.mkdir(parents=True)
                afew.write_text(source.replace('${home.hwc.mail.notmuch.maildirRoot}', str(mail)))
                hp = mail / '.notmuch' / 'hooks' / 'post-new'; hp.parent.mkdir(parents=True)
                hp.write_text(hook.replace('export NOTMUCH_CONFIG="$HOME/.notmuch-config"', 'export NOTMUCH_CONFIG=' + shlex.quote(str(config)))); hp.chmod(0o700)
                def nm(*args): return subprocess.check_output(['${pkgs.notmuch}/bin/notmuch', *args], env=env, text=True)
                def move(): subprocess.run(['${afewTest}/bin/afew', '-t', '-a'],env=env,check=True,capture_output=True)
                # Durable human commands also apply to old mail. A fixed old
                # date catches an accidental MailMover age filter.
                raw = 'Message-ID: <trash@example.invalid>\nFrom: sender@example.invalid\nTo: fixture@example.invalid\nSubject: Fixture\nDate: Sat, 01 Jan 2000 12:00:00 +0000\n\nSynthetic content\n'
                inbox = mail / 'proton/inbox/cur/old:2,S'; trash = mail / 'proton/Trash/cur/fetched:2,S'
                inbox.write_text(raw); nm('new'); trash.write_text(raw); nm('new')
                # A partial physical copy and stale Inbox tag are NOT local restore intent.
                move(); assert trash.exists(), 'stale Inbox undid fetched Trash'
                assert inbox.exists(), 'partial copy was deleted'
                inbox.unlink(); nm('new')
                for _ in range(3):
                    move(); nm('new')
                    assert trash.exists() and not list((mail/'proton/inbox/cur').iterdir())
                # Tags and old intent markers cannot move a physical file.
                nm('tag','+transport/inbox','+inbox','-trash','--','id:trash@example.invalid')
                move(); nm('new')
                assert trash.exists() and not list((mail/'proton/inbox/cur').iterdir())
        afew_source = pathlib.Path(sys.argv[3]).read_text()
        check_phone_trash(afew_source)
        try:
            check_phone_trash(afew_source + "\n[MailMover]\nrename = True\n")
        except AssertionError:
            pass
        else:
            raise AssertionError('retired mover passed the writer isolation check')

        # Exercise the actual generated dispatcher with only its runtime binding
        # substituted. Removing reopen from that dispatcher must lose db/notmuch.
        control = pathlib.Path(sys.argv[2]).read_text()
        runtime_path = "/run/current-system/sw/bin/mail-classifier-runtime"
        assert control.count(runtime_path) == 1
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            # Exercise the actual legacy label loop. Its directory and notmuch
            # executable are the only substituted dependencies.
            labels = root / "Labels"
            labels.mkdir()
            for name in ['finance', managed_prefix + 'look', '_work']:
                (labels / name).mkdir()
            tags = root / 'tags'
            tagger = root / 'notmuch'
            tagger.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" >> " + str(tags) + "\n")
            tagger.chmod(0o755)
            start = hook.index('# Dynamic Proton label → notmuch tag mapping')
            end = hook.index('# Shield: kept mail', start)
            fragment = hook[start:end]
            import re
            fragment = re.sub(r'_LABELS_DIR=.*', '_LABELS_DIR="' + str(labels) + '"', fragment)
            fragment = re.sub(r'/nix/store/[^\s"\x27]+/bin/notmuch\b', str(tagger), fragment)
            def check_labels(text):
                tags.write_text("")
                subprocess.run(['${pkgs.bash}/bin/bash', '-c', text], check=True)
                applied = tags.read_text().splitlines()
                assert '+finance' in applied
                assert '+' + managed_prefix + 'look' not in applied
                assert '+_work' not in applied
            check_labels(fragment)
            try:
                check_labels(fragment.replace('|' + managed_prefix + '*', ""))
            except AssertionError:
                pass
            else:
                raise AssertionError('removed managed-label skip passed its check')
            runtime = root / "runtime"
            runtime.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
            runtime.chmod(0o755)
            def dispatch(text, verb="reopen", *arguments):
                wrapper = root / "wrapper"
                lock_path = ${builtins.toJSON "${builtins.dirOf mailHome.hwc.mail.mbsync.statusFile}/sync.lock"}
                wrapper.write_text(text.replace(runtime_path, str(runtime)).replace(lock_path, str(root / 'sync.lock')))
                wrapper.chmod(0o755)
                return subprocess.check_output([str(wrapper), verb, *arguments], text=True).splitlines()
            def check_withdraw_lock(source):
                import fcntl
                with (root / 'sync.lock').open('a') as owner:
                    fcntl.flock(owner,fcntl.LOCK_EX | fcntl.LOCK_NB)
                    assert dispatch(source,'review-transport')[0]=='review-transport'
                    for arguments in [('--withdraw','a'*64),('--withdraw='+'a'*64,)]:
                        try: dispatch(source,'review-transport',*arguments)
                        except subprocess.CalledProcessError as error: assert error.returncode==75
                        else: raise AssertionError('withdraw bypassed the active effect owner')
                    try: dispatch(source,'withdraw-transport','--command-id','a'*64)
                    except subprocess.CalledProcessError as error: assert error.returncode==75
                    else: raise AssertionError('withdraw alias bypassed the active effect owner')
                assert '--withdraw' in dispatch(source,'review-transport','--withdraw','a'*64)
            check_withdraw_lock(control)
            try: check_withdraw_lock(control.replace('"$arg" == --withdraw || "$arg" == --withdraw=*','"$arg" == --removed-withdraw'))
            except AssertionError: pass
            else: raise AssertionError('removed withdrawal guard passed its wiring check')
            def check(arguments):
                assert arguments[0] == "reopen"
                assert arguments[1:3] == ["--db", "/var/lib/hwc/mail-classifier/ledger.sqlite"]
                assert arguments[3] == "--notmuch"
            check(dispatch(control))
            observation = dispatch(control, "observe-residency")
            assert observation[:3] == ['observe-residency', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
            assert observation[observation.index('--bridge-host') + 1] == '127.0.0.1'
            assert observation[observation.index('--bridge-port') + 1] == '1143'
            password_command = observation[observation.index('--password-command') + 1]
            assert shlex.split(password_command)[:2] == ['sh', '-c']
            probe = dispatch(control, 'label-probe')
            assert probe[:3] == ['label-probe', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
            assert '--notmuch' not in probe
            projected = dispatch(control, 'project-labels')
            assert projected[:3] == ['project-labels', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
            assert '--notmuch' in projected
            assert projected[projected.index('--output') + 1].endswith('/labels.json')
            reviewed = dispatch(control, 'review-label-write')
            assert reviewed[:3] == ['review-label-write', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
            assert '--bridge-host' in reviewed and '--notmuch' in reviewed
            assert reviewed[reviewed.index('--output') + 1].endswith('/label-review.json')
            try:
                broken_review = dispatch(control.replace('|review-label-write', ""), 'review-label-write')
                assert '--bridge-host' in broken_review and '--notmuch' in broken_review
            except AssertionError:
                pass
            else:
                raise AssertionError('dispatcher accepted removed review wiring')
            try:
                check(dispatch(control.replace("|reopen", "")))
            except AssertionError:
                pass
            else:
                raise AssertionError("dispatcher check accepted removed reopen wiring")
        PY
        touch "$out"
      '';

      # The gateway must run the TypeScript build produced by Nix. Pointing
      # systemd back at ignored checkout dist/ output recreates the stale-code
      # failure this boundary removes. Referencing the entry point also builds
      # the package, whose checkPhase runs the MCP test suite.
      mcp-immutable-build = let
        # The gateway's host follows hwc.system.mcp.serverAlias (hwc-work since
        # service split wave 2), so the check reads that host's unit.
        fleet = self.nixosConfigurations.hwc-home.config.hwc;
        gatewayHost = fleet.networking.hosts.servers.${fleet.system.mcp.serverAlias};
        service = self.nixosConfigurations.${gatewayHost}.config.systemd.services.hwc-sys-mcp;
        command = service.serviceConfig.ExecStart;
        main = lib.last (lib.splitString " " command);
        n8n = service.environment.HWC_N8N_ENTRY_POINT;
      in
      assert lib.assertMsg (builtins.elem (builtins.dirOf service.environment.HWC_MAIL_SYNC_STATUS) service.serviceConfig.ReadWritePaths)
        "mcp-immutable-build: shared mail owner lock must be writable inside the gateway sandbox";
      assert lib.assertMsg (lib.hasPrefix "/nix/store/" main)
        "mcp-immutable-build: gateway entry point is not in the Nix store";
      assert lib.assertMsg (!(lib.hasInfix "/home/eric/.nixos/" main))
        "mcp-immutable-build: gateway returned to mutable checkout dist output";
      assert lib.assertMsg (lib.hasPrefix "/nix/store/" n8n && !(service.serviceConfig ? ExecStartPre))
        "mcp-immutable-build: n8n backend must be immutable with no startup installer";
      pkgs.runCommand "mcp-immutable-build" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
        test -f ${main}
        timeout 45 ${service.environment.HWC_NODE_PATH} \
          ${./domains/system/mcp/parts/n8n-mcp/smoke.mjs} \
          ${n8n} ${service.environment.HWC_NODE_PATH}
        touch "$out"
      '';

      brainvec-deployment = let
        service = self.nixosConfigurations.hwc-work.config.systemd.services.brainvec-ingest;
        env = lib.filterAttrs (name: _: lib.hasPrefix "BRAINVEC_" name) service.environment;
        source = inputs.brainvec;
        reader = self.nixosConfigurations.hwc-work.config.systemd.services.brain-mcp.environment;
      in assert reader.BRAINVEC_SOURCE == toString source;
      assert lib.all (name: reader.${name} == env.${name})
        (builtins.filter (lib.hasPrefix "BRAINVEC_EMBED_") (builtins.attrNames env));
      pkgs.runCommand "brainvec-deployment" { nativeBuildInputs = [ pkgs.nodejs_22 pkgs.deno ]; } ''
        node --test ${source}/contract.test.mjs
        # Test the actual rendered wrapper and environment, not a second launcher.
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") env)}
        export BRAINVEC_VAULT="$TMPDIR/vault" BRAINVEC_CACHE="$TMPDIR/cache"
        mkdir -p "$BRAINVEC_VAULT" "$BRAINVEC_CACHE"
        printf '# Woodworking\nCabinet joinery and wood.\n' > "$BRAINVEC_VAULT/wood.md"
        printf '# Cooking\nSoup recipes.\n' > "$BRAINVEC_VAULT/food.md"
        cat > "$TMPDIR/embed-fixture.mjs" <<'JS'
        globalThis.fetch = async (_url, options) => ({
          ok: true,
          json: async () => ({ data: JSON.parse(options.body).input.map((text, index) => ({
            index, embedding: text.toLowerCase().includes('wood') ? [1, 0] : [0, 1],
          })) }),
        });
        JS
        export NODE_OPTIONS="--import=$TMPDIR/embed-fixture.mjs"
        ${service.serviceConfig.ExecStart}
        node ${source}/query.mjs --json --k 1 woodworking > result.json
        node -e 'const r=require("./result.json"); if(r.hits[0].path!=="wood.md") process.exit(1)'
        cp "$BRAINVEC_CACHE/index.jsonl" expected.jsonl
        # Rebuild from source after discarding the derived fixture index.
        rm "$BRAINVEC_CACHE/index.jsonl" "$BRAINVEC_CACHE/meta.json"
        ${service.serviceConfig.ExecStart}
        cmp expected.jsonl "$BRAINVEC_CACHE/index.jsonl"
        # No changed notes: no embedder, GitHub, git, SSH or writable checkout.
        unset NODE_OPTIONS
        export BRAINVEC_EMBED_BASE_URL=http://127.0.0.1:1
        ${service.serviceConfig.ExecStart}
        cmp expected.jsonl "$BRAINVEC_CACHE/index.jsonl"
        node ${source}/query.mjs --json --related wood.md > related.json
        node -e 'const r=require("./related.json"); if(r.hits[0].path!=="food.md") process.exit(1)'
        # Deno consumes the same Node-compatible adapter and identity.
        export DENO_DIR="$TMPDIR/deno"
        node --input-type=module -e 'import {EMBED_ID} from "${source}/embed.mjs"; console.log(EMBED_ID)' > node-id
        deno eval 'import {EMBED_ID} from "${source}/embed.mjs"; console.log(EMBED_ID)' > deno-id
        cmp node-id deno-id
        # Pin source provenance and prove the production wrapper consumes it.
        ${pkgs.ripgrep}/bin/rg -F '${source}/ingest.mjs' ${service.serviceConfig.ExecStart}
        if ${pkgs.ripgrep}/bin/rg 'git |ssh |600_apps' ${service.serviceConfig.ExecStart}; then
          echo 'brainvec-deployment: mutable checkout or timer-side updater remains' >&2
          exit 1
        fi
        touch "$out"
      '';

      lead-scout-member-recovery = let
        work = self.nixosConfigurations.hwc-work;
        candidate = work.config;
        disabled = (work.extendModules { modules = [{
          hwc.server.ai.leadScout.memberInstance.enable = lib.mkForce false;
        }]; }).config;
        member = candidate.hwc.server.ai.leadScout.memberInstance;
        unit = candidate.systemd.user.services.lead-scout-member-instance;
        s = unit.serviceConfig;
        u = unit.unitConfig;
        commandPath = command: builtins.head (lib.splitString " " command);
        budget = command: lib.toInt (lib.last (lib.splitString " " command));
      in
      assert lib.assertMsg (member.enable && member.projectName == "lead-scout-datax")
        "member recovery: actual work activation/project wiring missing";
      assert lib.assertMsg (!(disabled.systemd.user.services ? lead-scout-member-instance)
        && !(disabled.systemd.user.units ? "lead-scout-member-instance.service")
        && disabled.hwc.server.ai.leadScout.memberInstance.vhost.enable
        && disabled.hwc.server.ai.leadScout.modelBridge.enable)
        "member recovery: disabled compatibility must omit supervision and retain vhost/bridge";
      assert lib.assertMsg (unit.wantedBy == [ "default.target" ]
        && u.ConditionUser == candidate.hwc.server.ai.leadScout.user
        && candidate.users.users.eric.linger
        && unit.environment.COMPOSE_PROJECT_NAME == member.projectName
        && s.WorkingDirectory == member.directory
        && lib.hasSuffix " ${member.projectName}_app_1 ${member.projectName}_db_1" s.ExecStart)
        "member recovery: user activation/adoption wiring missing";
      assert lib.assertMsg (s.Type == "exec" && !(s.RemainAfterExit or false)
        && lib.hasInfix " wait --condition=stopped --exit-first-match " s.ExecStart)
        "member recovery: foreground waiter missing";
      assert lib.assertMsg (builtins.isString s.ExecStartPre && !(s ? ExecStartPost)
        && !(s ? ExecStop)) "member recovery: duplicate preparation/cleanup phases";
      assert lib.assertMsg (s.Restart == "always" && s.RestartSteps == 4
        && s.RestartSec == 15 && s.RestartMaxDelaySec == 240
        && u.StartLimitBurst == 5
        && u.StartLimitIntervalSec > u.StartLimitBurst * (
          budget s.ExecStartPre + s.TimeoutStartSec + s.TimeoutStopSec
          + budget s.ExecStopPost + s.RestartMaxDelaySec))
        "member recovery: start window does not contain failed-start budgets";
      assert lib.assertMsg (builtins.isString s.ExecStartPre && !(s ? ExecStartPost)
        && !(s ? ExecStop) && s.TimeoutStopSec == 90
        && s.KillSignal == "SIGTERM" && s.KillMode == "mixed"
        && s.TimeoutStartFailureMode == "kill" && s.TimeoutStopFailureMode == "kill"
        && !(s ? SuccessExitStatus) && lib.hasPrefix "-" s.ExecStart
        && budget s.ExecStartPre == 300 && budget s.ExecStopPost == 90)
        "member recovery: aggregate preparation/sole cleanup boundary missing";
      assert lib.assertMsg (u.OnFailure == "hwc-service-failure-notifier@lead-scout-member-instance.service"
        && lib.hasSuffix " --user %i" candidate.systemd.user.services."hwc-service-failure-notifier@".serviceConfig.ExecStart)
        "member recovery: user terminal notifier missing";
      pkgs.runCommand "lead-scout-member-recovery" {} ''
        units=${candidate.environment.etc."systemd/user".source}
        test -L "$units/default.target.wants/lead-scout-member-instance.service"
        ${pkgs.ripgrep}/bin/rg -F 'ConditionUser=${candidate.hwc.server.ai.leadScout.user}' "$units/lead-scout-member-instance.service"
        ${pkgs.ripgrep}/bin/rg -F 'OnFailure=${u.OnFailure}' "$units/lead-scout-member-instance.service"
        ${pkgs.ripgrep}/bin/rg -F 'ExecStart=${s.ExecStart}' "$units/lead-scout-member-instance.service"
        ${pkgs.ripgrep}/bin/rg -F 'ExecStartPre=${s.ExecStartPre}' "$units/lead-scout-member-instance.service"
        ${pkgs.ripgrep}/bin/rg -F 'ExecStopPost=${s.ExecStopPost}' "$units/lead-scout-member-instance.service"
        test ! -e ${disabled.environment.etc."systemd/user".source}/lead-scout-member-instance.service
        ${pkgs.ripgrep}/bin/rg -F 'timeout --signal=KILL "$1"' ${commandPath s.ExecStartPre}
        ${pkgs.ripgrep}/bin/rg -F 'timeout --signal=KILL "$1"' ${commandPath s.ExecStopPost}
        steps=$(${pkgs.gawk}/bin/awk 'NF {last=$NF} END {print last}' ${commandPath s.ExecStartPre})
        jitter=$(${pkgs.ripgrep}/bin/rg --no-config --no-line-number '^/nix/store/.*-lead-scout-restart-jitter$' "$steps")
        ${pkgs.ripgrep}/bin/rg -F 'sleep "$((RANDOM % 6))"' "$jitter"
        ${pkgs.ripgrep}/bin/rg -F 'start-limit-hit' ${candidate.hwc.notifications._internal.serviceFailureNotify}/bin/hwc-service-failure-notify
        touch "$out"
      '';

      scout-layout = let
        work = self.nixosConfigurations.hwc-work;
        cfg = work.config;
        root = "${cfg.hwc.paths.user.home}/600_apps/scout";
        check = name: option:
          let
            app = "${root}/apps/${name}";
            service = cfg.systemd.services.${name}.serviceConfig;
            defaults = work.options.hwc.server.ai.${option};
          in lib.assertMsg (
            toString defaults.workspaceRoot.default == root
            && toString defaults.projectDir.default == app
            && toString service.WorkingDirectory == app
            # Direct node, not the tsx CLI wrapper (a second process that
            # relays its own SIGTERM): the unit's main process is node itself,
            # loading the monorepo's hoisted tsx loader and this app's CLI.
            && lib.hasSuffix "/bin/node" (builtins.head (lib.splitString " " service.ExecStart))
            && lib.hasInfix " --import ${root}/node_modules/tsx/dist/loader.mjs ${app}/src/cli.ts serve" service.ExecStart
          ) "scout-layout: ${name} defaults, rendered service or direct-node launcher left the monorepo";
      in
      assert check "lead-scout" "leadScout";
      assert check "home-scout" "homeScout";
      assert lib.all (name:
        toString cfg.systemd.services.${name}.serviceConfig.WorkingDirectory == "${root}/apps/home-scout/ingest"
        && cfg.systemd.services.${name}.environment.PYTHONPATH == "${root}/apps/home-scout/ingest"
      ) [ "home-scout-harvest" "home-scout-cadastral" "home-scout-redfin" "home-scout-schools" "home-scout-overlays" ];
      pkgs.runCommand "scout-layout" {} ''touch "$out"'';

      journal-retention = let
        work = self.nixosConfigurations.hwc-work;
        home = self.nixosConfigurations.hwc-home.config;
        # A host override must still win over the capability's default.
        override = (work.extendModules {
          modules = [ { services.journald.extraConfig = "SystemMaxUse=2G"; } ];
        }).config.services.journald.extraConfig;
      in
      assert lib.assertMsg (lib.hasInfix "SystemMaxUse=1G" work.config.services.journald.extraConfig)
        "journal-retention: work has no explicit default ceiling";
      assert lib.hasInfix "SystemMaxUse=8G" home.services.journald.extraConfig;
      assert override == "SystemMaxUse=2G";
      pkgs.runCommand "journal-retention" {} ''touch "$out"'';

      # ── Prometheus tier ladders are mutually exclusive ──────────────────
      # Parses the ACTUAL rule expressions (not a second copy of the numbers)
      # and proves no sample value can satisfy two tiers of one family. Before
      # the 2026-09-07 change a 96%-full filesystem matched Moderate, Elevated
      # and High at once and sent three messages about one fact.
      alert-tier-exclusivity = let
        alertRules = import ./domains/monitoring/prometheus/parts/alerts.nix { inherit lib; };
        allRules = lib.concatMap (g: g.rules) alertRules.groups;
        ruleNamed = name:
          let hits = lib.filter (r: r.alert == name) allRules;
          in if hits == [] then null else builtins.head hits;
        # Expressions are multi-line; flatten before matching so `.` never has
        # to cross a newline.
        flat = s: lib.concatStringsSep " " (lib.splitString "\n" s);
        boundsOf = name:
          let
            rule = ruleNamed name;
            e = flat rule.expr;
            lower = builtins.match ".*> ([0-9.]+).*" e;
            upper = builtins.match ".*<= ([0-9.]+).*" e;
          in
            assert lib.assertMsg (rule != null)
              "alert-tier-exclusivity: no rule named ${name} — a rename silently empties this check";
            assert lib.assertMsg (lower != null)
              "alert-tier-exclusivity: ${name} has no `> N` lower bound to parse";
            {
              inherit name;
              lower = lib.toInt (builtins.head lower);
              upper = if upper == null then null else lib.toInt (builtins.head upper);
            };
        # Ordered high tier first. Only the top tier may be unbounded above.
        families = {
          cpu    = [ "HighCPUUsage" "ElevatedCPUUsage" ];
          memory = [ "HighMemoryUsage" "ElevatedMemoryUsage" ];
          disk   = [ "HighDiskUsage" "ElevatedDiskUsage" "ModerateDiskUsage" ];
        };
        # Every threshold in use, each ±1, plus the ends of the scale. Bounds are
        # whole numbers, so integer samples cross every boundary exactly.
        samples = [ 0 50 69 70 71 81 82 83 84 85 86 89 90 91 94 95 96 99 100 ];
        matches = b: v: v > b.lower && (b.upper == null || v <= b.upper);
        overlaps = lib.concatLists (lib.mapAttrsToList (family: names:
          let bounds = map boundsOf names;
          in lib.concatMap (v:
            let hit = lib.filter (b: matches b v) bounds;
            in lib.optional (lib.length hit > 1)
              "${family}: sample ${toString v} matches ${
                lib.concatStringsSep " + " (map (b: b.name) hit)}"
          ) samples
        ) families);
        unboundedLowTiers = lib.concatLists (lib.mapAttrsToList (family: names:
          map (b: "${family}: ${b.name} has no upper bound but is not the top tier")
            (lib.filter (b: b.upper == null) (map boundsOf (builtins.tail names)))
        ) families);
        problems = overlaps ++ unboundedLowTiers;
      in
      assert lib.assertMsg (problems == [])
        "alert tier ladders overlap:\n  ${lib.concatStringsSep "\n  " problems}";
      pkgs.runCommand "alert-tier-exclusivity" {} ''touch "$out"'';

      # ── The alert rules are valid PromQL, per Prometheus' own parser ────
      # alert-tier-exclusivity proves the tier NUMBERS cannot overlap. It cannot
      # prove the expressions PARSE — it reads them as strings with
      # builtins.match, so a rule file Prometheus rejects passes it clean. The
      # 2026-09-07 tier work introduced chained comparisons (`> 82 <= 85`), a
      # form this repo had never shipped, and an unparseable rule file does not
      # degrade gracefully: prometheus.service refuses to start, which takes
      # every alert — and therefore the whole notification path — with it.
      # Checked against the FILES THE SERVER WILL LOAD (read off the evaluated
      # config) rather than a second rendering of parts/alerts.nix, so this
      # cannot pass on a copy while the deployed file is broken.
      # Parses the rules of whichever registered server runs the central
      # Prometheus (hwc-work since service split wave 3).
      alert-rules-parse = let
        servers = lib.attrValues self.nixosConfigurations."hwc-home".config.hwc.networking.hosts.servers;
        central = lib.findFirst
          (h: self.nixosConfigurations ? ${h} && self.nixosConfigurations.${h}.config.hwc.monitoring.prometheus.enable)
          null servers;
        prom = self.nixosConfigurations.${central}.config.services.prometheus;
        ruleFiles = prom.ruleFiles ++ map (r: pkgs.writeText "exported-rules.yml" r) prom.rules;
      in
      assert lib.assertMsg (central != null && ruleFiles != [])
        "alert-rules-parse: no registered server runs the central Prometheus — this check has no subject and would pass empty";
      pkgs.runCommand "alert-rules-parse" {
        nativeBuildInputs = [ pkgs.prometheus.cli ];
      } ''
        promtool check rules ${lib.concatMapStringsSep " " toString ruleFiles}
        touch $out
      '';

      # ── Every OnFailure= notifier points at a unit that exists ──────────
      # Derived from the EVALUATED hwc-home config, so it needs no second
      # copy of the monitored list. A name that resolves to no ExecStart is a
      # stub unit: it reads as coverage and delivers nothing (seven such dead
      # entries were found by hand on 2026-08-26).
      # Every serving host alerts on its own units (service split): check each.
      alert-onfailure-units = let
        onFailureOf = svc:
          let v = (svc.unitConfig or {}).OnFailure or null;
          in if v == null then ""
             else if builtins.isList v then lib.concatStringsSep " " v
             else toString v;
        deadOn = host: let
          c = self.nixosConfigurations.${host}.config;
          monitored = lib.filter
            (n: lib.hasInfix "hwc-service-failure-notifier@" (onFailureOf c.systemd.services.${n}))
            (builtins.attrNames c.systemd.services);
          unitText = n:
            let t = (c.systemd.units."${n}.service" or {}).text or null;
            in if t == null then "" else t;
        in map (n: "${host}:${n}") (lib.filter (n: !(lib.hasInfix "ExecStart=" (unitText n))) monitored);
        dead = lib.concatMap deadOn [ "hwc-home" "hwc-work" ];
        preservesUnit = host: let
          c = self.nixosConfigurations.${host}.config;
          system = c.systemd.services."hwc-service-failure-notifier@".serviceConfig.ExecStart;
          user = c.systemd.user.services."hwc-service-failure-notifier@".serviceConfig.ExecStart;
        in lib.hasSuffix " %i" system && lib.hasSuffix " --user %i" user
          && lib.hasInfix (builtins.unsafeDiscardStringContext "ExecStart=${system}")
            c.systemd.units."hwc-service-failure-notifier@.service".text;
      in
      assert lib.assertMsg (dead == [])
        ("monitored units with no ExecStart (OnFailure= on these is a silent no-op): "
         + lib.concatStringsSep ", " dead);
      assert lib.assertMsg (lib.all preservesUnit [ "hwc-home" "hwc-work" ])
        "failure notifier must preserve literal unit names with %i, not unescape hyphens with %I";
      pkgs.runCommand "alert-onfailure-units" {} ''touch "$out"'';

      # ── The SR gauntlet units can actually run `flock` ──────────────────
      # run.sh serializes the poll timer against the run-now drain with flock,
      # which NixOS' default service PATH does not provide: without
      # pkgs.util-linux on srgPath both units exit 1 at the lock line, before
      # any investigation. Resolved against the PATH systemd will really set
      # (read off the rendered unit files of the evaluated hwc-home config),
      # not against the srgPath list, so this cannot pass on a package that is
      # named but never reaches the unit.
      # The gauntlet runs on hwc-work since service split wave 1; the check
      # follows it (it failed "no subject" while still pointed at hwc-home).
      # Rebuilding a runtime must not launch or interrupt investigations.
      gauntlet-switch-policy = let
        services = self.nixosConfigurations.hwc-work.config.systemd.services;
        names = [ "sr-gauntlet" "sr-gauntlet-runnow" "dx1-gauntlet" "dx1-gauntlet-runnow" ];
      in
      assert lib.all (name:
        builtins.hasAttr name services && !services.${name}.restartIfChanged
        && lib.hasInfix "X-RestartIfChanged=false"
          self.nixosConfigurations.hwc-work.config.systemd.units."${name}.service".text
      ) names;
      pkgs.runCommand "gauntlet-switch-policy" {} ''touch "$out"'';

      sr-gauntlet-flock = let
        server = self.nixosConfigurations."hwc-work".config;
        units = [ "sr-gauntlet.service" "sr-gauntlet-runnow.service" ];
        unitFile = n: pkgs.writeText "check-${n}" server.systemd.units.${n}.text;
      in
      assert lib.assertMsg server.hwc.automation.srGauntlet.enable
        "sr-gauntlet-flock: srGauntlet is disabled on hwc-work — this check has no subject and would pass empty";
      pkgs.runCommand "sr-gauntlet-flock" {} ''
        fail=0
        ${lib.concatMapStringsSep "\n" (n: ''
          unitPath=""
          while IFS= read -r line; do
            case "$line" in
              Environment=*PATH=*) unitPath="''${line#*PATH=}"; unitPath="''${unitPath%\"}" ;;
            esac
          done < ${unitFile n}
          if [ -z "$unitPath" ]; then
            echo "FAIL: ${n} sets no PATH — srgPath is not reaching the unit." >&2
            fail=1
          elif ! ( PATH="$unitPath"; command -v flock >/dev/null ); then
            echo "FAIL: ${n} has no flock on its PATH. run.sh takes its lock with" >&2
            echo "      flock; the unit exits 1 before any work. Add pkgs.util-linux" >&2
            echo "      to srgPath in domains/automation/sr-gauntlet/index.nix." >&2
            fail=1
          fi
        '') units}
        [ "$fail" = 0 ] || exit 1
        touch $out
      '';

      # ── A quiet nightly-builds morning stays quiet ──────────────────────
      # The no-action branch of the morning review must record and send
      # nothing. Two directions: the P5 "nothing needs you" card must not come
      # back, and the POST must stay behind the nb_notify gate.
      nightly-review-silent = pkgs.runCommand "nightly-review-silent" {
        nativeBuildInputs = [ pkgs.ripgrep ];
      } ''
        cd ${self}
        src=domains/automation/nightly-builds/index.nix
        fail=0
        if rg -q 'prio=5' "$src"; then
          echo "FAIL: the morning review has a P5 branch again — a morning with no" >&2
          echo "      decision must send nothing, not a card saying so." >&2
          fail=1
        fi
        rg -q 'nb_notify=0' "$src" || {
          echo "FAIL: no nb_notify=0 branch — the no-action path is not silent." >&2; fail=1; }
        rg -q 'if \[ "\$nb_notify" = 1 \]' "$src" || {
          echo "FAIL: the notify POST is no longer gated on nb_notify." >&2; fail=1; }
        [ "$fail" = 0 ] || exit 1
        touch $out
      '';

      bitwarden-portal = let
        client = lib.findFirst (p: (p.meta.mainProgram or "") == "bitwarden")
          (throw "bitwarden-portal: laptop no longer installs Bitwarden")
          self.homeConfigurations."eric@hwc-laptop".config.home.packages;
      in pkgs.runCommand "bitwarden-portal" {
        nativeBuildInputs = [ pkgs.python3 pkgs.ripgrep ];
      } ''
        # The actual HM package must invoke the tested relay launcher.
        rg --text --fixed-strings '${client.portalLauncher}' '${client}/bin/bitwarden'
        BITWARDEN_PORTAL_TEST_LAUNCHER='${client.portalLauncher}' \
          python3 ${./domains/home/apps/bitwarden/test_portal_launcher.py}
        touch "$out"
      '';

      t3-update-gate = let
        root = "/tmp/t3-update-gate";
        fixture = (self.nixosConfigurations.hwc-work.extendModules {
          modules = [ ({ lib, ... }: {
            home-manager.users.eric = {
              home.homeDirectory = lib.mkForce "${root}/home";
              hwc.home.apps.t3code.repo = lib.mkForce "${root}/primary";
              hwc.home.apps.agent-harness = {
                nixosRepo = lib.mkForce "${root}/nixos";
                workspaceRoot = lib.mkForce "${root}/workspace";
              };
            };
          }) ];
        }).config.home-manager.users.eric;
        updater = builtins.head (builtins.filter (p: (p.name or "") == "t3-update") fixture.home.packages);
        python = pkgs.python3.withPackages (p: [ p.jsonschema ]);
      in pkgs.runCommand "t3-update-gate" { nativeBuildInputs = [ python pkgs.git ]; } ''
        python3 -B ${./domains/home/apps/t3code/test_update_gate.py} \
          --updater ${updater}/bin/t3-update --root ${root}
        python3 -B ${inputs.agent-harness}/tracker/t3_release.test.py
        touch "$out"
      '';

      t3-switch-policy = let
        targets = [
          { host = "hwc-home"; unit = "t3-serve"; }
          { host = "hwc-work"; unit = "t3-serve"; }
          { host = "hwc-laptop"; unit = "t3code"; }
        ];
        units = map (target: let
          home = self.nixosConfigurations.${target.host}.config.home-manager.users.eric;
          updater = builtins.head (builtins.filter (p: (p.name or "") == "t3-update") home.home.packages);
        in {
          inherit (target) host unit;
          policy = home.systemd.user.services.${target.unit}.Unit.X-SwitchMethod or null;
          file = home.home.file."${home.xdg.configHome}/systemd/user/${target.unit}.service".source;
          # Schema inspection only; these paths are never executed by this fixture.
          runtime = builtins.unsafeDiscardStringContext updater.releaseRuntime.drvAttrs.text;
        }) targets;
        fixtures = pkgs.writeText "t3-switch-policy.json" (builtins.toJSON units);
      in
      assert lib.assertMsg (lib.all (unit: unit.policy == "keep-old") units)
        "t3-switch-policy: an implicit home switch must preserve each running T3 shape";
      pkgs.runCommand "t3-switch-policy" {
        nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.jsonschema ])) ];
      } ''
        python3 -B - ${fixtures} ${inputs.agent-harness}/tracker/t3_release.py <<'PY'
        import configparser, importlib.util, json, pathlib, sys, tempfile
        spec = importlib.util.spec_from_file_location('t3_release', sys.argv[2])
        release = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(release)
        def keeps_active(text):
            unit = configparser.RawConfigParser(strict=False)
            unit.optionxform = str
            unit.read_string(text)
            return unit.get('Unit', 'X-SwitchMethod', fallback=None) == 'keep-old'
        for item in json.loads(pathlib.Path(sys.argv[1]).read_text()):
            with tempfile.NamedTemporaryFile(mode='w+', suffix='.json') as runtime_file:
                runtime_file.write(item['runtime']); runtime_file.flush()
                runtime = release.load_runtime(pathlib.Path(runtime_file.name))
            assert runtime['serviceUnit'] == item['unit'] + '.service', item['host']
            assert runtime['headless'] == (item['unit'] == 't3-serve'), item['host']
            text = pathlib.Path(item['file']).read_text()
            assert keeps_active(text), item
            missing = '\n'.join(line for line in text.splitlines() if not line.startswith('X-SwitchMethod='))
            assert missing != text and not keeps_active(missing), 'missing-policy control escaped'
            print(item['host'] + '/' + item['unit'] + ': runtime schema, rendered keep-old and removal control pass')
        PY
        touch "$out"
      '';

      user-runtime-paths = let
        laptopSystem = self.nixosConfigurations.hwc-laptop;
        laptop = laptopSystem.config.home-manager.users.eric;
        paths = laptopSystem.config.hwc.paths;
        standalone = self.homeConfigurations."eric@hwc-laptop".config;
        stable = self.nixosConfigurations.hwc-home.config.home-manager.users.eric;
        stableStandalone = self.homeConfigurations."eric@hwc-home".config;
        overridden = (laptopSystem.extendModules {
          modules = [{
            hwc.paths.user.apps = "/tmp/hwc-test-apps";
            hwc.paths.user.go.workspace = "/tmp/hwc-test-go";
            hwc.paths.user.go.moduleCache = "/tmp/hwc-test-modules";
          }];
        }).config.home-manager.users.eric;
        homes = [ laptop standalone stable stableStandalone ];
        modelPaths = laptop.hwc.home.apps.whisper-cpp.modelPaths;
        cleanup = laptop.systemd.user.services.go-cache-clean.Service;
        noHomeModels = home: !(lib.any (lib.hasPrefix "models/") (lib.attrNames home.home.file));
        projectMapping = home:
          home.xdg.userDirs.extraConfig.PROJECTS == home.home.sessionVariables.PROJECTS
          && !(lib.hasInfix "${home.home.homeDirectory}/Projects"
            home.home.activation.createXdgUserDirectories.data);
      in
      assert lib.assertMsg (lib.all projectMapping homes)
        "user-runtime-paths: XDG Projects must use the app root in both HM API lanes";
      assert lib.assertMsg (laptop.home.sessionVariables.PROJECTS == toString paths.user.apps
        && laptop.home.sessionVariables.GOPATH == toString paths.user.go.workspace
        && laptop.home.sessionVariables.GOMODCACHE == toString paths.user.go.moduleCache
        && laptop.home.sessionVariables.GOCACHE == toString paths.user.go.buildCache
        && laptop.home.sessionVariables.GOBIN == toString paths.user.go.bin)
        "user-runtime-paths: integrated environment must consume hwc.paths";
      assert lib.assertMsg (overridden.home.sessionVariables.PROJECTS == "/tmp/hwc-test-apps"
        && overridden.home.sessionVariables.GOPATH == "/tmp/hwc-test-go"
        && overridden.home.sessionVariables.GOMODCACHE == "/tmp/hwc-test-modules")
        "user-runtime-paths: changing the central paths must change their consumers";
      assert lib.assertMsg (lib.all (home:
        home.home.sessionVariables.GOPATH != "${home.home.homeDirectory}/go"
        && home.home.sessionVariables.GOMODCACHE != "${home.home.homeDirectory}/go/pkg/mod") homes)
        "user-runtime-paths: Go must not recreate ~/go";
      assert lib.assertMsg (noHomeModels laptop && noHomeModels standalone
        && laptop.hwc.home.apps.hwc-dictation.model == toString modelPaths."base.en"
        && standalone.hwc.home.apps.hwc-dictation.model == toString standalone.hwc.home.apps.whisper-cpp.modelPaths."base.en"
        && lib.all (model: lib.elem (toString model) (map toString laptop.home.extraDependencies))
          (lib.attrValues modelPaths))
        "user-runtime-paths: dictation must use store files and every model must retain a GC root";
      assert lib.assertMsg (laptop.systemd.user.timers.go-cache-clean.Timer.OnCalendar == "monthly"
        && lib.elem "GOMODCACHE=${paths.user.go.moduleCache}" cleanup.Environment)
        "user-runtime-paths: cache retention must use the declared cache";
      pkgs.runCommand "user-runtime-paths" { } ''
        # The actual Go defaults file reaches callers without a fresh shell.
        export GOENV=${pkgs.writeText "go-env-test" laptop.xdg.configFile."go/env".text}
        test "$(${pkgs.go}/bin/go env GOPATH)" = '${paths.user.go.workspace}'
        test "$(${pkgs.go}/bin/go env GOMODCACHE)" = '${paths.user.go.moduleCache}'

        # Exercise the actual cleaner against isolated derived data. Source
        # and installed binaries must survive; the build cache must regenerate.
        runtime_test="$TMPDIR/go-runtime"
        mkdir -p "$runtime_test/workspace/src" "$runtime_test/bin" "$runtime_test/modules/example"
        echo keep > "$runtime_test/workspace/src/keep"
        echo keep > "$runtime_test/bin/keep"
        echo replaceable > "$runtime_test/modules/example/data"
        export GOPATH="$runtime_test/workspace" GOMODCACHE="$runtime_test/modules"
        export GOCACHE="$runtime_test/build" GOBIN="$runtime_test/bin" GOTOOLCHAIN=local
        echo 'package main; func main() {}' > "$runtime_test/main.go"
        ${pkgs.go}/bin/go build -o "$runtime_test/app" "$runtime_test/main.go"
        ${lib.head cleanup.ExecStart}
        test ! -e "$GOMODCACHE/example/data"
        test -f "$GOPATH/src/keep"
        test -f "$GOBIN/keep"
        ${pkgs.go}/bin/go build -o "$runtime_test/app" "$runtime_test/main.go"
        "$runtime_test/app"
        touch "$out"
      '';

      meals-integration = let
        work = self.nixosConfigurations.hwc-work.config;
        cfg = work.hwc.server.services.meals;
        unit = work.systemd.services.meals;
        settings = builtins.fromJSON (builtins.readFile (lib.last (lib.splitString " " unit.serviceConfig.ExecStart)));
      in
      assert lib.assertMsg (cfg.enable
        && settings.database == "${work.hwc.paths.state}/meals/meals.db"
        && settings.writesEnabled == cfg.writesEnabled
        && settings.baseUrl == cfg.url
        && settings.timeZone == work.time.timeZone
        && (builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile work.systemd.services.wall-display.environment.WALL_CONFIG))).meals.readUrl == "http://127.0.0.1:${toString cfg.port}"
        && settings.converter == { inherit (work.hwc.server.ai.dx2) baseUrl model apiKeyFile; modelIdentity = cfg.cookingModelIdentity; }
        && settings.cookingPromotion == cfg.cookingPromotion
        && work.hwc.system.mcp.mealCollections == cfg.collections
        && work.hwc.networking.shared.routeOwners.meals.owner == "work"
        && (lib.findFirst (r: r.name == "meals") {} work.hwc.networking.shared.routes).headers."X-Forwarded-For" == "{remote_host}"
        && lib.hasInfix "--check" unit.preStart
        && lib.hasInfix "--backup" work.services.borgbackup.jobs.hwc-backup.preHook
        && work.systemd.timers.meals-cleanup.timerConfig.Persistent)
        "Meals must bind exact effect targets, boot checks, backed-up state and cleanup";
      pkgs.runCommand "meals-integration" {} ''touch "$out"'';

      charter-law1 = mkCharterLint "law1-osconfig-safety" [
        "rg 'osConfig\\.' domains/home --type nix | rg -v 'osConfig\\.[a-zA-Z0-9_.]+ or |attrByPath|osConfig \\?|lib\\.mkIf isNixOS|#'"
      ];
      charter-law2 = mkCharterLint "law2-phantom-namespaces" [
        "rg 'hwc\\.(services|features|alerts|infrastructure)\\.' domains --type nix"
      ];
      charter-law4 = mkCharterLint "law4-permission-model" [
        "rg 'PGID\\s*=\\s*\"?1000\"?\\s*;' domains --type nix"
      ];
      charter-law5 = mkCharterLint "law5-container-standard" [
        "rg 'oci-containers\\.containers\\.' domains --glob '!**/mkContainer.nix' -l | xargs -r rg --files-without-match 'HWC-EXCEPTION\\(Law 5\\)'"
      ];
      charter-law7 = mkCharterLint "law7-lane-purity" [
        "rg 'import.*sys\\.nix' domains/home/*/index.nix"
      ];
      charter-law10 = mkCharterLint "law10-unit-anatomy" [
        # (a) the filename form the v11.0 migration eliminated.
        "fd options.nix domains"
        # (b) the CONTENT check Law 10 actually specifies. Until v12.6 only (a)
        # was wired, so a file could declare options freely as long as it wasn't
        # named options.nix — the gate was green while §3.1's own documented
        # lint returned four files. That lint was itself wrong three ways, all
        # fixed here: it matched the word in COMMENTS (jt.nix's "parts/ must
        # stay pure of mkOption" note), it MISSED mkEnableOption entirely
        # ('mkEnableOption' does not contain the substring 'mkOption'), and it
        # ignored the §4 exception protocol. Anchoring to `= mk...` after a
        # comment-free prefix fixes 1, the alternation fixes 2, and the
        # --files-without-match filter (same shape as law5) fixes 3.
        "rg -l '^[^#]*=[[:space:]]*(lib\\.)?mk(Option|EnableOption)\\b' domains --type nix -g '!**/index.nix' -g '!**/sys.nix' -g '!domains/paths/paths.nix' | xargs -r rg --files-without-match 'HWC-EXCEPTION\\(Law 10\\)'"
      ];
      charter-law12 = mkCharterLint "law12-readme-contract" [
        # v12.4 hybrid scope: top-level domains + high-churn module trees
        "for d in domains/*/ domains/server/containers/*/ domains/home/apps/*/; do [ -d \"$d\" ] || continue; case \"$d\" in */_shared/) continue;; esac; [ -f \"$d/README.md\" ] || echo \"Missing: $d/README.md\"; done"
        "for s in Purpose Boundaries Structure Changelog; do rg --files-without-match \"^## $s\" domains/*/README.md; done"
      ];
      charter-law14 = mkCharterLint "law14-flake-self-ref" [
        # [-] character class keeps this lint from matching its own definition
        "rg 'github:eriqueo/nixos[-]hwc' flake.nix"
      ];
      # Exercise rendered Borg hooks and helpers, including their failure paths.
      borg-recovery = let
        hosts = map (name: self.nixosConfigurations.${name}.config) [ "hwc-home" "hwc-work" ];
        fixtures = map (c: pkgs.writeText "borg-recovery.json" (builtins.toJSON {
          host = c.networking.hostName;
          hook = c.services.borgbackup.jobs.hwc-backup.preHook;
          customHook = c.hwc.data.borg.preBackupScript;
          snapshots = c.hwc.data.borg.sqliteSnapshots;
          stateRoot = "${c.hwc.paths.state}/borg-sqlite";
          paths = c.services.borgbackup.jobs.hwc-backup.paths;
          exclude = c.services.borgbackup.jobs.hwc-backup.exclude;
          cli = "${lib.findFirst (p: (p.name or "") == "borg-sqlite-snapshot") null c.environment.systemPackages}/bin/borg-sqlite-snapshot";
        })) hosts;
        restore = lib.findFirst (p: (p.name or "") == "borg-restore") null
          self.nixosConfigurations.hwc-work.config.environment.systemPackages;
      in
      assert lib.all (c: !(lib.hasInfix "break-lock"
        (c.systemd.services.borgbackup-job-hwc-backup.preStart or ""))) hosts;
      assert lib.all (c: lib.hasInfix (builtins.unsafeDiscardStringContext "${c.services.postgresql.package}/bin/pg_dumpall")
        c.services.borgbackup.jobs.hwc-backup.preHook) hosts;
      pkgs.runCommand "borg-recovery" { nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils pkgs.borgbackup pkgs.util-linux ]; } ''
        python3 - ${lib.concatStringsSep " " (map toString fixtures)} ${restore}/bin/borg-restore <<'PY'
        import gzip, hashlib, json, os, pathlib, pwd, re, shlex, shutil, sqlite3, subprocess, sys, tempfile, threading, time

        def run(argv, *, cwd=None, env=None, check=True):
            return subprocess.run(argv, cwd=cwd, env=env, check=check, capture_output=True, text=True, timeout=30)

        def coherent(path, marker=None, *, wal=False):
            uri = path.as_uri() + ('?mode=ro' if wal else '?mode=ro&immutable=1')
            with sqlite3.connect(uri, uri=True, timeout=2) as db:
                assert db.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
                row = db.execute('SELECT a.value,b.value,c.epoch,c.marker FROM alpha a,beta b,control c').fetchone()
            assert row[0] == row[1] == row[2], ('mixed transaction', row)
            if marker is not None:
                assert row[3] == marker, ('stale snapshot', row)
            return row

        def initialize(path):
            db = sqlite3.connect(path, timeout=2)
            db.execute('PRAGMA journal_mode=WAL')
            db.execute('PRAGMA wal_autocheckpoint=0')
            db.executescript('CREATE TABLE alpha(value INTEGER); CREATE TABLE beta(value INTEGER); '
                'CREATE TABLE control(epoch INTEGER,marker TEXT); CREATE TABLE payload(data BLOB); '
                "INSERT INTO alpha VALUES(0); INSERT INTO beta VALUES(0); INSERT INTO control VALUES(0,'initial');")
            db.executemany('INSERT INTO payload VALUES(?)', [(b'x' * 4096,) for _ in range(200)])
            db.commit()
            db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
            return db

        def transaction(db, epoch, marker):
            with db:
                db.execute('UPDATE alpha SET value=?', (epoch,))
                db.execute('UPDATE beta SET value=?', (epoch,))
                db.execute('UPDATE control SET epoch=?,marker=?', (epoch, marker))

        def require_failure(script, marker):
            marker.unlink(missing_ok=True)
            result = run(['bash', '-c', script + '\nprintf downstream > ' + shlex.quote(str(marker))], check=False)
            assert result.returncode != 0, ('snapshot failure swallowed', result.stdout, result.stderr)
            assert not marker.exists(), 'Borg create boundary reached after failed snapshot'

        def must_detect(check, label):
            try:
                check()
            except AssertionError:
                return
            raise AssertionError('seeded wiring violation escaped: ' + label)

        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            producer = root / "su"
            producer.write_text("#!${pkgs.bash}/bin/bash\nif [ -e " + str(root / "fail") + " ]; then exit 23; fi\nprintf 'valid SQL snapshot\\n'\n")
            producer.chmod(0o700)
            for i, fixture in enumerate(sys.argv[1:-1]):
                spec = json.loads(pathlib.Path(fixture).read_text())
                dest = root / str(i)
                dest.mkdir()
                nested = dest / "service-split" / "recovery.json"
                nested.parent.mkdir()
                nested.write_text("keep")
                os.utime(nested, (1, 1))
                old = dest / "postgresql-old.sql.gz"
                old.write_text("expired")
                os.utime(old, (1, 1))
                script = spec['hook']
                # Remove ONLY the exact declared custom suffix: Meals, CouchDB
                # and arr belong to their own owners, not this shared-hook test.
                custom = spec['customHook']
                if custom:
                    assert script.endswith(custom), 'custom-hook composition changed'
                    script = script[:-len(custom)]
                assert 'borg-sqlite-snapshot' in script, 'shared snapshot caller absent'
                assert set(spec['snapshots']) == {'t3'}
                config = spec['snapshots']['t3']
                state = dest / 'borg-sqlite'
                userdata = dest / 'userdata'
                userdata.mkdir()
                source = userdata / 'state.sqlite'
                # Substitute composition ports only; production helper and its
                # namespace/identity/permission/failure behavior remain intact.
                script = script.replace(spec['stateRoot'], str(state)).replace(config['source'], str(source))
                script = script.replace(shlex.quote(config['user']), shlex.quote(pwd.getpwuid(os.getuid()).pw_name))
                script = script.replace('/var/lib/backups', str(dest))
                script = script.replace("/run/wrappers/bin/su", str(producer))
                db = initialize(source)
                run(["bash", "-c", script])
                output = next(dest.glob("postgresql-2*.sql.gz"))
                before = output.read_bytes()
                assert gzip.decompress(before) == b"valid SQL snapshot\n"
                assert not old.exists() and nested.read_text() == "keep"
                (root / "fail").touch()
                assert run(["bash", "-c", script], check=False).returncode != 0
                assert output.read_bytes() == before
                assert not list(dest.glob(".postgresql-*"))
                (root / "fail").unlink()
                ready = state / 'ready' / 't3.sqlite'
                coherent(ready, 'initial')
                assert ready.stat().st_uid == os.getuid()
                assert ready.stat().st_mode & 0o777 == 0o600

                # A main(epoch0)/WAL(epoch1) tuple can pass integrity_check yet
                # violate transaction invariants. This is a known-bad control,
                # not attribution of any particular production archive failure.
                raw = dest / 'raw.sqlite'
                shutil.copyfile(source, raw)
                transaction(db, 1, 'checkpointed')
                db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
                db.execute("UPDATE control SET marker='later-committed'")
                db.commit()
                shutil.copyfile(pathlib.Path(str(source) + '-wal'), pathlib.Path(str(raw) + '-wal'))
                with sqlite3.connect(raw.as_uri() + '?mode=ro', uri=True) as mixed:
                    assert mixed.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
                    assert mixed.execute('SELECT a.value,b.value,c.epoch FROM alpha a,beta b,control c').fetchone() == (0, 0, 1)
                must_detect(lambda: coherent(raw, wal=True), 'raw file-copy consistency')

                # Remove the actual caller. A still-valid old snapshot must not
                # satisfy the fresh committed marker required by this consumer.
                cli = spec['cli']
                omitted = script.replace(cli, 'true')
                assert omitted != script
                run(['bash', '-c', omitted])
                must_detect(lambda: coherent(ready, 'later-committed'), 'snapshot invocation removed')
                run(['bash', '-c', script])
                coherent(ready, 'later-committed')

                # Separate real writer runs while the actual rendered hook/CLI
                # execute. The fixture's atomic invariant must survive churn.
                stop, started = threading.Event(), threading.Event()
                commits, errors = [], []
                def writing():
                    writer = None
                    try:
                        writer = sqlite3.connect(source, timeout=2)
                        writer.execute('PRAGMA wal_autocheckpoint=0')
                        epoch = 2
                        deadline = time.monotonic() + 20
                        while not stop.is_set():
                            assert epoch < 10002 and time.monotonic() < deadline, 'owned writer exceeded budget'
                            transaction(writer, epoch, 'active-writer')
                            commits.append(time.monotonic())
                            started.set()
                            epoch += 1
                            # Remain active until the caller finishes, with a
                            # strict budget and low WAL churn on slow builders.
                            stop.wait(.005)
                    except BaseException as error:
                        errors.append(repr(error))
                        started.set()
                    finally:
                        if writer is not None:
                            writer.close()
                thread = threading.Thread(target=writing)
                thread.start()
                try:
                    assert started.wait(5) and not errors
                    begin = time.monotonic()
                    run(['bash', '-c', script])
                    end = time.monotonic()
                    coherent(ready)
                    assert any(begin < tick < end for tick in commits), 'writer did not overlap snapshot caller'
                finally:
                    stop.set()
                    thread.join(5)
                assert not thread.is_alive() and not errors, errors

                # Exercise standalone CLI, including required source and size
                # failures; each preserves the old published bytes and staging.
                argv = [cli, 'create', '--state-root', str(state), '--name', 't3', '--source', str(source),
                    '--user', pwd.getpwuid(os.getuid()).pw_name, '--max-bytes', str(config['maxBytes']),
                    '--timeout-seconds', str(config['timeoutSeconds'])]
                run(argv)
                coherent(ready)
                lastgood = ready.read_bytes()
                slot = state / 'staging' / 't3'
                slot.mkdir(mode=0o700)
                held_file = slot / 'keep-existing-slot'
                held_file.write_text('another attempt owns this slot')
                assert run(argv, check=False).returncode != 0
                assert held_file.read_text() == 'another attempt owns this slot'
                assert ready.read_bytes() == lastgood
                held_file.unlink()
                slot.rmdir()
                alias = userdata / 'source-alias.sqlite'
                alias.symlink_to(source)
                invalid = userdata / 'invalid.sqlite'
                invalid.write_bytes(b'not a SQLite database' * 100)
                for broken in [argv[:argv.index('--source') + 1] + [str(userdata / 'missing.sqlite')] + argv[argv.index('--source') + 2:],
                               argv[:argv.index('--source') + 1] + [str(alias)] + argv[argv.index('--source') + 2:],
                               argv[:argv.index('--source') + 1] + [str(invalid)] + argv[argv.index('--source') + 2:],
                               argv[:argv.index('--max-bytes') + 1] + ['1'] + argv[argv.index('--max-bytes') + 2:]]:
                    assert run(broken, check=False).returncode != 0
                    assert ready.read_bytes() == lastgood
                    assert not list((state / 'staging').glob('**/*.sqlite'))
                alias.unlink()
                invalid.unlink()
                # A last-good symlink cannot redirect publication or modify its
                # target. Restore only this fixture's exact saved regular file.
                saved = ready.with_name('saved-lastgood')
                ready.rename(saved)
                target = dest / 'symlink-target'
                target.write_text('keep target intact')
                ready.symlink_to(target)
                try:
                    assert run(argv, check=False).returncode != 0
                    assert ready.is_symlink() and target.read_text() == 'keep target intact'
                    assert saved.read_bytes() == lastgood
                finally:
                    ready.unlink()
                    saved.rename(ready)
                # Rollback-journal EXCLUSIVE lock forces a genuine reader wait;
                # the real worker must fail within its configured small budget.
                locked = userdata / 'locked.sqlite'
                locker = initialize(locked)
                locker.execute('PRAGMA journal_mode=DELETE')
                locker.execute('BEGIN EXCLUSIVE')
                bounded = argv.copy()
                bounded[bounded.index('--source') + 1] = str(locked)
                bounded[bounded.index('--timeout-seconds') + 1] = '1'
                begin = time.monotonic()
                try:
                    assert run(bounded, check=False).returncode != 0
                    assert time.monotonic() - begin < 8, 'worker deadline did not bound lock wait'
                    assert ready.read_bytes() == lastgood
                    assert not list((state / 'staging').glob('**/*.sqlite'))
                finally:
                    locker.rollback()
                    locker.close()
                    locked.unlink()
                # Real failed producer through rendered call site must stop
                # before the next archive step. A wrapper swallowing its error
                # is an independent wiring mutation, required to be detected.
                failed = script.replace(str(source), str(userdata / 'missing.sqlite'))
                downstream = dest / 'borg-create-started'
                require_failure(failed, downstream)
                assert ready.read_bytes() == lastgood
                swallow = dest / 'swallow-snapshot-error'
                swallow.write_text('#!${pkgs.bash}/bin/bash\n' + shlex.quote(cli) + ' "$@" || true\n')
                swallow.chmod(0o700)
                must_detect(lambda: require_failure(failed.replace(cli, str(swallow)), downstream), 'producer failure swallowed')
                assert ready.read_bytes() == lastgood

                # Local disposable Borg repository: use actual evaluated exact
                # excludes and source coverage, preserving other userdata.
                (userdata / 'pairing-fixture').write_text('synthetic credential placeholder')
                staging = state / 'staging' / 'not-an-archive-input'
                staging.write_text('partial')
                assert any(pathlib.PurePosixPath(spec['stateRoot'] + '/ready').is_relative_to(p) for p in spec['paths'])
                assert str(pathlib.PurePosixPath(config['source']).parent) in spec['paths']
                def remap(value):
                    return value.replace(spec['stateRoot'], str(state)).replace(config['source'], str(source))
                excludes = [remap(value) for value in spec['exclude']]
                env = {k: v for k, v in os.environ.items() if not k.startswith('BORG_')}
                env.update(BORG_CACHE_DIR=str(dest / 'cache'), BORG_CONFIG_DIR=str(dest / 'config'),
                    BORG_SECURITY_DIR=str(dest / 'security'), BORG_CHECK_I_KNOW_WHAT_I_AM_DOING='YES')
                repo = dest / 'repo'
                run(['borg', 'init', '--encryption=none', str(repo)], env=env)
                def archive(name, patterns):
                    args = ['borg', 'create', '--compression', 'none']
                    for pattern in patterns:
                        args += ['--exclude', pattern]
                    run([*args, str(repo) + '::' + name, str(state), str(userdata)], env=env)
                    extracted = dest / ('extract-' + name)
                    extracted.mkdir()
                    run(['borg', 'extract', str(repo) + '::' + name], cwd=extracted, env=env)
                    return extracted
                def verify_archive(extracted):
                    copied = extracted / str(state).lstrip('/')
                    restored_user = extracted / str(userdata).lstrip('/')
                    coherent(copied / 'ready' / 't3.sqlite')
                    assert (restored_user / 'pairing-fixture').read_text() == 'synthetic credential placeholder'
                    assert not any((restored_user / ('state.sqlite' + suffix)).exists() for suffix in ("", '-wal', '-shm')), 'raw SQLite entered archive'
                    assert not (copied / 'staging' / 'not-an-archive-input').exists(), 'staging entered archive'
                verify_archive(archive('valid', excludes))
                raw_patterns = [value for value in excludes if str(source) in value]
                assert len(raw_patterns) == 3, raw_patterns
                must_detect(lambda: verify_archive(archive('raw-exclusion-removed', [value for value in excludes if value not in raw_patterns])), 'raw SQLite exclusions removed')
                db.close()
                print(json.dumps({'host': spec['host'], 'state': 'passed',
                    'snapshotSha256': hashlib.sha256(ready.read_bytes()).hexdigest(),
                    'checks': ['postgresql-publication-retention-failure', 'rendered-hook-sqlite-publication',
                        'raw-wal-mixed-transaction-red', 'concurrent-writer-snapshot', 'standalone-cli',
                        'existing-slot-held', 'source-symlink-missing-invalid-size-held',
                        'lastgood-symlink-held', 'real-lock-deadline', 'lastgood-preserved',
                        'failed-hook-stops-downstream', 'local-borg-archive-extract',
                        'non-database-userdata-preserved', 'raw-and-staging-excluded'],
                    'mutationsDetected': ['snapshot-caller-removed', 'producer-failure-swallowed',
                        'raw-sqlite-exclusions-removed']}), flush=True)
            fake = root / "borg"
            fake.write_text("#!${pkgs.bash}/bin/bash\nexit 42\n")
            fake.chmod(0o700)
            script, replacements = re.subn(r"/nix/store/[^\s]+/bin/borg\b", str(fake), pathlib.Path(sys.argv[-1]).read_text())
            assert replacements >= 1
            result = subprocess.run(["bash", "-c", script, "restore", "absent", str(root / "restore")])
            assert result.returncode == 42, result.returncode
        PY
        touch "$out"
      '';

      home-rename = let
        renamed = self.nixosConfigurations ? hwc-home;
        home = self.nixosConfigurations.${if renamed then "hwc-home" else "hwc-server"}.config;
        job = home.services.borgbackup.jobs.hwc-backup;
      in
      assert lib.assertMsg (renamed && !(self.nixosConfigurations ? hwc-server))
        "home rename: only hwc-home may name the home machine/output";
      assert home.networking.hostName == "hwc-home";
      assert home.hwc.networking.hosts.servers.main == home.networking.hostName;
      assert lib.elem "--hostname=${home.networking.hostName}" home.services.tailscale.extraSetFlags;
      assert job.repo == "/mnt/backup/borg-hwc-server";
      assert job.archiveBaseName == "hwc-server-hwc-backup";
      assert job.prune.prefix == job.archiveBaseName;
      assert builtins.hashFile "sha256" ./machines/home/AGE_PUBLIC_KEY.txt
        == "a98fc2db8fd8507418f110474d5a83f62e24fa4b1af10b7c92fc8066ea8a64d7";
      assert lib.all (name: let c = self.nixosConfigurations.${name}.config; in
        c.hwc.networking.hosts.fqdn.main == "hwc-home.${c.hwc.networking.hosts.tailnetSuffix}"
        && lib.elem "hwc-home" c.home-manager.users.eric.hwc.home.apps.agent-harness.fleetHosts
        && !(lib.elem "hwc-server" c.home-manager.users.eric.hwc.home.apps.agent-harness.fleetHosts)
      ) [ "hwc-home" "hwc-work" "hwc-laptop" ];
      pkgs.runCommand "home-rename" {} ''touch "$out"'';

      phone-ingest-ownership = let
        home = self.nixosConfigurations.hwc-home.config;
        work = self.nixosConfigurations.hwc-work.config;
        vhost = "whisper.${work.hwc.networking.shared.vhostDomain}";
        ingestUnits = [ "inbox-processor-audio" "inbox-processor-screenshots" ];
      in
      assert lib.assertMsg (home.hwc.server.ai.whisper.enable && home.hwc.server.ai.whisper.gpu
        && !(work.hwc.server.ai.whisper.enable or false)
        && !(work.systemd.services ? whisper-server)
        && home.hwc.server.services.bloxelsCv.enable
        && lib.all (name: !(builtins.hasAttr name home.systemd.paths)
          && !(builtins.hasAttr name home.systemd.services)
          && builtins.hasAttr name work.systemd.paths) ingestUnits)
        "phone ingestion: home owns GPU Whisper/Bloxels; work alone processes audio/screenshots";
      assert lib.elem "hwc-work" home.hwc.data.syncthing.folders.inbox-mobile.devices;
      assert work.hwc.data.syncthing.folders.inbox-mobile.path == work.hwc.paths.brain.inbox-mobile;
      assert work.hwc.server.services.inboxProcessor.audioInboxPath == "${work.hwc.paths.brain.inbox-mobile}/audio";
      assert work.hwc.server.services.inboxProcessor.whisperUrl == "https://${vhost}";
      assert !(lib.elem "whisper-server.service" work.systemd.services.inbox-processor-audio.wants);
      assert lib.hasInfix "WHISPER_URL=\"https://${vhost}/v1/audio/transcriptions\""
        (builtins.readFile work.systemd.services.inbox-processor-audio.serviceConfig.ExecStart);
      assert (work.hwc.networking.shared.routeOwners.whisper.owner or "main") == "main";
      assert lib.hasInfix vhost home.services.caddy.extraConfig;
      pkgs.runCommand "phone-ingest-ownership" {} ''touch "$out"'';

      # Exercise the XPS guard through the production preStart, before any
      # database setup. The fixture replaces OS probes and drops their string
      # contexts so this check does not build ZFS/FFmpeg merely to mock them.
      xps-media-readiness = let
        peer = self.nixosConfigurations.hwc-xps.config;
        service = peer.systemd.services.jellyfin;
        preflight = builtins.head (lib.splitString "DATA_DIR=" service.preStart);
        encoding = (builtins.head service.restartTriggers).text;
        homeEncoding = (builtins.head self.nixosConfigurations.hwc-home.config.systemd.services.jellyfin.restartTriggers).text;
        fixture = pkgs.writeText "xps-media-readiness.json" (builtins.toJSON {
          script = builtins.unsafeDiscardStringContext preflight;
          zpool = builtins.unsafeDiscardStringContext "${peer.boot.zfs.package}/bin/zpool";
          pool = builtins.head peer.boot.zfs.extraPools;
        });
      in
      assert lib.assertMsg (lib.hasInfix "pool_health=" preflight)
        "XPS Jellyfin must run its pool guard before database setup";
      assert service.unitConfig.AssertPathIsMountPoint == peer.hwc.paths.media.root;
      assert lib.elem "zfs-mount.service" service.requires;
      assert lib.hasInfix "<HardwareAccelerationType>none</HardwareAccelerationType>" encoding;
      assert lib.hasInfix "<EnableHardwareEncoding>false</EnableHardwareEncoding>" encoding;
      assert lib.hasInfix "<HardwareAccelerationType>nvenc</HardwareAccelerationType>" homeEncoding;
      pkgs.runCommand "xps-media-readiness" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        python3 - ${fixture} ${pkgs.bash}/bin/bash ${pkgs.coreutils}/bin/timeout <<'PY'
        import json, pathlib, re, subprocess, sys, tempfile, time
        fixture = json.loads(pathlib.Path(sys.argv[1]).read_text())
        bash, timeout = sys.argv[2:]
        original = fixture["script"]
        matches = re.findall(r"(/nix/store/[^\s]+/bin/timeout) 10s", original)
        assert len(matches) == 1, "production probe must have one 10-second deadline"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            fake = root / "zpool"
            script = root / "preflight"
            script.write_text(original.replace(matches[0], timeout).replace(fixture["zpool"], str(fake)))
            def run(state):
                fake.write_text("#!${pkgs.python3}/bin/python3\n"
                    "import sys,time\n"
                    + "assert sys.argv[1:] == " + repr(["list", "-H", "-o", "health", fixture["pool"]]) + "\n"
                    + ("time.sleep(30)\n" if state == "TIMEOUT" else
                       "sys.exit(3)\n" if state == "PROBE_FAILED" else "print(" + repr(state) + ")\n"))
                fake.chmod(0o700)
                start = time.monotonic()
                result = subprocess.run([bash, "-e", str(script)], capture_output=True, text=True, timeout=15)
                return result, time.monotonic() - start
            for state in ["ONLINE", "DEGRADED"]:
                result, _ = run(state)
                assert result.returncode == 0, (state, result.stderr)
                if state == "DEGRADED":
                    assert result.stderr, "degraded storage must emit a warning"
            for state in ["SUSPENDED", "UNAVAIL", "FAULTED", "UNKNOWN", "PROBE_FAILED", "TIMEOUT"]:
                result, elapsed = run(state)
                assert result.returncode != 0, (state, "startup unexpectedly passed")
                assert elapsed < 15, (state, "probe exceeded its ceiling")
            print("XPS production preflight: healthy/degraded accepted; unavailable, suspended, failed and timed-out probes rejected")
        PY
        touch "$out"
      '';

      # Service-split retirement contract, evaluated through production units.
      fleet-map-routing = let
        work = self.nixosConfigurations.hwc-work.config;
        home = self.nixosConfigurations.hwc-home.config;
        unit = work.systemd.services.fleet-map-publish;
      in
      assert lib.assertMsg (work.hwc.monitoring.fleet-map.enable
        && work.hwc.networking.shared.routeOwners.map.owner == "work"
        && lib.hasInfix "@map host map." work.services.caddy.extraConfig
        && !(lib.hasInfix "@map host map." home.services.caddy.extraConfig))
        "fleet-map must be published only by its work owner";
      assert lib.assertMsg (lib.hasInfix "--capture" unit.script
        && lib.hasInfix "/run/wrappers/bin" unit.environment.PATH
        && lib.hasInfix "/run/current-system/sw/bin" unit.environment.PATH
        && unit.serviceConfig.TimeoutStartSec == "10min")
        "fleet-map publisher needs the real host commands and a bounded lifetime";
      pkgs.runCommand "fleet-map-routing" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        cd ${inputs.fleet-map}
        PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v
        touch "$out"
      '';

      service-split-retirement = let
        server = self.nixosConfigurations.hwc-home.config;
        work = self.nixosConfigurations.hwc-work.config;
        laptopHome = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
        mailCommand = "ssh -t ${work.hwc.networking.hosts.fqdn.work} aerc";
        workHome = work.home-manager.users.eric;
        prune = workHome.systemd.user.services.podman-image-prune or {};
        peer = self.nixosConfigurations.hwc-xps.config;
        absent = units: names: lib.all (name: !(builtins.hasAttr name units)) names;
      in
      assert lib.assertMsg (
        lib.any (cmd: lib.hasSuffix "/bin/podman image prune --force --filter until=12h" cmd)
          (prune.Service.ExecStart or [])
        && (prune.Service.TimeoutStartSec or "") == "10min"
        && workHome.systemd.user.timers.podman-image-prune.Timer.Persistent
        && !(server.home-manager.users.eric.systemd.user.services ? podman-image-prune)
      ) "service split: rootless build-cache retention must be bounded and preserve referenced/named images";
      assert lib.assertMsg (laptopHome.hwc.home.core.shell.aliases.aerc == mailCommand
        && lib.elem "SUPER,E,exec,kitty -e ${mailCommand}"
          laptopHome.wayland.windowManager.hyprland.settings.bind)
        "service split: laptop shell and desktop mail must reach the work mail owner";
      assert lib.assertMsg (absent server.systemd.services [
        "podman-authentik-server" "podman-authentik-worker" "authentik-env"
        "llama-embed" "podman-n8n" "nightly-builds"
        "proton-bridge-relay-1025" "proton-bridge-relay-1143"
      ]) "service split: a retired server unit returned";
      assert lib.assertMsg (absent server.home-manager.users.eric.systemd.user.services
        [ "mbsync" "mbsync-trash" "mail-health" "vdirsyncer" "protonmail-bridge" ])
        "service split: retired server mail service returned";
      assert lib.assertMsg (server.services.postgresql.enable
        && server.hwc.media.immich.enable && server.hwc.data.couchdb.enable
        && server.hwc.business.paperless.receipts.enable
        && builtins.hasAttr "podman-immich-redis" server.systemd.services
        && builtins.hasAttr "paperless-receipts-mover" server.systemd.paths)
        "service split: media storage or receipt ingress lost";
      assert lib.assertMsg (work.hwc.automation.n8n.enable
        && work.hwc.automation.refinery.enable && work.hwc.automation.nightlyBuilds.enable
        && work.home-manager.users.eric.hwc.mail.bridge.enable
        && !work.hwc.mail.bridge.relay.enable
        && !peer.hwc.data.couchdb.enable && !peer.hwc.automation.refinery.enable
        && !peer.hwc.automation.nightlyBuilds.enable)
        "service split: application ownership regressed";
      assert lib.assertMsg (lib.all (name:
        work.systemd.services.${name}.serviceConfig.ReadOnlyPaths == [ "-/mnt" ])
        [ "nightly-builds" "nightly-builds-runnow" ])
        "service split: nightly sandbox must tolerate absent media mounts";
      pkgs.runCommand "service-split-retirement" {} ''touch "$out"'';

      # Wave 4 compatibility contract: the old entry point survives while
      # only work owns the application. Remove the legacy-port assertion only
      # with wave 5 evidence that old clients have moved.
      n8n-route-compatibility = let
        server = self.nixosConfigurations."hwc-home".config;
        work = self.nixosConfigurations."hwc-work".config;
        route = lib.findFirst (r: r.name == "n8n") null
          work.hwc.networking.shared.effectiveRoutes;
        port = toString route.port;
        ownerIp = work.hwc.networking.hosts.ips.work;
        ownerName = work.hwc.networking.hosts.fqdn.work;
        oldListener = "${server.hwc.networking.shared.rootHost}:${port}";
        serverCaddy = server.services.caddy.extraConfig;
        workVhosts = lib.attrNames (lib.filterAttrs (_: o: o.owner == "work" && o.mode == "vhost")
          work.hwc.networking.shared.routeOwners);
      in
      assert lib.assertMsg (lib.all (name:
        !(lib.hasInfix "@${name} host ${name}." serverCaddy)) workVhosts)
        "route cleanup: a work vhost fallback returned on home";
      assert lib.assertMsg (lib.hasInfix "handle @webhook" serverCaddy
        && lib.hasInfix "reverse_proxy ${ownerIp}:${toString work.hwc.system.mcp.port}" serverCaddy)
        "route cleanup: shared webhook or MCP entrypoint missing";
      assert lib.assertMsg (!server.hwc.automation.n8n.enable && work.hwc.automation.n8n.enable)
        "n8n compatibility: work must be the only declared writer";
      assert lib.assertMsg (lib.hasInfix oldListener serverCaddy
        && lib.hasInfix "reverse_proxy https://${ownerIp}:${port}" serverCaddy
        && lib.hasInfix "tls_server_name ${ownerName}" serverCaddy
        && lib.hasInfix "header_up Host ${ownerName}" serverCaddy
        && lib.elem route.port server.networking.firewall.allowedTCPPorts)
        "n8n compatibility: former-owner listener, upstream, TLS identity or firewall missing";
      assert lib.assertMsg (lib.hasInfix "${ownerName}:${port}" work.services.caddy.extraConfig
        && lib.hasInfix "reverse_proxy http://127.0.0.1:${toString work.hwc.automation.n8n.port}" work.services.caddy.extraConfig)
        "n8n compatibility: work does not serve the local application";
      pkgs.runCommand "n8n-route-compatibility" {} ''touch "$out"'';

      # Tracked n8n workflow JSON is a REDACTED DERIVED EXPORT of live n8n
      # (domains/automation/n8n/parts/workflows/README.md). This runs the same
      # scanner the export tool refuses to write past, so a raw webhook, bearer
      # token, API key or unrecognised credential-shaped literal cannot reach
      # git through a hand-pasted export. The rule table lives in the tool, not
      # here — one producer — and is exercised by
      # workspace/automation/test_n8n_workflow_export.py.
      n8n-workflow-secret-literals = pkgs.runCommand "n8n-workflow-secret-literals" {
        nativeBuildInputs = [ pkgs.python3 ];
      } ''
        cd ${self}
        python3 workspace/automation/n8n-workflow-export.py \
          scan --dir domains/automation/n8n/parts/workflows
        touch $out
      '';
      charter-law16 = mkCharterLint "law16-layer-purity" [
        "rg 'mkDerivation|fetchurl|writeShellScript' profiles/ --glob '!README.md'"
        "rg -i '\\b(laptop|xps|kids|firestick|hwc-home)\\b' profiles/ --glob '!README.md'"
        "rg 'import.*profiles/' profiles/"
        "rg 'mkOption|mkEnableOption' profiles/"
      ];
    };

    #========================================================================
    # GENERATED OUTPUTS — one nixosConfiguration + one standalone
    # homeConfiguration per machine in the registry.
    # Standalone HM usage: home-manager switch --flake ~/.nixos#eric@$(hostname)
    # Alias: hms
    #========================================================================
    homeConfigurations = lib.mapAttrs' (name: m:
      lib.nameValuePair "eric@hwc-${name}" (mkHome name m)
    ) machines;

    nixosConfigurations = lib.mapAttrs' (name: m:
      lib.nameValuePair "hwc-${name}" (mkNixos name m)
    ) machines;
  };
}
