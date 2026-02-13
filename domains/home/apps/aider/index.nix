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
          if grep -Eq '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "${openaiSecretPath}"; then
            source "${openaiSecretPath}"
          else
            export OPENAI_API_KEY="$(tr -d '\r\n' < "${openaiSecretPath}")"
          fi
        fi
      '')
      (lib.optionalString (anthropicSecretPath != null) ''
        if [ -f "${anthropicSecretPath}" ]; then
          if grep -Eq '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "${anthropicSecretPath}"; then
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
  imports = [ ./options.nix ];

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
