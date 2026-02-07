# domains/server/business/options.nix
#
# Consolidated options for server business subdomain
# Charter-compliant: ALL business API options defined here

{ lib, config, ... }:

let
  feature = config.hwc.server.native.business;
  cfg = config.hwc.server.businessApi;
  paths = config.hwc.paths;
in
{
  options.hwc.server.native.business = {
    enable = lib.mkEnableOption "business services feature flag";
  };

  options.hwc.server.businessApi = {
    enable = lib.mkEnableOption "Business API services";

    #==========================================================================
    # API SERVICES
    #==========================================================================
    apis = {
      invoicing = {
        enable = lib.mkEnableOption "Invoicing API";

        port = lib.mkOption {
          type = lib.types.port;
          default = 3001;
          description = "Invoicing API port";
        };

        database = lib.mkOption {
          type = lib.types.str;
          default = "postgresql://localhost/invoicing";
          description = "Database connection string";
        };
      };

      crm = {
        enable = lib.mkEnableOption "CRM API";

        port = lib.mkOption {
          type = lib.types.port;
          default = 3002;
          description = "CRM API port";
        };
      };

      analytics = {
        enable = lib.mkEnableOption "Analytics API";

        port = lib.mkOption {
          type = lib.types.port;
          default = 3003;
          description = "Analytics API port";
        };
      };
    };

    #==========================================================================
    # DATA STORAGE
    #==========================================================================
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/business";
      description = "Business API data directory";
    };
  };
}
