# HWC Charter Module/domains/services/business/api.nix
#
# API - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.api.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../domains/services/business/api.nix
#
# USAGE:
#   hwc.services.api.enable = true;
#   # TODO: Add specific usage examples

# modules/services/business/api.nix
# Charter v3 Business API Development Environment
# SOURCE: /etc/nixos/hosts/serv../domains/business-api.nix (lines 1-111)
{ config, lib, pkgs, ... }:

with lib;

let 
  cfg = config.hwc.services.business.api;
  paths = config.hwc.paths;
in {
  
  ####################################################################
  # CHARTER V3 OPTIONS
  ####################################################################
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.business.api = {
    enable = mkEnableOption "business API development environment and services";
    
    development = {
      enable = mkEnableOption "development environment setup with virtual environment";
      pythonVersion = mkOption {
        type = types.package;
        default = pkgs.python3;
        description = "Python version to use for business API";
      };
      requirements = mkOption {
        type = types.listOf types.str;
        default = [
          "fastapi==0.104.1"
          "uvicorn[standard]==0.24.0"
          "sqlalchemy==2.0.23"
          "alembic==1.13.1"
          "psycopg2-binary==2.9.9"
          "asyncpg==0.29.0"
          "pandas==2.1.4"
          "pydantic==2.5.0"
          "python-multipart==0.0.6"
          "python-dotenv==1.0.0"
          "httpx==0.25.2"
          "requests==2.31.0"
          "pillow==10.1.0"
          "opencv-python==4.8.1.78"
          "pytesseract==0.3.10"
          "pdf2image==1.16.3"
          "streamlit==1.28.1"
          "plotly==5.17.0"
          "altair==5.1.2"
          "redis==5.0.1"
          "chromadb==0.4.18"
          "sentence-transformers==2.2.2"
          "langchain==0.1.0"
          "openai==1.3.0"
        ];
        description = "Python package requirements for business API";
      };
    };
    
    service = {
      enable = mkEnableOption "business API systemd service (for production deployment)";
      host = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = "API server bind address";
      };
      port = mkOption {
        type = types.port;
        default = 8000;
        description = "API server port";
      };
      workingDirectory = mkOption {
        type = types.str;
        default = "${paths.business.root}/api";
        description = "Working directory for the API service";
      };
      user = mkOption {
        type = types.str;
        default = "eric";
        description = "User to run the API service as";
      };
      autoStart = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to auto-start the API service (disabled by default for development)";
      };
    };
    
    packages = {
      enable = mkEnableOption "business API related system packages";
    };
  };

  ####################################################################
  # CHARTER V3 IMPLEMENTATION
  ####################################################################

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = mkIf cfg.enable {
    
    # Assertions

    #==========================================================================
    # VALIDATION - Assertions and checks
    #==========================================================================
    assertions = [
      {
        assertion = cfg.service.enable -> cfg.packages.enable;
        message = "Business API service requires packages to be enabled (hwc.services.business.api.packages.enable = true)";
      }
      {
        assertion = cfg.service.enable -> config.hwc.services.business.database.postgresql.enable;
        message = "Business API service requires PostgreSQL database to be enabled";
      }
      {
        assertion = cfg.service.enable -> config.hwc.services.business.database.redis.enable;
        message = "Business API service requires Redis to be enabled";
      }
    ];

    ####################################################################
    # BUSINESS API PACKAGES
    ####################################################################
    environment.systemPackages = mkIf cfg.packages.enable (with pkgs; [
      # FastAPI and web framework tools
      python3Packages.fastapi
      python3Packages.uvicorn
      python3Packages.pydantic
      python3Packages.python-multipart
      
      # Database and data processing
      python3Packages.sqlalchemy
      python3Packages.alembic  # Database migrations
      python3Packages.psycopg2
      python3Packages.asyncpg
      python3Packages.pandas
      
      # Business integrations
      python3Packages.httpx  # For JobTread API
      python3Packages.requests
      python3Packages.python-dotenv
      
      # Document processing and OCR
      python3Packages.pillow
      python3Packages.opencv4
      python3Packages.pytesseract
      python3Packages.pdf2image
      
      # Data visualization
      python3Packages.streamlit
      python3Packages.plotly
      python3Packages.altair
    ]);

    ####################################################################
    # DEVELOPMENT ENVIRONMENT SETUP
    ####################################################################
    environment.etc."business/setup-dev-env.sh" = mkIf cfg.development.enable {
      text = ''
        #!/bin/bash
        
        echo "Setting up Heartwood Craft business development environment..."
        
        # Ensure business API directory exists
        mkdir -p ${cfg.service.workingDirectory}
        cd ${cfg.service.workingDirectory}
        
        # Create Python virtual environment for business API
        ${cfg.development.pythonVersion}/bin/python -m venv venv
        
        # Activate virtual environment for setup
        source venv/bin/activate
        
        # Create requirements.txt with Charter v3 managed requirements
        cat > requirements.txt << 'EOF'
      ${concatStringsSep "\n" cfg.development.requirements}
      EOF
        
        # Install requirements
        echo "Installing Python requirements..."
        pip install --upgrade pip
        pip install -r requirements.txt
        
        # Create basic project structure if it doesn't exist
        mkdir -p {static,templates,api,tests}
        
        # Create basic main.py if it doesn't exist
        if [ ! -f main.py ]; then
          cat > main.py << 'EOF'
      from fastapi import FastAPI, HTTPException
      from fastapi.staticfiles import StaticFiles
      from fastapi.templating import Jinja2Templates
      import os
      
      app = FastAPI(
          title="Heartwood Craft Business API",
          description="Business intelligence and operations API",
          version="1.0.0"
      )
      
      # Static files and templates
      app.mount("/static", StaticFiles(directory="static"), name="static")
      templates = Jinja2Templates(directory="templates")
      
      @app.get("/")
      async def root():
          return {
              "message": "Heartwood Craft Business API", 
              "status": "operational",
              "database": os.getenv("DATABASE_URL", "postgresql://business_user@localhost/heartwood_business"),
              "redis": os.getenv("REDIS_URL", "redis://localhost:6379/0")
          }
      
      @app.get("/health")
      async def health_check():
          return {"status": "healthy"}
      
      if __name__ == "__main__":
          import uvicorn
          uvicorn.run(app, host="${cfg.service.host}", port=${toString cfg.service.port})
      EOF
        fi
        
        # Create .env file with Charter v3 paths if it doesn't exist
        if [ ! -f .env ]; then
          cat > .env << 'EOF'
      DATABASE_URL=postgresql://business_user:secure_password_change_me@localhost:5432/heartwood_business
      REDIS_URL=redis://localhost:6379/0
      BUSINESS_DATA_PATH=${paths.business.root}
      MEDIA_PATH=${paths.media}
      HOT_STORAGE_PATH=${paths.hot}
      COLD_STORAGE_PATH=${paths.cold}
      EOF
        fi
        
        # Set proper ownership
        chown -R ${cfg.service.user}:users ${cfg.service.workingDirectory}
        
        echo "Business development environment ready!"
        echo ""
        echo "=== Environment Details ==="
        echo "API Directory: ${cfg.service.workingDirectory}"
        echo "Database: postgresql://business_user@localhost:5432/heartwood_business"
        echo "Redis: redis://localhost:6379/0"
        echo "API Server: http://localhost:${toString cfg.service.port}"
        echo "Dashboard: http://localhost:8501"
        echo ""
        echo "=== Quick Start ==="
        echo "cd ${cfg.service.workingDirectory}"
        echo "source venv/bin/activate"
        echo "uvicorn main:app --host ${cfg.service.host} --port ${toString cfg.service.port} --reload"
      '';
      mode = "0755";
    };

    ####################################################################
    # BUSINESS API SYSTEMD SERVICE
    ####################################################################
    systemd.services.business-api = mkIf cfg.service.enable {
      description = "Heartwood Craft Business API";
      after = [ 
        "postgresql.service" 
        "redis-business.service"
      ] ++ optionals config.hwc.services.ai.ollama.enable [ "ollama.service" ];
      
      wants = [ 
        "postgresql.service" 
        "redis-business.service"
      ] ++ optionals config.hwc.services.ai.ollama.enable [ "ollama.service" ];
      
      serviceConfig = {
        Type = "simple";
        User = cfg.service.user;
        WorkingDirectory = cfg.service.workingDirectory;
        ExecStart = "${pkgs.python3Packages.uvicorn}/bin/uvicorn main:app --host ${cfg.service.host} --port ${toString cfg.service.port}";
        Restart = "always";
        RestartSec = "10";
        
        # Environment variables for the service
        Environment = [
          "DATABASE_URL=postgresql://business_user@localhost:5432/heartwood_business"
          "REDIS_URL=redis://localhost:6379/0"
          "BUSINESS_DATA_PATH=${paths.business.root}"
          "MEDIA_PATH=${paths.media}"
          "HOT_STORAGE_PATH=${paths.hot}"
          "COLD_STORAGE_PATH=${paths.cold}"
        ];
      };
      
      # Only auto-start if explicitly enabled
      wantedBy = mkIf cfg.service.autoStart [ "multi-user.target" ];
    };

    ####################################################################
    # DEVELOPMENT HELPER SERVICE
    ####################################################################
    systemd.services.business-api-dev-setup = mkIf cfg.development.enable {
      description = "Setup business API development environment";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.bash}/bin/bash /etc/business/setup-dev-env.sh";
      };
      wantedBy = [ "multi-user.target" ];
    };

    ####################################################################
    # NETWORKING INTEGRATION  
    ####################################################################
    # Register business API ports with Charter v3 networking
    hwc.networking.firewall.extraTcpPorts = mkIf (cfg.service.enable && config.hwc.networking.enable) [
      cfg.service.port
    ];

    # Allow business API access on Tailscale interface
    networking.firewall.interfaces."tailscale0" = mkIf (cfg.service.enable && config.hwc.networking.tailscale.enable) {
      allowedTCPPorts = [ cfg.service.port ];
    };
  };
}
