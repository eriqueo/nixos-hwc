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
    bridge.enable = true;
    aerc.enable = true;

    calendar = {
      enable = true;
      icsWatch.enable = true;
      accounts.icloud = {
        email = "eric@iheartwoodcraft.com";
        color = "dark green";
      };
    };

    # VTODO/Reminders sync (todoman). Shares calendar's vdirsyncer config + timer
    # and reuses the icloud account above.
    tasks.enable = true;

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
      newTags = [ "unread" "inbox" ];
      excludeFolders = [ "trash" "spam" "[Gmail]/All Mail" ];

      # Go-forward classification, derived from the 2026-06 Gmail backlog audit.
      # Scoped to tag:new (only future mail) and never touches tag:keep
      # (family/friends). See domains/mail/notmuch/parts/rules.nix.
      rules = {
        # Pure noise — auto-trashed on arrival.
        trashSenders = [
          # lead-gen platforms
          "angi.com" "angieslist.com" "homeadvisor.com" "wix.com"
          # marketing drip / cold social
          "linkedin.com" "nextdoor.com" "semrush.com" "jonloomer.com"
          "trainsemail.com" "thinkr.org" "constructionconsulting.co"
          "contractorcto.com" "nextlevelsystems.co" "qemailserver.com"
          "ccsend.com"
        ];
        # Low-value-but-keepable — auto-archived (out of inbox, kept in All Mail).
        archiveSenders = [
          # retail / suppliers (receipts tracked in QB/JobTread; keep findable)
          "amazon.com" "sherwin.com" "harborfreight.com" "homedepot.com"
          "bruntworkwear.com" "fergusonhome.com" "bestbuy.com" "soundcore.com"
          "jossandmain.com" "plumdragonherbs.com" "hibid.com"
          # coaching / industry
          "builttobuildacademy.com" "narihq.org" "agingcare.com"
          "thecontractorfight.com"
          # bulk / SaaS marketing
          "mailchimpapp.com" "zapier.com" "supadata.ai" "beehiiv.com"
          "sage.com" "perplexity.ai" "vimeo.com"
        ];
      };

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
