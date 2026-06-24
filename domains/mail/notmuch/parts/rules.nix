{ lib, cfg, osConfig ? {}}:
let
  R = cfg.rules or {};
  orJoin = xs: lib.concatStringsSep " OR " xs;
  mkFrom = s: "from:" + s;
  mkSubj = s: "subject:" + lib.toLower s;

  newsletterQ   = orJoin (["list:\"*\""] ++ map mkFrom (R.newsletterSenders   or []));
  notificationQ = orJoin (map mkFrom (R.notificationSenders or []));
  financeQ      = orJoin (map mkFrom (R.financeSenders      or []));
  actionQ       = orJoin (map mkSubj (R.actionSubjects      or []));
  trashQ        = orJoin (map mkFrom (R.trashSenders        or []));
  archiveQ      = orJoin (map mkFrom (R.archiveSenders      or []));

  # Emit a real newline using a multi-line string
  line = tag: ops: q:
    if q == "" then "" else ''
notmuch tag ${tag} ${ops} -- '${q}'
'';

  # Scope rules to tag:new so they only process freshly-indexed messages.
  scopeNew = q: if q == "" then "" else "tag:new AND (${q})";
  # Destructive rules also never touch protected (family/friends) mail.
  scopeNewSafe = q: if q == "" then "" else "tag:new AND NOT tag:keep AND (${q})";
  rulesText = ''
${line "+newsletter"  "-inbox" (scopeNew newsletterQ)}
${line "+notification" "-inbox" (scopeNew notificationQ)}
${line "+finance"     "-inbox" (scopeNew financeQ)}
${line "+action"      ""       (scopeNew actionQ)}
${line "+archive"     "-inbox" (scopeNewSafe archiveQ)}
${line "+trash"       "-inbox -unread" (scopeNewSafe trashQ)}
'';
in { text = rulesText; }