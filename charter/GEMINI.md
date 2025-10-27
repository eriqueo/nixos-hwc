# HWC Architecture Charter Summary

This document summarizes the key principles of the HWC Architecture Charter (`charter.md`).

*   **Core Concepts**:
    *   **Domains**: Folders of modules organized by interaction boundary (e.g., `domains/home`, `domains/system`). Namespace matches folder structure (e.g., `domains/home/apps/firefox` -> `hwc.home.apps.firefox`).
    *   **Modules**: A single logical concern (e.g., all Firefox configuration). Each module has an `index.nix` and a mandatory `options.nix`.
    *   **Profiles**: Domain-specific feature menus that aggregate modules. They have `BASE` (critical) and `OPTIONAL FEATURES` sections.
    *   **Machines**: Hardware-specific configurations that compose profiles.
*   **Flow**: `flake.nix` -> `machines/<host>` -> `profiles/*` -> `domains/*`.
*   **Lane Purity**: Strict separation between system-level configuration and Home Manager configuration. `domains/home` is for Home Manager. System-wide packages or services are handled in `sys.nix` files within a module, but imported by system profiles.
*   **Home Manager**: Activated at the `machines` level, not in profiles (except for `profiles/home.nix` which is a feature menu).
*   **Validation**: Modules must include a `# VALIDATION` section with assertions to ensure dependencies are met, enforcing fail-fast builds.
