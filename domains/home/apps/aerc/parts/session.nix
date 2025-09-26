# aerc session.nix - packages and services for aerc
{ lib, pkgs, config, ... }:

{
  # Packages needed for aerc functionality (equivalent to neomutt session)
  packages = with pkgs; [
    aerc           # the email client itself
    msmtp          # send mail (same as neomutt setup)
    isync          # mbsync for offline sync 
    notmuch        # fast search/indexing (aerc has good notmuch integration)
    
    # HTML and text processing (for mailcap and filters)
    w3m            # HTML rendering in terminal
    lynx           # Alternative HTML renderer
    catimg         # Image display in terminal (if supported)
    
    # PDF and document handling
    poppler_utils  # pdftotext for PDF viewing
    
    # URL handling
    urlscan        # URL extraction from emails (used in keybindings)
    
    # Address book
    abook          # address book (same as neomutt)
    
    # Additional useful tools
    file           # file type detection (used in mailcap)
    unzip          # archive handling
    tar            # archive handling
    gzip           # compression handling
    
    # Optional: better terminal tools
    bat            # syntax-highlighted cat (can replace cat in some mailcap entries)
    fd             # better find (for file attachments)
    ripgrep        # better grep (for search operations)
    
    # Colorize filter dependencies (if using built-in colorize)
    # aerc has a built-in colorize filter, but these can enhance it
    
    # Calendar handling
    khal           # calendar integration (optional)
    
    # GPG for encryption (same as neomutt)
    gnupg          # email encryption/signing
  ];

  # Services configuration
  services = {
    # Note: aerc doesn't need specific services like neomutt
    # Sync services would typically be handled separately
  };

  # Environment variables
  env = {
    # aerc will respect these standard variables
    # EDITOR is handled globally in your system config
    
    # Mailcap path (aerc will find this automatically)
    # MAILCAPS = "$HOME/.mailcap";
  };

  # Optional: shell aliases that work well with aerc
  shellAliases = {
    # Quick aerc launch
    mail = "aerc";
    
    # Useful mail-related commands
    mailsync = "mbsync -a";
    mailindex = "notmuch new";
    
    # Quick address book
    contacts = "abook";
    
    # URL extraction (used by keybinding)
    urls = "urlscan";
  };
}
