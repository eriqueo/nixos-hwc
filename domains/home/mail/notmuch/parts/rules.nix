{ lib, cfg }:
let
  R = cfg.rules or {};
  orJoin = xs: lib.concatStringsSep " OR " xs;
  mkFrom = s: "from:" + s;
  mkSubj = s: "subject:" + lib.toLower s;

  newsletterQ   = orJoin (["list:\"*\""] ++ map mkFrom (R.newsletterSenders   or []));
  notificationQ = orJoin (map mkFrom (R.notificationSenders or []));
  financeQ      = orJoin (map mkFrom (R.financeSenders      or []));
  actionQ       = orJoin (map mkSubj (R.actionSubjects      or []));

  # Emit a real newline using a multi-line string
  line = tag: ops: q:
    if q == "" then "" else ''
notmuch tag ${tag} ${ops} -- '${q}'
'';

  rulesText = ''
${line "+newsletter"  "-inbox" newsletterQ}
${line "+notification" "-inbox" notificationQ}
${line "+finance"     "-inbox" financeQ}
${line "+action"      ""       actionQ}
'';
in { text = rulesText; }
