{ lib, ... }:
let t = lib.types; in
{
  options.hwc.home.mail.notmuch = {
    # Leave empty → module derives from config.home.homeDirectory
    maildirRoot = lib.mkOption { type = t.str; default = ""; };

    # Identity (empty → derived from primary account if present)
    userName     = lib.mkOption { type = t.str; default = ""; };
    primaryEmail = lib.mkOption { type = t.str; default = ""; };
    otherEmails  = lib.mkOption { type = t.listOf t.str; default = []; };

    # Behavior / policy
    newTags        = lib.mkOption { type = t.listOf t.str; default = [ "unread" "inbox" ]; };
    excludeFolders = lib.mkOption { type = t.listOf t.str; default = []; };
    postNewHook    = lib.mkOption { type = t.lines; default = ""; };

    # UI
    savedSearches   = lib.mkOption { type = t.attrsOf t.str; default = {}; };
    installDashboard = lib.mkOption { type = t.bool; default = false; };
    installSampler   = lib.mkOption { type = t.bool; default = false; };
    
    rules = {
      # Senders you consider newsletters
      newsletterSenders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "newsletter@" "news@" "updates@" "digest@" "list@" "mailer@" ];
        description = "Substrings to match in From: for newsletter tagging.";
      };

      # Senders you consider “notifications”
      notificationSenders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "no-reply@" "noreply@" "notifications@" "notices@" "github.com" ];
        description = "Substrings for notification tagging.";
      };

      # Finance-ish senders
      financeSenders = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "amazon.com" "paypal.com" "stripe.com" "squareup.com" "intuit.com" "quickbooks" "chase.com" "bankofamerica.com" ];
        description = "Substrings for finance tagging.";
      };

      # Subjects that imply action
      actionSubjects = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "invoice" "quote" "proposal" "estimate" "RFP" "action required" "approve" "signature" "past due" ];
        description = "Lowercase substrings; if present in subject mark +action.";
      };
    };
  };  
}
