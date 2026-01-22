{ config, lib, pkgs, osConfig ? {}, ... }:

let
  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  # Safe access to age secrets (only available on NixOS hosts)
  gmailPersonalSecretPath = if (osCfg ? age) && (osCfg.age.secrets ? gmail-personal-password)
                            then osCfg.age.secrets.gmail-personal-password.path
                            else "/dev/null";  # Fallback path on non-NixOS (user must override)

  gmailBusinessSecretPath = if (osCfg ? age) && (osCfg.age.secrets ? gmail-business-password)
                            then osCfg.age.secrets.gmail-business-password.path
                            else "/dev/null";  # Fallback path on non-NixOS (user must override)
in
#==========================================================================
# OPTIONS
#==========================================================================
# Sets values only (no options). Lives under the domain so it's uniform with others.
{
  imports = [ ./options.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  hwc.home.mail.accounts = {
    proton-unified = {
        name = "proton-unified";
        type = "proton-bridge";
        realName = "Eric";
        address = "eric@iheartwoodcraft.com";  # Primary address for sending
        login = "eriqueo";  # Bridge username (NOT email address)
        password = { mode = "pass"; pass = "email/proton/bridge"; };
        maildirName = "100_proton";  # Single maildir for all Proton mail
        mailboxMapping = {
          "Folders/hwc_inbox"      = "hwc-inbox";
          "Folders/personal_inbox" = "personal-inbox";
          "Sent"                   = "sent";
          "Drafts"                 = "drafts";
          "Archive"                = "archive";
        };
        sync.wildcards = [];  # Explicit folders only - no wildcards
        send.msmtpAccount = "proton-hwc";  # Default to work identity
        # Add second identity for personal address
        extraMsmtp = ''
          account proton-personal
          host 127.0.0.1
          port 1025
          tls off
          tls_starttls off
          auth plain
          from eriqueo@proton.me
          user eriqueo
          passwordeval "pass show email/proton/bridge"
        '';
        primary = true;
      };

    gmail-personal = {
          name = "gmail-personal";
          type = "gmail";
          realName = "Eric O'Keefe";
          address = "eriqueokeefe@gmail.com";
          login = "eriqueokeefe@gmail.com";
          password = {
            mode = "agenix";
            agenix = gmailPersonalSecretPath;
          };
          maildirName = "210_gmail-personal";
          mailboxMapping = {
            "INBOX"               = "inbox";
            "[Gmail]/Sent Mail"   = "sent";
            "[Gmail]/Drafts"      = "drafts";
            "[Gmail]/Starred"     = "starred";
          };
          send.msmtpAccount = "gmail-personal";
        };

        gmail-business = {
          name = "gmail-business";
          type = "gmail";
          realName = "Eric O'Keefe";
          address = "heartwoodcraftmt@gmail.com";
          login = "heartwoodcraftmt@gmail.com";
          password = {
            mode = "agenix";
            agenix = gmailBusinessSecretPath;
          };
          maildirName = "110_gmail-business";
          mailboxMapping = {
            "INBOX"               = "inbox";
            "[Gmail]/Sent Mail"   = "sent";
            "[Gmail]/Drafts"      = "drafts";
            "[Gmail]/Starred"     = "starred";
          };
          send.msmtpAccount = "gmail-business";
        };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
