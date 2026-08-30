{ config, lib, pkgs, osConfig ? {}, ... }:

let
  # Feature Detection: Check if we're on a NixOS host with HWC system config
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};

  # Handshake: safe access to agenix secrets (mirrors calendar/index.nix and
  # tasks/index.nix). Use osConfig.age.secrets path when HM evaluates as a
  # NixOS module (sudo nixos-rebuild). Fall back to the canonical agenix
  # runtime path so standalone HM (`hms`) doesn't rewrite ~/.mbsyncrc with
  # /dev/null — the secret file exists at this path regardless of HM eval mode.
  # /dev/null was the old fallback: it produced an empty PassCmd, which made
  # mbsync skip both Gmail accounts and exit 1 every 10 minutes with nothing in
  # the config to show for it. A wrong path that fails at runtime is worse than
  # no branch at all.
  gmailPersonalSecretPath = if (osCfg ? age) && (osCfg.age.secrets ? gmail-personal-password)
                            then osCfg.age.secrets.gmail-personal-password.path
                            else "/run/agenix/gmail-personal-password";

  gmailBusinessSecretPath = if (osCfg ? age) && (osCfg.age.secrets ? gmail-business-password)
                            then osCfg.age.secrets.gmail-business-password.path
                            else "/run/agenix/gmail-business-password";
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.mail.accountsResolved = lib.mkOption {
    type = lib.types.attrs;
    default = {};
    readOnly = true;
    description = "Derived per-account maildir + provider-specific special-folder roles for downstream modules.";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config.hwc.mail.accounts = {
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
        sync.wildcards = [ "*" "!All Mail" "!archive" "!drafts" "!sent" "!starred" "!Labels/_*" ];
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

    ## Gmail accounts - IMAP sync ENABLED for backlog cleanup (2026-06-22).
    ##  Both still forward to Proton; msmtp send-only accounts remain active.
    ##  Wildcards bounded to INBOX only: pulling [Gmail]/All Mail would drag in
    ##  the full archive superset (tens of thousands, duplicated). Archive in
    ##  Gmail = removing the INBOX label, which mbsync expresses by expunging the
    ##  message from the INBOX channel (it survives in All Mail). Widen the
    ##  wildcard set later if other labels need indexing.

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
        sync.enable = true;   # Backlog cleanup: pull INBOX into notmuch
        sync.wildcards = [ "INBOX" "Family-Friends" ];
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
        sync.enable = true;   # Backlog cleanup: pull INBOX into notmuch
        sync.wildcards = [ "INBOX" "Family-Friends" ];
        send.msmtpAccount = "gmail-business";
      };
    
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
