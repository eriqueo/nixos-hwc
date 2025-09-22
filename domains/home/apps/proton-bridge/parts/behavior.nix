# ProtonMail Bridge • Behavior part
# Functional configuration and behavior settings.
{ lib, pkgs, config, ... }:

{
  files = profileBase: {
    # Bridge configuration directory setup
    # Note: Bridge creates its own config files, but we can pre-create the directory
    ".config/protonmail/bridge/.keep".text = "";
    
    # Helper script for initial setup
    ".local/bin/proton-bridge-setup".source = pkgs.writeShellScript "proton-bridge-setup" ''
      #!/bin/bash
      echo "ProtonMail Bridge Setup Helper"
      echo "=============================="
      echo "1. Run: protonmail-bridge --cli"
      echo "2. Login with your ProtonMail credentials"
      echo "3. Note the Bridge password generated for email clients"
      echo ""
      echo "Email Client Settings:"
      echo "IMAP Server: 127.0.0.1:1143"
      echo "SMTP Server: 127.0.0.1:1025"
      echo "Username: your@protonmail.com"
      echo "Password: [Bridge generated password]"
    '';
  };
}