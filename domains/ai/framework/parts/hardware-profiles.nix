# domains/ai/framework/parts/hardware-profiles.nix
#
# Hardware profile definitions for AI framework
# Defines resource limits, model selection, and thermal thresholds per profile

{ config, lib }:

let
  cfg = config.hwc.ai.framework;

  # Hardware detection logic
  hasGPU = config.hwc.infrastructure.hardware.gpu.enable or false;
  gpuType = config.hwc.infrastructure.hardware.gpu.type or "none";

  # Memory detection (convert to GB)
  # Note: hardware.memorySize might not be available, so provide fallback
  totalRAM_MB = config.hardware.memorySize or 8192;  # Default to 8GB if unknown
  totalRAM_GB = totalRAM_MB / 1024;

  # Profile detection logic
  detectedProfile =
    if cfg.hardware.profile != "auto" then cfg.hardware.profile
    else if (!hasGPU) then "cpu-only"
    else if (totalRAM_GB >= cfg.hardware.detection.ramThresholdGB) then "server"
    else "laptop";

  # Profile definitions
  profiles = {
    # Laptop: Conservative, thermal-aware
    laptop = {
      description = "Laptop profile - conservative limits, aggressive thermal protection";

      # Model selection by task complexity
      models = {
        small = cfg.models.small;    # llama3.2:1b (1.3GB)
        medium = cfg.models.medium;  # llama3.2:3b (2.0GB)
        large = cfg.models.large;    # phi3.5:3.8b (2.3GB)
      };

      # Ollama resource limits
      ollama = {
        maxCpuPercent = 200;      # 2 cores max
        maxMemoryMB = 4096;       # 4GB max
        maxRequestSeconds = 60;   # 1 minute timeout
      };

      # Thermal thresholds (conservative)
      thermal = {
        warningTemp = 70;         # Start warning early
        criticalTemp = 80;        # Stop before hardware throttles
        checkInterval = "15s";    # Frequent checks
        cooldownMinutes = 10;     # Longer cooldown
      };

      # Idle behavior (save battery)
      idle = {
        enable = true;
        shutdownMinutes = 5;      # Quick shutdown
        checkInterval = "1min";   # Frequent checks
      };

      # Default to small models in thermal stress
      thermalFallback = "small";
    };

    # Server: Relaxed limits, assumes good cooling
    server = {
      description = "Server profile - relaxed limits, assumes datacenter cooling";

      # Model selection by task complexity
      models = {
        small = cfg.models.medium;   # llama3.2:3b (2.0GB) - server can handle this as "small"
        medium = "qwen2.5-coder:7b"; # 4.7GB
        large = "qwen2.5-coder:14b"; # 8.9GB (if GPU available)
      };

      # Ollama resource limits
      ollama = {
        maxCpuPercent = 400;      # 4 cores
        maxMemoryMB = 8192;       # 8GB
        maxRequestSeconds = 180;  # 3 minutes
      };

      # Thermal thresholds (relaxed)
      thermal = {
        warningTemp = 80;         # Higher warning threshold
        criticalTemp = 90;        # Server-grade cooling
        checkInterval = "30s";    # Less frequent checks
        cooldownMinutes = 5;      # Shorter cooldown
      };

      # Idle behavior (stay running)
      idle = {
        enable = true;
        shutdownMinutes = 15;     # Longer idle time
        checkInterval = "5min";   # Infrequent checks
      };

      # Fallback to medium models
      thermalFallback = "medium";
    };

    # CPU-only: No GPU, tight limits
    cpu-only = {
      description = "CPU-only profile - no GPU, minimal resource usage";

      # Model selection (smallest only)
      models = {
        small = cfg.models.small;    # llama3.2:1b
        medium = cfg.models.small;   # Force small for medium tasks too
        large = cfg.models.medium;   # Max out at 3b
      };

      # Ollama resource limits (tight)
      ollama = {
        maxCpuPercent = 200;      # 2 cores
        maxMemoryMB = 2048;       # 2GB
        maxRequestSeconds = 30;   # 30 seconds
      };

      # Thermal thresholds (conservative)
      thermal = {
        warningTemp = 75;
        criticalTemp = 85;
        checkInterval = "20s";
        cooldownMinutes = 10;
      };

      # Idle behavior (aggressive shutdown)
      idle = {
        enable = true;
        shutdownMinutes = 10;
        checkInterval = "2min";
      };

      # Always use smallest
      thermalFallback = "small";
    };
  };

  # Selected profile based on detection
  activeProfile = profiles.${detectedProfile};

in
{
  # Export detection results and profile
  inherit detectedProfile activeProfile profiles;

  # Hardware facts for debugging
  hardware = {
    hasGPU = hasGPU;
    gpuType = gpuType;
    totalRAM_GB = totalRAM_GB;
  };
}
