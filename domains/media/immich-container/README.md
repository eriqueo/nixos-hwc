# domains/server/containers/immich/

## Purpose

Immich photo management with NVIDIA CUDA GPU acceleration for ML operations (Smart Search, Facial Recognition) and hardware-accelerated media processing.

## Boundaries

- **Manages**: Immich container, ML service, GPU configuration, cache directories
- **Does NOT manage**: GPU drivers (→ `domains/infrastructure/hardware/gpu`), PostgreSQL (→ `domains/server/databases/`), storage paths (→ `domains/paths/`)

## Structure

```
domains/server/containers/immich/
├── index.nix           # Container definition with GPU config
├── options.nix         # hwc.server.containers.immich.* options
└── sys.nix             # System-lane packages
```

## GPU Optimizations

### Performance Gains

| Operation | CPU | CUDA | Speedup |
|-----------|-----|------|---------|
| Smart Search Indexing | ~2s/img | ~0.4-1s/img | **2-5x** |
| Facial Recognition | ~1.5s/face | ~0.3-0.8s/face | **2-5x** |
| Thumbnail Generation | ~0.8s/img | ~0.3-0.5s/img | **1.5-3x** |

### Key Optimizations

1. **ONNX Runtime CUDA**: `ONNXRUNTIME_PROVIDER = "cuda"` - 2-5x faster ML inference
2. **TensorRT Cache**: `/var/lib/immich/.cache/tensorrt` - optimized inference graphs
3. **Memory Locking**: `LimitMEMLOCK = "infinity"` - eliminates GPU memory paging
4. **Process Priority**: `Nice = -10` for ML service responsiveness
5. **SystemD Dependencies**: Waits for `nvidia-container-toolkit-cdi-generator`

### GPU Devices Exposed

- `/dev/nvidia0`, `/dev/nvidiactl`, `/dev/nvidia-modeset`
- `/dev/nvidia-uvm`, `/dev/nvidia-uvm-tools`
- `/dev/dri/*` (Direct Rendering Infrastructure)

## Configuration

```nix
hwc.server.containers.immich = {
  enable = true;
  gpu.enable = true;  # Enable CUDA acceleration
};

# Required infrastructure
hwc.infrastructure.hardware.gpu = {
  enable = true;
  type = "nvidia";
  nvidia.containerRuntime = true;  # REQUIRED
};
```

## Validation

```bash
# Comprehensive GPU validation
./workspace/utilities/immich-gpu-check.sh

# Manual checks
nvidia-smi  # GPU available
journalctl -u immich-machine-learning | grep -i "onnx\|cuda"  # CUDA provider
```

## Troubleshooting

**ML not using GPU**: Check `nvidia-smi`, `lsmod | grep nvidia`, CDI generator status

**ONNX using CPU**: Verify `ONNXRUNTIME_PROVIDER` env var, check CUDA library paths

**Poor performance**: Check GPU memory usage, TensorRT cache population, process priorities

## Changelog

- 2026-09-26: Comment-only — the config's reference to the machine file follows the
  home-machine rename (`machines/server/config.nix` → `machines/home/config.nix`);
  identities preserved (4ac9941d).
- 2026-08-28: **The fifteen dead `$PSQL` grant lines are gone, and the immich database
  and its owning role are now declared.** `$PSQL` is undefined in the generated
  postgresql post-start script and `|| true` swallowed the command-not-found, so none
  of the eight `public`-schema grants or the seven `vectors`-schema grants ever ran.
  They are not restored: Immich connects as its own `immich` role, which owns the
  database, so the app never touched them; their only purpose was letting `eric` read
  the database from a psql prompt, and `eric` is a superuser. Neither the database nor
  its owner was declared anywhere in the repo — both existed on the live cluster by
  hand, and a rebuilt cluster would not have reproduced them. The owner is
  `cfg.database.name`, **not** `cfg.database.user`: the machine sets
  `database.user = "eric"` (the role the container *connects* as, via trust auth) while
  the live database and its objects are owned by a separate `immich` role. Declaring
  ownership from `database.user` would emit `ALTER DATABASE immich OWNER TO eric` — a
  live ownership change wearing a cleanup's clothes, which NixOS's own
  `ensureDBOwnership` assertion caught on first eval. Full audit in
  `domains/data/databases/README.md` (e82ca994, 53e84228).
- 2026-03-29: Replaced the stale read-only `${paths.media.root}/pictures` mount (the
  directory had been deleted and was empty) with `${paths.photos}/external` in both
  the server and ML containers, for the new external library holding 34K laptop-only
  photos (0a0f7414).
- 2026-03-27: Fixed Prometheus metrics port mappings — added host-side port publishing for apiPort (8091) and microservicesPort (8092) which were only set as container env vars but never exposed, causing false ServiceDown alerts
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2025-11-21: Initial GPU optimization implementation
