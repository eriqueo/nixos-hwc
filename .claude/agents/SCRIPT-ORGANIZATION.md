# Definitive Script Organization Strategy for HWC NixOS

## Current State: The Mess

**You have 198 scripts scattered across 15+ directories.**

### The Problem

```
❌ Scripts everywhere:
   - workspace/utilities/scripts/      (10 scripts)
   - workspace/utilities/monitoring/   (5 scripts)
   - workspace/utilities/lints/        (10 scripts)
   - workspace/network/                (9 scripts)
   - workspace/infrastructure/         (7 scripts)
   - workspace/automation/             (multiple subdirs)
   - workspace/productivity/           (multiple subdirs)
   - scripts/                          (5 scripts at root)
   - domains/*/                        (scattered everywhere)

❌ Inconsistent naming:
   - grebuild.sh vs grebuild (Nix)
   - journal-errors vs journal_errors
   - disk-space-monitor.sh vs disk_check

❌ Duplicate functionality:
   - grebuild exists as BOTH Nix function AND script
   - journal-errors exists as BOTH Nix function AND script
```

---

## The Solution: Three-Tier Architecture

### Tier 1: Nix-Defined Commands (User-Facing)
**Location:** `domains/home/environment/shell/parts/`
**Purpose:** Production commands available in PATH
**Format:** `writeShellApplication` in Nix
**Naming:** No extension, kebab-case

**Examples:**
- `grebuild` - Git + rebuild workflow
- `journal-errors` - Log analysis
- `system-health` - Health check
- `service-status` - Service monitoring

**Why Nix:**
- ✅ Automatically in PATH
- ✅ Dependency management
- ✅ Proper Nix store integration
- ✅ Works across all machines
- ✅ Declarative and reproducible

### Tier 2: Workspace Scripts (Implementation)
**Location:** `workspace/scripts/`
**Purpose:** Implementation scripts, automation, development tools
**Format:** Standalone .sh or .py files
**Naming:** kebab-case with extension

**Structure:**
```
workspace/scripts/
├── monitoring/          # System monitoring
│   ├── disk-check.sh
│   ├── gpu-check.sh
│   ├── service-check.sh
│   └── log-analysis.sh
├── maintenance/         # Maintenance tasks
│   ├── cleanup-logs.sh
│   ├── backup-verify.sh
│   └── update-check.sh
├── development/         # Development utilities
│   ├── charter-lint.sh
│   ├── nix-check.sh
│   └── test-module.sh
├── automation/          # Automated workflows
│   ├── media-orchestrator.py
│   ├── qbt-finished.sh
│   └── sab-finished.py
└── utils/              # General utilities
    ├── network-diag.sh
    ├── container-status.sh
    └── secret-manager.sh
```

### Tier 3: Domain-Specific Scripts
**Location:** `domains/*/scripts/` or `domains/*/parts/`
**Purpose:** Scripts specific to a domain/service
**Format:** .sh or .py with descriptive names
**Naming:** Domain-specific, any format

**Examples:**
- `domains/server/frigate-v2/scripts/verify-config.sh`
- `domains/home/apps/n8n/parts/n8n-workflows/scripts/backup.sh`
- `domains/infrastructure/winapps/parts/vm-manager.sh`

**Keep these where they are** - they're domain-specific and belong with their service.

---

## The Decision Tree

```
Is this a command users run directly?
├─ YES → Tier 1: Nix-defined command
│         Location: domains/home/environment/shell/parts/
│         Example: grebuild, journal-errors, system-health
│
└─ NO → Is it specific to one domain/service?
        ├─ YES → Tier 3: Domain-specific script
        │         Location: domains/<domain>/scripts/
        │         Example: frigate verify-config, n8n backup
        │
        └─ NO → Tier 2: Workspace script
                  Location: workspace/scripts/<category>/
                  Example: monitoring, automation, development
```

---

## Migration Strategy

### Phase 1: Identify Your "Daily Drivers"

**These should become Tier 1 (Nix commands):**

Current candidates:
1. ✅ `grebuild` - Already Nix-defined
2. ✅ `journal-errors` - Already Nix-defined
3. ❓ `disk-space-monitor.sh` → `disk-check`
4. ❓ `systemd-failure-notifier.sh` → `service-check`
5. ❓ `list-services.sh` → `service-status`
6. ❓ `charter-lint.sh` → `lint`

**Question:** What other commands do you run multiple times per week?

### Phase 2: Consolidate Workspace Scripts

**Move these to `workspace/scripts/`:**

```bash
# Monitoring scripts
workspace/utilities/monitoring/* → workspace/scripts/monitoring/

# Development scripts
workspace/utilities/lints/* → workspace/scripts/development/

# Network scripts
workspace/network/* → workspace/scripts/utils/network/

# Infrastructure scripts (non-domain-specific)
workspace/infrastructure/filesystem/* → workspace/scripts/development/
```

### Phase 3: Clean Up Duplicates

**Current duplicates:**
- `grebuild.sh` (workspace/utilities/scripts/) vs `grebuild` (Nix)
  - **Decision:** Keep Nix version, delete script
- `journal-errors` (workspace/utilities/scripts/) vs `journal-errors` (Nix)
  - **Decision:** Keep Nix version, delete script

### Phase 4: Standardize Naming

**Rename for consistency:**

```bash
# User-facing commands (Tier 1): no extension, kebab-case
grebuild          ✅
journal-errors    ✅
disk-check        ✅ (rename from disk-space-monitor.sh)
service-check     ✅ (rename from systemd-failure-notifier.sh)

# Workspace scripts (Tier 2): with extension, kebab-case
disk-check.sh     ✅
service-check.sh  ✅
charter-lint.sh   ✅
media-orchestrator.py ✅
```

---

## Recommended Final Structure

```
/home/eric/.nixos/
│
├── domains/
│   └── home/
│       └── environment/
│           └── shell/
│               ├── index.nix
│               ├── options.nix
│               └── parts/
│                   ├── grebuild.nix          # Tier 1: User command
│                   ├── journal-errors.nix    # Tier 1: User command
│                   ├── disk-check.nix        # Tier 1: User command (NEW)
│                   ├── service-check.nix     # Tier 1: User command (NEW)
│                   └── system-health.nix     # Tier 1: User command (NEW)
│
├── workspace/
│   └── scripts/                              # Tier 2: Implementation
│       ├── monitoring/
│       │   ├── disk-check.sh                 # Implementation for disk-check
│       │   ├── service-check.sh              # Implementation for service-check
│       │   ├── gpu-monitor.sh
│       │   ├── log-analysis.sh
│       │   └── system-health.sh              # Consolidates all checks
│       ├── maintenance/
│       │   ├── cleanup-logs.sh
│       │   ├── backup-verify.sh
│       │   └── update-check.sh
│       ├── development/
│       │   ├── charter-lint.sh
│       │   ├── nix-check.sh
│       │   ├── add-home-app.sh
│       │   └── update-headers.sh
│       ├── automation/
│       │   ├── media-orchestrator.py
│       │   ├── qbt-finished.sh
│       │   └── sab-finished.py
│       └── utils/
│           ├── network/
│           │   ├── quicknet.sh
│           │   ├── netcheck.sh
│           │   └── wifi-audit.sh
│           ├── container-status.sh
│           └── secret-manager.sh
│
└── domains/                                  # Tier 3: Domain-specific
    ├── server/
    │   └── frigate-v2/
    │       └── scripts/
    │           └── verify-config.sh
    └── home/
        └── apps/
            └── n8n/
                └── parts/
                    └── n8n-workflows/
                        └── scripts/
                            └── backup.sh
```

---

## Alias Strategy

### Current State

You have aliases defined in:
- `domains/home/environment/shell/options.nix` (lines 47-155)

**Current aliases include:**
- `errors` → `journal-errors`
- `errors-hour` → `journal-errors '1 hour ago'`
- `errors-today` → `journal-errors 'today'`
- Many others (ll, la, git shortcuts, etc.)

### Recommended Additions

Add these to `domains/home/environment/shell/options.nix`:

```nix
aliases = {
  # Existing aliases...
  
  # System monitoring
  "health" = "system-health";              # NEW
  "disk" = "disk-check";                   # NEW
  "services" = "service-status";           # NEW
  "ss" = "service-status";                 # NEW (short version)
  
  # Development
  "rebuild" = "grebuild";                  # Alias for clarity
  "lint" = "charter-lint";                 # NEW
  
  # Maintenance
  "cleanup" = "cleanup-logs";              # NEW
  "backup-check" = "backup-verify";        # NEW
  
  # Existing (keep these)
  "errors" = "journal-errors";
  "errors-hour" = "journal-errors '1 hour ago'";
  "errors-today" = "journal-errors 'today'";
};
```

---

## Implementation Plan

### Step 1: Run Inventory (DONE ✅)
```bash
./workspace/utilities/scripts/script-inventory.sh
# Output: .script-inventory/SUMMARY.md
```

### Step 2: Identify Daily Drivers (YOUR INPUT NEEDED)

**Question:** Which of these do you run most often?

From existing scripts:
- [ ] `grebuild` (already Nix)
- [ ] `journal-errors` (already Nix)
- [ ] `disk-space-monitor.sh`
- [ ] `systemd-failure-notifier.sh`
- [ ] `list-services.sh`
- [ ] `charter-lint.sh`
- [ ] `caddy-health-check.sh`
- [ ] `quicknet.sh`
- [ ] Other: _______________

### Step 3: Create Nix Commands for Daily Drivers

For each daily driver, create a Nix command:

```nix
# Example: domains/home/environment/shell/parts/disk-check.nix
{ pkgs }:

pkgs.writeShellApplication {
  name = "disk-check";
  
  runtimeInputs = with pkgs; [
    coreutils
    gawk
  ];
  
  text = ''
    # Implementation here
    # Or call workspace script:
    # ${pkgs.bash}/bin/bash ~/.nixos/workspace/scripts/monitoring/disk-check.sh "$@"
  '';
}
```

Then import in `domains/home/environment/shell/index.nix`:

```nix
let
  grebuildScript = import ./parts/grebuild.nix { inherit pkgs; };
  journalErrorsScript = import ./parts/journal-errors.nix { inherit pkgs; };
  diskCheckScript = import ./parts/disk-check.nix { inherit pkgs; };  # NEW
in
{
  config = lib.mkIf cfg.enable {
    home.packages = cfg.packages
      ++ lib.optionals cfg.scripts.grebuild [ grebuildScript ]
      ++ lib.optionals cfg.scripts.journalErrors [ journalErrorsScript ]
      ++ lib.optionals cfg.scripts.diskCheck [ diskCheckScript ];  # NEW
  };
}
```

### Step 4: Add Aliases

Update `domains/home/environment/shell/options.nix`:

```nix
aliases = {
  # ... existing aliases ...
  "health" = "system-health";
  "disk" = "disk-check";
  "services" = "service-status";
};
```

### Step 5: Consolidate Workspace Scripts

```bash
# Create new structure
mkdir -p workspace/scripts/{monitoring,maintenance,development,automation,utils}

# Move monitoring scripts
mv workspace/utilities/monitoring/*.sh workspace/scripts/monitoring/

# Move development scripts
mv workspace/utilities/lints/*.sh workspace/scripts/development/

# Move network scripts
mv workspace/network/*.sh workspace/scripts/utils/network/
mkdir -p workspace/scripts/utils/network
mv workspace/network/*.sh workspace/scripts/utils/network/

# etc.
```

### Step 6: Update References

Search for hardcoded paths and update:

```bash
# Find references to old paths
grep -r "workspace/utilities/scripts" domains/
grep -r "workspace/utilities/monitoring" domains/

# Update to new paths
# workspace/utilities/scripts/ → workspace/scripts/development/
# workspace/utilities/monitoring/ → workspace/scripts/monitoring/
```

### Step 7: Test

```bash
# Rebuild
grebuild "refactor: consolidate script organization"

# Test commands
health
disk
services
errors
lint
```

---

## Decision Matrix

| Script | Current Location | Tier | New Location | Alias |
|--------|-----------------|------|--------------|-------|
| grebuild | Nix (already) | 1 | domains/home/environment/shell/parts/ | `rebuild` |
| journal-errors | Nix (already) | 1 | domains/home/environment/shell/parts/ | `errors` |
| disk-space-monitor.sh | utilities/monitoring/ | 1 | domains/home/environment/shell/parts/disk-check.nix | `disk` |
| systemd-failure-notifier.sh | utilities/monitoring/ | 1 | domains/home/environment/shell/parts/service-check.nix | `services` |
| list-services.sh | utilities/scripts/ | 1 | domains/home/environment/shell/parts/service-status.nix | `ss` |
| charter-lint.sh | utilities/lints/ | 2 | workspace/scripts/development/ | `lint` |
| media-orchestrator.py | automation/ | 2 | workspace/scripts/automation/ | - |
| quicknet.sh | network/ | 2 | workspace/scripts/utils/network/ | `netcheck` |
| frigate verify-config | domains/server/frigate-v2/ | 3 | (stay) | - |

---

## Questions for You

### 1. What are your actual daily drivers?
Which scripts do you run multiple times per week?

### 2. What should be Tier 1 (Nix commands)?
Which scripts deserve to be in PATH as first-class commands?

### 3. What's dead weight?
Which scripts/projects can be archived or deleted?

### 4. What's missing?
What functionality do you need that doesn't exist?

---

## Next Steps

1. **You tell me:** Your top 5 most-used scripts
2. **I create:** Nix command definitions for those scripts
3. **I create:** Aliases for convenient access
4. **I create:** Migration script to consolidate workspace
5. **You test:** Rebuild and verify everything works
6. **We iterate:** Based on what you actually use

**Let's start simple: What are your top 3-5 most-used scripts?**
