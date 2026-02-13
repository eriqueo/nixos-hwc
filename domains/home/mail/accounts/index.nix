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
    proton = {
        name = "proton";
        type = "proton-bridge";
        realName = "Eric";
        address = "eric@iheartwoodcraft.com";  # Primary address for sending
        login = "eric@iheartwoodcraft.com";
        password = { mode = "pass"; pass = "email/proton/bridge"; };
        maildirName = "proton";
        # Sync ALL Proton folders except "All Mail" (virtual) and lowercase
        # duplicates exposed by Bridge (Sent/sent, Archive/archive, etc.)
        sync.wildcards = [ "*" "!All Mail" "!archive" "!drafts" "!sent" "!starred" ];
        send.msmtpAccount = "proton-hwc";  # Default to work identity
        # Additional sending identities for other addresses on this account
        extraMsmtp = ''
          account proton-personal
          host 127.0.0.1
          port 1025
          tls off
          tls_starttls off
          auth plain
          from eriqueo@proton.me
          user eriqueo@proton.me
          passwordeval "pass show email/proton/bridge"

          account proton-office
          host 127.0.0.1
          port 1025
          tls off
          tls_starttls off
          auth plain
          from office@iheartwoodcraft.com
          user office@iheartwoodcraft.com
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
        maildirName = "gmail-personal";
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
        maildirName = "gmail-business";
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
