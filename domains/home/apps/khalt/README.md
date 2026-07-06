# domains/home/apps/khalt

Thin Home Manager translator for **khalt** — the user's source fork of
khal/ikhal (own repo at `~/600_apps/khalt`, consumed as the `khalt` flake
input). Imports khalt's reusable HM module and feeds it an HWC-specific khal
config built from the shared `hwc.mail.calendar` data + the system theme.

NAMESPACE: `hwc.home.apps.khalt.*` (Charter Law 2: namespace = folder).
Enabled in `profiles/desktop/home.nix` (laptop, `defaultView = month`) and on
`hwc-server` (`machines/server/home.nix`) so the MCP gateway has khalt's `khal`
binary + `~/.config/khalt/config`.

khalt **supersedes plain khal**: its package ships the full `khal`/`ikhal` CLI
plus the `khalt` (ikhal) wrapper. The HM module exposes only the `khalt`
wrapper into the profile (to avoid colliding with a system khal in the
buildEnv); the calendar domain installs the package's `khal` separately as THE
khal binary.

## Calendars

`[calendars]` is rendered from `hwc.mail.calendar`:
- iCloud `accounts` → `calendars/<account>/*` (suppressed when radicale is on).
- `localCalendars` → their `.ics` dirs.
- `hwc.mail.calendar.radicale.enable` → a `[[radicale]]` discover calendar at
  `~/.local/share/vdirsyncer/calendars-radicale/*` (the live source once iCloud
  is retired — the same dir the MCP's `hwc_calendar` reads via `-c` this config).

## Structure

```
domains/home/apps/khalt/
├── index.nix    # hwc.home.apps.khalt.* — imports khalt HM module, builds config
└── README.md
```

## Changelog

- **2026-07-06**: Wired into the new unified keymap factory (`domains/home/keymap`).
  When `hwc.home.keymap.grammar` is present, the generated `[keybindings]` block
  from `keymap/parts/to-khalt.nix` (list-app bare verbs: `a`=add, `e`=edit,
  `d`=delete, Enter=open — shared with todui) is appended to `programs.khalt.configText`.
  Guarded with `lib.optionalString` so khalt still evaluates when the keymap
  module isn't imported.
- **2026-06-15**: `[calendars]` now renders the Radicale-synced calendar
  (`calendars-radicale/`) when `hwc.mail.calendar.radicale.enable` is set, and
  drops the stale iCloud account calendars in that case (mirrors
  `domains/mail/calendar`'s khal.nix). Part of the calendar→Radicale +
  khalt-supersedes-khal migration; the server now enables this app headlessly
  so the MCP can point `HWC_KHALT_CONFIG` at the generated config.
- Initial: thin translator importing `inputs.khalt.homeManagerModules.khalt`;
  theme-driven `[palette_tokens]`, zoom `default_view`, vdirsyncer on PATH.
