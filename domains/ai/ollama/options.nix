{ lib, ... }:

{
  options.hwc.ai.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port for the Ollama service";
    };

    models = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            description = "Model name in Ollama format (e.g., llama3.2:3b)";
          };
          autoUpdate = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Automatically update this model on rebuilds";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = 50;
            description = "Pull priority (lower = pulled first, useful for dependencies)";
          };
        };
      }));
      default = [ "llama3:8b" "codellama:13b" ];
      description = ''
        Models to pre-download and keep available.
        Can be either strings (e.g., "llama3:8b") or attribute sets with configuration:
        { name = "llama3.2:3b"; autoUpdate = false; priority = 10; }
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ollama";
      description = "Directory for storing Ollama models";
    };

    healthCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable health check for Ollama service";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5min";
        description = "Health check interval (systemd time format)";
      };
    };

    modelValidation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Validate models after pull by testing inference";
      };

      testPrompt = lib.mkOption {
        type = lib.types.str;
        default = "Hello";
        description = "Test prompt to verify model loads correctly";
      };
    };

    modelHealth = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable periodic model health checks";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Time to run model health checks (HH:MM format)";
      };
    };

    diskMonitoring = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable disk space monitoring for model storage";
      };

      warningThreshold = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Disk usage percentage to trigger warning (default: 80%)";
      };

      criticalThreshold = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Disk usage percentage to trigger critical alert (default: 90%)";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "6h";
        description = "Disk space check interval (systemd time format)";
      };
    };

    resourceLimits = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable resource limits to prevent runaway CPU/memory usage";
      };

      maxCpuPercent = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Maximum CPU usage percentage (100 = 1 core, 200 = 2 cores, etc.)
          null = unlimited (server default), set to 200-400 for laptop
        '';
      };

      maxMemoryMB = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Maximum memory in MB
          null = unlimited (server default), set to 4096-8192 for laptop
        '';
      };

      maxRequestSeconds = lib.mkOption {
        type = lib.types.int;
        default = 600;
        description = ''
          Maximum seconds for a single request before killing it
          Server: 600s (10min), Laptop: 180s (3min) recommended
        '';
      };
    };

    idleShutdown = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Auto-stop ollama service after idle timeout
          Recommended: true for laptop, false for server
        '';
      };

      idleMinutes = lib.mkOption {
        type = lib.types.int;
        default = 15;
        description = "Minutes of inactivity before shutting down";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "2min";
        description = "How often to check for idle state";
      };
    };

    thermalProtection = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Monitor CPU temperature and throttle/stop ollama if too hot
          Recommended: true for laptop, false for server (if datacenter cooling)
        '';
      };

      warningTemp = lib.mkOption {
        type = lib.types.int;
        default = 80;
        description = "Temperature (°C) to start throttling ollama (pause new requests)";
      };

      criticalTemp = lib.mkOption {
        type = lib.types.int;
        default = 90;
        description = "Temperature (°C) to immediately stop ollama";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "How often to check CPU temperature";
      };

      cooldownMinutes = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Minutes to wait after thermal shutdown before allowing restart";
      };
    };
  };
}