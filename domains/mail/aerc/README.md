# aerc — Terminal Email Client

Declarative aerc configuration for a unified Proton Mail + Notmuch setup, managed via NixOS Home Manager.

## Purpose

Unified email workflow across Proton and Gmail identities. Uses notmuch for indexing and virtual folders, msmtp for sending, and mbsync for IMAP sync.

## Boundaries

- **Owns**: aerc.conf, binds.conf, accounts.conf, notmuch-queries, stylesets, templates, ov pager config
- **Depends on**: `domains/mail/` (accounts, mbsync, notmuch, msmtp, afew)
- **Never contains**: systemd services, mail sync logic, secret declarations

## Structure

```
aerc/
  index.nix              # Module entry — enable toggle, packages, shell aliases, activation
  package.nix            # Forked aerc package from the flake input
  parts/
    config.nix           # aerc.conf, accounts.conf, notmuch-queries, stylesets, templates
    binds.nix            # binds.conf (keybindings) + ov pager config
    appearance.nix       # hwc styleset (palette-driven)
    tags.nix             # Mail taxonomy adapter for queries, styles, and bindings
    tags-custom.json     # User-defined aerc-only tags
    sieve.nix            # Sieve script deployment
    sieve-filters.nix    # Server-side Sieve rules
```

## Architecture

### Mail Pipeline

```
Proton Mail <--IMAP--> Proton Bridge (localhost:1143/1025)
                            |
                     mbsync (IMAP sync)
                            |
                   ~/400_mail/Maildir/proton/
                            |
                     notmuch new + post-new hook
                       (tagging rules)
                            |
                   aerc (notmuch:// backend)
                            |
                     msmtp (sendmail)
                            |
                    Proton Bridge SMTP
```

### Sync Lifecycle (`<C-r>` or systemd timer)

1. **Pre-sync**: afew MailMover physically moves files based on tags (archive/trash/spam)
2. **Sync**: `mbsync -a` syncs IMAP state bidirectionally
3. **Post-sync**: `notmuch new` indexes new messages, triggers post-new hook
4. **Hook**: Applies folder-state tags, auto-classification rules, Proton label tags

The `<C-r>` keybind runs `sync-mail` which executes the full pipeline (mbsync + notmuch new). Never run bare `mbsync -a` from aerc — it skips notmuch indexing and tags will appear to revert.

### Daily queue semantics

`now` is the managed decision queue: `tag:queue AND tag:inbox`. Opening or
reading a message never removes it. Only a disposition that removes `inbox`
(archive or trash) finishes the item. A task/calendar/Paperless handoff writes
to the destination but deliberately leaves the source email in place; press
`a` after confirming the handoff. `family`, `datax`, and `hwc` are context lenses over that
same queue, not filing destinations. `backlog` is legacy unread mail that has
not yet been promoted into a bounded managed cohort.

### Tag System (tags.nix)

Shared tag metadata originates in `domains/mail/taxonomy/data.nix`; `tags.nix` adapts it for aerc, and `tags-custom.json` holds aerc-only additions. The generated data supplies:

- Notmuch query-map entries for direct drill-down
- `[user]` styles for virtual folder names
- nested `<Space>mc*` category and `<Space>mv*` user-flag bindings

Tags remain available to the shared triage and briefing integrations, but the daily message list deliberately does not render tag pills or color whole rows by category.
Automation-only `action` and `pending` tags remain queryable but do not appear
in the human mark menu.

#### Tag Types

| Type | Behavior | Example |
|------|----------|---------|
| **Category** (`categoryTags`) | Mutually exclusive — assigning one removes the other categories | work, finance, tech, personal, family |
| **Flag** (`flagTags`) | Additive — coexists with categories; may be automation-only | action, pending, keep |

#### Tag Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `tag` | yes | Notmuch tag name |
| `color` | yes | Hex color for `[user]` styleset section |
| `spaceKey` | no | Key for `<Space>m*` and `<Space>g*` bindings (defaults to first char of tag) |
| `display` | no | Display name in query-map and stylesets (defaults to tag) |
| `query` | no | Custom notmuch query (defaults to `tag:<name> AND NOT tag:trash`) |
| `extra` | no | Extra styleset lines (e.g., `"insurance.dim = true"`) |
| `noGoTo` | no | Skip `<Space>g*` generation (avoids key conflicts) |

The current tag vocabulary, leader keys, and palette roles live in
`domains/mail/taxonomy/data.nix`; this README does not duplicate that registry.

### Stylesets

All 9 bundled aerc stylesets (blue, catppuccin, default, dracula, monochrome, nord, pink, solarized, solarized-dark) are copied at Nix eval time with a `[user]` section appended for folder-name styles.

Switch themes live with `<Space>ts` followed by the theme name (tab-completes).

The custom `hwc` styleset in `appearance.nix` is palette-driven from `hwc.home.theme.colors`. Message state supplies row emphasis; categories do not recolor the row.

## Keybindings

### Global

| Key | Action |
|-----|--------|
| `<A-h>` / `<A-l>` | Prev/next aerc tab |
| `<A-S-j>` / `<A-S-k>` | Next/prev aerc tab compatibility aliases |
| `<A-j>` / `<A-k>` | Next/prev visible context |
| `<C-p>` / `<C-n>` | Next/prev account |
| `<C-r>` | Full mail sync (mbsync + notmuch new) |
| `<C-q>` | Quit (with confirmation) |
| `<C-t>` | Open terminal |
| `;` | View binds.conf |
| `<Space>?` | Open the focused leader cheat sheet |
| `<Space>ts` | Switch styleset |

### Messages

| Key | Action |
|-----|--------|
| `j` / `k` | Next / prev message |
| `g` / `G` | First / last message |
| `<C-d>` / `<C-u>` | Page down / up (50%) |
| `<Enter>` | Open message |
| `q` | Quit |
| `J` / `K` | Toggle mark + move |
| `V` | Visual mark mode |
| `r` | Mark read |
| `u` | Mark unread |
| `D` | Delete |
| `c` | Compose |
| `C` | Reply all (quote) |

### Disposition (Messages)

| Key | Action |
|-----|--------|
| `a` | Finish and archive (`+archive -inbox -unread`) |
| `d` | Finish and trash (`+trash -inbox -unread`) |
| `X` | Move to folder (prompt) |
| `Y` | Copy to folder (prompt) |

### Space-Leader Navigation (`<Space>g*`)

| Key | Folder |
|-----|--------|
| `<Space>gi` | now |
| `<Space>gF` | family |
| `<Space>gD` | datax |
| `<Space>gW` | hwc |
| `<Space>gB` | backlog (hidden drill-down) |
| `<Space>gI` | full inbox (hidden drill-down) |
| `<Space>gu` | unread |
| `<Space>ga` | Archive |
| `<Space>gs` | sent |
| `<Space>gd` | trash |
| `<Space>gz` | spam |
| `<Space>g_` | hide_my_email |

Tag-derived folders no longer occupy this first-level navigation menu. Use
the tag filters below; the generated query-map still retains every legacy and
automation tag.

### Space-Leader Labels (`<Space>m*`)

| Key | Action |
|-----|--------|
| `<Space>mu` | +unread |
| `<Space>ma` | +archive -inbox -unread |
| `<Space>md` | +trash -inbox -unread |
| `<Space>mz` | +spam -inbox |
| `<Space>ml` | Free-form label (prompt) |
| `<Space>mx` | Clear removable categories/flags; preserve protected `keep` |
| `<Space>mc…` | Classify with a category; pause after `c` to see choices |
| `<Space>mv…` | Add a user-visible flag; pause after `v` to see choices |

`action` and `pending` are automation-only compatibility tags. They are not
offered as manual workflow states: create a task/calendar/document handoff and
archive the source message instead.

### Filter / Sort

| Key | Action |
|-----|--------|
| `<Space>ff` | Filter messages |
| `<Space>fs` | Search messages |
| `<Space>ft` | Filter the current folder by tag; `Tab` completes tag names |
| `<Space>fT` | Find a tag across all mail in the reusable `tag-search` query |
| `<Space>fc` | Clear the current filter/search |
| `<Space>fu` | Unsubscribe using the message's `List-Unsubscribe` header |
| `<Space>sd` | Sort by date (newest first) |
| `<Space>tt` | Toggle thread view |

### View

| Key | Action |
|-----|--------|
| `q` | Close view |
| `J` / `K` | Next / prev message |
| `r` | Reply |
| `R` | Reply all |
| `f` | Forward |
| `a` | Archive + close |
| `d` | Trash + close |
| `H` | Toggle headers |
| `u` | Open link |
| `O` | Open attachment |
| `t` | Review and create a task in the shared todui/phone backend |
| `i` | Review and create a calendar event for khalt/phone |
| `p` | Queue a safe PDF record of the email for Paperless |
| `S` | Save attachment |
| `U` | URL scan (urlscan) |
| `/` | Search in pager (passthrough) |

Review helpers open in an aerc terminal tab. `<A-h>` / `<A-l>` move between
that tab and the original message without closing the editor; `<C-x>` opens the
aerc command prompt inside a terminal.

### Searching by tag

Use `<Space>ft` when you want to narrow the context already open. Aerc seeds
`:filter tag:`; type a tag or press `Tab` to complete one, then press `Enter`.
The active folder still bounds the results—for example, filtering `now` by
`finance` shows only finance messages in the managed queue. `<Space>fc` removes
that filter.

Use `<Space>fT` when you want the complete history. It seeds a top-level
notmuch query and reuses one `tag-search` folder, so repeated searches do not
grow the sidebar. Press `<Space>gi` to return to `now`.

### Compose

| Key | Action |
|-----|--------|
| `<Tab>` / `<S-Tab>` | Next / prev field |
| `<C-s>` | Send |
| `<C-x>` | Command prompt |

### Compose Review

| Key | Action |
|-----|--------|
| `y` | Send |
| `n` | Abort |
| `e` | Edit |
| `p` | Postpone |
| `a` | Attach file |
| `H` | Convert to HTML multipart |

## Column Layout

```
state<3 | date<10 | from<22 | subject<*
```

| Column | Template | Description |
|--------|----------|-------------|
| `state` | `.IsUnread` / `.IsFlagged` | `●` unread and `★` flagged |
| `date` | `.DateAutoFormat` | Relative dates (Today, Yesterday, Mon 10 Mar) |
| `from` | `.From \| names` | Sender display name |
| `subject` | `.Subject` | Subject with thread prefix and fold count |

Unread messages are bold, read messages are dim, and selection remains a strong reversed bar. Category tags stay out of the row chrome.

## Virtual Folders (Query Map)

The sidebar intentionally exposes only `now`, `family`, `datax`, and `hwc`.
`now` is the complete recent unread non-noise inbox. The other three folders
partition that same set exactly: DataX wins on `tag:datax`; family then matches
protected family mail and the three personal recipient addresses; HWC receives
everything left so no current message disappears. `now` is the default; only
its unread count appears in the sidebar, and the tab count is scoped to it.
Backlog, drafts, sent, archive, trash, and the legacy tag/triage queries remain
available by direct keybinding without competing for attention in the sidebar.

Primary folders:

| Folder | Query |
|--------|-------|
| now | unread inbox mail from the last 7 days, excluding notifications, newsletters, trash, and `triage/noise` |
| family | the `now` set matching `family`/`keep` or a personal recipient address, excluding DataX |
| datax | the `now` set tagged `datax` |
| hwc | every message left in `now` after DataX and family, including uncategorized mail |
| backlog | the same unread non-noise inbox set as `now`, older than the 7-day window |
| inbox | `tag:inbox AND NOT tag:trash` |
| unread | `tag:unread AND NOT tag:trash` |
| sent | `tag:sent` |
| drafts | `tag:draft` |
| Archive | `tag:archive AND NOT tag:trash` |
| trash | `tag:trash` |
| spam | `tag:spam` |
| important | `tag:important AND NOT tag:trash` |
| hide_my_email | `tag:hide` |

The remaining static, triage, and tag-derived queries stay in the query map for integrations, bindings, and direct `:cf <name>` drill-down without crowding the sidebar.

Tag-derived folders are generated from `domains/mail/taxonomy/data.nix` and
remain directly addressable even though they are hidden from the sidebar and
the first-level navigation popup.

## Filters

| MIME Type | Handler |
|-----------|---------|
| `text/html` | aerc bundled HTML filter |
| `text/plain` | wrap + colorize |
| `text/calendar` | aerc calendar filter |
| `text/*` | cat passthrough |
| `message/delivery-status` | colorize |
| `image/*` | kitty icat (if Kitty) or chafa sixel |
| `application/pdf` | pdftotext |
| `application/json` | jq colored |
| `subject,~^\[PATCH` | hldiff (patch highlighting) |

Multipart converter: pandoc markdown-to-HTML for rich email composition (`H` in compose review).

## Sending

Outgoing mail via msmtp through Proton Bridge SMTP (localhost:1025). Three sending identities configured:

- `proton-hwc` — eric@iheartwoodcraft.com (default)
- `proton-personal` — eriqueo@proton.me
- `proton-office` — office@iheartwoodcraft.com

TLS disabled for localhost Bridge connections (`tls_certcheck off`).

## Packages

aerc, msmtp, isync, w3m, notmuch, urlscan, ripgrep, glow, pandoc, chafa, poppler-utils, jq, mpv, xdg-utils, ov, xclip

## Adding a New Tag

1. For a shared mail tag, edit `domains/mail/taxonomy/data.nix`; for an
   aerc-only tag, use `<Space>M` to update `parts/tags-custom.json`.
2. Rebuild — query-map, folder styles, and bindings update automatically.
3. If a Proton label exists, the post-new hook discovers it from
   `proton/Labels/<name>/`.

## Changelog

- 2026-09-15: Bounded the mark/classify popup by nesting categories and visible
  flags, removed automation-only `action`/`pending` from the human workflow,
  and made bulk clears preserve the protected `keep` tag. Added tag-aware
  current-folder filtering and reusable all-mail queries with completion.
  Aerc tabs now use mnemonic `<A-h>/<A-l>` navigation and accept both terminal
  encodings of the `<A-S-j>/<A-S-k>` compatibility chords. The fork pin also
  serializes IPC commands on aerc's UI loop, preventing remote `:reload` from
  racing a tab redraw and crashing the client.
- 2026-09-14: Added the opened-message handoff grammar: `t` reviews and creates
  an idempotent task, `i` reviews and creates a calendar event, and `p` queues a
  deterministic text-only PDF for Paperless. Handoffs never archive the source;
  `a` remains the explicit finish action. Configured exact Proton and Google
  Authentication-Results authorities so RFC 8058 unsubscribe can validate real
  DKIM-pass messages without trusting a wildcard.
- 2026-09-14: The embedded `less` viewer now uses `-~`, leaving the area below
  short messages blank instead of painting every unused row with `~`.
- 2026-09-14: Review-terminal `<C-h>/<C-l>` now switch aerc tabs directly, so
  the original message remains one key away while editing a handoff.
- 2026-09-14: Made `now` a stable `queue` + `inbox` decision surface, independent
  of unread state and message date. The original 41 messages form the cutover
  cohort; new arrivals join automatically. Legacy unread mail remains isolated
  in `backlog` until promoted in bounded batches.
- 2026-09-14: Human archive/trash bindings now also clear `unread`. These keys
  mean the message has been decided and removed from `now`; automatic arrival
  rules retain their previous unread behavior.
- 2026-09-14: Refined the calm sidebar to `now`, `family`, `datax`, and `hwc`.
  DataX-first precedence plus HWC fallback makes the three contexts an exact
  partition of `now`; added direct `<Space>gF/gD/gW/gB` navigation and kept
  backlog/system/tag views hidden but addressable. Corrected the documented
  keymap and tag source to match the generated configuration.
- 2026-09-14: Added the calm daily surface: `now` is recent unread non-noise,
  `backlog` holds its older complement, and the sidebar exposes only seven
  useful destinations. Only `now` shows a sidebar count, the tab count is also
  scoped to `now`, and the message list is reduced to
  state/date/from/subject, removed tag pills and category-wide row colors, and
  replaced the inert trash-sender helper with built-in `:unsubscribe`.
- 2026-06-26: folder nav `<C-j>/<C-k>` → `<A-j>/<A-k>` (next/prev-folder). Ctrl is now the workbench/zellij layer (Ctrl+j/k cycle tabs), so in-app side-column nav moved to Alt to avoid the collision.
- 2026-06-26: which-key footer legend (`esc close · ⌫ back`) on the bottom border + Backspace walks up one chord level (forked aerc, app/whichkey.go + app/aerc.go); new themeable `whichkey_legend` style.
- 2026-06-26: which-key popover redesign (forked aerc) — compact content-sized box (was edge-to-edge), `key → label` rows with nvim arrow, group keys read `domain +N` (e.g. `buffer +7`); styleset reworked to a raised slate card (bg3, lighter than terminal) with an inverted cream title chip and copper border, plus interior padding + a minimum box size. Code in `github:eriqueo/aerc` (app/whichkey.go, app/aerc.go); colors in `parts/appearance.nix`.
- 2026-03-19: Fix act-one-delete-rest → act-dir (was deleting label file copies); fix hide_my_email query to use tag:hide instead of wrong Folders/ path
- 2026-03-15: Add family and hwcmt tags; spam folder and bidirectional sync; hide_my_email folder; to column; symbolic flags; human-readable column layout; full sync-mail pipeline on `<C-r>`; tag exclude filters for notifications/action/aerc; single-source-of-truth tag system with derived bindings, queries, stylesets, and column templates
- 2026-03-14: Fix compose editor (lf-editor), send (msmtp path), TLS (certcheck off); add compose review bindings; switch to dracula styleset with live switching; add tag-based message coloring across all themes; add quoted_reply HTML template; add bundled filters and multipart-converters
