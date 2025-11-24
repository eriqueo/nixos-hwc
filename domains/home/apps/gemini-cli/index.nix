{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.geminiCli;
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

    # Set environment variable for Gemini API key
    home.sessionVariables = lib.mkIf (config.age.secrets ? gemini-api-key) {
      GEMINI_API_KEY = "\${cat ${config.age.secrets.gemini-api-key.path} 2>/dev/null || echo}";
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = lib.mkIf cfg.enable [
    {
      assertion = config.age.secrets ? gemini-api-key;
      message = "gemini-cli requires age.secrets.gemini-api-key to be configured in the secrets domain";
    }
  ];
}
