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

    # Pinned nixpkgs solely to source tailscale 1.98.2 via overlay.
    # 1.98.0 in the main nixpkgs has a MagicDNS regression on link-change
    # (drops the per-tailnet self-route on suspend/resume, leaving only the
    # global ts.net split-DNS rule -> NXDOMAIN for *.ocelot-wahoo.ts.net).
    # Fixed upstream in 1.98.2. Scoped to one package via overlay to avoid
    # a wide nixpkgs jump (8-day delta OOMed the laptop on rebuild).
    # REMOVE WHEN: locked `nixpkgs` has tailscale >= 1.98.2 (check at each
    # `nix flake update`: nix eval .#nixosConfigurations.hwc-laptop.pkgs.tailscale.version)
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/64c08a7ca051951c8eae34e3e3cb1e202fe36786";

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

    # Overlay: replace tailscale with the build from nixpkgs-tailscale.
    # See `nixpkgs-tailscale` input comment for the rationale.
    tailscaleOverlay = final: prev: {
      tailscale = inputs.nixpkgs-tailscale.legacyPackages.${prev.stdenv.hostPlatform.system}.tailscale;
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

    # Pkgs helper with optional overlays (server uses this)
    # CUDA enabled - using cache.nixos-cuda.org for pre-built binaries
    mkPkgsWithOverlays = system: nixpkgsInput: extraOverlays:
      import nixpkgsInput {
        inherit system;
        overlays = [ silenceDeprecatedAliases claudeCodeOverlay cloudflaredOverlay ] ++ extraOverlays;
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

    # Laptop-only pkgs: same as `pkgs` plus the tailscale 1.98.2 overlay.
    # Server/xps stay untouched (different channel, not affected by the bug).
    pkgs-laptop = pkgs.extend tailscaleOverlay;

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
        nixosPkgs = pkgs-laptop;       # unstable + tailscale 1.98.2 overlay
        hmPkgs    = pkgs-laptop;
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
      graph_dir = "${self}/workspace/nixos/graph"
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
