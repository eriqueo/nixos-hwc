# aerc behavior.nix - translating neomutt keybindings to aerc
{ lib, pkgs, config, ... }:
let
  accVals = lib.attrValues (config.hwc.home.core.mail.accounts or {});
  
  # Generate account-specific folder navigation shortcuts
  # ",g1" ",g2" etc. for quick INBOX jumping
  accountBindings = lib.concatStringsSep "\n" (lib.imap0 (i: acc: 
    let 
      n = toString (i + 1);
      maildirName = acc.maildirName or acc.name or "inbox";
    in ''
      macro${n} = ":cf ${maildirName}<Enter>"
    '') accVals);
    
in
{
  files = profileBase: {
    ".config/aerc/binds.conf".text = ''
      # ############################################
      # UNIVERSAL KEYBINDING SYSTEM - AERC
      # Leader = ',' ; lowercase after leader
      # Translated from neomutt keybindings
      # ############################################
      
      # Global bindings (apply everywhere unless overridden)
      [global]
      # Reserve leader key
      "," = :noop<Enter>
      
      ############################################
      # MESSAGE LIST CONTEXT (like neomutt index)
      ############################################
      [messages]
      
      # ===== CORE NAVIGATION (vim-like) =====
      g = :select 0<Enter>
      G = :select -1<Enter>
      
      j = :next<Enter>
      k = :prev<Enter>
      
      # Page navigation
      <C-f> = :next 100%<Enter>
      <C-b> = :prev 100%<Enter>
      
      # ===== LEADER + G - GO/NAVIGATION =====
      ",gh" = ":cf INBOX<Enter>"
      ",gs" = ":cf Sent<Enter>"  
      ",gd" = ":cf Drafts<Enter>"
      ",gt" = ":cf Trash<Enter>"
      ",ga" = ":cf Archive<Enter>"
      ",gg" = ":cf<space>"
      
      # Account-specific INBOX shortcuts (,g1, ,g2, etc.)
      ${accountBindings}
      
      # ===== LEADER + F - FIND/FILTER =====
      ",fa" = ":clear<Enter>"
      ",fn" = ":filter<space>unread<Enter>" 
      ",fu" = ":filter<space>unread<Enter>"
      ",ft" = ":filter<space>flagged<Enter>"
      ",ff" = ":filter<space>flagged<Enter>"
      ",fc" = ":clear<Enter>"
      ",fs" = ":search<space>"
      
      # ===== LEADER + S - SORT =====
      ",sn" = ":sort from<Enter>"
      ",ss" = ":sort size<Enter>" 
      ",sm" = ":sort date<Enter>"
      ",st" = ":sort thread<Enter>"
      ",sr" = ":sort -r date<Enter>"
      ",se" = ":sort subject<Enter>"
      
      # ===== LEADER + T - THREAD OPERATIONS =====
      ",th" = ":fold<Enter>"
      ",ta" = ":fold -a<Enter>"
      ",tn" = ":next-folder<Enter>"
      ",tp" = ":prev-folder<Enter>"
      
      # ===== SWEEP TAGGING (J/K like Yazi) =====
      J = ":mark -t<Enter>:next<Enter>"
      K = ":mark -t<Enter>:prev<Enter>"
      
      # Tag operations
      ",a" = ":mark -a<Enter>"
      ",u" = ":unmark -a<Enter>"
      
      # ===== LEADER + Y/X - COPY/MOVE =====
      ",y" = ":copy<space>"
      ",x" = ":move<space>"
      
      # Quick moves
      ",xa" = ":move Archive<Enter>"
      ",xs" = ":move Sent<Enter>"
      
      # ===== WINDOW/VIEW =====
      ",wh" = ":help<Enter>"
      ",ws" = ":toggle-sidebar<Enter>"
      
      # ===== QUICK SINGLE KEYS =====
      i = ":compose<Enter>"
      o = ":view<Enter>"
      <Enter> = ":view<Enter>"
      r = ":reply<Enter>"
      R = ":reply -a<Enter>"
      f = ":forward<Enter>"
      "/" = ":search<space>"
      n = ":next-result<Enter>"
      N = ":prev-result<Enter>"
      
      # Delete operations
      d = ":move Trash<Enter>"
      D = ":delete<Enter>"
      
      # Archive
      a = ":move Archive<Enter>"
      A = ":archive flat<Enter>"
      
      # ===== UTILITIES =====
      ",us" = ":pipe urlscan<Enter>"
      ",aa" = ":pipe abook --add-email<Enter>"
      ",mr" = ":mark -a<Enter>:mark -t unread<Enter>:unmark -a<Enter>"
      ",rr" = ":source ~/.config/aerc/aerc.conf<Enter>"
      
      # Terminal and external commands
      "!" = ":term<space>"
      "$" = ":term<space>"
      "|" = ":pipe<space>"
      
      ############################################
      # MESSAGE VIEWER CONTEXT (like neomutt pager)
      ############################################
      [view]
      
      # Navigation in viewer
      j = ":next<Enter>"
      k = ":prev<Enter>"
      g = ":select 0<Enter>"
      G = ":select -1<Enter>"
      
      # Page navigation within message
      <C-f> = ":next-part<Enter>"
      <C-b> = ":prev-part<Enter>
      J = ":next<Enter>"
      K = ":prev<Enter>"
      
      # Close viewer
      q = ":close<Enter>"
      
      # Actions from viewer
      r = ":reply<Enter>"
      R = ":reply -a<Enter>"
      f = ":forward<Enter>"
      
      # Delete from viewer
      d = ":move Trash<Enter>"
      D = ":delete<Enter>"
      
      # Archive from viewer  
      a = ":move Archive<Enter>"
      A = ":archive flat<Enter>"
      
      # Save and pipe
      s = ":save<space>"
      "|" = ":pipe<space>"
      
      # Headers and parts
      H = ":toggle-headers<Enter>"
      <C-k> = ":prev-part<Enter>"
      <C-j> = ":next-part<Enter>"
      
      # URL handling
      ",us" = ":open-link<space>"
      
      ############################################
      # COMPOSE CONTEXT
      ############################################
      [compose]
      
      # Navigation between fields
      <C-k> = ":prev-field<Enter>"
      <C-j> = ":next-field<Enter>"
      <Tab> = ":next-field<Enter>"
      
      # Header operations
      ",ha" = ":header<space>"
      
      # Attachments
      a = ":attach<space>"
      ",sa" = ":attach<space>"
      d = ":detach<space>"
      
      # Send operations
      y = ":send<Enter>"
      q = ":abort<Enter>"
      
      # Postpone (like neomutt's postpone)
      p = ":postpone<Enter>"
      
      ############################################
      # COMPOSE EDITOR CONTEXT
      ############################################
      [compose::editor]
      
      # Don't inherit global bindings in editor
      $noinherit = true
      $ex = <C-x>
      
      # Field navigation from editor
      <C-k> = ":prev-field<Enter>"
      <C-j> = ":next-field<Enter>"
      
      ############################################
      # COMPOSE REVIEW CONTEXT  
      ############################################
      [compose::review]
      
      # Review actions
      y = ":send<Enter>"
      e = ":edit<Enter>"
      a = ":attach<space>"
      d = ":detach<space>"
      q = ":abort<Enter>"
      p = ":postpone<Enter>"
      
      ############################################
      # TERMINAL CONTEXT
      ############################################
      [terminal]
      
      # Terminal navigation
      <C-p> = ":prev-tab<Enter>"
      <C-n> = ":next-tab<Enter>"
      q = ":close<Enter>"
      
      ############################################
      # FOLDER/SIDEBAR CONTEXT  
      ############################################
      # Note: aerc doesn't have a dedicated folder context like neomutt
      # Folder navigation is handled in the messages context
      
      ############################################
      # ACCOUNT-SPECIFIC OVERRIDES
      ############################################
      # Example of per-account bindings (uncomment and modify as needed):
      # [messages:account=Work]
      # S = ":move Spam<Enter>"
      # 
      # [messages:account=Personal] 
      # A = ":archive<Enter>"
    '';
  };
}
