# NeoMutt • Appearance part
# Theming and visual configuration.
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt;
  materials = cfg.materials or {};
  
  # Import theme adapter for NeoMutt colors
  themeColors = import ../../../theme/adapters/neomutt.nix { inherit config lib; };
  
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
        then "cat /run/agenix/proton-bridge-password | tr -d '\\n'"
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
        ${if isGmail then ''
          set postponed = "+[Gmail]/Drafts"
          set record = "+[Gmail]/Sent Mail"
          set trash = "+[Gmail]/Trash"
        '' else ''
          set postponed = "+Drafts"
          set record = "+Sent"
          set trash = "+Trash"
        ''}
        
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
      
      # Colors from theme adapter (deep-nord palette)
      color normal     ${themeColors.colors.normal.fg}     ${themeColors.colors.normal.bg}
      color attachment ${themeColors.colors.attachment.fg} ${themeColors.colors.attachment.bg}
      color hdrdefault ${themeColors.colors.hdrdefault.fg} ${themeColors.colors.hdrdefault.bg}
      color indicator  ${themeColors.colors.indicator.fg}  ${themeColors.colors.indicator.bg}
      color markers    ${themeColors.colors.markers.fg}    ${themeColors.colors.markers.bg}
      color quoted     ${themeColors.colors.quoted.fg}     ${themeColors.colors.quoted.bg}
      color signature  ${themeColors.colors.signature.fg}  ${themeColors.colors.signature.bg}
      color status     ${themeColors.colors.status.fg}     ${themeColors.colors.status.bg}
      color tilde      ${themeColors.colors.tilde.fg}      ${themeColors.colors.tilde.bg}
      color tree       ${themeColors.colors.tree.fg}       ${themeColors.colors.tree.bg}
      
      # Mailbox definitions
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: account: 
        let
          # Determine if this is a Gmail account
          isGmail = lib.hasSuffix "@gmail.com" account.email;
          imapServer = if isGmail then "imap.gmail.com:993" else "127.0.0.1:1143";
        in ''
          # ${account.name} mailboxes
          mailboxes "imap://${imapServer}/INBOX"
          ${if isGmail then ''
            mailboxes "imap://${imapServer}/[Gmail]/Sent Mail"
            mailboxes "imap://${imapServer}/[Gmail]/Drafts" 
            mailboxes "imap://${imapServer}/[Gmail]/Trash"
            mailboxes "imap://${imapServer}/[Gmail]/All Mail"
          '' else ''
            mailboxes "imap://${imapServer}/Sent"
            mailboxes "imap://${imapServer}/Drafts"
            mailboxes "imap://${imapServer}/Trash"
          ''}
        ''
      ) cfg.accounts)}
      
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
