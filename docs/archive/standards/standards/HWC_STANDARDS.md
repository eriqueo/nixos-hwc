# HWC NixOS Repository Standards v1.0

**Last Updated:** 2025-11-19
**Status:** Active
**Scope:** All code, configuration, and documentation in nixos-hwc repository

---

## Table of Contents

1. [Path Management Standards](#1-path-management-standards)
2. [Naming Conventions](#2-naming-conventions)
3. [Module Organization](#3-module-organization)
4. [Import Patterns](#4-import-patterns)
5. [Backup & Generated Files](#5-backup--generated-files)
6. [Documentation Requirements](#6-documentation-requirements)
7. [Code Quality](#7-code-quality)
8. [Security & Secrets](#8-security--secrets)
9. [Testing & Validation](#9-testing--validation)
10. [Enforcement](#10-enforcement)

---

## 1. Path Management Standards

### 1.1 Repository Root Discovery

**STANDARD:** All scripts and programs MUST discover the repository root dynamically.

#### Shell Scripts (Bash)

**✅ REQUIRED Pattern:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Discover repository root using git
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "${HWC_NIXOS_DIR:-/etc/nixos}")"
readonly REPO_ROOT

# Discover script directory
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

**❌ FORBIDDEN:**
```bash
REPO_ROOT="/home/eric/.nixos"           # Hard-coded user path
REPO_ROOT="/etc/nixos"                  # Hard-coded system path
SCRIPT_DIR="$HOME/.nixos/scripts"       # Hard-coded relative to HOME
```

**Rationale:** Hard-coded paths break portability across machines, users, and deployment environments.

#### Python Scripts

**✅ REQUIRED Pattern:**
```python
#!/usr/bin/env python3
import os
import subprocess
from pathlib import Path

def get_repo_root() -> Path:
    """Get repository root using git."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            check=True
        )
        return Path(result.stdout.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        # Fallback to environment variable
        return Path(os.getenv("HWC_NIXOS_DIR", "/etc/nixos"))

# Usage
REPO_ROOT = get_repo_root()
SCRIPT_DIR = Path(__file__).resolve().parent
```

**❌ FORBIDDEN:**
```python
REPO_ROOT = Path("/etc/nixos")                    # Hard-coded
config_path = "/etc/nixos/config/file.yaml"       # Hard-coded
home_dir = Path("/home/eric")                     # Hard-coded user
```

### 1.2 Environment Variable Usage

**STANDARD:** Use HWC environment variables defined in `domains/system/core/paths.nix`.

**Available Variables:**
```bash
# Storage Tiers
HWC_HOT_STORAGE         # Hot storage (SSD) - NULLABLE
HWC_MEDIA_STORAGE       # Media storage (HDD) - NULLABLE
HWC_COLD_STORAGE        # Archive storage - NULLABLE
HWC_BACKUP_STORAGE      # Backup destination - NULLABLE

# System Paths
HWC_STATE_DIR           # /var/lib/hwc - Persistent data
HWC_CACHE_DIR           # /var/cache/hwc - Regeneratable cache
HWC_LOGS_DIR            # /var/log/hwc - Service logs
HWC_TEMP_DIR            # /tmp/hwc - Temporary files

# User Paths
HWC_USER_HOME           # User home directory
HWC_INBOX_DIR           # Global inbox
HWC_WORK_DIR            # Work/business area
HWC_PERSONAL_DIR        # Personal area
HWC_TECH_DIR            # Technology development
HWC_MEDIA_DIR           # Media collection
HWC_VAULTS_DIR          # Knowledge management

# Application Roots
HWC_BUSINESS_ROOT       # /opt/business
HWC_AI_ROOT             # /opt/ai
HWC_ADHD_ROOT           # /opt/adhd-tools
HWC_SURVEILLANCE_ROOT   # /opt/surveillance

# Configuration
HWC_NIXOS_DIR           # NixOS configuration root
HWC_SECRETS_SRC_DIR     # Secrets directory
HWC_SOPS_AGE_KEY        # SOPS age key file
```

**✅ REQUIRED Usage:**
```bash
# Shell - Always check nullable paths
if [[ -n "${HWC_HOT_STORAGE}" && -d "${HWC_HOT_STORAGE}" ]]; then
    DOWNLOAD_DIR="${HWC_HOT_STORAGE}/downloads"
else
    echo "ERROR: Hot storage not configured" >&2
    exit 1
fi

# Use with defaults
CONFIG_DIR="${HWC_STATE_DIR:-/var/lib/hwc}/config"
```

```python
# Python - Use with validation
import os
from pathlib import Path

hot_storage = os.getenv('HWC_HOT_STORAGE')
if not hot_storage:
    raise EnvironmentError("HWC_HOT_STORAGE not set - storage tier not configured")

download_dir = Path(hot_storage) / "downloads"
```

### 1.3 Nix Path References

**STANDARD:** Prefer config-based paths over relative file paths.

**✅ PREFERRED:**
```nix
# Use paths from hwc.paths
dataDir = "${config.hwc.paths.hot}/myservice";
configFile = "${config.hwc.paths.state}/myservice/config.yaml";
```

**⚠️ ACCEPTABLE for asset references:**
```nix
# Asset files in same repository
assetDir = ./../../../../workspace/productivity/transcript-formatter;

# But better to use:
assetDir = "${config.hwc.paths.nixos}/workspace/productivity/transcript-formatter";
```

**❌ FORBIDDEN:**
```nix
# Hard-coded absolute paths
dataDir = "/mnt/hot/myservice";
homeDir = "/home/eric";
configDir = "/etc/nixos/config";
```

### 1.4 User Home Directory

**STANDARD:** User home MUST be derived from system configuration, never hard-coded.

**✅ REQUIRED in Nix:**
```nix
# In options definition
home = lib.mkOption {
  type = lib.types.path;
  default = config.users.users.eric.home;
  defaultText = lib.literalExpression "config.users.users.eric.home";
  description = "User home directory (derived from user config)";
};
```

**✅ REQUIRED in scripts:**
```bash
# Shell - Use environment or getent
USER_HOME="${HWC_USER_HOME:-$(getent passwd eric | cut -d: -f6)}"
```

```python
# Python - Use os.path.expanduser or environment
import os
from pathlib import Path

user_home = Path(os.getenv('HWC_USER_HOME', os.path.expanduser('~eric')))
```

---

## 2. Naming Conventions

### 2.1 File Naming

**STANDARD:** Consistent naming by file type.

| File Type | Convention | Examples |
|-----------|------------|----------|
| Shell scripts | `kebab-case.sh` | `deploy-age-keys.sh`, `charter-lint.sh` |
| Python scripts | `snake_case.py` | `bible_system_installer.py`, `media_monitor.py` |
| Nix modules | `kebab-case.nix` or single word | `config.nix`, `media-orchestrator.nix` |
| Documentation | `SCREAMING_SNAKE_CASE.md` or `Title-Case.md` | `README.md`, `HWC_STANDARDS.md` |
| JSON/YAML | `kebab-case.json` | `workflow-config.json` |

**❌ FORBIDDEN:**
```
mixedCase.sh              # Wrong case for shell
Script-Name.py            # Wrong case for Python
my_nix_module.nix         # Use kebab-case for Nix
readme.txt                # Use .md for docs
```

### 2.2 Directory Naming

**STANDARD:** Consistent directory naming.

| Purpose | Convention | Examples |
|---------|------------|----------|
| Domain modules | `kebab-case` | `home/`, `server/`, `infrastructure/` |
| Application directories | `kebab-case` | `n8n-workflows/`, `transcript-formatter/` |
| Nix module subdirs | `kebab-case` or single word | `parts/`, `declarations/`, `monitoring/` |
| Workspace categories | `single-word` | `automation/`, `utilities/`, `projects/` |

**✅ REQUIRED Structure:**
```
domains/
  server/              # Domain
    monitoring/        # Service category
      parts/           # Implementation details
        metrics.nix
```

**❌ FORBIDDEN:**
```
domains/
  Server/              # Capitalized
  my_domain/           # Snake case
  mixed-Domain/        # Mixed
```

### 2.3 Variable Naming

**Shell:**
```bash
# Constants: SCREAMING_SNAKE_CASE
readonly SCRIPT_DIR="..."
readonly MAX_RETRIES=3

# Local variables: snake_case
backup_dir="/tmp/backup"
log_level="info"

# Environment variables: HWC_SCREAMING_SNAKE
export HWC_STATE_DIR="/var/lib/hwc"
```

**Python:**
```python
# Constants: SCREAMING_SNAKE_CASE
MAX_RETRIES = 3
DEFAULT_TIMEOUT = 30

# Variables: snake_case
backup_dir = Path("/tmp/backup")
log_level = "info"

# Class names: PascalCase
class BibleSystemInstaller:
    pass
```

**Nix:**
```nix
# Use camelCase for options
options.hwc.myService = {
  dataDir = lib.mkOption { ... };
  configFile = lib.mkOption { ... };
};

# Use kebab-case for attribute names in config
config.hwc.my-service = {
  data-dir = "/var/lib/my-service";
};
```

---

## 3. Module Organization

### 3.1 Directory Structure

**STANDARD:** Follow established hierarchy.

```
nixos-hwc/
├── machines/          # Machine-specific configurations
│   ├── server/
│   │   ├── config.nix       # Main configuration
│   │   └── hardware.nix     # Hardware configuration
│   └── laptop/
│       ├── config.nix
│       └── hardware.nix
│
├── profiles/          # Cross-cutting system profiles
│   ├── base.nix            # Fundamental system setup
│   ├── server.nix          # Server-specific setup
│   └── security.nix        # Security hardening
│
├── domains/           # Functional domain modules
│   ├── system/             # Core system configuration
│   │   ├── core/
│   │   │   ├── index.nix
│   │   │   ├── options.nix
│   │   │   └── paths.nix   # ⭐ Central path definitions
│   │   ├── packages/
│   │   └── services/
│   ├── server/             # Server services
│   ├── home/               # User environment
│   ├── infrastructure/     # Infrastructure services
│   └── secrets/            # Secret management
│
└── workspace/         # Development and utilities
    ├── lib/                # 🆕 Shared libraries
    │   ├── bash/           # Shell utilities
    │   └── python/         # Python utilities
    ├── scripts/            # Operational scripts
    ├── devtools/           # Development tools
    ├── automation/         # Automation scripts
    ├── projects/           # Project-specific code
    ├── backups/            # Centralized backups
    ├── build/              # Build artifacts
    ├── generated/          # Generated files
    └── logs/               # Script logs
```

### 3.2 Module File Structure

**STANDARD:** Each domain module MUST follow this pattern:

```
domains/my-domain/
├── index.nix           # Auto-imports all modules
├── options.nix         # Option definitions
├── README.md           # Module documentation
├── parts/              # Implementation details (optional)
│   ├── service-a.nix
│   └── service-b.nix
└── my-subdomain/       # Sub-modules (if needed)
    ├── index.nix
    └── options.nix
```

**✅ REQUIRED in options.nix:**
```nix
# File: domains/my-domain/options.nix
{ config, lib, pkgs, ... }:

{
  options.hwc.my-domain = {
    enable = lib.mkEnableOption "My Domain";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.state}/my-domain";
      description = "Data directory for my-domain";
    };
  };

  config = lib.mkIf config.hwc.my-domain.enable {
    # Implementation here
  };
}
```

### 3.3 Charter Headers

**STANDARD:** All Nix modules MUST include charter header.

**✅ REQUIRED Template:**
```nix
# HWC Charter Module/path/to/module.nix
#
# SERVICE NAME - Brief service description
#
# DEPENDENCIES (Upstream):
#   - config.hwc.paths.* (domains/system/core/paths.nix)
#   - config.hwc.secrets.* (domains/secrets/index.nix)
#
# USED BY (Downstream):
#   - profiles/*.nix (enables via hwc.service-name.enable)
#   - domains/other/module.nix (uses data from this service)
#
# IMPORTS REQUIRED IN:
#   - profiles/base.nix: ../domains/my-domain/index.nix
#
# USAGE:
#   hwc.my-service.enable = true;
#   hwc.my-service.dataDir = "/custom/path";

{ config, lib, pkgs, ... }:
# Module implementation...
```

---

## 4. Import Patterns

### 4.1 Nix Module Imports

**STANDARD:** Prefer absolute imports over relative when possible.

**✅ PREFERRED (via index.nix auto-import):**
```nix
# machines/server/config.nix
{
  imports = [
    ../../profiles/base.nix
    ../../profiles/server.nix
    ../../domains/server/routes.nix
  ];
}
```

**✅ ACCEPTABLE (for closely related modules):**
```nix
# domains/home/mail/msmtp/parts/render.nix
let
  common = import ../../parts/common.nix { inherit lib; };
in
# ...
```

**❌ DISCOURAGED (deep relative imports):**
```nix
# Fragile - breaks if file is moved
palette = import ../../../../../../../theme/palettes/deep-nord.nix {};
```

**✅ BETTER (use config reference):**
```nix
# Define in domains/home/theme/index.nix:
config.hwc.theme.palettes.deep-nord = import ./palettes/deep-nord.nix {};

# Then use everywhere:
palette = config.hwc.theme.palettes.deep-nord;
```

### 4.2 Python Module Imports

**STANDARD:** Use absolute imports with proper path setup.

**✅ REQUIRED:**
```python
#!/usr/bin/env python3
import sys
from pathlib import Path

# Add library to path if needed
lib_path = Path(__file__).parents[3] / "workspace" / "lib" / "python"
if lib_path.exists():
    sys.path.insert(0, str(lib_path))

# Now use absolute imports
from hwc_paths import get_repo_root, get_hwc_path
```

**❌ FORBIDDEN:**
```python
# Hard-coded sys.path
sys.path.append("/etc/nixos/workspace/lib")

# Relative imports without package structure
from ...lib import utils  # Won't work
```

### 4.3 Shell Script Sourcing

**STANDARD:** Source shared libraries with fallback.

**✅ REQUIRED:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Source path utilities with fallback
UTIL_LIB="${HWC_NIXOS_DIR:-/etc/nixos}/workspace/lib/bash/path-utils.sh"
if [[ -f "$UTIL_LIB" ]]; then
    source "$UTIL_LIB"
else
    echo "WARNING: path-utils.sh not found, using fallback" >&2
    # Inline fallback functions
    get_repo_root() { git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"; }
fi

readonly REPO_ROOT="$(get_repo_root)"
```

---

## 5. Backup & Generated Files

### 5.1 Timestamp Format

**STANDARD:** Use ISO 8601-like format: `YYYYMMDD_HHMMSS`

**✅ REQUIRED:**
```bash
# Shell
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

# File naming
backup_file="mycomponent.backup.${TIMESTAMP}.tar.gz"
log_file="script.${TIMESTAMP}.log"
```

```python
# Python
from datetime import datetime

timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
backup_file = f"mycomponent.backup.{timestamp}.tar.gz"
```

**❌ FORBIDDEN:**
```bash
# Non-sortable formats
date +%m/%d/%Y           # Uses slashes
date +%Y-%m-%d           # Uses dashes in YYYYMMDD (inconsistent)

# Ambiguous formats
date +%d%m%y             # Two-digit year

# Files without timestamps
file.bak
file.backup
file.old
```

### 5.2 Backup Directory Structure

**STANDARD:** All backups MUST go to centralized locations.

**✅ REQUIRED Locations:**
```
workspace/
├── backups/                    # Application/component backups
│   ├── n8n-workflows/
│   │   └── workflows.backup.20241119_143022.tar.gz
│   ├── bible-system/
│   └── .gitkeep
│
├── build/                      # Build artifacts
│   ├── project-name/
│   └── .gitkeep
│
├── generated/                  # Generated configuration files
│   ├── script-name/
│   └── .gitkeep
│
└── logs/                       # Script execution logs
    ├── deployment/
    ├── automation/
    └── .gitkeep
```

**✅ REQUIRED in Scripts:**
```bash
# Create component-specific backup directory
COMPONENT="bible-system"
BACKUP_DIR="${HWC_NIXOS_DIR}/workspace/backups/${COMPONENT}"
mkdir -p "$BACKUP_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_FILE="${BACKUP_DIR}/${COMPONENT}.backup.${TIMESTAMP}.tar.gz"

# Create backup
tar -czf "$BACKUP_FILE" -C "$SOURCE_DIR" .

# Cleanup old backups (keep last 10)
find "$BACKUP_DIR" -name "${COMPONENT}.backup.*.tar.gz" -type f -printf '%T@ %p\n' | \
    sort -rn | tail -n +11 | cut -d' ' -f2- | xargs rm -f
```

### 5.3 .gitignore Requirements

**STANDARD:** Generated files MUST be gitignored.

**✅ REQUIRED in .gitignore:**
```gitignore
# Build artifacts
workspace/build/**
!workspace/build/.gitkeep

# Generated files
workspace/generated/**
!workspace/generated/.gitkeep

# Backups
workspace/backups/**
!workspace/backups/.gitkeep

# Logs
workspace/logs/**
!workspace/logs/.gitkeep

# Timestamp patterns
*.backup.*
*.log.[0-9]*
*.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].*

# Home Manager backups
*.backup
*.bak
```

---

## 6. Documentation Requirements

### 6.1 README Files

**STANDARD:** Each major directory MUST have a README.md.

**✅ REQUIRED Locations:**
- `README.md` (repository root)
- `domains/*/README.md` (each domain)
- `workspace/*/README.md` (each workspace category)
- `docs/README.md` (documentation index)

**✅ REQUIRED Structure:**
```markdown
# Component Name

Brief description (1-2 sentences).

## Purpose

What this component does and why it exists.

## Dependencies

- Upstream dependency 1
- Upstream dependency 2

## Usage

```nix
# Example configuration
hwc.component.enable = true;
```

## File Structure

- `file1.nix` - Description
- `file2.nix` - Description

## Related Documentation

- [Related Doc 1](../path/to/doc.md)
```

### 6.2 Code Comments

**STANDARD:** All non-trivial code MUST have explanatory comments.

**✅ REQUIRED in Shell:**
```bash
#!/usr/bin/env bash
# Brief script description
#
# Usage: script-name.sh [options]
# Options:
#   -h, --help    Show this help
#
# Environment variables:
#   HWC_NIXOS_DIR   Repository root (default: /etc/nixos)

set -euo pipefail

# Function documentation
# Args:
#   $1 - Source directory
#   $2 - Destination directory
backup_directory() {
    local src="$1"
    local dst="$2"

    # Implementation...
}
```

**✅ REQUIRED in Python:**
```python
#!/usr/bin/env python3
"""
Brief module description.

This module provides functionality for...

Usage:
    python script.py --option value

Environment Variables:
    HWC_NIXOS_DIR: Repository root directory
"""

import os
from pathlib import Path

def backup_directory(src: Path, dst: Path) -> bool:
    """
    Backup a directory to destination.

    Args:
        src: Source directory path
        dst: Destination directory path

    Returns:
        True if successful, False otherwise

    Raises:
        ValueError: If source doesn't exist
    """
    # Implementation...
```

**✅ REQUIRED in Nix:**
```nix
# Function or option documentation
services.myservice = {
  dataDir = lib.mkOption {
    type = lib.types.path;
    default = "${config.hwc.paths.state}/myservice";
    description = ''
      Data directory for myservice.

      This directory stores persistent data including:
      - Configuration files
      - Database files
      - Cache data
    '';
    example = "/mnt/hot/myservice";
  };
};
```

---

## 7. Code Quality

### 7.1 Shell Script Requirements

**STANDARD:** All shell scripts MUST follow these rules.

**✅ REQUIRED Header:**
```bash
#!/usr/bin/env bash
set -euo pipefail
```

**Explanation:**
- `-e` - Exit on error
- `-u` - Error on undefined variable
- `-o pipefail` - Pipeline fails if any command fails

**✅ REQUIRED Function Format:**
```bash
# Function name: verb_noun
create_backup() {
    local src="$1"
    local dst="$2"

    # Validate inputs
    [[ -d "$src" ]] || { echo "Source not found: $src" >&2; return 1; }

    # Implementation...
}
```

**❌ FORBIDDEN:**
```bash
#!/bin/bash              # Use #!/usr/bin/env bash
# No set -e             # Always use set -euo pipefail
function backup { }     # Use name() { } not function name { }
$variable               # Use "$variable" (quoted)
```

### 7.2 Python Script Requirements

**STANDARD:** All Python scripts MUST follow PEP 8.

**✅ REQUIRED:**
```python
#!/usr/bin/env python3
"""Module docstring."""

import sys           # Standard library
import os
from pathlib import Path

import requests      # Third-party
import yaml

from hwc_paths import get_repo_root  # Local imports

# Constants
MAX_RETRIES = 3
DEFAULT_TIMEOUT = 30

# Type hints required for functions
def process_file(input_path: Path, output_path: Path) -> bool:
    """Process file from input to output."""
    # Implementation...
    return True

# Main guard
if __name__ == "__main__":
    main()
```

### 7.3 Nix Module Requirements

**STANDARD:** Follow NixOS module conventions.

**✅ REQUIRED:**
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.myservice;
in {
  # Options section
  options.hwc.myservice = {
    enable = lib.mkEnableOption "My Service";

    # Use appropriate types
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Service port";
    };

    # Paths should reference hwc.paths
    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.state}/myservice";
      description = "Data directory";
    };
  };

  # Config section with conditional
  config = lib.mkIf cfg.enable {
    # Implementation...
  };
}
```

---

## 8. Security & Secrets

### 8.1 Secret Management

**STANDARD:** All secrets MUST use SOPS/age encryption.

**✅ REQUIRED:**
```nix
# Declare secrets in domains/secrets/declarations/
sops.secrets."myservice/api-key" = {
  sopsFile = ./secrets.yaml;
  owner = "myservice";
  mode = "0400";
};

# Reference in service config
services.myservice = {
  apiKeyFile = config.sops.secrets."myservice/api-key".path;
};
```

**❌ FORBIDDEN:**
```nix
# Hard-coded secrets
apiKey = "sk-1234567890abcdef";

# Plain text files
apiKeyFile = "/etc/myservice/api-key.txt";

# Environment variables with secrets
environment.variables.API_KEY = "secret";
```

### 8.2 File Permissions

**STANDARD:** Sensitive files MUST have restrictive permissions.

**✅ REQUIRED:**
```bash
# Secret files: 0400 (read-only for owner)
chmod 0400 secret-file

# Config files: 0600 (read-write for owner)
chmod 0600 config-file

# Directories: 0700 (rwx for owner only)
chmod 0700 config-dir
```

---

## 9. Testing & Validation

### 9.1 Pre-Deployment Checks

**STANDARD:** All changes MUST pass validation before deployment.

**✅ REQUIRED before `nixos-rebuild switch`:**
```bash
# 1. Syntax check
nix flake check

# 2. Build check
nixos-rebuild build --flake .#hwc-server

# 3. Test (dry activation)
sudo nixos-rebuild test --flake .#hwc-server

# 4. If all pass, then switch
sudo nixos-rebuild switch --flake .#hwc-server
```

### 9.2 Script Testing

**STANDARD:** Scripts MUST handle errors gracefully.

**✅ REQUIRED Error Handling:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Check prerequisites
command -v git >/dev/null 2>&1 || {
    echo "ERROR: git not found in PATH" >&2
    exit 1
}

# Validate environment
: "${HWC_NIXOS_DIR:?HWC_NIXOS_DIR not set - are you in a NixOS environment?}"

# Function with error handling
process_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    # Process...
}

# Trap for cleanup
cleanup() {
    local exit_code=$?
    # Cleanup temporary files
    [[ -n "${TEMP_DIR:-}" ]] && rm -rf "$TEMP_DIR"
    exit $exit_code
}
trap cleanup EXIT INT TERM
```

---

## 10. Enforcement

### 10.1 Pre-Commit Checks

**STANDARD:** Use pre-commit hooks to enforce standards.

**✅ RECOMMENDED `.git/hooks/pre-commit`:**
```bash
#!/usr/bin/env bash
set -e

echo "Running HWC standards checks..."

# Check for hard-coded paths
if git diff --cached | grep -E '"/etc/nixos|/home/eric'; then
    echo "ERROR: Hard-coded paths detected" >&2
    echo "Use HWC_NIXOS_DIR and HWC_USER_HOME instead" >&2
    exit 1
fi

# Check shell script headers
for file in $(git diff --cached --name-only | grep '\.sh$'); do
    if ! head -n2 "$file" | grep -q 'set -euo pipefail'; then
        echo "ERROR: $file missing 'set -euo pipefail'" >&2
        exit 1
    fi
done

# Check Python script headers
for file in $(git diff --cached --name-only | grep '\.py$'); do
    if ! head -n1 "$file" | grep -q '#!/usr/bin/env python3'; then
        echo "ERROR: $file missing proper shebang" >&2
        exit 1
    fi
done

echo "Standards checks passed ✓"
```

### 10.2 Compliance Auditing

**STANDARD:** Regular compliance audits MUST be performed.

**✅ REQUIRED:**
- Monthly: Run compliance audit
- Before major releases: Full standards review
- After structural changes: Validate all affected files

**Audit Command:**
```bash
# Run standards compliance audit
./workspace/devtools/lints/standards-audit.sh
```

### 10.3 Exception Process

**STANDARD:** Standards exceptions MUST be documented.

**✅ REQUIRED for exceptions:**
```nix
# STANDARDS EXCEPTION: Hard-coded path required for NixOS limitation
# Reason: NixOS doesn't support dynamic paths for hardware.configuration
# Date: 2024-11-19
# Reviewer: Eric
hardware.nvidia.package = /nix/store/specific-path;
```

---

## Appendix A: Quick Reference

### Path Standards

| Context | Required Pattern |
|---------|------------------|
| Shell repo root | `REPO_ROOT="$(git rev-parse --show-toplevel)"` |
| Shell script dir | `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` |
| Python repo root | `get_repo_root()` from `hwc_paths.py` |
| Python script dir | `Path(__file__).resolve().parent` |
| Nix paths | Use `config.hwc.paths.*` |
| User home | Use `config.users.users.eric.home` or `$HWC_USER_HOME` |

### Naming Standards

| Item | Convention |
|------|------------|
| Shell scripts | `kebab-case.sh` |
| Python scripts | `snake_case.py` |
| Nix modules | `kebab-case.nix` |
| Directories | `kebab-case` or `singleword` |
| Shell variables | `snake_case` |
| Shell constants | `SCREAMING_SNAKE_CASE` |
| Python variables | `snake_case` |
| Python constants | `SCREAMING_SNAKE_CASE` |
| Python classes | `PascalCase` |
| Nix options | `camelCase` |

### File Locations

| Purpose | Location |
|---------|----------|
| Shared bash libs | `workspace/lib/bash/` |
| Shared python libs | `workspace/lib/python/` |
| Operational scripts | `workspace/scripts/` |
| Development tools | `workspace/devtools/` |
| Backups | `workspace/backups/<component>/` |
| Generated files | `workspace/generated/<script>/` |
| Build artifacts | `workspace/build/<project>/` |
| Script logs | `workspace/logs/<category>/` |

---

## Appendix B: Migration Guide

For existing code that doesn't meet standards:

1. **Identify violations** using compliance audit tool
2. **Prioritize fixes** by severity (Critical > High > Medium > Low)
3. **Create utility libraries** first (`workspace/lib/`)
4. **Update scripts** to use utilities
5. **Test thoroughly** before committing
6. **Document exceptions** if standards cannot be met

---

**Document Version:** 1.0
**Effective Date:** 2025-11-19
**Next Review:** 2025-12-19
