# domains/home/core/development/index.nix
#
# Development environment — languages, editors, container tools
#
# NAMESPACE: hwc.home.core.development.*
# USED BY: profiles/session.nix, machines/home/config.nix
# USAGE: hwc.home.core.development.enable = true;

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.core.development;
  t = lib.types;
  # Law 1 standalone fallback; NixOS placement is owned by hwc.paths.
  goPaths = lib.attrByPath [ "hwc" "paths" "user" "go" ] {
    workspace = "${config.xdg.dataHome}/go";
    moduleCache = "${config.xdg.cacheHome}/go/mod";
    buildCache = "${config.xdg.cacheHome}/go-build";
    bin = "${config.home.homeDirectory}/.local/bin";
  } osConfig;
  goEnvironment = {
    GOPATH = goPaths.workspace;
    GOMODCACHE = goPaths.moduleCache;
    GOCACHE = goPaths.buildCache;
    GOBIN = goPaths.bin;
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.core.development = {
    enable = lib.mkEnableOption "Development tools and environment";

    editors = {
      neovim = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Neovim with configuration";
      };
      micro = lib.mkOption {
        type = t.bool;
        default = true;
        description = "Enable Micro editor";
      };
    };

    languages = {
      nix = lib.mkOption { type = t.bool; default = true; description = "Enable Nix development tools"; };
      python = lib.mkOption { type = t.bool; default = true; description = "Enable Python development tools"; };
      javascript = lib.mkOption { type = t.bool; default = false; description = "Enable JavaScript/Node.js development tools"; };
      rust = lib.mkOption { type = t.bool; default = false; description = "Enable Rust development tools"; };
    };

    containers = lib.mkOption { type = t.bool; default = true; description = "Enable container development tools"; };
    rootlessImagePrune.enable = lib.mkEnableOption "daily expiry of untagged rootless build images older than 12 hours";
    directoryStructure = lib.mkOption { type = t.bool; default = true; description = "Create development directory structure"; };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {

    # Go also reads this file in existing shells and GUI-launched builds that
    # have not sourced the new session variables. Nix owns these defaults.
    xdg.configFile."go/env".text = lib.generators.toKeyValue {} goEnvironment;

    # REPLACEABLE: caches contain downloaded/compiled dependencies, never
    # user source or installed binaries. go clean removes whole caches rather
    # than expiring individual files inside an otherwise present module.
    systemd.user.services.go-cache-clean = {
      Unit.Description = "Clear replaceable Go dependency and build caches";
      Service = {
        Type = "oneshot";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}")
          (goEnvironment // { GOTOOLCHAIN = "local"; });
        # Skip an active compiler; the next monthly run can try again.
        ExecCondition = pkgs.writeShellScript "go-cache-idle" ''
          ! ${pkgs.procps}/bin/pgrep -u "$(${pkgs.coreutils}/bin/id -u)" -x 'go|compile|link'
        '';
        ExecStart = "${pkgs.go}/bin/go clean -modcache -cache";
        TimeoutStartSec = "5min";
        Nice = 19;
      };
    };
    systemd.user.timers.go-cache-clean = {
      Unit.Description = "Monthly retention for replaceable Go caches";
      Timer = { OnCalendar = "monthly"; RandomizedDelaySec = "15min"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };

    # REPLACEABLE build cache. Podman preserves named images and images used
    # by any container (including stopped containers); never prune volumes.
    systemd.user.services.podman-image-prune = lib.mkIf cfg.rootlessImagePrune.enable {
      Unit = {
        Description = "Expire superseded rootless build images after a 12-hour grace period";
        ConditionPathIsDirectory = "%h/.local/share/containers/storage";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.podman}/bin/podman image prune --force --filter until=12h";
        TimeoutStartSec = "10min";
        Nice = 10;
      };
    };
    systemd.user.timers.podman-image-prune = lib.mkIf cfg.rootlessImagePrune.enable {
      Unit.Description = "Daily rootless build-cache retention";
      Timer = { OnCalendar = "daily"; RandomizedDelaySec = "15min"; Persistent = true; };
      Install.WantedBy = [ "timers.target" ];
    };

    home.packages = with pkgs; [
      git-lfs
      gh
      # doctl: see domains/home/apps/doctl (agenix-authenticated wrapper).
      wireguard-tools
      bun            # runtime for claude-code's Discord channel MCP server (.mcp.json: `command: "bun"`)

    ] ++ lib.optionals cfg.editors.micro [
      micro

    ] ++ lib.optionals cfg.languages.nix [
      nil
      nixfmt
      statix
      deadnix
      alejandra

    ] ++ lib.optionals cfg.languages.python [
      pyright
    ] ++ lib.optionals (cfg.languages.python && !config.hwc.home.apps.analysis.enable) [
      (python3.withPackages (ps: with ps; [
        pip virtualenv
        requests beautifulsoup4 lxml icalendar pytz tzdata
      ]))

    ] ++ lib.optionals cfg.languages.javascript [
      nodejs
      yarn
      typescript
      typescript-language-server

    ] ++ lib.optionals cfg.languages.rust [
      rustc
      cargo
      rust-analyzer

    ] ++ lib.optionals cfg.containers [
      docker-compose
      kubernetes-helm
      kubectl
    ];

    # Bridge editors.neovim to the nvim app domain
    hwc.home.apps.nvim.enable = lib.mkIf cfg.editors.neovim true;

    home.sessionVariables = {
      EDITOR = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      VISUAL = lib.mkForce (if cfg.editors.neovim then "nvim" else "micro");
      PROJECTS = config.xdg.userDirs.extraConfig.PROJECTS;
      SCRIPTS = "$HOME/.nixos/workspace";
      WORKSPACE = "$HOME/.nixos/workspace";
    } // goEnvironment // lib.optionalAttrs cfg.languages.python {
      PYTHONDONTWRITEBYTECODE = "1";
      PYTHONUNBUFFERED = "1";
      PIP_USER = "1";

    } // lib.optionalAttrs cfg.languages.javascript {
      NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    };

    home.sessionPath = [
      "$HOME/bin"
      goPaths.bin
    ] ++ lib.optionals cfg.languages.javascript [
      "$HOME/.npm-global/bin"
    ];
  };
}
