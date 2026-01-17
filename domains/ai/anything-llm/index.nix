# domains/ai/anything-llm/index.nix
#
# AnythingLLM implementation - Local AI assistant with file system access
# Provides ChatGPT-like interface for interacting with local files via Ollama

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.anything-llm;

  # Build volume mount list based on configuration
  volumeMounts =
    lib.optionals cfg.workspace.nixosDir [
      "${config.hwc.paths.user.home}/.nixos:/app/collector/nixos:ro"
    ] ++
    lib.optionals cfg.workspace.homeDir [
      "${config.hwc.paths.user.home}:/app/collector/home:ro"
    ] ++
    (map (path: "${path}:/app/collector/${baseNameOf path}:ro") cfg.workspace.customPaths) ++
    [
      "${cfg.dataDir}:/app/server/storage"
    ];

in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {

    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    # AnythingLLM container service
    virtualisation.podman.enable = true;

    systemd.services.podman-anything-llm = {
      description = "AnythingLLM - Local AI assistant with file access";
      after = [ "network-online.target" "podman-ollama.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.podman ];

      serviceConfig = {
        Type = "forking";
        Restart = "always";
        RestartSec = "10s";
        TimeoutStartSec = "120s";
      };

      preStart = ''
        ${pkgs.podman}/bin/podman pull mintplexlabs/anythingllm:latest
      '';

      script = ''
        ${pkgs.podman}/bin/podman run \
          --rm \
          --name anything-llm \
          --detach \
          --publish 127.0.0.1:${toString cfg.port}:3001 \
          --add-host host.containers.internal:host-gateway \
          ${lib.concatMapStringsSep " " (v: "--volume ${v}") volumeMounts} \
          --env "LLM_PROVIDER=ollama" \
          --env "OLLAMA_BASE_PATH=${cfg.ollama.endpoint}" \
          --env "OLLAMA_MODEL_PREF=${cfg.ollama.defaultModel}" \
          --env "EMBEDDING_ENGINE=${cfg.embeddings.provider}" \
          --env "EMBEDDING_MODEL_PREF=${cfg.embeddings.model}" \
          --env "STORAGE_DIR=/app/server/storage" \
          --env "DISABLE_TELEMETRY=true" \
          --env "SERVER_PORT=3001" \
          mintplexlabs/anythingllm:latest
      '';

      preStop = ''
        ${pkgs.podman}/bin/podman stop -t 10 anything-llm || true
      '';

      postStop = ''
        ${pkgs.podman}/bin/podman rm -f anything-llm || true
      '';
    };

    # Firewall configuration (localhost only by default)
    # Access via: http://localhost:${cfg.port}

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.ai.ollama.enable;
        message = "AnythingLLM requires Ollama to be enabled (hwc.ai.ollama.enable = true)";
      }
      {
        assertion = cfg.workspace.nixosDir || cfg.workspace.homeDir || (cfg.workspace.customPaths != []);
        message = "AnythingLLM requires at least one workspace path to be enabled";
      }
    ];
  };
}
