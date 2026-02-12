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
        login = "eric@iheartwoodcraft.com";  # Bridge IMAP username (split mode requires email address)
        password = { mode = "pass"; pass = "email/proton/bridge"; };
        maildirName = ".100_proton";  # Hidden account sync folder
        # Sync ALL Proton folders except "All Mail" (virtual folder causes issues with Expunge)
        # Exclude "All Mail" (virtual) and lowercase duplicates exposed by Bridge
        # (Bridge exposes both "Sent" and "sent", "Archive" and "archive", etc.)
        sync.wildcards = [ "*" "!All Mail" "!archive" "!drafts" "!sent" "!starred" ];
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
          maildirName = ".210_gmail-personal";
          # Sync inbox plus all Gmail label folders
          sync.wildcards = [ "INBOX" "[Gmail]/*" ];
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
          maildirName = ".110_gmail-business";
          # Sync inbox plus all Gmail label folders
          sync.wildcards = [ "INBOX" "[Gmail]/*" ];
          send.msmtpAccount = "gmail-business";
        };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
