# domains/home/apps/rea/index.nix
#
# REA (Reverse Engineer Anything): the `rea` CLI for the user, and its bundled
# `reverse-engineer-anything` skill added to the agent-harness one skill set so
# Claude, Codex and Pi all get the same investigation workflow. The MCP
# registration that lets Claude Code call REA's tools is the system lane's job
# (sys.nix): ~/.mcp.json is generated there.
#
# Upstream's `npx rea-agents setup` edits agent configs and installs the skill
# by hand; here both are Nix-owned, so `rea setup`/`rea update` are not used.
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.rea;
  reaPkg = if cfg.package != null then cfg.package else pkgs.callPackage ./parts/package.nix { };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.rea = {
    enable = lib.mkEnableOption "REA (Reverse Engineer Anything) CLI and agent skill";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "REA package. If null, the pinned parts/package.nix build (nixpkgs Ghidra, Apktool, Binwalk and Unblob wired in).";
    };

    skill.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Add the bundled `reverse-engineer-anything` skill to the agent-harness
        skill set (`hwc.home.apps.agent-harness.extraSkills`), the one tree
        every runtime loads.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ reaPkg ];

    hwc.home.apps.agent-harness.extraSkills = lib.mkIf cfg.skill.enable {
      reverse-engineer-anything = "${reaPkg}/${reaPkg.passthru.skillDir or "lib/node_modules/rea-agents/skills/reverse-engineer-anything"}";
    };

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = !cfg.skill.enable || config.hwc.home.apps.agent-harness.enable;
        message = "hwc.home.apps.rea.skill.enable needs hwc.home.apps.agent-harness.enable: the skill set is the harness's.";
      }
    ];
  };
}
