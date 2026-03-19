# aerc — Terminal Email Client

Declarative aerc configuration for a unified Proton Mail + Notmuch setup, managed via NixOS Home Manager.

## Purpose

Single-account email workflow: all addresses (eric@iheartwoodcraft.com, eriqueo@proton.me, office@, eriqueokeefe@gmail.com) consolidated through Proton Bridge. Uses notmuch for indexing and virtual folders, msmtp for sending, and mbsync for IMAP sync.

## Boundaries

- **Owns**: aerc.conf, binds.conf, accounts.conf, notmuch-queries, stylesets, templates, ov pager config
- **Depends on**: `domains/home/mail/` (accounts, mbsync, notmuch, msmtp, afew)
- **Never contains**: systemd services, mail sync logic, secret declarations

## Structure

```
aerc/
  index.nix              # Module entry — enable toggle, packages, shell aliases, activation
  parts/
    tags.nix             # Single source of truth for tag definitions (colors, keys, queries)
    config.nix           # aerc.conf, accounts.conf, notmuch-queries, stylesets, templates
    binds.nix            # binds.conf (keybindings) + ov pager config
    theme.nix            # hwc-theme styleset (Gruvbox-inspired, palette-driven)
    session.nix          # Shell environment helpers (legacy, mostly moved to index.nix)
    sieve.nix            # Server-side sieve filter rules
    behavior.nix         # Reference behavior documentation (not imported)
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

### Tag System (tags.nix)

All tag metadata is defined once in `tags.nix` and consumed by both `config.nix` and `binds.nix`. Adding a new tag to this file automatically generates:

- Notmuch query-map entry (virtual folder in aerc)
- Column-tags `.StyleMap` case (colored tag pill in message list)
- `.Style` switch case (tag-based row coloring for date/sender/to/subject)
- `[user]` styleset section (appended to all 9 bundled themes)
- Exclusive single-key binding (if `key` is set)
- `<Space>m*` additive label binding
- `<Space>g*` go-to-folder binding

#### Tag Types

| Type | Behavior | Example |
|------|----------|---------|
| **Category** (`categoryTags`) | Mutually exclusive — pressing one removes all others + inbox | work, finance, tech, personal, family |
| **Flag** (`flagTags`) | Additive — coexists with categories | starred, hwcmt |

#### Tag Attributes

| Attribute | Required | Description |
|-----------|----------|-------------|
| `tag` | yes | Notmuch tag name |
| `color` | yes | Hex color for `[user]` styleset section |
| `key` | no | Single-key exclusive binding in `[messages]` (category tags only) |
| `spaceKey` | no | Key for `<Space>m*` and `<Space>g*` bindings (defaults to first char of tag) |
| `display` | no | Display name in query-map and stylesets (defaults to tag) |
| `query` | no | Custom notmuch query (defaults to `tag:<name> AND NOT tag:trash`) |
| `extra` | no | Extra styleset lines (e.g., `"insurance.dim = true"`) |
| `noGoTo` | no | Skip `<Space>g*` generation (avoids key conflicts) |

#### Current Tags

| Tag | Color | Key | Space | Folder |
|-----|-------|-----|-------|--------|
| starred | red `#FF5555` | `s` | `*` | starred |
| hwcmt | orange `#FFB86C` (dim) | — | `h` | hwcmt |
| work | orange `#FFB86C` | `w` | `w` | work |
| coaching | yellow `#F1FA8C` | — | `c` | coaching |
| finance | green `#50FA7B` | `f` | `f` | finance |
| bank | cyan `#8BE9FD` | — | `b` | bank |
| insurance | green `#50FA7B` (dim) | — | `i` | — |
| tech | purple `#BD93F9` | — | `t` | tech |
| personal | pink `#FF79C6` | `p` | `p` | personal |
| family | sage `#98C379` | — | `y` | family |

### Stylesets

All 9 bundled aerc stylesets (blue, catppuccin, default, dracula, monochrome, nord, pink, solarized, solarized-dark) are copied at Nix eval time with a `[user]` section appended containing tag colors. This means tag coloring works regardless of which theme is active.

Switch themes live with `<Space>ts` followed by the theme name (tab-completes).

The custom `hwc-theme` styleset in `theme.nix` is palette-driven from `hwc.home.theme.colors` and includes domain-based sender coloring (iheartwoodcraft.com, gmail, proton addresses).

## Keybindings

### Global

| Key | Action |
|-----|--------|
| `<C-h>` / `<C-l>` | Prev/next tab |
| `<C-j>` / `<C-k>` | Next/prev folder |
| `<C-p>` / `<C-n>` | Next/prev account |
| `<C-r>` | Full mail sync (mbsync + notmuch new) |
| `<C-q>` | Quit (with confirmation) |
| `<C-t>` | Open terminal |
| `?` | View binds.conf |
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

### Tagging (Messages)

| Key | Action |
|-----|--------|
| `a` | Archive (`+archive -inbox`) |
| `d` | Trash (`+trash -inbox`) |
| `s` | Star (`+starred`) |
| `S` | Spam (`+spam -inbox`) |
| `w` | Work (exclusive — removes other categories) |
| `f` | Finance (exclusive) |
| `t` | Tech (exclusive) |
| `p` | Personal (exclusive) |
| `X` | Move to folder (prompt) |
| `Y` | Copy to folder (prompt) |

### Space-Leader Navigation (`<Space>g*`)

| Key | Folder |
|-----|--------|
| `<Space>gi` | inbox |
| `<Space>gu` | unread |
| `<Space>ga` | Archive |
| `<Space>gs` | sent |
| `<Space>gd` | trash |
| `<Space>gS` | spam |
| `<Space>gH` | hide_my_email |
| `<Space>g*` | starred |
| `<Space>gh` | hwcmt |
| `<Space>gw` | work |
| `<Space>gc` | coaching |
| `<Space>gf` | finance |
| `<Space>gb` | bank |
| `<Space>gt` | tech |
| `<Space>gp` | personal |
| `<Space>gy` | family |

### Space-Leader Labels (`<Space>m*`)

| Key | Action |
|-----|--------|
| `<Space>mu` | +unread |
| `<Space>ma` | +archive -inbox |
| `<Space>m*` | +starred |
| `<Space>mh` | +hwcmt |
| `<Space>md` | +trash -inbox |
| `<Space>mS` | +spam -inbox |
| `<Space>ml` | Free-form label (prompt) |
| `<Space>mw` | +work -inbox |
| `<Space>mc` | +coaching -inbox |
| `<Space>mf` | +finance -inbox |
| `<Space>mb` | +bank -inbox |
| `<Space>mi` | +insurance -inbox |
| `<Space>mt` | +tech -inbox |
| `<Space>mp` | +personal -inbox |
| `<Space>my` | +family -inbox |

### Filter / Sort

| Key | Action |
|-----|--------|
| `<Space>ff` | Filter messages |
| `<Space>fs` | Search messages |
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
| `s` | Star |
| `H` | Toggle headers |
| `u` | Open link |
| `O` | Open attachment |
| `S` | Save attachment |
| `U` | URL scan (urlscan) |
| `/` | Search in pager (passthrough) |

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
tags<12 | date<10 | from<16 | to<14 | flags>4 | subject<*
```

| Column | Template | Description |
|--------|----------|-------------|
| `tags` | `.StyleMap` | Colored tag pills (system tags excluded) |
| `date` | `.DateAutoFormat` | Relative dates (Today, Yesterday, Mon 10 Mar) |
| `from` | `.From \| names` | Sender display name |
| `to` | `.To \| names` | Recipient display name (shows which address received) |
| `flags` | Symbolic | `●` unread, `↩` replied, `★` flagged, `⊞` attachment |
| `subject` | `.Subject` | Subject with thread prefix and fold count |

All columns are colored by tag category via `.Style` with a derived switch expression.

## Virtual Folders (Query Map)

Static folders:

| Folder | Query |
|--------|-------|
| inbox | `tag:inbox AND NOT tag:trash` |
| unread | `tag:unread AND NOT tag:trash` |
| sent | `tag:sent` |
| drafts | `tag:draft` |
| Archive | `tag:archive AND NOT tag:trash` |
| trash | `tag:trash` |
| spam | `tag:spam` |
| important | `tag:important AND NOT tag:trash` |
| hide_my_email | `tag:hide` |

Tag-derived folders (auto-generated from `tags.nix`):

| Folder | Query |
|--------|-------|
| starred | `tag:starred AND NOT tag:trash` |
| hwcmt | `tag:hwcmt AND NOT tag:trash` |
| work | `tag:work AND NOT tag:trash` |
| coaching | `tag:coaching AND NOT tag:trash` |
| finance | `tag:finance AND NOT tag:trash` |
| bank | `tag:bank AND NOT tag:trash` |
| insurance | `tag:insurance AND NOT tag:trash` |
| tech | `tag:tech AND NOT tag:trash` |
| personal | `(tag:gmail-personal OR tag:personal) AND NOT tag:trash` |
| family | `tag:family AND NOT tag:trash` |

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

1. Add entry to `categoryTags` or `flagTags` in `parts/tags.nix`
2. Rebuild — query-map, stylesets, bindings, and column coloring update automatically
3. If Proton label exists, the post-new hook auto-discovers it from `proton/Labels/<name>/`

## Changelog

- 2026-03-19: Fix act-one-delete-rest → act-dir (was deleting label file copies); fix hide_my_email query to use tag:hide instead of wrong Folders/ path
- 2026-03-15: Add family and hwcmt tags; spam folder and bidirectional sync; hide_my_email folder; to column; symbolic flags; human-readable column layout; full sync-mail pipeline on `<C-r>`; tag exclude filters for notifications/action/aerc; single-source-of-truth tag system with derived bindings, queries, stylesets, and column templates
- 2026-03-14: Fix compose editor (lf-editor), send (msmtp path), TLS (certcheck off); add compose review bindings; switch to dracula styleset with live switching; add tag-based message coloring across all themes; add quoted_reply HTML template; add bundled filters and multipart-converters
