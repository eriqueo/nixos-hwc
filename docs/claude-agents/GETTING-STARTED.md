# Getting Started: Practical Agent + Script Architecture

## Your Dual-Use Architecture

```
┌─────────────────────────────────────────────────────────┐
│ WITH INTERNET (Claude Code)                            │
├─────────────────────────────────────────────────────────┤
│ Agent → Skill → Script                                  │
│   ↓       ↓       ↓                                     │
│ Expert  Process  Execute                                │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ WITHOUT INTERNET (Terminal)                             │
├─────────────────────────────────────────────────────────┤
│ Alias → Script                                          │
│   ↓       ↓                                             │
│ Quick   Execute                                         │
└─────────────────────────────────────────────────────────┘
```

**Key Insight:** The scripts are the foundation. They must work standalone.

---

## Current State Analysis

### ✅ What You Already Have

**Existing Monitoring Scripts:**
- `disk-space-monitor.sh` - Disk usage with ntfy alerts
- `gpu-monitor.sh` - GPU monitoring
- `systemd-failure-notifier.sh` - Service failure alerts
- `daily-summary.sh` - Daily system summary
- `nixos-rebuild-notifier.sh` - Build notifications

**Existing Utility Scripts:**
- `grebuild.sh` - Git rebuild workflow
- `list-services.sh` - Service enumeration
- `journal-errors` - Log error extraction
- `caddy-health-check.sh` - Caddy status

**Pattern Observed:**
- Scripts are already production-grade (have `set -euo pipefail`)
- Use `hwc-ntfy-send` for notifications
- Designed for systemd timer execution
- Self-contained and robust

### ❌ What's Missing

1. **No shell aliases** - Can't quickly run these from terminal
2. **No agent wrappers** - Claude can't easily invoke them
3. **No skills** - No structured workflows for common tasks
4. **Scripts scattered** - Some in `monitoring/`, some in `scripts/`

---

## Recommended Architecture

### Directory Structure

```
workspace/
├── scripts/                          # NEW: Consolidated scripts
│   ├── monitoring/                   # System health checks
│   │   ├── disk-check                # Alias-friendly names (no .sh)
│   │   ├── service-check
│   │   ├── log-check
│   │   └── system-health
│   ├── maintenance/                  # Routine maintenance
│   │   ├── cleanup-logs
│   │   ├── update-system
│   │   └── backup-verify
│   └── utils/                        # General utilities
│       ├── rebuild
│       ├── service-status
│       └── container-status
├── utilities/                        # Keep existing structure
│   ├── monitoring/                   # Legacy location
│   └── scripts/                      # Legacy location
```

### Alias Configuration

**Location:** `domains/home/shell/aliases.nix` (NEW)

```nix
# domains/home/shell/aliases.nix
{ config, lib, pkgs, ... }:

{
  home.shellAliases = {
    # Monitoring
    "disk-check" = "$HOME/.nixos/workspace/scripts/monitoring/disk-check";
    "service-check" = "$HOME/.nixos/workspace/scripts/monitoring/service-check";
    "log-check" = "$HOME/.nixos/workspace/scripts/monitoring/log-check";
    "health" = "$HOME/.nixos/workspace/scripts/monitoring/system-health";
    
    # Maintenance
    "cleanup" = "$HOME/.nixos/workspace/scripts/maintenance/cleanup-logs";
    "update-check" = "$HOME/.nixos/workspace/scripts/maintenance/update-system --check";
    
    # Utils
    "rebuild" = "$HOME/.nixos/workspace/scripts/utils/rebuild";
    "ss" = "$HOME/.nixos/workspace/scripts/utils/service-status";
    "cs" = "$HOME/.nixos/workspace/scripts/utils/container-status";
  };
}
```

### Agent Configuration

**Location:** `.claude/agents/sysadmin-agent.md` (NEW)

This agent would:
- Know about all available scripts
- Invoke them with appropriate arguments
- Interpret results
- Suggest actions based on output

---

## Best Place to Start

### Option 1: **System Health Check** (RECOMMENDED)

**Why Start Here:**
- ✅ You already have pieces (disk, gpu, systemd monitors)
- ✅ Most frequently needed
- ✅ Clear success criteria (is system healthy?)
- ✅ Immediate value

**What to Build:**

1. **Script:** `workspace/scripts/monitoring/system-health`
   - Consolidates disk, memory, CPU, services
   - Single command to check everything
   - Outputs human-readable summary
   - Exit codes: 0=healthy, 1=warnings, 2=critical

2. **Alias:** `health` 
   - Quick terminal check
   - Usage: `health` or `health --verbose`

3. **Skill:** `.claude/skills/system-health-check.md`
   - Run health check
   - Interpret results
   - Suggest fixes for issues

4. **Agent:** `.claude/agents/sysadmin-agent.md`
   - System administration expert
   - Can run health checks
   - Can diagnose issues
   - Can suggest remediation

**Example Usage:**

```bash
# Terminal (no internet)
$ health
✅ System Health: OK
  ✅ Disk: 45% used (55% free)
  ✅ Memory: 8.2GB / 32GB (25%)
  ✅ CPU: 12% average
  ✅ Services: 47/47 running
  ⚠️  GPU: Not detected

# Claude Code (with internet)
User: "Check system health"
Agent: [Runs system-health script]
       "System is healthy overall. GPU not detected - is this expected?"
```

---

### Option 2: **Service Status Check**

**Why This:**
- ✅ Frequently needed ("Is X running?")
- ✅ Clear output
- ✅ Easy to build on

**What to Build:**

1. **Script:** `workspace/scripts/monitoring/service-check`
   - Check specific service or all services
   - Show status, uptime, recent logs
   - Exit codes based on health

2. **Alias:** `service-check` or `ss`
   - Usage: `ss plex` or `ss --all`

3. **Skill:** `.claude/skills/service-troubleshoot.md`
   - Check service status
   - Analyze logs
   - Suggest restart/fixes

---

### Option 3: **Log Analysis**

**Why This:**
- ✅ You already have `journal-errors`
- ✅ Frequently needed for troubleshooting
- ✅ AI can add value (pattern recognition)

**What to Build:**

1. **Script:** `workspace/scripts/monitoring/log-check`
   - Extract recent errors
   - Filter by service
   - Summarize patterns

2. **Alias:** `log-check` or `errors`
   - Usage: `errors` or `errors plex`

3. **Skill:** `.claude/skills/log-analysis.md`
   - Run log check
   - Identify patterns
   - Suggest root causes

---

## Recommended Starting Point

### Start with: **System Health Check**

**Phase 1: Build the Script**
1. Create `workspace/scripts/monitoring/system-health`
2. Consolidate existing monitors (disk, memory, CPU, services)
3. Add clear output format
4. Test thoroughly

**Phase 2: Add Alias**
1. Create `domains/home/shell/aliases.nix`
2. Add `health` alias
3. Test from terminal

**Phase 3: Create Skill**
1. Create `.claude/skills/system-health-check.md`
2. Define workflow for running and interpreting
3. Test with Claude

**Phase 4: Create Agent**
1. Create `.claude/agents/sysadmin-agent.md`
2. Include system-health-check skill
3. Test end-to-end

---

## Success Criteria

### For the Script
- [ ] Runs standalone (no dependencies on Claude)
- [ ] Clear, human-readable output
- [ ] Proper exit codes (0=ok, 1=warn, 2=critical)
- [ ] Fast (< 5 seconds)
- [ ] Handles errors gracefully

### For the Alias
- [ ] Easy to remember (`health` not `system-health-check.sh`)
- [ ] Works from any directory
- [ ] No setup required (just rebuild)

### For the Skill
- [ ] Minimal user input required
- [ ] Interprets script output correctly
- [ ] Provides actionable recommendations
- [ ] Saves time vs. manual prompting

### For the Agent
- [ ] Knows when to use the skill
- [ ] Can run without excessive prompting
- [ ] Provides value beyond just running script
- [ ] Actually gets used (not shelf-ware)

---

## Anti-Patterns to Avoid

### ❌ Don't Create Agents You Won't Use
**Problem:** "I should have an agent for everything"
**Solution:** Only create agents for tasks you do weekly or more

### ❌ Don't Make Scripts Depend on Claude
**Problem:** Script requires AI to interpret output
**Solution:** Script output should be human-readable standalone

### ❌ Don't Overcomplicate Aliases
**Problem:** `alias health="cd ~/.nixos && ./workspace/scripts/monitoring/system-health.sh --verbose --format=json | jq ."`
**Solution:** `alias health="~/.nixos/workspace/scripts/monitoring/system-health"`

### ❌ Don't Scatter Scripts
**Problem:** Scripts in 5 different directories
**Solution:** Consolidate in `workspace/scripts/` with clear categories

### ❌ Don't Skip the Script
**Problem:** Agent that just runs commands directly
**Solution:** Always create reusable script first, then wrap with agent

---

## Questions to Answer Before Building

### 1. What do you actually run frequently?
- What commands do you type most often?
- What checks do you do daily/weekly?
- What troubleshooting steps do you repeat?

### 2. What's painful without internet?
- What can't you do when Claude is unavailable?
- What do you wish you had aliased?
- What do you have to look up every time?

### 3. Where would AI add value?
- What tasks require interpretation?
- What has complex decision trees?
- What benefits from pattern recognition?

---

## Next Steps

### Immediate:
1. **Answer the questions above** - Identify your top 3 pain points
2. **Pick one to start** - System health check recommended
3. **Build the script first** - Make it work standalone
4. **Add the alias** - Make it convenient
5. **Test without Claude** - Ensure it's useful on its own

### Then:
6. **Create the skill** - Define the workflow
7. **Create/extend the agent** - Add AI value
8. **Test with Claude** - Ensure it works end-to-end
9. **Use it for real** - Actually use it, don't just build it

### Finally:
10. **Iterate** - Improve based on actual use
11. **Expand** - Add your #2 and #3 pain points
12. **Document** - Update this guide with learnings

---

## My Recommendation

**Start with a single, high-value script:**

**Build:** `system-health` script
**Alias:** `health`
**Use case:** "Is my server okay?"

**Why:**
- You'll use it constantly
- Works great without AI
- AI can add value (interpretation, suggestions)
- Foundation for more complex checks

**Don't build:**
- 10 agents you'll never use
- Complex workflows you don't need
- Scripts that duplicate existing tools

**Do build:**
- Things you actually need
- Things you'll actually use
- Things that work standalone

---

## Questions for You

Before we build anything, let's identify what you actually need:

1. **What do you check most often on your server?**
   - Service status?
   - Disk space?
   - Logs?
   - Something else?

2. **What's annoying to type repeatedly?**
   - Long commands?
   - Multi-step processes?
   - Commands you have to look up?

3. **What would you want aliased for offline use?**
   - What can't you do without Claude?
   - What do you wish was one command?

4. **What existing scripts do you actually use?**
   - Which ones in `workspace/utilities/monitoring/`?
   - Which ones in `workspace/utilities/scripts/`?
   - Which ones never get used?

**Answer these, and we'll build exactly what you need, not what sounds cool.**
