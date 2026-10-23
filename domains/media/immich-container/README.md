# Immich container module

## Purpose

Run the Immich photo server and machine-learning service while preserving the
photo library, PostgreSQL data and NVIDIA interfaces.

## Boundaries

- Manages server, ML and Redis containers, their mounts, limits and dependencies.
- Declares the existing database and owning role through the database capability.
- Uses GPU drivers from `domains/system/gpu` and paths from `domains/paths`.
- Keeps application upgrades and schema changes separate from runtime/TLS fixes.

## Structure

```
domains/media/immich-container/
├── index.nix          # hwc.media.immich options, immutable image inputs/recipes
├── sys.nix            # System-lane import point
├── README.md
└── parts/
    └── config.nix     # Containers, storage, DB ownership, metrics/dependencies
```

## Runtime images

The temporary defaults retain Immich 2.5.6. The server copies Node 24.22.1 from
an immutable official Node image while retaining the app and Node ABI 137. The
shared pure recipe also serves Seerr without changing its accepted image.

The ML recipe keeps its app, Python, CUDA, cuDNN and ONNX packages. It updates
only Jammy `libssl3`/`openssl` to `3.0.2-0ubuntu1.30`, the distro CA package and
hash-pinned certifi 2026.10.23. A builder installs certifi without dependency
resolution; its temporary pip tooling is absent from the final image. Ubuntu's
CA package still trusts C1/C3, so the recipe derives exclusions from the existing
`security.pki.caCertificateBlacklist` and regenerates the default store.

Build the Dockerfile outputs `system.build.immichServerRuntimeImageRecipe` and
`system.build.immichMlRuntimeImageRecipe`. Cache their pinned inputs, then build
Docker-format images with the evaluated `hwc.media.immich.images` tags. Use an
empty build context. Building images does not switch services.

Private qualification checks actual Node and native image processing, both
certificate stores, outbound model-host HTTPS, ML's own health check and a
profiled tiny CUDA inference. Old/new/old authenticated API reads preserve 18
core tables and 55 migrations without a database reset. `immich-runtime-wiring`
checks the selected OCI images against their generated recipe hashes.

Retain exact old images and current data for recovery. Remove the temporary
recipes after an upstream release passes those runtime, data and recovery
checks. These checks do not certify every application dependency.

## Configuration

```nix
hwc.media.immich = {
  enable = true;
  gpu.enable = true;
  network.mode = "host";
};
```

`database.user` is the connecting role; the database's owning role is declared
separately from its name. Do not replace ownership with the connecting user.
Storage paths and resource limits remain options under `hwc.media.immich`.
The GPU branch uses NVIDIA CDI and keeps its cache below the apps-root Immich
directory. Redis remains a separate container.

Immich detects its media path inside the container. Changing that path can
trigger an automatic database file-path migration. Keep `/usr/src/app/upload`
and the existing live mount wiring through runtime-only releases.

## Changelog

- 2026-10-23: Pin same-app server/ML runtime recipes, correct Node/shared TLS and
  certificate consumers, and bind the selected image tags to recipe checks.
  Document actual module ownership and remove unmeasured speed estimates.
- 2026-03-27: Fixed Prometheus metrics port mappings — added host-side port publishing for apiPort (8091) and microservicesPort (8092) which were only set as container env vars but never exposed, causing false ServiceDown alerts
- 2026-02-26: Created README per Law 12 (migrated from docs/infrastructure/)
- 2025-11-21: Initial GPU optimization implementation
