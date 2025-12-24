# Server Cleanup Checklist - December 2025

**Generated**: 2025-12-23
**Status**: Assessment Complete
**Priority**: Medium (no critical issues, but several improvements available)

## Recently Completed ✅

- ✅ **paths.nix Refactoring**: Established single source of truth for all paths
- ✅ **Charter Documentation**: Added §14 Path Management
- ✅ **Module Path References**: 8 modules refactored to use canonical paths
- ✅ **Charter Compliance**: Down from 99 → 97 violations (remaining are acceptable fallback values)

## Priority 1: Implementation File Hardcoded Paths

**Issue**: While options.nix files are clean, implementation files still have hardcoded paths

### Files to Update:

1. **domains/server/native/immich/index.nix** (lines 215, 275)
   - `ReadOnlyPaths = [ "/mnt/media/pictures" ]`
   - Should use: `config.hwc.paths.media.root` or similar
   - Impact: Medium - affects security sandboxing

2. **domains/server/native/orchestration/media-orchestrator.nix** (lines 4, 6)
   ```nix
   cfgRoot = "/opt/downloads";
   hotRoot = "/mnt/hot";
   ```
   - Should use: `config.hwc.paths.arr.downloads`, `config.hwc.paths.hot.root`
   - Impact: Medium - orchestrator is core media automation

3. **domains/server/native/frigate/index.nix** (lines 287, 291)
   - Assertions checking for `/mnt/` prefix
   - Should validate against `config.hwc.paths.*` instead
   - Impact: Low - validation logic, but should use canonical paths

4. **domains/server/native/monitoring/prometheus/parts/alerts.nix** (lines 160, 245)
   - Prometheus queries hardcode `mountpoint=~"/|/mnt/.*"`
   - Should use dynamic mountpoint list from paths.nix
   - Impact: Low - monitoring still works, but less flexible

**Estimated Effort**: 1-2 hours
**Benefit**: Complete path centralization, easier machine migration

## Priority 2: Documentation TODOs

**Issue**: Many modules have boilerplate TODO comments from templates

### Modules Missing Documentation:

1. **domains/server/native/networking/parts/** (5 files)
   - databases.nix, networking.nix, ntfy.nix, vpn.nix
   - All missing: description, dependencies, downstream consumers, usage examples

2. **domains/server/native/networking/database.nix**
   - Same documentation gaps

**Estimated Effort**: 2-3 hours (if documenting properly)
**Benefit**: Better maintainability, onboarding, understanding system dependencies

## Priority 3: Example/Config File Cleanup

**Issue**: Example configs have hardcoded paths that should reference variables

### Files to Update:

1. **domains/server/native/immich/example-config.nix**
   - 20+ hardcoded `/mnt/photos`, `/mnt/media` references
   - Should use: `config.hwc.paths.photos`, etc.
   - Impact: Low - example file, but good practice
   - Estimated Effort: 30 minutes

**Benefit**: Examples match actual patterns, easier to copy-paste

## Priority 4: Legacy File Cleanup

**Issue**: Obsolete shim files no longer needed

### Files to Remove:

1. **domains/server/routes.nix** (91 bytes)
   - Legacy shim: "routes moved to domains/server/native/routes.nix"
   - Check if anything still imports this
   - If not, delete it
   - Estimated Effort: 5 minutes (after verification)

**Benefit**: Cleaner repository, no confusing legacy files

## Priority 5: Service Optimization Review

**Issue**: Services may have sub-optimal resource allocations or configurations

### Areas to Review:

1. **Container Resource Limits**
   - Most containers use generic `--memory=2g --cpus=1.0`
   - Should review actual usage and tune per-service
   - Check: `podman stats` output for actual usage patterns

2. **Backup Retention Policies**
   - Multiple retention day settings across modules
   - Should consolidate or document strategy
   - Files: backup/options.nix, storage cleanup, database backups

3. **Monitoring Coverage Gaps**
   - Verify all critical services are monitored
   - Check for services without health checks
   - Review alert thresholds (currently 85% disk, 75% warning)

**Estimated Effort**: 3-4 hours (analysis + tuning)
**Benefit**: Better resource utilization, reduced memory pressure, improved monitoring

## Priority 6: Security Hardening

**Issue**: Some services may benefit from additional hardening

### Review Areas:

1. **Service Sandboxing**
   - Check which services lack `ProtectSystem`, `PrivateTmp`, etc.
   - Review ReadWritePaths restrictions
   - Example: immich has ReadOnlyPaths but could be more restrictive

2. **Container Network Isolation**
   - Verify containers are on appropriate networks
   - Check for unnecessary host network access
   - Review firewall rules per service

3. **Secret Management**
   - Audit which services have `extraGroups = [ "secrets" ]`
   - Verify no secrets in environment variables (should be in files)
   - Check secret permissions (should be 0440)

**Estimated Effort**: 2-3 hours
**Benefit**: Reduced attack surface, better isolation

## Priority 7: Charter Compliance Fine-Tuning

**Issue**: Charter linter shows 97 violations, mostly false positives

### Tasks:

1. **Update Charter Linter**
   - Distinguish between primary hardcoded paths (bad) and fallback values (acceptable)
   - Pattern: `default = config.hwc.paths.X or "/fallback"` should NOT trigger
   - Pattern: `default = "/hardcoded"` should trigger
   - Location: `workspace/utilities/lints/charter-lint.sh`

2. **Verify Remaining Violations**
   - Run compliance check: `nix build .#checks.x86_64-linux.charter-compliance`
   - Review each violation to confirm it's acceptable
   - Document any exceptions

**Estimated Effort**: 1-2 hours
**Benefit**: Accurate compliance metrics, better linter

## Optional Enhancements

### Documentation

1. **Service README Files**
   - Each complex service (immich, frigate, etc.) could have README.md
   - Document: purpose, configuration, backup strategy, troubleshooting
   - Estimated Effort: 1 hour per service

2. **Architecture Diagrams**
   - Network topology diagram
   - Storage tier flow diagram
   - Service dependency graph
   - Tool: graphviz, mermaid, or similar
   - Estimated Effort: 3-4 hours

### Automation

1. **Automated Testing**
   - Service health check scripts
   - Integration tests for critical workflows
   - Backup validation automation
   - Estimated Effort: 4-6 hours

2. **Deployment Verification**
   - Post-deployment smoke tests
   - Automated rollback on failure
   - Service dependency verification
   - Estimated Effort: 3-4 hours

### Performance

1. **Storage Tier Optimization**
   - Verify hot/cold separation is optimal
   - Review which services benefit from SSD vs HDD
   - Consider tiering adjustments
   - Estimated Effort: 2-3 hours (analysis)

2. **Database Performance Review**
   - PostgreSQL query optimization
   - Index review for frequently accessed tables
   - Connection pool tuning
   - Estimated Effort: 2-3 hours

## Immediate Action Items (Quick Wins)

1. ✅ **Delete legacy routes.nix shim** (5 min)
   - Verify nothing imports it
   - Delete if unused

2. **Update media-orchestrator.nix paths** (15 min)
   - Lines 4, 6: Use config.hwc.paths.*
   - Quick fix, high consistency value

3. **Fix immich ReadOnlyPaths** (10 min)
   - Use dynamic path from config
   - Better sandboxing, more portable

4. **Document networking modules** (30 min)
   - Fill in at least description and usage for 5 networking files
   - Immediate documentation value

**Total Quick Wins**: ~1 hour, significant improvement

## Long-Term Maintenance

### Regular Tasks (Quarterly)

- Review container resource usage and adjust limits
- Update service versions (container tags)
- Review and update backup retention policies
- Audit secret rotation dates
- Review monitoring alert thresholds
- Check for deprecated configurations

### Annual Tasks

- Full security audit
- Performance benchmarking
- Disaster recovery test
- Documentation review and updates
- Charter compliance review

## Estimation Summary

| Priority | Task | Effort | Benefit |
|----------|------|--------|---------|
| P1 | Implementation file paths | 1-2h | High |
| P2 | Documentation TODOs | 2-3h | Medium |
| P3 | Example file cleanup | 30m | Low |
| P4 | Legacy file removal | 5m | Low |
| P5 | Service optimization | 3-4h | Medium |
| P6 | Security hardening | 2-3h | High |
| P7 | Charter linter tuning | 1-2h | Medium |
| **Total** | **Critical Path** | **10-17h** | **High** |

**Quick Wins (1h)** provide immediate value and should be done first.

## Next Steps

### Recommended Order:

1. **Quick Wins** (1 hour) - immediate improvement
2. **P1: Implementation Paths** (1-2 hours) - complete path centralization
3. **P4: Legacy Cleanup** (5 minutes) - remove confusion
4. **P7: Charter Linter** (1-2 hours) - accurate metrics
5. **P6: Security Hardening** (2-3 hours) - reduce risk
6. **P2: Documentation** (2-3 hours) - ongoing, incremental
7. **P5: Optimization** (3-4 hours) - performance, when needed

### Decision Points:

- **Do now**: Quick wins + P1 implementation paths
- **Schedule soon**: P6 security hardening, P7 linter tuning
- **Ongoing**: P2 documentation as modules are touched
- **As needed**: P5 optimization when issues arise

## Related Documentation

- **CHARTER.md §14**: Path Management rules
- **docs/architecture/paths-nix-refactoring-2025-12.md**: Recent refactoring history
- **docs/troubleshooting/permissions.md**: Permission patterns and fixes
- **docs/standards/permission-patterns.md**: Standard permission configurations

## Notes

- No critical issues identified - server is in good shape
- Recent paths.nix refactoring addressed major consistency issue
- Most remaining work is polish and incremental improvement
- Focus on quick wins and high-impact items first
