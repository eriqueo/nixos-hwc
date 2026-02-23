# domains/business/index.nix
#
# Business Domain - Business services and APIs
#
# NAMESPACE: hwc.business.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths)
#   - hwc.server.databases.postgresql (database backend)
#   - Optional: hwc.ai.ollama (for OCR LLM normalization)
#
# USED BY:
#   - profiles/business.nix

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.business;
  enabled = cfg.enable;

  # Import implementation modules
  receiptsOcrImpl = import ./parts/receipts-ocr.nix { inherit config lib pkgs; };
  apiImpl = import ./parts/api.nix { inherit config lib pkgs; };

  # Check if PostgreSQL is available
  postgresqlAvailable =
    (config.hwc.server.databases.postgresql.enable or false) ||
    (config.services.postgresql.enable or false);

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf enabled {
    # =======================================================================
    # SYSTEM PACKAGES
    # =======================================================================
    environment.systemPackages = lib.flatten [
      (lib.optionals cfg.receiptsOcr.enable receiptsOcrImpl.packages)
      (lib.optionals cfg.api.enable apiImpl.packages)
    ];

    # =======================================================================
    # TMPFILES (Directory Structure)
    # =======================================================================
    systemd.tmpfiles.rules = lib.flatten [
      # Base business directory
      "d ${cfg.dataDir} 0750 eric users -"
      "d /var/log/hwc 0755 root root -"

      # Receipts OCR directories
      (lib.optionals cfg.receiptsOcr.enable receiptsOcrImpl.tmpfilesRules)

      # API directories
      (lib.optionals cfg.api.enable apiImpl.tmpfilesRules)

      # Future service directories
      (lib.optionals cfg.invoicing.enable [
        "d ${cfg.dataDir}/invoicing 0750 eric users -"
      ])
      (lib.optionals cfg.crm.enable [
        "d ${cfg.dataDir}/crm 0750 eric users -"
      ])
    ];

    # =======================================================================
    # SERVICES
    # =======================================================================
    systemd.services = lib.mkMerge [
      # Receipts OCR services
      (lib.mkIf cfg.receiptsOcr.enable {
        receipts-ocr-setup = receiptsOcrImpl.setupService;
        receipts-ocr = receiptsOcrImpl.mainService;
        receipts-ocr-db-init = receiptsOcrImpl.dbInitService;
      })

      # Business API service
      (lib.mkIf (cfg.api.enable && cfg.api.service.enable) {
        business-api = apiImpl.mainService;
      })
    ];

    # =======================================================================
    # LOG ROTATION
    # =======================================================================
    services.logrotate.settings = lib.mkMerge [
      (lib.mkIf cfg.receiptsOcr.enable {
        receipts-ocr = {
          files = [ "/var/log/hwc/receipts-ocr*.log" ];
          frequency = "weekly";
          rotate = 4;
          compress = true;
          delaycompress = true;
          missingok = true;
          notifempty = true;
          create = "0644 root root";
        };
      })

      (lib.mkIf cfg.api.enable {
        business-api = {
          files = [ "/var/log/hwc/business-api*.log" ];
          frequency = "weekly";
          rotate = 4;
          compress = true;
          missingok = true;
          notifempty = true;
          create = "0644 root root";
        };
      })
    ];

    # =======================================================================
    # FIREWALL
    # =======================================================================
    networking.firewall.interfaces."tailscale0" = lib.mkIf (config.hwc.system.networking.tailscale.enable or false) {
      allowedTCPPorts = lib.flatten [
        (lib.optionals cfg.receiptsOcr.enable receiptsOcrImpl.firewallPorts)
        (lib.optionals (cfg.api.enable && cfg.api.service.enable) apiImpl.firewallPorts)
        (lib.optional cfg.invoicing.enable cfg.invoicing.port)
        (lib.optional cfg.crm.enable cfg.crm.port)
      ];
    };

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.receiptsOcr.enable || postgresqlAvailable;
        message = ''
          hwc.business.receiptsOcr requires PostgreSQL to be enabled.
          Enable with: hwc.server.databases.postgresql.enable = true
          Or: services.postgresql.enable = true
        '';
      }
      {
        assertion = !cfg.receiptsOcr.enable || !cfg.receiptsOcr.ollama.enable ||
          (config.services.ollama.enable or false) ||
          (config.hwc.ai.ollama.enable or false);
        message = ''
          hwc.business.receiptsOcr with Ollama requires Ollama to be enabled.
          Enable with: hwc.ai.ollama.enable = true
          Or: services.ollama.enable = true
          Or: disable Ollama with: hwc.business.receiptsOcr.ollama.enable = false
        '';
      }
      {
        assertion = !cfg.invoicing.enable || !cfg.crm.enable ||
          cfg.invoicing.port != cfg.crm.port;
        message = "hwc.business.invoicing and crm cannot use the same port";
      }
      {
        assertion = !cfg.api.service.enable || cfg.api.enable;
        message = "hwc.business.api.service.enable requires hwc.business.api.enable = true";
      }
    ];

    # =======================================================================
    # WARNINGS
    # =======================================================================
    warnings = lib.flatten [
      (lib.optional (cfg.receiptsOcr.enable && !postgresqlAvailable) ''
        hwc.business.receiptsOcr is enabled but PostgreSQL is not.
        The service will fail to process receipts until PostgreSQL is configured.
      '')

      (lib.optional cfg.invoicing.enable ''
        hwc.business.invoicing is enabled but not yet implemented.
        This is a placeholder for future functionality.
      '')

      (lib.optional cfg.crm.enable ''
        hwc.business.crm is enabled but not yet implemented.
        This is a placeholder for future functionality.
      '')
    ];
  };
}
