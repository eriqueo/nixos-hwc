# behavior.nix
{ lib, pkgs, config, ... }:
let
  # ... your let bindings ...
in
{
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text = ''
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
# Pager: page down/up
bind pager  J next-page
bind pager  K previous-page

# Attachment list: page down/up
bind attach J next-page
bind attach K previous-page

############################################
# ,g — GO / NAVIGATION
############################################
# Per-account quick INBOX jump: ",g1" ",g2" ...
# (Your Nix code should emit quoted keys)
# example emitted lines:
# macro index ",g1" "<change-folder>=ACCOUNT1/INBOX<enter>" "Go: ACCOUNT1 INBOX"
# macro index ",g2" "<change-folder>=ACCOUNT2/INBOX<enter>" "Go: ACCOUNT2 INBOX"

macro index ",gh" "<change-folder>=INBOX<enter>"      "Go: home (INBOX)"
macro index ",gs" "<change-folder>=Sent<enter>"       "Go: Sent"
macro index ",gd" "<change-folder>=Drafts<enter>"     "Go: Drafts"
macro index ",gt" "<change-folder>=Trash<enter>"      "Go: Trash"
macro index ",ga" "<change-folder>=Archive<enter>"    "Go: Archive"
macro index ",gg" "<change-folder>?"                  "Go: choose folder"

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

# Tag all / untag all (lowercase after leader)
macro index ",a" "<tag-pattern>~A<enter>"             "Tag all in view"
macro index ",u" "<tag-prefix><untag-pattern>~A<enter>" "Untag all"

############################################
# ,y / ,x — COPY (LABEL) / MOVE (universal ops)
############################################
# Copy (adds a label on Gmail IMAP)
macro index ",y" "<tag-prefix><copy-message>"         "Copy tagged to mailbox"
# Move (requires 'set move=yes' for save to move)
macro index ",x" "<tag-prefix><save-message>"         "Move tagged to mailbox"

# Quick archive moves (optional shortcuts)
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
bind index i mail                                     # compose (like 'insert')
bind index o display-message                          # open message
bind index r reply                                    # reply
bind index R group-reply                              # reply all
bind index f forward-message                          # forward
bind index / search                                   # search
bind index n search-next                              # next search
bind index N search-opposite                          # prev search

############################################
# UTILITIES (lowercase leader; conflict-free)
############################################
# URL scan moved to ",us" to avoid clash with ",u" (untag all)
macro index ",us" "<pipe-message> urlscan<enter>"     "URL: extract"
macro index ",aa" "<pipe-message>abook --add-email<enter>" "Address: add sender"
macro attach ",sa" "<save-entry> ~/Mail/attachments/<enter>" "Save attachment"

# Mark all visible as read (clear 'new' flag), keep selection clean
macro index ",mr" "<tag-pattern>~A<enter><tag-prefix><clear-flag>N<untag-pattern>~A<enter>" "Mark all visible as read"

# Reload config
macro index ",rr" "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"

############################################
# RECOMMENDED SETTINGS FOR THIS WORKFLOW
############################################
# When saving, move the message instead of copying (used by ",x" and shortcuts)
set move=yes
# Don't nag on append/save prompts
set confirmappend=no
# Show sidebar if compiled with sidebar
# set sidebar_visible=yes
    '';
  };
}
