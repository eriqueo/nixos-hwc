# profiles/mail/home.nix — mail role, Home Manager lane
#
# Full mail menu: bridge, aerc, notmuch, calendar sync, mail health.
# Identity data lives here because only the mail role consumes it.
#
# USED BY: see the machines table in flake.nix

{ lib, ... }:

{
  imports = [
    ../../domains/mail/index.nix
  ];

  hwc.mail = {
    enable = true;
    bridge.enable = lib.mkDefault true;
    aerc.enable = true;

    # Calendar + tasks sync against the self-hosted Radicale server only.
    calendar = {
      enable = true;
      icsWatch.enable = true;
    };

    # VTODO sync (todoman) against Radicale. Shares calendar's vdirsyncer
    # config + timer.
    tasks.enable = true;

    # CardDAV rolodex (khard + aerc completion) against the CRM-owned
    # eric/contacts address book — bidirectional peer of the iPhone account.
    contacts.enable = true;

    health = {
      enable = true;
      # webhook.url names a concrete host — it lives in the machine one-off
      # (machines/<m>/home.nix), per Law 16.
      freshnessHours = 12;
    };

    notmuch = {
      maildirRoot = "/home/eric/400_mail/Maildir";
      userName = "Eric O'Keefe";
      primaryEmail = "eric@iheartwoodcraft.com";
      otherEmails = [ "eriqueo@proton.me" "heartwoodcraftmt@gmail.com" "eriqueokeefe@gmail.com" ];
      excludeFolders = [ "trash" "spam" "[Gmail]/All Mail" ];

      savedSearches = {
        inbox = "tag:inbox and not tag:archived";
        unread = "tag:unread";
        work = "from:*@iheartwoodcraft.com or from:*heartwoodcraftmt@gmail.com";
        personal = "from:*@proton.me or from:*eriqueokeefe@gmail.com";
        urgent = "tag:urgent or tag:important";
      };
    };
  };
}
