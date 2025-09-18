# NeoMutt • Behavior/macros (keyfeel like MW)
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt or { };
  # derive account names once for jump macros
  accNames = lib.attrNames (cfg.accounts or { });
  # helper to make a safe token for macros
  accTok = n: n;
in {
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text = ''
      # Do NOT steal 'g' (reply-all). Use 'G' prefix for jumps.
      # Generate simple jump macros per account to INBOX if account names are known.
      ${lib.concatStringsSep "\n"
        (map (n: "macro index G${accTok n:0:1}i \"<change-folder>=${n}/INBOX<enter>\" \"Go: ${n} Inbox\"")
          accNames)
      }

      # Bulk ops (tag first with 't' or 'T')
      macro index M  "<tag-prefix><save-message>"           "Move tagged/current"
      macro index C  "<tag-prefix><copy-message>"           "Copy tagged/current"
      macro index DD "<tag-prefix><delete-message>"         "Delete tagged"
      macro index A "<pipe-message>abook --add-email<enter>" "Add sender to abook"

      # sidebar binds
      bind index,pager \CP sidebar-prev
      bind index,pager \CN sidebar-next
      bind index,pager \CO sidebar-open
      bind index,pager \CB sidebar-page-up
      bind index,pager \CF sidebar-page-down
      
      # Quick reload of whole config
      macro index R "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"
    '';
    
    # Mailcap audit: inline HTML first, GUI fallback only if DISPLAY
    ".mailcap".text = ''
      # Inline HTML first
      text/html; w3m  -I %{charset} -T text/html -dump %s; nametemplate=%s.html; copiousoutput;
      text/html; lynx -assume_charset=%{charset} -display_charset=utf-8 -dump %s; nametemplate=%s.html; copiousoutput;

      # GUI fallback
      text/html; xdg-open %s; test=test -n "$DISPLAY"

      image/*;           feh %s &;      test=test -n "$DISPLAY"
      application/pdf;   zathura %s &;  test=test -n "$DISPLAY"
    '';
  };
}
