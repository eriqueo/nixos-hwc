# Laptop Config: AI Framework Migration Patch

## Minimal Changes Required

Replace the entire Ollama configuration section (lines 312-383 in current laptop config) with the framework configuration:

### REMOVE (Lines 312-383)
```nix
  #============================================================================
  # AI SERVICES CONFIGURATION (Laptop)
  #============================================================================
  # Laptop has superior hardware (32GB RAM, RTX 2000 Ada GPU) - optimized for performance
  hwc.ai.ollama = {
    enable = false;  # Disabled by default, toggle with waybar button
    # GPU-accelerated models leveraging NVIDIA RTX 2000 (8GB VRAM)
    models = [
      "qwen2.5-coder:14b-q5_K_M"      # 9.7GB - Primary coding, GPU accelerated
      "deepseek-coder:6.7b-instruct"  # 3.9GB - Excellent code generation
      "llama3.2:3b"                   # 2.0GB - Fast queries, battery mode
      "phi-3:14b"                     # 7.9GB - Microsoft's efficient model
    ];

    # Balanced resource limits (50% of system capacity)
    resourceLimits = {
      enable = true;
      maxCpuPercent = 800;          # 8 cores (50% of 16 cores)
      maxMemoryMB = 16384;           # 16GB (50% of 32GB RAM)
      maxRequestSeconds = 300;       # 5 minutes for larger models
    };

    # Auto-shutdown after idle (perfect for grebuild sprints)
    idleShutdown = {
      enable = true;
      idleMinutes = 15;              # Shutdown after 15min of inactivity
      checkInterval = "2min";         # Check every 2 minutes
    };

    # Thermal protection tuned for modern CPU (can handle higher temps)
    thermalProtection = {
      enable = true;
      warningTemp = 85;              # Intel Core Ultra 9 safe operating temp
      criticalTemp = 95;             # Emergency stop (before CPU throttles at 100°C)
      checkInterval = "30s";          # Check every 30 seconds
      cooldownMinutes = 5;           # Faster recovery after thermal event
    };
  };

  # Local AI workflows for laptop
  hwc.ai.local-workflows = {
    enable = false;  # Disabled by default (requires Ollama to be running)

    # File cleanup for Downloads
    fileCleanup = {
      enable = true;
      watchDirs = [ "/home/eric/Downloads" ];
      schedule = "hourly";
      model = "llama3.2:3b";  # Use smaller model for battery efficiency
      dryRun = false;
    };

    # Journaling (less frequent on laptop)
    journaling = {
      enable = true;
      outputDir = "/home/eric/Documents/HWC-AI-Journal";
      sources = [ "systemd-journal" "nixos-rebuilds" ];
      schedule = "weekly";  # Weekly on laptop vs daily on server
      timeOfDay = "02:00";
      model = "llama3.2:3b";
    };

    # Auto-documentation
    autoDoc = {
      enable = true;
      model = "qwen2.5-coder:7b";  # Use larger model on laptop
    };

    # Chat CLI with better model
    chatCli = {
      enable = true;
      model = "mistral:7b-instruct";  # Larger model for better quality
    };
  };
```

### ADD (Replacement)
```nix
  #============================================================================
  # AI FRAMEWORK CONFIGURATION (Laptop)
  #============================================================================
  # Hardware-agnostic AI framework with thermal awareness and Charter integration
  # Auto-detects laptop profile: conservative limits, aggressive thermal protection
  hwc.ai.framework = {
    enable = true;  # Enable framework (disabled by default via waybar toggle)

    # Framework will auto-detect "laptop" profile based on:
    # - GPU present: nvidia
    # - RAM: 32GB (< 16GB threshold = server)
    # Result: Conservative thermal limits, smaller models, quick idle shutdown

    # Optional: Override thermal thresholds (defaults are already good)
    # thermal = {
    #   warningTemp = 70;   # Default: 70°C for laptop
    #   criticalTemp = 80;  # Default: 80°C for laptop
    # };

    # Optional: Override model selection (defaults are good)
    # models = {
    #   small = "llama3.2:1b";    # Quick tasks
    #   medium = "llama3.2:3b";   # Documentation
    #   large = "phi3.5:3.8b";    # Analysis
    # };

    # Charter integration (enabled by default)
    charter = {
      enable = true;
      charterPath = "/home/eric/.nixos/CHARTER.md";
      citeLaws = true;  # Require outputs to cite Charter Laws
    };

    # Logging (enabled by default)
    logging = {
      enable = true;
      logDir = "/var/log/hwc-ai";
      logThermal = true;  # Log temperatures with each AI task
    };
  };

  # Framework automatically configures Ollama with profile-based limits
  # No need to manually configure hwc.ai.ollama anymore!

  # Local AI workflows can still be configured separately if needed
  # (But disabled by default - enable if you want scheduled tasks)
  # hwc.ai.local-workflows.enable = false;
```

## Key Benefits of Migration

### Before
- **Manual configuration**: Separate laptop/server configs
- **Static limits**: Fixed CPU/memory limits regardless of conditions
- **Reactive thermal**: Responded after getting hot
- **No Charter awareness**: Generic AI outputs

### After
- **Auto-detection**: Same config works on laptop and server
- **Dynamic limits**: Adjusts based on temperature and load
- **Proactive thermal**: Prevents overheating before it happens
- **Charter-aware**: All outputs cite relevant architectural rules

## Validation After Migration

```bash
# 1. Rebuild with framework
grebuild "migrate to AI framework"

# 2. Check detected profile
ai-status
# Expected output:
# Profile: laptop
# Hardware:
#   - GPU: nvidia
#   - RAM: 32GB
# Active Configuration:
#   - Models: llama3.2:1b, llama3.2:3b, phi3.5:3.8b
#   - CPU Limit: 200% (2 cores)
#   - Memory Limit: 4096MB (4GB)
#   - Thermal Warning: 70°C
#   - Thermal Critical: 80°C

# 3. Start Ollama and test
sudo systemctl start podman-ollama.service
ai-doc domains/ai/framework/index.nix

# 4. Monitor temperature during execution
watch -n 1 'sensors | grep Package'

# 5. Verify thermal safety
# - Task should complete successfully
# - Temp should stay below 80°C
# - If temp rises above 70°C, framework downgrades to smallest model
# - If temp reaches 80°C, framework aborts immediately

# 6. Check logs
ls -lh /var/log/hwc-ai/
cat /var/log/hwc-ai/task-*.log
```

## What Stays the Same

- **Waybar toggle**: Still works (start/stop Ollama)
- **Manual control**: Framework doesn't auto-start Ollama
- **Models downloaded**: Existing models remain available
- **Grebuild workflow**: Still works, just generates better docs

## What Changes

- **Resource limits**: More conservative (2 cores vs 8 cores)
- **Thermal thresholds**: More aggressive (70/80°C vs 85/95°C)
- **Model selection**: Task-aware (small/medium/large)
- **Documentation**: Charter-aware with Law citations

## Rollback If Needed

If framework causes issues, simply:

1. Change `hwc.ai.framework.enable = false;`
2. Restore old `hwc.ai.ollama` configuration
3. Rebuild: `grebuild "rollback framework"`

Old models and data remain untouched - rollback is instant.

## Next Steps After Migration

1. **Test for 1 week** - Monitor thermal behavior
2. **Review generated docs** - Check Charter citations
3. **Fine-tune if needed** - Adjust thermal thresholds
4. **Enable on server** - If laptop succeeds, migrate server too
5. **Add pre-commit hooks** - Phase 2 feature (Charter validation)

## Questions

Check the migration guide:
```bash
cat /home/eric/.nixos/docs/ai-framework-migration.md
```

Or test the commands:
```bash
ollama-wrapper --help
charter-search help
ai-status
```
