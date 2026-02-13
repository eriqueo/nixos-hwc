{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.home.apps.gemini-cli;

  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  # Check for gemini-api-key secret (only on NixOS hosts with age secrets)
  hasGeminiSecret = (osCfg ? age) && (osCfg.age.secrets ? gemini-api-key);
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
    # gemini-cli not available in nixpkgs 24.05, only in unstable
    home.packages = lib.optionals (pkgs ? gemini-cli) [
      pkgs.gemini-cli
    ];

    # Load Gemini API key from agenix secret in shell initialization
    programs.zsh.initContent = lib.mkIf hasGeminiSecret (lib.mkAfter ''
      # Source Gemini API key from agenix secret
      if [ -f "${osCfg.age.secrets.gemini-api-key.path}" ]; then
        source "${osCfg.age.secrets.gemini-api-key.path}"
      fi
    '');

    programs.bash.initExtra = lib.mkIf hasGeminiSecret ''
      # Source Gemini API key from agenix secret
      if [ -f "${osCfg.age.secrets.gemini-api-key.path}" ]; then
        source "${osCfg.age.secrets.gemini-api-key.path}"
      fi
    '';
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
