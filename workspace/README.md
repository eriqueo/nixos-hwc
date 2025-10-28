# HWC NixOS Workspace

## Purpose & Overview

The **HWC NixOS Workspace** is a **purpose-organized collection** of scripts, automation tools, development projects, and utilities that are **declaratively managed** as part of the NixOS configuration. All content is version-controlled and deployed automatically during system rebuilds.

**Key Principle**: Everything in the workspace is **declaratively managed** - no manual script management, all automation version-controlled, complete reproducibility across machines.

## Workspace Architecture

The workspace is organized by **purpose and function** rather than machine or technology:

```
workspace/
├── automation/                  # System & media automation scripts
│   ├── media-orchestrator.py  # Event-driven media workflow coordinator
│   ├── qbt-finished.sh        # qBittorrent post-processing hook
│   └── sab-finished.py        # SABnzbd post-processing hook
├── network/                    # Network analysis & security tools
│   ├── quicknet.sh            # Fast network triage
│   ├── advnetcheck.sh         # Advanced network diagnostics
│   ├── homewifi-audit.sh      # WiFi security auditing
│   ├── netcheck.sh           # Comprehensive network analysis
│   ├── wifibrute.sh          # WiFi security testing
│   ├── hw-overview.sh        # Hardware network overview
│   ├── toolscan.sh           # Network tool scanning
│   ├── wifisurvery.sh        # WiFi survey and analysis
│   └── capture.pcap          # Network packet captures
├── productivity/               # Personal productivity automation
│   ├── transcript-formatter/  # AI-powered transcript processing
│   │   ├── obsidian_transcript_formatter.py
│   │   ├── formatting_prompt.txt
│   │   └── nixos_formatter_runner.sh
│   └── music_duplicate_detector.sh  # Music library cleanup
├── utilities/                  # NixOS development & system utilities
│   ├── config-validation/     # NixOS configuration validation tools
│   ├── lints/                # Code quality and charter compliance
│   ├── templates/            # Code templates and scaffolding
│   ├── domains/             # Domain development utilities
│   └── tests/               # Testing utilities
├── infrastructure/            # System deployment & management
│   ├── filesystem/           # Filesystem management scripts
│   │   ├── add-home-app.sh  # Home Manager app addition
│   │   └── update-headers.sh # File header updates
│   └── vault-sync-system.nix # Obsidian vault synchronization
└── projects/                  # Development projects
    └── site-crawler/         # Web scraping and SEO analysis
        ├── crawler/         # Scrapy-based web crawler
        ├── extractor/       # Content extraction tools
        ├── data/           # Scraped data and analysis
        └── pyproject.toml  # Python project configuration
```

## Integration with NixOS

### Declarative Deployment

Scripts are **automatically deployed** during system rebuilds:

```nix
# domains/server/orchestration/media-orchestrator.nix
systemd.services.media-orchestrator-install = {
  script = ''
    # Deploy automation scripts from workspace
    cp /home/eric/.nixos/workspace/automation/media-orchestrator.py /opt/downloads/scripts/
    cp /home/eric/.nixos/workspace/automation/qbt-finished.sh /opt/downloads/scripts/
    cp /home/eric/.nixos/workspace/automation/sab-finished.py /opt/downloads/scripts/
    chmod +x /opt/downloads/scripts/*.py /opt/downloads/scripts/*.sh
  '';
};
```

### Environment Integration

The workspace is accessible via environment variables:

```bash
# Set by Home Manager development configuration
export WORKSPACE="$HOME/.nixos/workspace"
export PROJECTS="$HOME/.nixos/workspace/projects"
export SCRIPTS="$HOME/.nixos/workspace"

# Usage
cd $WORKSPACE/automation    # Access automation scripts
cd $PROJECTS               # Access development projects
```

### Service Integration

Services automatically consume workspace content:

- **SABnzbd**: Uses `automation/sab-finished.py` for post-processing
- **qBittorrent**: Uses `automation/qbt-finished.sh` for completion hooks
- **Media Orchestrator**: Deploys and runs `automation/media-orchestrator.py`
- **Transcript Formatter**: Home Manager service uses `productivity/transcript-formatter/`

## Workspace Categories

### 🤖 Automation (`automation/`)
**System and media workflow automation**

Production automation scripts that handle real-time workflows:

**Media Orchestrator** (`media-orchestrator.py`):
- **Event-driven architecture**: Monitors `/mnt/hot/events` for completion events
- **Cross-service integration**: Triggers rescans in Sonarr, Radarr, Lidarr
- **Prometheus metrics**: Exports workflow metrics for monitoring
- **Error handling**: Robust error handling and logging
- **API integration**: Uses agenix secrets for service API access

**Post-processing Hooks**:
- `qbt-finished.sh`: qBittorrent completion → JSON event creation
- `sab-finished.py`: SABnzbd completion → JSON event creation

**Deployment**: Scripts automatically deployed to `/opt/downloads/scripts/` on system rebuild.

### 🌐 Network (`network/`)
**Network analysis, security testing, and diagnostics**

Comprehensive network security and analysis toolkit:

**Analysis Tools**:
- `quicknet.sh`: Fast network triage for immediate issues
- `netcheck.sh`: Comprehensive network diagnostics and health checks
- `advnetcheck.sh`: Advanced network analysis with detailed reporting

**Security Tools**:
- `homewifi-audit.sh`: WiFi security auditing and vulnerability assessment
- `wifibrute.sh`: WiFi security testing (defensive use only)
- `wifisurvery.sh`: WiFi survey and signal analysis

**Hardware Tools**:
- `hw-overview.sh`: Hardware network interface overview
- `toolscan.sh`: Network tool availability and capability scanning

**Data**:
- `capture.pcap`: Network packet captures for analysis
- `wifi_report_*`: WiFi survey reports and data

### 📝 Productivity (`productivity/`)
**Personal productivity and content processing automation**

**Transcript Formatter** (`transcript-formatter/`):
- **AI-powered processing**: Uses Ollama/Qwen for transcript formatting
- **File monitoring**: Watches for new transcript files
- **Obsidian integration**: Formats transcripts for Obsidian vault
- **Desktop integration**: GUI prompts for save location
- **Error handling**: Robust processing with notifications

**Music Library Management**:
- `music_duplicate_detector.sh`: Analyzes music library for duplicates
- **Multi-strategy detection**: Size, name patterns, content analysis

### 🔧 Utilities (`utilities/`)
**NixOS development and system management utilities**

**Configuration Validation** (`config-validation/`):
- NixOS configuration analysis and validation
- Migration assistance and compatibility checking
- System configuration distillation and comparison

**Code Quality** (`lints/`):
- Charter compliance checking
- Code quality analysis
- Automated fixes and improvements

**Development Tools** (`templates/`, `domains/`, `tests/`):
- Code templates for new modules
- Domain development utilities
- Testing frameworks and utilities

### 🏗️ Infrastructure (`infrastructure/`)
**System deployment and infrastructure management**

**Filesystem Management** (`filesystem/`):
- `add-home-app.sh`: Automated Home Manager application addition
- File header management and consistency tools

**Vault Synchronization**:
- `vault-sync-system.nix`: Obsidian vault synchronization system
- Automated backup and sync workflows

### 📦 Projects (`projects/`)
**Development projects and applications**

**Site Crawler** (`site-crawler/`):
- **Scrapy framework**: Professional web scraping infrastructure
- **SEO analysis**: Website analysis and optimization insights
- **Data extraction**: Structured content extraction and processing
- **Python packaging**: Proper `pyproject.toml` configuration

## Development Workflow

### Adding New Scripts

1. **Choose category**: Determine purpose-based location
2. **Create script**: Add to appropriate workspace directory
3. **Test functionality**: Verify script works correctly
4. **Add to git**: `git add workspace/category/script.ext`
5. **Rebuild system**: Scripts deploy automatically

### Workspace Integration

For scripts that need system integration:

```nix
# Example: Deploy new automation script
systemd.services.my-automation-install = {
  script = ''
    cp /home/eric/.nixos/workspace/automation/my-script.py /opt/target/
    chmod +x /opt/target/my-script.py
  '';
};
```

### Environment Access

Scripts can access workspace content:

```bash
#!/bin/bash
# Access other workspace scripts
source "$WORKSPACE/utilities/lib/common.sh"

# Access project data
DATA_DIR="$WORKSPACE/projects/my-project/data"
```

## Version Control & Backup

### Git Integration

The entire workspace is version-controlled:

```bash
# All changes tracked
git add workspace/
git commit -m "feat: add new automation script"

# History preserved
git log --oneline workspace/
```

### Backup Strategy

- **Primary**: Git version control with remote backup
- **Secondary**: System backup includes workspace as part of NixOS config
- **Disaster Recovery**: Complete workspace restoration via git clone

## Security Considerations

### Script Permissions

- **Automated deployment**: Scripts get appropriate permissions during deployment
- **Principle of least privilege**: Scripts run with minimal required permissions
- **Execution control**: Only deployed scripts are executable in target locations

### Sensitive Data

- **No secrets in workspace**: All secrets managed via agenix
- **API keys**: Scripts read from agenix secret paths
- **Credentials**: No hardcoded credentials in any scripts

### Network Tools

- **Defensive use only**: Security tools for defensive analysis only
- **Documentation**: Clear usage guidelines and limitations
- **Isolation**: Network testing isolated to appropriate environments

## Integration Points

### With Domain System

- **Server Domain**: Automation scripts deployed for container services
- **Home Domain**: Productivity tools integrated with Home Manager
- **Secrets Domain**: Scripts consume API keys via agenix
- **Infrastructure Domain**: Scripts access hardware and storage paths

### With External Services

- **Media Services**: Automation scripts integrate with *arr APIs
- **AI Services**: Productivity tools use Ollama for processing
- **Monitoring**: Scripts export metrics for system monitoring
- **Notifications**: Scripts send status via NTFY

## Future Expansion

### Planned Additions

1. **Development Tools**: Enhanced development workflow automation
2. **Monitoring Scripts**: System health and performance monitoring
3. **Backup Automation**: Automated backup verification and testing
4. **Business Tools**: Business workflow automation

### Architecture Evolution

- **Modular Expansion**: Add new categories as needed
- **Cross-workspace Dependencies**: Enhanced script coordination
- **Advanced Integration**: Deeper NixOS system integration
- **Multi-machine Support**: Workspace sharing across multiple machines

---

**Workspace Version**: v2.0 - Purpose-organized declarative automation
**Charter Compliance**: ✅ Full compliance with HWC Charter v6.0
**Last Updated**: October 2024 - Post reorganization and agenix migration