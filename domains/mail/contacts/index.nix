# domains/mail/contacts/index.nix
#
# contacts — CardDAV rolodex client (khard + vdirsyncer pair).
#
# NAMESPACE: hwc.mail.contacts.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.mail.contacts.enable = true;
#
# Auto-imported by domains/mail/index.nix (readDir).
#
# The machine-side twin of the iPhone's CardDAV account: two-way syncs the
# CRM-owned `eric/contacts` address book on Radicale (hwc-crm D26) to a local
# vdir. khard reads/writes the vdir; aerc completes addresses from it (via
# mail-addresses, merged with notmuch history). Edits made here flow back to
# Radicale on the next vdirsyncer run, where the CRM's 15-min reconcile folds
# them into leads exactly like phone edits — every client is a peer.
#
# Like mail/tasks, this module runs NO vdirsyncer config or timer of its own:
# it contributes a [pair contacts_radicale] fragment to
# hwc.mail.calendar.extraVdirsyncerPairs (asserted below).

{ config, lib, pkgs, osConfig ? {}, ... }:

let
  cfg = config.hwc.mail.contacts;

  dataDir = "~/.local/share/vdirsyncer";

  # Handshake: agenix secret path when HM evaluates as a NixOS module,
  # canonical runtime path for standalone `hms` (mirrors mail/tasks).
  isNixOSHost = osConfig ? hwc;
  osCfg = if isNixOSHost then osConfig else {};
  hasRadicalePw = (osCfg ? age) && (osCfg.age.secrets ? radicale-htpasswd);
  radicalePwPath = if hasRadicalePw
    then osCfg.age.secrets.radicale-htpasswd.path
    else "/run/agenix/radicale-htpasswd";

  contactsPair = ''
    [pair contacts_radicale]
    a = "contacts_radicale_remote"
    b = "contacts_radicale_local"
    # Pinned to the CRM-owned address book (hwc-crm creates it server-side).
    # carddav storages only discover addressbooks, but pinning keeps a stray
    # phone-created book from silently joining the sync.
    collections = ["${cfg.collection}"]
    metadata = ["displayname"]
    # True simultaneous-edit conflicts resolve to the server copy: the CRM is
    # the canonical writer and its reconcile pass re-folds machine edits anyway.
    conflict_resolution = "a wins"

    [storage contacts_radicale_remote]
    type = "carddav"
    url = "${cfg.url}"
    username = "${cfg.username}"
    # Same quote-free awk password extraction as the calendar/tasks pairs:
    # pick this user's line from the shared multi-user htpasswd secret.
    password.fetch = ["command", "awk", "-F:", "-v", "u=${cfg.username}", "$1==u{match($0,/:/);print substr($0,RSTART+1)}", "${radicalePwPath}"]

    [storage contacts_radicale_local]
    type = "filesystem"
    path = "${dataDir}/contacts-radicale/"
    fileext = ".vcf"
  '';

  khardConf = ''
    [addressbooks]
    [[hwc-crm]]
    path = ~/.local/share/vdirsyncer/contacts-radicale/${cfg.collection}/

    [general]
    default_action = list
    editor = nvim

    [contact table]
    display = first_name
    preferred_email_address_type = pref, work, home
    preferred_phone_number_type = pref, cell, home

    [vcard]
    # Match what the CRM writes (and iOS accepts) — avoids version churn
    # on round-trip edits.
    preferred_version = 3.0
  '';

  # aerc address-book-cmd target: rolodex contacts (khard) first, then
  # notmuch sender history, deduped case-insensitively.
  addrScript = pkgs.writeShellScriptBin "mail-addresses" ''
    {
      ${pkgs.khard}/bin/khard email --parsable --remove-first-line "$1" 2>/dev/null
      ${pkgs.notmuch}/bin/notmuch address --format=text --output=recipients "$1" 2>/dev/null
    } | ${pkgs.gawk}/bin/awk '!seen[tolower($0)]++'
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.mail.contacts = {
    enable = lib.mkEnableOption
      "CardDAV rolodex sync (khard + vdirsyncer against the CRM address book)";

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://tasks.hwc.iheartwoodcraft.com/";
      description = "Radicale base URL (the Caddy vhost; serves CardDAV too).";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "eric";
      description = "Radicale user owning the address book (the phone's login).";
    };

    collection = lib.mkOption {
      type = lib.types.str;
      default = "contacts";
      description = "Address book collection id under the user (hwc-crm D26).";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.khard addrScript ];

    # Ride the calendar's single vdirsyncer config + 15-min timer.
    hwc.mail.calendar.extraVdirsyncerPairs = [ contactsPair ];

    xdg.configFile."khard/khard.conf".text = khardConf;

    home.activation.contactsDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p ~/.local/share/vdirsyncer/contacts-radicale
    '';

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = config.hwc.mail.calendar.enable;
        message = "hwc.mail.contacts requires hwc.mail.calendar.enable = true "
          + "(it shares the calendar vdirsyncer config and sync timer).";
      }
    ];
  };
}
