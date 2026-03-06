# domains/home/apps/gemini-cli/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.gemini-cli;

  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};
  hasGeminiSecret = (osCfg ? age) && (osCfg.age.secrets ? gemini-api-key);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.gemini-cli = {
    enable = lib.mkEnableOption "Gemini CLI";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = lib.optionals (pkgs ? gemini-cli) [ pkgs.gemini-cli ];

    programs.zsh.initContent = lib.mkIf hasGeminiSecret (lib.mkAfter ''
      if [ -f "${osCfg.age.secrets.gemini-api-key.path}" ]; then
        source "${osCfg.age.secrets.gemini-api-key.path}"
      fi
    '');

    programs.bash.initExtra = lib.mkIf hasGeminiSecret ''
      if [ -f "${osCfg.age.secrets.gemini-api-key.path}" ]; then
        source "${osCfg.age.secrets.gemini-api-key.path}"
      fi
    '';
  };
}
