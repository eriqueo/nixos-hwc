{ config, lib, pkgs, osConfig ? {}, ... }:

let
  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;

  # Safe access to age secrets (only available on NixOS hosts)
  gmailPersonalSecretPath = if isNixOSHost && (osConfig ? age) && (osConfig.age.secrets ? gmail-personal-password)
                            then osConfig.age.secrets.gmail-personal-password.path
                            else "/dev/null";  # Fallback path on non-NixOS (user must override)

  gmailBusinessSecretPath = if isNixOSHost && (osConfig ? age) && (osConfig.age.secrets ? gmail-business-password)
                            then osConfig.age.secrets.gmail-business-password.path
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
    proton = {
        name = "proton";
        type = "proton-bridge";
        realName = "Eric";
        address = "eriqueo@proton.me";
        login = "eric@iheartwoodcraft.com";
        password = { mode = "pass"; pass = "email/proton/bridge"; };
        maildirName = "200_personal";
        mailboxMapping = {
          "personal_inbox" = "inbox";    # Server-side filtered folder
          "Sent"           = "sent";
          "Drafts"         = "drafts";
          "Archive"        = "archive";
        };
        sync.wildcards = [ "Folders/*" "Labels/*" ];
        send.msmtpAccount = "proton";
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


    iheartwoodcraft = {
          name = "iheartwoodcraft";
          type = "proton-bridge";
          realName = "Eric";
          address = "eric@iheartwoodcraft.com";
          login = "eric@iheartwoodcraft.com";
          password = { mode = "pass"; pass = "email/proton/bridge"; };
          maildirName = "100_hwc";
          mailboxMapping = {
            "hwc_inbox" = "inbox";    # Server-side filtered folder (note: underscore, not hyphen)
            "Sent"      = "sent";
            "Drafts"    = "drafts";
            "Archive"   = "archive";
          };
          sync.wildcards = [ "Folders/*" ];
          send.msmtpAccount = "iheartwoodcraft";
        };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
