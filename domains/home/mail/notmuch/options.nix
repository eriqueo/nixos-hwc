{ lib, osConfig ? {}, ...}:
let t = lib.types; in
{
  options.hwc.home.mail.notmuch = {
    maildirRoot = lib.mkOption { type = t.str; default = ""; };
    userName = lib.mkOption { type = t.str; default = ""; };
    primaryEmail = lib.mkOption { type = t.str; default = ""; };
    otherEmails = lib.mkOption { type = t.listOf t.str; default = []; };
    newTags = lib.mkOption { type = t.listOf t.str; default = [ "unread" "inbox" ]; };
    excludeFolders = lib.mkOption { type = t.listOf t.str; default = []; };
    postNewHook = lib.mkOption { type = t.lines; default = ""; };
    savedSearches = lib.mkOption { type = t.attrsOf t.str; default = {}; };
    installDashboard = lib.mkOption { type = t.bool; default = false; };
    installSampler = lib.mkOption { type = t.bool; default = false; };
    rules = {
      newsletterSenders = lib.mkOption { type = t.listOf t.str; default = [ "newsletter@" "news@" "updates@" "digest@" "list@" "mailer@" ]; };
      notificationSenders = lib.mkOption { type = t.listOf t.str; default = [ "no-reply@" "noreply@" "notifications@" "notices@" "github.com" ]; };
      financeSenders = lib.mkOption { type = t.listOf t.str; default = [ "amazon.com" "paypal.com" "stripe.com" "squareup.com" "intuit.com" "quickbooks" "chase.com" "bankofamerica.com" ]; };
      actionSubjects = lib.mkOption { type = t.listOf t.str; default = [ "invoice" "quote" "proposal" "estimate" "RFP" "action required" "approve" "signature" "past due" ]; };
    };
  };
}