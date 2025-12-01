# domains/server/ai/open-webui/default.nix
#
# Open WebUI - Modern web interface for Ollama
# Provides a beautiful, feature-rich UI for interacting with local LLMs

{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.server.ai.open-webui;
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
    # Import implementation parts
    imports = [
      (import ./parts/container.nix { inherit config lib pkgs; cfg = cfg; })
      (import ./parts/caddy.nix { inherit config lib pkgs; cfg = cfg; })
    ];

    # Ensure Podman is enabled
    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    # Ensure OCI containers backend is set
    virtualisation.oci-containers.backend = "podman";

    # Open firewall port if domain is not configured (local access)
    networking.firewall.allowedTCPPorts = lib.mkIf (cfg.domain == null) [ cfg.port ];
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  config.assertions = [
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
}
