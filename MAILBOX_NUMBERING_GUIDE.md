# Unified Inbox Maildir Architecture

**Owner**: Eric
**Scope**: `~/Maildir/` — All email organization
**Goal**: GTD-style unified inbox with domain-based contextual filing
**Philosophy**: Single pane of glass, process once, file by context

---

## Core Principles

1. **Single Unified Inbox**: All new mail from all accounts lands in `000_inbox` — **one place to check**
2. **Global System Folders**: Shared Sent (`010_sent`), Drafts (`011_drafts`), Spam (`800_spam`), Trash (`900_trash`)
3. **Domain-Specific Archives**: Contextual filing into `190_hwc-archive` (work) or `290_pers-archive` (personal)
4. **Source Account Tagging**: notmuch auto-tags by account, aerc color-codes for visual differentiation
5. **Filesystem Charter Alignment**: 3-digit numbering (`XXX_name`) with domain separation

---

## The Critical Difference

### ❌ Wrong (Segregated Systems)
```
100-work/110-inbox/        ← Separate work inbox
100-work/111-archive/
200-personal/210-inbox/    ← Separate personal inbox
200-personal/211-archive/
```
**Problem**: Multiple inboxes to check, violates GTD "single collection point" principle

### ✅ Correct (Unified Inbox)
```
000_inbox/                 ← THE ONLY inbox (all accounts)
190_hwc-archive/           ← Work archive (filed contextually)
290_pers-archive/          ← Personal archive (filed contextually)
```
**Benefit**: One inbox, process once, file by context

---

## Maildir Structure

### Global Folders (Shared Across All Accounts)

```
~/Maildir/
├── 000_inbox/             # Unified inbox - ALL new mail lands here
├── 010_sent/              # Global sent folder
├── 011_drafts/            # Global drafts folder
├── 800_spam/              # Global spam folder
└── 900_trash/             # Global trash folder
```

### Domain-Specific Folders (Contextual Filing)

```
~/Maildir/
├── 190_hwc-archive/       # Work archived mail
├── 120_hwc-dev/           # Work development/projects
├── 290_pers-archive/      # Personal archived mail
├── 210_pers-important/    # Personal important/starred
└── 220_pers-dev/          # Personal development/projects
```

### Per-Account Sync Paths (Hidden Implementation Detail)

```
~/Maildir/
├── 100_hwc/               # HWC account sync path
├── 110_gmail-business/    # Gmail business sync path
├── 200_personal/          # Gmail personal sync path
└── 210_proton/            # Proton sync path
```

**Note**: These directories are mbsync implementation details. Users interact with the unified `000_inbox` and domain folders above.

---

## Account Configuration

### Work Domain (1xx)

**iheartwoodcraft** (`eric@iheartwoodcraft.com`):
```nix
maildirName = "100_hwc";
mailboxMapping = {
  "INBOX"   = "000_inbox";         # → Unified inbox
  "Sent"    = "010_sent";          # → Global sent
  "Drafts"  = "011_drafts";        # → Global drafts
  "Archive" = "190_hwc-archive";   # → Work archive
  "Spam"    = "800_spam";          # → Global spam
  "Trash"   = "900_trash";         # → Global trash
};
```

**gmail-business** (`heartwoodcraftmt@gmail.com`):
```nix
maildirName = "110_gmail-business";
mailboxMapping = {
  "INBOX"               = "000_inbox";         # → Unified inbox
  "[Gmail]/Sent Mail"   = "010_sent";          # → Global sent
  "[Gmail]/Drafts"      = "011_drafts";        # → Global drafts
  "[Gmail]/All Mail"    = "190_hwc-archive";   # → Work archive
  "[Gmail]/Spam"        = "800_spam";          # → Global spam
  "[Gmail]/Trash"       = "900_trash";         # → Global trash
};
```

### Personal Domain (2xx)

**gmail-personal** (`eriqueokeefe@gmail.com`):
```nix
maildirName = "200_personal";
mailboxMapping = {
  "INBOX"               = "000_inbox";         # → Unified inbox
  "[Gmail]/Sent Mail"   = "010_sent";          # → Global sent
  "[Gmail]/Drafts"      = "011_drafts";        # → Global drafts
  "[Gmail]/All Mail"    = "290_pers-archive";  # → Personal archive
  "[Gmail]/Starred"     = "210_pers-important";# → Personal important
  "[Gmail]/Spam"        = "800_spam";          # → Global spam
  "[Gmail]/Trash"       = "900_trash";         # → Global trash
};
```

**proton** (`eriqueo@proton.me`):
```nix
maildirName = "210_proton";
mailboxMapping = {
  "INBOX"   = "000_inbox";         # → Unified inbox
  "Sent"    = "010_sent";          # → Global sent
  "Drafts"  = "011_drafts";        # → Global drafts
  "Archive" = "290_pers-archive";  # → Personal archive
  "Spam"    = "800_spam";          # → Global spam
  "Trash"   = "900_trash";         # → Global trash
};
```

---

## notmuch Tagging Strategy

Auto-applied tags for visual differentiation and filtering:

```bash
# Tag by source account
notmuch tag +hwc-email -- 'path:100_hwc/** OR from:*@iheartwoodcraft.com'
notmuch tag +gmail-work -- 'path:110_gmail-business/** OR from:*heartwoodcraftmt@gmail.com'
notmuch tag +gmail-personal -- 'path:200_personal/** OR from:*eriqueokeefe@gmail.com'
notmuch tag +proton-personal -- 'path:210_proton/** OR from:*@proton.me'

# Tag by domain (derived)
notmuch tag +work -- 'tag:hwc-email OR tag:gmail-work'
notmuch tag +personal -- 'tag:gmail-personal OR tag:proton-personal'

# Tag unified inbox
notmuch tag +inbox -- 'folder:000_inbox'
```

---

## aerc Color Scheme

Visual differentiation in the unified inbox:

| Tag               | Color         | Purpose                    |
|-------------------|---------------|----------------------------|
| `hwc-email`       | Light Blue    | HWC work email             |
| `gmail-work`      | Dark Blue     | Gmail work email           |
| `gmail-personal`  | Light Purple  | Gmail personal email       |
| `proton-personal` | Dark Purple   | Proton personal email      |
| `work`            | Blue          | Any work domain email      |
| `personal`        | Purple        | Any personal domain email  |

Configuration in `domains/home/apps/aerc/parts/theme.nix`:
```nix
"*.hwc-email" = token "#5DA0DE" "default" false;       # Light blue
"*.gmail-work" = token "#2563EB" "default" false;      # Dark blue
"*.gmail-personal" = token "#C084FC" "default" false;  # Light purple
"*.proton-personal" = token "#9333EA" "default" false; # Dark purple
```

---

## aerc Keybindings

### Primary Workflow

```ini
# Archive (generic - aerc decides)
d = :archive flat<Enter>

# Archive to specific domain
d1 = :mv 190_hwc-archive<Enter>      # Work archive
d2 = :mv 290_pers-archive<Enter>     # Personal archive

# Delete
D = :delete<Enter>
```

### Navigation (`<Space>g` for "Go")

```ini
<Space>gi = :cf 000_inbox<Enter>          # The one true Inbox
<Space>gs = :cf 010_sent<Enter>           # Sent
<Space>gd = :cf 011_drafts<Enter>         # Drafts
<Space>ga1 = :cf 190_hwc-archive<Enter>   # Work archive
<Space>ga2 = :cf 290_pers-archive<Enter>  # Personal archive
<Space>gp1 = :cf 120_hwc-dev<Enter>  # Work development
<Space>gp2 = :cf 220_pers-dev<Enter> # Personal development
```

### Filing (`<Space>m` for "Move")

```ini
<Space>mp1 = :mv 120_hwc-dev<Enter>      # Work development
<Space>mp2 = :mv 220_pers-dev<Enter>     # Personal development
<Space>mi = :mv 210_pers-important<Enter>     # Personal important
```

---

## Workflow Example

### Morning Email Processing

1. **Open aerc** → Automatically shows `000_inbox`
2. **See unified inbox** with color-coded messages:
   - Light blue = HWC work email
   - Dark blue = Gmail work email
   - Light purple = Gmail personal
   - Dark purple = Proton personal
3. **Process each message**:
   - Work email → Press `d1` → Moves to `190_hwc-archive`
   - Personal email → Press `d2` → Moves to `290_pers-archive`
   - Project-specific → Press `<Space>mp1` → Moves to `120_hwc-dev`
4. **Result**: Empty inbox, everything filed contextually

### Searching

```bash
# Find all work email
:filter tag:work

# Find all HWC email specifically
:filter tag:hwc-email

# Find all personal email
:filter tag:personal

# Find all unread in inbox
:filter tag:inbox AND tag:unread
```

---

## Why This Architecture Works

### ✅ Single Collection Point (GTD)
- Only one inbox to check (`000_inbox`)
- All new mail visible in one view
- No mental overhead deciding "which inbox to check"

### ✅ Contextual Filing
- Archive work email → `190_hwc-archive`
- Archive personal email → `290_pers-archive`
- File by context, not by source account

### ✅ Visual Clarity
- Color coding shows account source at a glance
- No need to segregate into separate inboxes
- Unified view with instant visual differentiation

### ✅ Filesystem Charter Alignment
- 3-digit numbering (`000_inbox`, `190_hwc-archive`)
- Domain separation (1xx = work, 2xx = personal)
- Consistent with file organization principles

### ✅ Scalable
- Easy to add new accounts (just route to `000_inbox`)
- Easy to add new domain folders (`3xx_tech/`, etc.)
- Simple, predictable structure

---

## Anti-Patterns to Avoid

### ❌ Multiple Inboxes
**Bad**: Creating `110-inbox`, `210-inbox` folders
**Why**: Violates "single pane of glass" principle, increases cognitive load

### ❌ Account-Based Filing
**Bad**: Filing by account (`100_hwc/archive/`, `200_personal/archive/`)
**Why**: Breaks contextual organization, creates silos

### ❌ Moving Messages to Inbox
**Bad**: Keybinding like `x0 = :mv 000_inbox<Enter>`
**Why**: Inbox is for new mail only, not a filing destination

### ❌ Segregated Sent/Drafts
**Bad**: Creating `110-sent`, `210-sent` folders
**Why**: Mail clients expect single Sent/Drafts folders

---

## Migration Steps

### 1. Backup
```bash
cp -r ~/Maildir ~/Maildir.backup.$(date +%Y%m%d)
```

### 2. Rebuild System
```bash
git add -A
git commit -m "feat(mail): implement unified inbox architecture"
sudo nixos-rebuild switch --flake .#hwc-laptop
```

### 3. Clear and Resync
```bash
rm -rf ~/Maildir/*
mbsync -a
notmuch new
```

### 4. Verify Structure
```bash
tree -L 1 -d ~/Maildir/

# Should show:
# 000_inbox/
# 010_sent/
# 011_drafts/
# 100_hwc/
# 110_gmail-business/
# 190_hwc-archive/
# 200_personal/
# 210_proton/
# 290_pers-archive/
# 800_spam/
# 900_trash/
```

### 5. Test in aerc
- Open aerc
- Verify `000_inbox` is default view
- Check color coding on messages
- Test `d1`/`d2` archiving
- Test `<Space>gi` navigation

---

## Troubleshooting

### Inbox not showing messages
- Check `mbsync -a` ran successfully
- Verify `notmuch new` indexed mail
- Check `~/Maildir/000_inbox/` contains files

### Colors not showing
- Verify notmuch tags applied: `notmuch search tag:hwc-email`
- Check aerc theme loaded: `~/.config/aerc/stylesets/hwc-theme`
- Restart aerc

### Messages syncing to wrong folders
- Check `mailboxMapping` in account config
- Verify mbsync patterns: `cat ~/.mbsyncrc`
- Re-run `mbsync -a` after config changes

---

## Summary

This architecture creates a **powerful unified inbox** that:
- ✅ Processes all mail in one place (`000_inbox`)
- ✅ Files contextually by domain (`190_hwc-archive`, `290_pers-archive`)
- ✅ Maintains visual differentiation via colors (blue = work, purple = personal)
- ✅ Aligns with Filesystem Charter principles
- ✅ Scales elegantly as accounts/domains grow

**The goal**: One inbox to check, color-coded messages, contextual filing, zero cognitive overhead.

---

**Version**: v3.0 - Unified Inbox Architecture
**Last Updated**: 2025-10-06
**Status**: Production implementation
