# NeoMutt • Behavior/macros (MW-ish keyfeel, no overlap with appearance)
{ lib, pkgs, config, ... }:

let
  cfg       = config.features.neomutt or { };
  accounts  = cfg.accounts or {};
  accNames  = lib.attrNames accounts;

  # Derive maildir for an account (prefer maildirName, else name)
  maildirOf = n: (accounts.${n}.maildirName or n);

  # 1-based enumeration producing a list of { name = "..."; idx = "1" | "2" | ... }
  numbered  = lib.imap1 (i: n: { name = n; idx = toString i; }) accNames;

  # First-letter helper for optional letter macros
  firstChar = s: builtins.substring 0 1 s;

in {
  files = profileBase: {
    ".config/neomutt/behavior.muttrc".text = ''
      # Do NOT alias plain 'g' (avoid bind warning about 'gi' aliasing 'g')
      bind index g noop

      # ----------------------------
      # Account jump macros
      # ----------------------------
      # Numeric: always unique (canonical)
      ${lib.concatStringsSep "\n" (map (p:
        let md = maildirOf p.name;
        in ''macro index G${p.idx}i "<change-folder>=${md}/INBOX<enter>" "Go: ${p.name} INBOX"''
      ) numbered)}

      # Letter helpers (may collide; provided as convenience only)
      ${lib.concatStringsSep "\n" (map (n:
        let k  = lib.toLower (firstChar n);
            md = maildirOf n;
        in ''macro index G${k}i "<change-folder>=${md}/INBOX<enter>" "Go: ${n} INBOX (letter helper)"''
      ) accNames)}

      # ----------------------------
      # Bulk ops (tag with 't'/'T' first)
      # ----------------------------
      macro index M  "<tag-prefix><save-message>"    "Move tagged/current"
      macro index C  "<tag-prefix><copy-message>"    "Copy tagged/current"
      macro index DD "<tag-prefix><delete-message>"  "Delete tagged"

      # Add sender to abook
      macro index A "<pipe-message>abook --add-email<enter>" "Add sender to abook"

      # Sidebar (well-supported set) – double backslash to survive Nix string escapes
      bind index,pager \\Cp sidebar-prev
      bind index,pager \\Cn sidebar-next
      bind index,pager \\Co sidebar-open
      bind index,pager \\CP sidebar-prev-new
      bind index,pager \\CN sidebar-next-new

      # Quick reload
      macro index R "<enter-command>source ~/.config/neomutt/neomuttrc<enter>" "Reload config"
    '';

    # Mailcap: inline HTML first; GUI fallback only when DISPLAY
    ".mailcap".text = ''
      # Inline HTML (pick the one you actually have installed)
      text/html; w3m  -I %{charset} -T text/html -dump %s; nametemplate=%s.html; copiousoutput;
      text/html; lynx -assume_charset=%{charset} -display_charset=utf-8 -dump %s; nametemplate=%s.html; copiousoutput;

      # GUI fallback
      text/html; xdg-open %s; test=test -n "$DISPLAY"

      image/*;         feh %s &;      test=test -n "$DISPLAY"
      application/pdf; zathura %s &;  test=test -n "$DISPLAY"
    '';
  };
}
