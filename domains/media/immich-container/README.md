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

- 2026-09-26: Comment in `parts/config.nix` follows the home-machine rename —
  `machines/server/config.nix:1133` → `machines/home/config.nix:1133`. Comment only
  (`4ac9941d`).
- 2026-08-28: The `immich` database and its owning `immich` role are declared —
  `hwc.data.databases.postgresql.databases = [ cfg.database.name ]` plus
  `services.postgresql.ensureUsers` with `ensureDBOwnership`. Neither had been declared
  anywhere in the repo; both existed on the live cluster by hand and a rebuilt cluster
  would not have reproduced them. The owner is `cfg.database.name`, **not**
  `cfg.database.user`: the container connects as `eric` via trust auth while the
  database and its objects are owned by the separate `immich` role, so declaring from
  `database.user` would have emitted a live `ALTER DATABASE immich OWNER TO eric`
  (`53e84228`).
- 2026-08-28: Deleted the fifteen dead `$PSQL` GRANT / ALTER DEFAULT PRIVILEGES lines
  from `postgresql.postStart` — eight for schema `public`, seven for the pgvector
  `vectors` schema. `$PSQL` is undefined in the generated post-start script and
  `|| true` swallowed the command-not-found, so none ever ran. Nothing was restored:
  Immich connects as the `immich` owner role, and the grants only existed to let the
  superuser `eric` read the database from a psql prompt (`e82ca994`).
- 2026-03-29: Container volumes mount `${config.hwc.paths.photos}/external` at
  `/mnt/media/photos/external:ro` in place of `${config.hwc.paths.media.root}/pictures`
  — the external library holding laptop photos; the unused pictures mount is dropped
  (`39e3a8c3`, `0a0f7414`).
- 2026-03-27: Fixed Prometheus metrics port mappings — added host-side port publishing for apiPort (8091) and microservicesPort (8092) which were only set as container env vars but never exposed, causing false ServiceDown alerts
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2025-11-21: Initial GPU optimization implementation
