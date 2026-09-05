# zellij

## Purpose
Configures zellij as workbench's pane host: installs the package, writes a
palette-derived KDL theme and config directly (bypassing `programs.zellij`),
ships the `workbench` layout of hub/tool tabs, and wires the Ctrl+Space
meta-leader which-key plugin when the unified keymap grammar is present.

## Boundaries
- ✅ `hwc.home.apps.zellij.enable`; `defaultLayout` (default "workbench"); config.kdl (theme, session_serialization off), workbench.kdl layout, zellij-which.wasm deployed to a stable `~/.config/zellij/plugins/` path (permission-grant persistence)
- ✅ Mail pane command late-bound from `hwc.home.core.shell.aliases.aerc`; hub facts come from the Workbench registry; tool facts come from the structured tab table
- ❌ The workbench host app and peer TUIs are their own modules; the which-key plugin is built in its own 600_apps repo (`zellij-which` flake input)
- ❌ Intra-app Space leaders belong to each app; zellij owns only the inter-app meta layer

## Structure
- `index.nix` — options, packages, config.kdl/layout/plugin via xdg.configFile
- `parts/appearance.nix` — palette → KDL themes block
- `parts/layout.nix` — workbench pane-grid KDL (late-bound mail command)
- `parts/tabs.nix` — versioned hub registry consumer + structured tool tab set (order = GoToTab indices)

## Changelog
- 2026-09-04: Consume Workbench hubRegistry schema v1; derive deployment order and landing, add mail/nightly hubs, and keep aerc distinct.
- 2026-09-04: Namespace hub/tool destinations; derive tools from one ordered table and reject name, destination, order, and hub-command collisions.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
