{ ... }:
{
  imports = [
    ../modules/services/business-api.nix
    ../modules/services/databases.nix
  ];
  
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
