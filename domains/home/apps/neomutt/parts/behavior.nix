# =============================================================================
# NEOMUTT CONFIGURATION 
# =============================================================================

# behavior.nix (updated with universal keybindings)
{ lib, pkgs, config, ... }:
let
  accounts = config.hwc.home.core.mail.accounts or {};
  accNames = lib.attrNames accounts;
  maildirOf = n: (accounts.${n}.maildirName or n);
  numbered = lib.imap1 (i: n: { name = n; idx = toString i; }) accNames;
  firstChar = s: builtins.substring 0 1 s;
  attachmentsDir = "~/Mail/attachments/";
in
{
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text = ''
      ############################################
      # UNIVERSAL KEYBINDING SYSTEM - NEOMUTT
      # Space-leader based with consistent patterns
      ############################################
      
      # Set leader key (space is hard in mutt, use comma)
      bind index "," noop
      bind pager "," noop
      
      ############################################
      # VIM-STYLE NAVIGATION (consistent with yazi/nvim)
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
      # ,g - GO/NAVIGATION (consistent with yazi)
      ############################################
${lib.concatStringsSep "\n" (map (p:
  let md = maildirOf p.name;
  in "      macro index ,g${p.idx} \"<change-folder>=${md}/INBOX<enter>\" \"Go: ${p.name} INBOX\""
) numbered)}
      
      macro index ,gh "<change-folder>=INBOX<enter>"           "Go: home (main inbox)"
      macro index ,gs "<change-folder>=Sent<enter>"            "Go: sent"
      macro index ,gd "<change-folder>=Drafts<enter>"          "Go: drafts"
      macro index ,gt "<change-folder>=Trash<enter>"           "Go: trash"
      macro index ,ga "<change-folder>=Archive<enter>"         "Go: archive"
      macro index ,gg "<change-folder>?"                       "Go: choose folder"
      
      ############################################
      # ,f - FIND/SEARCH (consistent with yazi)
      ############################################
      macro index ,ff "<limit>all<enter>"                      "Find: show all"
      macro index ,fn "<limit>~N<enter>"                       "Find: new mail"
      macro index ,fu "<limit>~U<enter>"                       "Find: unread"
      macro index ,ft "<limit>~T<enter>"                       "Find: tagged"
      macro index ,ff "<limit>~F<enter>"                       "Find: flagged"
      macro index ,fc "<limit>~A<enter>"                       "Find: clear filter"
      macro index ,fs "<search>~"                              "Find: search pattern"
      
      ############################################
      # ,s - SORT/SESSION (consistent with yazi)
      ############################################
      macro index ,sn "<sort-mailbox>from<enter>"              "Sort: by name/from"
      macro index ,ss "<sort-mailbox>size<enter>"              "Sort: by size"
      macro index ,sm "<sort-mailbox>date<enter>"              "Sort: by date"
      macro index ,st "<sort-mailbox>threads<enter>"           "Sort: by threads"
      macro index ,sr "<sort-mailbox>reverse-date<enter>"      "Sort: reverse date"
      macro index ,se "<sort-mailbox>subject<enter>"           "Sort: by subject"
      
      ############################################
      # ,t - TOGGLE/THREAD (consistent with yazi)
      ############################################
      macro index ,th "<collapse-thread>"                      "Toggle: thread collapse"
      macro index ,ta "<collapse-all>"                         "Toggle: all threads"
      macro index ,tn "<next-thread><collapse-thread>"         "Thread: next"
      macro index ,tp "<previous-thread><collapse-thread>"     "Thread: previous"
      
      ############################################
      # ,y - YANK/COPY (new, consistent)
      ############################################
      macro index ,yy "<copy-message>?"                        "Yank: copy message"
      macro index ,yp "<pipe-message>echo -n | xclip -selection clipboard" "Yank: copy path"
      
      ############################################
      # ,d - DELETE/REMOVE (consistent with yazi)
      ############################################
      macro index ,dd "<delete-message>"                       "Delete: message"
      macro index ,dt "<delete-thread>"                        "Delete: thread"
      macro index ,dp "<purge-deleted>"                        "Delete: purge deleted"
      
      ############################################
      # ,w - WINDOW/VIEW (new, consistent)
      ############################################
      macro index ,wh "<toggle-help>"                          "Window: toggle help"
      macro index ,ws "<enter-command>toggle sidebar_visible<enter>" "Window: toggle sidebar"
      
      ############################################
      # ,b - BULK operations (enhanced, consistent)
      ############################################
      macro index ,bt "<tag-message>"                          "Bulk: tag current"
      macro index ,ba "<tag-pattern>~A<enter>"                 "Bulk: tag all"
      macro index ,bn "<untag-pattern>~A<enter>"               "Bulk: untag all"
      macro index ,bm "<tag-prefix><save-message>"             "Bulk: move tagged"
      macro index ,bc "<tag-prefix><copy-message>"             "Bulk: copy tagged"
      macro index ,bd "<tag-prefix><delete-message>"           "Bulk: delete tagged"
      macro index ,br "<tag-prefix><flag-message>"             "Bulk: flag tagged"
      
      ############################################
      # QUICK SINGLE KEYS (consistent with vim/yazi)
      ############################################
      bind index i mail                                         # compose (like 'insert')
      bind index o display-message                              # open message
      bind index r reply                                        # reply
      bind index R group-reply                                  # reply all
      bind index f forward-message                              # forward
      bind index / search                                       # search
      bind index n search-next                                  # next search
      bind index N search-opposite                              # prev search
      
      # Archive and address book (from original)
      macro index ,aa "<pipe-message>abook --add-email<enter>" "Address: add sender"
      macro index ,u  "<pipe-message> urlscan<enter>"          "URL: extract"
      macro attach ,sa "<save-entry> ${attachmentsDir}<enter>" "Save: attachment"
      
      # Utilities
      macro index ,A "<tag-pattern>~N<enter><tag-prefix><clear-flag>N<untag-pattern>.<enter>" "Mark all as read"
      macro index ,R "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"
    '';
  };
}
