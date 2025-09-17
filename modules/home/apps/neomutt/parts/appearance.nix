# NeoMutt • Appearance part
# Theming and visual configuration.
{ lib, pkgs, config, ... }:

{
  files = profileBase: {
    # Basic NeoMutt configuration
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
    '';
    
    ".mailcap".text = ''
      text/html; firefox %s &; test=test -n "$DISPLAY"; needsterminal;
      text/html; lynx -assume_charset=%{charset} -display_charset=utf-8 -dump %s; nametemplate=%s.html; copiousoutput;
      image/*; feh %s &; test=test -n "$DISPLAY"
      application/pdf; zathura %s &; test=test -n "$DISPLAY"
    '';
  };
}