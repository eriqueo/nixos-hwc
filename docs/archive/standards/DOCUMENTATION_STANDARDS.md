# HWC Documentation Standards

**Purpose**: Standardized approach to documentation across the HWC system ensuring consistency, discoverability, and maintainability.

---

## 📁 Two-Tier Documentation Architecture

### **Tier 1: Domain READMEs** (`domains/*/README.md`)
**Role**: "How-to" guides for developers working within specific domains
**Scope**: Single domain focus
**Audience**: Domain developers, module contributors
**Lifecycle**: Updated with domain changes
**Template**: `docs/templates/DOMAIN_README_TEMPLATE.md`

### **Tier 2: Project Documentation** (`docs/`)
**Role**: Cross-domain projects, historical records, migration guides
**Scope**: Multi-domain or temporal (projects, migrations, decisions)
**Audience**: System architects, project managers, migration teams
**Lifecycle**: Created for projects, archived when obsolete
**Templates**: Various in `docs/templates/`

---

## 📋 Mandatory Documentation Requirements

### **Every Domain Must Have**
1. **`README.md`** following the standard template
2. **Purpose & Scope** clearly defined
3. **Domain Boundaries** explicitly stated
4. **Module Standards** with examples
5. **Best Practices** including anti-patterns
6. **Development Workflow** for contributors

### **Every Project Must Have**
1. **Clear scope** defining affected domains
2. **Status tracking** with completion criteria
3. **Timeline** of major milestones
4. **Validation methods** for each phase
5. **Success criteria** for completion

### **Every Migration Must Document**
1. **Before/after architecture** comparison
2. **Step-by-step process** with validation
3. **Rollback procedures** for safety
4. **Lessons learned** for future migrations
5. **Charter compliance** verification

---

## 🏗️ Documentation Patterns

### **Domain README Structure**
```markdown
# [Domain] Domain
## Purpose & Scope          # What this domain manages
## Domain Architecture      # How it's organized
## Domain Boundaries        # What it does/doesn't do
## Module Standards         # Consistent patterns
## Core Modules            # Key functionality
## Best Practices          # Do's and don'ts
## Development Workflow     # How to contribute
## Validation              # Testing and troubleshooting
## Reference Links          # Related documentation
```

### **Project Documentation Structure**
```markdown
# [Project Name]
## Project Overview        # Goals and scope
## Status                  # Current phase and progress
## Architecture           # Technical approach
## Implementation         # Step-by-step execution
## Validation             # Testing and verification
## Timeline               # Key milestones
## Lessons Learned        # Post-completion analysis
```

### **Migration Guide Structure**
```markdown
# [Migration Name]
## Migration Overview      # Why and what's changing
## Before/After           # Architecture comparison
## Prerequisites          # Requirements and dependencies
## Migration Steps        # Detailed process
## Validation             # How to verify each step
## Rollback               # How to undo if needed
## Success Criteria       # How to know it's complete
## Troubleshooting        # Common issues and solutions
```

---

## 🔍 Content Guidelines

### **Writing Style**
- **Direct and actionable**: Focus on what developers need to do
- **Example-driven**: Show concrete examples, not just theory
- **Problem-solving**: Address common issues and anti-patterns
- **Charter-aligned**: Reference Charter principles and namespace patterns

### **Code Examples**
```nix
# ✅ Good: Complete, working example with context
hwc.home.apps.firefox = {
  enable = true;
  theme = config.hwc.home.theme.palette;
  profiles.default = {
    bookmarks = [ ... ];
    extensions = [ ... ];
  };
};

# ❌ Bad: Incomplete snippet without context
enable = true;
theme = "dark";
```

### **Link Patterns**
- **Relative links**: `domains/[domain]/README.md`
- **Charter references**: `charter.md` (always root level)
- **Cross-references**: Clear relationship explanations

---

## 🔄 Maintenance Workflows

### **When to Update Domain READMEs**
**Triggers**:
- New modules added to domain
- Charter compliance changes
- Best practices evolve
- Architecture patterns change

**Process**:
1. Update affected sections
2. Verify examples still work
3. Check cross-references
4. Update "Last Updated" date

### **When to Create Project Documentation**
**Criteria**:
- Affects multiple domains
- Significant architectural change
- Migration or refactoring work
- Complex application deployment

**Process**:
1. Use appropriate template
2. Define clear scope and success criteria
3. Track progress with status updates
4. Archive when complete

### **When to Archive Documentation**
**Criteria**:
- Project completed >6 months ago
- Superseded by newer approaches
- Contradicts current Charter
- No longer relevant to system

**Process**:
1. Move to `docs/archive/`
2. Add archival date and reason
3. Update any cross-references
4. Remove from active indexes

---

## ✅ Quality Checklist

### **Domain README Quality**
- [ ] Follows standard template structure
- [ ] Clear purpose and scope definition
- [ ] Explicit domain boundaries
- [ ] Working code examples
- [ ] Anti-patterns identified
- [ ] Development workflow documented
- [ ] Charter compliance noted
- [ ] Cross-references accurate

### **Project Documentation Quality**
- [ ] Clear scope and affected domains
- [ ] Status tracking with timeline
- [ ] Validation methods defined
- [ ] Success criteria explicit
- [ ] Lessons learned captured
- [ ] Archive plan identified

### **Overall Documentation Health**
- [ ] No broken internal links
- [ ] All domains have READMEs
- [ ] Templates are current
- [ ] Archive is properly organized
- [ ] Index is up to date

---

## 📊 Documentation Metrics

### **Coverage Metrics**
- **Domain README Coverage**: 5/5 domains have READMEs
- **Template Compliance**: % following standard templates
- **Link Health**: % of internal links working
- **Freshness**: Average age of last update

### **Quality Metrics**
- **Completeness**: All required sections present
- **Accuracy**: Examples work as documented
- **Consistency**: Follows established patterns
- **Usefulness**: Addresses real developer needs

### **Maintenance Metrics**
- **Update Frequency**: How often docs are updated
- **Archive Rate**: How much gets archived vs updated
- **Cross-Reference Health**: Links between documents

---

## 🎯 Documentation Goals

### **Short-term (Next 30 days)**
- All domain READMEs follow standard template
- Project documentation moved to docs/ structure
- Email documentation consolidated
- Broken links eliminated

### **Medium-term (Next 90 days)**
- Documentation metrics dashboard
- Automated link checking
- Template compliance validation
- Regular maintenance schedule

### **Long-term (Next 180 days)**
- Documentation generates automatically from code
- AI assistant can answer questions from docs
- Community contribution guidelines
- Documentation versioning with Charter

---

**Standards Version**: v1.0
**Charter Alignment**: HWC Charter v6.0
**Last Updated**: 2025-10-28