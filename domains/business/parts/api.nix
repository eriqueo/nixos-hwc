# domains/business/parts/api.nix
#
# Business API Implementation
# Python FastAPI service for business operations
#
# Pure helper that returns configuration attributes
# Fails gracefully when dependencies are missing

{ config, lib, pkgs }:

let
  cfg = config.hwc.business.api;
  businessCfg = config.hwc.business;
  paths = config.hwc.paths;

  # Source directory
  sourceDir = "${paths.nixos or "/home/eric/.nixos"}/workspace/business/remodel-api";

  # Python environment for business API
  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    fastapi
    uvicorn
    pydantic
    httpx
    python-dotenv
    sqlalchemy
    psycopg2
    alembic
  ]);

  # API service script with validation
  apiServiceScript = pkgs.writeScriptBin "business-api-service" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    WORK_DIR="${cfg.service.workingDirectory}"
    LOG_FILE="/var/log/hwc/business-api.log"

    log() {
      echo "[$(${pkgs.coreutils}/bin/date '+%Y-%m-%d %H:%M:%S')] $1" | ${pkgs.coreutils}/bin/tee -a "$LOG_FILE"
    }

    ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$LOG_FILE")"
    ${pkgs.coreutils}/bin/mkdir -p "$WORK_DIR"

    log "Starting business-api service..."

    # Check if main.py exists
    if [ ! -f "$WORK_DIR/main.py" ]; then
      log "WARNING: main.py not found at $WORK_DIR"
      log "  Creating minimal stub..."

      ${pkgs.coreutils}/bin/cat > "$WORK_DIR/main.py" << 'PYEOF'
"""
Business API - STUB

Deploy actual code to: ${cfg.service.workingDirectory}
"""
from fastapi import FastAPI

app = FastAPI(title="Business API (STUB)", version="0.0.0")

@app.get("/")
def root():
    return {
        "status": "stub",
        "message": "Business API not deployed",
        "deploy_to": "${cfg.service.workingDirectory}"
    }

@app.get("/health")
def health():
    return {"status": "stub", "deployed": False}
PYEOF
      log "  Stub created - deploy real code to enable functionality"
    fi

    cd "$WORK_DIR"
    log "Starting uvicorn on ${cfg.service.host}:${toString cfg.service.port}..."
    exec ${pythonEnv}/bin/uvicorn main:app \
      --host ${cfg.service.host} \
      --port ${toString cfg.service.port} \
      ${lib.optionalString cfg.development.enable "--reload"}
  '';

in
{
  # Packages to install
  packages = lib.optionals cfg.packages.enable [
    pythonEnv
    apiServiceScript
  ];

  # tmpfiles rules
  tmpfilesRules = [
    "d ${businessCfg.dataDir} 0750 eric users -"
    "d ${cfg.service.workingDirectory} 0755 eric users -"
    "d /var/log/hwc 0755 root root -"
  ];

  # Main API service (returns empty attrs if not enabled)
  mainService = {
    description = "Business API Service";
    after = [ "network.target" "postgresql.service" ];
    wants = [ "postgresql.service" ];
    wantedBy = lib.mkIf cfg.service.autoStart [ "multi-user.target" ];

    environment = {
      PYTHONUNBUFFERED = "1";
      BUSINESS_DATA_DIR = businessCfg.dataDir;
    };

    serviceConfig = {
      Type = "simple";
      User = "eric";
      Group = "users";
      WorkingDirectory = cfg.service.workingDirectory;
      ExecStart = "${apiServiceScript}/bin/business-api-service";
      Restart = "on-failure";
      RestartSec = "30";

      # Security hardening
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [ businessCfg.dataDir cfg.service.workingDirectory "/var/log/hwc" ];

      # Logging
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Firewall ports
  firewallPorts = [ cfg.service.port ];
}
