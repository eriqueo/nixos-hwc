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
2. **Sync**: `mbsync.service` runs the ten-minute core lane; Proton Trash is an isolated daily pull-only mirror
3. **Post-sync**: `notmuch new` indexes new messages, triggers post-new hook
4. **Hook**: Applies folder-state tags, auto-classification rules, Proton label tags

The `<C-r>` keybind waits for `mbsync.service`, which runs the locked core pipeline (MailMover + mbsync + notmuch new). `sync-mail trash` never runs MailMover because Proton Bridge rejects uploads into Trash. Never run bare `mbsync -a` from aerc — it skips lane status and notmuch indexing.

### Daily workflow semantics

The sidebar is one workflow axis: `DO`, `DID`, `LOOK`, and `JUNK`. `DO` is the
inbox-zero queue. `DID` means Eric acted and is waiting; a new reply reopens it
to `DO`. `LOOK` needs no response. `JUNK` is recoverable Trash. Archive removes
the active state and records completion. Opening or reading mail never changes
state. Domain (`HWC`, `DataX`, `Family`, `Personal`, `Other`) is a column/filter,
never a folder or placement rule. Factual Tags never move mail.

A folded row expands to its complete thread. When `J`/`K` marks exist, `a` or
`d` applies thread-wide to the marked set through the classifier ledger.

### Tag System (tags.nix)

Shared factual-tag metadata originates in `domains/mail/taxonomy/data.nix`;
the versioned classifier contract supplies State and Domain. `tags.nix` adapts
optional tags for aerc, and `tags-custom.json` holds aerc-only additions.

- Notmuch query-map entries for direct drill-down
- `[user]` styles for virtual folder names
- nested `<Space>mv*` optional factual-tag bindings

The message list renders Domain, State, and factual Tags as separate columns.
Legacy `action` and `pending` tags do not participate in workflow.

#### Tag Types

| Type | Behavior | Example |
|------|----------|---------|
| **Domain** | Exactly one; independent of State | hwc, datax, family, personal, other |
| **State** | Exactly one while active | do, did, look, junk |
| **Tag** | Additive fact; never controls placement | attachment, finance, receipt |

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
| `a` | Finish/archive marked messages, otherwise the selected folded thread |
| `d` | Finish/trash marked messages, otherwise the selected folded thread |
| `X` | Move to folder (prompt) |
| `Y` | Copy to folder (prompt) |

### Space-Leader Navigation (`<Space>g*`)

| Key | Folder |
|-----|--------|
| `<Space>gi` | DO |
| `<Space>gd` | DID |
| `<Space>gl` | LOOK |
| `<Space>gj` | JUNK |
| `<Space>gB` | backlog (hidden drill-down) |
| `<Space>gI` | full inbox (hidden drill-down) |
| `<Space>gu` | unread |
| `<Space>ga` | Archive |
| `<Space>gs` | sent |
| `<Space>gT` | trash |
| `<Space>gz` | spam |
| `<Space>g_` | hide_my_email |

Tag-derived folders no longer occupy this first-level navigation menu. Use
the tag filters below; the generated query-map still retains every legacy and
automation tag.

### Space-Leader Labels (`<Space>m*`)

| Key | Action |
|-----|--------|
| `<Space>mu` | +unread |
| `<Space>ma` | Finish/archive marked messages |
| `<Space>md` | Finish/trash marked messages |
| `<Space>mz` | +spam -inbox |
| `<Space>ml` | Free-form label (prompt) |
| `<Space>mx` | Clear removable categories/flags; preserve protected `keep` |
| `<Space>mv…` | Add a user-visible flag; pause after `v` to see choices |
| `<Space>ta/td/tl/tj` | Teach DO/DID/LOOK/JUNK |
| `<Space>tc h/d/f/p/o` | Teach HWC/DataX/Family/Personal/Other Domain |
| `<Space>ra` | Create an exact-sender plus subject-text routing rule from the selected message |
| `<Space>rm` | Review and disable active routing rules |

`action` and `pending` are automation-only compatibility tags. They are not
offered as manual workflow states: create a task/calendar/document handoff and
archive the source message instead.

The rule review suggests a stable bracketed prefix such as `[P1 CRITICAL]` when
the subject has one. `DO` is the safe default. `JUNK` requires typing a second
confirmation because it moves future matches to recoverable Trash. Rules never
match every message from a sender without subject text.

### Filter / Sort

| Key | Action |
|-----|--------|
| `<Space>ff` | Filter messages |
| `<Space>fs` | Search messages |
| `<Space>ft` | Filter the current folder by tag; `Tab` completes tag names |
| `<Space>fT` | Find a tag across all mail in the reusable `tag-search` query |
| `<Space>fc` | Clear the current filter/search |
| `<Space>fu` | Unsubscribe from the message header; email-only senders ask first, then open review without Neovim |
| `<Space>sd` | Sort by date (newest first) |
| `<Space>tt` | Toggle the selected thread fold |
| `<Space>tT` | Fold every thread in the current view |

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

The viewer opens the sender-authored plain part first. `h` / `l` move between
MIME parts when an HTML layout is useful. Plain mail is wrapped to a 100-column
reading measure, repeated blank lines collapse, and long tracking URLs render
as clickable `↗ domain` labels. The full URL remains the link target and stays
available through `u` or `U`; the renderer never follows it or loads remote
content.

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

`From | Subject | Date | Domain | State | Tags`

| Column | Template | Description |
|--------|----------|-------------|
| `from` | `.From \| names` | Sender display name |
| `subject` | `.Subject` | Subject with thread prefix and fold count |
| `date` | `.DateAutoFormat` | Relative date |
| `domain` | `domain/*` | HWC/DataX/Family/Personal/Other |
| `state` | `state/*` | DO/DID/LOOK/JUNK |
| `tags` | `trait/*` plus optional facts | Factual traits only |

Unread messages are bold, read messages are dim, and selection remains a strong reversed bar.

## Virtual Folders (Query Map)

The sidebar exposes only the four active workflow states. Domain drill-down is
available with `<Space>fd h/d/f/p/o`; clear it with `<Space>fc`.

Primary folders:

| Folder | Query |
|--------|-------|
| do | `tag:state/do` — Eric must act |
| did | `tag:state/did` — waiting after Eric acted |
| look | `tag:state/look` — read or monitor |
| junk | `tag:state/junk` — recoverable Trash |
| backlog | legacy unread inbox mail not yet promoted into the managed queue |
| inbox | `tag:inbox AND NOT tag:trash` |
| unread | `tag:unread AND NOT tag:trash` |
| sent | `tag:sent` |
| drafts | `tag:draft` |
| Archive | `tag:archive AND NOT tag:trash` |
| trash | `tag:trash` |
| spam | `tag:spam` |
| important | `tag:important AND NOT tag:trash` |
| hide_my_email | `tag:hide` |

The remaining static and tag-derived queries stay in the query map for direct
drill-down without crowding the sidebar.

Tag-derived folders are generated from `domains/mail/taxonomy/data.nix` and
remain directly addressable even though they are hidden from the sidebar and
the first-level navigation popup.

## Filters

| MIME Type | Handler |
|-----------|---------|
| `text/html` | aerc bundled HTML filter |
| `text/plain` | 100-column wrap + control sanitization + compact clickable tracking links |
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

- 2026-09-22: Routed `<C-r>` through `mbsync.service`, so aerc uses the same
  locked core lane and authoritative unit result as timers and the MCP.
- 2026-09-22: Made the isolated Proton Trash lane pull-only and kept MailMover
  out of Trash-only runs because Bridge refuses IMAP APPEND into Trash.
- 2026-09-22: Replaced overlapping folder/category/flag semantics with one
  workflow axis (`DO/DID/LOOK/JUNK`), one independent Domain, and factual Tags.
  Added ledger-backed state/Domain teaching, thread-wide marked archive/trash,
  explicit fold-one/fold-all keys, and the six-column message list.

- 2026-09-21: Replaced the thread-view toggle with selected/all fold controls:
  `<Space>tt` toggles the selected fold and `<Space>tT` folds the current view.
  Restored native marked-or-selected behavior for `a` and `d`, so `J`/`K`
  selections archive or trash as one batch while folded rows still expand to
  complete threads.
- 2026-09-21: Initially made single-key `a` and `d` dispositions force the
  selected thread. Superseded above after that approach erased `J`/`K` marks;
  explicit folds now provide whole-thread behavior without breaking batches.
- 2026-09-21: The sidebar now exposes Now, subject categories, Later, and Junk
  from the local Laya contract. `<Space>t...` records durable human attention
  and category corrections through the classifier ledger.

- 2026-09-15: Made sender-authored plain text the default reading view while
  retaining `h`/`l` MIME switching. Plain mail now uses a stable 100-column
  measure, collapses excess blank lines, strips untrusted terminal controls,
  and hides long tracking URLs behind local, clickable `↗ domain` labels
  without resolving or loading them.
- 2026-09-15: Made unsubscribe drafts an explicit two-step decision. Email-only
  senders first explain that unsubscribe requires an email; continuing opens
  aerc's review screen without Neovim, and `y` remains the separate send action.
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
