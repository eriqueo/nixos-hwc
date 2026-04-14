# domains/home/apps/aider/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.aider;

  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  openaiSecretPath = lib.attrByPath [ "age" "secrets" "openai-api-key" "path" ] null osCfg;
  anthropicSecretPath = lib.attrByPath [ "age" "secrets" "anthropic-api-key" "path" ] null osCfg;

  aiderPkg =
    if cfg.package != null then cfg.package
    else if lib.hasAttrByPath [ "aider-chat-full" ] pkgs then pkgs.aider-chat-full
    else if lib.hasAttrByPath [ "aider-chat" ] pkgs then pkgs.aider-chat
    else if lib.hasAttrByPath [ "aider" ] pkgs then pkgs.aider
    else null;

  aliasList =
    [
      "cloud:${cfg.cloudModel}"
      "local:${cfg.localModel}"
    ]
    ++ (lib.mapAttrsToList (name: model: "${name}:${model}") cfg.extraAliases);

  secretInit = lib.concatStringsSep "\n" (
    lib.filter (line: line != "") [
      (lib.optionalString (openaiSecretPath != null) ''
        if [ -f "${openaiSecretPath}" ]; then
          if grep '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "${openaiSecretPath}"; then
            source "${openaiSecretPath}"
          else
            export OPENAI_API_KEY="$(tr -d '\r\n' < "${openaiSecretPath}")"
          fi
        fi
      '')
      (lib.optionalString (anthropicSecretPath != null) ''
        if [ -f "${anthropicSecretPath}" ]; then
          if grep '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "${anthropicSecretPath}"; then
            source "${anthropicSecretPath}"
          else
            export ANTHROPIC_API_KEY="$(tr -d '\r\n' < "${anthropicSecretPath}")"
          fi
        fi
      '')
    ]
  );

  shellInit = lib.concatStringsSep "\n" (
    [
      "export OLLAMA_API_BASE=\"${cfg.ollamaApiBase}\""
    ]
    ++ lib.optionals (secretInit != "") [
      secretInit
    ]
  );

  aiderConfig = lib.generators.toYAML {} {
    model = cfg.cloudModel;
    weak-model = cfg.localModel;
    alias = aliasList;
    check-update = false;
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.aider = {
    enable = lib.mkEnableOption "aider AI pair-programming CLI";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Aider package to use. If null, auto-detect from nixpkgs.";
    };

    cloudModel = lib.mkOption {
      type = lib.types.str;
      default = "openai/gpt-4o-mini";
      description = "Default cloud model for aider.";
    };

    localModel = lib.mkOption {
      type = lib.types.str;
      default = "ollama/llama3.2:3b";
      description = "Default local model for aider via Ollama.";
    };

    ollamaApiBase = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434";
      description = "Ollama API base URL used by aider for local models.";
    };

    extraAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Additional aider model aliases in name -> model format.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = lib.optionals (aiderPkg != null) [ aiderPkg ];
    home.sessionVariables.OLLAMA_API_BASE = cfg.ollamaApiBase;

    home.file.".aider.conf.yml".text = aiderConfig;

    programs.zsh.initContent = lib.mkAfter ''
      # Aider local model endpoint + optional API key secrets.
      ${shellInit}
    '';

    programs.bash.initExtra = ''
      # Aider local model endpoint + optional API key secrets.
      ${shellInit}
    '';

    #======================================================================
    # VALIDATION
    #======================================================================
    assertions = [
      {
        assertion = aiderPkg != null;
        message = "aider package must be available (set hwc.home.apps.aider.package if needed)";
      }
    ];
  };
}
