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

  aliasYaml = lib.concatMapStrings (entry: "  - ${builtins.toJSON entry}\n") aliasList;

  secretInit = lib.concatStringsSep "\n" (
    lib.filter (line: line != "") [
      (lib.optionalString (openaiSecretPath != null) ''
        if [ -f "${openaiSecretPath}" ]; then
          source "${openaiSecretPath}"
        fi
      '')
      (lib.optionalString (anthropicSecretPath != null) ''
        if [ -f "${anthropicSecretPath}" ]; then
          source "${anthropicSecretPath}"
        fi
      '')
    ]
  );

  aiderConfig = ''
    # Managed by Home Manager (domains/home/apps/aider)
    # Cloud auth: set OPENAI_API_KEY and/or ANTHROPIC_API_KEY in your environment.

    model: ${cfg.cloudModel}
    weak-model: ${cfg.localModel}
    ollama-api-base: ${cfg.ollamaApiBase}
    alias:
${aliasYaml}    check-update: false
  '';
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

    home.file.".aider.conf.yml".text = aiderConfig;

    programs.zsh.initContent = lib.mkIf (secretInit != "") (lib.mkAfter ''
      # Source optional aider API key secrets from agenix.
      ${secretInit}
    '');

    programs.bash.initExtra = lib.mkIf (secretInit != "") ''
      # Source optional aider API key secrets from agenix.
      ${secretInit}
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
