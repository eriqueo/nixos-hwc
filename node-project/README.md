# Node Project

This directory contains configuration files to support the distributed Immich setup.

- `immich-worker-config.nix` provides the NixOS configuration for the laptop worker node that handles machine-learning tasks.
- `main-server-updates.nix` contains the NixOS configuration snippets to apply on the main server (hwc-server) to enable remote access for the worker.
