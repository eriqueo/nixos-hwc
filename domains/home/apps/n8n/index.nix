# domains/home/apps/n8n/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.n8n;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.n8n = {
    enable = lib.mkEnableOption "n8n workflow automation";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.n8n ];

    home.sessionVariables = {
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
      DB_SQLITE_POOL_SIZE = "5";
      N8N_RUNNERS_ENABLED = "true";
      N8N_BLOCK_ENV_ACCESS_IN_NODE = "false";
    };
  };
}
