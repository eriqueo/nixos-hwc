# Domain-Based Unified Mailbox Guide

**Owner**: Eric
**Scope**: `~/Maildir/` — All email organization
**Goal**: Unified domain-based mailboxes with source account tagging and visual differentiation

---

## Core Principles

1. **Domain Separation**: Organize by context (work/personal), not by email account
2. **Unified Inboxes**: Single inbox per domain, regardless of source account
3. **Source Tagging**: Auto-tag messages by source account for filtering/searching
4. **Visual Differentiation**: Color-coded by account within domain (blue spectrum = work, purple = personal)
5. **3-Digit Numbering**: Align with Filesystem Charter (`XXX-name` format)

---

## Mailbox Structure

### Work Domain (100-199)
```
100-work/
├── 110-inbox/          # Unified work inbox (all work accounts)
├── 111-archive/        # Archived work emails
├── 112-sent/           # Sent work emails
├── 113-drafts/         # Work drafts
├── 114-clients/        # Client-specific threads
├── 115-projects/       # Project-specific threads
├── 118-spam/           # Work spam
└── 119-trash/          # Deleted work emails
```

### Personal Domain (200-299)
```
200-personal/
├── 210-inbox/          # Unified personal inbox (all personal accounts)
├── 211-archive/        # Archived personal emails
├── 212-sent/           # Sent personal emails
├── 213-drafts/         # Personal drafts
├── 214-important/      # Starred/important personal emails
├── 218-spam/           # Personal spam
└── 219-trash/          # Deleted personal emails
```

---

## Account Routing & Tagging

### Work Accounts → `100-work/`

| Account           | IMAP Folders                          | Local Folders      | Auto-Tags      | Color Scheme |
|-------------------|---------------------------------------|--------------------|----------------|--------------|
| iheartwoodcraft   | INBOX, Archive, Sent, Drafts, Trash  | 110-inbox, etc.    | `hwc-email`    | Light Blue   |
| gmail-business    | INBOX, [Gmail]/*, etc.                | 110-inbox, etc.    | `gmail-work`   | Dark Blue    |

### Personal Accounts → `200-personal/`

| Account           | IMAP Folders                          | Local Folders      | Auto-Tags          | Color Scheme  |
|-------------------|---------------------------------------|--------------------|-------------------|---------------|
| gmail-personal    | INBOX, [Gmail]/*, etc.                | 210-inbox, etc.    | `gmail-personal`  | Light Purple  |
| proton            | INBOX, Archive, Sent, Drafts, Trash   | 210-inbox, etc.    | `proton-personal` | Dark Purple   |

---

## Folder Numbering Pattern

Within each domain, use the tens place for folder type:

| Range  | Purpose                  | Examples                              |
|--------|--------------------------|---------------------------------------|
| XX0-XX4| Core mail folders        | XX0=inbox, XX1=archive, XX2=sent, XX3=drafts, XX4=important/starred |
| XX5-XX7| Custom/project folders   | XX5=projects, XX6=clients, XX7=reading |
| XX8    | Spam                     | XX8=spam                              |
| XX9    | Trash                    | XX9=trash                             |

---

## Implementation Details

### 1. mbsync Configuration

**Goal**: Route multiple accounts into unified domain mailboxes

**Strategy**: Use mbsync's multi-master sync to pull all work accounts → `100-work/`, all personal → `200-personal/`

**Example mapping** (iheartwoodcraft → 100-work):
```
Patterns "INBOX" "110-inbox" "Archive" "111-archive" "Sent" "112-sent"
```

**Example mapping** (gmail-business → 100-work):
```
Patterns "INBOX" "110-inbox" "[Gmail]/All Mail" "111-archive" "[Gmail]/Sent Mail" "112-sent"
```

**Example mapping** (gmail-personal → 200-personal):
```
Patterns "INBOX" "210-inbox" "[Gmail]/All Mail" "211-archive" "[Gmail]/Sent Mail" "212-sent"
```

**Example mapping** (proton → 200-personal):
```
Patterns "INBOX" "210-inbox" "Archive" "211-archive" "Sent" "212-sent"
```

### 2. notmuch Tagging

**Goal**: Auto-tag messages by source account on sync

**Tagging rules** (`~/.notmuch-config` or post-new hook):

```bash
# Work domain tags
notmuch tag +hwc-email +work -- folder:100-work/** and from:*@iheartwoodcraft.com
notmuch tag +gmail-work +work -- folder:100-work/** and from:*@gmail.com

# Personal domain tags
notmuch tag +gmail-personal +personal -- folder:200-personal/** and from:*@gmail.com
notmuch tag +proton-personal +personal -- folder:200-personal/** and from:*@proton.me
```

**Additional useful tags:**
- `+inbox` for messages in XX0-inbox folders
- `+archived` for messages in XX1-archive folders
- `+unread` for new messages
- `+flagged` for important/starred

### 3. aerc Color Configuration

**Goal**: Visual differentiation by source account within unified inbox

**Color scheme** (`~/.config/aerc/aerc.conf` or stylesets):

```ini
# Work domain - Blue spectrum
*.hwc-email = blue
*.gmail-work = darkblue

# Personal domain - Purple spectrum
*.gmail-personal = lightmagenta
*.proton-personal = magenta

# Folder-based colors
*.work = blue
*.personal = magenta
```

### 4. aerc Keybindings

**Updated keybindings** for 3-digit folder structure:

```ini
# Move to inbox
<Space>g0 = :cf 110-inbox<Enter>   # Work inbox
<Space>g2 = :cf 210-inbox<Enter>   # Personal inbox

# Quick file messages
x0 = :mv 110-inbox<Enter>          # To work inbox
x1 = :mv 111-archive<Enter>        # To work archive
x2 = :mv 112-sent<Enter>           # To work sent
x4 = :mv 114-clients<Enter>        # To work clients
x5 = :mv 115-projects<Enter>       # To work projects

p0 = :mv 210-inbox<Enter>          # To personal inbox
p1 = :mv 211-archive<Enter>        # To personal archive
p4 = :mv 214-important<Enter>      # To personal important

# Quick spam/trash
x8 = :mv 118-spam<Enter>           # Work spam
x9 = :mv 119-trash<Enter>          # Work trash
p9 = :mv 219-trash<Enter>          # Personal trash
```

---

## Workflow

### Receiving Mail
1. **Sync**: `mbsync -a` pulls all accounts into unified domain folders
2. **Tag**: notmuch post-new hook auto-tags by source account
3. **View**: Open aerc, see unified inbox with color-coded messages

### Filtering by Account
- Search work from HWC: `tag:hwc-email`
- Search work from Gmail: `tag:gmail-work`
- Search all work: `tag:work` or `folder:100-work/**`
- Search all personal: `tag:personal` or `folder:200-personal/**`

### Filing Messages
- Use keybindings (`x1`, `x4`, `p1`, etc.) to move to appropriate folders
- Archive is domain-specific (work archive vs personal archive)
- Projects/clients folders for active threads

---

## Migration Plan

### Phase 1: Backup
```bash
cp -r ~/Maildir ~/Maildir.backup.$(date +%Y%m%d)
```

### Phase 2: Update Configuration
1. Update mbsync account mappings (route to unified folders)
2. Update notmuch tagging rules
3. Update aerc colors and keybindings
4. Rebuild NixOS: `sudo nixos-rebuild switch --flake .#hwc-laptop`

### Phase 3: Initial Sync
```bash
# Clear existing Maildir (backup already made)
rm -rf ~/Maildir/*

# Sync all accounts into new structure
mbsync -a

# Initial notmuch index
notmuch new
```

### Phase 4: Verification
```bash
# Check folder structure
tree -L 2 -d ~/Maildir/

# Should show:
# 100-work/110-inbox/
# 100-work/111-archive/
# ...
# 200-personal/210-inbox/
# ...

# Check tags
notmuch search tag:hwc-email
notmuch search tag:gmail-work
notmuch search tag:gmail-personal
notmuch search tag:proton-personal
```

### Phase 5: Test in aerc
- Open aerc
- Navigate folders with updated keybindings
- Verify color coding
- Test message filing
- Test search/filter by tags

---

## Troubleshooting

### Messages syncing to wrong domain
- Check mbsync `Patterns` mapping in account config
- Verify account is routing to correct domain folder (100-work vs 200-personal)

### Tags not applying
- Check notmuch post-new hook is running
- Verify `from:` patterns match actual email addresses
- Manually tag: `notmuch tag +hwc-email -- from:*@iheartwoodcraft.com`

### Colors not showing in aerc
- Check aerc styleset configuration
- Verify tag names match exactly (case-sensitive)
- Test with: `notmuch search tag:hwc-email` (should show messages)

### Duplicate messages in unified inbox
- mbsync might be syncing same message from multiple accounts
- Use notmuch deduplication or adjust sync patterns

---

## Benefits of This Approach

✅ **Single work inbox** - All work email in one place, regardless of source account
✅ **Single personal inbox** - All personal email unified
✅ **Context-based organization** - File by domain (work vs personal), not by account
✅ **Visual differentiation** - Colors show account source at a glance
✅ **Searchable by source** - Tags enable filtering by specific account when needed
✅ **Filesystem Charter alignment** - 3-digit numbering with domain separation
✅ **Scalable** - Easy to add new accounts (just route to appropriate domain)
✅ **Clean keybindings** - Predictable, domain-aware folder navigation

---

## Future Enhancements

### Additional Domains
- `300-tech/` for GitHub notifications, dev mailing lists
- `000-system/` for server/monitoring alerts

### Additional Folders
- `116-waiting/` for emails awaiting response
- `117-reading/` for newsletters/long reads
- `225-receipts/` for purchase confirmations

### Smart Filtering
- Auto-file by sender patterns
- Auto-tag by subject keywords
- Priority inbox via notmuch queries

---

**Version**: v2.0 - Domain-Based Unified Mailboxes
**Last Updated**: 2025-10-06
**Status**: Active implementation
