# domains/business/options.nix
#
# Business Domain - Business services and APIs
#
# NAMESPACE: hwc.business.*
#
# DEPENDENCIES:
#   - hwc.paths (storage paths)
#   - hwc.data.databases.postgresql (database backend)

{ lib, config, ... }:

let
  paths = config.hwc.paths or {};
in
{
  options.hwc.business = {
    enable = lib.mkEnableOption "Business services domain";

    #==========================================================================
    # DATA STORAGE
    #==========================================================================
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = paths.business.root or "/opt/business";
      description = "Root directory for business data";
    };

    #==========================================================================
    # RECEIPTS OCR SERVICE
    #==========================================================================
    receiptsOcr = {
      enable = lib.mkEnableOption "Receipts OCR service for processing receipt images";

      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Host to bind the API server to";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 8001;
        description = "Port for the receipts OCR API";
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "eric";
        description = "User to run the service as";
      };

      databaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "postgresql://business_user@localhost:5432/heartwood_business";
        description = "PostgreSQL connection string";
      };

      ollama = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable LLM normalization with Ollama";
        };

        url = lib.mkOption {
          type = lib.types.str;
          default = "http://localhost:11434";
          description = "Ollama API URL";
        };

        model = lib.mkOption {
          type = lib.types.str;
          default = "llama3.2";
          description = "Ollama model to use for normalization";
        };
      };

      storageRoot = lib.mkOption {
        type = lib.types.str;
        default = "${paths.hot.root or "/mnt/hot"}/receipts";
        description = "Root directory for receipt storage";
      };

      confidenceThreshold = lib.mkOption {
        type = lib.types.float;
        default = 0.7;
        description = "OCR confidence threshold for auto-review";
      };

      autoStart = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to auto-start the service";
      };
    };

    #==========================================================================
    # BUSINESS API
    #==========================================================================
    api = {
      enable = lib.mkEnableOption "Business API services";

      development = {
        enable = lib.mkEnableOption "Development mode for business API";
      };

      service = {
        enable = lib.mkEnableOption "Business API systemd service";

        host = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Host to bind the API to";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8000;
          description = "Port for the business API";
        };

        workingDirectory = lib.mkOption {
          type = lib.types.str;
          default = "/opt/business/api";
          description = "Working directory for the API service";
        };

        autoStart = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether to auto-start the API service";
        };
      };

      packages = {
        enable = lib.mkEnableOption "Install business API Python packages";
      };
    };

    #==========================================================================
    # FUTURE SERVICES (PLACEHOLDERS)
    #==========================================================================
    invoicing = {
      enable = lib.mkEnableOption "Invoicing service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3001;
        description = "Invoicing service port";
      };

      database = lib.mkOption {
        type = lib.types.str;
        default = "postgresql://localhost/invoicing";
        description = "Database connection string";
      };
    };

    crm = {
      enable = lib.mkEnableOption "CRM service";

      port = lib.mkOption {
        type = lib.types.port;
        default = 3002;
        description = "CRM service port";
      };
    };
  };
}
