# domains/ai/tools/index.nix
#
# AI CLI tools for charter search, ollama interaction, and code generation

{ config, lib, pkgs, aiProfile ? null, aiProfileName ? "laptop", ... }:

let
  cfg = config.hwc.ai.tools;

  # Create Charter search tool
  charterSearchTool = pkgs.writeScriptBin "charter-search" (builtins.readFile ./parts/charter-search.sh);

  # Create Ollama wrapper with profile-aware configuration
  ollamaWrapperTool = pkgs.writeScriptBin "ollama-wrapper" (''
    #!${pkgs.bash}/bin/bash
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.jq pkgs.gnugrep pkgs.gawk pkgs.libnotify pkgs.lm_sensors charterSearchTool ]}:$PATH"
    export CHARTER_PATH="${cfg.charter.charterPath}"
    export LOG_DIR="${cfg.logging.logDir}"
    ${lib.optionalString (aiProfile != null) ''
    export THERMAL_WARNING="${toString aiProfile.thermal.warningTemp}"
    export THERMAL_CRITICAL="${toString aiProfile.thermal.criticalTemp}"
    export PROFILE="${aiProfileName}"
    ''}
    export VERBOSE="${if cfg.logging.enable then "true" else "false"}"

  '' + builtins.readFile ./parts/ollama-wrapper.sh);

  # Quick wrapper for common tasks
  aiDocTool = pkgs.writeScriptBin "ai-doc" ''
    #!${pkgs.bash}/bin/bash
    # Quick documentation generator using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper doc medium "$@"
  '';

  aiCommitTool = pkgs.writeScriptBin "ai-commit" ''
    #!${pkgs.bash}/bin/bash
    # Quick commit documentation using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper commit small "$@"
  '';

  aiLintTool = pkgs.writeScriptBin "ai-lint" ''
    #!${pkgs.bash}/bin/bash
    # Charter compliance checker using ollama-wrapper
    ${ollamaWrapperTool}/bin/ollama-wrapper lint small "$@"
  '';

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.tools = {
    enable = lib.mkEnableOption "AI CLI tools";

    charter = {
      charterPath = lib.mkOption {
        type = lib.types.str;
        default = "${config.hwc.paths.nixos}/CHARTER.md";
        description = "Path to CHARTER.md file";
      };
    };

    logging = {
      enable = lib.mkEnableOption "AI tool logging";

      logDir = lib.mkOption {
        type = lib.types.str;
        default = "${config.hwc.paths.user.home}/.local/share/ai-logs";
        description = "Directory for AI tool logs";
      };
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # Install AI CLI tools
    environment.systemPackages = [
      charterSearchTool
      ollamaWrapperTool
      aiDocTool
      aiCommitTool
      aiLintTool
    ];

    # Create log directory if logging enabled
    systemd.tmpfiles.rules = lib.optionals cfg.logging.enable [
      "d ${cfg.logging.logDir} 0755 eric users -"
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    # NOTE: Charter path validation done at runtime by tools, not build-time
    # builtins.pathExists not available in restricted evaluation
  };
}
