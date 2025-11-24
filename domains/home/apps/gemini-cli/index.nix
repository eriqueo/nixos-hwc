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

    # Set environment variable for Gemini API key if secret is configured
    home.sessionVariables = lib.mkIf hasGeminiSecret {
      GEMINI_API_KEY = "\${cat ${osConfig.age.secrets.gemini-api-key.path} 2>/dev/null || echo}";
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
