# Filesystem Organization Charter Summary

This document summarizes the key principles of the Filesystem Organization Charter (`FILESYSTEM-CHARTER.md`).

*   **Core Principle**: A 3-digit prefix system for top-level folders in the home directory (`~/`) to separate domains.
*   **Top-Level Structure**:
    *   `000_inbox/`: Global inbox for new files.
    *   `100_hwc/`: Work domain.
    *   `200_personal/`: Personal domain.
    *   `300_tech/`: Technology/development domain.
    *   `500_media/`: Cross-domain media library.
    *   `900_vaults/`: Cloud sync folders (Obsidian, etc.).
*   **Workflow**: Files land in `000_inbox/`, are processed, and then moved to the appropriate domain-specific inbox (e.g., `100_hwc/000-inbox/`) before being filed.
*   **XDG Integration**: Standard XDG directories (`XDG_DOWNLOAD_DIR`, `XDG_DOCUMENTS_DIR`, etc.) are mapped to specific locations within this structure via `domains/system/core/paths.nix`.

---

## Project Architecture & Status (Learned from READMEs)

This project is a NixOS configuration built on a strict, domain-driven architecture defined by the "HWC Charter."

### Core Architecture:
*   **Domain-Driven**: The configuration is split into logical domains:
    *   **System**: Core OS (users, networking, filesystem structure).
    *   **Infrastructure**: The "glue" layer (hardware integration like GPU, permissions).
    *   **Home**: User-specific environment (managed by Home Manager).
    *   **Server/Services**: Application daemons (like Jellyfin).
    *   **Secrets**: Manages all credentials via `agenix` with a stable "materials facade".
*   **Declarative First**: The system is meant to be fully declarative. Manual changes (like `mkdir`) are an anti-pattern. Directories, users, and services should all be defined in Nix code.
*   **Strict Separation**: "Lane purity" is enforced. Home-manager configs should not contain system-level definitions.

### Current Project Status:
*   **Major Refactoring in Progress**: The configuration is being actively migrated from a legacy, monolithic structure to the new domain-driven architecture.
*   **Validation is Critical**: A dedicated validation toolchain exists in `scripts/config-validation/` to compare the old and new configurations *before* deployment. This is used to prevent regressions.
*   **New Configuration is a Work-in-Progress**: The new configuration (in this repository) is not yet a 1:1 match for the production system and may be missing functionality.

---

## Philosophy, Process & Deeper Context (Learned from Root `.md` Files)

This context is critical for understanding how to operate within this repository.

### Core Philosophy:
*   **Fix Root Causes, Not Symptoms**: Per `CLAUDE.md`, the primary directive is to understand the "why" behind a problem and fix it correctly according to the architecture, not just apply a patch to make it work. Manual, imperative commands (`mkdir`, `systemctl start`) to fix declarative issues are an anti-pattern.
*   **Declarative Purity**: The system must be managed declaratively through Nix files. All file paths, directories, and services should be defined in the configuration.

### Project Status & Process:
*   **Active, Documented Refactoring**: The entire configuration is in a state of major, ongoing refactoring. This includes:
    *   **Profile Refactor**: Migrating away from `base.nix`/`sys.nix` to a one-profile-per-domain model (`PROFILE_REFACTOR_GUIDE.md`).
    *   **Charter Compliance**: A formal effort to fix all architectural violations (`CHARTER_MANUAL_FIX_REPORT.md`).
    *   **Email System Overhaul**: A massive, detailed migration of the email system is underway, with extensive planning and debugging logs.
*   **Implication**: The current code is a work-in-progress and may not reflect the final intended state. My role is to help move towards that state.

### Recurring Technical Challenges:
*   **System Services vs. User Sessions**: A recurring and difficult technical challenge is getting `systemd` services to correctly interact with user-level resources that require authentication, such as `gnome-keyring`, `gpg`, and `pass` (`PROTON_BRIDGE_DEBUG_HISTORY.md`). This is a key area to be aware of when debugging services.

### Architectural Patterns:
*   **Server-Side Containers**: The intended architecture for server applications (like n8n and Jellyfin) is to run them as declarative, rootless Podman containers managed by NixOS, often exposed via Caddy and Tailscale (`n8n_plan.md`).
*   **Strict Module Structure**: Modules *must* have a separate `options.nix` file for their definitions. Placing options inside `index.nix` is a known anti-pattern being actively fixed (`CHARTER_MANUAL_FIX_REPORT.md`).
