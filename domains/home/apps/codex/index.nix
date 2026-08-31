# domains/home/apps/codex/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.codex;
  codexPkg = if cfg.package != null then cfg.package else (pkgs.codex or null);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.codex = {
    enable = lib.mkEnableOption "OpenAI Codex CLI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Codex package to use. If null, will use flake input.";
    };

    env = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional environment variables for Codex CLI";
    };

    sharedSkillSource = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.claude-config/skills";
      description = "Shared Agent Skills source tree used for selected Codex skill symlinks.";
    };

    sharedSkills = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "delegate"
        "herdr"
        "project-director"
      ];
      description = "Shared skills exposed to Codex from sharedSkillSource; the source files stay single-copy.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ codexPkg ];

    home.sessionVariables = cfg.env;

    # Create config directory
    xdg.configFile."codex/.keep".text = "";

    # Claude already consumes the shared skill tree directly. Codex has its
    # own skill root, so expose only the cross-harness orchestration skills as
    # out-of-store symlinks instead of copying a second source tree.
    home.file = lib.listToAttrs (map (skill:
      lib.nameValuePair ".codex/skills/${skill}" {
        source = config.lib.file.mkOutOfStoreSymlink "${cfg.sharedSkillSource}/${skill}";
      }
    ) cfg.sharedSkills);

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = codexPkg != null;
        message = "codex package must be available";
      }
    ];
  };
}
