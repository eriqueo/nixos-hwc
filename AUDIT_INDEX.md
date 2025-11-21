# Systemd Services Audit - Document Index

**Audit Date:** 2025-11-19
**Repository:** eriqueo/nixos-hwc
**Branch:** claude/audit-systemd-services-018tpGYMCXhECKE5mF4HPeRG
**Auditor:** Claude (Anthropic AI Assistant)

---

## 📋 Quick Navigation

| Document | Purpose | Who Should Read |
|----------|---------|-----------------|
| **[AUDIT_SUMMARY.md](AUDIT_SUMMARY.md)** | Executive summary, quick stats, action plan | Everyone - Start here |
| **[SYSTEMD_AUDIT_REPORT.md](SYSTEMD_AUDIT_REPORT.md)** | Complete detailed analysis of all services | Developers, security reviewers |
| **[SYSTEMD_REFACTORING_PROPOSALS.md](SYSTEMD_REFACTORING_PROPOSALS.md)** | Concrete diff patches and refactoring code | Implementers |
| **[REFACTORING_CHECKLIST.md](REFACTORING_CHECKLIST.md)** | Implementation tracking checklist | Project managers, implementers |
| **[AUDIT_INDEX.md](AUDIT_INDEX.md)** | This file - navigation guide | Everyone |

---

## 🎯 Where to Start

### If you're a **Manager/Team Lead:**
1. Read **AUDIT_SUMMARY.md** (15-20 minutes)
   - Understand critical findings
   - Review action plan and timeline
   - Assess risk vs. effort

2. Review metrics in **REFACTORING_CHECKLIST.md**
   - Track implementation progress
   - Monitor completion criteria

### If you're a **Developer/Implementer:**
1. Skim **AUDIT_SUMMARY.md** for context (10 minutes)

2. Deep-dive **SYSTEMD_AUDIT_REPORT.md** for your services
   - Understand anti-patterns
   - Study best practice examples
   - Note specific issues

3. Use **SYSTEMD_REFACTORING_PROPOSALS.md** for implementation
   - Copy diff patches
   - Follow implementation guides
   - Reference testing strategies

4. Track work in **REFACTORING_CHECKLIST.md**
   - Check off completed items
   - Note blockers and questions

### If you're a **Security Reviewer:**
1. Read **AUDIT_SUMMARY.md** critical findings

2. Review **SYSTEMD_AUDIT_REPORT.md** security sections
   - Verify anti-pattern identification
   - Assess risk ratings
   - Check hardening recommendations

3. Validate **SYSTEMD_REFACTORING_PROPOSALS.md** mitigations
   - Review proposed security directives
   - Verify secret handling improvements
   - Check capability restrictions

---

## 📊 Audit Scope

### Services Analyzed: 60+

#### By Category:
- **Infrastructure:** 4 services (GPU, WinApps, networking)
- **AI/LLM:** 7 services (Ollama, MCP, AI Bible, Fabric)
- **Containers:** 15 OCI containers + support services
- **Applications:** 3 services (Business API, Transcript API)
- **Databases:** 4 services (PostgreSQL, CouchDB, Redis)
- **Backup:** 4 services (User backup, DB backups)
- **Monitoring:** 8 services (Storage, GPU, camera watchdog)
- **System:** 5 services (Protonmail, VPN, networking)
- **Timers:** 11 scheduled services

#### By File Location:
- `domains/infrastructure/` - 2 files
- `domains/server/ai/` - 4 files
- `domains/server/apps/` - 2 files
- `domains/server/backup/` - 1 file
- `domains/server/business/` - 2 files
- `domains/server/containers/` - 25 files
- `domains/server/couchdb/` - 1 file
- `domains/server/frigate/` - 3 files
- `domains/server/monitoring/` - 2 files
- `domains/server/networking/` - 4 files
- `domains/server/storage/` - 2 files
- `domains/system/services/` - 5 files
- `workspace/infrastructure/` - 1 file

---

## 🔴 Critical Findings Summary

### Top 5 Security Issues

1. **Gluetun Container with `--privileged`** - CRITICAL
   - Full host access via privileged container
   - Can load kernel modules
   - No resource limits

2. **80% Services Run as Root** - HIGH
   - Unnecessary privilege escalation risk
   - 48 out of 60 services affected

3. **No Security Hardening (87% services)** - HIGH
   - Missing ProtectSystem, ProtectHome, NoNewPrivileges
   - 52 out of 60 services affected

4. **Secrets in Environment Variables** - HIGH
   - Database passwords visible in process list
   - Affects business-api and others

5. **No Container Resource Limits** - MEDIUM-HIGH
   - Risk of resource exhaustion
   - 12 out of 15 containers affected

---

## 🏆 Best Practice Examples

Services that demonstrate excellent patterns:

1. **protonmail-bridge** (Gold Standard - 9.5/10)
   - Complete security hardening
   - Proper user/group management
   - StateDirectory usage
   - CapabilityBoundingSet restrictions

2. **ai-bible** (Excellent - 8.5/10)
   - DynamicUser
   - StateDirectory
   - Strong ProtectSystem/ProtectHome

3. **user-backup** (Good - 8/10)
   - Well-structured scripts
   - Proper timer configuration
   - Intelligent fallback logic

4. **storage-cleanup** (Good - 7.5/10)
   - Excellent script quality
   - Addresses operational issues
   - Proper error handling

---

## 📈 Implementation Roadmap

### Phase 1: Critical Security (Week 1)
**Effort:** 16-24 hours
- Remove Gluetun `--privileged` flag
- Fix Business API secret handling
- Fix Media Orchestrator root access
- Convert high-risk services from root

### Phase 2: Standardization (Week 2)
**Effort:** 20-30 hours
- Implement `hwc-container` module
- Implement `hwc-monitor` module
- Convert containers to standard pattern
- Convert monitors to timer pattern

### Phase 3: Hardening (Week 3)
**Effort:** 16-24 hours
- Apply security baseline to all services
- Eliminate all hard-coded paths
- Add StateDirectory to all services
- Achieve 8+/10 security scores

### Phase 4: Documentation & Testing
**Effort:** Ongoing
- Update CHARTER.md
- Create service templates
- Set up automated testing
- CI integration

**Total Estimated Effort:** 52-78 hours over 3-4 weeks

---

## 📖 Document Descriptions

### AUDIT_SUMMARY.md (25 pages)
**Contents:**
- Executive summary with quick stats
- Critical findings deep-dive
- Best practice examples
- Anti-pattern "hall of shame"
- Action plan with timeline
- Success criteria and metrics
- Risk assessment
- FAQ and next steps

**Best for:** Getting overview, presenting to stakeholders, planning

---

### SYSTEMD_AUDIT_REPORT.md (150+ pages)
**Contents:**
- Service-by-service detailed analysis
- 9 major categories of services
- Line-by-line code review
- Anti-pattern identification with severity ratings
- Best practice comparisons
- Security analysis
- Comprehensive anti-pattern summary table
- Refactoring strategy overview

**Best for:** Understanding issues, learning patterns, implementation reference

---

### SYSTEMD_REFACTORING_PROPOSALS.md (60+ pages)
**Contents:**
- 6 concrete diff patches:
  1. GPU Monitor Service (timer conversion)
  2. Business API Security (secrets + hardening)
  3. Gluetun Container (remove privileged)
  4. Media Orchestrator (root + secrets)
  5. Container Standardization Module (new abstraction)
  6. Monitoring Pattern Module (new abstraction)
- Full implementation code for new modules
- Testing strategies
- Rollback procedures
- Example usage patterns

**Best for:** Copy-paste implementation, understanding solutions

---

### REFACTORING_CHECKLIST.md (35 pages)
**Contents:**
- 200+ implementation checklist items
- Organized by phase and priority
- Service-by-service tracking
- Testing validation checklist
- Completion criteria
- Success metrics tracking
- Rollback procedures
- Notes section for blockers

**Best for:** Project management, tracking progress, daily work

---

## 🔧 How to Use These Documents

### For Implementation

1. **Planning Phase:**
   - Read AUDIT_SUMMARY.md
   - Understand scope from SYSTEMD_AUDIT_REPORT.md
   - Review timeline and effort estimates

2. **Implementation Phase:**
   - Work through REFACTORING_CHECKLIST.md by priority
   - Reference SYSTEMD_REFACTORING_PROPOSALS.md for code
   - Look up specific services in SYSTEMD_AUDIT_REPORT.md as needed

3. **Review Phase:**
   - Run systemd-analyze security on changed services
   - Check off items in REFACTORING_CHECKLIST.md
   - Update metrics in AUDIT_SUMMARY.md

4. **Completion Phase:**
   - Verify all completion criteria met
   - Update CHARTER.md with new patterns
   - Archive audit documents for future reference

---

## 🎓 Learning Resources

### Understanding Systemd Security

Key directives explained:

- **DynamicUser:** Automatically creates temporary uid/gid
- **StateDirectory:** Creates `/var/lib/<service>` with proper permissions
- **ProtectSystem:** Makes system directories read-only
- **ProtectHome:** Hides user home directories
- **PrivateTmp:** Service gets isolated `/tmp`
- **NoNewPrivileges:** Prevents privilege escalation
- **CapabilityBoundingSet:** Restricts Linux capabilities
- **SystemCallFilter:** Restricts syscalls (advanced)

### Example Hardening Template

```nix
serviceConfig = {
  # User management
  DynamicUser = true;
  Group = "service-group";

  # Filesystem
  StateDirectory = "service-name";
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;

  # Security
  NoNewPrivileges = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectControlGroups = true;

  # Network
  RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
  PrivateNetwork = false;  # Set true if no network needed

  # Capabilities
  CapabilityBoundingSet = "";  # Drop all unless specifically needed

  # Logging
  StandardOutput = "journal";
  StandardError = "journal";
};
```

---

## 🚨 Important Warnings

### Before Applying Changes

1. **Test in VM first**
   ```bash
   nixos-rebuild build-vm --flake .#hwc-server
   ```

2. **Backup critical data**
   - Database dumps
   - Container volumes
   - Configuration files

3. **Plan downtime windows**
   - Some services require restart
   - Container recreation needed for limits
   - Test rollback procedure

4. **Read service-specific notes**
   - Gluetun changes affect all VPN-routed containers
   - Business API needs database password secret created
   - Media orchestrator needs Python script update

### Known Gotchas

- **DynamicUser:** May cause permission issues if service previously ran as root
- **ProtectSystem=strict:** Requires explicit ReadWritePaths for data directories
- **LoadCredential:** Script must read from $CREDENTIALS_DIRECTORY, not environment
- **Container resource limits:** May cause OOM if set too low

---

## 📞 Getting Help

### If You Get Stuck

1. **Review the specific service in SYSTEMD_AUDIT_REPORT.md**
   - Understand the current issues
   - Check the proposed solution

2. **Check SYSTEMD_REFACTORING_PROPOSALS.md**
   - Look for similar patterns
   - Review testing strategies

3. **Use systemd-analyze**
   ```bash
   systemd-analyze security service-name
   journalctl -u service-name -f
   ```

4. **Test incrementally**
   - Apply one change at a time
   - Test thoroughly before moving on
   - Keep notes in REFACTORING_CHECKLIST.md

---

## 📝 Changelog

### 2025-11-19 - Initial Audit
- Conducted comprehensive audit of 60+ services
- Identified 5 critical, 18 high, 25 medium severity issues
- Created 4 implementation documents
- Proposed 6 refactoring patterns
- Estimated 52-78 hours total effort

---

## ✅ Sign-Off

This audit has been completed to the best of my ability. All findings are based on:

- **Systemd Best Practices:** freedesktop.org systemd documentation
- **NixOS Best Practices:** Official NixOS manual and community patterns
- **Security Standards:** CIS benchmarks, NIST guidelines
- **Container Security:** Docker/Podman security recommendations
- **Operational Experience:** Common failure modes and anti-patterns

**Limitations:**
- Static analysis only (no runtime testing performed)
- Based on current codebase state (2025-11-19)
- Some context may be missing for business logic
- Assumes standard NixOS deployment patterns

**Confidence Level:** HIGH
- Clear anti-patterns identified with evidence
- Proposed solutions are tested patterns
- Refactoring strategy is proven and incremental

---

**Audit Completed:** 2025-11-19
**Documents Generated:** 5
**Total Pages:** ~270
**Services Analyzed:** 60+
**Issues Identified:** 48 major
**Best Practices Found:** 4 exemplary services

**Next Step:** Review AUDIT_SUMMARY.md and decide on implementation timeline.

