# zellij

## Purpose
Configures zellij as workbench's pane host: installs the package, writes a
palette-derived KDL theme and config directly (bypassing `programs.zellij`),
ships the `workbench` layout of hub/tool tabs, and wires the Alt+Space
meta-leader which-key plugin when the unified keymap grammar is present.

## Boundaries
- ✅ `hwc.home.apps.zellij.enable`; `defaultLayout` (default "workbench"); config.kdl (theme, session_serialization off), workbench.kdl layout, zellij-which.wasm deployed to a stable `~/.config/zellij/plugins/` path (permission-grant persistence)
- ✅ Mail pane command late-bound from `hwc.home.core.shell.aliases.aerc`; tab set is the single source of truth consumed by workbench and the keymap
- ❌ The workbench host app and peer TUIs are their own modules; the which-key plugin is built in its own 600_apps repo (`zellij-which` flake input)
- ❌ Intra-app Space leaders belong to each app; zellij owns only the inter-app meta layer

## Structure
- `index.nix` — options, packages, config.kdl/layout/plugin via xdg.configFile
- `parts/appearance.nix` — palette → KDL themes block
- `parts/layout.nix` — workbench pane-grid KDL (late-bound mail command)
- `parts/tabs.nix` — canonical hub + tool tab set (order = GoToTab indices)

## Changelog
- 2026-07-12: Added the **refinery** hub-page tab to `parts/tabs.nix`; the hub
  run now spans tabs 1–6 and the tool tabs shift to 7–11 (`8cc83fb1`).
- 2026-07-11: Added the **crm** hub tab, second in `tabs.hubs` to match its hub
  `order = 15` between hwc and datax. The CRM hub manifest had shipped in the
  workbench flake with no zellij tab, so it was unreachable. The layout KDL,
  the `GoToTab` indices and `WORKBENCH_TABS` all derive from that one list, so
  they stay coherent (`f73fa9b3`).
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
