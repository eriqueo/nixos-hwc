# AI Framework Migration Guide

## Overview

The new AI Framework provides hardware-agnostic, thermal-aware AI capabilities for both laptop and server. It replaces manual Ollama configuration with intelligent profile-based defaults.

## Key Changes

### Before (Old Approach)
```nix
# machines/laptop/config.nix
hwc.ai.ollama = {
  enable = false;  # Manual toggle
  models = [ "qwen2.5-coder:14b" ... ];  # Hardcoded for laptop
  resourceLimits = {
    maxCpuPercent = 800;  # Manual tuning
    maxMemoryMB = 16384;
  };
  thermalProtection = {
    warningTemp = 85;
    criticalTemp = 95;
  };
};
```

### After (New Framework)
```nix
# machines/laptop/config.nix
hwc.ai.framework = {
  enable = true;  # Enable framework
  # Everything else is AUTO-DETECTED!
};
```

## What The Framework Provides

### 1. Hardware Detection
- **Auto-detects** laptop vs server vs cpu-only
- Based on: GPU presence, RAM amount, cooling capability

### 2. Profile-Based Configuration
**Laptop Profile** (auto-selected if GPU + < 16GB RAM):
- Models: `llama3.2:1b`, `llama3.2:3b`, `phi3.5:3.8b`
- CPU: 2 cores max
- Memory: 4GB max
- Thermal: 70°C warning, 80°C critical
- Idle: Shutdown after 5 minutes

**Server Profile** (auto-selected if >= 16GB RAM):
- Models: `llama3.2:3b`, `qwen2.5-coder:7b`, `qwen2.5-coder:14b`
- CPU: 4 cores max
- Memory: 8GB max
- Thermal: 80°C warning, 90°C critical
- Idle: Shutdown after 15 minutes

**CPU-Only Profile** (auto-selected if no GPU):
- Models: `llama3.2:1b` only
- CPU: 2 cores max
- Memory: 2GB max
- Conservative limits

### 3. Thermal-Aware Execution
- Monitors CPU temperature every 5 seconds during AI tasks
- Downgrades to smallest model if temp > warning
- Aborts immediately if temp > critical
- Emergency stop service runs every 10 seconds

### 4. Charter Integration
- Automatically retrieves relevant Charter sections
- Injects context into AI prompts
- Validates compliance (lint mode)
- Cites specific Laws in outputs

## New Commands Available

### `ollama-wrapper`
Core thermal-aware AI execution:
```bash
ollama-wrapper doc medium domains/ai/ollama/index.nix
ollama-wrapper commit small domains/ai/framework/options.nix
ollama-wrapper readme large domains/ai/
```

### `ai-doc`
Quick documentation generator:
```bash
ai-doc domains/ai/framework/index.nix
# Equivalent to: ollama-wrapper doc medium <file>
```

### `ai-commit`
Quick commit documentation:
```bash
ai-commit domains/ai/framework/options.nix
# Equivalent to: ollama-wrapper commit small <file>
```

### `ai-lint`
Charter compliance checker:
```bash
ai-lint domains/ai/ollama/index.nix
# Checks for Charter violations
```

### `charter-search`
Standalone Charter context tool:
```bash
charter-search search domains/ai/ollama/index.nix doc
charter-search law 2
charter-search list
charter-search validate domains/ai/ollama/options.nix
```

### `ai-status`
Framework status report:
```bash
ai-status
# Shows:
# - Detected profile (laptop/server/cpu-only)
# - Hardware (GPU, RAM)
# - Active limits
# - Current temperature
# - Ollama status
```

## Migration Steps for Laptop

### Step 1: Enable Framework (Recommended Approach)

**Option A: Framework Only (Simplest)**
```nix
# machines/laptop/config.nix

# REMOVE old Ollama config (lines 314-347)
# hwc.ai.ollama = { ... };

# ADD new framework config
hwc.ai.framework = {
  enable = true;
  # All defaults are good for laptop!
};
```

**Option B: Framework with Custom Overrides**
```nix
# machines/laptop/config.nix

hwc.ai.framework = {
  enable = true;

  # Override thermal thresholds if desired
  thermal = {
    warningTemp = 70;   # More conservative
    criticalTemp = 80;
  };

  # Override models if desired
  models = {
    small = "llama3.2:1b";
    medium = "llama3.2:3b";
    large = "phi3.5:3.8b";
  };
};

# Framework will configure Ollama automatically
# But you can still override specific Ollama settings:
hwc.ai.ollama.models = lib.mkForce [ "llama3.2:1b" "llama3.2:3b" ];
```

### Step 2: Test Configuration
```bash
# Check what profile is detected
ai-status

# Should show:
# Profile: laptop
# Hardware:
#   - GPU: nvidia
#   - RAM: 32GB
# Active Configuration:
#   - Models: llama3.2:1b, llama3.2:3b, phi3.5:3.8b
#   - CPU Limit: 200%
#   - Memory Limit: 4096MB
#   - Thermal Warning: 70°C
#   - Thermal Critical: 80°C
```

### Step 3: Rebuild and Validate
```bash
# Rebuild with framework
grebuild "enable AI framework"

# After rebuild:
ai-status  # Verify profile and limits

# Start Ollama (framework enables it by default)
sudo systemctl start podman-ollama.service

# Test thermal safety
ai-doc domains/ai/framework/index.nix
# Watch temperature: sensors | grep Package
```

## Grebuild Integration

The framework includes Charter-aware documentation generation for grebuild.

### Current Grebuild Workflow
```bash
grebuild "commit message"
# 1. Commits changes
# 2. Tests configuration
# 3. Applies rebuild
# 4. Pushes to remote (optional)
# 5. Triggers AI docs (if Ollama running)
```

### What AI Docs Generate
- Summary of changes
- Configuration changes with Charter compliance notes
- Impact analysis
- Testing recommendations
- Troubleshooting tips
- Next steps

Output saved to: `docs/ai-doc/rebuild-docs-TIMESTAMP.md`

## Thermal Safety Features

### Pre-Flight Check
Before any AI task:
1. Check CPU temperature
2. If > critical: ABORT immediately
3. If > warning: Use smallest model
4. If OK: Use appropriate model for task

### During Execution
Every 5 seconds:
1. Check temperature
2. If > critical: Kill task + stop Ollama
3. Log temperature readings

### Emergency Protection
Separate timer service runs every 10 seconds:
- Checks if Ollama is running
- Checks temperature
- If > critical: Stops Ollama immediately
- Logs emergency stops

## Troubleshooting

### Framework Not Detected
```bash
# Check if module is imported
nix-instantiate --eval -E '(import <nixpkgs/nixos> {}).config.hwc.ai.framework.enable'

# Should return: true
```

### Wrong Profile Detected
```bash
ai-status  # Shows detected profile

# Override in config.nix:
hwc.ai.framework.hardware.profile = "laptop";  # Force laptop
```

### Ollama Not Starting
```bash
# Check framework configuration
ai-status

# Check Ollama logs
journalctl -u podman-ollama.service -f

# Framework enables Ollama by default, but check:
systemctl status podman-ollama.service
```

### Tools Not Found
```bash
# Check if installed
which ollama-wrapper charter-search ai-doc

# If missing, rebuild:
grebuild "reinstall framework tools"
```

## Rollback Plan

If framework causes issues:

```nix
# machines/laptop/config.nix

# Disable framework
hwc.ai.framework.enable = false;

# Re-enable old Ollama config
hwc.ai.ollama = {
  enable = false;  # Still disabled by default
  # ... old configuration
};
```

Then rebuild:
```bash
grebuild "rollback to old Ollama config"
```

## Performance Comparison

### Old Approach
- Manual thermal management
- Hardcoded models per machine
- No Charter awareness
- Generic documentation

### New Framework
- Automatic thermal protection
- Intelligent model selection
- Charter-aware context
- Validated documentation

### Thermal Safety Improvement
- Old: Reactive (responded after overheating)
- New: Proactive (prevents overheating)

## Next Steps

1. **Enable framework on laptop** (Step 1 above)
2. **Test thermal behavior** with `ai-doc` commands
3. **Monitor for 1 week** - check logs, temperatures
4. **Enable on server** if laptop succeeds
5. **Add pre-commit hooks** (Phase 2 feature)

## Questions?

Run:
```bash
ollama-wrapper --help
charter-search help
ai-status
```

Or check logs:
```bash
ls -lh /var/log/hwc-ai/
journalctl -u ai-framework-status.service
journalctl -u ai-thermal-emergency.service
```
