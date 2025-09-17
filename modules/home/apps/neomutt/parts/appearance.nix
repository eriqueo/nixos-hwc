# NeoMutt • Appearance part
# Theming and visual configuration.
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt;
  materials = cfg.materials or {};
  
  # Import theme palette
  palette = import ../../../theme/palettes/deep-nord.nix {};
  
  # Generate account configurations for ProtonMail Bridge
  accountConfigs = lib.concatStringsSep "\n\n" (lib.mapAttrsToList (name: account: ''
    # ${account.name} account configuration
    folder-hook ${account.email} 'source ~/.config/neomutt/accounts/${account.name}'
  '') cfg.accounts);

  # Generate individual account config files
  accountFiles = lib.listToAttrs (lib.mapAttrsToList (name: account: 
    let
      passwordCommand = 
        if account.useAgenixPassword
        then "cat /run/agenix/proton-bridge-password"
        else if account ? bridgePasswordCommand && account.bridgePasswordCommand != null
        then account.bridgePasswordCommand
        else "echo 'ERROR: Password not configured'";
      
      # Determine if this is a Gmail account
      isGmail = lib.hasSuffix "@gmail.com" account.email;
      
      # Server settings based on provider
      imapServer = if isGmail then "imap.gmail.com:993" else "127.0.0.1:1143";
      smtpServer = if isGmail then "smtp.gmail.com:587" else "127.0.0.1:1025";
      sslSettings = if isGmail then ''
        set ssl_starttls = yes
        set ssl_force_tls = yes
      '' else ''
        set ssl_starttls = no
        set ssl_force_tls = no
      '';
    in {
      name = ".config/neomutt/accounts/${account.name}";
      value.text = ''
        # Account: ${account.name}
        set from = "${account.email}"
        set realname = "${account.realName}"
        
        # Email server settings
        set imap_user = "${account.bridgeUsername}"
        set imap_pass = "`${passwordCommand}`"
        set smtp_user = "${account.bridgeUsername}"
        set smtp_pass = "`${passwordCommand}`"
        
        # Server settings
        set folder = "imap://${imapServer}/"
        set spoolfile = "+INBOX"
        set postponed = "+[Gmail]/Drafts"
        set record = "+[Gmail]/Sent Mail"
        set trash = "+[Gmail]/Trash"
        
        set smtp_url = "smtp://${account.bridgeUsername}@${smtpServer}/"
        ${sslSettings}
      '';
    }
  ) cfg.accounts);
in
{
  files = profileBase: {
    # Main NeoMutt configuration
    ".neomuttrc".text = ''
      # Basic settings
      set mailcap_path = ~/.mailcap
      set mime_type_query_command = "file --mime-type -b %s"
      
      # Display settings
      set sort = reverse-date
      set index_format = "%4C %Z %{%b %d} %-15.15L (%?l?%4l&%4c?) %s"
      set pager_index_lines = 10
      set pager_context = 3
      set menu_scroll = yes
      
      # Colors (deep-nord theme)
      color normal     "#${palette.fg}"         "#${palette.bg}"
      color attachment "#${palette.warn}"       "#${palette.bg}"
      color hdrdefault "#${palette.accent2}"    "#${palette.bg}"
      color indicator  "#${palette.bg}"         "#${palette.accent}"
      color markers    "#${palette.crit}"       "#${palette.bg}"
      color quoted     "#${palette.good}"       "#${palette.bg}"
      color signature  "#${palette.fgDim}"      "#${palette.bg}"
      color status     "#${palette.fg}"         "#${palette.surface1}"
      color tilde      "#${palette.info}"       "#${palette.bg}"
      color tree       "#${palette.accent}"     "#${palette.bg}"
      
      # Account configurations
      ${accountConfigs}
      
      # Default to first account if configured
      ${lib.optionalString (cfg.accounts != {}) 
        "source ~/.config/neomutt/accounts/${(lib.head (lib.attrNames cfg.accounts))}"}
    '';
    
    ".mailcap".text = ''
      text/html; firefox %s &; test=test -n "$DISPLAY"; needsterminal;
      text/html; lynx -assume_charset=%{charset} -display_charset=utf-8 -dump %s; nametemplate=%s.html; copiousoutput;
      image/*; feh %s &; test=test -n "$DISPLAY"
      application/pdf; zathura %s &; test=test -n "$DISPLAY"
    '';
  } // accountFiles;
}
