# Action Plan: From 80+ Scripts to Useful Aliases

## The Problem

You have **~80+ scripts** but probably use **5-10 regularly**.

The rest is:
- ❌ Legacy/archived projects
- ❌ One-time migration tools  
- ❌ Development utilities you rarely touch
- ❌ Scripts that don't work anymore

## The Solution

**Don't build new things. Make existing things convenient.**

```
Step 1: Identify your "daily drivers" (3-5 scripts)
Step 2: Create aliases for them
Step 3: Test and iterate
Step 4: Only then consider AI wrappers
```

---

## Quick Win: Alias Your Top 5

### Template

Create `domains/home/shell/aliases.nix`:

```nix
{ config, lib, pkgs, ... }:

{
  home.shellAliases = {
    # Replace these with YOUR most-used scripts
    "rebuild" = "${config.home.homeDirectory}/.nixos/workspace/utilities/scripts/grebuild.sh";
    "errors" = "${config.home.homeDirectory}/.nixos/workspace/utilities/scripts/journal-errors";
    "services" = "${config.home.homeDirectory}/.nixos/workspace/utilities/scripts/list-services.sh";
    "disk" = "${config.home.homeDirectory}/.nixos/workspace/utilities/monitoring/disk-space-monitor.sh";
    "lint" = "${config.home.homeDirectory}/.nixos/workspace/utilities/lints/charter-lint.sh";
  };
}
```

Then import in your home configuration:

```nix
# domains/home/index.nix (or wherever your home config is)
imports = [
  ./shell/aliases.nix
  # ... other imports
];
```

### Usage

After rebuild:

```bash
$ rebuild          # Instead of: ./workspace/utilities/scripts/grebuild.sh
$ errors           # Instead of: ./workspace/utilities/scripts/journal-errors
$ services         # Instead of: ./workspace/utilities/scripts/list-services.sh
$ disk             # Instead of: ./workspace/utilities/monitoring/disk-space-monitor.sh
$ lint domains/    # Instead of: ./workspace/utilities/lints/charter-lint.sh domains/
```

---

## Likely Candidates (Based on Script Audit)

### 🟢 High Probability You Use These

1. **`grebuild.sh`** → `rebuild`
   - Git commit + NixOS rebuild workflow
   - Probably your most-used command

2. **`journal-errors`** → `errors`
   - Extract systemd journal errors
   - Essential for troubleshooting

3. **`list-services.sh`** → `services` or `ss`
   - List systemd services
   - Quick status check

4. **`disk-space-monitor.sh`** → `disk`
   - Check disk space
   - Manual trigger for automated monitor

5. **`charter-lint.sh`** → `lint`
   - Code quality checking
   - Development workflow

### 🟡 Medium Probability

6. **`systemd-failure-notifier.sh`** → `check-services`
   - Service failure detection
   - Might be automated only

7. **`caddy-health-check.sh`** → `caddy`
   - Caddy status
   - If you troubleshoot web services often

8. **`quicknet.sh`** → `netcheck`
   - Quick network diagnostics
   - If you debug network issues

9. **`media-automation-status.sh`** → `media-status`
   - Media stack status
   - If you manage media services

10. **`frigate-health.sh`** → `frigate`
    - Frigate camera status
    - If you use Frigate

---

## The One Question

**What 3-5 commands do you type most often?**

Examples:
- `cd ~/.nixos && ./workspace/utilities/scripts/grebuild.sh`
- `journalctl -xe | grep -i error`
- `systemctl list-units --failed`
- `df -h`
- Something else?

---

## Next Steps (Choose Your Path)

### Path A: "Just Give Me Aliases" (5 minutes)

1. **You tell me:** Your top 3-5 most-used scripts
2. **I create:** `domains/home/shell/aliases.nix` with those aliases
3. **You test:** Rebuild and try them out
4. **Done:** No agents, no complexity, just convenience

### Path B: "I Want a Unified Command" (15 minutes)

1. **I create:** Single `hwc` wrapper script
2. **Usage:** `hwc health`, `hwc errors`, `hwc services`, etc.
3. **You test:** One command to rule them all
4. **Benefit:** Consistent interface, easy to remember

### Path C: "I Want AI Help Too" (30 minutes)

1. **We do Path A or B first** (aliases/wrapper)
2. **Then add:** Agent that can invoke scripts and interpret results
3. **You test:** Both terminal (offline) and Claude (online) workflows
4. **Benefit:** Works with or without internet

---

## My Recommendation

### Start with Path A

**Why:**
- ✅ 5 minutes to implement
- ✅ Immediate value
- ✅ No complexity
- ✅ Works offline
- ✅ Easy to iterate

**How:**
1. You tell me your top 3-5 scripts
2. I create the aliases file
3. You rebuild and test
4. We iterate based on what you actually use

**Then:**
- If aliases are enough → Done!
- If you want unified command → Add Path B
- If you want AI help → Add Path C

---

## The Real Question

**What do you actually type most often?**

Not "what should I monitor" or "what would be cool to have."

**What do you literally type into your terminal multiple times per week?**

Tell me those 3-5 commands, and I'll make them one word.

---

## Example: My Guess at Your Top 5

Based on the scripts and typical NixOS workflows:

1. **`rebuild`** - Git commit + rebuild (grebuild.sh)
2. **`errors`** - Check journal errors (journal-errors)
3. **`services`** - List services (list-services.sh)
4. **`disk`** - Check disk space (disk-space-monitor.sh)
5. **`lint`** - Check code quality (charter-lint.sh)

**Am I close? What would you change?**
