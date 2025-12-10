# HWC NixOS Script Inventory

**Generated:** Wed Dec 10 11:41:16 AM MST 2025
**Repository:** /home/eric/.nixos

---

## Overview

| Category | Count |
|----------|-------|
| Shell Scripts (.sh) | 143 |
| Python Scripts (.py) | 189 |
| Nix Script Definitions | 5 |
| Shell Functions (in Nix) | 0 |
| Shell Aliases | 0 |
| **Total Scripts** | **332** |

---

## Executable Scripts

| Type | Executable | Non-Executable |
|------|------------|----------------|
| Shell | 131 | 12 |
| Python | 47 | 142 |

---

## Script Organization

### Top Directories (Shell Scripts)

```
## Shell Scripts by Directory
     20 /home/eric/.nixos/workspace/nixos
     11 /home/eric/.nixos/workspace_fix/lints
      9 /home/eric/.nixos/workspace/monitoring
      9 /home/eric/.nixos/workspace_fix/zshrc
      9 /home/eric/.nixos/workspace_fix/network
      9 /home/eric/.nixos/workspace/diagnostics/network/network
      8 /home/eric/.nixos/workspace_fix/monitoring
      7 /home/eric/.nixos/workspace_fix/media_stack
      5 /home/eric/.nixos/workspace_fix/projects/nixos-translator/tools
```

### Top Directories (Python Scripts)

```
## Python Scripts by Directory
     29 /home/eric/.nixos/domains/home/apps/n8n/parts/n8n-workflows/scripts
      8 /home/eric/.nixos/workspace_fix/projects/bible
      8 /home/eric/.nixos/workspace/bible
      7 /home/eric/.nixos/workspace_fix/projects/nixos-translator/scanners
      7 /home/eric/.nixos/workspace/diagnostics/nixos-translator/scanners
      7 /home/eric/.nixos/domains/home/apps/n8n/parts/n8n-workflows/src
      6 /home/eric/.nixos/workspace/projects/estimate-automation/src/models
      6 /home/eric/.nixos/workspace/projects/bible-plan/prompts/bible_prompts
      6 /home/eric/.nixos/workspace_fix/projects/transcript-formatter (copy 1)
```

---

## Nix-Defined Scripts

These scripts are defined using `writeShellApplication` in Nix files:

```
domains/home/environment/shell/parts/caddy-health.nix
domains/home/environment/shell/parts/charter-lint.nix
domains/home/environment/shell/parts/grebuild.nix
domains/home/environment/shell/parts/journal-errors.nix
domains/home/environment/shell/parts/list-services.nix
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

### Script Organization (Updated 2025-12-10)

**Current Structure** (Purpose-Driven):

1. **Organized by trigger/purpose** (not arbitrary categories)
   - workspace/nixos/ - NixOS development tools
   - workspace/monitoring/ - System health checks
   - workspace/hooks/ - Event-driven automation
   - workspace/diagnostics/ - Troubleshooting tools
   - workspace/setup/ - One-time deployment
   - workspace/bible/ - Domain-specific automation
   - workspace/media/ - Media management
   - workspace/projects/ - Standalone projects

2. **Naming standards**
   - User-facing commands: via Nix wrappers (grebuild, charter-lint, etc.)
   - Implementation scripts: kebab-case with .sh/.py extensions
   - Three-tier architecture (Nix → workspace → domain)

3. **No duplicates**
   - User commands are Nix derivations wrapping workspace scripts
   - Scripts can be edited without rebuilding NixOS
   - Single canonical location per script

### Current Structure Benefits

```
workspace/
├── nixos/         # Clear: NixOS config development
├── monitoring/    # Clear: System health monitoring
├── hooks/         # Clear: Triggered by events
├── diagnostics/   # Clear: Troubleshooting
├── setup/         # Clear: One-time deployment
├── bible/         # Clear: Domain-specific
├── media/         # Clear: Media tools
└── projects/      # Clear: Standalone projects
```

vs. old ambiguous structure:
- development/ - development of what?
- automation/ - automated how?
- utilities/ - utility for what?

See workspace/README.md for full documentation.

