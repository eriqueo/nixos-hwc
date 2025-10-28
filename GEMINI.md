# HWC Documentation Index

## ⚠️ MANDATORY FOR ALL AI ASSISTANTS ⚠️

**READ THESE DOCUMENTS BEFORE ANY WORK:**
1. **`charter.md`** (HWC Architecture Charter v6.0) - REQUIRED
2. **`FILESYSTEM-CHARTER.md`** (Home directory structure v2.0) - REQUIRED
3. **`CLAUDE.md`** (Working instructions & patterns) - REQUIRED

**Purpose**: Dynamic index to authoritative documentation sources (never duplicates content)

---

## **Core Charters** (Foundational Documents)

### **🏗️ NixOS Architecture Charter** → `charter.md`
- **Current Version**: v6.0 - Configuration Validity & Dependency Assertions
- **Scope**: Complete NixOS domain architecture, module patterns, profiles, machines
- **Key Sections**: Domain boundaries, Unit Anatomy, Lane Purity, Validation rules

### **📁 Filesystem Organization Charter** → `FILESYSTEM-CHARTER.md`
- **Current Version**: v2.0 - Integration with HWC Architecture Charter v6.0
- **Scope**: Home directory organization (`~/`) with domain-based 3-digit prefix system
- **Key Sections**: Domain definitions, XDG integration, GTD-style inbox workflow

---

## **Implementation Guides** (AI Assistant Instructions)

### **🤖 Claude Code Instructions** → `CLAUDE.md`
- **Reference Architecture**: HWC Charter v6.0
- **Purpose**: Working instructions for AI assistant, common patterns, anti-patterns
- **Key Sections**: Philosophy, rebuild commands, path mappings, troubleshooting

---

## **Architecture Documentation** → `docs/architecture/`
- **Compliance Tracking**: `compliance-lint.md` - Charter v5 compliance initiative
- **Refactoring Plans**: `PROFILE_REFACTOR_GUIDE.md` - Profile architecture evolution

---

## **Quick Reference Links**

| **Topic** | **Source Document** | **Section** |
|-----------|-------------------|-------------|
| Domain Structure | `charter.md` | §3 Domain Boundaries |
| Module Anatomy | `charter.md` | §4 Unit Anatomy |
| Home Paths | `FILESYSTEM-CHARTER.md` | Top-Level Structure |
| Rebuild Commands | `CLAUDE.md` | Common Commands |
| Validation Rules | `charter.md` | §18 Configuration Validity |

---

**Last Updated**: 2025-10-28
**Maintenance**: This index points to sources - never duplicates content to prevent staleness
