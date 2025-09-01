# Phase 4: Testing & Documentation - Execution Guide

**CRITICAL**: Do not proceed unless Phase 3 is complete with full toggle control and ZERO Charter v4 violations.

## Prerequisites Verification

**MANDATORY**: Before starting, run these commands and verify results:

```bash
./scripts/validate-charter-v4.sh
```
**REQUIRED RESULT**: "✅ No violations found"

```bash
nixos-rebuild test --flake .#hwc-laptop
```
**REQUIRED RESULT**: Build succeeds without errors

```bash
# Verify toggle system works
rg "hwc\.[^.]*\..*\.enable.*true" profiles/ | wc -l
```
**REQUIRED RESULT**: >0 (shows toggles are active)

If any check fails, STOP and complete Phase 3 first.

## Phase 4 Overview

**GOAL**: Comprehensive testing and documentation of the fully refactored Charter v4 architecture.

**SUCCESS CRITERIA**:
- All machine configurations build successfully
- All services function correctly in isolation and combination
- Complete documentation for architecture and usage patterns
- Performance meets or exceeds baseline
- Migration retrospective completed

## Step 4.1: Machine Configuration Testing

**MANDATORY**: Test all machine configurations independently.

### 4.1.1: Identify All Machine Configurations

**DISCOVERY**:
```bash
find machines/ -name "config.nix" | sed 's|machines/||; s|/config.nix||'
```

**EXPECTED OUTPUTS**: `laptop`, `server`, etc.

### 4.1.2: Test Each Machine Configuration

**FOR EACH machine configuration found**:

1. **Test build**:
```bash
nixos-rebuild test --flake .#hwc-MACHINE_NAME
```
**EXAMPLE**: `nixos-rebuild test --flake .#hwc-laptop`

2. **Record build time**:
```bash
time nixos-rebuild test --flake .#hwc-MACHINE_NAME 2>&1 | tee "build-test-MACHINE_NAME.log"
```

3. **Verify no warnings or errors**:
```bash
grep -i "error\|warning" "build-test-MACHINE_NAME.log"
```

4. **Document any issues** in `docs/MACHINE_TEST_RESULTS.md`

### 4.1.3: Machine Configuration Compliance

**FOR EACH machine configuration**:

1. **Verify contains only facts and toggles**:
```bash
rg "systemd\.|virtualisation\.|environment\." machines/MACHINE_NAME/config.nix
```
**REQUIRED RESULT**: No matches (implementation should be in modules)

2. **Verify hardware facts are appropriate**:
```bash
rg "hwc\.(gpu|paths|networking)" machines/MACHINE_NAME/config.nix
```
**REQUIRED**: Only machine-specific hardware facts

3. **Check service toggles match machine purpose**:
```bash
rg "hwc\.services\..*enable.*true" machines/MACHINE_NAME/config.nix
```

## Step 4.2: Service Functionality Testing

**MANDATORY**: Test every service individually and in combination.

### 4.2.1: Generate Service Test Matrix

**IDENTIFY ALL SERVICES**:
```bash
find modules/services/ -name "*.nix" -exec basename {} .nix \; | sort > docs/SERVICE_LIST.txt
```

**CREATE TEST COMBINATIONS**:
- Single service tests
- Service group tests (e.g., all media services)
- Full system test

### 4.2.2: Individual Service Testing

**FOR EACH service in SERVICE_LIST.txt**:

1. **Create isolated test profile**:
```bash
cp profiles/base.nix profiles/test-SERVICE_NAME.nix
```

2. **Add only the target service**:
```nix
# In profiles/test-SERVICE_NAME.nix
hwc.services.SERVICE_NAME.enable = true;
# Include required dependencies only
```

3. **Test in isolation**:
```bash
# Temporarily modify machine config to use test profile
nixos-rebuild test --flake .#hwc-laptop
```

4. **Verify service functionality**:
```bash
# Service status
sudo systemctl status podman-SERVICE_NAME.service 2>/dev/null || sudo systemctl status SERVICE_NAME.service

# Network connectivity (if applicable)
curl -f http://localhost:PORT || echo "Service not responding on expected port"

# Log check
journalctl -u "*SERVICE_NAME*" --since="1 minute ago" --no-pager
```

5. **Document results**:
```bash
echo "SERVICE_NAME: [PASS/FAIL] - Notes" >> docs/SERVICE_TEST_RESULTS.md
```

6. **Clean up test profile**:
```bash
rm profiles/test-SERVICE_NAME.nix
```

### 4.2.3: Service Group Testing

**MANDATORY GROUPS TO TEST**:

1. **Media Stack**: All *arr services + qBittorrent + Jellyfin
2. **Monitoring Stack**: Prometheus + Grafana
3. **AI Stack**: Ollama + related services
4. **Infrastructure Stack**: All hwc.infrastructure services

**FOR EACH group**:

1. **Enable all services in group**:
```nix
# Example for media stack
hwc.services = {
  radarr.enable = true;
  sonarr.enable = true;
  lidarr.enable = true;
  qbittorrent.enable = true;
  jellyfin.enable = true;
};
```

2. **Test build and functionality**
3. **Verify service interactions work** (e.g., Radarr can communicate with qBittorrent)

## Step 4.3: Performance Analysis

**MANDATORY METRICS COLLECTION**:

### 4.3.1: Build Performance Analysis

1. **Baseline measurement** (clean build):
```bash
nix-collect-garbage -d
time nixos-rebuild test --flake .#hwc-laptop > build-performance-baseline.log 2>&1
```

2. **Incremental build measurement**:
```bash
# Make small change and measure rebuild time
echo "# Performance test comment" >> modules/services/media/jellyfin.nix
time nixos-rebuild test --flake .#hwc-laptop > build-performance-incremental.log 2>&1
git checkout HEAD -- modules/services/media/jellyfin.nix
```

3. **Module evaluation performance**:
```bash
nix eval --show-trace .#nixosConfigurations.hwc-laptop.config.system.build.toplevel 2>&1 | tee eval-performance.log
```

### 4.3.2: System Resource Analysis

**DOCUMENT SYSTEM IMPACT**:

1. **Memory usage of modular architecture**:
```bash
nix-store --query --requisites /run/current-system | wc -l > store-path-count.txt
nix path-info -S /run/current-system > store-size.txt
```

2. **Service startup times**:
```bash
systemd-analyze critical-chain
systemd-analyze blame | head -20
```

## Step 4.4: Architecture Documentation

**MANDATORY DOCUMENTATION CREATION**:

### 4.4.1: Create Architecture Overview

**CREATE FILE**: `docs/ARCHITECTURE_OVERVIEW.md`

**REQUIRED SECTIONS**:

1. **Domain Structure**:
```bash
find modules/ -type d | sort | sed 's|^|    |' > docs/domain-structure.txt
```

2. **Service Catalog**:
```bash
find modules/services/ -name "*.nix" -exec head -5 {} \; | grep "^#.*- " > docs/service-descriptions.txt
```

3. **Toggle Reference**:
```bash
rg "options\.hwc\." modules/ -A 3 | grep "mkEnableOption\|description" > docs/toggle-reference.txt
```

4. **Dependency Map**:
```bash
rg "DEPENDENCIES.*Upstream" modules/ -A 3 > docs/dependency-map.txt
```

### 4.4.2: Create Usage Patterns Guide

**CREATE FILE**: `docs/USAGE_PATTERNS.md`

**MANDATORY CONTENT**:

1. **How to add a new service**
2. **How to modify existing service configuration**  
3. **How to create new machine configuration**
4. **How to debug service issues**
5. **Charter v4 compliance checklist**

### 4.4.3: Create Troubleshooting Guide

**CREATE FILE**: `docs/TROUBLESHOOTING.md`

**REQUIRED SECTIONS**:

1. **Common build failures and solutions**
2. **Service startup issues**
3. **Network connectivity problems**
4. **Storage/persistence issues**
5. **Charter v4 violation fixes**

### 4.4.4: Update All Module Documentation

**FOR EACH MODULE**, verify header documentation is accurate:

1. **Dependencies section matches actual dependencies**
2. **Usage examples are correct**
3. **Options are documented**

**AUTOMATED CHECK**:
```bash
find modules/ -name "*.nix" -exec grep -L "DEPENDENCIES\|USED BY\|USAGE:" {} \; > docs/modules-missing-docs.txt
```

If any modules found, update their headers.

## Step 4.5: Migration Retrospective

**MANDATORY ANALYSIS**:

### 4.5.1: Create Migration Report

**CREATE FILE**: `docs/MIGRATION_RETROSPECTIVE.md`

**REQUIRED ANALYSIS**:

1. **Quantitative Results**:
```bash
# Count modules by domain
find modules/ -name "*.nix" | cut -d/ -f2 | sort | uniq -c

# Count lines of code by domain  
find modules/ -name "*.nix" -exec wc -l {} + | grep -v total | sort -nr

# Service count
find modules/services/ -name "*.nix" | wc -l
```

2. **Charter v4 Compliance Score**:
```bash
./scripts/validate-charter-v4.sh > docs/final-compliance-report.txt
```

3. **Performance Impact**:
   - Build time comparison (before vs after)
   - System resource usage
   - Service startup time analysis

### 4.5.2: Identify Lessons Learned

**DOCUMENT**:

1. **Architectural decisions that worked well**
2. **Challenges encountered and how they were solved**
3. **Patterns that should be avoided**
4. **Recommendations for future development**

### 4.5.3: Create Maintenance Plan

**DOCUMENT ONGOING MAINTENANCE**:

1. **Regular validation schedule** (how often to run Charter v4 checks)
2. **Service update procedures**
3. **New service addition workflow**
4. **Performance monitoring recommendations**

## Step 4.6: Final Validation Suite

**COMPREHENSIVE FINAL TESTING**:

### 4.6.1: Create Automated Test Suite

**CREATE FILE**: `scripts/full-system-test.sh`

**MUST INCLUDE**:
```bash
#!/usr/bin/env bash
set -euo pipefail

echo "🔍 Running comprehensive system validation..."

# Charter compliance
./scripts/validate-charter-v4.sh

# Build all machines
for machine in $(find machines/ -name "config.nix" | sed 's|machines/||; s|/config.nix||'); do
    echo "Testing hwc-$machine..."
    nixos-rebuild test --flake .#hwc-$machine
done

# Service functionality tests
# (Add specific service tests here)

echo "✅ Full system validation complete"
```

### 4.6.2: Execute Final Test Suite

```bash
chmod +x scripts/full-system-test.sh
./scripts/full-system-test.sh 2>&1 | tee docs/FINAL_VALIDATION_LOG.txt
```

**REQUIRED RESULT**: All tests pass

### 4.6.3: Security Validation

**MANDATORY CHECKS**:

1. **No secrets in plaintext**:
```bash
rg "password.*=" modules/ machines/ profiles/ | grep -v "TODO\|EXAMPLE"
```
**REQUIRED RESULT**: No matches

2. **Proper agenix integration**:
```bash
rg "age\.secrets" modules/ | wc -l
```

3. **No hardcoded sensitive paths**:
```bash
rg "/etc/\|/var/\|/tmp/" modules/ | grep -v "hwc.paths\|/nix/store"
```

## Phase 4 Completion Criteria

**ALL of the following MUST be true**:

1. **All Machines Build**: Every machine configuration builds successfully
2. **All Services Function**: Every service works correctly in isolation and combination  
3. **Performance Acceptable**: Build times and resource usage within acceptable limits
4. **Documentation Complete**: All required documentation files exist and are accurate
5. **Test Suite Passes**: Automated test suite runs without failures
6. **Charter Compliance**: Zero violations maintained throughout testing
7. **Retrospective Complete**: Migration analysis and lessons learned documented

## Failure Recovery

**If any criterion fails**:

1. **Document specific failure** in detail
2. **Determine if issue is**:
   - Configuration problem (fix and retest)
   - Architectural problem (may require Phase 2/3 revision)
   - Documentation problem (update docs)
3. **Do not mark Phase 4 complete** until ALL criteria met

## Final Deliverables

**MANDATORY FILES AT COMPLETION**:

- `docs/ARCHITECTURE_OVERVIEW.md`
- `docs/USAGE_PATTERNS.md`
- `docs/TROUBLESHOOTING.md`
- `docs/MIGRATION_RETROSPECTIVE.md`
- `docs/FINAL_VALIDATION_LOG.txt`
- `scripts/full-system-test.sh`

**FINAL VALIDATION**:
```bash
./scripts/full-system-test.sh && echo "🎉 Phase 4 Complete - Charter v4 Migration Successful!"
```

**Phase 4 is complete when the Charter v4 architecture is fully tested, documented, and proven to be production-ready.**