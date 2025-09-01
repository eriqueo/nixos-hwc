# nixos-hwc/modules/services/ai/ollama-old.nix
#
# OLLAMA OLD - Brief service description
# TODO: Add detailed description of what this module provides
#
# DEPENDENCIES (Upstream):
#   - TODO: List upstream dependencies
#   - config.hwc.paths.* (modules/system/paths.nix)
#
# USED BY (Downstream):
#   - TODO: List downstream consumers
#   - profiles/*.nix (enables via hwc.services.ollama-old.enable)
#
# IMPORTS REQUIRED IN:
#   - profiles/profile.nix: ../modules/services/ai/ollama-old.nix
#
# USAGE:
#   hwc.services.ollama-old.enable = true;
#   # TODO: Add specific usage examples

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.ollama;
  paths = config.hwc.paths;
in {
  #============================================================================
  # OPTIONS - What can be configured
  #============================================================================
  options.hwc.services.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM";
    
    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port";
    };
    
    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "llama2" "codellama" ];
      description = "Models to download";
    };
    
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/ollama";
      description = "Model storage directory";
    };
    
    enableGpu = lib.mkEnableOption "GPU acceleration";
    
    memoryLimit = lib.mkOption {
      type = lib.types.str;
      default = "16G";
      description = "Memory limit";
    };
  };
  

  #============================================================================
  # IMPLEMENTATION - What actually gets configured
  #============================================================================
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.ollama = {
      image = "ollama/ollama:latest";
      
      ports = [ "${toString cfg.port}:11434" ];
      
      volumes = [
        "${cfg.dataDir}:/root/.ollama"
      ];
      
      environment = {
        OLLAMA_HOST = "0.0.0.0";
        OLLAMA_MODELS = cfg.dataDir;
      };
      
      extraOptions = lib.optionals cfg.enableGpu [
        "--gpus=all"
        "--device=/dev/nvidia0"
        "--device=/dev/nvidiactl"
        "--device=/dev/nvidia-uvm"
      ];
    };
    
    # Model download service
    systemd.services.ollama-models = {
      description = "Download Ollama models";
      after = [ "ollama.service" ];
      wantedBy = [ "multi-user.target" ];
      
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      
      script = ''
        ${lib.concatMapStrings (model: ''
          ${pkgs.curl}/bin/curl -X POST http://localhost:${toString cfg.port}/api/pull \
            -d '{"name": "${model}"}'
        '') cfg.models}
      '';
    };
    
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
