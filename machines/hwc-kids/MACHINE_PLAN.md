# HWC-Kids Machine Plan: Retro Gaming + AI Compute Node

**Machine**: hwc-kids
**Role**: Dual-purpose retro gaming station + distributed AI compute node
**Status**: Bootstrap mode (secrets disabled, pending age key deployment)
**Charter Version**: v5.0 compliant

---

## Hardware Profile

- **CPU**: Intel i7-8750H (6C/12T @ 2.20GHz)
- **RAM**: 32GB
- **GPU**: Intel UHD Graphics 630 (integrated)
- **Storage**: NVMe SSD (root), ESP boot partition
- **Capabilities**:
  - Intel QuickSync hardware video encoding
  - Intel GPU compute (oneAPI/Level Zero for AI inference)
  - Sufficient for all retro gaming (pre-2000s consoles)

---

## Machine Roles

### 1. **Retro Gaming Station**
- Frontend: EmulationStation-DE or RetroArch GUI
- Emulation: RetroArch with libretro cores
- Controller support: USB/Bluetooth gamepads
- ROM library: `/home/eric/retro-roms`
- Save states: `~/.config/retroarch/saves`

### 2. **AI Compute Node**
- Service: Ollama (containerized LLM inference)
- Acceleration: Intel GPU via oneAPI
- Models: Lightweight models optimized for Intel (llama3:8b, codellama:7b)
- Network: Exposed on Tailscale mesh (port 11434)
- Storage: `/var/lib/ollama` for model cache

---

## Architecture (Charter v5.0 Compliant)

### Domain Structure

```
domains/
├── home/
│   └── apps/
│       ├── retroarch/              # NEW MODULE
│       │   ├── options.nix         → hwc.home.apps.retroarch.*
│       │   ├── index.nix           → HM implementation
│       │   ├── sys.nix             → system packages (controllers, udev)
│       │   └── parts/
│       │       ├── cores.nix       → libretro core selection
│       │       └── config.nix      → RetroArch config template
│       └── emulationstation-de/    # OPTIONAL MODULE
│           ├── options.nix         → hwc.home.apps.emulationstation.*
│           ├── index.nix           → HM implementation
│           └── parts/
│               └── config.nix      → ES-DE config
│
├── infrastructure/
│   └── hardware/
│       └── gpu/
│           └── parts/
│               └── gpu.nix         # EXTEND for Intel compute
│
└── server/
    └── ai/
        └── ollama/                 # EXISTING (use as-is)
            └── default.nix         → hwc.server.ai.ollama.*
```

### Profile Composition

**hwc-kids imports:**
- `profiles/system.nix` → Core OS services
- `profiles/home.nix` → Home Manager domain menu
- `profiles/server.nix` → Server workload capabilities
- `profiles/ai.nix` → AI service capabilities
- `profiles/security.nix` → DISABLED until age keys deployed

**hwc-laptop does NOT import:**
- `profiles/server.nix` (not a server)
- `profiles/ai.nix` (AI runs on server/kids only)

### Machine-Specific Activation

**Charter Section 7 Compliance**: HM activation is machine-specific.

```nix
# machines/hwc-kids/config.nix
imports = [
  ../../profiles/system.nix
  ../../profiles/home.nix
  ../../profiles/server.nix    # Makes server modules available
  ../../profiles/ai.nix         # Makes AI modules available
];

hwc.infrastructure.hardware.gpu = {
  type = "intel";
  intel.enableCompute = true;   # For AI workloads
};

hwc.server.ai.ollama = {
  enable = true;                # Only enabled on this machine
  models = [ "llama3:8b" "codellama:7b" ];
};
```

```nix
# machines/hwc-kids/home.nix (NEW FILE)
{ config, pkgs, ... }: {
  home-manager.users.eric = {
    imports = [
      ../../domains/home/apps/kitty
      ../../domains/home/apps/retroarch          # Only this machine
      ../../domains/home/apps/emulationstation-de # Optional
    ];

    hwc.home.apps.retroarch = {
      enable = true;
      cores = [
        "snes9x" "genesis-plus-gx" "beetle-psx-hw"
        "mupen64plus" "mgba" "nestopia"
      ];
    };
  };
}
```

---

## Implementation Phases

### Phase 1: Retro Gaming Module (Home Domain)
1. Create `domains/home/apps/retroarch/` module
   - `options.nix` → Define `hwc.home.apps.retroarch.*` API
   - `index.nix` → HM config for RetroArch + cores
   - `sys.nix` → Udev rules for controllers
   - `parts/cores.nix` → Declarative core selection helper

2. Create `machines/hwc-kids/home.nix`
   - Import retroarch module
   - Configure core selection
   - Set ROM paths

3. Optional: Create `domains/home/apps/emulationstation-de/`
   - Frontend launcher for ROM library
   - Auto-detect RetroArch cores

### Phase 2: AI Compute Node (Server Domain)
1. Extend Intel GPU support in `domains/infrastructure/hardware/gpu/`
   - Add Intel compute options (oneAPI, Level Zero)
   - Container runtime support for Intel GPUs
   - Update `hwc.infrastructure.hardware.gpu.intel.*` namespace

2. Update `machines/hwc-kids/config.nix`
   - Import `profiles/server.nix` and `profiles/ai.nix`
   - Enable Intel GPU compute
   - Configure Ollama service
   - Set storage paths

3. Verify Ollama containerization
   - Ensure Intel GPU passthrough works
   - Test model inference performance
   - Expose on Tailscale network

### Phase 3: Security Hardening (Post-Bootstrap)
1. Deploy age keys to hwc-kids
2. Enable `profiles/security.nix`
3. Configure secrets:
   - `hwc.system.users.user.useSecrets = true`
   - `hwc.system.users.user.ssh.useSecrets = true`
4. Remove hardcoded SSH fallback key
5. Configure auto-login if desired

---

## Storage Layout

```
/home/eric/
├── retro-roms/                # ROM library
│   ├── snes/
│   ├── genesis/
│   ├── psx/
│   └── n64/
├── .config/retroarch/
│   ├── saves/                 # Save states
│   └── retroarch.cfg
└── 03-tech/local-storage/     # General hot storage

/var/lib/
├── ollama/                    # AI model cache
└── hwc/                       # HWC service data

/opt/
├── ai/                        # AI service configs (if needed)
└── cache/                     # Shared cache
```

---

## Network Configuration

### Tailscale Mesh Integration
- Hostname: `hwc-kids`
- Tailscale IP: (assigned by network)
- Exposed services:
  - SSH: 22 (Tailscale only)
  - Ollama API: 11434 (accessible from laptop/server)

### Firewall (Strict Mode)
- Default deny
- Allow SSH via Tailscale
- Allow Ollama API on Tailscale interface
- No public-facing services (gaming is local only)

---

## Performance Considerations

### Intel GPU Optimization
- QuickSync for video transcoding (if needed)
- Level Zero compute runtime for Ollama
- Shared GPU memory allocation (configurable)

### Model Selection for Intel GPU
- Prefer quantized models (Q4, Q5)
- Avoid large models (>13B parameters)
- Test inference latency before production use

### Gaming Performance
- Intel UHD 630 sufficient for:
  - All 8-bit/16-bit consoles (NES, SNES, Genesis, etc.)
  - PSX (PlayStation 1)
  - N64 (with some shader limitations)
  - Arcade (MAME)
- Not suitable for:
  - PS2/GameCube (too demanding)
  - Modern shaders/filters (may need reduction)

---

## Charter Compliance Checklist

- [x] **Section 1**: Modules follow namespace pattern (folder → option path)
- [x] **Section 3**: Domain boundaries respected (home/infrastructure/server)
- [x] **Section 4**: Unit anatomy (options.nix, index.nix, sys.nix, parts/)
- [x] **Section 5**: Lane purity (sys.nix in home domain, imported by system profile)
- [x] **Section 7**: HM activation at machine level (`machines/hwc-kids/home.nix`)
- [x] **Section 11**: File standards (kebab-case, camelCase options)
- [x] **Section 12**: Single source of truth (only hwc-kids enables these features)

---

## Testing Strategy

### Retro Gaming
1. Build and switch to new config
2. Launch RetroArch, verify cores loaded
3. Test controller input (USB/Bluetooth)
4. Load sample ROM, verify playback
5. Test save states

### AI Compute
1. Verify Ollama container starts
2. Check Intel GPU detection (`vainfo`, `clinfo`)
3. Pull test model (`ollama pull llama3:8b`)
4. Test inference from laptop via Tailscale
5. Monitor GPU utilization during inference

### Integration
1. Verify gaming performance unaffected by AI service
2. Test concurrent usage (gaming + AI inference)
3. Monitor thermals under load
4. Validate Tailscale connectivity

---

## Future Enhancements

- **Gaming**:
  - Add more emulator frontends (Pegasus, Attract-Mode)
  - ROM collection management scripts
  - Automated scraping for metadata/artwork
  - Network play support

- **Compute**:
  - Distributed compute orchestration (Ray, Dask)
  - Model serving with multiple replicas
  - Performance monitoring (Prometheus/Grafana)
  - Auto-scaling based on demand

- **Infrastructure**:
  - Automated backup of save states
  - ROM library synchronization
  - Model cache management
  - Remote administration tools

---

**Last Updated**: 2025-10-05
**Author**: Eric (with Claude Code assistance)
**Charter Compliance**: v5.0
