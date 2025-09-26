# domains/home/apps/neomutt/parts/behavior.nix
{ lib, pkgs, config, ... }:
let
  # Pull shared mail accounts (may be empty during refactors)
  mailAccs  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues mailAccs;
  haveAccs  = accVals != [];

  # Generate ",g1", ",g2", ... macros to jump to each account's INBOX (optional)
  # Uses maildirName so it matches your local Maildir layout.
  inboxMacroLines =
    lib.imap0 (i: a:
      ''macro index ",g${toString (i + 1)}" "<change-folder>=${a.maildirName}/INBOX<enter>" "Go: ${a.name} INBOX"''
    ) accVals;

  inboxMacros = lib.concatStringsSep "\n" inboxMacroLines;
in
{
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text =
      ''
############################################
# UNIVERSAL KEYBINDING SYSTEM - NEOMUTT
# Leader = ',' ; lowercase after leader
############################################

# Reserve leader
bind index "," noop
bind pager ", " noop
bind pager "," noop

############################################
# CORE NAV (vim-like)
############################################
bind index  g first-entry
bind index  G last-entry
bind pager  g top
bind pager  G bottom

bind index  j next-entry
bind index  k previous-entry
bind pager  j next-line
bind pager  k previous-line

# Page up/down in pager/attach (not index, so J/K are free there)
bind pager  J next-page
bind pager  K previous-page
bind attach J next-page
bind attach K previous-page

############################################
# ,g — GO / NAVIGATION
############################################
# Quick jumps
macro index ",gh" "<change-folder>=INBOX<enter>"      "Go: home (INBOX)"
macro index ",gs" "<change-folder>=Sent<enter>"       "Go: Sent"
macro index ",gd" "<change-folder>=Drafts<enter>"     "Go: Drafts"
macro index ",gt" "<change-folder>=Trash<enter>"      "Go: Trash"
macro index ",ga" "<change-folder>=Archive<enter>"    "Go: Archive"
macro index ",gg" "<change-folder>?"                  "Go: choose folder"
''
      + lib.optionalString haveAccs
        ("\n# Per-account INBOX shortcuts (auto-generated)\n" + inboxMacros + "\n")
      + ''
############################################
# ,f — FIND / FILTER (no conflicts)
############################################
macro index ",fa" "<limit>all<enter>"                 "Find: show all"
macro index ",fn" "<limit>~N<enter>"                  "Find: new"
macro index ",fu" "<limit>~U<enter>"                  "Find: unread"
macro index ",ft" "<limit>~T<enter>"                  "Find: tagged"
macro index ",ff" "<limit>~F<enter>"                  "Find: flagged"
macro index ",fc" "<limit>all<enter>"                 "Find: clear filter"
macro index ",fs" "<search>"                          "Find: search pattern"

############################################
# ,s — SORT
############################################
macro index ",sn" "<sort-mailbox>from<enter>"         "Sort: by from/name"
macro index ",ss" "<sort-mailbox>size<enter>"         "Sort: by size"
macro index ",sm" "<sort-mailbox>date<enter>"         "Sort: by date"
macro index ",st" "<sort-mailbox>threads<enter>"      "Sort: by threads"
macro index ",sr" "<sort-mailbox>reverse-date<enter>" "Sort: reverse date"
macro index ",se" "<sort-mailbox>subject<enter>"      "Sort: by subject"

############################################
# ,t — THREAD TOGGLES
############################################
macro index ",th" "<collapse-thread>"                 "Toggle: collapse thread"
macro index ",ta" "<collapse-all>"                    "Toggle: collapse all"
macro index ",tn" "<next-thread><collapse-thread>"    "Thread: next (collapse)"
macro index ",tp" "<previous-thread><collapse-thread>" "Thread: prev (collapse)"

############################################
# SWEEP TAGGING (matches Yazi J/K sweep)
############################################
macro index J "<tag-message><next-undeleted>"         "Tag & move down"
macro index K "<tag-message><previous-undeleted>"     "Tag & move up"
macro index ",a" "<tag-pattern>~A<enter>"             "Tag all in view"
macro index ",u" "<tag-prefix><untag-pattern>~A<enter>" "Untag all"

############################################
# ,y / ,x — COPY / MOVE
############################################
macro index ",y" "<tag-prefix><copy-message>"         "Copy tagged to mailbox"
macro index ",x" "<tag-prefix><save-message>"         "Move tagged to mailbox"
macro index ",xa" "<tag-prefix><save-message>=Archive<enter>" "Move tagged to Archive"
macro index ",xs" "<tag-prefix><save-message>=Sent<enter>"    "Move tagged to Sent"

############################################
# WINDOW / VIEW
############################################
macro index ",wh" "<toggle-help>"                     "Window: toggle help"
macro index ",ws" "<enter-command>toggle sidebar_visible<enter>" "Window: toggle sidebar"

############################################
# QUICK SINGLE KEYS (vim-like)
############################################
bind index i mail
bind index o display-message
bind index r reply
bind index R group-reply
bind index f forward-message
bind index / search
bind index n search-next
bind index N search-opposite

############################################
# UTILITIES
############################################
macro index ",us" "<pipe-message> urlscan<enter>"     "URL: extract"
macro index ",aa" "<pipe-message>abook --add-email<enter>" "Address: add sender"
macro attach ",sa" "<save-entry> ~/Mail/attachments/<enter>" "Save attachment"
macro index ",mr" "<tag-pattern>~A<enter><tag-prefix><clear-flag>N<untag-pattern>~A<enter>" "Mark all visible as read"
macro index ",rr" "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"

############################################
# RECOMMENDED SETTINGS FOR THIS WORKFLOW
############################################
set move=yes
set confirmappend=no
# set sidebar_visible=yes
'';
  };
}
