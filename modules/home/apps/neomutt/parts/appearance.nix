# NeoMutt • Appearance part
# Theming and visual configuration.
{ lib, pkgs, config, ... }:

let
  cfg = config.features.neomutt;
  materials = config.hwc.security.materials;
  
  # Generate account configurations for ProtonMail Bridge
  accountConfigs = lib.concatStringsSep "\n\n" (lib.mapAttrsToList (name: account: ''
    # ${account.name} account configuration
    folder-hook ${account.email} 'source ~/.config/neomutt/accounts/${account.name}'
  '') cfg.accounts);

  # Generate individual account config files
  accountFiles = lib.listToAttrs (lib.mapAttrsToList (name: account: 
    let
      passwordCommand = if account.useAgenixPassword
        then "cat ${materials.protonBridgePasswordFile}"
        else account.bridgePasswordCommand;
    in {
      name = ".config/neomutt/accounts/${account.name}";
      value.text = ''
        # Account: ${account.name}
        set from = "${account.email}"
        set realname = "${account.realName}"
        
        # ProtonMail Bridge settings
        set imap_user = "${account.bridgeUsername}"
        set imap_pass = "`${passwordCommand}`"
        set smtp_user = "${account.bridgeUsername}"
        set smtp_pass = "`${passwordCommand}`"
        
        # Server settings for ProtonMail Bridge
        set folder = "imap://127.0.0.1:1143/"
        set spoolfile = "+INBOX"
        set postponed = "+Drafts"
        set record = "+Sent"
        set trash = "+Trash"
        
        set smtp_url = "smtp://${account.bridgeUsername}@127.0.0.1:1025/"
        set ssl_starttls = no
        set ssl_force_tls = no
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
      
      # Colors (basic theme)
      color normal     white         default
      color attachment yellow        default
      color hdrdefault cyan          default
      color indicator  black         yellow
      color markers    red           default
      color quoted     green         default
      color signature  cyan          default
      color status     brightgreen   blue
      color tilde      blue          default
      color tree       red           default
      
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