{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.apps.n8n;
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
    home.packages = with pkgs; [
      n8n
    ];

    home.sessionVariables = {
      N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS = "true";
      DB_SQLITE_POOL_SIZE = "5";
      N8N_RUNNERS_ENABLED = "true";
      N8N_BLOCK_ENV_ACCESS_IN_NODE = "false";
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
}
