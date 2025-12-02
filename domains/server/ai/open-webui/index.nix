# domains/server/ai/open-webui/index.nix
#
# Open WebUI - Modern web interface for Ollama
# Provides a beautiful, feature-rich UI for interacting with local LLMs

{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.ai.open-webui;
  
  # Build environment variables
  baseEnv = {
    # Access Ollama via host gateway (container uses bridge networking, not host mode)
    OLLAMA_BASE_URL = "http://ollama:11434";
    WEBUI_AUTH = if cfg.enableAuth then "true" else "false";
    DEFAULT_MODELS = cfg.defaultModel;

    # RAG Configuration
    ENABLE_RAG_WEB_SEARCH = "false";  # Keep it local
    CHUNK_SIZE = toString cfg.ragChunkSize;
    CHUNK_OVERLAP = toString cfg.ragOverlap;

    # UI Customization
    WEBUI_NAME = "HWC AI Assistant";

    # Security
    ENABLE_SIGNUP = "true";  # Allow user registration
    ENABLE_LOGIN_FORM = toString cfg.enableAuth;

    # Performance
    NUM_WORKERS = "2";
  };

  # Merge with user-provided extra environment variables
  containerEnv = baseEnv // cfg.extraEnv;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./options.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Podman container configuration
    virtualisation.oci-containers.containers.open-webui = {
      image = "ghcr.io/open-webui/open-webui:${cfg.imageTag}";
      
      autoStart = true;

      ports = [
        "${toString cfg.port}:8080"  # Open WebUI default internal port is 8080
      ];

      volumes = [
        "${cfg.dataDir}:/app/backend/data"
      ];

      environment = containerEnv;

      # No extra options needed - using default bridge networking with port mapping
      extraOptions = [];
    };

    # Ensure Podman is enabled
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # Ensure OCI containers backend is set
    virtualisation.oci-containers.backend = "podman";

    # Systemd service customization
    systemd.services.podman-open-webui = {
      after = [ "podman-ollama.service" ];
      wants = [ "podman-ollama.service" ];
      
      serviceConfig = {
        Restart = "always";
        RestartSec = "10s";
      };
    };

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 root root -"
    ];

    #========================================================================
    # VALIDATION
    #========================================================================
    assertions = [
      {
        assertion = cfg.enable -> (cfg.port > 0 && cfg.port < 65536);
        message = "Open WebUI port must be between 1 and 65535";
      }
      {
        assertion = cfg.enable -> (cfg.ragChunkSize > 0);
        message = "RAG chunk size must be positive";
      }
      {
        assertion = cfg.enable -> (cfg.ragOverlap >= 0 && cfg.ragOverlap < cfg.ragChunkSize);
        message = "RAG overlap must be non-negative and less than chunk size";
      }
    ];
  };
}
