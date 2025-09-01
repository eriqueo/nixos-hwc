# Claude Development Guidelines

This file provides essential context for Claude instances working on this nixos-hwc codebase.

## 📋 Start Here - Read This First

**Session Startup Checklist:**
1. **Migration Status**: [`docs/MIGRATION_STATUS.md`](docs/MIGRATION_STATUS.md) - current phase & progress
2. **Charter v4**: [`docs/CHARTER_v4.md`](docs/CHARTER_v4.md) - domain separation rules
3. **Progress Check**: `./scripts/migration-progress.sh` - validation & next actions
4. **Current Phase**: Complete Phase 1 before moving to Phase 2

## 🏗️ Architecture Overview

This is a NixOS flake configuration following Charter v4 domain separation:

```
modules/
├── infrastructure/    # Hardware drivers, device control
├── system/           # Core OS functions  
├── services/         # Application/daemon orchestration
└── home/             # User environment (Home Manager)

profiles/             # Orchestration (imports + toggles)
machines/             # Hardware reality (facts only)
```

## 🔄 Workflow Rules

### Before Any Changes:
1. **Read Charter v4** (`docs/CHARTER_v4.md`) - understand domain separation
2. **Check compliance** with `./scripts/validate-charter-v4.sh`
3. **Follow dependency direction**: profiles → modules (never reverse)

### For Waybar/UI Changes:
- **All waybar config** stays in `modules/home/waybar/`
- **Hardware scripts** go in `modules/infrastructure/`
- **Tools are simple** - just waybar config blocks, no complex options
- **One place to look** for waybar issues

### For New Modules:
- Use **Charter v4 header template** (see `docs/CHARTER_v4.md` section 7.2)
- Follow **domain classification** rules
- Add **section headers** (`#============================================================================`)
- Use **kebab-case** naming

## 🚫 Anti-Patterns to Avoid

- **Hardware scripts in home/** - violates domain separation
- **Complex tool options** - tools should be simple waybar config
- **Cross-domain imports** - respect dependency direction
- **Missing headers** - every module needs Charter v4 headers

## 🛠️ Available Tools

- **Validation**: `./scripts/validate-charter-v4.sh`
- **Header updates**: `./scripts/simple-header-update.sh --all`
- **Section headers**: `./scripts/add-section-headers.sh --all`
- **Domain analysis**: `./scripts/fix-domain-violations.sh`

## ✅ Success Criteria

- Charter v4 validation passes with zero violations
- Clean domain boundaries (no hardware in home/, etc.)
- Single source of truth for each capability
- One place to look for each UI component (waybar/)

## 🔄 Session Continuity Process

### Before Making Changes:
1. Run `./scripts/migration-progress.sh` to check current status
2. Read `docs/MIGRATION_STATUS.md` for context
3. Understand current phase requirements

### After Making Changes:
1. Update `docs/MIGRATION_STATUS.md` with progress
2. Run validation: `./scripts/validate-charter-v4.sh`
3. Update completion percentages
4. Note any blockers or decisions needed

### Phase Transitions:
- **Complete Phase 1** (zero violations) before Phase 2
- **Document decisions** for architectural changes  
- **Test builds** after major changes

---

**When in doubt, ask the user rather than making assumptions about architecture.**