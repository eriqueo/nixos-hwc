# domains/business/parts/receipts-ocr.nix
#
# Receipts OCR Service Implementation
# Systemd service for processing receipt images with OCR and PostgreSQL storage
#
# Pure helper that returns configuration attributes
# Fails gracefully with clear error messages when dependencies are missing

{ config, lib, pkgs }:

let
  cfg = config.hwc.business.receiptsOcr;
  businessCfg = config.hwc.business;
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
  serviceDir = "${businessCfg.dataDir}/receipts-ocr";

  # Source code directory (expected location)
  sourceDir = "${paths.nixos or "/home/eric/.nixos"}/workspace/projects/receipts-pipeline";

  # Receipt OCR service script with validation
  receiptOcrService = pkgs.writeScriptBin "receipt-ocr-service" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SERVICE_DIR="${serviceDir}"
    SOURCE_DIR="${sourceDir}"
    LOG_FILE="/var/log/hwc/receipts-ocr.log"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$LOG_FILE")"

    log "Starting receipts-ocr service..."

    # Check if source code exists
    if [ ! -f "$SERVICE_DIR/src/receipt_ocr_service.py" ]; then
      log "ERROR: Source code not found at $SERVICE_DIR/src/"
      log "  Expected: $SERVICE_DIR/src/receipt_ocr_service.py"
      log ""
      log "To deploy the service:"
      log "  1. Ensure source code exists at: $SOURCE_DIR/src/"
      log "  2. Run: sudo systemctl start receipts-ocr-setup"
      log "  3. Then restart this service"
      log ""
      log "Service will exit. Fix deployment and restart."
      exit 1
    fi

    # Check database connectivity
    log "Checking database connectivity..."
    if ! ${pkgs.postgresql}/bin/psql "${cfg.databaseUrl}" -c "SELECT 1" > /dev/null 2>&1; then
      log "WARNING: Cannot connect to database: ${cfg.databaseUrl}"
      log "  Service will start but may fail on database operations"
    else
      log "  Database connection OK"
    fi

    # Check Ollama if enabled
    ${lib.optionalString cfg.ollama.enable ''
      log "Checking Ollama connectivity..."
      if ! ${pkgs.curl}/bin/curl -sf "${cfg.ollama.url}/api/tags" > /dev/null 2>&1; then
        log "WARNING: Cannot connect to Ollama at ${cfg.ollama.url}"
        log "  LLM normalization will fail until Ollama is available"
      else
        log "  Ollama connection OK"
      fi
    ''}

    cd "$SERVICE_DIR"
    log "Starting uvicorn on ${cfg.host}:${toString cfg.port}..."
    exec ${pythonEnv}/bin/python -m uvicorn src.receipt_ocr_service:app \
      --host ${cfg.host} \
      --port ${toString cfg.port}
  '';

  # CLI wrapper script
  receiptOcrCli = pkgs.writeScriptBin "receipt-ocr" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SERVICE_DIR="${serviceDir}"

    if [ ! -d "$SERVICE_DIR/src" ]; then
      echo "ERROR: Receipts OCR not deployed. Run: sudo systemctl start receipts-ocr-setup"
      exit 1
    fi

    cd "$SERVICE_DIR"
    exec ${pythonEnv}/bin/python -m src.receipt_ocr_service "$@"
  '';

in
{
  # Packages to install
  packages = [
    pythonEnv
    receiptOcrCli
    pkgs.tesseract      # OCR engine
    pkgs.poppler_utils  # PDF tools (pdftoimage)
  ];

  # tmpfiles rules for directories
  tmpfilesRules = [
    "d ${serviceDir} 0755 ${cfg.user} users -"
    "d ${serviceDir}/src 0755 ${cfg.user} users -"
    "d ${cfg.storageRoot} 0755 ${cfg.user} users -"
    "d ${cfg.storageRoot}/raw 0755 ${cfg.user} users -"
    "d ${cfg.storageRoot}/processed 0755 ${cfg.user} users -"
    "d ${cfg.storageRoot}/failed 0755 ${cfg.user} users -"
    "d ${cfg.storageRoot}/watched 0755 ${cfg.user} users -"
    "d /var/log/hwc 0755 root root -"
  ];

  # Setup service (deploys code from workspace)
  setupService = {
    description = "Setup receipts OCR service (deploy code)";
    wantedBy = [ "multi-user.target" ];
    before = [ "receipts-ocr.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = cfg.user;
    };

    script = ''
      set -euo pipefail

      SERVICE_DIR="${serviceDir}"
      SOURCE_DIR="${sourceDir}"
      LOG_FILE="/var/log/hwc/receipts-ocr-setup.log"

      log() {
        echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
      }

      ${pkgs.coreutils}/bin/mkdir -p "$SERVICE_DIR/src"
      ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$LOG_FILE")"

      log "Receipts OCR setup starting..."
      log "  Service directory: $SERVICE_DIR"
      log "  Source directory: $SOURCE_DIR"

      # Check if source code exists in workspace
      if [ -d "$SOURCE_DIR/src" ] && [ -f "$SOURCE_DIR/src/receipt_ocr_service.py" ]; then
        log "Found source code in workspace, deploying..."
        ${pkgs.rsync}/bin/rsync -av --delete "$SOURCE_DIR/src/" "$SERVICE_DIR/src/"
        log "  Deployed $(${pkgs.findutils}/bin/find "$SERVICE_DIR/src" -name "*.py" | ${pkgs.coreutils}/bin/wc -l) Python files"
      else
        log "WARNING: Source code not found at $SOURCE_DIR/src/"
        log "  Creating stub files for development..."

        # Create minimal stub that explains the situation
        ${pkgs.coreutils}/bin/cat > "$SERVICE_DIR/src/__init__.py" << 'PYEOF'
"""
Receipt OCR Pipeline - STUB

This is a placeholder. To deploy the actual service:
1. Clone/create the source code at: ${sourceDir}
2. Run: sudo systemctl restart receipts-ocr-setup
3. Then: sudo systemctl restart receipts-ocr

Required structure:
  ${sourceDir}/src/receipt_ocr_service.py
  ${sourceDir}/src/config.py
  ${sourceDir}/src/ocr/
  ${sourceDir}/src/api/
"""
__version__ = "0.0.0-stub"
PYEOF

        ${pkgs.coreutils}/bin/cat > "$SERVICE_DIR/src/receipt_ocr_service.py" << 'PYEOF'
"""
Receipt OCR Service - STUB

This file is a placeholder. See __init__.py for deployment instructions.
"""
from fastapi import FastAPI

app = FastAPI(title="Receipts OCR (STUB)", version="0.0.0")

@app.get("/")
def root():
    return {
        "status": "stub",
        "message": "Service not deployed. See logs for deployment instructions.",
        "deploy_from": "${sourceDir}"
    }

@app.get("/health")
def health():
    return {"status": "stub", "deployed": False}
PYEOF

        log "  Stub files created - service will run but won't process receipts"
      fi

      # Create config file
      ${pkgs.coreutils}/bin/cat > "$SERVICE_DIR/src/config.py" << 'PYEOF'
"""Configuration for receipt OCR service - Generated by NixOS"""
import os
from pathlib import Path

class Config:
    def __init__(self):
        self.database_url = os.getenv('DATABASE_URL', '${cfg.databaseUrl}')
        self.ollama_enabled = ${if cfg.ollama.enable then "True" else "False"}
        self.ollama_url = os.getenv('OLLAMA_URL', '${cfg.ollama.url}')
        self.ollama_model = os.getenv('OLLAMA_MODEL', '${cfg.ollama.model}')
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

config = Config()
PYEOF

      log "Setup complete"
    '';
  };

  # Main service
  mainService = {
    description = "Receipts OCR Service";
    after = [
      "postgresql.service"
      "receipts-ocr-setup.service"
    ] ++ lib.optional (cfg.ollama.enable && (config.services.ollama.enable or false)) "ollama.service";

    wants = [
      "postgresql.service"
    ] ++ lib.optional (cfg.ollama.enable && (config.services.ollama.enable or false)) "ollama.service";

    requires = [ "receipts-ocr-setup.service" ];

    wantedBy = lib.mkIf cfg.autoStart [ "multi-user.target" ];

    environment = {
      DATABASE_URL = cfg.databaseUrl;
      OLLAMA_ENABLED = if cfg.ollama.enable then "true" else "false";
      OLLAMA_URL = cfg.ollama.url;
      OLLAMA_MODEL = cfg.ollama.model;
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
      Restart = "on-failure";
      RestartSec = "30";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ cfg.storageRoot serviceDir "/var/log/hwc" ];

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Database init service (with proper error handling)
  dbInitService = {
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
      set -euo pipefail

      LOG_FILE="/var/log/hwc/receipts-ocr-db.log"
      ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$LOG_FILE")"

      log() {
        echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
      }

      log "Checking database setup..."

      # Check if database exists (using standard grep, not rg)
      if ! ${pkgs.postgresql}/bin/psql -lqt | ${pkgs.coreutils}/bin/cut -d \| -f 1 | ${pkgs.gnugrep}/bin/grep -qw heartwood_business; then
        log "Creating heartwood_business database..."
        ${pkgs.postgresql}/bin/createdb heartwood_business || {
          log "ERROR: Failed to create database"
          exit 1
        }
        log "  Database created"

        # Create user if doesn't exist
        if ! ${pkgs.postgresql}/bin/psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='business_user'" | ${pkgs.gnugrep}/bin/grep -q 1; then
          ${pkgs.postgresql}/bin/createuser business_user || log "  Note: business_user may already exist"
        fi
        log "  User business_user ready"
      else
        log "  Database heartwood_business already exists"
      fi

      # Check if schema needs to be applied
      SCHEMA_FILE="${sourceDir}/database/schema.sql"
      if [ -f "$SCHEMA_FILE" ]; then
        # Check if receipts table exists
        if ! ${pkgs.postgresql}/bin/psql heartwood_business -c "SELECT 1 FROM receipts LIMIT 1" > /dev/null 2>&1; then
          log "Applying schema from $SCHEMA_FILE..."
          ${pkgs.postgresql}/bin/psql heartwood_business -f "$SCHEMA_FILE" || {
            log "WARNING: Schema application failed - manual intervention may be needed"
          }
        else
          log "  Schema already applied (receipts table exists)"
        fi
      else
        log "  Note: No schema file found at $SCHEMA_FILE"
        log "  Create schema manually or add schema.sql to workspace"
      fi

      log "Database setup complete"
    '';
  };

  # Firewall configuration
  firewallPorts = [ cfg.port ];
}
