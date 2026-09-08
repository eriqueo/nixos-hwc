# nixos-hwc/flake.nix
#
# Flake: HWC NixOS Configuration (Roles Architecture)
# Single source of truth for the fleet: the `machines` registry maps each
# machine to a channel + role list. Glue resolves roles to
# profiles/<role>/{sys,home}.nix halves; machines/<m>/ holds hardware +
# genuine one-offs only.
#
# DEPENDENCIES (Upstream):
#   - nixpkgs (nixos-unstable), nixpkgs-stable (25.11)
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
    nixpkgs.url         = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url  = "github:NixOS/nixpkgs/nixos-25.11";

    nixvirt = {
        url = "github:AshleyYakeley/NixVirt";
        inputs.nixpkgs.follows = "nixpkgs";
      };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager-stable = {
      url = "github:nix-community/home-manager/release-25.11";
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
    mkPkgs = system: nixpkgsInput:
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
          rcloneOverlay   # iCloud-capable rclone 1.74.1 (HM lane on stable machines)
          # Expose the cowork-capable Claude Desktop package (package-only flake,
          # no overlay of its own) under pkgs for the home app module.
          (final: prev: {
            claude-cowork-linux =
              inputs.claude-cowork.packages.${prev.stdenv.hostPlatform.system}.default;
          })
        ];
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
    # Stable 25.11 lags upstream cloudflared releases; the daemon needs to track
    # current Cloudflare edge protocol to keep the tunnel healthy.
    cloudflaredOverlay = import ./overlays/cloudflared.nix { nixpkgs-unstable = nixpkgs; };

    # Rclone overlay - backport from unstable to stable
    # Stable 25.11's rclone 1.72.1 can't authenticate to iCloud Drive
    # (SRP auth fix landed in 1.74.0); unstable tracks 1.74.1. See overlay file.
    rcloneOverlay = import ./overlays/rclone.nix { nixpkgs-unstable = nixpkgs; };

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
        overlays = [ silenceDeprecatedAliases pandasStubsOverlay claudeCodeOverlay cloudflaredOverlay rcloneOverlay ] ++ extraOverlays;
        config = {
          allowUnfree = true;
          nvidia.acceptLicense = true;
          cudaSupport = true;  # Binary cache should provide pre-built CUDA packages
          permittedInsecurePackages = [
            "qtwebengine-5.15.19"
            "n8n-1.91.3"
          ];
        };
      };

    # CHARTER v9.0: Use unstable for laptop (latest features), stable for server (production stability)
    pkgs = mkPkgs system nixpkgs;

    # pkgs-stable (25.11 - claude-code now available natively)
    pkgs-stable = mkPkgs system nixpkgs-stable;

    # pkgs-stable with CUDA overlay for server (Immich ML GPU acceleration)
    pkgs-stable-cuda = mkPkgsWithOverlays system nixpkgs-stable [ serverOverlay ];

    # Firestick is the one aarch64 machine
    pkgs-firestick = mkPkgs "aarch64-linux" nixpkgs;

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
      server = {
        channel   = "stable";
        roles     = [ "base" "server" "business" "monitoring" "mail" ];
        nixosPkgs = pkgs-stable-cuda;  # CUDA overlay (Immich ML / llama.cpp)
        hmPkgs    = pkgs-stable;       # standalone HM lane stays plain stable
      };
      laptop = {
        channel   = "unstable";
        roles     = [ "base" "desktop" ];
        nixosPkgs = pkgs;
        hmPkgs    = pkgs;
        hmBackupExt  = "hm-bak";
        extraModules = [ inputs.nixvirt.nixosModules.default ];
      };
      xps = {
        channel   = "stable";
        roles     = [ "base" "desktop" "server" "monitoring" ];
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
      # Exercise the actual laptop module wiring, not a second layout renderer.
      # Credential checks use fake secrets; no server or real secret is accessed.
      radicale-client-auth = let
        home = self.homeConfigurations."eric@hwc-laptop".config;
        fixture = pkgs.writeText "radicale-client-config.json" (builtins.toJSON {
          command = home.programs.todui.radicale.passwordCommand;
          username = home.programs.todui.radicale.username;
          sync = home.xdg.configFile."vdirsyncer/config".text;
        });
      in pkgs.runCommand "radicale-client-auth" {
        nativeBuildInputs = [ pkgs.python3 pkgs.gawk ];
      } ''
        python3 - ${fixture} <<'PY'
        import configparser, json, pathlib, shlex, subprocess, sys
        cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
        sync = configparser.RawConfigParser()
        sync.read_string(cfg["sync"])
        clients = [("todui", cfg["username"], cfg["command"])]
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
            assert result.returncode == 0, f"{name}: credential command failed"
            assert result.stdout == expected[user] + "\n", f"{name}: wrong user's password"
            print(f"{name}: selected only its user's complete password")
        PY
        touch $out
      '';

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
      in
      assert lib.assertMsg (names == map (tab: tab.name) navigation.destinations)
        "workbench check: generated tab names/order differ from navigation";
      assert lib.assertMsg (hubCommands == map (hub: hub.slug) navigation.hubTabs)
        "workbench check: generated hub commands differ from registry";
      assert lib.assertMsg (focused == [ navigation.landingHub ])
        "workbench check: generated landing tab differs from registry";
      assert lib.assertMsg (home.programs.workbench.defaultHub == navigation.landingHub
        && home.programs.workbench.tabs == navigation.launcherTabs)
        "workbench check: launcher destinations differ from layout";
      assert lib.assertMsg (lib.all (entry: lib.hasInfix
        "${entry.key}|goto-tab|${toString navigation.tabFor.${entry.target}}|${entry.desc}" configKdl) jumps)
        "workbench check: generated grammar indices differ from navigation";
      assert lib.assertMsg (destinationFor "m" == "tool:aerc" && destinationFor "i" == "hub:mail"
        && destinationFor "R" == "hub:refinery" && destinationFor "N" == "hub:nightly")
        "workbench check: mail/refinery/nightly shortcuts changed destination";
      pkgs.runCommand "workbench-navigation" {} ''touch "$out"'';
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
      alert-rules-parse = let
        ruleFiles = self.nixosConfigurations."hwc-server".config.services.prometheus.ruleFiles;
      in
      assert lib.assertMsg (ruleFiles != [])
        "alert-rules-parse: hwc-server declares no prometheus ruleFiles — this check has no subject and would pass empty";
      pkgs.runCommand "alert-rules-parse" {
        nativeBuildInputs = [ pkgs.prometheus.cli ];
      } ''
        promtool check rules ${lib.concatMapStringsSep " " toString ruleFiles}
        touch $out
      '';

      # ── Every OnFailure= notifier points at a unit that exists ──────────
      # Derived from the EVALUATED hwc-server config, so it needs no second
      # copy of the monitored list. A name that resolves to no ExecStart is a
      # stub unit: it reads as coverage and delivers nothing (seven such dead
      # entries were found by hand on 2026-08-26).
      alert-onfailure-units = let
        server = self.nixosConfigurations."hwc-server".config;
        onFailureOf = svc:
          let v = (svc.unitConfig or {}).OnFailure or null;
          in if v == null then ""
             else if builtins.isList v then lib.concatStringsSep " " v
             else toString v;
        monitored = lib.filter
          (n: lib.hasInfix "hwc-service-failure-notifier@" (onFailureOf server.systemd.services.${n}))
          (builtins.attrNames server.systemd.services);
        unitText = n:
          let t = (server.systemd.units."${n}.service" or {}).text or null;
          in if t == null then "" else t;
        dead = lib.filter (n: !(lib.hasInfix "ExecStart=" (unitText n))) monitored;
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
      # (read off the rendered unit files of the evaluated hwc-server config),
      # not against the srgPath list, so this cannot pass on a package that is
      # named but never reaches the unit.
      sr-gauntlet-flock = let
        server = self.nixosConfigurations."hwc-server".config;
        units = [ "sr-gauntlet.service" "sr-gauntlet-runnow.service" ];
        unitFile = n: pkgs.writeText "check-${n}" server.systemd.units.${n}.text;
      in
      assert lib.assertMsg server.hwc.automation.srGauntlet.enable
        "sr-gauntlet-flock: srGauntlet is disabled on hwc-server — this check has no subject and would pass empty";
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
        "rg -i '\\b(laptop|xps|kids|firestick|hwc-server)\\b' profiles/ --glob '!README.md'"
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
