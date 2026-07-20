# domains/home/apps/claude-code/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.claude-code;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.claude-code = {
    enable = lib.mkEnableOption "Claude Code CLI (Nix package + Obsidian MCP cert)";

    # Shared, version-controlled skill/agent/command/CLAUDE.md/engineering-principles set. Lives in a
    # standalone git repo (NOT ~/.nixos — branch switches there would vaporize
    # the symlink targets mid-session). Symlinked live so edits are immediate
    # and identical across every host.
    #
    # Deliberately INDEPENDENT of `enable`: hwc-server runs claude from an
    # ad-hoc npm global and must NOT get the Nix package or the laptop-only
    # Obsidian cert var (the cert file does not exist there). It opts into the
    # shared config alone via shareConfig.enable.
    shareConfig = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = cfg.enable;
        description = "Symlink ~/.claude/{skills,agents,commands,CLAUDE.md,engineering-principles} from the shared claude-config git repo. Defaults to the package enable, but can be turned on standalone (e.g. hwc-server).";
      };
      repoPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.home.homeDirectory}/.claude-config";
        description = "Working-tree path of the shared claude-config git repo (mkOutOfStoreSymlink target).";
      };
      items = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "skills"
          "agents"
          "commands"
          "CLAUDE.md"
          "engineering-principles"
          # Individual files, not the hooks/ dir — ~/.claude/hooks also holds
          # host-local hooks (herdr-agent-state.sh) that must stay unmanaged.
          "hooks/principles-primer.sh"
          "hooks/principles-gate.sh"
        ];
        description = "Entries under repoPath to symlink into ~/.claude/ (nested paths symlink single files).";
      };
      autoPull = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Run a systemd --user timer that fast-forward-pulls the config repo so other hosts' commits arrive zero-touch.";
        };
        interval = lib.mkOption {
          type = lib.types.str;
          default = "15min";
          description = "systemd OnUnitActiveSec cadence for the auto-pull timer.";
        };
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    # Package + Obsidian MCP cert — laptop-class hosts only (cfg.enable).
    (lib.mkIf cfg.enable {
      home.packages = [ pkgs.claude-code ];

      # Trust the self-signed cert from the Obsidian Local REST API plugin
      # so Claude Code's HTTP MCP transport can connect without validation errors.
      # Cert source: https://127.0.0.1:27124/obsidian-local-rest-api.crt
      home.sessionVariables.NODE_EXTRA_CA_CERTS = "${config.home.homeDirectory}/.claude/certs/obsidian-local-rest-api.crt";
    })

    # Live symlinks from the shared config repo into ~/.claude/. Independent of
    # the package so headless hosts can share skills without the Nix binary.
    (lib.mkIf cfg.shareConfig.enable {
      home.file = lib.listToAttrs (map (item:
        lib.nameValuePair ".claude/${item}" {
          source = config.lib.file.mkOutOfStoreSymlink "${cfg.shareConfig.repoPath}/${item}";
        }) cfg.shareConfig.items);
    })

    # Optional zero-touch receive: fast-forward-pull the config repo on a timer.
    # Pull-only (never auto-commits/pushes) so a dirty working tree of in-progress
    # skill edits is never clobbered — a non-ff state just makes the unit no-op.
    (lib.mkIf (cfg.shareConfig.enable && cfg.shareConfig.autoPull.enable) {
      systemd.user.services.claude-config-pull = {
        Unit.Description = "Fast-forward-pull the shared claude-config repo";
        Service = {
          Type = "oneshot";
          # Fetch, then fast-forward ONLY when strictly behind. A diverged/ahead
          # or dirty tree is a clean no-op (exit 0) — matching the receive-only
          # intent — instead of `pull --ff-only`'s loud exit-128 every interval.
          ExecStart = pkgs.writeShellScript "claude-config-pull" ''
            set -eu
            ${pkgs.git}/bin/git -C ${cfg.shareConfig.repoPath} fetch --quiet
            ${pkgs.git}/bin/git -C ${cfg.shareConfig.repoPath} merge --ff-only '@{u}' \
              || echo "claude-config: non-ff (diverged/ahead/dirty) — skipping pull"
          '';
        };
      };
      systemd.user.timers.claude-config-pull = {
        Unit.Description = "Periodic pull of the shared claude-config repo";
        Timer = {
          OnBootSec = "2min";
          OnUnitActiveSec = cfg.shareConfig.autoPull.interval;
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })

    #========================================================================
    # VALIDATION
    #========================================================================
    {
      assertions = [
        {
          assertion = cfg.shareConfig.enable -> (cfg.shareConfig.items != [ ]);
          message = "hwc.home.apps.claude-code.shareConfig.items must list at least one entry when shareConfig is enabled.";
        }
        {
          assertion = cfg.shareConfig.autoPull.enable -> cfg.shareConfig.enable;
          message = "hwc.home.apps.claude-code.shareConfig.autoPull requires shareConfig.enable = true.";
        }
      ];
    }
  ];
}
