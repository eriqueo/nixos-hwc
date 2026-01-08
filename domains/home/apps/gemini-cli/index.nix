{ config, lib, pkgs, osConfig, ... }:

let
  cfg = config.hwc.home.apps.geminiCli;
  hasGeminiSecret = osConfig.age.secrets ? gemini-api-key;
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
    home.packages = [
      pkgs.gemini-cli
    ];

    # Load Gemini API key from agenix secret in shell initialization
    programs.zsh.initContent = lib.mkIf hasGeminiSecret ''
      # Source Gemini API key from agenix secret
      if [ -f "${osConfig.age.secrets.gemini-api-key.path}" ]; then
        source "${osConfig.age.secrets.gemini-api-key.path}"
      fi
    '';

    programs.bash.initExtra = lib.mkIf hasGeminiSecret ''
      # Source Gemini API key from agenix secret
      if [ -f "${osConfig.age.secrets.gemini-api-key.path}" ]; then
        source "${osConfig.age.secrets.gemini-api-key.path}"
      fi
    '';
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
