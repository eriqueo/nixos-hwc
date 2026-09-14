# domains/server/containers/immich/

## Purpose

Immich photo management with NVIDIA CUDA GPU acceleration for ML operations (Smart Search, Facial Recognition) and hardware-accelerated media processing.

## Boundaries

- **Manages**: Immich container, ML service, GPU configuration, cache directories
- **Does NOT manage**: GPU drivers (→ `domains/infrastructure/hardware/gpu`), PostgreSQL (→ `domains/server/databases/`), storage paths (→ `domains/paths/`)

## Structure

```
domains/media/immich-container/
├── index.nix           # hwc.media.immich.* options (declared inline, Law 10)
├── parts/
│   └── config.nix      # Container definitions, GPU config, Postgres role/database, storage
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

- 2026-08-28: **The database and its owning role are now declared; fifteen dead
  grants are gone.** `parts/config.nix` held an eight-line `$PSQL` block for schema
  `public` plus seven more for the pgvector `vectors` schema, and none ever ran —
  `$PSQL` is undefined in the generated postgresql post-start script and `|| true`
  swallowed the command-not-found. They were not restored: immich connects as its
  own `immich` role, which owns the database, so the app never touched them; their
  only purpose was letting `eric` read the database from a psql prompt, and `eric`
  is a superuser. Deleting them surfaced a real gap — neither the database nor its
  owning role was declared anywhere in the repo, so a rebuilt cluster would not
  have reproduced either. Both are now declared, with the owner taken from
  `cfg.database.name` and **not** `cfg.database.user`: those are different facts
  this module's options don't distinguish (`machines/server/config.nix` sets
  `database.user = "eric"`, the role the container CONNECTS as, while the live
  database and its objects are owned by a separate `immich` role). Declaring from
  `database.user` would have emitted `ALTER DATABASE immich OWNER TO eric` — a live
  ownership change wearing a cleanup's clothes — and NixOS's own `ensureDBOwnership`
  assertion caught it on the first eval (`e82ca994`, `53e84228`).
- 2026-03-29: External-library mount repointed —
  `${paths.media.root}/pictures:/mnt/media/pictures:ro` became
  `${paths.photos}/external:/mnt/media/photos/external:ro`, mounting the laptop
  photo library and dropping the unused pictures mount (`0a0f7414`).
- 2026-03-27: Fixed Prometheus metrics port mappings — added host-side port publishing for apiPort (8091) and microservicesPort (8092) which were only set as container env vars but never exposed, causing false ServiceDown alerts
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2025-11-21: Initial GPU optimization implementation
