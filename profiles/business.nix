{ ... }:
{
  #==========================================================================
  # BASE SYSTEM - Critical for machine functionality
  #==========================================================================
  imports = [
    ../domains/server/business-api.nix
    ../domains/server/databases.nix
  ];

  #==========================================================================
  # OPTIONAL FEATURES - Sensible defaults, override per machine
  #==========================================================================
  hwc.services.businessApi = {
    enable = true;
    apis = {
      invoicing.enable = true;
      crm.enable = true;
      analytics.enable = true;
    };
  };
  
  hwc.services.databases = {
    postgresql = {
      enable = true;
      databases = [ "invoicing" "crm" "analytics" ];
      backup.enable = true;
    };
    redis.enable = true;
  };
}
