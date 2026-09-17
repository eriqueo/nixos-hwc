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
        "dx2-evidence"
        "herdr"
        "project-closeout"
        "project-director"
      ];
      description = "Shared skills exposed to Codex from sharedSkillSource; the source files stay single-copy.";
    };

    # The engineering workflow skills live at ~/.agents/skills, the documented
    # Codex user-skill root. claude-config's codex-workflow-start.sh names that
    # path and principles-lint.sh checks all four there. It was hand-built on
    # hwc-laptop and absent on hwc-server (found 2026-09-17), so Codex threads
    # served from the server had no workflow skills at all.
    workflowSkills = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "stepwise-refinement"
        "chestertons-fence"
        "premortem"
        "datax-sr-triage"
      ];
      description = "Shared skills exposed at ~/.agents/skills (Codex user-skill root) from sharedSkillSource; the set principles-lint.sh verifies.";
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
    home.file = lib.listToAttrs (
      (map (skill:
        lib.nameValuePair ".codex/skills/${skill}" {
          source = config.lib.file.mkOutOfStoreSymlink "${cfg.sharedSkillSource}/${skill}";
        }
      ) cfg.sharedSkills)
      ++ (map (skill:
        lib.nameValuePair ".agents/skills/${skill}" {
          source = config.lib.file.mkOutOfStoreSymlink "${cfg.sharedSkillSource}/${skill}";
        }
      ) cfg.workflowSkills)
    );

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
