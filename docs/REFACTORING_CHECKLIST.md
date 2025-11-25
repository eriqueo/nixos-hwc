# Systemd Services Refactoring - Implementation Checklist

Use this checklist to track progress on implementing the audit recommendations.

---

## Phase 1: Critical Security Fixes (Week 1)

### 🔴 Priority 1: Gluetun Container Security

- [ ] **Remove `--privileged` flag from Gluetun**
  - File: `domains/server/containers/gluetun/parts/config.nix:46`
  - Action: Remove `"--privileged"` from extraOptions
  - Testing: Verify VPN connection still works

- [ ] **Remove SYS_MODULE capability**
  - File: Same as above
  - Action: Remove `"--cap-add=SYS_MODULE"`
  - Action: Add kernel modules to boot.kernelModules on host

- [ ] **Add resource limits to Gluetun**
  - File: Same as above
  - Action: Add `--memory=512m`, `--cpus=0.5`, `--pids-limit=100`
  - Testing: Monitor resource usage, adjust if needed

- [ ] **Harden gluetun-env-setup service**
  - File: `domains/server/containers/gluetun/parts/config.nix:11-34`
  - Action: Add security hardening directives
  - Action: Add `set -euo pipefail` to script

- [ ] **Test Gluetun functionality**
  - [ ] VPN connects successfully
  - [ ] qBittorrent can access internet through VPN
  - [ ] SABnzbd can access internet through VPN
  - [ ] VPN failover works correctly

---

### 🟠 Priority 2: Business API Security

- [ ] **Create business-db-password secret**
  - File: `domains/secrets/declarations/apps.nix`
  - Action: Add age secret for database password
  - Action: Generate and encrypt secret with agenix

- [ ] **Convert Business API to LoadCredential**
  - File: `domains/server/business/api.nix:282-315`
  - Action: Replace Environment with LoadCredential
  - Action: Update Python app to read from CREDENTIALS_DIRECTORY

- [ ] **Add security hardening to business-api**
  - File: Same as above
  - Action: Add NoNewPrivileges, ProtectSystem, ProtectHome, etc.
  - Action: Add ReadWritePaths for business data

- [ ] **Fix Restart policy**
  - File: Same as above
  - Action: Change `Restart = "always"` to `Restart = "on-failure"`

- [ ] **Add StateDirectory and CacheDirectory**
  - File: Same as above
  - Action: Add StateDirectory = "business-api"
  - Action: Add CacheDirectory = "business-api"

- [ ] **Test Business API**
  - [ ] API starts correctly
  - [ ] Database connection works
  - [ ] Redis connection works
  - [ ] Secrets are loaded correctly
  - [ ] No permission errors

---

### 🟠 Priority 3: Media Orchestrator Security

- [ ] **Convert to DynamicUser**
  - File: `domains/server/orchestration/media-orchestrator.nix`
  - Action: Replace `User = "root"` with `DynamicUser = true`
  - Action: Add Group = "media"

- [ ] **Convert secrets to LoadCredential**
  - File: Same as above
  - Action: Remove preStart script
  - Action: Add LoadCredential for all *arr API keys
  - Action: Update Python script to read from CREDENTIALS_DIRECTORY

- [ ] **Add comprehensive hardening**
  - File: Same as above
  - Action: Add all security directives
  - Action: Add CapabilityBoundingSet = ""

- [ ] **Fix Restart policy**
  - File: Same as above
  - Action: Change to `Restart = "on-failure"`
  - Action: Add StartLimitIntervalSec and StartLimitBurst

- [ ] **Add StateDirectory**
  - File: Same as above
  - Action: Replace hard-coded path with StateDirectory

- [ ] **Test Media Orchestrator**
  - [ ] Service starts as non-root
  - [ ] Can communicate with Radarr API
  - [ ] Can communicate with Sonarr API
  - [ ] Can communicate with Lidarr API
  - [ ] Can communicate with Prowlarr API
  - [ ] Automation logic works correctly

---

### 🟡 Priority 4: Additional Critical Root Users

- [ ] **Convert gpu-monitor to DynamicUser**
  - File: `domains/infrastructure/hardware/parts/gpu.nix:154-172`
  - See Diff 1 in SYSTEMD_REFACTORING_PROPOSALS.md

- [ ] **Convert winapps-monitor to timer pattern**
  - File: `domains/infrastructure/winapps/index.nix`
  - Action: Replace while-loop with timer-triggered oneshot

- [ ] **Harden ProtonVPN service**
  - File: `domains/system/services/vpn/index.nix`
  - Action: Add security directives
  - Action: Add StateDirectory for session data

---

## Phase 2: Standardization (Week 2)

### 📦 Priority 5: Container Standardization Module

- [ ] **Create hwc-container module**
  - File: Create `modules/services/hwc-container.nix`
  - Action: Copy template from SYSTEMD_REFACTORING_PROPOSALS.md
  - Action: Import in flake.nix or main config

- [ ] **Convert Radarr to new pattern**
  - File: `domains/server/containers/radarr/index.nix`
  - Action: Replace virtualisation.oci-containers with services.hwc.container
  - Testing: Verify Radarr starts and functions correctly

- [ ] **Convert Sonarr to new pattern**
  - File: `domains/server/containers/sonarr/parts/config.nix`
  - Action: Same as Radarr
  - Testing: Verify Sonarr starts and functions correctly

- [ ] **Convert Lidarr to new pattern**
  - File: `domains/server/containers/lidarr/parts/config.nix`
  - Action: Same as Radarr
  - Testing: Verify Lidarr starts and functions correctly

- [ ] **Convert Prowlarr to new pattern**
  - File: `domains/server/containers/prowlarr/parts/config.nix`
  - Action: Same as Radarr
  - Testing: Verify Prowlarr starts and functions correctly

- [ ] **Convert qBittorrent to new pattern**
  - File: `domains/server/containers/qbittorrent/parts/config.nix`
  - Action: Ensure VPN network mode works
  - Testing: Verify VPN routing works correctly

- [ ] **Convert SABnzbd to new pattern**
  - File: `domains/server/containers/sabnzbd/parts/config.nix`
  - Action: Ensure VPN network mode works
  - Testing: Verify VPN routing works correctly

- [ ] **Convert remaining containers**
  - [ ] Jellyseerr
  - [ ] Organizr
  - [ ] Slskd
  - [ ] Soularr
  - [ ] Tdarr
  - [ ] Beets
  - [ ] Recyclarr

- [ ] **Update container shared library**
  - File: `domains/server/containers/_shared/lib.nix`
  - Action: Mark as deprecated, point to new module
  - Action: Add migration guide comment

---

### 🔍 Priority 6: Monitoring Pattern Module

- [ ] **Create hwc-monitor module**
  - File: Create `modules/services/hwc-monitor.nix`
  - Action: Copy template from SYSTEMD_REFACTORING_PROPOSALS.md
  - Action: Import in flake.nix or main config

- [ ] **Convert GPU monitor**
  - File: `domains/infrastructure/hardware/parts/gpu.nix`
  - Action: Replace while-loop service with services.hwc.monitor
  - Testing: Verify metrics collection works

- [ ] **Convert WinApps monitor**
  - File: `domains/infrastructure/winapps/index.nix`
  - Action: Replace while-loop service with services.hwc.monitor
  - Testing: Verify VM health checks work

- [ ] **Convert CouchDB health monitor**
  - File: `domains/server/couchdb/index.nix`
  - Action: Replace oneshot service with services.hwc.monitor
  - Testing: Verify health endpoint checking works

- [ ] **Convert Gluetun health check**
  - File: `domains/server/networking/parts/networking.nix`
  - Action: Replace service with services.hwc.monitor
  - Testing: Verify VPN status checking works

- [ ] **Add Frigate camera watchdog to pattern**
  - File: `domains/server/frigate/parts/watchdog.nix`
  - Action: Convert to services.hwc.monitor
  - Testing: Verify camera monitoring works

---

## Phase 3: Comprehensive Hardening (Week 3)

### 🛡️ Priority 7: Security Baseline for All Services

Create a tracking spreadsheet or mark here:

#### Infrastructure Services
- [ ] `gpu-monitor` (if not already done)
- [ ] `winapps-vm-autostart`
- [ ] `winapps-monitor` (if not already done)

#### AI/LLM Services
- [x] `ai-bible` (already excellent)
- [ ] `ai-bible-generate`
- [ ] `mcp-filesystem-nixos`
- [ ] `mcp-proxy`
- [ ] `ollama-pull-models`
- [x] `fabric-api` (already good, minor improvements)

#### Application Services
- [ ] `business-api` (if not already done)
- [ ] `business-api-dev-setup`

#### Backup Services
- [ ] `user-backup` (add remaining hardening)
- [ ] `backup-system-info`

#### Container Support Services
- [ ] `init-media-network`
- [ ] `gluetun-env-setup` (if not already done)
- [ ] `slskd-config-generator`
- [ ] `soularr-config`
- [ ] All `podman-*` service dependencies

#### Database Services
- [ ] `couchdb-config-setup`
- [ ] `couchdb-health-monitor` (if not already done)
- [ ] `postgresql-backup`
- [ ] `business-backup`

#### Monitoring & Cleanup
- [ ] `media-cleanup` (add remaining hardening)
- [ ] `storage-monitor` (add remaining hardening)
- [ ] `frigate-storage-prune`
- [ ] `frigate-camera-watchdog` (if not already done)
- [ ] `tdarr-safety-check`

#### System Services
- [x] `protonmail-bridge` (gold standard, no changes needed)
- [ ] `protonmail-bridge-cert`
- [ ] `protonvpn-connect`

#### Specialized Services
- [ ] `media-orchestrator` (if not already done)
- [ ] `media-orchestrator-install`
- [ ] `vault-sync` (system service)
- [ ] `vault-watch` (user service)
- [ ] `transcript-api`

---

### 📁 Priority 8: Path Standardization

Track hard-coded path elimination:

#### Services Using Hard-Coded Paths

- [ ] GPU monitor → Use LogsDirectory
- [ ] Business API → Use StateDirectory
- [ ] MCP services → Use config paths
- [ ] Gluetun → Use StateDirectory
- [ ] All container configs → Derive from paths module
- [ ] Media orchestrator → Use StateDirectory
- [ ] Vault sync → Use user home from config

#### Systemd Directory Conversions

Template for each service:
```nix
serviceConfig = {
  StateDirectory = "service-name";      # /var/lib/service-name
  CacheDirectory = "service-name";      # /var/cache/service-name
  LogsDirectory = "service-name";       # /var/log/service-name
  RuntimeDirectory = "service-name";    # /run/service-name
  ConfigurationDirectory = "service-name"; # /etc/service-name
};
```

Apply to:
- [ ] AI services (ai-bible, ollama, etc.)
- [ ] Business services
- [ ] Container support services
- [ ] Monitoring services
- [ ] Backup services

---

## Phase 4: Documentation & Testing

### 📚 Documentation Updates

- [ ] **Update CHARTER.md**
  - [ ] Add systemd best practices section
  - [ ] Document hwc-container module usage
  - [ ] Document hwc-monitor module usage
  - [ ] Add security hardening standards

- [ ] **Create service templates**
  - [ ] Template for new simple service
  - [ ] Template for new container service
  - [ ] Template for new timer/monitor service
  - [ ] Template for secret injection

- [ ] **Update module documentation**
  - [ ] Document all options in hwc-container
  - [ ] Document all options in hwc-monitor
  - [ ] Add usage examples
  - [ ] Add migration guide from old pattern

---

### 🧪 Testing & Validation

#### Automated Testing

- [ ] **Set up systemd-analyze security scanning**
  - Script to run on all services
  - Target: 8+/10 score for all services
  - Generate report

- [ ] **Create service test suite**
  - [ ] Test: All services start successfully
  - [ ] Test: All containers can communicate
  - [ ] Test: All secrets are loaded correctly
  - [ ] Test: All health checks pass
  - [ ] Test: Resource limits are enforced

- [ ] **Set up CI integration**
  - [ ] Build test in GitHub Actions
  - [ ] VM test in GitHub Actions
  - [ ] Security scan in GitHub Actions
  - [ ] Fail on hardening regressions

#### Manual Validation

- [ ] **Production smoke test**
  - [ ] All critical services running
  - [ ] Media download pipeline works
  - [ ] Frigate cameras recording
  - [ ] Business API accessible
  - [ ] Backups completing successfully

- [ ] **Security audit**
  - [ ] No services running as root unnecessarily
  - [ ] No containers with --privileged
  - [ ] All secrets use LoadCredential or agenix
  - [ ] All services have basic hardening
  - [ ] systemd-analyze security scores reviewed

- [ ] **Performance validation**
  - [ ] Resource usage within limits
  - [ ] No CPU/memory exhaustion
  - [ ] Disk space stable (log rotation working)
  - [ ] Network throughput acceptable

---

## Completion Criteria

### Phase 1 Complete When:
- [ ] All CRITICAL issues resolved
- [ ] All HIGH severity security issues resolved
- [ ] Services tested and stable
- [ ] No regressions in functionality

### Phase 2 Complete When:
- [ ] 80%+ containers using hwc-container module
- [ ] All monitors using hwc-monitor module
- [ ] Shared patterns documented
- [ ] Migration guides written

### Phase 3 Complete When:
- [ ] 90%+ services have security score 8+/10
- [ ] Zero hard-coded paths (except /nix/store)
- [ ] All services using systemd directories
- [ ] Security audit passes

### Phase 4 Complete When:
- [ ] Documentation complete and reviewed
- [ ] Automated testing in place
- [ ] CI pipeline functional
- [ ] Team trained on new patterns

---

## Success Metrics

Track these metrics before and after refactoring:

| Metric | Before | Target | Actual |
|--------|--------|--------|--------|
| Avg security score | 3.2/10 | 8.0/10 | ___ |
| Services as root | 48/60 | <10/60 | ___ |
| Privileged containers | 2/15 | 0/15 | ___ |
| Hard-coded paths | 40 | 0 | ___ |
| Services with hardening | 8/60 | 55+/60 | ___ |
| Lines of container config | ~2000 | <500 | ___ |

---

## Rollback Procedures

### If a Phase Fails

**Phase 1 Rollback:**
```bash
git revert <commit-range>
nixos-rebuild switch --flake .#hwc-server
systemctl restart affected-services
```

**Phase 2 Rollback:**
- Containers retain old images for 30 days
- Can switch back to old pattern by reverting commits
- Test in VM before production

**Phase 3 Rollback:**
- Hardening is additive, can be disabled per-service
- Remove offending directives if breaking functionality

### Emergency Rollback

```bash
# Full rollback to audit start
git checkout <pre-audit-commit>
nixos-rebuild switch --flake .#hwc-server
```

---

## Notes & Issues

Use this section to track blockers, questions, and decisions:

### Blockers
-

### Questions
-

### Decisions
-

### Issues Found During Implementation
-

---

**Checklist Created:** 2025-11-19
**Last Updated:** _______
**Completed:** ___ / 200+ items

