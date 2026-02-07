# Home Manager File Management Patterns

**Purpose**: Prevent `.hm-bak` conflicts by using correct file management patterns

**Version**: 1.0
**Last Updated**: 2026-01-07

---

## The Problem

Home Manager backup files (`.hm-bak`) are created when HM encounters conflicts during activation. These conflicts indicate **architectural anti-patterns** in your configuration.

### Root Cause

**The Fatal Anti-Pattern**:
```nix
# ❌ WRONG: Managing same file in two places
home.file.".config/foo".text = "content";
home.activation.copyFoo = ''
  cp something ~/.config/foo
  chmod 600 ~/.config/foo
'';
```

**Why It Breaks**:
1. First rebuild: HM creates symlink at `.config/foo`
2. Activation hook overwrites symlink with regular file
3. Next rebuild: HM sees regular file where it expects symlink
4. HM creates `.hm-bak` → **ACTIVATION FAILURE**

---

## The Right Patterns

### Pattern 1: Immutable Config Files (No Secrets)

**Use Case**: Configuration files that never change, contain no secrets

**Solution**: Pure declarative management
```nix
✅ CORRECT
home.file.".config/app/config.toml".text = ''
  setting = "value"
'';
```

**Example**: `aerc/accounts.conf`, `hyprland.conf`, `waybar/config`

---

### Pattern 2: Files Needing Special Permissions

**Use Case**: Config files need non-default permissions (e.g., 600), but NO secrets

**Solution**: Use `onChange` hook
```nix
✅ CORRECT
home.file.".config/app/config" = {
  text = configContent;
  onChange = ''
    chmod 600 $HOME/.config/app/config
  '';
};
```

**Why**: HM symlink is created first, then `onChange` runs after linking

---

### Pattern 3: Files With Runtime Secrets

**Use Case**: Config files need secrets that can't be in Nix store (world-readable)

**Solution A**: Use agenix with one-time setup
```nix
✅ CORRECT
# Declare secret
age.secrets.app-password = {
  file = ../secrets/parts/app/password.age;
  group = "secrets";
  mode = "0440";
};

# Create config only if missing (preserve user edits)
home.activation.setupAppConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  CONFIG="$HOME/.config/app/config"
  if [ ! -f "$CONFIG" ]; then
    cat > "$CONFIG" << EOF
password = $(cat ${config.age.secrets.app-password.path})
other_setting = value
EOF
    chmod 600 "$CONFIG"
  fi
'';
```

**Solution B**: Template approach
```nix
✅ CORRECT
home.file.".config/app/config.template".text = ''
  password = @PASSWORD@
'';

home.activation.finalizeAppConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
  TEMPLATE="$HOME/.config/app/config.template"
  CONFIG="$HOME/.config/app/config"
  SECRET="${config.age.secrets.app-password.path}"

  sed "s/@PASSWORD@/$(cat $SECRET)/" "$TEMPLATE" > "$CONFIG"
  chmod 600 "$CONFIG"
'';
```

**Example**: `msmtp/config` (email passwords), SSH configs

---

### Pattern 4: Mutable Files (Program Updates Them)

**Use Case**: Files that programs or XDG tools modify at runtime

**Solution**: Use program-specific options, DON'T manage file directly
```nix
❌ WRONG
home.file.".config/mimeapps.list".text = "...";

✅ CORRECT
xdg.mimeApps = {
  enable = true;
  defaultApplications = {
    "text/html" = "firefox.desktop";
    "application/pdf" = "zathura.desktop";
  };
};
```

**Examples**:
- `mimeapps.list` → use `xdg.mimeApps`
- `user-dirs.dirs` → use `xdg.userDirs`
- Browser profiles → Don't manage, let browser handle
- `dconf` settings → use `dconf.settings`

---

### Pattern 5: Initial Setup Only (Preserve User Edits)

**Use Case**: Create initial config, but let user modify it

**Solution**: Check if file exists before creating
```nix
✅ CORRECT
home.activation.initAppConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  CONFIG="$HOME/.config/app/config"
  if [ ! -f "$CONFIG" ]; then
    echo "Creating initial config..."
    cat > "$CONFIG" << 'EOF'
# User-editable configuration
setting = "default"
EOF
  fi
'';
```

**When to use**: Configs you want users to customize manually

---

## Anti-Pattern Detection

### Symptoms

1. **Recurring `.hm-bak` files** after rebuilds
2. **"would be clobbered"** errors during HM activation
3. **Files switching between symlink ↔ regular file**

### Root Causes

```nix
❌ ANTI-PATTERN 1: Dual Management
home.file.".config/foo".text = "...";
home.activation.something = '' ... > ~/.config/foo'';

❌ ANTI-PATTERN 2: Managing Mutable Files
home.file.".config/mimeapps.list".text = "...";
# Program will update this file!

❌ ANTI-PATTERN 3: Secrets in Nix Store
home.file.".config/app/secret".text = "password123";
# World-readable in /nix/store!
```

---

## Migration Guide

### If You Have `.hm-bak` Conflicts

1. **Identify the file**: `find ~/.config -name "*.hm-bak"`

2. **Determine file type**:
   - Contains secrets? → Pattern 3
   - Program modifies it? → Pattern 4
   - Needs special perms? → Pattern 2
   - Immutable config? → Pattern 1

3. **Refactor** using correct pattern above

4. **Test**: `sudo nixos-rebuild switch`

5. **Verify**: No `.hm-bak` files created

### Example Migration: aerc accounts.conf

**Before** (Anti-pattern):
```nix
# domains/home/apps/aerc/parts/config.nix
home.file.".config/aerc/accounts.conf".text = accountsConf;
home.file.".config/aerc/accounts.conf.source".text = accountsConf;

# domains/home/apps/aerc/index.nix
home.activation.aerc-accounts-finalize = ''
  install -Dm600 ~/.config/aerc/accounts.conf.source ~/.config/aerc/accounts.conf
'';
```

**After** (Pattern 1 - No secrets, no special perms needed):
```nix
# domains/home/apps/aerc/parts/config.nix
home.file.".config/aerc/accounts.conf".text = accountsConf;
# That's it! No activation hook needed.
```

---

## Quick Reference

| File Type | Pattern | Tool |
|-----------|---------|------|
| Immutable config (no secrets) | `home.file.foo.text` | Pattern 1 |
| Needs chmod | `home.file.foo + onChange` | Pattern 2 |
| Contains secrets | `age.secrets + home.activation` | Pattern 3 |
| Program modifies | Use program options | Pattern 4 |
| User-editable | `home.activation` with existence check | Pattern 5 |

---

## Validation

### Before Commit

```bash
# Check for anti-patterns
rg "home\.file.*home\.activation" domains/home/

# Find potential mutable files
rg "mimeapps\.list|user-dirs\.dirs|\.mozilla" domains/home/ | grep home.file
```

### After Rebuild

```bash
# Should return empty
find ~/.config -name "*.hm-bak" 2>/dev/null

# Verify symlinks
ls -la ~/.config/aerc/accounts.conf  # Should show symlink
```

---

## See Also

- [Charter v6.0](../CHARTER.md) - Domain boundaries and architectural rules
- [Home Manager Manual](https://nix-community.github.io/home-manager/) - Official documentation
- [Agenix Secrets](../domains/secrets/README.md) - Secret management patterns

---

**Remember**: If you're creating `.hm-bak` files, you're using the WRONG pattern. Fix the root cause, not the symptom.
