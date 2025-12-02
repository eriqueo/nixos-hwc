# Script Dependency Verification Template

## Purpose

Standardized pattern for verifying script dependencies. Use this for all scripts in `workspace/scripts/`.

## When to Use Dependency Verification

### ✅ Always Include
- Script header with dependencies documented
- Exit code 127 for missing dependencies (standard "command not found")

### ✅ Add Verification For
- **Complex scripts** with multiple dependencies
- **Scripts using non-standard tools** (not guaranteed on NixOS)
- **Scripts for export** to other machines
- **Critical scripts** where failure is costly

### ⚠️ Optional For
- **Simple scripts** with 1-2 standard commands
- **Scripts using only coreutils** (always available)

## Standard Template

### For Scripts with Standard Dependencies

```bash
#!/usr/bin/env bash
# script-name - Brief description
#
# Usage: script-name [args]
#
# Dependencies: git, curl, jq (standard on NixOS)
# Location: workspace/scripts/category/script-name.sh
# Invoked by: Shell function in domains/home/environment/shell/index.nix

set -euo pipefail

#==============================================================================
# DEPENDENCY VERIFICATION
#==============================================================================
# Standard tools - should always exist on NixOS, but verify for robustness

REQUIRED_COMMANDS=(git curl jq)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: Required command '$cmd' not found" >&2
    echo "This should not happen on a standard NixOS system." >&2
    exit 127
  fi
done

#==============================================================================
# CONFIGURATION
#==============================================================================

# Your config here...

#==============================================================================
# MAIN LOGIC
#==============================================================================

# Your script here...
```

### For Scripts with Exotic Dependencies

```bash
#!/usr/bin/env bash
# video-processor - Process videos with ffmpeg
#
# Usage: video-processor input.mp4 output.mp4
#
# Dependencies:
#   - ffmpeg (NOT standard - must be installed)
#   - imagemagick (NOT standard - must be installed)
#   - python3 with opencv (NOT standard - must be installed)
# Location: workspace/scripts/media/video-processor.sh

set -euo pipefail

#==============================================================================
# DEPENDENCY VERIFICATION
#==============================================================================
# Exotic tools - NOT guaranteed on NixOS, must verify

REQUIRED_COMMANDS=(ffmpeg convert python3)

missing_deps=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "$cmd" &>/dev/null; then
    missing_deps+=("$cmd")
  fi
done

if [ ${#missing_deps[@]} -gt 0 ]; then
  echo "Error: Missing required dependencies:" >&2
  for dep in "${missing_deps[@]}"; do
    echo "  - $dep" >&2
  done
  echo "" >&2
  echo "Install with: nix-shell -p ffmpeg imagemagick python312Packages.opencv" >&2
  exit 127
fi

# Verify Python packages
if ! python3 -c "import cv2" 2>/dev/null; then
  echo "Error: Python opencv package not found" >&2
  echo "Install with: nix-shell -p python312Packages.opencv" >&2
  exit 127
fi

#==============================================================================
# MAIN LOGIC
#==============================================================================

# Your script here...
```

### For Simple Scripts (Minimal Verification)

```bash
#!/usr/bin/env bash
# simple-script - Does something simple
#
# Usage: simple-script
#
# Dependencies: None (uses only bash builtins)
# Location: workspace/scripts/utils/simple-script.sh

set -euo pipefail

# No dependency verification needed for bash builtins

echo "Hello, worl
