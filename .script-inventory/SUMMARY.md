# HWC NixOS Script Inventory

**Generated:** Tue Nov 25 14:53:32 EST 2025
**Repository:** /home/ubuntu/nixos-hwc

---

## Overview

| Category | Count |
|----------|-------|
| Shell Scripts (.sh) | 84 |
| Python Scripts (.py) | 114 |
| Nix Script Definitions | 2 |
| Shell Functions (in Nix) | 0 |
| Shell Aliases | 0 |
| **Total Scripts** | **198** |

---

## Executable Scripts

| Type | Executable | Non-Executable |
|------|------------|----------------|
| Shell | 74 | 10 |
| Python | 25 | 89 |

---

## Script Organization

### Top Directories (Shell Scripts)

```
## Shell Scripts by Directory
     10 /home/ubuntu/nixos-hwc/workspace/utilities/scripts
     10 /home/ubuntu/nixos-hwc/workspace/utilities/lints
      9 /home/ubuntu/nixos-hwc/workspace/network
      5 /home/ubuntu/nixos-hwc/workspace/utilities/nixos-translator/tools
      5 /home/ubuntu/nixos-hwc/workspace/utilities/monitoring
      5 /home/ubuntu/nixos-hwc/scripts
      4 /home/ubuntu/nixos-hwc/workspace/infrastructure/filesystem
      3 /home/ubuntu/nixos-hwc/workspace/utilities
      3 /home/ubuntu/nixos-hwc/workspace/infrastructure/server
```

### Top Directories (Python Scripts)

```
## Python Scripts by Directory
     29 /home/ubuntu/nixos-hwc/domains/home/apps/n8n/parts/n8n-workflows/scripts
      8 /home/ubuntu/nixos-hwc/workspace/automation/bible
      7 /home/ubuntu/nixos-hwc/workspace/utilities/nixos-translator/scanners
      7 /home/ubuntu/nixos-hwc/domains/home/apps/n8n/parts/n8n-workflows/src
      6 /home/ubuntu/nixos-hwc/workspace/projects/estimate-automation/src/models
      6 /home/ubuntu/nixos-hwc/workspace/projects/bible-plan/prompts/bible_prompts
      6 /home/ubuntu/nixos-hwc/workspace/productivity/transcript-formatter
      5 /home/ubuntu/nixos-hwc/workspace/projects/receipts-pipeline/src
      4 /home/ubuntu/nixos-hwc/workspace/utilities/graph
```

---

## Nix-Defined Scripts

These scripts are defined using `writeShellApplication` in Nix files:

```
domains/home/environment/shell/parts/grebuild.nix
domains/home/environment/shell/parts/journal-errors.nix
```

---

## Shell Functions

Functions defined in Nix `initContent`/`initExtra`:

```

```

---

## Shell Aliases

Defined aliases (first 30):

```

```



---

## Detailed Files

- **All shell scripts:** `shell-scripts.txt`
- **All Python scripts:** `python-scripts.txt`
- **Nix script definitions:** `nix-scripts.txt`
- **Shell functions:** `nix-functions.txt`
- **Aliases:** `aliases.txt`
- **Location analysis:** `location-analysis.txt`
- **Executable scripts:** `executable-shell.txt`, `executable-python.txt`

---

## Recommendations

### Script Organization Issues

1. **Scripts scattered across multiple directories**
   - workspace/automation/
   - workspace/utilities/scripts/
   - workspace/utilities/monitoring/
   - workspace/infrastructure/
   - workspace/network/

2. **Inconsistent naming**
   - Some with .sh extension, some without
   - Mix of kebab-case and snake_case

3. **Duplicate functionality**
   - Functions in Nix files vs. standalone scripts
   - Example: `grebuild` is both a Nix function and a script

### Suggested Structure

```
workspace/scripts/
├── monitoring/          # System monitoring scripts
│   ├── disk-check
│   ├── service-check
│   ├── log-check
│   └── system-health
├── maintenance/         # Maintenance and cleanup
│   ├── cleanup-logs
│   ├── update-system
│   └── backup-verify
├── development/         # Development utilities
│   ├── rebuild
│   ├── lint
│   └── test
└── utils/              # General utilities
    ├── service-status
    └── container-status
```

### Next Steps

1. **Consolidate scripts** into `workspace/scripts/`
2. **Standardize naming** (kebab-case, no .sh extension for user-facing)
3. **Create aliases** in `domains/home/environment/shell/options.nix`
4. **Remove duplicates** (choose Nix function OR script, not both)
5. **Document** which scripts are active vs. archived

