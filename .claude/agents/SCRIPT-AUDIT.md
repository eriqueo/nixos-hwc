# Script Audit: What You Already Have

## Overview

You have **~80+ scripts** across multiple categories. The key question is: **Which ones do you actually use?**

---

## Script Inventory by Category

### 🤖 Automation (22 scripts)

#### Bible System (9 scripts) - `workspace/automation/bible/`
**Purpose:** Bible app automation system
- `bible_debug_toolkit.py`
- `bible_post_build_hook.sh`
- `bible_rewriter.py`
- `bible_system_cleanup.py`
- `bible_system_installer.py`
- `bible_system_migrator.py`
- `bible_system_validator.py`
- `bible_workflow_manager.py`
- `consistency_manager.py`

**Usage Question:** Do you actively use the Bible system? Or is this legacy?

#### Media Automation (5 scripts)
**Purpose:** Media download/processing automation
- `workspace/automation/media-orchestrator.py` - Event-driven media workflow
- `workspace/automation/qbt-finished.sh` - qBittorrent post-processing
- `workspace/automation/sab-finished.py` - SABnzbd post-processing
- `workspace/automation/media/launch_frigate.sh` - Frigate launcher
- `workspace/automation/media/slskd-verify.sh` - Soulseek verification

**Usage Question:** These look actively used. Are they?

#### Media Monitoring (1 script)
- `workspace/automation/monitoring/media-monitor.py` - Media service monitoring

---

### 🏗️ Infrastructure (8 scripts)

#### Filesystem Management (4 scripts) - `workspace/infrastructure/filesystem/`
**Purpose:** NixOS file/module management
- `add-home-app.sh` - Add Home Manager apps
- `add-section-headers.sh` - Add section headers to files
- `simple-header-update.sh` - Update headers
- `update-headers.sh` - Header management

**Usage Question:** Development tools? How often used?

#### Server Management (3 scripts) - `workspace/infrastructure/server/`
- `debug-slskd.sh` - Debug Soulseek
- `fix_both.sh` - Fix script (what does this fix?)
- `test-integration.sh` - Integration testing

**Usage Question:** Active debugging tools or one-time fixes?

#### Vault Sync (1 file)
- `vault-sync-system.nix` - Obsidian vault sync

---

### 🌐 Network (10 scripts)

**Purpose:** Network analysis and security testing
- `advnetcheck.sh` - Advanced network check
- `advnetcheck2.sh` - Advanced network check v2
- `homewifi-audit.sh` - WiFi security audit
- `hw-overview.sh` - Hardware network overview
- `netcheck.sh` - Network diagnostics
- `quicknet.sh` - Quick network triage
- `toolscan.sh` - Network tool scanning
- `wifibrute.sh` - WiFi security testing
- `wifisurvery.sh` - WiFi survey
- `capture.pcap` - Packet capture data

**Usage Question:** Are these actively used or were they one-time diagnostic tools?

---

### 📝 Productivity (11 scripts)

#### AI Documentation (2 scripts) - `workspace/productivity/ai-docs/`
- `ai-docs-wrapper.sh` - AI docs wrapper
- `ai-narrative-docs.py` - AI narrative documentation

#### Transcript Formatting (9 scripts) - `workspace/productivity/transcript-formatter/`
**Purpose:** YouTube transcript processing
- `formatter.py`
- `formatting_prompt.txt`
- `nixos_formatter_runner.sh`
- `obsidian_transcript_formatter.py`
- `obsidian_transcript_formatter_backup.py`
- `playlists.py`
- `transcript-wrapper.sh`
- `yt-transcript-api.py`
- `yt_transcript.py`
- Plus cleaners: `basic.py`, `llm.py`

**Usage Question:** Active workflow or abandoned project?

#### Music Management (1 script)
- `music_duplicate_detector.sh` - Find duplicate music files

---

### 📦 Projects (3 major projects)

#### Bible Plan Project
**Purpose:** Bible app prompts/planning
- Multiple prompt files for different domains

**Usage Question:** Active project or archived?

#### Estimate Automation Project
**Purpose:** Construction estimate automation
- Full Python project with models, schemas, tests
- Templates for assemblies, labor, materials

**Usage Question:** Active business tool or development project?

#### Receipts Pipeline Project
**Purpose:** Receipt OCR and processing
- Database schema
- N8N workflows
- OCR processing
- LLM normalization

**Usage Question:** Production system or prototype?

#### Site Crawler Project
**Purpose:** SEO analysis and web scraping
- Scrapy-based crawler
- SEO analysis tools
- Multiple site data exports

**Usage Question:** Active tool or one-time use?

---

### 🔧 Utilities (35+ scripts)

#### Monitoring (5 scripts) - `workspace/utilities/monitoring/`
**Purpose:** System health monitoring
- `daily-summary.sh` - Daily system summary
- `disk-space-monitor.sh` - Disk space alerts ⭐
- `gpu-monitor.sh` - GPU monitoring
- `nixos-rebuild-notifier.sh` - Build notifications
- `systemd-failure-notifier.sh` - Service failure alerts ⭐

**Usage Question:** Which of these actually run via systemd timers?

#### Scripts (11 scripts) - `workspace/utilities/scripts/`
**Purpose:** General utilities
- `caddy-health-check.sh` - Caddy status check
- `check-gpu-acceleration.sh` - GPU acceleration verification
- `deploy-age-keys.sh` - Age key deployment
- `deploy-agent-improvements.sh` - Agent deployment
- `grebuild.sh` - Git rebuild workflow ⭐
- `journal-errors` - Extract journal errors ⭐
- `list-services.sh` - List systemd services
- `migrate-media-stack.sh` - Media stack migration
- `setup-monitoring.sh` - Monitoring setup
- `setup-tdarr-auto.py` - Tdarr automation setup
- `sops-verify.sh` - SOPS verification

**Usage Question:** Which ones do you run manually vs. automated?

#### Lints (10 scripts) - `workspace/utilities/lints/`
**Purpose:** Code quality and charter compliance
- `add-assertions.sh`
- `add-section-headers.sh`
- `analyze-namespace.sh`
- `autofix.sh`
- `charter-lint.sh` ⭐
- `debug_test.sh`
- `lint-helper.sh`
- `quick-anatomy.sh`
- `simple-checker.sh`
- `smart-charter-fix.sh`

**Usage Question:** Development tools - how often used?

#### Config Validation (6 scripts) - `workspace/utilities/config-validation/`
**Purpose:** NixOS config analysis
- `config-differ.sh`
- `config-extractor.py`
- `quick-start.sh`
- `sabnzbd-analyzer.py`
- `system-distiller.py`

#### NixOS Translator (15+ files) - `workspace/utilities/nixos-translator/`
**Purpose:** Translate configs to NixOS
- Scanners for containers, dotfiles, packages, services
- Generators for different backends
- Migration tools

**Usage Question:** One-time migration tool or ongoing use?

#### Graph Tools (5 files) - `workspace/utilities/graph/`
**Purpose:** Dependency graphing
- `graph.py`
- `hwc_graph.py`
- `scanner.py`
- `formatters.py`

#### Media Tools (3 scripts)
- `beets-container-helper.sh` - Beets music management
- `beets-helper.sh` - Beets helper
- `media-organizer.sh` - Media organization
- `media-automation-status.sh` - Media automation status
- `frigate-health.sh` - Frigate health check

---

## Analysis: Usage Patterns

### 🟢 Likely Active (High Value for Aliases)

These scripts probably run regularly and would benefit from aliases:

1. **`grebuild.sh`** - Git rebuild workflow
   - **Alias:** `rebuild` or `gr`
   - **Usage:** Daily/weekly

2. **`journal-errors`** - Extract journal errors
   - **Alias:** `errors` or `je`
   - **Usage:** Troubleshooting

3. **`disk-space-monitor.sh`** - Disk monitoring
   - **Alias:** `disk-check`
   - **Usage:** Via systemd timer + manual checks

4. **`systemd-failure-notifier.sh`** - Service failures
   - **Alias:** `service-check`
   - **Usage:** Via systemd timer + manual checks

5. **`charter-lint.sh`** - Code quality
   - **Alias:** `lint`
   - **Usage:** Development

6. **`list-services.sh`** - List services
   - **Alias:** `services` or `ss`
   - **Usage:** Regular checks

7. **Media automation scripts** (orchestrator, qbt, sab)
   - Probably automated, but might need manual triggers

### 🟡 Possibly Active (Medium Value)

These might be used occasionally:

- Network diagnostic scripts (quicknet, netcheck)
- GPU monitoring/checking
- Caddy health check
- Beets music management
- Transcript formatter (if you process videos regularly)

### 🔴 Likely Inactive (Low Value)

These look like one-time tools or archived projects:

- Bible system (unless actively developed)
- NixOS translator (migration tool)
- WiFi security testing (one-time audits)
- Site crawler (one-time SEO analysis)
- Most infrastructure/filesystem scripts (development tools)

---

## Recommendations

### Phase 1: Identify Your "Daily Drivers"

**Answer these questions:**

1. **What do you type most often?**
   - `./workspace/utilities/scripts/grebuild.sh`?
   - `journalctl -xe | grep error`?
   - Something else?

2. **What do you wish was shorter?**
   - Long paths to scripts?
   - Multi-step processes?
   - Commands you look up?

3. **What runs automatically vs. manually?**
   - Which monitoring scripts run via systemd?
   - Which do you trigger manually?

4. **What's actually broken or missing?**
   - Scripts that don't work?
   - Functionality you need but don't have?

### Phase 2: Consolidate & Alias

**Don't create new scripts. Wrap existing ones.**

#### Option A: Alias Your Top 5
Create aliases for the 5 scripts you use most:

```nix
# domains/home/shell/aliases.nix
{
  home.shellAliases = {
    # Top 5 based on your usage
    "rebuild" = "~/.nixos/workspace/utilities/scripts/grebuild.sh";
    "errors" = "~/.nixos/workspace/utilities/scripts/journal-errors";
    "services" = "~/.nixos/workspace/utilities/scripts/list-services.sh";
    "disk" = "~/.nixos/workspace/utilities/monitoring/disk-space-monitor.sh";
    "lint" = "~/.nixos/workspace/utilities/lints/charter-lint.sh";
  };
}
```

#### Option B: Create Wrapper Script
Single entry point for all monitoring:

```bash
# workspace/scripts/hwc (new consolidated script)
#!/usr/bin/env bash
# HWC utility wrapper

case "$1" in
  health)
    # Run all health checks
    ~/.nixos/workspace/utilities/monitoring/disk-space-monitor.sh
    ~/.nixos/workspace/utilities/monitoring/systemd-failure-notifier.sh
    ;;
  errors)
    ~/.nixos/workspace/utilities/scripts/journal-errors "$@"
    ;;
  services)
    ~/.nixos/workspace/utilities/scripts/list-services.sh "$@"
    ;;
  rebuild)
    ~/.nixos/workspace/utilities/scripts/grebuild.sh "$@"
    ;;
  *)
    echo "Usage: hwc {health|errors|services|rebuild}"
    ;;
esac
```

Then alias: `alias hwc="~/.nixos/workspace/scripts/hwc"`

### Phase 3: Add Agent Wrapper (Only If Needed)

**Only create agents for tasks where AI adds value:**

- **Log analysis** - Pattern recognition, root cause analysis
- **Service troubleshooting** - Diagnosis and remediation suggestions
- **System health** - Interpretation and recommendations

**Don't create agents for:**
- Simple status checks (just run the script)
- One-line commands (use aliases)
- Scripts you rarely use

---

## Questions for You

### 1. What are your actual "daily drivers"?
Which 3-5 scripts do you run most often?

### 2. What's painful right now?
What do you wish was easier/faster?

### 3. What's in systemd timers?
Which monitoring scripts run automatically?

### 4. What's dead weight?
Which scripts/projects are archived and can be ignored?

### 5. What's missing?
What do you need that doesn't exist yet?

---

## Proposed Next Steps

### Step 1: Audit Your Usage (5 minutes)
Tell me your top 5 most-used scripts from this list.

### Step 2: Create Aliases (10 minutes)
I'll create `domains/home/shell/aliases.nix` with your top 5.

### Step 3: Test (5 minutes)
Rebuild, test aliases, iterate.

### Step 4: Add Agent (Optional)
Only if there's a script where AI interpretation adds value.

---

## The Key Question

**Of all these scripts, which 3-5 do you actually use regularly?**

Everything else is noise. Let's focus on making those 3-5 incredibly convenient, then decide if any need AI wrappers.

**Tell me your top 5, and we'll make them one-word commands.**
