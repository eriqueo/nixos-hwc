# workbench

## Purpose
Thin translator wiring the standalone `workbench` flake's HM module
(`programs.workbench`) into the HWC namespace: feeds it the system palette,
MCP gateway URL, hub/tab data, and late-bound peer launchers (mail via the
shell's aerc alias, browser via `gpu-launch chromium-hwc-workbench`).

## Boundaries
- ✅ `hwc.home.apps.workbench.enable`; `gatewayUrl`, `offline`, `hubsDir` options; `wb-reload` binary (kills + recreates the zellij `workbench` session); staged `workbench/keymap.json` when the keymap grammar is present
- ✅ Tool tabs imported from `../zellij/parts/tabs.nix` so host navigation can't drift from the layout
- ❌ The app itself lives in the `workbench` flake input (600_apps); this module only supplies values
- ❌ Pane grid/theme belong to `domains/home/apps/zellij/`; keymap grammar to `domains/home/keymap/`

## Structure
- `index.nix` — imports the flake's HM module; options + programs.workbench wiring, wb-reload, keymap staging

## Changelog
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
