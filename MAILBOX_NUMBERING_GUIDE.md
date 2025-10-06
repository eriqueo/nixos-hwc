# Standardized Numbered Mailbox Guide

## Goal
Create consistent numbered mailbox prefixes (0-9) that work across:
- aerc keybindings (local Maildir names)
- mbsync syncing (server ↔ local mapping)
- All email accounts (ProtonMail, Gmail, etc.)

---

## The Problem

Your aerc bindings reference:
```
0_Inbox, 1_Archive, 2_Sent, 3_Drafts, 4_Important, etc.
```

But your IMAP servers have standard names:
- ProtonMail: `INBOX`, `Archive`, `Sent`, `Drafts`, `Folders/Important`
- Gmail: `INBOX`, `[Gmail]/All Mail`, `[Gmail]/Sent Mail`, `[Gmail]/Drafts`

mbsync needs to map between these correctly.

---

## The Solution: mbsync Channel Mapping

mbsync supports **per-folder renaming** using the `Patterns` directive with `:` notation:

```
Patterns "INBOX" "0_Inbox" "Archive" "1_Archive" "Sent" "2_Sent"
```

This means:
- **Remote (IMAP server):** `INBOX`, `Archive`, `Sent`
- **Local (Maildir):** `0_Inbox`, `1_Archive`, `2_Sent`

---

## Standard Mailbox Numbering Scheme

Based on your aerc bindings:

| Number | Purpose       | Common IMAP Names                          |
|--------|---------------|--------------------------------------------|
| 0      | Inbox         | `INBOX`                                    |
| 1      | Archive       | `Archive`, `[Gmail]/All Mail`              |
| 2      | Sent          | `Sent`, `[Gmail]/Sent Mail`                |
| 3      | Drafts        | `Drafts`, `[Gmail]/Drafts`                 |
| 4      | Important     | `Important`, `Folders/Important`, `Starred`|
| 5      | ProjectA      | Custom folder (create on server)          |
| 6      | ProjectB      | Custom folder (create on server)          |
| 7      | ReadLater     | Custom folder (create on server)          |
| 8      | Spam          | `Spam`, `Junk`, `[Gmail]/Spam`             |
| 9      | Trash         | `Trash`, `[Gmail]/Trash`                   |

---

## Implementation Steps

### Step 1: Add Mapping Configuration to Account Options

**File:** `domains/home/mail/accounts/parts/options.nix`

Add a new option for mailbox mapping:

```nix
mailboxMapping = lib.mkOption {
  type = lib.types.attrsOf lib.types.str;
  default = {
    "INBOX" = "0_Inbox";
    "Archive" = "1_Archive";
    "Sent" = "2_Sent";
    "Drafts" = "3_Drafts";
    "Important" = "4_Important";
    "Spam" = "8_Spam";
    "Trash" = "9_Trash";
  };
  description = ''
    Mapping of remote IMAP folder names to local numbered Maildir names.
    Format: { "RemoteName" = "LocalName"; }
  '';
};
```

### Step 2: Update mbsync render to use mappings

**File:** `domains/home/mail/mbsync/parts/render.nix`

Modify the `patternsFor` function to generate mapping patterns:

```nix
# OLD (around line 33):
patternsFor = a:
  let
    raw0 = a.sync.patterns or [ "INBOX" ];
    # ... existing code
  in
    # ... existing code

# NEW:
patternsFor = a:
  let
    # Get mailbox mapping if defined
    mapping = a.mailboxMapping or {};

    # Generate patterns with renaming
    mappedPatterns = lib.mapAttrsToList
      (remote: local: "\"${remote}\" \"${local}\"")
      mapping;

    # Keep existing sync.patterns for additional folders
    raw0 = a.sync.patterns or [];
    additionalPatterns = map confQuote raw0;

    # Combine
    allPatterns = mappedPatterns ++ additionalPatterns;

    # Add Proton custom folders
    withProton =
      if a.type == "proton-bridge"
      then allPatterns ++ [ "\"Folders/*\"" ]
      else allPatterns;
  in
    if common.isGmail a
    then lib.unique (map escapeSquareBrackets (lib.concatLists (map expandGoogleAliases withProton)))
    else lib.unique withProton;
```

### Step 3: Configure Each Account

**File:** `domains/home/mail/accounts/index.nix`

For each account, define its specific mapping:

#### ProtonMail Example:
```nix
hwc.home.mail.accounts.proton = {
  enable = true;
  type = "proton-bridge";
  # ... existing config ...

  mailboxMapping = {
    "INBOX" = "0_Inbox";
    "Archive" = "1_Archive";
    "Sent" = "2_Sent";
    "Drafts" = "3_Drafts";
    "Folders/Important" = "4_Important";
    "Folders/Work" = "5_Work";        # Custom folder
    "Folders/Personal" = "6_Personal"; # Custom folder
    "Spam" = "8_Spam";
    "Trash" = "9_Trash";
  };
};
```

#### Gmail Example:
```nix
hwc.home.mail.accounts.gmail-personal = {
  enable = true;
  type = "gmail";
  # ... existing config ...

  mailboxMapping = {
    "INBOX" = "0_Inbox";
    "[Gmail]/All Mail" = "1_Archive";
    "[Gmail]/Sent Mail" = "2_Sent";
    "[Gmail]/Drafts" = "3_Drafts";
    "[Gmail]/Starred" = "4_Important";
    "Work" = "5_Work";              # Custom label
    "Personal" = "6_Personal";      # Custom label
    "[Gmail]/Spam" = "8_Spam";
    "[Gmail]/Trash" = "9_Trash";
  };
};
```

---

## Step 4: Create Custom Folders on Server

For folders that don't exist yet (5-7 in your scheme), you need to create them:

### ProtonMail Web UI:
1. Go to Settings → Folders/Labels
2. Create: `Important`, `Work`, `Personal`, `ReadLater` (or your preferred names)
3. They will appear under `Folders/` in IMAP

### Gmail Web UI:
1. Create labels: `Work`, `Personal`, `ReadLater`
2. In Settings → Labels, enable "Show in IMAP" for each
3. They will appear as top-level folders in IMAP

---

## Step 5: Update aerc bindings

Your aerc bindings are already correct! They reference the local numbered names:

```
x0 = :mv 0_Inbox<Enter>
x1 = :mv 1_Archive<Enter>
# etc.
```

Once mbsync creates the numbered folders locally, aerc will find them.

---

## Step 6: Initial Sync & Migration

After implementing the changes:

1. **Backup existing mail:**
   ```bash
   cp -r ~/Maildir ~/Maildir.backup
   ```

2. **Clear local mail (optional - forces clean sync):**
   ```bash
   rm -rf ~/Maildir/*
   ```

3. **Rebuild NixOS:**
   ```bash
   sudo nixos-rebuild switch --flake .#hwc-laptop
   ```

4. **Run initial sync:**
   ```bash
   mbsync -a
   ```

5. **Verify folder structure:**
   ```bash
   ls -la ~/Maildir/iheartwoodcraft/
   # Should show: 0_Inbox/ 1_Archive/ 2_Sent/ etc.
   ```

6. **Test in aerc:**
   ```bash
   aerc
   # Try: <Space>g0 (should go to 0_Inbox)
   # Try: x1 (should move message to 1_Archive)
   ```

---

## Alternative: Simpler Approach (If Above is Too Complex)

If modifying mbsync render is too complex, you can use **symlinks**:

### After normal mbsync (without renaming):

```bash
#!/usr/bin/env bash
# ~/scripts/create-numbered-mailbox-links.sh

MAILDIR="$HOME/Maildir"

for account in iheartwoodcraft proton gmail-personal gmail-business; do
  cd "$MAILDIR/$account" || continue

  # Create numbered symlinks pointing to actual folders
  ln -sf INBOX 0_Inbox
  ln -sf Archive 1_Archive
  ln -sf Sent 2_Sent
  ln -sf Drafts 3_Drafts
  ln -sf Important 4_Important
  ln -sf Spam 8_Spam
  ln -sf Trash 9_Trash

  # Gmail-specific
  if [[ "$account" == gmail-* ]]; then
    ln -sf "[Gmail]/All Mail" 1_Archive
    ln -sf "[Gmail]/Sent Mail" 2_Sent
    ln -sf "[Gmail]/Drafts" 3_Drafts
    ln -sf "[Gmail]/Starred" 4_Important
    ln -sf "[Gmail]/Spam" 8_Spam
    ln -sf "[Gmail]/Trash" 9_Trash
  fi
done
```

**Add to mbsync service:**

```nix
# domains/home/mail/mbsync/parts/service.nix
ExecStartPost = "${pkgs.bash}/bin/bash /home/eric/scripts/create-numbered-mailbox-links.sh";
```

**Pros:**
- Simple, no mbsync config changes
- Easy to understand and debug

**Cons:**
- Symlinks might confuse some mail clients
- Doesn't actually rename folders on disk
- Links need recreation after each sync

---

## Recommended Approach

**Use the mbsync mapping approach (Steps 1-6)** because:
- ✅ Folders are actually renamed (cleaner)
- ✅ Works with all mail clients
- ✅ Consistent across rebuilds
- ✅ No post-sync scripts needed

The symlink approach is a quick hack if you need it working immediately.

---

## Troubleshooting

### Folders not syncing:
- Check `mbsync -a -D` for debug output
- Verify folder exists on server (check webmail)
- Check `Patterns` line in generated `~/.mbsyncrc`

### aerc can't find folders:
- Run `ls ~/Maildir/<account>/` to verify names
- Check aerc config references match exactly (case-sensitive)
- Try `:cf 0_Inbox` manually in aerc

### Messages disappear:
- Check server webmail - they should be in the renamed folder
- mbsync might have moved them correctly but aerc is looking in wrong place
- Verify `mailboxMapping` matches both server names and aerc bindings

---

## Summary

1. Add `mailboxMapping` option to account options
2. Update mbsync render to use mappings in `Patterns`
3. Configure each account with server→local name mapping
4. Create custom folders on server if needed
5. Rebuild and sync
6. Test in aerc

**Result:** Consistent 0-9 numbered folders across all accounts, clean keybindings, proper server sync.
