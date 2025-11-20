# hwc-graph: NixOS Module Dependency Graph Tool

A minimal, focused CLI tool for analyzing module dependencies in the NixOS HWC configuration.

## Purpose

This tool helps you:
- **Understand dependencies**: See what modules require other modules
- **Impact analysis**: Know what will break before you disable something
- **Requirements analysis**: Know what needs to be enabled for a module to work
- **Safer refactoring**: Visualize the dependency graph before making changes

## Quick Start

```bash
# From repo root
python3 workspace/utilities/graph/hwc_graph.py stats

# Or use the flake app (after flake integration)
nix run .#hwc-graph stats
```

## Commands

### List all modules
```bash
hwc-graph list
```

Shows all discovered modules grouped by domain (infrastructure, system, server, home).

**Example output:**
```
INFRASTRUCTURE (5 modules)
  hwc.infrastructure.hardware [infrastructure] (0 deps, 3 dependents)
  hwc.infrastructure.storage [infrastructure]
  ...

SERVER (27 modules)
  hwc.server.jellyfin [service] (2 deps, 0 dependents)
    ↳ requires: hwc.infrastructure.hardware.gpu.enable, hwc.services.reverseProxy.enable
  hwc.server.frigate [service] (4 deps, 0 dependents)
    ↳ requires: hwc.infrastructure.hardware.gpu, hwc.secrets.enable, ...
  ...
```

### Show module details
```bash
hwc-graph show <module-name>

# Examples:
hwc-graph show hwc.server.jellyfin
hwc-graph show hwc.infrastructure.hardware
```

Displays detailed information about a specific module, including dependencies and metadata.

**Example output:**
```
hwc.server.jellyfin - Jellyfin media server (native service)
  ├─ requires → hwc.infrastructure.hardware.gpu.enable
  └─ requires → hwc.services.reverseProxy.enable

Domain: server
Kind: service
Path: /home/user/nixos-hwc/domains/server/jellyfin
```

### Impact analysis
```bash
hwc-graph impact <module-name>

# Examples:
hwc-graph impact hwc.infrastructure.hardware
hwc-graph impact hwc.secrets
```

Shows **what depends on** this module (what will break if you disable it).

**Example output:**
```
Impact Analysis: hwc.infrastructure.hardware
================================================================================

Direct Dependents (3):
These will IMMEDIATELY break if you disable this module:

  ❌ hwc.server.frigate [service]
  ❌ hwc.server.immich [service]
  ❌ hwc.server.jellyfin [service]

================================================================================
Total Impact: 3 module(s) will be affected
⚠️  Disabling this module requires careful consideration
```

**Use cases:**
- Before disabling GPU support: `hwc-graph impact hwc.infrastructure.hardware`
- Before removing VPN: `hwc-graph impact gluetun`
- Before removing reverse proxy: `hwc-graph impact reverseProxy`

### Requirements analysis
```bash
hwc-graph requirements <module-name>

# Examples:
hwc-graph requirements hwc.server.frigate
hwc-graph requirements hwc.server.jellyfin
```

Shows **what this module needs** (what must be enabled for it to work).

**Example output:**
```
Requirements Analysis: hwc.server.frigate
================================================================================

Direct Dependencies (4):
These MUST be enabled for this module to work:

  ✓ hwc.infrastructure.hardware.gpu [infrastructure]
  ✓ hwc.infrastructure.hardware.gpu.enable
  ✓ hwc.secrets [security]
  ✓ hwc.secrets.enable

================================================================================
Total Requirements: 4 module(s) must be enabled
```

**Use cases:**
- Before enabling a new service: `hwc-graph requirements hwc.server.frigate`
- Understanding what you need for GPU transcoding: `hwc-graph requirements hwc.server.jellyfin`

### Graph statistics
```bash
hwc-graph stats
```

Shows overall graph statistics and health check.

**Example output:**
```
Graph Statistics
================================================================================

Total Modules: 81

By Domain:
  home: 37
  infrastructure: 5
  secrets: 1
  server: 27
  system: 11

By Kind:
  container: 18
  home: 37
  infrastructure: 5
  security: 1
  service: 9
  system: 11

Dependency Stats:
  Average dependencies per module: 0.21
  Average dependents per module: 0.14
  Root modules (no dependencies): 71
  Orphan modules (nothing depends on): 27

✅ No circular dependencies detected
```

### Export graph data
```bash
hwc-graph export --format=json > graph.json
```

Exports the entire dependency graph as JSON for external tools.

**JSON structure:**
```json
{
  "modules": [
    {
      "name": "hwc.infrastructure.hardware",
      "domain": "infrastructure",
      "kind": "infrastructure",
      "description": "GPU hardware acceleration support",
      "ports": [],
      "path": "domains/infrastructure/hardware",
      "dependencies_count": 0,
      "dependents_count": 3
    }
  ],
  "edges": [
    {
      "from": "hwc.server.jellyfin",
      "to": "hwc.infrastructure.hardware.gpu.enable",
      "type": "requires"
    }
  ]
}
```

## How It Works

### Dependency Discovery

The tool scans your repository and discovers dependencies through:

1. **options.nix files**: Identifies module names
   - Pattern: `options.hwc.server.jellyfin = { ... }`
   - Extracts: `hwc.server.jellyfin`

2. **Assertion statements** in index.nix:
   ```nix
   assertions = [
     {
       assertion = !cfg.enable || config.hwc.infrastructure.hardware.gpu.enable;
       message = "...";
     }
   ];
   ```
   - Detects that this module depends on `hwc.infrastructure.hardware.gpu`

3. **Comment headers**:
   ```nix
   # DEPENDENCIES:
   #   - hwc.infrastructure.hardware.gpu
   #   - hwc.secrets.enable
   ```

### Limitations

- **Heuristic-based**: Not a full Nix AST parser
- **Best-effort**: Some dynamic dependencies may be missed
- **Naming normalization**: Dependencies like `hwc.X.Y.enable` map to module `hwc.X.Y`
- **Assertion-focused**: Relies on proper assertion declarations (per Charter v6)

These limitations are intentional trade-offs for simplicity and maintainability.

## Common Workflows

### Before Disabling a Module
```bash
# Check what will break
hwc-graph impact hwc.infrastructure.hardware

# If safe, disable in your config
```

### Before Enabling a New Module
```bash
# See what it needs
hwc-graph requirements hwc.server.frigate

# Enable dependencies first
# Then enable the module
```

### Refactoring
```bash
# Get full graph overview
hwc-graph list

# Check specific modules involved
hwc-graph show hwc.server.jellyfin
hwc-graph impact hwc.infrastructure.hardware

# Export for offline analysis
hwc-graph export --format=json > graph.json
```

### Health Check
```bash
# Regular health check
hwc-graph stats

# Look for:
# - Circular dependencies (bad)
# - Orphan modules (potential cleanup)
# - High dependency counts (potential refactor targets)
```

## Integration

### Run Directly (Python)
```bash
python3 workspace/utilities/graph/hwc_graph.py <command>
```

### Run via Flake (after integration)
```bash
nix run .#hwc-graph <command>
```

### Alias (Add to your shell)
```bash
alias hwc-graph='python3 ~/nixos-hwc/workspace/utilities/graph/hwc_graph.py'
```

## Design Principles

1. **Small and hackable**: ~500 lines of Python, easy to understand and extend
2. **No external dependencies**: Uses only Python stdlib
3. **Explicit over magical**: Heuristic-based scanning, not full Nix parsing
4. **Single-user focused**: Optimized for clarity, not library quality
5. **No infrastructure**: Just a CLI tool, no web servers or dashboards

## Future Enhancements (Optional)

If you find this useful, you could extend it with:
- GraphViz visualization (`hwc-graph visualize --output=deps.svg`)
- Auto-enable dependencies (`hwc-graph enable <module> --deps`)
- Interactive TUI for exploration
- Pre-commit hook to check for breaking changes

But for now, it's intentionally minimal and focused.

## Troubleshooting

**Module not found**:
- Use partial names: `hwc-graph show jellyfin`
- Use full names: `hwc-graph show hwc.server.jellyfin`
- List all: `hwc-graph list | grep jellyfin`

**Ambiguous module name**:
- The tool will show all matches
- Use a more specific name

**Dependencies seem wrong**:
- Check that assertions exist in the module's `index.nix`
- Verify assertions follow the pattern: `config.hwc.X.Y.enable`
- Add comment headers if needed: `# DEPENDENCIES:`

## Files

- `scanner.py`: Repository scanning and module discovery
- `graph.py`: Dependency graph traversal and analysis
- `formatters.py`: Output formatting (text and JSON)
- `hwc_graph.py`: CLI entry point
- `README.md`: This file

## Version

v1.0.0 - Initial minimal viable implementation

## License

Same as nixos-hwc repository.
