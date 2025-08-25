# In: modules/services/ai/ollama.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.services.ollama;
  # It's good practice to get paths from the config where they are defined.
  # Assuming paths.hot is defined elsewhere in your flake.
  paths = config.hwc.paths;
in
{
  options.hwc.services.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM (via OCI Container)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port for Ollama service.";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # Let's update the defaults to the models we discussed!
      default = [ "llama3:8b" "codellama:13b" ];
      description = "Models to be pre-downloaded and available.";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      # Ensure this path exists and has correct permissions.
      default = "${paths.hot}/ollama";
      description = "Directory for storing Ollama models.";
    };

    # This option is now much cleaner and more declarative.
    enableGpu = lib.mkEnableOption "NVIDIA GPU acceleration";
  };

  config = lib.mkIf cfg.enable {
    # This is the core of the container definition.
    virtualisation.oci-containers.containers.ollama = {
      image = "ollama/ollama:latest";

      ports = [ "${toString cfg.port}:11434" ];

      volumes = [
        "${cfg.dataDir}:/root/.ollama"
      ];

      environment = {
        OLLAMA_HOST = "0.0.0.0";
        # This variable is not needed; Ollama defaults to /root/.ollama
        # OLLAMA_MODELS = cfg.dataDir;
        
      };

      # --- THE CRITICAL FIX ---
      # This is the declarative NixOS way to enable NVIDIA GPU access in a container.
      # It correctly mounts the drivers from the host.
      # This replaces your manual --device and --gpus flags.
      gpus.enable = cfg.enableGpu;
    };

    # This service is a clever way to pre-pull models. Let's make it more robust.
    systemd.services.ollama-pull-models = {
      description = "Download initial Ollama models";
      # This should run after the container is up and the network is ready.
      after = [ "multi-user.target" "ollama.service" ];
      wants = [ "ollama.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Prevent it from running on every single boot, only on changes.
        ExecStartPre = "/bin/sh -c 'if [ -f /var/lib/ollama-models-pulled ]; then exit 0; fi'";
        ExecStart = ''
          /bin/sh -c '
            echo "Waiting for Ollama service to be ready..."
            while ! ${pkgs.curl}/bin/curl -s http://localhost:${toString cfg.port}; do
              sleep 1
            done
            echo "Ollama service is up. Pulling models..."
            ${lib.concatMapStrings (model: ''
              echo "Pulling ${model}..."
              ${pkgs.curl}/bin/curl -X POST http://localhost:${toString cfg.port}/api/pull \
                -d '{"name": "${model}", "stream": false}'
              echo "${model} pulled."
            '' ) cfg.models}
            touch /var/lib/ollama-models-pulled
          '';
      };
    };

    # This ensures the data directory exists with the right permissions.
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    # This is correct.
    networking.firewall.allowedTCPPorts = [ cfg.port ];

    # Add your user to the 'ollama' group to allow access without sudo.
    # This is necessary if you want to use the `ollama` CLI tool directly.
    users.groups.ollama = {};
    users.users.eric.extraGroups = [ "ollama" ];
    environment.systemPackages = [ pkgs.ollama ];
  };
}
