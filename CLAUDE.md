# Claude Code Working Instructions

**Project**: NixOS HWC (Heartwood Collective)

## ⚠️ MANDATORY READING REQUIREMENT ⚠️

**BEFORE STARTING ANY WORK, AI ASSISTANTS MUST READ:**
1. **`charter.md`** - Complete HWC Architecture Charter v6.0
2. **`FILESYSTEM-CHARTER.md`** - Home directory organization v2.0
3. **This entire document** - Working instructions and patterns

**Failure to read these documents results in architectural violations and broken implementations.**

**Full Charter**: See `charter.md` for complete architecture documentation

---

## Philosophy & Approach

**CRITICAL: Fix Root Causes, Not Symptoms**

- When something fails, **STOP and understand WHY** before attempting fixes
- Do NOT make "shitty patches" just to get things to rebuild
- Do NOT focus on getting something to work at the expense of doing it correctly
- If you don't understand the root problem, **ASK** before proceeding
- Simple fixes are fine IF they address the actual issue
- Multiple steps are fine IF they're the right steps

**Examples of Bad Behavior to AVOID:**
- ❌ "Let me try wrapping this in a try-catch to suppress the error"
- ❌ "I'll add this hack to make it build, we can fix it properly later"
- ❌ "The test is failing, let me disable the test"
- ❌ Making 5 rapid changes without understanding which one actually helps

**Examples of Good Behavior:**
- ✅ "This is failing because X. The root cause is Y. Here's how to fix Y."
- ✅ "I need to understand the dependency chain before making changes"
- ✅ "This 'fix' would work but it's a bandaid. Let me do it properly."

---

## Architecture Quick Reference

**Full details in `charter.md` - Read it if unfamiliar with HWC architecture**

### Domain Structure
- `domains/system/` - Core OS, users, networking, paths
- `domains/secrets/` - Encrypted secrets (agenix), API at `/run/agenix`
- `domains/infrastructure/` - Hardware, GPU, power, virtualization
- `domains/server/` - Containers, databases, media stacks
- `domains/home/` - User environment (Home Manager only)
- `profiles/` - Domain feature menus (system.nix, home.nix, etc.)
- `machines/<host>/` - Hardware facts + profile composition

### Key Rules
- Namespace follows folder: `domains/home/apps/firefox/` → `hwc.home.apps.firefox.*`
- Every module needs `options.nix` (never define options elsewhere)
- System domain = NixOS, Home domain = Home Manager, never mix
- Profiles provide feature menus, machines compose profiles
- One logical concern per module directory

---

## Common Commands

### Rebuild & Test
```bash
# Build (don't switch yet)
sudo nixos-rebuild build --flake .#hwc-laptop

# Switch to new config (after testing build)
sudo nixos-rebuild switch --flake .#hwc-laptop

# Test boot (safe - reverts on reboot)
sudo nixos-rebuild test --flake .#hwc-laptop
```

### Git Workflow
```bash
# ALWAYS commit before rebuild
git add -A
git commit -m "message"

# Then rebuild
sudo nixos-rebuild build --flake .#hwc-laptop
```

### Home Manager
- Home Manager is a **MODULE**, not a flake
- Config lives in `machines/laptop/home.nix`
- Activates via system rebuild (not separate `home-manager switch`)

---

## Common Mistakes & Reminders

### Tool Usage
- ❌ **NEVER use `grep`** → ✅ Use `rg` (ripgrep)
- ❌ **NEVER use `sed`** → ✅ Directly edit files with Edit tool
- ❌ **Don't use `find`** → ✅ Use Glob or Grep tools

### Architecture
- ❌ Don't add Home Manager config to system domain
- ❌ Don't add systemd services to home domain
- ❌ Don't define options outside `options.nix` files
- ❌ Don't hardcode paths - use `config.hwc.paths.*`
- ✅ Always add validation section to modules with enable toggles
- ✅ Assert runtime dependencies (fail at build, not runtime)
- ✅ Add `extraGroups = [ "secrets" ]` to all service users for secret access

### Build Process
- ❌ Don't try simple fixes just to get things to work
- ❌ Don't skip understanding the root cause
- ✅ Add and commit changes BEFORE rebuilding
- ✅ Build first, then switch (don't switch on red)
- ✅ Run linters if configured (`npm run lint`, `ruff`, etc.)

### Flake Name
- The flake is `hwc-laptop`, not just `laptop`
- Command: `sudo nixos-rebuild build --flake .#hwc-laptop`

---

## Project-Specific Notes

### Paths
- Local development storage: `~/300_tech/120-development/local-storage/` (per filesystem charter)
- Secrets: `/run/agenix` (managed by agenix)
- Filesystem charter: `FILESYSTEM-CHARTER.md` (home directory organization)

### Networking
- Wait-online policy is per-machine (laptop = "off", server = "all")
- Static routes need explicit interface configuration

### Secrets & Age Key Management
- Domain: `domains/secrets/`
- All secrets via agenix (encrypted .age files)
- Stable API at `/run/agenix`
- **Permission Model**: All secrets use `group = "secrets"; mode = "0440"`
- **Service Access**: All service users must include `extraGroups = [ "secrets" ]`
- **Emergency Fallback**: Automatic fallback to hardcoded credentials when agenix fails
  - User password: `"il0wwlm?"` (when secrets unavailable)
  - SSH keys: Hardcoded fallback keys (when secrets unavailable)
  - **No manual intervention required** - system auto-detects and warns

**Age Key Access for Secret Updates:**
```bash
# 1. Get the public key for encryption
sudo age-keygen -y /etc/age/keys.txt
# Output: age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne

# 2. Encrypt new secret with the public key
echo "new-secret-value" | age -r age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne > domains/secrets/parts/domain/secret-name.age

# 3. Verify decryption works
sudo age -d -i /etc/age/keys.txt domains/secrets/parts/domain/secret-name.age

# 4. Commit and rebuild
git add domains/secrets/parts/domain/secret-name.age
git commit -m "update secret"
sudo nixos-rebuild switch --flake .#hwc-laptop
```

**Important:** Always backup old .age files before replacing them.

---

## Specialized Agents

**Use these HWC-specific agents proactively for better results:**

### Primary Agents
- **`nixos-hwc-architect`** - Use for architecture design, module creation, domain organization, and HWC compliance review
- **`nixos-hwc-troubleshooter`** - Use for build failures, configuration conflicts, service issues, and system debugging

### When to Use Each Agent

**Architecture Agent** (`nixos-hwc-architect`):
- Planning new modules or features
- Reviewing domain boundaries and namespace compliance
- Designing profile structure (BASE vs OPTIONAL)
- Secret management workflows (agenix/age)
- Migration from non-HWC patterns
- Any architectural decisions

**Troubleshooting Agent** (`nixos-hwc-troubleshooter`):
- NixOS rebuild failures
- Module conflicts and option collisions
- systemd service issues
- Performance problems
- Runtime errors and crashes
- Any debugging or error resolution

**Examples:**
```bash
# Use architecture agent
"Help me add a new container service following HWC patterns"
"Review this module for domain compliance"

# Use troubleshooting agent
"My rebuild is failing with type errors"
"Service won't start after configuration change"
```

**Agent Specifications**: See `nixos-hwc-agent.md` and `nixos-hwc-troubleshooter.md` for complete capabilities.

---

## When In Doubt

1. **Use the specialized agents** - They understand HWC patterns deeply
2. **Read the charter**: `CHARTER.md`
3. **Ask the user** if you don't understand the root cause
4. **Explain your reasoning** before making changes
5. **Fix root problems**, not symptoms

---

**Charter Version Reference**: v6.0 (see `CHARTER.md` for full details)
