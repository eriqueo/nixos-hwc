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

  # Grebuild integration script
  grebuildDocsTool = pkgs.writeScript "grebuild-docs" (''
    #!${pkgs.bash}/bin/bash
    export PATH="${lib.makeBinPath [ pkgs.coreutils pkgs.curl pkgs.git pkgs.systemd pkgs.util-linux pkgs.libnotify pkgs.nettools ollamaWrapperTool ]}:$PATH"
    export NIXOS_DIR="${config.hwc.paths.nixos}"
    export OUTPUT_DIR="${config.hwc.paths.nixos}/docs/ai-generated"
    export OLLAMA_ENDPOINT="http://localhost:11434"
    export VERBOSE="false"
  '' + builtins.readFile ./parts/grebuild-docs.sh);

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

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

    # Post-rebuild AI documentation service (grebuild integration)
    systemd.services.post-rebuild-ai-docs = {
      description = "AI Tools - Post-rebuild documentation generator";
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${pkgs.bash}/bin/bash ${grebuildDocsTool}";
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    # NOTE: Charter path validation done at runtime by tools, not build-time
    # builtins.pathExists not available in restricted evaluation
  };
}
