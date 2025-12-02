# Agent System Insights & Mission Understanding

This document captures the key insights from analyzing existing agents and defines the mission for creating automation agents, skills, and scripts for the HWC NixOS system.

---

## Core Understanding: What Are Agents?

**Agents are specialized Claude personas** that transform a general-purpose AI into a domain expert through:

1. **Structured System Prompts** - Comprehensive Markdown files that define expertise, workflows, and standards
2. **Domain Knowledge** - Deep understanding of specific areas (scripting, documentation, monitoring, etc.)
3. **Repeatable Workflows** - Defined processes for common tasks
4. **Quality Standards** - Explicit criteria for evaluating outputs
5. **Interaction Protocols** - Clear guidelines for human-AI collaboration

---

## The Agent Architecture Pattern

### Anatomy of an Effective Agent

```
┌─────────────────────────────────────────┐
│ HEADER                                  │
│ - Role (specialization)                 │
│ - Mission (objective)                   │
├─────────────────────────────────────────┤
│ CORE COMPETENCIES                       │
│ - Domain-specific skills                │
│ - Best practices                        │
│ - Standards and principles              │
├─────────────────────────────────────────┤
│ WORKFLOW MODES                          │
│ - Mode A: [Primary workflow]            │
│ - Mode B: [Secondary workflow]          │
│ - Templates and checklists              │
├─────────────────────────────────────────┤
│ INTERACTION PROTOCOL                    │
│ - How to respond to user requests       │
│ - Questions to ask                      │
│ - When to seek permission               │
├─────────────────────────────────────────┤
│ SPECIAL CONSIDERATIONS                  │
│ - Edge cases                            │
│ - Security concerns                     │
│ - Performance requirements              │
├─────────────────────────────────────────┤
│ QUALITY CHECKLIST                       │
│ - Universal criteria                    │
│ - Type-specific criteria                │
├─────────────────────────────────────────┤
│ RESPONSE STYLE                          │
│ - Communication characteristics         │
│ - Tone and approach                     │
├─────────────────────────────────────────┤
│ EXAMPLES                                │
│ - Concrete demonstrations               │
│ - Before/after comparisons              │
│ - Explanations                          │
├─────────────────────────────────────────┤
│ REMEMBER                                │
│ - Core mission reinforcement            │
│ - Self-reflection questions             │
│ - Motivational closing                  │
└─────────────────────────────────────────┘
```

---

## Key Insights from Existing Agents

### 1. Script Quality Agent

**Key Patterns:**
- **Dual Templates** - Provides complete templates for both bash and Python
- **Grading System** - Uses A-F scale for objective quality assessment
- **Mode Switching** - Different workflows for creating new vs. refactoring existing
- **Comprehensive Checklists** - Ensures nothing is forgotten
- **Security Focus** - Explicit security considerations (no `shell=True`, proper quoting)

**Best Practices Extracted:**
- Always include `set -euo pipefail` in bash scripts
- Use type hints in Python
- Provide complete, runnable templates
- Include both simple and complex examples
- Make quality criteria objective and measurable

### 2. Documentation Architect

**Key Patterns:**
- **Phased Approach** - Discovery → Structuring → Writing
- **Audience Awareness** - Different reading paths for different audiences
- **Visual Communication** - Emphasis on diagrams and mental models
- **Comprehensive Coverage** - 10 standard sections for technical docs
- **Progressive Disclosure** - Start high-level, drill down to details

**Best Practices Extracted:**
- Always explain the "why" behind decisions
- Use concrete examples from actual codebase
- Create mental models for understanding
- Document evolutionary history, not just current state
- Include troubleshooting guides

---

## Mission: Automation Agents for HWC NixOS

### Primary Objective
Create a suite of specialized agents that automate routine checks, monitors, and maintenance tasks for the HWC NixOS server infrastructure.

### Target Areas

#### 1. System Health Monitoring
**Agents Needed:**
- **System Health Agent** - CPU, memory, disk, network monitoring
- **Service Status Agent** - Systemd service health checks
- **Container Health Agent** - Docker/Podman container monitoring
- **Log Analysis Agent** - Error detection and pattern analysis

#### 2. Security & Compliance
**Agents Needed:**
- **Security Audit Agent** - Vulnerability scanning, permission checks
- **Backup Verification Agent** - Backup integrity and recency checks
- **Certificate Monitor Agent** - SSL/TLS certificate expiration tracking
- **Access Control Agent** - User and permission auditing

#### 3. Performance & Optimization
**Agents Needed:**
- **Performance Monitor Agent** - Resource usage trends and bottlenecks
- **Disk Space Agent** - Storage monitoring and cleanup recommendations
- **Network Performance Agent** - Bandwidth and latency monitoring
- **Database Health Agent** - Database performance and integrity

#### 4. Infrastructure Management
**Agents Needed:**
- **NixOS Update Agent** - Flake update monitoring and testing
- **Service Dependency Agent** - Dependency graph validation
- **Configuration Drift Agent** - Detect unauthorized changes
- **Deployment Verification Agent** - Post-deployment smoke tests

---

## Agent vs. Skill vs. Script

### Agent
**Definition:** A specialized Claude persona with comprehensive domain expertise
**Format:** Markdown file with structured sections
**Purpose:** Transform Claude into a domain expert
**Location:** `.claude/agents/`
**Example:** `script-quality-agent.md`

### Skill
**Definition:** A focused workflow for a specific task within a domain
**Format:** Markdown file with step-by-step process
**Purpose:** Automate repetitive workflows
**Location:** `.claude/skills/` (to be created)
**Example:** `agenix-secrets.md` (referenced but not yet created)

### Script
**Definition:** Executable code that performs automated tasks
**Format:** Shell script (.sh) or Python script (.py)
**Purpose:** Automate system operations
**Location:** `workspace/automation/`, `workspace/utilities/monitoring/`
**Example:** `media-monitor.py`, `disk-space-monitor.sh`

### Relationship
```
Agent (Domain Expert)
  ├── Skill 1 (Workflow)
  │   └── Script 1 (Implementation)
  ├── Skill 2 (Workflow)
  │   └── Script 2 (Implementation)
  └── Skill 3 (Workflow)
      └── Script 3 (Implementation)
```

**Example:**
```
Monitoring Agent
  ├── System Health Check Skill
  │   └── system-health-check.sh
  ├── Service Status Skill
  │   └── service-status-monitor.py
  └── Alert Generation Skill
      └── alert-generator.sh
```

---

## Integration with HWC NixOS Workflow

### 1. Agent Creation Workflow
```
1. Identify need (e.g., "Need to monitor disk space")
2. Define domain (System Monitoring)
3. Create agent file (.claude/agents/monitoring-agent.md)
4. Define workflows (Check, Alert, Report)
5. Create skills (.claude/skills/disk-space-check.md)
6. Implement scripts (workspace/utilities/monitoring/disk-space-monitor.sh)
7. Integrate with NixOS (systemd timer, service)
8. Test and iterate
```

### 2. Usage Workflow
```
1. User: "Check disk space on all volumes"
2. Claude (as Monitoring Agent): 
   - Invokes disk-space-check skill
   - Runs disk-space-monitor.sh script
   - Analyzes output
   - Generates report
   - Suggests actions if thresholds exceeded
```

### 3. Deployment Workflow
```
1. Agent defines standards and workflows
2. Skills provide step-by-step processes
3. Scripts implement automation
4. NixOS modules deploy scripts
5. Systemd services/timers run scripts
6. Monitoring collects metrics
7. Alerts notify of issues
```

---

## Design Principles for HWC Agents

### 1. Charter Compliance
All agents must follow HWC Charter principles:
- Modular design
- Clear separation of concerns
- Declarative configuration
- Reproducibility
- Documentation

### 2. Quality Standards
All outputs must meet quality criteria:
- **Robust** - Handle errors gracefully
- **Secure** - No vulnerabilities or credential exposure
- **Maintainable** - Clear code, good documentation
- **Efficient** - Appropriate resource usage
- **Testable** - Predictable, verifiable behavior

### 3. NixOS Integration
All scripts must integrate properly:
- Deployed via NixOS modules
- Use agenix for secrets
- Follow systemd best practices
- Respect filesystem hierarchy
- Use proper logging

### 4. Monitoring & Alerting
All monitoring must be actionable:
- Clear metrics and thresholds
- Meaningful alerts (not noise)
- Actionable recommendations
- Historical trend tracking
- Integration with notification system (NTFY)

---

## Agent Creation Priorities

### Phase 1: Foundation (Immediate)
1. **Monitoring Agent** - System health checks
2. **Script Quality Agent** - Already exists, enhance for monitoring scripts
3. **Skills Directory** - Create `.claude/skills/` structure

### Phase 2: Core Automation (Short-term)
4. **Service Health Agent** - Systemd service monitoring
5. **Log Analysis Agent** - Error detection and alerting
6. **Disk Space Agent** - Storage monitoring

### Phase 3: Advanced Features (Medium-term)
7. **Security Audit Agent** - Vulnerability scanning
8. **Performance Monitor Agent** - Resource optimization
9. **Backup Verification Agent** - Backup integrity

### Phase 4: Optimization (Long-term)
10. **NixOS Update Agent** - Automated update testing
11. **Configuration Drift Agent** - Change detection
12. **Deployment Verification Agent** - Post-deploy validation

---

## Success Criteria

### For Agents
- [ ] Comprehensive domain coverage
- [ ] Clear, actionable workflows
- [ ] Quality standards defined
- [ ] Examples demonstrate best practices
- [ ] Tested with real scenarios
- [ ] Documented in README

### For Skills
- [ ] Step-by-step process defined
- [ ] Minimal user input required
- [ ] Handles common edge cases
- [ ] Integrates with scripts
- [ ] Saves significant time/tokens

### For Scripts
- [ ] Follows quality standards (A or B grade)
- [ ] Integrates with NixOS
- [ ] Uses agenix for secrets
- [ ] Proper error handling
- [ ] Comprehensive logging
- [ ] Systemd integration

---

## Metrics for Success

### Agent Effectiveness
- **Task Completion Rate** - % of tasks successfully completed
- **Quality Score** - Average quality of generated scripts (A-F scale)
- **Token Efficiency** - Tokens saved vs. manual prompting
- **User Satisfaction** - Feedback on agent usefulness

### Automation Coverage
- **Services Monitored** - % of services with health checks
- **Alert Response Time** - Time from issue to notification
- **False Positive Rate** - % of alerts that weren't real issues
- **Automation Percentage** - % of routine tasks automated

### System Health
- **Uptime** - System availability percentage
- **Issue Detection Time** - Time to detect problems
- **Resolution Time** - Time from detection to resolution
- **Preventive Actions** - Issues caught before impact

---

## Next Steps

### Immediate Actions
1. ✅ Create `.claude/agents/` structure (already exists)
2. ✅ Create agent template (AGENT-TEMPLATE.md)
3. ✅ Create agent creation guide (AGENT-CREATION-GUIDE.md)
4. ⏳ Create `.claude/skills/` directory
5. ⏳ Create first monitoring agent
6. ⏳ Create first monitoring script
7. ⏳ Test end-to-end workflow

### Short-term Goals
- Build out monitoring agent suite
- Create 5-10 core monitoring scripts
- Integrate with systemd timers
- Set up NTFY alerting
- Document usage patterns

### Long-term Vision
- Comprehensive automation coverage
- Self-healing capabilities
- Predictive maintenance
- Automated optimization
- Full observability

---

## Key Takeaways

### What Makes a Good Agent
1. **Specificity** - Clear domain and purpose
2. **Structure** - Defined workflows and processes
3. **Standards** - Explicit quality criteria
4. **Examples** - Concrete demonstrations
5. **Practicality** - Solves real problems

### What Makes a Good Skill
1. **Focus** - Single, well-defined task
2. **Efficiency** - Saves time and tokens
3. **Automation** - Minimal user input
4. **Reliability** - Consistent results
5. **Integration** - Works with scripts and tools

### What Makes a Good Script
1. **Robustness** - Handles errors gracefully
2. **Security** - No vulnerabilities
3. **Maintainability** - Clear and documented
4. **Efficiency** - Appropriate resource usage
5. **Integration** - Works with NixOS ecosystem

---

## Conclusion

The agent system provides a powerful framework for codifying expertise and automating routine tasks. By creating specialized agents for monitoring, security, and infrastructure management, we can:

- **Reduce manual effort** - Automate repetitive tasks
- **Improve consistency** - Apply standards uniformly
- **Enhance reliability** - Catch issues early
- **Enable scaling** - Handle growing infrastructure
- **Facilitate learning** - Document best practices

The mission is clear: **Build a comprehensive suite of agents, skills, and scripts that automate routine checks and monitors for the HWC NixOS infrastructure, ensuring reliability, security, and performance.**

**Let's build it.**
