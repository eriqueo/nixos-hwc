# HWC Charter Module/domains/services/business-api.nix
#
# BUSINESS API - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.business-api.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/business-api.nix
#
# USAGE:
#   hwc.services.business-api.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.businessApi;
in {
  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.apis.invoicing.enable {
      virtualisation.oci-containers.containers.invoicing-api = {
        image = "business/invoicing:latest";
        ports = [ "${toString cfg.apis.invoicing.port}:3000" ];
        volumes = [
          "${cfg.dataDir}/invoicing:/data"
        ];
        environment = {
          DATABASE_URL = cfg.apis.invoicing.database;
          NODE_ENV = "production";
        };
      };
    })

    (lib.mkIf cfg.apis.crm.enable {
      virtualisation.oci-containers.containers.crm-api = {
        image = "business/crm:latest";
        ports = [ "${toString cfg.apis.crm.port}:3000" ];
        volumes = [
          "${cfg.dataDir}/crm:/data"
        ];
      };
    })

    {
      systemd.tmpfiles.rules = [
        "d ${cfg.dataDir} 0750 root root -"
        "d ${cfg.dataDir}/invoicing 0750 root root -"
        "d ${cfg.dataDir}/crm 0750 root root -"
      ];

      networking.firewall.allowedTCPPorts = lib.flatten [
        (lib.optional cfg.apis.invoicing.enable cfg.apis.invoicing.port)
        (lib.optional cfg.apis.crm.enable cfg.apis.crm.port)
      ];
    }
  ]);
}
