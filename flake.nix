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
    # Fleet map UI and read-only capture tools have their own app lifecycle.
    fleet-map = { url = "github:eriqueo/fleet-map"; flake = false; };

    # Ingest code deploys with the system generation, never from a timer pull.
    brainvec = { url = "github:eriqueo/brainvec"; flake = false; };
    refinery = { url = "github:eriqueo/refinery"; flake = false; };

    nixpkgs.url         = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url  = "github:NixOS/nixpkgs/nixos-26.05";
    # TS-2026-011 needs Tailscale >= 1.102.3; stable 26.05 has 1.98.10.
    # Remove this temporary pin when both Nixpkgs inputs provide >= 1.102.3.
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/4975466d324710c576dc11ad614684e6bd8cad8e";

    # Static agent policy and adapters. Mutable memories and the mistakes
    # ledger live in ~/.agent-state and never enter this Nix input.
    agent-harness = {
      url = "github:eriqueo/claude-config";
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
          pandasStubsOverlay   # TEMP: skip pandas-stubs tests (upstream pytest-9.1.1 breakage)
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

    # pandas-stubs overlay — TEMPORARY (tracked). Skips pandas-stubs' failing test
    # phase on the 2026-07-25 nixpkgs (upstream pytest-9.1.1 deprecation-as-error
    # that otherwise fails the whole HM user-environment). See the file header for
    # the removal condition.
    pandasStubsOverlay = import ./overlays/pandas-stubs.nix;

    # Pkgs helper with optional overlays (server uses this)
    # CUDA enabled - using cache.nixos-cuda.org for pre-built binaries
    mkPkgsWithOverlays = system: nixpkgsInput: extraOverlays:
      import nixpkgsInput {
        inherit system;
        overlays = [ silenceDeprecatedAliases pandasStubsOverlay claudeCodeOverlay cloudflaredOverlay ] ++ extraOverlays;
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
    pkgs-stable = mkPkgs system nixpkgs-stable [ tailscaleOverlay ];

    # pkgs-stable with CUDA overlay for server (Immich ML GPU acceleration)
    pkgs-stable-cuda = mkPkgsWithOverlays system nixpkgs-stable [ serverOverlay tailscaleOverlay ];

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
        nixosPkgs = pkgs-stable-cuda;  # CUDA overlay (Immich ML / llama.cpp)
        hmPkgs    = pkgs-stable;       # standalone HM lane stays plain stable
      };
      work = {
        channel   = "stable";
        roles     = [ "base" "server" "mail" "business" "monitoring" ];
        nixosPkgs = pkgs-stable;
        hmPkgs    = pkgs-stable;
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
          { nixpkgs.hostPlatform = sysArch; }
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
              extraSpecialArgs = {
                inherit inputs;
                nixosApiVersion = ch.apiVersion;
              };
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
        extraSpecialArgs = {
          inherit inputs;
          nixosApiVersion = ch.apiVersion;
        };
        modules =
          roleHalves "home.nix" m.roles
          ++ [
            (./machines + "/${name}/home.nix")
            { home.username = "eric"; home.homeDirectory = "/home/eric"; }
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

  in {
    # Apps - CLI utilities
    apps.${system} = {
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

      # Exercise the actual laptop module wiring, not a second layout renderer.
      workbench-navigation = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        navigation = import ./domains/home/apps/zellij/parts/tabs.nix {
          inherit lib; hubRegistry = inputs.workbench.hubRegistry;
        };
        layout = home.xdg.configFile."zellij/layouts/workbench.kdl".text;
        configKdl = home.xdg.configFile."zellij/config.kdl".text;
        captures = pattern: text: map builtins.head
          (builtins.filter builtins.isList (builtins.split pattern text));
        names = captures ''tab name="([^"]+)"'' layout;
        hubCommands = captures ''args "--hub" "([^"]+)"'' layout;
        focused = captures ''tab name="([^"]+)" focus=true'' layout;
        grammar = home.hwc.home.keymap.grammar;
        jumps = lib.filter (entry: entry ? target) grammar.meta;
        destinationFor = key: (builtins.head (lib.filter (entry: entry.key == key) jumps)).target;
        acceptsRegistry = registry: (builtins.tryEval (builtins.deepSeq
          (import ./domains/home/apps/zellij/parts/tabs.nix { inherit lib; hubRegistry = registry; }) true)).success;
        registry = inputs.workbench.hubRegistry;
      in
      assert lib.assertMsg (!acceptsRegistry (registry // { schemaVersion = 999; }))
        "workbench check: unsupported registry schema accepted";
      assert lib.assertMsg (!acceptsRegistry (registry // { hubs = registry.hubs ++ [ (builtins.head registry.hubs) ]; }))
        "workbench check: duplicate registry hub accepted";
      assert lib.assertMsg (!acceptsRegistry (registry // { hubs = map (hub: hub // { defaultTab = false; }) registry.hubs; }))
        "workbench check: hidden landing accepted";
      assert lib.assertMsg (builtins.head names == "brief" && focused == [ "brief" ] && !(lib.elem "server" names))
        "workbench check: Brief must land first and Server must remain on demand";
      assert lib.assertMsg (names == map (tab: tab.name) navigation.destinations)
        "workbench check: generated tab names/order differ from navigation";
      assert lib.assertMsg (hubCommands == map (hub: hub.slug) navigation.hubTabs)
        "workbench check: generated hub commands differ from registry";
      assert lib.assertMsg (focused == [ navigation.landingHub ])
        "workbench check: generated landing tab differs from registry";
      assert lib.assertMsg (home.programs.workbench.defaultHub == navigation.landingHub
        && home.programs.workbench.tabs == navigation.launcherTabs)
        "workbench check: launcher destinations differ from layout";
      assert lib.assertMsg (lib.versionAtLeast home.hwc.home.apps.zellij.package.version "0.45.1"
        && lib.elem home.hwc.home.apps.zellij.package home.programs.workbench.extraRuntimePackages
        && lib.elem home.hwc.home.apps.zellij.package home.home.packages)
        "workbench check: shell and wrapper must share the graphics-capable pane host";
      assert lib.assertMsg (lib.all (entry: lib.hasInfix
        "${entry.key}|goto-tab|${toString navigation.tabFor.${entry.target}}|${entry.desc}" configKdl) jumps)
        "workbench check: generated grammar indices differ from navigation";
      assert lib.assertMsg (destinationFor "m" == "tool:aerc" && destinationFor "i" == "hub:mail"
        && destinationFor "R" == "hub:refinery" && destinationFor "N" == "hub:nightly")
        "workbench check: mail/refinery/nightly shortcuts changed destination";
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
          "<A-h> = :prev-tab<Enter>"
          "<A-l> = :next-tab<Enter>"
          "<A-J> = :next-tab<Enter>"
          "<A-K> = :prev-tab<Enter>"
          "<A-S-j> = :next-tab<Enter>"
          "<A-S-k> = :prev-tab<Enter>"
          "<Space>ft = :filter tag:"
          "<Space>fT = :query -f -n tag-search tag:"
          "<Space>fc = :clear -s<Enter>"
          "<Space>fu = :unsubscribe -s<Enter>"
          "<Space>ta = :pipe -m mail-classifier correct --state do<Enter>"
          "<Space>td = :pipe -m mail-classifier correct --state did<Enter>"
          "<Space>tcd = :pipe -m mail-classifier correct --domain datax<Enter>"
          "<Space>ra = :pipe -m mail-classifier route-review<Enter>"
          "<Space>rm = :term mail-classifier route-manage<Enter>"
        ];
        missing = lib.filter (needle: !(lib.hasInfix needle binds)) required;
      in
      assert lib.assertMsg (missing == [])
        "aerc-bindings: generated server binds are missing ${lib.concatStringsSep ", " missing}";
      assert lib.assertMsg (lib.length directMarkLines <= 8)
        "aerc-bindings: first mark popup has ${toString (lib.length directMarkLines)} direct entries (limit 8)";
      assert lib.assertMsg (!(lib.hasInfix "<Space>m! =" binds) && !(lib.hasInfix "<Space>m? =" binds))
        "aerc-bindings: action/pending leaked back into the human mark menu";
      assert lib.assertMsg (!(lib.hasInfix "-keep" tags.clearFlagsCmd) && !(lib.hasInfix "-keep" tags.clearAllCmd))
        "aerc-bindings: a bulk clear can remove the protected keep tag";
      assert lib.assertMsg (builtins.all (tag: !(lib.elem "-${tag}" (lib.splitString " " tags.clearAllCmd)))
        ([ "flagged" "starred" "keep" "work" "finance" "family" "action" "pending" ]
          ++ map (domain: "${contract.domainTagPrefix}${domain}") contract.domains))
        "aerc-bindings: metadata clear strips stars, historical tags or Domain";
      assert lib.assertMsg (lib.hasInfix ":modify-labels ${tags.clearAllCmd}<Enter>" binds
        && lib.hasInfix "<Space>mvg = :modify-labels +ads<Enter>" binds
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
        && registry.searches."domain:family" == "tag:${contract.domainTagPrefix}family"
        && registry.searches."history:family" == "tag:family"
        && !(registry.searches ? business) && !(registry.searches ? money)
        && !(registry.searches ? "label:finance"))
        "aerc-bindings: current axes and historical search registry drifted";
      pkgs.runCommand "aerc-bindings" {
        nativeBuildInputs = [ pkgs.python3 pkgs.notmuch ];
        queries = home.home.file.".config/aerc/notmuch-queries".source;
        bindsFile = home.home.file.".config/aerc/binds.conf".source;
      } ''
        python3 - "$queries" "$bindsFile" <<'PY'
        import os, pathlib, subprocess, sys, tempfile
        queries = dict(line.split('=', 1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
                       if line and not line.startswith('#'))
        assert all(':' not in name for name in queries), queries
        binds = pathlib.Path(sys.argv[2]).read_text()
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
            clear = next(line for line in binds.splitlines() if '<Space>mx =' in line)
            operations = clear.split(':modify-labels ', 1)[1].split('<Enter>', 1)[0].split()
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
        print('generated views, legacy search, real metadata clear, stars and physical copies pass')
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
            line = next(line.strip() for line in view.splitlines() if line.strip().startswith('I = '))
            assert line.startswith('I = :pipe -s -m '), 'image view must receive full MIME and close on pager exit'
            return line.removeprefix('I = :pipe -s -m ').split('<Enter>', 1)[0]
        command = image_command(wiring['binds'])
        for broken in [re.sub(r'^\s*I = .*$', "", wiring['binds'], flags=re.M),
                       wiring['binds'].replace('I = :pipe -s -m ', 'I = :pipe -s -p ')]:
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
        ${pkgs.python3}/bin/python3 - ${mailHome.home.file.".local/bin/mail-health-check".source} <<'PY'
        import copy, json, os, pathlib, re, shlex, subprocess, sys, tempfile
        source = pathlib.Path(sys.argv[1]).read_text()
        start = source.index('check_mbsync() {')
        fragment = source[start:source.index('# ─── Check 5:', start)]
        healthy = {'state': 'healthy', 'lastOutcome': 'success', 'exitCode': 0, 'lastSuccessEpoch': 9900}
        base = {'schemaVersion': 1, 'lanes': {k: copy.deepcopy(healthy) for k in ['core', 'trash', 'labels']}}
        def run(text, status, result='success', exit_code=0, projection=True):
            with tempfile.TemporaryDirectory() as d:
                root = pathlib.Path(d); state = root/'status.json'; state.write_text(json.dumps(status))
                ctl = root/'systemctl'
                ctl.write_text('#!${pkgs.python3}/bin/python3\nimport os,sys\n'
                    'if "show" in sys.argv: print(os.environ["RESULT"] if "Result" in sys.argv else os.environ["EXIT_CODE"])\n')
                ctl.chmod(0o700)
                script = re.sub(r'/nix/store/[^\s]+/bin/systemctl', str(ctl), text)
                header = 'set -eu\nSYNC_STATUS='+shlex.quote(str(state))+'\nSYNC_MAX_AGE_MIN=45\nTRASH_SYNC_MAX_AGE_MIN=1800\nTRASH_TIMER_ENABLED=true\n'
                header += 'LABEL_PROJECTION_ENABLED='+str(projection).lower()+'\nnow_epoch() { echo 10000; }\nfail() { echo "F:$*"; }\nwarn() { echo "W:$*"; }\n'
                r = subprocess.run(['${pkgs.bash}/bin/bash','-c',header+script+'\ncheck_mbsync\n'],capture_output=True,text=True,
                    env={**os.environ,'RESULT':result,'EXIT_CODE':str(exit_code)})
                assert r.returncode == 0, r.stderr
                return r.stdout.splitlines()
        def label_failure(text):
            s = copy.deepcopy(base); s['lanes']['labels'].update(state='degraded',lastOutcome='projection-failed',exitCode=69)
            lines = run(text,s,'exit-code',69)
            assert not any(x.startswith('F:') for x in lines), lines
            assert any(x.startswith('W:Mail sync lane labels is degraded') for x in lines), lines
        label_failure(fragment)
        assert run(fragment,base) == []
        s = copy.deepcopy(base); s['lanes']['core'].update(state='degraded',exitCode=1)
        assert any(x.startswith('F:Mail sync lane core') for x in run(fragment,s,'exit-code',1))
        s = copy.deepcopy(base); s['lanes']['core']['lastSuccessEpoch']=1
        assert any(x.startswith('F:Mail sync lane core last succeeded') for x in run(fragment,s))
        assert any(x.startswith('F:Mail sync status is missing') for x in run(fragment,{}))
        assert any(x.startswith('F:mbsync.service') for x in run(fragment,base,'exit-code',23))
        s = copy.deepcopy(base); s['lanes']['labels']['lastSuccessEpoch']=1
        assert any(x.startswith('W:Mail sync lane labels last succeeded') for x in run(fragment,s))
        del s['lanes']['labels']; assert run(fragment,s,projection=False)==[]
        broken,count=re.subn(r'if \[\[ "\$core_result" != exit-code.*?\]\]; then','if true; then',fragment,flags=re.S)
        assert count==1
        try: label_failure(broken)
        except AssertionError: pass
        else: raise AssertionError('removed health distinction passed wiring test')
        print('generated mail health: label warning, healthy transport, real failures, stale lanes and removed wiring pass')
        PY
        touch "$out"
      '';

      mail-residency-shadow = let
        home = mailHome;
        fixture = pkgs.writeText "mail-residency-shadow.json" (builtins.toJSON {
          script = home.home.file.".local/bin/sync-mail".text;
          command = home.hwc.mail.classifier.residency.command;
          projection = home.hwc.mail.classifier.projection.command;
          statusFile = home.hwc.mail.mbsync.statusFile;
          maildirRoot = home.hwc.mail.notmuch.maildirRoot;
        });
      in
      assert lib.assertMsg home.hwc.mail.classifier.residency.enable
        "mail-residency-shadow: mail host must observe in shadow";
      pkgs.runCommand "mail-residency-shadow" {} ''
        ${pkgs.python3}/bin/python3 - ${fixture} <<'PY'
        import json
        import os
        import pathlib
        import re
        import subprocess
        import sys
        import tempfile

        fixture = json.loads(pathlib.Path(sys.argv[1]).read_text())
        original = fixture['script']
        assert original.count(fixture['command']) == 1
        assert original.count(fixture['projection']) == 1

        def exercise(source, stage="", mode='core'):
            with tempfile.TemporaryDirectory() as directory:
                root = pathlib.Path(directory)
                log = root / 'calls'
                status = root / 'status.json'
                stub = root / 'command'
                stub.write_text('#!${pkgs.python3}/bin/python3\n'
                    'import os, pathlib, sys\n'
                    'name = pathlib.Path(sys.argv[0]).name\n'
                    'if name == "mail-classifier": name = sys.argv[1]\n'
                    'if name == "transport": name += "-" + sys.argv[sys.argv.index("--phase") + 1]\n'
                    'if name == "mbsync" and "--pull-new" in sys.argv: name = "prefetch"\n'
                    'with open(os.environ["CALL_LOG"], "a") as f: f.write(name + "\\n")\n'
                    'raise SystemExit(23 if name == os.environ["FAIL_STAGE"] else 0)\n')
                stub.chmod(0o755)
                for name in ['afew', 'mbsync', 'notmuch', 'mail-classifier']:
                    (root / name).symlink_to(stub)
                script = source.replace(fixture['statusFile'], str(status))
                script = script.replace(fixture['maildirRoot'], str(root / 'Maildir'))
                script = re.sub(r'/nix/store/[^\s"\x27]+/bin/(afew|mbsync|notmuch|mail-classifier)\b',
                    lambda m: str(root / m[1]), script)
                wrapper = root / 'sync-mail'
                wrapper.write_text(script)
                wrapper.chmod(0o755)
                result = subprocess.run(['${pkgs.bash}/bin/bash', str(wrapper), mode],
                    env={**os.environ, 'CALL_LOG': str(log), 'FAIL_STAGE': stage, 'SYNC_MAIL_LOCKED': '1'},
                    capture_output=True, text=True)
                calls = log.read_text().splitlines()
                lanes = json.loads(status.read_text())['lanes']
                assert 'notmuch' in calls, 'indexing must survive transport/mover failure'
                if mode == 'trash':
                    assert calls == ['mbsync', 'notmuch'], calls
                    assert 'residency' not in lanes
                    assert 'labels' not in lanes
                else:
                    expected = ['prefetch', 'mbsync', 'notmuch']
                    fetched = stage not in ['prefetch', 'mbsync', 'notmuch']
                    if fetched:
                        expected += ['observe-residency', 'transport-apply']
                        if stage != 'transport-apply':
                            expected.append('afew')
                            if stage != 'afew':
                                expected += ['mbsync', 'transport-ack']
                    expected.append('notmuch')
                    healthy = fetched and stage not in ['transport-apply', 'afew', 'transport-ack']
                    if healthy and stage != 'observe-residency': expected.append('project-labels')
                    assert calls == expected, calls
                    assert lanes['core']['state'] == ('healthy' if healthy else 'degraded')
                    assert lanes['residency']['state'] == ('healthy' if healthy and stage != 'observe-residency' else 'degraded')
                    assert lanes['labels']['state'] == ('healthy' if healthy and not stage else 'degraded')
                assert result.returncode == (23 if stage else 0), result.stderr

        for stage in ["", 'prefetch', 'afew', 'mbsync', 'notmuch', 'observe-residency', 'transport-apply', 'transport-ack', 'project-labels']:
            exercise(original, stage)
        exercise(original, mode='trash')
        for missing in ['--pull-new --pull-gone --create-near --remove-none --expunge-near', '--phase apply', '--phase ack']:
            try:
                exercise(original.replace(missing, '--missing-wiring'))
            except AssertionError:
                pass
            else:
                raise AssertionError('removed reconciliation wiring passed: ' + missing)
        try:
            exercise(original.replace(fixture['command'], 'true'))
        except AssertionError:
            pass
        else:
            raise AssertionError('removed observer wiring passed its check')
        try:
            exercise(original.replace(fixture['projection'], 'true'))
        except AssertionError:
            pass
        else:
            raise AssertionError('removed projector wiring passed its check')
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
        hook = home.home.file."/home/eric/400_mail/Maildir/.notmuch/hooks/post-new".text;
        bindLines = lib.splitString "\n" binds;
        bindCount = needle: lib.length (lib.filter (line: lib.hasInfix needle line) bindLines);
        archiveDisposition = "      a = :pipe -m mail-classifier transition --outcome done<Enter>";
        trashDisposition = "      d = :pipe -m mail-classifier transition --outcome trash<Enter>";
        requiredBinds = [
          "<Space>gA = :cf all<Enter>"
          "<Space>sf = :sort from -r date<Enter>"
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
        && bindCount "<Space>tT = :fold -a<Enter>" == 1
        && !(lib.hasInfix ":toggle-threads<Enter>" binds))
        "mail-workflow-v2: thread fold controls changed unexpectedly";
      assert lib.assertMsg (bindCount "<Space>ma = :pipe -m mail-classifier transition --outcome done<Enter>" == 1
        && bindCount "<Space>md = :pipe -m mail-classifier transition --outcome trash<Enter>" == 1)
        "mail-workflow-v2: marked-message archive/trash controls changed unexpectedly";
      assert lib.assertMsg (lib.hasInfix "sort = -r date" aercConf)
        "mail-workflow-v2: newest-first is not the default sort";
      assert lib.assertMsg (lib.hasInfix "do = tag:state/do" queries
        && lib.hasInfix "did = tag:state/did" queries
        && lib.hasInfix "look = tag:state/look" queries
        && lib.hasInfix "junk = tag:state/junk" queries)
        "mail-workflow-v2: workflow state views regressed";
      assert lib.assertMsg (!(lib.hasInfix "category/" queries)
        && !(lib.hasInfix "attention/" queries)
        && !(lib.hasInfix "tag:queue" queries)
        && lib.hasInfix "all            = NOT tag:trash" queries)
        "mail-workflow-v2: legacy workflow/category folders returned";
      assert lib.assertMsg (lib.hasInfix "index-columns = from<20,subject<*,date<10,domain<9,state<5,tags<24" aercConf
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
        folder_state = hook.index("+inbox +state/do")
        remove_new = hook.index("# Remove transient new tag", folder_state)
        assert folder_state < remove_new, "new mail loses its safe DO state"
        assert "mail-rule" not in hook, "retired sender-rule writer returned"
        assert "tag:new AND NOT tag:keep" not in hook, "legacy sender placement returned"

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
                    subprocess.run(['${afewTest}/bin/afew', '-m', '-a'], env=env, check=True, capture_output=True)
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
                def move(): subprocess.run(['${afewTest}/bin/afew', '-m', '-a'],env=env,check=True,capture_output=True)
                raw = 'Message-ID: <trash@example.invalid>\nFrom: sender@example.invalid\nTo: fixture@example.invalid\nSubject: Fixture\nDate: Thu, 01 Oct 2026 12:00:00 +0000\n\nSynthetic content\n'
                inbox = mail / 'proton/inbox/cur/old:2,S'; trash = mail / 'proton/Trash/cur/fetched:2,S'
                inbox.write_text(raw); nm('new'); trash.write_text(raw); nm('new')
                # A partial physical copy and stale Inbox tag are NOT local restore intent.
                move(); assert trash.exists(), 'stale Inbox undid fetched Trash'
                assert inbox.exists(), 'partial copy was deleted'
                inbox.unlink(); nm('new')
                for _ in range(3):
                    move(); nm('new')
                    assert trash.exists() and not list((mail/'proton/inbox/cur').iterdir())
                # Only the durable command projection marker authorizes restoration.
                nm('tag','+transport/inbox','+inbox','-trash','--','id:trash@example.invalid')
                move(); nm('new')
                assert not trash.exists() and len(list((mail/'proton/inbox/cur').iterdir())) == 1
        afew_source = pathlib.Path(sys.argv[3]).read_text()
        check_phone_trash(afew_source)
        try:
            check_phone_trash(afew_source.replace('tag:transport/inbox','tag:inbox'))
        except AssertionError:
            pass
        else:
            raise AssertionError('generic Inbox tags still authorize Trash restoration')

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
            def dispatch(text, verb="reopen"):
                wrapper = root / "wrapper"
                lock_path = ${builtins.toJSON "${builtins.dirOf mailHome.hwc.mail.mbsync.statusFile}/sync.lock"}
                wrapper.write_text(text.replace(runtime_path, str(runtime)).replace(lock_path, str(root / 'sync.lock')))
                wrapper.chmod(0o755)
                return subprocess.check_output([str(wrapper), verb], text=True).splitlines()
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
            assert '--bridge-host' in reviewed and '--notmuch' not in reviewed
            try:
                broken_review = dispatch(control.replace('|review-label-write', ""), 'review-label-write')
                assert '--bridge-host' in broken_review and '--notmuch' not in broken_review
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
        && lib.hasSuffix " --user %I" candidate.systemd.user.services."hwc-service-failure-notifier@".serviceConfig.ExecStart)
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
      in
      assert lib.assertMsg (dead == [])
        ("monitored units with no ExecStart (OnFailure= on these is a silent no-op): "
         + lib.concatStringsSep ", " dead);
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
        hookFiles = map (c: pkgs.writeText "borg-pre-hook" c.services.borgbackup.jobs.hwc-backup.preHook) hosts;
        restore = lib.findFirst (p: (p.name or "") == "borg-restore") null
          self.nixosConfigurations.hwc-work.config.environment.systemPackages;
      in
      assert lib.all (c: !(lib.hasInfix "break-lock"
        (c.systemd.services.borgbackup-job-hwc-backup.preStart or ""))) hosts;
      assert lib.all (c: lib.hasInfix (builtins.unsafeDiscardStringContext "${c.services.postgresql.package}/bin/pg_dumpall")
        c.services.borgbackup.jobs.hwc-backup.preHook) hosts;
      pkgs.runCommand "borg-recovery" { nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils ]; } ''
        python3 - ${lib.concatStringsSep " " (map toString hookFiles)} ${restore}/bin/borg-restore <<'PY'
        import gzip, os, pathlib, re, subprocess, sys, tempfile
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            producer = root / "su"
            producer.write_text("#!${pkgs.bash}/bin/bash\nif [ -e " + str(root / "fail") + " ]; then exit 23; fi\nprintf 'valid SQL snapshot\\n'\n")
            producer.chmod(0o700)
            for i, hook in enumerate(sys.argv[1:-1]):
                dest = root / str(i)
                dest.mkdir()
                nested = dest / "service-split" / "recovery.json"
                nested.parent.mkdir()
                nested.write_text("keep")
                os.utime(nested, (1, 1))
                old = dest / "postgresql-old.sql.gz"
                old.write_text("expired")
                os.utime(old, (1, 1))
                script = pathlib.Path(hook).read_text().replace("/var/lib/backups", str(dest))
                script = script.replace("/run/wrappers/bin/su", str(producer))
                # Host-specific CouchDB/arr producers are outside this PG test.
                script = script.replace("systemctl is-active --quiet couchdb", "false")
                script = script.replace('SRC="/opt/', 'SRC="' + str(root) + '/absent/')
                subprocess.run(["bash", "-c", script], check=True)
                output = next(dest.glob("postgresql-2*.sql.gz"))
                before = output.read_bytes()
                assert gzip.decompress(before) == b"valid SQL snapshot\n"
                assert not old.exists() and nested.read_text() == "keep"
                (root / "fail").touch()
                assert subprocess.run(["bash", "-c", script]).returncode != 0
                assert output.read_bytes() == before
                assert not list(dest.glob(".postgresql-*"))
                (root / "fail").unlink()
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
