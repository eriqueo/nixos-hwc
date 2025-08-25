# nixos-hwc/modules/services/ai/ollama.nix
#
# Service: Ollama (Local LLM via OCI container)
# Consumes GPU capability exposed by modules/system/gpu.nix (no driver logic here).
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.*        (modules/system/paths.nix)
#   - config.hwc.gpu.*          (modules/system/gpu.nix)  // accel, containerOptions, containerEnvironment
#
# USED BY (Downstream):
#   - profiles/ai.nix           (orchestration toggle)
#   - machines/*/config.nix     (facts: enable service, models list)
#
# IMPORTS REQUIRED IN:
#   - profiles/ai.nix: ../modules/services/ai/ollama.nix
#
# USAGE:
#   hwc.services.ollama.enable = true;
#   hwc.services.ollama.models = [ "llama3:8b" "codellama:13b" ];
#   # GPU use is inferred from hwc.gpu.type/accel; no enableGpu knob here.

{ config, lib, pkgs, ... }:

let
  cfg   = config.hwc.services.ollama;
  paths = config.hwc.paths;

  # Derived convenience flags from infrastructure capability (read-only source of truth)
  accel = config.hwc.gpu.accel or "cpu";
  gpuExtraOptions = config.hwc.gpu.containerOptions or [];
  gpuEnv          = config.hwc.gpu.containerEnvironment or {};
in
{
  #============================================================================
  # OPTIONS - Service interface (no hardware toggles here)
  #============================================================================
  options.hwc.services.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM (via OCI container)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port for the Ollama service.";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "llama3:8b" "codellama:13b" ];
      description = "Models to pre-download and keep available.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.hot}/ollama";
      description = "Directory for storing Ollama models.";
    };

    # If you want a manual CPU override even when GPU is present, add a boolean here later.
    # For now, we follow hwc.gpu.accel automatically.
  };

  #============================================================================
  # IMPLEMENTATION - Container + ancillary units
  #============================================================================
  config = lib.mkIf cfg.enable {

    # OCI container definition. We consume GPU capability via containerOptions/env.
    virtualisation.oci-containers.containers.ollama = {
      image  = "ollama/ollama:latest";
      ports  = [ "${toString cfg.port}:11434" ];
      volumes = [ "${cfg.dataDir}:/root/.ollama" ];

      # Merge GPU env from infrastructure layer with service env.
      environment = gpuEnv // {
        OLLAMA_HOST = "0.0.0.0";
      };

      # Pass device flags from infrastructure (NVIDIA/Intel/AMD) in a single place.
      # Works for Docker backend via --device=... and similar options.
      extraOptions = gpuExtraOptions;
    };

    # Create data directory with correct ownership before the container starts.
    systemd.tmpfiles.rules = [ "d ${cfg.dataDir} 0755 root root -" ];

    # Open firewall for the API port.
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Optional: install the host CLI, useful for local scripts/testing.
    environment.systemPackages = [ pkgs.ollama ];

    # One-shot model pre-pull after the container is up.
    systemd.services.ollama-pull-models = {
      description = "Pre-download initial Ollama models";
      after  = [ "network-online.target" "oci-containers-ollama.service" ];
      wants  = [ "network-online.target" "oci-containers-ollama.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Run once (idempotent marker)
        ExecStartPre = "/bin/sh -c 'test -f /var/lib/ollama-models-pulled && exit 0 || exit 0'";
        ExecStart = let
          pullCmds = lib.concatMapStringsSep "\n" (model: ''
            echo "Pulling ${model}..."
            ${pkgs.curl}/bin/curl -sS -X POST -H 'Content-Type: application/json' \
              --data '{"name":"${model}","stream":false}' \
              http://127.0.0.1:${toString cfg.port}/api/pull || exit 1
            echo "Pulled: ${model}"
          '') cfg.models;
        in ''
          /bin/sh -eu -c '
            echo "Waiting for Ollama to be ready on port ${toString cfg.port}..."
            for i in $(seq 1 120); do
              if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:${toString cfg.port}/api/tags >/dev/null; then
                break
              fi
              sleep 1
            done
            ${pullCmds}
            touch /var/lib/ollama-models-pulled
          '
        '';
      };
    };

    # IMPORTANT: No user/group manipulation here (user domain). Keep Charter separation.
    # users.groups.ollama = {};
    # users.users.eric.extraGroups = [ "ollama" ];
  };
}
