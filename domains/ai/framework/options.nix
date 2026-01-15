# domains/ai/framework/options.nix
#
# AI Framework - Hardware-agnostic, thermal-aware AI system
# Provides unified interface for laptop/server AI workloads
# Charter v9.1 compliant

{ lib, ... }:

{
  options.hwc.ai.framework = {
    enable = lib.mkEnableOption "AI framework with thermal awareness and Charter integration";

    # Hardware profile configuration
    hardware = {
      profile = lib.mkOption {
        type = lib.types.enum [ "auto" "laptop" "server" "cpu-only" ];
        default = "auto";
        description = ''
          Hardware profile for resource allocation:
          - auto: Detect GPU/RAM and choose appropriate limits
          - laptop: Conservative limits (thermal-aware)
          - server: Relaxed limits (assumes good cooling)
          - cpu-only: No GPU, tight memory limits
        '';
      };

      detection = {
        ramThresholdGB = lib.mkOption {
          type = lib.types.int;
          default = 16;
          description = "RAM threshold (GB) for auto-detecting server vs laptop (>= threshold = server)";
        };
      };
    };

    # Thermal safety configuration
    thermal = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable thermal monitoring and protection";
      };

      warningTemp = lib.mkOption {
        type = lib.types.int;
        default = 75;
        description = "Temperature (°C) to trigger warnings and downgrade to small models";
      };

      criticalTemp = lib.mkOption {
        type = lib.types.int;
        default = 85;
        description = "Temperature (°C) to abort AI tasks immediately";
      };

      checkInterval = lib.mkOption {
        type = lib.types.str;
        default = "15s";
        description = "How often to check CPU temperature during AI tasks";
      };

      emergencyStop = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable emergency stop of Ollama if critical temperature reached";
      };
    };

    # Charter integration configuration
    charter = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Charter-aware documentation and context injection";
      };

      searchMethod = lib.mkOption {
        type = lib.types.enum [ "ripgrep" "faiss" ];
        default = "ripgrep";
        description = ''
          Charter search method:
          - ripgrep: Fast grep-based search (good for 236-line Charter)
          - faiss: Vector DB with embeddings (future upgrade)
        '';
      };

      charterPath = lib.mkOption {
        type = lib.types.path;
        default = "/home/eric/.nixos/CHARTER.md";
        description = "Path to Charter document";
      };

      citeLaws = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Require AI outputs to cite specific Charter Laws";
      };
    };

    # Model selection by task complexity
    models = {
      small = lib.mkOption {
        type = lib.types.str;
        default = "llama3.2:1b";
        description = "Smallest model for quick lookups (1.3GB, 5W, <2s)";
      };

      medium = lib.mkOption {
        type = lib.types.str;
        default = "llama3.2:3b";
        description = "Balanced model for documentation (2GB, 10W, <10s)";
      };

      large = lib.mkOption {
        type = lib.types.str;
        default = "phi3.5:3.8b";
        description = "Quality model for complex analysis (2.3GB, 15W, <30s)";
      };
    };

    # Task-specific timeouts
    timeouts = {
      lookup = lib.mkOption {
        type = lib.types.int;
        default = 10;
        description = "Timeout (seconds) for quick lookups";
      };

      documentation = lib.mkOption {
        type = lib.types.int;
        default = 60;
        description = "Timeout (seconds) for documentation generation";
      };

      analysis = lib.mkOption {
        type = lib.types.int;
        default = 180;
        description = "Timeout (seconds) for complex code analysis";
      };
    };

    # Logging and debugging
    logging = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable framework logging";
      };

      logDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/log/hwc-ai";
        description = "Directory for framework logs";
      };

      logThermal = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Log temperature readings with each AI task";
      };
    };

    # NPU (Intel AI Boost) tier for lightweight, always-on inference
    npu = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable Tier 0 NPU inference (Intel AI Boost) for lightweight tasks";
      };

      modelId = lib.mkOption {
        type = lib.types.str;
        default = "OpenVINO/Phi-3.5-mini-instruct-int4-ov";
        description = "HuggingFace model repo to fetch the OpenVINO-optimized int4 model";
      };

      modelDir = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/hwc-ai/npu-models/phi-3.5-mini";
        description = "Local directory to cache the NPU-optimized model";
      };
    };
  };
}
