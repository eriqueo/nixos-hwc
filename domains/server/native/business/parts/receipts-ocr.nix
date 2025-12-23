# HWC Charter Module/domains/server/business/parts/receipts-ocr.nix
#
# Receipts OCR Service
# Systemd service for processing receipt images with OCR and PostgreSQL storage
#
# DEPENDENCIES (Upstream):
#   - config.hwc.services.databases.postgresql (PostgreSQL database)
#   - config.hwc.paths.* (Storage paths)
#
# USED BY (Downstream):
#   - domains/server/business/api.nix
#
# USAGE:
#   hwc.services.business.receipts-ocr.enable = true;

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hwc.services.business.receipts-ocr;
  paths = config.hwc.paths;

  # Python environment with all dependencies
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    psycopg2
    pytesseract
    pdf2image
    opencv4
    pillow
    numpy
    httpx
    pydantic
    python-multipart
    python-dotenv
  ]);

  # Service working directory
  serviceDir = "${paths.business.root}/receipts-ocr";

  # Receipt OCR service script
  receiptOcrService = pkgs.writeScriptBin "receipt-ocr-service" ''
    #!${pkgs.bash}/bin/bash
    cd ${serviceDir}
    exec ${pythonEnv}/bin/python -m src.receipt_ocr_service serve \
      --host ${cfg.host} \
      --port ${toString cfg.port}
  '';

  # CLI wrapper script
  receiptOcrCli = pkgs.writeScriptBin "receipt-ocr" ''
    #!${pkgs.bash}/bin/bash
    cd ${serviceDir}
    exec ${pythonEnv}/bin/python -m src.receipt_ocr_service "$@"
  '';

in {

  ####################################################################
  # OPTIONS
  ####################################################################

  options.hwc.services.business.receipts-ocr = {
    enable = mkEnableOption "Receipts OCR service for processing receipt images";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "Host to bind the API server to";
    };

    port = mkOption {
      type = types.port;
      default = 8001;
      description = "Port for the receipts OCR API";
    };

    user = mkOption {
      type = types.str;
      default = "eric";
      description = "User to run the service as";
    };

    databaseUrl = mkOption {
      type = types.str;
      default = "postgresql://business_user@localhost:5432/heartwood_business";
      description = "PostgreSQL connection string";
    };

    ollamaEnabled = mkOption {
      type = types.bool;
      default = true;
      description = "Enable LLM normalization with Ollama";
    };

    ollamaUrl = mkOption {
      type = types.str;
      default = "http://localhost:11434";
      description = "Ollama API URL";
    };

    ollamaModel = mkOption {
      type = types.str;
      default = "llama3.2";
      description = "Ollama model to use for normalization";
    };

    storageRoot = mkOption {
      type = types.str;
      default = "${paths.hot.root}/receipts";
      description = "Root directory for receipt storage";
    };

    confidenceThreshold = mkOption {
      type = types.float;
      default = 0.7;
      description = "OCR confidence threshold for auto-review";
    };

    autoStart = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to auto-start the service";
    };
  };

  ####################################################################
  # IMPLEMENTATION
  ####################################################################

  config = mkIf cfg.enable {

    # Assertions
    assertions = [
      {
        assertion = config.hwc.services.databases.postgresql.enable;
        message = "Receipts OCR service requires PostgreSQL to be enabled";
      }
      {
        assertion = cfg.ollamaEnabled -> config.services.ollama.enable or false;
        message = "Receipts OCR service with LLM requires Ollama to be enabled";
      }
    ];

    ####################################################################
    # SYSTEM PACKAGES
    ####################################################################

    environment.systemPackages = [
      pythonEnv
      receiptOcrCli
      pkgs.tesseract  # OCR engine
      pkgs.poppler_utils  # PDF tools (pdftoimage)
    ];

    ####################################################################
    # SETUP SERVICE
    ####################################################################

    # Create service directory and install code
    systemd.tmpfiles.rules = [
      "d ${serviceDir} 0755 ${cfg.user} users -"
      "d ${cfg.storageRoot} 0755 ${cfg.user} users -"
      "d ${cfg.storageRoot}/raw 0755 ${cfg.user} users -"
      "d ${cfg.storageRoot}/processed 0755 ${cfg.user} users -"
      "d ${cfg.storageRoot}/failed 0755 ${cfg.user} users -"
      "d ${cfg.storageRoot}/watched 0755 ${cfg.user} users -"
    ];

    # One-shot service to deploy code
    systemd.services.receipts-ocr-setup = {
      description = "Setup receipts OCR service";
      wantedBy = [ "multi-user.target" ];
      before = [ "receipts-ocr.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
      };

      script = ''
        # Copy source code to service directory
        mkdir -p ${serviceDir}/src

        # Copy Python modules (will be replaced with actual files)
        cat > ${serviceDir}/src/__init__.py << 'EOF'
"""Receipt OCR Pipeline"""
__version__ = "1.0.0"
EOF

        cat > ${serviceDir}/src/config.py << 'EOF'
"""Configuration for receipt OCR service"""
import os
from pathlib import Path

class Config:
    def __init__(self):
        self.database_url = os.getenv('DATABASE_URL', '${cfg.databaseUrl}')
        self.ollama_enabled = ${if cfg.ollamaEnabled then "True" else "False"}
        self.ollama_url = os.getenv('OLLAMA_URL', '${cfg.ollamaUrl}')
        self.ollama_model = os.getenv('OLLAMA_MODEL', '${cfg.ollamaModel}')
        self.confidence_threshold = float(os.getenv('OCR_CONFIDENCE_THRESHOLD', '${toString cfg.confidenceThreshold}'))
        self.storage_root = Path(os.getenv('STORAGE_ROOT', '${cfg.storageRoot}'))
        self.upload_path = self.storage_root / 'raw'
        self.processed_path = self.storage_root / 'processed'
        self.failed_path = self.storage_root / 'failed'
        self.api_host = '${cfg.host}'
        self.api_port = ${toString cfg.port}

    def get_upload_path(self):
        from datetime import datetime
        date_path = self.upload_path / datetime.now().strftime('%Y/%m')
        date_path.mkdir(parents=True, exist_ok=True)
        return date_path

    def get_processed_path(self):
        from datetime import datetime
        date_path = self.processed_path / datetime.now().strftime('%Y/%m')
        date_path.mkdir(parents=True, exist_ok=True)
        return date_path

    def get_failed_path(self):
        from datetime import datetime
        date_path = self.failed_path / datetime.now().strftime('%Y/%m')
        date_path.mkdir(parents=True, exist_ok=True)
        return date_path
EOF

        # Note: Full source code should be copied from workspace/projects/receipts-pipeline/src/
        echo "Note: Full Python source code should be deployed from workspace/projects/receipts-pipeline/"
        echo "Service directory: ${serviceDir}"
      '';
    };

    ####################################################################
    # SYSTEMD SERVICE
    ####################################################################

    systemd.services.receipts-ocr = {
      description = "Receipts OCR Service";
      after = [
        "postgresql.service"
        "receipts-ocr-setup.service"
      ] ++ optional (cfg.ollamaEnabled && config.services.ollama.enable or false) "ollama.service";

      wants = [
        "postgresql.service"
      ] ++ optional (cfg.ollamaEnabled && config.services.ollama.enable or false) "ollama.service";

      wantedBy = mkIf cfg.autoStart [ "multi-user.target" ];

      environment = {
        DATABASE_URL = cfg.databaseUrl;
        OLLAMA_ENABLED = if cfg.ollamaEnabled then "true" else "false";
        OLLAMA_URL = cfg.ollamaUrl;
        OLLAMA_MODEL = cfg.ollamaModel;
        STORAGE_ROOT = cfg.storageRoot;
        OCR_CONFIDENCE_THRESHOLD = toString cfg.confidenceThreshold;
        API_HOST = cfg.host;
        API_PORT = toString cfg.port;
        PYTHONUNBUFFERED = "1";
      };

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        WorkingDirectory = serviceDir;
        ExecStart = "${receiptOcrService}/bin/receipt-ocr-service";
        Restart = "always";
        RestartSec = "10";

        # Security hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ cfg.storageRoot ];

        # Logging
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    ####################################################################
    # DATABASE INITIALIZATION
    ####################################################################

    # One-shot service to initialize database schema
    systemd.services.receipts-ocr-db-init = {
      description = "Initialize receipts OCR database schema";
      after = [ "postgresql.service" ];
      wants = [ "postgresql.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
      };

      script = ''
        # Check if database exists
        if ! ${pkgs.postgresql}/bin/psql -lqt | cut -d \| -f 1 | grep -qw heartwood_business; then
          echo "Creating heartwood_business database..."
          ${pkgs.postgresql}/bin/createdb heartwood_business
          ${pkgs.postgresql}/bin/createuser -s business_user || true
        fi

        # Apply schema if tables don't exist
        if ! ${pkgs.postgresql}/bin/psql heartwood_business -c "SELECT 1 FROM receipts LIMIT 1" 2>/dev/null; then
          echo "Initializing database schema..."
          # Note: Schema should be applied from workspace/projects/receipts-pipeline/database/schema.sql
          echo "Schema file: workspace/projects/receipts-pipeline/database/schema.sql"
        fi
      '';
    };

    ####################################################################
    # FIREWALL
    ####################################################################

    # Open port on Tailscale interface (not public)
    networking.firewall.interfaces."tailscale0" = mkIf config.hwc.networking.tailscale.enable {
      allowedTCPPorts = [ cfg.port ];
    };
  };
}
