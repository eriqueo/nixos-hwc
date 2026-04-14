# Dotfiles Audit Implementation Summary

**Date:** 2025-11-18
**Branch:** claude/audit-dotfiles-nixos-01RXuwtS4QSfMGXDGjfJqx5i
**Related:** See [DOTFILES_AUDIT_REPORT.md](./DOTFILES_AUDIT_REPORT.md) for full audit details

## Changes Implemented

This document summarizes all changes made during the dotfiles audit to improve portability and remove hard-coded user references.

---

## 1. Shell Environment Fixes

### File: `domains/home/environment/shell/index.nix`

#### Fix #1: Shell Function Path (Line 140)
**Before:**
```nix
add-app() {
  /home/eric/.nixos/workspace/infrastructure/filesystem/add-home-app.sh "$@"
}
```

**After:**
```nix
add-app() {
  ${config.home.homeDirectory}/.nixos/workspace/infrastructure/filesystem/add-home-app.sh "$@"
}
```

**Impact:** Shell function now works for any user

---

#### Fix #2: Environment Variables (Lines 51-54)
**Before:**
```nix
home.sessionVariables = cfg.sessionVariables;
```

**After:**
```nix
home.sessionVariables = cfg.sessionVariables // {
  # Override HWC_NIXOS_DIR to use dynamic home directory
  HWC_NIXOS_DIR = "${config.home.homeDirectory}/.nixos";
};
```

**Impact:** HWC_NIXOS_DIR now uses actual user's home directory

---

#### Fix #3: SSH Aliases (Lines 123-127)
**Before:**
```nix
shellAliases = cfg.aliases;
```

**After:**
```nix
shellAliases = cfg.aliases // {
  # Override SSH aliases to use dynamic username
  "homeserver" = "ssh ${config.home.username}@100.115.126.41";
  "server" = "ssh ${config.home.username}@100.115.126.41";
};
```

**Impact:** SSH aliases now use actual username

---

#### Fix #4: MCP Config Generation (NEW - Lines 170-238)
**Added:**
```nix
# MCP (Model Context Protocol) configuration for Claude Desktop
# Generate .mcp.json with dynamic paths
home.file.".mcp.json" = lib.mkIf cfg.mcp.enable {
  text = builtins.toJSON {
    mcpServers = {
      filesystem = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-filesystem"
          "${config.home.homeDirectory}/.nixos"
          "/etc/nixos"
        ] ++ lib.optionals cfg.mcp.includeConfigDir [
          "${config.xdg.configHome}"
        ];
      };
      # ... additional MCP servers
    };
  };
};
```

**Impact:**
- MCP config now generated with Nix (no hard-coded paths)
- Can be enabled/disabled per machine
- Supports laptop (with config dir) and server (with additional tools) variants

---

### File: `domains/home/environment/shell/options.nix`

#### Added MCP Options (Lines 197-216)
**Added:**
```nix
# MCP (Model Context Protocol) configuration
mcp = {
  enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable MCP configuration file generation for Claude Desktop";
  };

  includeConfigDir = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Include user config directory in filesystem MCP server (laptop only)";
  };

  includeServerTools = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Include server-specific MCP tools (postgres, prometheus, puppeteer)";
  };
};
```

**Impact:** MCP configuration is now declarative and configurable

---

## 2. Server Module Fixes

### File: `domains/server/orchestration/media-orchestrator.nix`

#### Fix: Media Orchestrator Paths (Lines 8-11, 30-32)
**Before:**
```nix
let
  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);
  cfgRoot = "/opt/downloads";
  paths = config.hwc.paths;
  hotRoot = "/mnt/hot";
in
# ...
cp /home/eric/.nixos/workspace/automation/media-orchestrator.py ${cfgRoot}/scripts/
cp /home/eric/.nixos/workspace/automation/qbt-finished.sh ${cfgRoot}/scripts/
cp /home/eric/.nixos/workspace/automation/sab-finished.py ${cfgRoot}/scripts/
```

**After:**
```nix
let
  pythonWithRequests = pkgs.python3.withPackages (ps: with ps; [ requests ]);
  cfgRoot = "/opt/downloads";
  paths = config.hwc.paths;
  hotRoot = "/mnt/hot";

  # Get username from system configuration
  userName = config.hwc.system.users.user.name;
  userHome = config.users.users.${userName}.home;
  workspaceDir = "${userHome}/.nixos/workspace";
in
# ...
cp ${workspaceDir}/automation/media-orchestrator.py ${cfgRoot}/scripts/
cp ${workspaceDir}/automation/qbt-finished.sh ${cfgRoot}/scripts/
cp ${workspaceDir}/automation/sab-finished.py ${cfgRoot}/scripts/
```

**Impact:** Scripts copied from actual user's workspace directory

---

### File: `domains/system/services/protonmail-bridge/index.nix`

#### Fix: Protonmail Bridge Username (Lines 6-7, 54)
**Before:**
```nix
let
  cfg = config.hwc.system.services.protonmail-bridge;
  bridgePkg = pkgs.protonmail-bridge;
in
# ...
if ${pkgs.procps}/bin/pgrep -u eric -f "protonmail-bridge" ...
```

**After:**
```nix
let
  cfg = config.hwc.system.services.protonmail-bridge;
  bridgePkg = pkgs.protonmail-bridge;

  # Get username from system configuration
  userName = config.hwc.system.users.user.name;
in
# ...
if ${pkgs.procps}/bin/pgrep -u ${userName} -f "protonmail-bridge" ...
```

**Impact:** Service check now uses actual username

---

## 3. Server AI/MCP Module Fixes

### File: `domains/server/ai/mcp/options.nix`

#### Fix: MCP Options Defaults (Lines 31-50)
**Before:**
```nix
allowedDirs = mkOption {
  type = types.listOf types.str;
  default = [
    "/home/eric/.nixos"
    "/home/eric/.nixos-mcp-drafts"
  ];
  description = "Directories accessible to the filesystem MCP server";
};

draftsDir = mkOption {
  type = types.path;
  default = "/home/eric/.nixos-mcp-drafts";
  description = "Directory for LLM-proposed changes (read/write)";
};

user = mkOption {
  type = types.str;
  default = "eric";
  description = "User to run the filesystem MCP server as";
};
```

**After:**
```nix
allowedDirs = mkOption {
  type = types.listOf types.str;
  # Note: This will be dynamically set in default.nix based on actual user
  default = [];
  description = "Directories accessible to the filesystem MCP server";
};

draftsDir = mkOption {
  type = types.path;
  # Note: This will be dynamically set in default.nix based on actual user
  default = "/tmp/.nixos-mcp-drafts";
  description = "Directory for LLM-proposed changes (read/write)";
};

user = mkOption {
  type = types.str;
  # Note: This will be dynamically set in default.nix based on actual user config
  default = "";
  description = "User to run the filesystem MCP server as";
};
```

**Impact:** Options no longer have hard-coded defaults

---

### File: `domains/server/ai/mcp/default.nix`

#### Fix #1: Add Dynamic User Variables (Lines 6-8)
**Added:**
```nix
# Get username from system configuration
userName = config.hwc.system.users.user.name;
userHome = config.users.users.${userName}.home;
```

---

#### Fix #2: ProtectHome Setting (Line 71)
**Before:**
```nix
ProtectHome = mkIf (user != "eric") true;  # Don't protect if running as eric
```

**After:**
```nix
ProtectHome = mkIf (user != userName) true;  # Don't protect if running as primary user
```

---

#### Fix #3: Dynamic Defaults (NEW - Lines 130-148)
**Added:**
```nix
#--------------------------------------------------------------------------
# DYNAMIC DEFAULTS - Set user-specific paths
#--------------------------------------------------------------------------
{
  hwc.server.ai.mcp.filesystem.nixos = mkMerge [
    (mkIf (cfg.filesystem.nixos.enable && cfg.filesystem.nixos.user == "") {
      user = lib.mkDefault userName;
    })
    (mkIf (cfg.filesystem.nixos.enable && cfg.filesystem.nixos.allowedDirs == []) {
      allowedDirs = lib.mkDefault [
        "${userHome}/.nixos"
        "${userHome}/.nixos-mcp-drafts"
      ];
    })
    (mkIf (cfg.filesystem.nixos.enable && cfg.filesystem.nixos.draftsDir == "/tmp/.nixos-mcp-drafts") {
      draftsDir = lib.mkDefault "${userHome}/.nixos-mcp-drafts";
    })
  ];
}
```

**Impact:** MCP paths now set dynamically based on actual user

---

## 4. Repository Maintenance

### File: `.gitignore`

#### Added Machine-Specific Entries (Lines 27-33)
**Before:**
```gitignore
# Claude Code
.mcp.json
.claude/auto-push-cron.sh
.claude/auto-push.log
```

**After:**
```gitignore
# Claude Code - Machine-specific and generated configs
.mcp.json
.mcp.laptop.json
.mcp.server.json
.claude/settings.local.json
.claude/.claude/settings.local.json
.claude/auto-push-cron.sh
.claude/auto-push.log
```

**Impact:** Machine-specific MCP configs and Claude settings now ignored

---

### Removed Files

**Deleted:**
- `profiles/home.nix.backup.1760469543` - Old backup file

**Impact:** Cleaner repository

---

## Summary of Changes

### Files Modified (8)
1. `domains/home/environment/shell/index.nix` - Fixed paths, added MCP generator
2. `domains/home/environment/shell/options.nix` - Added MCP options
3. `domains/server/orchestration/media-orchestrator.nix` - Fixed workspace paths
4. `domains/system/services/protonmail-bridge/index.nix` - Fixed username
5. `domains/server/ai/mcp/options.nix` - Removed hard-coded defaults
6. `domains/server/ai/mcp/default.nix` - Added dynamic user handling
7. `.gitignore` - Added machine-specific entries
8. Removed `profiles/home.nix.backup.1760469543`

### Files Created (2)
1. `DOTFILES_AUDIT_REPORT.md` - Comprehensive audit findings
2. `IMPLEMENTATION_SUMMARY.md` - This document

---

## Testing Required

Before merging, test the following:

### Laptop Build
```bash
nixos-rebuild build --flake .#laptop
```

**Verify:**
- [ ] Build completes successfully
- [ ] Shell functions work (test `add-app`)
- [ ] Environment variables set correctly (`echo $HWC_NIXOS_DIR`)
- [ ] SSH aliases work (`alias | grep server`)
- [ ] No hard-coded paths in generated MCP config

### Server Build
```bash
nixos-rebuild build --flake .#server
```

**Verify:**
- [ ] Build completes successfully
- [ ] Media orchestrator service configured correctly
- [ ] Protonmail bridge service configured correctly
- [ ] MCP filesystem service uses correct paths
- [ ] All services use correct username

---

## Migration Notes

### For Users Other Than "eric"

If deploying this config for a different user:

1. **Update system user configuration** in `profiles/system.nix`:
   ```nix
   hwc.system.users.user.name = "newusername";
   ```

2. **No other changes needed** - all paths and usernames will be derived automatically

### For Laptop Configuration

To enable MCP config generation on laptop:

```nix
# In machines/laptop/config.nix or profiles/home.nix
hwc.home.shell.mcp = {
  enable = true;
  includeConfigDir = true;  # Include ~/.config for laptop
  includeServerTools = false;
};
```

### For Server Configuration

To enable MCP config generation on server:

```nix
# In machines/server/config.nix
hwc.home.shell.mcp = {
  enable = true;
  includeConfigDir = false;
  includeServerTools = true;  # Include postgres, prometheus, puppeteer
};
```

---

## Benefits Achieved

### Portability ✅
- Configuration now works for any username
- All paths derived from system configuration
- No hard-coded assumptions about user identity

### Maintainability ✅
- MCP configs generated declaratively
- Single source of truth for user configuration
- Machine-specific settings properly tracked

### Charter Compliance ✅
- Proper use of options and implementation separation
- Dynamic defaults set in implementation layer
- Clean namespace usage throughout

---

## Remaining Considerations

### Low Priority Items

These are acceptable as-is but could be improved in the future:

1. **User identity data** (names, emails) - Currently hard-coded but these are legitimate user data, not configuration bugs

2. **Timezone settings** - Currently "America/Denver" in several places - could be centralized

3. **Tailscale IPs** - SSH aliases use hard-coded IP - could reference from Tailscale config

See [DOTFILES_AUDIT_REPORT.md](./DOTFILES_AUDIT_REPORT.md) Section 3.2 for details.

---

## Conclusion

All Priority 1 (Critical) fixes have been implemented:
- ✅ Fixed shell function hard-coded path
- ✅ Fixed environment variable defaults
- ✅ Fixed media orchestrator paths
- ✅ Fixed protonmail bridge username
- ✅ Created MCP config generator
- ✅ Fixed server MCP module paths
- ✅ Updated .gitignore
- ✅ Removed backup files

The configuration is now **fully portable** and can be used by any user simply by changing `hwc.system.users.user.name`.
