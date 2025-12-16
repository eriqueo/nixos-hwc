# AI Bible - Self-Documenting NixOS System

**Version 2.0** - Rebuilt from the ground up for better performance and Charter v6.0 compliance.

## Overview

The AI Bible is a self-documenting system that automatically analyzes your NixOS configuration and generates comprehensive, up-to-date documentation using a local LLM (Ollama). It continuously monitors your codebase for changes and updates documentation incrementally.

### Key Features

✅ **Automatic Codebase Analysis** - Scans all `.nix` files and documentation
✅ **LLM-Powered Documentation** - Uses local Ollama models to generate human-readable docs
✅ **Incremental Updates** - Only regenerates docs when files change
✅ **REST API** - Query documentation programmatically
✅ **Web UI** - Browse documentation in your browser
✅ **Post-Build Integration** - Auto-scans after system rebuilds
✅ **Charter v6.0 Compliant** - Proper namespaces and domain boundaries
✅ **Security Hardened** - Systemd sandboxing and resource limits

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  AI Bible Service                    │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────────┐   ┌─────────────┐   ┌──────────┐ │
│  │   Codebase   │──▶│     LLM     │──▶│   Docs   │ │
│  │   Analyzer   │   │  Generator  │   │ Storage  │ │
│  └──────────────┘   └─────────────┘   └──────────┘ │
│         │                   │                │      │
│         ▼                   ▼                ▼      │
│  ┌─────────────────────────────────────────────┐   │
│  │            FastAPI Web Server               │   │
│  │    http://localhost:8888                    │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Components

1. **Codebase Analyzer** - Scans NixOS config, detects changes, categorizes files
2. **LLM Client** - Interfaces with Ollama for text generation
3. **Documentation Generator** - Creates markdown docs from analyzed code
4. **Web API** - REST endpoints for querying and triggering scans
5. **Web UI** - Simple browser interface for viewing docs

## Quick Start

### 1. Enable in Machine Configuration

```nix
# machines/your-machine/config.nix
{
  imports = [ ../../profiles/ai.nix ];

  # Enable AI Bible
  hwc.services.aiBible.enable = true;
}
```

### 2. Rebuild System

```bash
sudo nixos-rebuild switch --flake .
```

### 3. Access Documentation

Open in browser: `http://localhost:8888`

Or use CLI:
```bash
# Check status
ai-bible-status

# Trigger manual scan
ai-bible-scan

# View service logs
journalctl -u ai-bible -f
```

## Configuration Options

All options are under `hwc.services.aiBible`:

### Basic Settings

```nix
hwc.services.aiBible = {
  enable = true;                  # Enable the service
  port = 8888;                    # Web API port
  dataDir = "/var/lib/ai-bible";  # Data storage location
};
```

### Features

```nix
hwc.services.aiBible.features = {
  autoGeneration = true;  # Auto-scan on schedule
  llmIntegration = true;  # Use LLM for doc generation
  webApi = true;          # Enable web API/UI

  categories = [          # Documentation categories
    "system_architecture"
    "container_services"
    "hardware_gpu"
    "monitoring_observability"
    "storage_data"
    "networking"
    "backup"
  ];
};
```

### LLM Configuration

```nix
hwc.services.aiBible.llm = {
  provider = "ollama";                    # LLM provider
  model = "llama3:8b";                    # Model to use
  endpoint = "http://localhost:11434";    # Ollama endpoint
};
```

### Codebase Analysis

```nix
hwc.services.aiBible.codebase = {
  rootPath = /etc/nixos;              # Config root to scan
  scanInterval = "daily";              # How often to auto-scan
  excludePaths = [ ".git" "result" ];  # Paths to skip
};
```

## API Reference

### Endpoints

#### `GET /`
Web UI for browsing documentation

#### `GET /api/status`
Get service status and stats

Response:
```json
{
  "status": "running",
  "config": {
    "codebase_root": "/etc/nixos",
    "llm_enabled": true,
    "llm_model": "llama3:8b"
  },
  "stats": {
    "categories": 7,
    "data_dir": "/var/lib/ai-bible"
  }
}
```

#### `GET /api/categories`
List all documentation categories

Response:
```json
{
  "categories": [
    {
      "name": "system_architecture",
      "display_name": "System Architecture",
      "file": "/var/lib/ai-bible/documentation/system_architecture.md",
      "size": 15234,
      "modified": "2025-11-19T10:30:00"
    }
  ]
}
```

#### `GET /api/category/{category_name}`
Get documentation for specific category

Response:
```json
{
  "category": "container_services",
  "content": "# Container Services\n\n..."
}
```

#### `POST /api/scan`
Trigger immediate codebase scan

Response:
```json
{
  "status": "scan_started"
}
```

## How It Works

### 1. Codebase Scanning

The analyzer walks the NixOS configuration directory (`/etc/nixos`) and:
- Finds all `.nix` and `.md` files
- Computes content hashes to detect changes
- Categorizes files based on path patterns
- Caches scan results for incremental updates

### 2. Change Detection

On each scan:
- Compares current file hashes with previous scan
- Identifies new, modified, or deleted files
- Groups changes by documentation category

### 3. Documentation Generation

For each category with changes:
- Reads relevant file contents
- Constructs a detailed prompt for the LLM
- Sends to Ollama for analysis
- Receives generated markdown documentation
- Saves to data directory

### 4. Serving Documentation

The FastAPI web server:
- Serves a simple HTML UI at the root
- Provides REST API for programmatic access
- Handles scan triggers
- Returns status and statistics

## Automatic Updates

### Post-Build Scanning

When `autoGeneration` is enabled, the system automatically triggers a scan after every successful `nixos-rebuild`. This ensures documentation stays current with your configuration.

### Scheduled Scanning

The systemd timer runs based on `scanInterval`:
- `daily` - Once per day
- `weekly` - Once per week
- `hourly` - Once per hour
- Or any valid systemd timer specification

## Performance

### Optimizations

1. **Incremental Updates** - Only processes changed files
2. **Hash-based Change Detection** - Fast file comparison
3. **Scan Caching** - Reuses previous scan results
4. **Resource Limits** - 2GB memory, 100% CPU quota
5. **File Limits** - Processes max 20 files per category to avoid token limits

### Resource Usage

Typical resource consumption:
- **Memory**: 500MB - 1.5GB during generation
- **CPU**: Burst during generation, idle otherwise
- **Disk**: ~50MB for docs + logs
- **Network**: Only to local Ollama (11434)

## Troubleshooting

### Service Won't Start

Check Ollama is running:
```bash
systemctl status ollama
```

Check AI Bible logs:
```bash
journalctl -u ai-bible -n 100
```

### No Documentation Generated

1. Check if LLM is available:
```bash
ai-bible-status
```

2. Trigger manual scan:
```bash
ai-bible-scan
```

3. Check for errors:
```bash
journalctl -u ai-bible -f
```

### Slow Documentation Generation

- Default model `llama3:8b` is relatively fast
- Consider using `llama3:3b` for faster generation
- Or disable LLM integration and just use file analysis

### Permission Errors

The service runs as `ai-bible` user with:
- Read-only access to `/etc/nixos`
- Read-write access to `/var/lib/ai-bible`

Check permissions:
```bash
sudo -u ai-bible ls -la /etc/nixos
```

## Security

### Sandboxing

The systemd service is heavily sandboxed:
- `PrivateTmp` - Private /tmp
- `ProtectSystem=strict` - Read-only filesystem
- `ProtectHome` - No home directory access
- `NoNewPrivileges` - Can't escalate privileges
- `PrivateDevices` - No device access
- Resource limits enforced

### Network Access

- Only connects to local Ollama (localhost:11434)
- Firewall rules only open configured port (default 8888)
- No external network access required

### Data Privacy

- All processing happens locally
- No data leaves your machine
- Documentation stored in `/var/lib/ai-bible`
- Logs in `/var/lib/ai-bible/logs`

## Differences from Old System

### What Changed

**Removed:**
- Complex 7-agent architecture
- Hardcoded `/etc/nixos/` paths in Python
- Disconnected automation scripts
- Missing integration points
- Overly complex workflow management

**Added:**
- Single unified Python service
- Proper NixOS integration
- Environment-based configuration
- Web API and UI
- Charter v6.0 compliance
- Security hardening
- Incremental updates
- Post-build hooks

### Migration Notes

The old AI Bible system (v1) was never enabled or used. This v2 is a complete rewrite with:
- Better architecture
- Simpler codebase
- Proper integration
- Actual functionality

No migration needed since the old system was unused.

## Examples

### Example 1: Enable with Custom Model

```nix
hwc.services.aiBible = {
  enable = true;
  llm.model = "codellama:13b";  # Use CodeLlama for code analysis
};
```

### Example 2: Scan Only (No LLM)

```nix
hwc.services.aiBible = {
  enable = true;
  features.llmIntegration = false;  # Disable AI generation
  features.autoGeneration = true;    # Still scan for changes
};
```

### Example 3: Custom Categories

```nix
hwc.services.aiBible = {
  enable = true;
  features.categories = [
    "my_custom_category"
    "hardware_gpu"
  ];
};
```

## Development

### Project Structure

```
domains/server/ai/ai-bible/
├── default.nix              # Module aggregator
├── options.nix              # All configuration options
├── parts/
│   └── ai-bible.nix         # Service implementation
├── ai_bible_service.py      # Main Python service
└── README.md                # This file
```

### Testing

Test the module:
```bash
# Build without switching
nixos-rebuild build --flake .

# Check service definition
systemctl cat ai-bible

# Test Python service directly
python3 domains/server/ai/ai-bible/ai_bible_service.py
```

### Contributing

When modifying:
1. Maintain Charter v6.0 compliance
2. Keep Python dependencies minimal
3. Add comprehensive logging
4. Update this README
5. Test with and without LLM enabled

## License

Part of nixos-hwc repository. See repository root for license.

## Support

For issues or questions:
1. Check logs: `journalctl -u ai-bible`
2. Check status: `ai-bible-status`
3. File issue in repository

---

**Last Updated**: 2025-11-19
**Version**: 2.0.0
**Status**: Production Ready
