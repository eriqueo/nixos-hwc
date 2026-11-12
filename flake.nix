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


    claude-cowork = {
      # Cowork-capable Claude Desktop for Linux. Replaces aaddrick's
      # claude-desktop-debian, whose buildFHSEnv wrapper left Electron's
      # main-process networking dead inside the sandbox (net::ERR_FAILED on
      # OAuth) — chat worked via the renderer's own Chromium stack, but Cowork's
      # main-process OAuth could never start a session. This port takes a
      # different approach: it extracts the macOS app, stubs the macOS-native
      # modules (@ant/claude-swift, @ant/claude-native) in JS, translates VM
      # /sessions paths to host paths in-process, and runs Claude Code directly
      # under bubblewrap; the overlay supplies a supported Electron runtime.
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

    # Third-party terminal arcade source; upstream has no Nix flake.
    # Package adapter: domains/home/apps/atari-style. Update through flake.lock.
    atari-style = {
      url = "github:jcaldwell-labs/atari-style";
      flake = false;
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

    # One import policy; callers keep their channel and ordered overlay suffix.
    mkPackageSet = { system, nixpkgsInput, overlays, cudaSupport ? false }:
      import nixpkgsInput {
        inherit system;
        config = {
          allowUnfree = true;
          nvidia.acceptLicense = true;
          permittedInsecurePackages = [ "qtwebengine-5.15.19" ];
        } // lib.optionalAttrs cudaSupport { cudaSupport = true; };
        overlays = [ silenceDeprecatedAliases gitCleanupOverlay nodejsSecurityOverlay
          pythonCompatibilityOverlay pythonRuntimeSecurityOverlay ] ++ overlays;
      };

    mkPkgs = system: nixpkgsInput: extraOverlays:
      mkPackageSet {
        inherit system nixpkgsInput;
        overlays = [
          # Expose the cowork-capable Claude Desktop package (package-only flake,
          # no overlay of its own) under pkgs for the home app module.
          (final: prev: {
            # TEMPORARY: the channel's44.9.3 predates October security fixes.
            # Retain T3's Electron44 ABI. Remove when its channel provides
            # Electron44.10.1 or newer; hashes are upstream SHASUMS256.txt.
            electron_44 = (prev.callPackage
              (inputs.nixpkgs + "/pkgs/development/tools/electron/binary/generic.nix")
              {}) "44.10.1" {
                x86_64-linux = "2be868b71b0aa71f30e6b5567a106a35a049385e963183c074aad1975ead5167";
                aarch64-linux = "0e16c008d628a9c8758ee75b6e2faf2f2ee5365e7e522f0884c8e52d0d551d2c";
                headers = "sha256-rsL5MzFdTiloJkECseOlSGQYhs0EdC8KGwoTouD58QU=";
              };
            # TEMPORARY: upstream names an EOL electron_41 argument. Preserve
            # its app/launcher, qualify with44, and remove when upstream's
            # recipe requests a supported runtime itself.
            claude-cowork-linux =
              inputs.claude-cowork.packages.${prev.stdenv.hostPlatform.system}.default.override {
                electron_41 = final.electron_44;
              };
          })
        ] ++ extraOverlays;
      };

    # Python peer compatibility applies to both normal and CUDA package sets.
    # PostHog7 requires MCP1; stable Streamlit needs the maintained Pillow13 recipe.
    # Removal conditions are attached to the two package overrides below.
    pythonCompatibilityOverlay = final: prev: {
            pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
              (pythonFinal: pythonPrev: {
                # TEMPORARY: channel Streamlit excludes security-fixed Pillow13.
                # Upstream1.66.1 declares pillow<14,>=9.2.0. Keep the recipe's
                # dependency checks; remove when both channels supply>=1.66.1.
                streamlit = (pythonFinal.callPackage
                  (inputs.nixpkgs + "/pkgs/development/python-modules/streamlit") {}).overridePythonAttrs {
                    version = "1.66.1";
                    src = prev.fetchurl {
                      url = "https://files.pythonhosted.org/packages/7f/20/d6490a27b4985907364112f40511c8e575efe042fb05983d060c753daf1c/streamlit-1.66.1.tar.gz";
                      hash = "sha256-dxCotnRp2nr3vzUDybaK/KVnb4MvYvm9oSIeDOEZQdE=";
                    };
                  };
              } // prev.lib.optionalAttrs (pythonPrev ? mcp_1) {
                  # TEMPORARY:7.71's peer contract excludes MCP2. Remove
                  # when its upstream recipe selects mcp_1 or supports MCP2.
                  posthog = pythonPrev.posthog.override { mcp = pythonFinal.mcp_1; };
                })
            ];
          };

    # Stable hosts backport the CLI from the existing unstable channel.
    claudeCodeOverlay = import ./overlays/claude-code.nix { nixpkgs-unstable = nixpkgs; };



    # Ghidra overlay — TEMPORARY (tracked). REA accepts only Ghidra 12.1.x;
    # stable 26.05 has 12.0.4. See the file header for the removal condition.
    ghidraOverlay = import ./overlays/ghidra.nix { nixpkgs-unstable = nixpkgs; };

    # TEMP: native Git pack cleanup on cancellation; removal test in the overlay.
    gitCleanupOverlay = import ./overlays/git.nix;
    # Node.js security overlay — TEMPORARY (tracked). Node 24.22.1 / 22.23.4
    # with brotli CVE-2026-111497 fix, ahead of both channels. See the file
    # header for the removal condition.
    nodejsSecurityOverlay = import ./overlays/nodejs-security.nix;
    # Helpers only: keep Python build/package graphs unchanged. Runtime
    # consumers select the checked stdlib explicitly after qualification.
    pythonRuntimeSecurityOverlay = import ./overlays/python-runtime-security.nix;

    # TEMPORARY: native modules select corrected runtimes without feeding them
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

    # CUDA remains explicit; its Claude overlay precedes caller overlays.
    mkPkgsWithOverlays = system: nixpkgsInput: extraOverlays:
      mkPackageSet {
        inherit system nixpkgsInput;
        cudaSupport = true;
        overlays = [ claudeCodeOverlay ] ++ extraOverlays;
      };

    # Runtime selection stays outside Python's package fixed point. Preserve
    # native/CUDA build packages; only the three owned instances opt in below.
    mkPythonRuntimeScope = original:
      let
        applications = (lib.mapAttrs (_: source: original.mkPythonHttpApplication {
          application = source.packages.${original.system}.default;
          python = source.inputs.nixpkgs.legacyPackages.${original.system}.python3;
        }) { inherit (inputs) workbench meals pnc-statement-pipeline; })
          // lib.genAttrs [ "piper-tts" "yt-dlp" ] (name: original.mkPythonHttpApplication {
            application = original.${name};
            python = original.python3;
          });
      in original // {
        python3 = original.mkPythonHttpRuntime original.python3;
        pythonHttpApplications = applications;
        inherit (applications) piper-tts yt-dlp;
      };

    # CHARTER v9.0: Use unstable for laptop (latest features), stable for server (production stability)
    pkgs = mkPkgs system nixpkgs [];
    pkgs-laptop = pkgs;

    # Stable hosts use the current CLI without a separate nixpkgs pin.
    pkgs-stable = mkPkgs system nixpkgs-stable [ ghidraOverlay claudeCodeOverlay ];

    # pkgs-stable with CUDA overlay for server (Immich ML GPU acceleration)
    pkgs-stable-cuda = mkPkgsWithOverlays system nixpkgs-stable [ ghidraOverlay ];

    checkRuntimeScope = mkNodeRuntimeScope pkgs;
    laptopRuntimeScope = mkNodeRuntimeScope pkgs-laptop;
    serverRuntimeScope = mkNodeRuntimeScope pkgs-stable;
    serverCudaRuntimeScope = mkNodeRuntimeScope pkgs-stable-cuda;
    laptopPythonRuntimePkgs = mkPythonRuntimeScope laptopRuntimeScope.pkgs;
    serverPythonRuntimePkgs = mkPythonRuntimeScope serverRuntimeScope.pkgs;
    serverCudaPythonRuntimePkgs = mkPythonRuntimeScope serverCudaRuntimeScope.pkgs;

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
        nixosPkgs = serverCudaPythonRuntimePkgs; # CUDA build graph, explicit native runtimes
        hmPkgs    = serverPythonRuntimePkgs;     # standalone HM stays plain stable
        scopedNodeRuntime = true;
      };
      work = {
        channel   = "stable";
        roles     = [ "base" "server" "mail" "business" "monitoring" ];
        nixosPkgs = serverPythonRuntimePkgs;
        hmPkgs    = serverPythonRuntimePkgs;
        scopedNodeRuntime = true;
      };
      laptop = {
        channel   = "unstable";
        roles     = [ "base" "desktop" ];
        nixosPkgs = laptopPythonRuntimePkgs;
        hmPkgs    = laptopPythonRuntimePkgs;
        scopedNodeRuntime = true;
        hmBackupExt  = "hm-bak";
        extraModules = [ inputs.nixvirt.nixosModules.default ];
      };
      xps = {
        channel   = "stable";
        roles     = [ "base" "desktop" "server" ];
        nixosPkgs = serverRuntimeScope.pkgs;
        hmPkgs    = serverRuntimeScope.pkgs;
        scopedNodeRuntime = true;
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

    # Fleet mail ownership supplies both client targets and existing mail checks.
    mailMachines = lib.filterAttrs (_: machine: lib.elem "mail" machine.roles) machines;
    mailOwner = assert lib.assertMsg (lib.length (builtins.attrNames mailMachines) == 1)
      "mail consumers: expected one mail-role owner";
      builtins.head (builtins.attrNames mailMachines);
    mailHost = "hwc-${mailOwner}";

    # Both Home Manager lanes receive the same system-owned values: the capture
    # path, Courier tailnet hostname, and the Tether package (built once by
    # the system half; without it standalone `hms` dropped the tetherd unit).
    homeSpecialArgs = name: ch:
      let
        sysConfig = self.nixosConfigurations."hwc-${name}".config;
        mailSystem = self.nixosConfigurations.${mailHost}.config;
        mailHome = mailSystem.home-manager.users.eric;
        hmLib = import ./domains/lib/hm.nix { inherit lib; };
      in {
        inherit inputs;
        nixosApiVersion = ch.apiVersion;
        # Remote paths are identity data, not local execution dependencies.
        # The mail owner's system and consumer check retain their real context;
        # copying it here would install the server's Mail stack on the laptop.
        workbenchMailTarget = {
          host = mailSystem.hwc.networking.hosts.fqdn.${mailOwner};
          remoteHelper = builtins.unsafeDiscardStringContext mailHome.programs.workbench.mailHelper.executable;
          remoteProfile = builtins.unsafeDiscardStringContext mailHome.programs.workbench.mailHelper.profilePath;
        };
        screenshotRoot = lib.attrByPath [ "hwc" "paths" "screenshots" ] null sysConfig;
        courierTailnetHost = "${sysConfig.networking.hostName}.${(hmLib.fleet sysConfig).tailnetSuffix}";
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
          # Instance binding belongs at composition; the server role consumes
          # generic storage metadata without naming a machine or key file.
          offsiteStorage = let storage = self.nixosConfigurations.hwc-xps.config; in {
            # Temporary rollout gate: enable after the cable/destination and
            # real restricted-repository restore pass, before controlled rollout.
            ready = false;
            repositories = storage.services.borgbackup.repos;
            address = storage.hwc.networking.hosts.selfIp;
            hostKey = lib.removeSuffix "\n" (builtins.readFile ./machines/xps/SSH_HOST_ED25519_PUBLIC_KEY.txt);
            recovery = let home = self.nixosConfigurations.hwc-home.config; in {
              # SSD state backup to the existing home destination is independent
              # of the held Maryland enclosure/replication rollout.
              ready = true;
              address = home.hwc.networking.hosts.selfIp;
              repository = home.services.borgbackup.repos.hwc-xps;
              hostKey = lib.removeSuffix "\n" (builtins.readFile ./machines/home/SSH_HOST_ED25519_PUBLIC_KEY.txt);
            };
          };
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
            {
              home.username = "eric"; home.homeDirectory = "/home/eric";
              # Consume the one system-HM origin producer without injecting
              # osConfig into every standalone home module.
              hwc.home.apps.workbench.serverUrl = lib.mkDefault
                self.nixosConfigurations."hwc-${name}".config.home-manager.users.eric.hwc.home.apps.workbench.serverUrl;
              # Same handshake for the tracker's Discord cards, whose producer
              # is the system control bot: `hms` must not switch them off.
              hwc.home.apps.agent-harness.tracker.discordCards = lib.mkDefault
                self.nixosConfigurations."hwc-${name}".config.home-manager.users.eric.hwc.home.apps.agent-harness.tracker.discordCards;
            }
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
    verification = import ./workspace/nixos-dev/verification {
      inherit self inputs lib system checkRuntimeScope channels keymapDocs keymapDocsApp laptopRuntimeScope machines mailHost mailMachines mailOwner pkgs-firestick pkgs-laptop pkgs-stable pkgs-stable-cuda serverCudaRuntimeScope serverRuntimeScope;
    };
  in {
    lib.verification = verification.inventory;
    lib.fleet = lib.mapAttrs' (name: machine:
      lib.nameValuePair "hwc-${name}" { inherit (machine) channel roles; }
    ) machines;
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
    # CHECKS — explicit owner registry; implementations stay beside their owner.
    #========================================================================
    checks.${system} = verification.checks;

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
