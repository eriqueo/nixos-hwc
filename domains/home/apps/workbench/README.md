# workbench

## Purpose
Thin translator wiring the standalone `workbench` flake's HM module
(`programs.workbench`) into the HWC namespace: feeds it the system palette,
MCP gateway URL, hub/tab data, and late-bound peer launchers (mail via the
shell's aerc alias, one-shot analysis via the selected Codex package, browser via
`gpu-launch chromium-hwc-workbench`).

## Boundaries
- ✅ `hwc.home.apps.workbench.enable`; `gatewayUrl`, `offline`, `hubsDir` options; `wb-reload` binary (kills + recreates the zellij `workbench` session); versioned `workbench/keymap.json`; bounded Codex selected-item runner
- ✅ Tool tabs imported from `../zellij/parts/tabs.nix` so host navigation can't drift from the layout
- ✅ Optional bundled desktop, confirmed read-only summaries and validated HTTPS/exact T3 opening; central TUI uses the server's existing handoff authority
- ❌ Native JSON/schema/desktop entry and T3 OAuth credentials remain with their app/service owners
- ❌ The app itself lives in the `workbench` flake input (600_apps); this module only supplies values
- ❌ Pane grid/theme belong to `domains/home/apps/zellij/`; keymap grammar to `domains/home/keymap/`

## Structure

`mailHelper.enable` installs the app-owned foreground helper/profile using
aerc-owned launch facts. `desktop.mail.enable` consumes a fixed remote helper
and profile from the fleet composition. Both default off in the module; the
mail role supplies the helper and the qualified laptop supplies the native
entry. Runtime sockets use the Home Manager cache root and remain bounded and
owned by the foreground resource. No daemon or account action starts at activation.

- `index.nix` — imports the app-owned generic module; TUI wiring, wb-reload, shared Zellij package, versioned keymap, Codex provider, registry navigation, guarded server origin, central TUI handoffs, and optional native capabilities.

`serverUrl` derives from the sole `workbench` vhost in the system's shared route
catalog and its domain. Standalone HWC `hms` consumes that resolved NixOS HM
value through the flake composition. Independent Home Manager defaults empty
and must supply an explicit HTTPS origin when enabling a desktop or central TUI.
Neither path depends on a local business registry.

`desktop.enable`, `desktop.summary.enable`, `desktop.externalLinks.enable` and
`handoff.enable` default off. Only the qualified laptop opts in.
The generic app owns native JSON, package and desktop
entry. HWC supplies only the shared origin and trusted Kitty, unwrapped Neovim,
and xdg-open paths. Installation does not launch tools or send messages.

The `workbench-desktop-consumer` flake check exercises both actual HM lanes,
independent-HM guards, route derivation, capability switches, rendered JSON,
wrapped central-client environment and the installed desktop entry.

## Changelog
- 2026-10-24: Bind the app-owned native Mail/helper schema to aerc launch facts
  and one fleet-owned remote target, preserving existing TUI destinations.
- 2026-10-24: Share one route-derived origin across both HM lanes, native desktop
  and central TUI. Enable the tested laptop consumer with separate local
  capability switches; retain app-owned schema/entry and credential boundaries.
- 2026-10-12: Share aerc rows with Workbench schema 2; generate isolated compose launcher, omit aerc view controls and unsafe thread actions, guard launcher coverage and global keys; move compose/replies/forward to c; retain routing, unsubscribe and read-status menus under m.

- 2026-10-06: Consume current mail State keys and five-State fixtures. Unstarted
  mail actions wait safely for the shared sync owner with bounded attempts;
  started or uncertain writes never replay. Trash/JUNK retain Proton star semantics.
- 2026-09-30: Share the graphics-capable Zellij package with the shell and restart helper; restart sessions only when the user invokes reload.
- 2026-09-24: Keep empty Kanban stages keyboard-reachable so mail can move
  through Act, Look, Later, and Junk even when only one stage has messages.
- 2026-09-23: Update Workbench's Kanban stage browser to show its navigation
  keys, distinguish navigation from message moves, and focus the first message
  only after its widget mounts.
- 2026-09-16: Update Workbench's agent runner to negotiate supported Codex
  feature flags and keep failures visible until dismissed.
- 2026-09-16: Update Workbench to the terminal-native Kanban stage browser with a selected-item preview and narrow-terminal collapse.
- 2026-09-16: Replace the interactive agent pane command with Workbench's bounded one-shot Codex provider; results now return to Workbench through the application-owned run ledger.
- 2026-09-15: Bind the Workbench `agent` target to the configured Codex package,
  stage the live versioned keymap contract, and include Codex in the wrapper runtime.
- 2026-09-07: Consume Workbench registry v2: Brief first/landing; filter explicit
  default tabs, keep Server on demand, preserve aerc and mail as distinct targets.
- 2026-09-04: Default hub and standing tools derive from the shared registry consumer; packaged TOML owns hub facts.
- 2026-09-04: Derive standing-tool destinations from the structured Zellij table; mail client tab is aerc.
- 2026-07-06: README added (Law 12 v12.4 hybrid-scope burn-down; content derived from module source).
