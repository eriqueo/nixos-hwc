# Fix media-orchestrator-install.service Failure

## Problem Summary

The `media-orchestrator-install.service` fails during system rebuild because it references a deleted file:

```
cp: cannot stat '/home/eric/.nixos/workspace/scripts/automation/media-orchestrator.py': No such file or directory
```

## Root Cause

**Path Mismatch**: The service definition at `/home/eric/.nixos/domains/server/orchestration/media-orchestrator.nix` references old paths that were reorganized in recent commits:

- **Expected path** (no longer exists): `/home/eric/.nixos/workspace/scripts/automation/media-orchestrator.py`
- **Actual path** (current location): `/home/eric/.nixos/workspace/automation/media-orchestrator.py`

**Recent consolidation**: Commits `debac7c` and `c070cfe` moved scripts from `workspace/scripts/` to `workspace/automation/` but the NixOS module wasn't updated.

## Architectural Context

**Important Discovery**: This is **legacy infrastructure being replaced by n8n workflows**

- **Legacy**: Standalone Python daemon monitoring event files
- **Modern**: n8n workflow `01-media-pipeline-orchestration.json` with webhooks, better integration, visibility

The system is actively migrating from standalone services to n8n orchestration.

## Recommended Approach: FIX PATH

**Decision**: Keep the media-orchestrator service running until n8n workflows are fully deployed and tested.

**Rationale**: The n8n Media Pipeline Orchestration workflow exists but isn't deployed yet. The legacy service provides critical functionality that shouldn't be interrupted.

### Files to Modify

**File: `/home/eric/.nixos/domains/server/orchestration/media-orchestrator.nix`**

Change line 30-32 from:
```nix
cp ${workspaceDir}/scripts/automation/media-orchestrator.py ${cfgRoot}/scripts/
cp ${workspaceDir}/scripts/automation/sab-finished.py ${cfgRoot}/scripts/
cp ${workspaceDir}/scripts/automation/qbt-finished.sh ${cfgRoot}/scripts/
```

To:
```nix
cp ${workspaceDir}/automation/media-orchestrator.py ${cfgRoot}/scripts/
cp ${workspaceDir}/automation/sab-finished.py ${cfgRoot}/scripts/
cp ${workspaceDir}/automation/qbt-finished.sh ${cfgRoot}/scripts/
```

**Change**: Remove `/scripts/` from the source paths (since files moved to `automation/` directly)

## Critical Files

### Files to Modify:
1. `/home/eric/.nixos/domains/server/orchestration/media-orchestrator.nix` - Fix source paths (line 30-32)

### Files That Must Exist (Verify):
1. `/home/eric/.nixos/workspace/automation/media-orchestrator.py` - Main orchestration script
2. `/home/eric/.nixos/workspace/automation/sab-finished.py` - SABnzbd completion handler
3. `/home/eric/.nixos/workspace/automation/qbt-finished.sh` - qBittorrent completion handler

## Implementation Steps

1. **Edit the NixOS module**
   - File: `/home/eric/.nixos/domains/server/orchestration/media-orchestrator.nix`
   - Line 30-32: Remove `/scripts/` from source paths
   - Change: `${workspaceDir}/scripts/automation/` → `${workspaceDir}/automation/`

2. **Rebuild system**
   - Command: `sudo nixos-rebuild switch --flake .#hwc-server`
   - Expected: No errors, service starts successfully

3. **Verify deployment**
   - Check service status: `systemctl status media-orchestrator-install.service`
   - Check service status: `systemctl status media-orchestrator.service`
   - Verify files deployed: `ls -la /opt/downloads/scripts/`

4. **Test functionality**
   - Check daemon logs: `journalctl -u media-orchestrator.service -f`
   - Trigger a download completion event
   - Verify library rescan occurs

## Future Migration Note

Once n8n workflows are deployed and tested, this service can be deprecated in favor of the n8n Media Pipeline Orchestration workflow, which provides:
- Webhook-based event handling
- Better monitoring and debugging
- Integration with other workflows
- Visual execution history
