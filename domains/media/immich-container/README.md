# domains/media/immich-container/

## Purpose

Immich photo management with NVIDIA CUDA GPU acceleration for ML operations (Smart Search, Facial Recognition) and hardware-accelerated media processing.

## Boundaries

- **Manages**: Immich container, ML service, GPU configuration, cache directories
- **Does NOT manage**: GPU drivers (→ `domains/system/gpu`), the PostgreSQL engine (→ `domains/data/databases/`), storage paths (→ `domains/paths/`)

## Namespace

`hwc.media.immich.*`

## Structure

```
domains/media/immich-container/
├── index.nix           # hwc.media.immich.* options + imports
├── parts/config.nix    # Container definitions, GPU config, DB declaration, mounts
├── sys.nix             # System-lane packages
└── README.md           # This file
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
hwc.media.immich = {
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

- 2026-10-19: Header, Boundaries, Structure and Configuration corrected to the real
  module. This README still described `domains/server/containers/immich/`, the
  retired `hwc.server.containers.immich.*` namespace and an `options.nix` that does
  not exist; the module lives at `domains/media/immich-container/` under
  `hwc.media.immich.*` with its container config in `parts/config.nix`.
  Documentation only.
- 2026-09-26: Comment reference updated for the home-machine rename
  (`machines/server/config.nix` → `machines/home/config.nix`) (`4ac9941d`).
- 2026-08-28: The `immich` database and its owning `immich` role are now declared
  here (`hwc.data.databases.postgresql.databases` + `services.postgresql.ensureUsers`
  with `ensureDBOwnership`). Both had existed on the live cluster by hand, so a
  rebuilt cluster would not have reproduced them. The owner is `cfg.database.name`,
  **not** `cfg.database.user` — the machine config sets `database.user = "eric"` as
  the role the container connects as, while the live database and its objects are
  owned by a separate `immich` role; declaring from `database.user` would have
  emitted `ALTER DATABASE immich OWNER TO eric` (`53e84228`).
- 2026-08-28: Deleted the fifteen dead `$PSQL` GRANT / ALTER DEFAULT PRIVILEGES
  lines from `postStart` (eight for schema `public`, seven for the pgvector
  `vectors` schema). None ever ran — `$PSQL` is undefined in the generated
  postgresql post-start script and `|| true` swallowed the command-not-found — and
  none were load-bearing: Immich connects as its own `immich` role, and the grants
  only existed to give the superuser `eric` access it already had (`e82ca994`).
- 2026-03-29: Replaced the unused `${paths.media.root}/pictures` read-only mount
  with `${paths.photos}/external:/mnt/media/photos/external:ro`, so the laptop
  photo library is mountable as an Immich external library (`39e3a8c3`,
  `0a0f7414`).
- 2026-03-27: Fixed Prometheus metrics port mappings — added host-side port publishing for apiPort (8091) and microservicesPort (8092) which were only set as container env vars but never exposed, causing false ServiceDown alerts
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2025-11-21: Initial GPU optimization implementation
