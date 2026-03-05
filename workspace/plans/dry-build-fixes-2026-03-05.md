# Dry Build Fixes — 2026-03-05

Tracking changes made during dry-build error resolution on branch `claude/review-migration-plan-Al1xi`.
Review after successful build to determine permanent fixes vs tech debt.

## Changes Made

### 1. Duplicate attribute definitions in `machines/server/config.nix`
- **Line 581**: Removed duplicate `hwc.data.backup.enable = false` (conflicted with block at line 305)
- **Line 585-586**: Removed duplicate `hwc.media.navidrome.enable = true` (kept `lib.mkForce false`)
- **Line 889**: Removed duplicate `hwc.media.immich.enable = lib.mkForce false` (kept block enable)

### 2. Missing `default.nix` in `domains/ai/ai-bible/`
- **Fix**: Changed import in `domains/ai/index.nix` from `./ai-bible` to `./ai-bible/index.nix`
- **Note**: This repo uses `index.nix` pattern, not `default.nix` (per Charter Law 9)

### 3. Missing `domains/lib/` directory (mkContainer import path)
- **Issue**: 23 files import `../../lib/mkContainer.nix` which resolves to `domains/lib/` not repo root `lib/`
- **Temporary fix**: Created symlink `domains/lib` → `../lib`
- **TODO**: Decide on permanent solution:
  - Option A: Keep symlink (simple, works)
  - Option B: Move `lib/` into `domains/lib/` (aligns with import paths)
  - Option C: Fix all 23 imports to use `../../../lib/mkContainer.nix` (correct but tedious)

### 8. protonmail-bridge also in wrong lane
- **Issue**: Same as #7 - `domains/home/mail/protonmail-bridge/index.nix` defines system-level services
- **Fix**: Renamed to `sys.nix` (already picked up by gatherSys from fix #7)

### 7. protonmail-bridge-cert in wrong lane
- **Issue**: `domains/home/mail/protonmail-bridge-cert/index.nix` defines system-level `systemd.services` but is imported in home-manager context
- **Fix**: Renamed to `sys.nix` and added mail to gatherSys in `profiles/core.nix`
- **Charter**: Law 7 compliance - sys.nix files belong to system lane

### 6. Orphaned user-backup.nix in backup domain
- **Issue**: `domains/data/backup/parts/user-backup.nix` uses `config.hwc.data.backup.user.*` but those options don't exist
- **Fix**: Commented out import in `backup/index.nix`
- **TODO**: Either delete the file or add the missing options to `options.nix`

### 5. Dead aggregator enables cleanup
- **Pattern**: Aggregator directories shouldn't have enable toggles; leaf services gate themselves
- **Deleted options.nix files**:
  - `domains/system/hardware/options.nix`
  - `domains/ai/options.nix`
  - `domains/home/apps/options.nix`
  - `domains/home/core/options.nix`
  - `domains/media/orchestration/options.nix`
- **Updated index.nix files**: Removed `./options.nix` imports and dead `lib.mkIf cfg.enable` blocks
- **Left alone**: `domains/home/mail/options.nix` (has real options: afew, accounts)
- **Charter consideration**: Document this pattern as guidance (enables on leaves, not aggregators)

### 4. System lane setting home option in `profiles/core.nix`
- **Issue**: Line 150 set `hwc.home.mail.protonmailBridge.enable` from system lane (Law 7 violation)
- **Fix**: Removed the line - home options should only be set in home-manager config
- **Note**: Charter Law 7 may need revision if cross-lane defaults are common pattern

## Build Status

**DRY BUILD SUCCESSFUL** - 2026-03-05

- 62 derivations to build
- 30 paths to fetch
- Evaluation warnings (expected): AI router, AI profile

## Pending Review

After successful build, review each change for:
- Charter compliance
- Long-term maintainability
- Whether temporary fixes should become permanent
