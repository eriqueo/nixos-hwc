# Plan: Find Broken References to Moved Scripts

## Context
Recently moved 3 scripts from `workspace/utilities/scripts/` to organized locations:
- `grebuild.sh` → `workspace/scripts/development/grebuild.sh`
- `list-services.sh` → `workspace/scripts/development/list-services.sh`
- `caddy-health-check.sh` → `workspace/scripts/monitoring/caddy-health-check.sh`

Need to verify nothing is still referencing the old paths.

## Logical Search Strategy

### 1. Search for Old Path References
**Target**: Hardcoded paths to `workspace/utilities/scripts/`

**Method**: Single comprehensive grep
```bash
rg "workspace/utilities/scripts" --type-add 'nix:*.nix' -t nix -t sh -t py -t md
```

**Why**: Most efficient - one search catches all file types that might reference scripts

### 2. Check Systemd Units
**Target**: Service definitions with ExecStart/ExecStartPre

**Method**: Focused search in domains
```bash
rg "ExecStart.*workspace.*scripts" domains/ --type-add 'nix:*.nix' -t nix
```

**Why**: Systemd units are most likely to break if paths changed

### 3. Verify System State
**Target**: Actual running services

**Method**: Check systemd status
```bash
systemctl --failed
journalctl -p err -n 50
```

**Why**: If anything broke, it would show up in failed services or error logs

### 4. Check for Relative References
**Target**: Scripts calling scripts with relative paths

**Method**: Search within workspace/scripts and workspace/utilities
```bash
rg "\.\./utilities/scripts" workspace/
rg "utilities/scripts" workspace/scripts/
```

**Why**: Scripts might use relative paths from their working directory

## Implementation Steps

1. Run comprehensive grep for old paths (Step 1)
2. Check systemd units (Step 2)
3. Verify no failed services (Step 3)
4. Check for relative paths (Step 4)
5. Document findings

## Expected Results

**If nothing broke:**
- Zero references to `workspace/utilities/scripts/` in active code
- No failed systemd services
- All 5 commands work (already verified)

**If something broke:**
- Hardcoded paths in systemd units
- Failed services after rebuild
- Scripts calling other scripts with old paths

## Success Criteria
- All searches return zero results for old paths
- No systemd failures
- Clean error logs
