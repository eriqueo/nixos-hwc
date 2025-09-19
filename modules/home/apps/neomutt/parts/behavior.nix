# modules/home/apps/neomutt/parts/behavior.nix
# Clean, ASCII-only, leader-based key scheme ("," and ";")
{ lib, pkgs, config, ... }:

let
  accounts   = config.features.mail.accounts or {};
  accNames   = lib.attrNames accounts;

  # account -> maildir name
  maildirOf  = n: (accounts.${n}.maildirName or n);

  # 1-based enumeration for stable number shortcuts
  numbered   = lib.imap1 (i: n: { name = n; idx = toString i; }) accNames;

  # first character of a string (for letter helpers)
  firstChar  = s: builtins.substring 0 1 s;

  # attachment save location used by macro ,sa
  attachmentsDir = "~/Mail/attachments/";
in
{
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text = ''
      ############################################
      # NAVIGATION (vim-like)
      ############################################
      bind index g first-entry
      bind index G last-entry
      bind pager g top
      bind pager G bottom

      bind index j next-entry
      bind index k previous-entry
      bind pager j next-line
      bind pager k previous-line

      bind attach,index,pager J next-page
      bind attach,index,pager K previous-page

      ############################################
      # LEADERS (reserved, no-ops)
      ############################################
      bind index "," noop
      bind pager "," noop
      bind index ";" noop
      bind pager ";" noop

      ############################################
      # ,g…  GO / ACCOUNT JUMPS
      ############################################
${lib.concatStringsSep "\n" (map (p:
  let md = maildirOf p.name;
  in "      macro index ,g${p.idx} \"<change-folder>=${md}/INBOX<enter>\" \"Go: ${p.name} INBOX\""
) numbered)}

${lib.concatStringsSep "\n" (map (n:
  let k  = firstChar n;
      md = maildirOf n;
  in "      macro index ,g${k} \"<change-folder>=${md}/INBOX<enter>\" \"Go: " + n + " INBOX (letter)\""
) accNames)}

      macro index ,gg "<change-folder>?" "Go: change folder"

      ############################################
      # ,b…  BULK (tag first with t/T)
      ############################################
      macro index ,bt "<tag-message>"                 "Bulk: tag current"
      macro index ,bT "<tag-pattern>.<enter>"         "Bulk: tag all"
      macro index ,bm "<tag-prefix><save-message>"    "Bulk: move tagged/current"
      macro index ,bc "<tag-prefix><copy-message>"    "Bulk: copy tagged/current"
      macro index ,bd "<tag-prefix><delete-message>"  "Bulk: delete tagged"

      ############################################
      # ,f…  FOLDER ops
      ############################################
      macro index ,fs "<save-message>?"               "Folder: save/move to"
      macro index ,fc "<copy-message>?"               "Folder: copy to"
      macro index ,f+ "<create-mailbox>?"             "Folder: create mailbox"

      ############################################
      # ,t…  THREAD ops
      ############################################
      bind  index zt collapse-thread
      bind  index zT collapse-all
      bind  index zn next-thread
      bind  index zN previous-thread

      macro index ,te "<collapse-thread>"             "Thread: toggle collapse"
      macro index ,tE "<collapse-all>"                "Thread: collapse all"
      macro index ,tn "<next-thread>"                 "Thread: next thread"
      macro index ,tN "<previous-thread>"             "Thread: prev thread"

      ############################################
      # ,s…  SEARCH / SORT / LIMIT
      ############################################
      macro index ,sn "<limit>~N<enter>"              "Limit: new"
      macro index ,su "<limit>~U<enter>"              "Limit: unread"
      macro index ,sa "<limit><enter>"                "Limit: clear"
      macro index ,sR "<enter-command>set sort=reverse-threads<enter><enter-command>set sort_aux=last-date-received<enter><redraw-screen>" "Sort: threaded"
      macro index ,sd "<enter-command>set sort=reverse-date<enter><redraw-screen>" "Sort: reverse date"
      macro index ,ss "<enter-command>toggle sort<enter><redraw-screen>" "Sort: toggle primary key"

      ############################################
      # ,a…  ADDRESS / URL / ATTACH
      ############################################
      macro index ,aa "<pipe-message>abook --add-email<enter>" "Abook: add sender"
      macro index ,u  "<pipe-message> urlscan<enter>"          "URL: extract"
      macro attach ,sa "<save-entry> ${attachmentsDir}<enter>" "Save attachment"

      ############################################
      # ;…  SIDEBAR leader (use enter-command)
      ############################################
      # ; + key → sidebar actions
      macro index,pager ";n" "<sidebar-next>"             "Sidebar: next"
      macro index,pager ";p" "<sidebar-prev>"             "Sidebar: prev"
      macro index,pager ";o" "<sidebar-open>"             "Sidebar: open"
      macro index,pager ";N" "<sidebar-next-new>"         "Sidebar: next new"
      macro index,pager ";P" "<sidebar-prev-new>"         "Sidebar: prev new"
      macro index,pager ";t" "<sidebar-toggle-visible>"   "Sidebar: toggle"
      ############################################
      # UTILITIES
      ############################################
      macro index ,A "<tag-pattern>~N<enter><tag-prefix><clear-flag>N<untag-pattern>.<enter>" "Mark all new as read"
      macro index ,R "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"
    '';
  };
}
