# domains/server/ai/open-webui/parts/container.nix
#
# Podman container configuration for Open WebUI

{ config, lib, pkgs, cfg }:

let
  # Build environment variables
  baseEnv = {
    OLLAMA_BASE_URL = cfg.ollamaEndpoint;
    WEBUI_AUTH = if cfg.enableAuth then "true" else "false";
    DEFAULT_MODELS = cfg.defaultModel;
    
    # RAG Configuration
    ENABLE_RAG_WEB_SEARCH = "false";  # Keep it local
    CHUNK_SIZE = toString cfg.ragChunkSize;
    CHUNK_OVERLAP = toString cfg.ragOverlap;
    
    # UI Customization
    WEBUI_NAME = "HWC AI Assistant";
    WEBUI_URL = if cfg.domain != null then "https://${cfg.domain}" else "http://localhost:${toString cfg.port}";
    
    # Security
    ENABLE_SIGNUP = "true";  # Allow user registration
    ENABLE_LOGIN_FORM = toString cfg.enableAuth;
    
    # Performance
    NUM_WORKERS = "2";
  };

  # Merge with user-provided extra environment variables
  containerEnv = baseEnv // cfg.extraEnv;

  # Convert environment to list format for systemd
  envList = lib.mapAttrsToList (name: value: "${name}=${value}") containerEnv;
in
{
  # Create data directory
  systemd.tmpfiles.rules = [
    "d ${cfg.dataDir} 0750 root root -"
  ];

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

    extraOptions = [
      "--network=host"  # Access Ollama on localhost
      "--pull=always"   # Always pull latest image on restart
    ];

    # Health check
    # Open WebUI has a /health endpoint
    # We'll rely on systemd's restart policy for now
  };

  # Systemd service customization
  systemd.services.podman-open-webui = {
    after = [ "podman-ollama.service" ];
    wants = [ "podman-ollama.service" ];
    
    serviceConfig = {
      Restart = "always";
      RestartSec = "10s";
    };
  };
}
