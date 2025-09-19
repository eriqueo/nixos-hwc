# NeoMutt • Behavior/macros (data-only part; index.nix writes files)
{ lib, pkgs, config, ... }:

let
  accounts  = config.features.mail.accounts or {};
  accNames  = lib.attrNames accounts;

  # Derive maildir for an account (prefer maildirName, else name)
  maildirOf = n: (accounts.${n}.maildirName or n);

  # 1-based enumeration producing a list of { name, idx }
  numbered  = lib.imap1 (i: n: { name = n; idx = toString i; }) accNames;

  # First-letter helper for optional letter macros
  firstChar = s: builtins.substring 0 1 s;

  # Where to save attachments via macro (adjust if you like)
  attachmentsDir = "~/Mail/attachments/";
in
{
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text = ''
      ########################################
      # BEHAVIOR / BINDINGS / MACROS
      # (Keep "G..." free for account jumps)
      ########################################

      # ----------------------------
      # 0) Clear/guard risky defaults
      # ----------------------------
      bind index \\ noop
      bind pager \\ noop
      # Reserve plain 'G' so "G1i", "Ga i", etc. macros work
      bind index G noop
      bind pager G noop
      # (We also leave 'g' free to avoid alias warnings with 'gi' patterns)

      # ----------------------------
      # 1) Vim-ish navigation (safe subset)
      # ----------------------------
      # Move within lists/messages
      bind index j next-entry
      bind index k previous-entry
      bind pager j next-line
      bind pager k previous-line

      # Page scroll (Ctrl-D / Ctrl-U)
      bind attach,index,pager \\CD next-page
      bind attach,index,pager \\CU previous-page

      # Go to first/last entries without stealing 'G'
      bind attach,index <home> first-entry
      bind attach,index <end>  last-entry
      bind pager <home> top
      bind pager <end>  bottom

      # ----------------------------
      # 2) Sidebar navigation
      # ----------------------------
      # Match sample's style: \CJ / \CK / \CE
      bind index,pager \\CJ sidebar-prev
      bind index,pager \\CK sidebar-next
      bind index,pager \\CE sidebar-open
      bind index,pager B    sidebar-toggle-visible

      # Optionally jump to new mailboxes
      bind index,pager \\CP sidebar-prev-new
      bind index,pager \\CN sidebar-next-new

      # ----------------------------
      # 3) Account jump macros (INBOX)
      # ----------------------------
      # Numeric: always unique (canonical)
      ${lib.concatStringsSep "\n" (map (p:
        let md = maildirOf p.name;
        in ''macro index G${p.idx}i "<change-folder>=${md}/INBOX<enter>" "Go: ${p.name} INBOX"''
      ) numbered)}

      # Letter helpers (may collide; convenience only)
      ${lib.concatStringsSep "\n" (map (n:
        let k  = lib.toLower (firstChar n);
            md = maildirOf n;
        in ''macro index G${k}i "<change-folder>=${md}/INBOX<enter>" "Go: ${n} INBOX (letter helper)"''
      ) accNames)}

      # ----------------------------
      # 4) Bulk ops & folder mgmt
      # ----------------------------
      # Tag first with 't' / 'T' then:
      macro index M  "<tag-prefix><save-message>"     "Move tagged/current"
      macro index C  "<tag-prefix><copy-message>"     "Copy tagged/current"
      macro index d  "<delete-message>"               "Delete current"
      macro index D  "<tag-prefix><delete-message>"   "Delete tagged"

      # Quick folder actions
      macro index cf "<change-folder>?"               "Change folder"
      macro index cs "<save-message>?"                "Save/move to folder"
      macro index cc "<copy-message>?"                "Copy to folder"

      # Mark all new as read (from sample)
      macro index A "<tag-pattern>~N<enter><tag-prefix><clear-flag>N<untag-pattern>.<enter>" "Mark all new as read"

      # Limit/unlimit helpers (useful with threads)
      macro index U "<limit>~N<enter>"                "Limit to unread"
      macro index L "<limit><enter>"                  "Clear limit"

      # ----------------------------
      # 5) Threading controls
      # ----------------------------
      bind index \\Ct collapse-thread
      bind index \\CT collapse-all
      bind index \\Cu next-thread
      bind index \\CU previous-thread

      # ----------------------------
      # 6) URL/Contacts helpers
      # ----------------------------
      # Extract URLs from messages/attachments (requires 'urlscan')
      macro index,pager  \\cb "<pipe-message> urlscan<enter>"  "Extract URLs (message)"
      macro attach,compose \\cb "<pipe-entry> urlscan<enter>"  "Extract URLs (attachment)"

      # Add sender to abook (you already had this)
      macro index A\\s "<pipe-message>abook --add-email<enter>" "Add sender to abook"

      # ----------------------------
      # 7) Mailcap helpers
      # ----------------------------
      bind attach <return> view-mailcap

      # ----------------------------
      # 8) QoL utilities
      # ----------------------------
      macro index R "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"
      macro index S "<sync-mailbox>" "Sync mailbox now"

      # ----------------------------
      # 9) Attachment save macro (adjust path)
      # ----------------------------
      macro attach s "<save-entry> <bol>${attachmentsDir}<eol>" "Save attachment to ${attachmentsDir}"
    '';

    # Mailcap: inline HTML first; GUI only if DISPLAY exists
    ".mailcap".text = ''
      # Text/html inline (choose one you have installed)
      text/html; w3m  -I %{charset} -T text/html -dump %s; nametemplate=%s.html; copiousoutput;
      text/html; lynx -assume_charset=%{charset} -display_charset=utf-8 -dump %s; nametemplate=%s.html; copiousoutput;

      # GUI fallback
      text/html; xdg-open %s; test=test -n "$DISPLAY"

      image/*;         feh %s &;      test=test -n "$DISPLAY"
      application/pdf; zathura %s &;  test=test -n "$DISPLAY"
    '';
  };
}
