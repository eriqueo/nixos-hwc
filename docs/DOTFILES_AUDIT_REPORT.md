# Dotfiles and User Configuration Audit Report

**Repository:** eriqueo/nixos-hwc
**Date:** 2025-11-18
**Auditor:** Claude
**Branch:** claude/audit-dotfiles-nixos-01RXuwtS4QSfMGXDGjfJqx5i

---

## Executive Summary

The nixos-hwc repository demonstrates **excellent dotfile management practices** with:

- ✅ **100% declarative configuration** - All dotfiles managed through Nix/Home Manager
- ✅ **Charter v6.0 compliance** - Clean domain-based architecture
- ✅ **27 applications configured** - Comprehensive coverage of CLI and GUI tools
- ✅ **Clear laptop/server separation** - Proper use of machine-level overrides
- ⚠️ **Minor parameterization issues** - Some hard-coded user references need cleanup

**Overall Grade:** A- (Excellent with room for minor improvements)

---

## 1. Dotfile Management Assessment

### 1.1 Home Manager Coverage

**All dotfiles are managed by Home Manager.** No manually managed config files found.

#### Shell & Environment (10 applications)
| Tool | Config Method | Status |
|------|---------------|--------|
| Zsh | `programs.zsh` | ✅ Fully managed |
| Starship | `programs.starship` | ✅ Fully managed |
| Git | `programs.git` | ✅ Fully managed |
| Neovim | `programs.neovim` | ✅ Fully managed |
| Tmux | `programs.tmux` | ✅ Fully managed |
| Micro | `programs.micro` | ✅ Fully managed |
| Direnv | `programs.direnv` | ✅ Fully managed |
| Fzf | `programs.fzf` | ✅ Fully managed |
| Bat | `programs.bat` | ✅ Fully managed |
| Zoxide | `programs.zoxide` | ✅ Fully managed |

#### Desktop Environment (7 applications)
| Tool | Config Files | Method | Status |
|------|--------------|--------|--------|
| Hyprland | `~/.config/hypr/*` | `wayland.windowManager.hyprland` | ✅ Fully managed |
| Waybar | `~/.config/waybar/*` | `programs.waybar.settings` | ✅ Fully managed |
| Kitty | `~/.config/kitty/kitty.conf` | `programs.kitty` | ✅ Fully managed |
| SwayNC | `~/.config/swaync/*` | `services.swaync` | ✅ Fully managed |
| Yazi | `~/.config/yazi/*` | `xdg.configFile` | ✅ Fully managed |
| Thunar | `~/.config/xfce4/helpers.rc` | `xdg.configFile` | ✅ Fully managed |
| GTK | `~/.config/gtk-{3,4}.0/gtk.css` | `xdg.configFile` | ✅ Fully managed |

#### Mail System (6 components)
| Component | Config Files | Status |
|-----------|--------------|--------|
| Aerc | `~/.config/aerc/*` | ✅ Declarative with runtime activation |
| Neomutt | `~/.config/neomutt/neomuttrc` | ✅ Fully managed |
| Betterbird | `~/.betterbird/profile/*` | ✅ Profile generation via Nix |
| Mbsync | `~/.mbsyncrc` | ✅ Fully managed |
| Msmtp | `~/.config/msmtp/config` | ✅ Fully managed |
| Notmuch | `~/.notmuch-config` | ✅ Fully managed |

### 1.2 Files Not Managed by Home Manager

**None found.** All configuration is declarative.

**Workspace files** (scripts, automation) are **intentionally unmanaged** and properly excluded:
- `workspace/automation/` - Runtime scripts (copied to service directories)
- `workspace/infrastructure/` - Development tooling
- `workspace/network/` - Network testing tools
- `workspace/projects/` - Personal projects (site-crawler, bible-plan)

**Recommendation:** ✅ Current approach is correct. These are either:
1. Runtime data (not configuration)
2. Development tools (not deployment configuration)
3. Personal projects (should remain in workspace)

---

## 2. Configuration Duplication Analysis

### 2.1 Laptop vs Server Configuration

**Differentiation Method:** Machine-level overrides with shared base configuration.

#### Shared Configuration ✅
Both laptop and server share:
- Core shell environment (Zsh, Starship, Git, Tmux)
- Development tools (Neovim, language toolchains)
- CLI utilities (Bat, Eza, Fzf, Ripgrep)
- Security tools (GPG, SSH)
- Theme system (palettes, fonts)

#### Laptop-Specific Configuration ✅
```nix
# machines/laptop/config.nix
hwc.home.apps = {
  hyprland.enable = true;     # Desktop environment
  waybar.enable = true;        # Status bar
  kitty.enable = true;         # Terminal
  chromium.enable = true;      # Browser
  betterbird.enable = true;    # Mail client
  obsidian.enable = true;      # Notes
  # ... 15+ GUI applications
};
```

#### Server-Specific Overrides ✅
```nix
# machines/server/config.nix:252-310
home-manager.users.eric = {
  # Disable all GUI apps
  hwc.home.apps.hyprland.enable = lib.mkForce false;
  hwc.home.apps.waybar.enable = lib.mkForce false;
  hwc.home.apps.kitty.enable = lib.mkForce false;
  # ... (disables 20+ GUI apps)

  # Keep CLI tools
  hwc.home.apps.aerc.enable = true;      # TUI mail
  hwc.home.apps.yazi.enable = true;      # TUI file manager
  hwc.home.shell.enable = true;          # Shell environment

  # Disable mail system (server uses API access)
  hwc.home.mail.enable = lib.mkForce false;
  hwc.home.fonts.enable = lib.mkForce false;
};
```

**Assessment:** ✅ **Excellent architecture.** No unnecessary duplication. Proper use of:
- Shared base in `profiles/home.nix`
- Machine-specific overrides
- Clean separation of concerns

### 2.2 Potential Optimizations

**No significant duplication found.** Configuration is well-organized with:
- Shared profiles for common configuration
- Machine-specific overrides for differences
- Proper domain boundaries

---

## 3. Hard-Coded User References

### 3.1 Critical Issues (Require Fixes)

#### Issue #1: Hard-coded Path in Shell Function
**Location:** `domains/home/environment/shell/index.nix:140`

```nix
# CURRENT (BROKEN)
add-app() {
  /home/eric/.nixos/workspace/infrastructure/filesystem/add-home-app.sh "$@"
}
```

**Impact:** Breaks portability, fails for other users
**Severity:** HIGH
**Fix:**
```nix
# RECOMMENDED
add-app() {
  ${config.home.homeDirectory}/.nixos/workspace/infrastructure/filesystem/add-home-app.sh "$@"
}
```

---

#### Issue #2: Hard-coded Username in home-manager.users
**Locations:**
- `flake.nix:94` - `home-manager.users.eric.home.stateVersion`
- `profiles/home.nix:12` - `users.eric = {`
- `machines/server/config.nix:252` - `home-manager.users.eric = {`
- `profiles/system.nix:188` - `name = "eric";`

**Impact:** Configuration tied to specific username
**Severity:** MEDIUM
**Fix:** Reference `config.hwc.system.users.user.name` instead

```nix
# RECOMMENDED
let
  userName = config.hwc.system.users.user.name;
in {
  home-manager.users.${userName} = {
    imports = [ ../domains/home/index.nix ];
    # ...
  };
}
```

---

#### Issue #3: Hard-coded Paths in MCP Configuration
**Locations:**
- `.mcp.laptop.json` (lines 8, 10, 16)
- `.mcp.server.json` (lines 8, 15)

```json
// CURRENT (BROKEN)
{
  "allowed_directories": [
    "/home/eric/.nixos",
    "/home/eric/.config"
  ],
  "cwd": "/home/eric/.nixos"
}
```

**Impact:** MCP tools fail for other users
**Severity:** HIGH
**Fix:** Generate these files with Nix

```nix
# RECOMMENDED - Add to domains/home/apps/
xdg.configFile."mcp.laptop.json".text = builtins.toJSON {
  allowed_directories = [
    "${config.home.homeDirectory}/.nixos"
    "${config.xdg.configHome}"
  ];
  cwd = "${config.home.homeDirectory}/.nixos";
  # ... rest of config
};
```

---

#### Issue #4: Hard-coded Path in Shell Options
**Location:** `domains/home/environment/shell/options.nix:42`

```nix
# CURRENT (BROKEN)
HWC_NIXOS_DIR = "/home/eric/.nixos";
```

**Fix:**
```nix
# RECOMMENDED
HWC_NIXOS_DIR = "${config.home.homeDirectory}/.nixos";
```

---

#### Issue #5: Hard-coded Paths in Media Orchestrator
**Location:** `domains/server/orchestration/media-orchestrator.nix:25-27`

```nix
# CURRENT (BROKEN)
cp /home/eric/.nixos/workspace/automation/media-orchestrator.py ${cfgRoot}/scripts/
cp /home/eric/.nixos/workspace/automation/qbt-finished.sh ${cfgRoot}/scripts/
cp /home/eric/.nixos/workspace/automation/sab-finished.py ${cfgRoot}/scripts/
```

**Fix:**
```nix
# RECOMMENDED
let
  workspaceDir = "${config.users.users.${userName}.home}/.nixos/workspace";
in ''
  cp ${workspaceDir}/automation/media-orchestrator.py ${cfgRoot}/scripts/
  cp ${workspaceDir}/automation/qbt-finished.sh ${cfgRoot}/scripts/
  cp ${workspaceDir}/automation/sab-finished.py ${cfgRoot}/scripts/
''
```

---

#### Issue #6: Hard-coded Username in Protonmail Bridge
**Location:** `domains/system/services/protonmail-bridge/index.nix:51`

```nix
# CURRENT (BROKEN)
if ${pkgs.procps}/bin/pgrep -u eric -f "protonmail-bridge" ...
```

**Fix:**
```nix
# RECOMMENDED
if ${pkgs.procps}/bin/pgrep -u ${userName} -f "protonmail-bridge" ...
```

---

#### Issue #7: Hard-coded SSH Aliases
**Location:** `domains/home/environment/shell/options.nix:87-88`

```nix
# CURRENT (WORKS BUT NOT IDEAL)
"homeserver" = "ssh eric@100.115.126.41";
"server" = "ssh eric@100.115.126.41";
```

**Fix:**
```nix
# RECOMMENDED
let
  userName = config.hwc.system.users.user.name;
  serverIp = config.hwc.networking.tailscale.serverIp or "100.115.126.41";
in {
  "homeserver" = "ssh ${userName}@${serverIp}";
  "server" = "ssh ${userName}@${serverIp}";
}
```

---

#### Issue #8: Hard-coded Path in grebuild Script
**Location:** `domains/home/environment/shell/parts/grebuild.nix:37`

```nix
# CURRENT (ACCEPTABLE - HAS FALLBACK)
nixdir="''${HWC_NIXOS_DIR:-/home/eric/.nixos}"
```

**Status:** ⚠️ Acceptable (uses environment variable with fallback)
**Recommendation:** Keep as-is (the environment variable is set correctly)

---

### 3.2 Acceptable Hard-coding (User Identity Data)

These are **legitimate user-specific values** that should remain:

#### User Identity
```nix
# profiles/home.nix:50-51
userName = "Eric O'Keefe";
primaryEmail = "eric@iheartwoodcraft.com";
```

#### Mail Accounts
```nix
# domains/home/mail/accounts/index.nix
realName = "Eric O'Keefe";
address = "eric@iheartwoodcraft.com";
```

**Recommendation:** ✅ Keep as-is. These are actual user data, not configuration parameters.

**Optional Enhancement:** Extract to a user profile module:
```nix
# domains/system/users/profiles/eric.nix
hwc.users.profiles.eric = {
  fullName = "Eric O'Keefe";
  emails = {
    primary = "eric@iheartwoodcraft.com";
    personal = "eriqueokeefe@gmail.com";
    business = "heartwoodcraftmt@gmail.com";
  };
};
```

---

### 3.3 Claude Settings (Not Part of Nix Config)

**Locations:**
- `.claude/settings.local.json`
- `.claude/.claude/settings.local.json`

These are **IDE-specific settings**, not Nix configuration. They:
- Should be in `.gitignore`
- Are machine-specific
- Don't affect Nix builds

**Recommendation:** Add to `.gitignore`:
```gitignore
.claude/settings.local.json
.claude/.claude/settings.local.json
```

---

## 4. Recommended Improvements

### Priority 1: Critical Fixes (Do Immediately)

1. **Fix shell function path** (`domains/home/environment/shell/index.nix:140`)
2. **Generate MCP configs with Nix** (`.mcp.*.json`)
3. **Fix media orchestrator paths** (`domains/server/orchestration/media-orchestrator.nix`)
4. **Fix protonmail bridge username** (`domains/system/services/protonmail-bridge/index.nix`)

### Priority 2: Improve Parameterization (Do Soon)

5. **Use config.hwc.system.users.user.name everywhere**
   - `flake.nix`
   - `profiles/home.nix`
   - `machines/server/config.nix`
   - Auto-login settings
   - Service user references

6. **Fix environment variable defaults**
   - `domains/home/environment/shell/options.nix:42` (HWC_NIXOS_DIR)
   - `domains/home/environment/shell/options.nix:87-88` (SSH aliases)

### Priority 3: Optional Enhancements (Nice to Have)

7. **Create user profile system**
   ```nix
   hwc.users.profiles.eric = {
     fullName = "Eric O'Keefe";
     gitName = "Eric";
     gitEmail = "eric@hwc.moe";
     emails = { ... };
   };
   ```

8. **Extract network configuration**
   - Tailscale IPs
   - Server hostnames
   - SSH keys

9. **Add .gitignore entries**
   - `.claude/settings.local.json`
   - `.mcp.*.json` (if not needed in git)

---

## 5. Implementation Plan

### Phase 1: Critical Fixes (30 minutes)

```bash
# 1. Fix shell function path
# Edit: domains/home/environment/shell/index.nix:140

# 2. Generate MCP configs
# Create: domains/home/apps/mcp-config/index.nix
# Remove: .mcp.laptop.json, .mcp.server.json (add to .gitignore)

# 3. Fix media orchestrator paths
# Edit: domains/server/orchestration/media-orchestrator.nix

# 4. Fix protonmail bridge username
# Edit: domains/system/services/protonmail-bridge/index.nix
```

### Phase 2: Parameterization (1 hour)

```bash
# 1. Create userName variable in all profile files
# 2. Replace all home-manager.users.eric with ${userName}
# 3. Fix environment variable defaults
# 4. Update auto-login and linger settings
```

### Phase 3: Testing (30 minutes)

```bash
# 1. Test laptop build
nixos-rebuild build --flake .#laptop

# 2. Test server build
nixos-rebuild build --flake .#server

# 3. Verify MCP config generation
# 4. Test shell functions
```

---

## 6. Files for Cleanup

### Files to Remove
```bash
profiles/home.nix.backup.1760469543  # Old backup file
```

### Files to Add to .gitignore
```gitignore
# IDE/Editor configs (machine-specific)
.claude/settings.local.json
.claude/.claude/settings.local.json

# Generated configs (if we generate them with Nix)
.mcp.laptop.json
.mcp.server.json
```

---

## 7. Summary & Recommendations

### What's Working Well ✅

1. **100% Declarative Dotfiles** - All configuration managed by Nix
2. **Charter v6.0 Compliance** - Clean domain architecture
3. **Laptop/Server Separation** - Proper use of overrides
4. **Comprehensive Coverage** - 27 applications fully configured
5. **No Manual Dotfiles** - Everything in version control

### Areas for Improvement ⚠️

1. **8 hard-coded paths/usernames** - Need parameterization
2. **MCP configs not generated** - Should be Nix-managed
3. **User data mixed with config** - Could extract to profiles
4. **Some backup files** - Need cleanup

### Overall Assessment

**Grade: A-**

The nixos-hwc repository demonstrates **excellent practices** in dotfile management:
- All configuration is declarative and version-controlled
- Clean separation between laptop and server
- Proper domain-based architecture
- Minimal duplication

The identified issues are **minor and easily fixable** - mostly related to parameterization of usernames and paths. These don't affect functionality but reduce portability.

**Recommendation:** Implement Priority 1 fixes to achieve **full portability**, then consider Priority 2 improvements for long-term maintainability.

---

## Appendix: Detailed File Inventory

### Home Manager Modules by Domain

```
domains/home/
├── apps/            # 27 application configurations
│   ├── aerc/
│   ├── betterbird/
│   ├── chromium/
│   ├── gpg/
│   ├── hyprland/
│   ├── kitty/
│   ├── librewolf/
│   ├── neomutt/
│   ├── obsidian/
│   ├── swaync/
│   ├── thunar/
│   ├── waybar/
│   ├── yazi/
│   └── ... (14 more)
├── environment/     # Shell & dev tools
│   ├── shell/      # Zsh, Starship, Git, Tmux
│   └── parts/
│       ├── development.nix  # Neovim, LSP, toolchains
│       └── productivity.nix
├── mail/           # Mail system (6 components)
│   ├── accounts/
│   ├── bridge/
│   ├── mbsync/
│   ├── msmtp/
│   └── notmuch/
└── theme/          # Theming & fonts
    ├── fonts/
    ├── palettes/   # deep-nord, gruv
    └── templates/
```

### Workspace Files (Intentionally Unmanaged)

```
workspace/
├── automation/         # Runtime scripts (media automation)
├── infrastructure/     # Development tools (add-home-app.sh)
├── network/           # Network testing tools (netcheck, wifi-audit)
└── projects/          # Personal projects
    ├── site-crawler/  # Python web scraper
    └── bible-plan/    # Bible reading prompts
```

**Status:** ✅ Correctly excluded from Nix management

---

## Contact

For questions about this audit or implementation assistance:
- Repository: eriqueo/nixos-hwc
- Branch: claude/audit-dotfiles-nixos-01RXuwtS4QSfMGXDGjfJqx5i
- Date: 2025-11-18
