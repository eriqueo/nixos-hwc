# Service Failure Remediation Plan

## Executive Summary

Three systemd services are failing due to distinct root causes that were introduced in recent commits. All failures can be permanently resolved with targeted, Charter-compliant fixes that follow existing patterns in the codebase.

## Root Cause Analysis

### 1. podman-ollama.service - CDI Device Resolution Failure

**Error**: `Error: setting up CDI devices: unresolvable CDI devices nvidia.com/gpu=all`

**Root Cause**: Race condition introduced in commit 51086d6 which removed systemd ordering dependencies. The service attempts to attach NVIDIA GPU devices via CDI (Container Device Interface) before the `nvidia-container-toolkit-cdi-generator.service` has created the required `/etc/cdi/nvidia.yaml` configuration file.

**Evidence**:
- ollama/index.nix:12 uses `--device=nvidia.com/gpu=all`
- No systemd dependencies present (removed in 51086d6)
- immich/index.nix:121-122 and 159-160 show correct pattern with `after` and `requires` dependencies

### 2. podman-frigate.service - Missing Host Mount Directory

**Error**: `statfs /mnt/hot/surveillance/frigate-v2/buffer: no such file or directory`

**Root Cause**: Directory creation relies on pre-start script (frigate-config service) which executes after boot but directories may not persist across reboots or fail if parent paths don't exist. The current implementation uses `mkdir -p` in the frigate-config service script (line 52) but this is not the Charter-recommended pattern.

**Evidence**:
- frigate/index.nix:48-53 creates directories in script, not tmpfiles
- immich/index.nix:88-106 shows proper pattern using systemd.tmpfiles.rules
- machine config (machines/server/config.nix:347) correctly sets path to `/mnt/hot/surveillance/frigate/buffer`
- Error shows `frigate-v2` path which is stale/orphaned from previous configuration
- tmpfiles.rules will create correct path and resolve the mismatch

### 3. transcript-api.service - Python Module Import Failure

**Error**: `Missing dependency: No module named 'fastapi'` (exit status 1)

**Root Cause**: `pkgs.buildEnv` approach doesn't properly construct Python's site-packages structure for module discovery. The current implementation uses `pathsToLink = [ "/bin" "/lib" ]` which creates a flat link structure, but Python requires packages in `lib/python3.12/site-packages` with proper metadata.

**Evidence**:
- transcript-api.nix:27-44 uses buildEnv instead of withPackages
- Comment mentions typer/typer-slim collision as justification (line 26)
- receipts-ocr.nix:25 shows standard pattern: `pkgs.python3.withPackages`
- PYTHONPATH workaround in line 65 is insufficient for proper package discovery

## Permanent Fix Strategy

### Fix 1: Add CDI Generator Dependency to Ollama

**File**: `domains/server/ai/ollama/index.nix`

**Approach**: Add systemd service override to ensure proper ordering, following the exact pattern used by immich.

**Implementation**:
```nix
# Add after line 53 (before the closing config block)
systemd.services.podman-ollama = lib.mkIf (gpuType == "nvidia") {
  after = [ "nvidia-container-toolkit-cdi-generator.service" ];
  requires = [ "nvidia-container-toolkit-cdi-generator.service" ];
};
```

**Rationale**:
- Follows established pattern from immich (immich/index.nix:119-122)
- Only applies when NVIDIA GPU is configured (conditional on gpuType)
- Ensures CDI configuration exists before Podman tries to resolve GPU devices
- Fail-fast: service won't start if CDI generator fails

**Validation**:
- Assertion already exists for GPU configuration (line 31-34)
- No additional validation needed

### Fix 2: Use tmpfiles for Frigate Directory Creation

**File**: `domains/server/frigate/index.nix`

**Approach**: Replace script-based directory creation with systemd.tmpfiles.rules and add validation that parent paths exist.

**Implementation**:
```nix
# Add after line 78 (before virtualisation.oci-containers)
systemd.tmpfiles.rules = [
  # Config directories
  "d ${cfg.storage.configPath} 0755 eric users -"
  "d ${cfg.storage.configPath}/models 0755 eric users -"
  "d ${cfg.storage.configPath}/labelmap 0755 eric users -"

  # Storage directories  "d ${cfg.storage.mediaPath} 0755 eric users -"
  "d ${cfg.storage.bufferPath} 0755 eric users -"
];

# Modify frigate-config service (lines 38-78) to ONLY handle config generation
# Remove mkdir commands (lines 48-53) and chown for directories (lines 56-58)
# Keep only config file generation (lines 60-74)
```

**Additional Validation**:
```nix
# Add to assertions section (line 153)
{
  assertion = !cfg.enable || (builtins.match "^/mnt/.*" cfg.storage.bufferPath != null);
  message = "hwc.server.frigate.storage.bufferPath must be under /mnt (e.g., /mnt/hot/surveillance/frigate/buffer)";
}
{
  assertion = !cfg.enable || (builtins.match "^/mnt/.*" cfg.storage.mediaPath != null);
  message = "hwc.server.frigate.storage.mediaPath must be under /mnt (e.g., /mnt/media/surveillance/frigate/media)";
}
```

**Rationale**:
- Follows Charter-recommended pattern (immich uses tmpfiles for all directories)
- Directories created early in boot process, before services start
- Survives reboots and is idempotent
- Separates concerns: tmpfiles = structure, service = config content
- Fail-fast with path validation

### Fix 3: Switch transcript-api to python3.withPackages

**File**: `domains/server/networking/parts/transcript-api.nix`

**Approach**: Replace `pkgs.buildEnv` with `pkgs.python3.withPackages` following the standard pattern used throughout the codebase.

**Implementation**:
```nix
# Replace lines 27-44 with:
pythonEnv = pkgs.python3.withPackages (ps: with ps; [
  fastapi
  uvicorn
  pydantic
  httpx
  yt-dlp
  youtube-transcript-api
  python-slugify
  spacy
  spacy-models.en_core_web_sm
]);

# Simplify PYTHONPATH in line 65 to:
PYTHONPATH = scriptDir;  # Only need the script directory, not site-packages
```

**Alternative (if typer collision resurfaces)**:
```nix
pythonEnv = (pkgs.python3.override {
  packageOverrides = self: super: {
    # Handle typer/typer-slim collision if it occurs
    typer = super.typer.overridePythonAttrs (old: {
      propagatedBuildInputs = builtins.filter (p: p.pname or "" != "typer-slim") (old.propagatedBuildInputs or []);
    });
  };
}).withPackages (ps: with ps; [
  # ... package list
]);
```

**Rationale**:
- Standard Nix pattern for Python environments (receipts-ocr.nix:25)
- Properly merges site-packages with correct metadata
- Simpler than buildEnv workaround
- The typer collision may have been resolved in recent nixpkgs
- If collision persists, override provides clean solution

**Validation**:
- Test that all imports work: fastapi, uvicorn, youtube-transcript-api, spacy
- Verify spacy model loading
- Check that service starts and responds

## Implementation Order

1. **transcript-api** (lowest risk, fastest to verify)
   - Single file change
   - Easy to test: restart service and check logs
   - No hardware dependencies

2. **frigate** (medium risk, structural improvement)
   - Requires careful migration of directory creation
   - Test that both config and directories work
   - Document the /mnt/hot path requirement

3. **ollama** (lowest risk but GPU-dependent)
   - Simple addition of systemd dependencies
   - Requires GPU hardware to fully test
   - Verify CDI generator runs first

## Testing Strategy

### Per-Service Testing

**transcript-api**:
```bash
# After rebuild
sudo systemctl restart transcript-api
sudo systemctl status transcript-api
journalctl -u transcript-api -n 50
curl http://localhost:8086/health  # or appropriate endpoint
```

**frigate**:
```bash
# Clean up old container and volumes (removes stale -v2 path reference)
podman stop frigate 2>/dev/null || true
podman rm frigate 2>/dev/null || true
podman volume prune -f

# Verify directories created
ls -la /mnt/hot/surveillance/frigate/
ls -la /var/lib/frigate/config/

# Restart service
sudo systemctl restart frigate-config
sudo systemctl restart podman-frigate
sudo systemctl status podman-frigate
```

**ollama**:
```bash
# Verify CDI generator ran
cat /etc/cdi/nvidia.yaml  # Should exist with GPU definitions

# Check service dependencies
systemctl list-dependencies podman-ollama

# Restart and verify GPU access
sudo systemctl restart podman-ollama
sudo systemctl status podman-ollama
podman exec -it ollama nvidia-smi  # Should show GPU
```

### Full System Test

```bash
# After all fixes applied
sudo nixos-rebuild test --flake .#hwc-server
sudo systemctl status podman-ollama podman-frigate transcript-api

# Verify all three services are active
systemctl list-units --failed  # Should be empty

# Reboot test
sudo reboot
# After reboot, verify all services started correctly
```

## Rollback Plan

Each fix is isolated and can be reverted independently:

1. **transcript-api**: Revert to buildEnv approach if withPackages fails
2. **frigate**: Keep script-based creation if tmpfiles has issues
3. **ollama**: Remove systemd dependency if CDI issues occur

## Critical Files

- `domains/server/ai/ollama/index.nix` - Add CDI dependency
- `domains/server/frigate/index.nix` - Add tmpfiles, modify frigate-config service
- `domains/server/networking/parts/transcript-api.nix` - Replace buildEnv with withPackages

## Success Criteria

- All three services show `active (running)` status
- `systemctl list-units --failed` returns empty
- Services survive reboot
- No race conditions or timing issues
- GPU devices accessible by ollama and frigate
- transcript-api responds to API requests
- frigate directories persist across reboots

## Long-term Maintenance

1. **Charter Compliance**: All fixes follow existing Charter patterns (tmpfiles, systemd dependencies, standard Python environments)
2. **Documentation**: Add comments explaining CDI dependencies and directory structure requirements
3. **Validation**: Assertions ensure configuration correctness at build time
4. **Monitoring**: Service failures will be caught by systemd status checks
