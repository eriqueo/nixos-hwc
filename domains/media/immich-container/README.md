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

- 2026-08-28: **Fifteen dead postgres GRANTs deleted; the database and its
  owning role declared for the first time.** `parts/config.nix` carried an
  eight-line `$PSQL` GRANT block for schema `public` and seven more for the
  pgvector `vectors` schema, and none ever ran — `$PSQL` is undefined in the
  generated postgresql post-start script and `|| true` swallowed each
  command-not-found (`e82ca994`). They were not restored: immich connects as
  its own `immich` role, which owns the database, so the app never used them,
  and their only purpose was letting `eric` browse from a psql prompt — which
  superuser already covers. The follow-on declared what the dead grants had
  hidden (`53e84228`): both the `immich` database and its owning role existed
  on the live cluster by hand, so a rebuilt cluster would not have reproduced
  either. Ownership is declared from `cfg.database.name`, **not**
  `cfg.database.user`. This module's options do not distinguish the connecting
  role from the owning role — `machines/server/config.nix:1133` sets
  `database.user = "eric"` while the live database and its objects are owned by
  a separate `immich` role — and deriving from `database.user` emitted
  `ALTER DATABASE immich OWNER TO eric`, a live ownership change wearing a
  cleanup's clothes. NixOS's own `ensureDBOwnership` assertion caught it on the
  first eval, which is why this was a two-commit change. Full audit in
  `domains/data/databases/README.md`.
- 2026-03-29: External library mounted for laptop photos; the unused `pictures`
  mount dropped (`0a0f7414`).
- 2026-03-27: Fixed Prometheus metrics port mappings — added host-side port publishing for apiPort (8091) and microservicesPort (8092) which were only set as container env vars but never exposed, causing false ServiceDown alerts
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2025-11-21: Initial GPU optimization implementation
