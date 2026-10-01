# One search registry for notmuch, aerc and the MCP mail tool.
{ lib, cfg, mailContract, osConfig ? {} }:
let
  taxonomy = (import ../../taxonomy/lib.nix { inherit lib; }).data;
  axis = name: prefix: items: builtins.listToAttrs (map (item: {
    name = "${name}:${item}";
    value = "tag:${prefix}${item}";
  }) items);
  custom = builtins.fromJSON (builtins.readFile ../../aerc/parts/tags-custom.json);
  customFacts = builtins.listToAttrs (map (tag: {
    name = "custom-fact:${tag.tag}"; value = "tag:${tag.tag} AND NOT tag:trash";
  }) ((custom.categories or []) ++ (custom.flags or [])));
  current = {
    inbox = "tag:inbox AND NOT tag:trash";
    unread = "tag:unread AND NOT tag:trash";
    sent = "tag:sent";
    drafts = "tag:draft";
    archive = "tag:archive AND NOT tag:trash";
    trash = "tag:trash";
    spam = "tag:spam";
    all = "NOT tag:trash";
    keep = "tag:keep";
    important = "tag:important AND NOT tag:trash";
    starred = "tag:flagged AND NOT tag:trash";
    "label:hide" = "tag:hide";
  } // axis "state" mailContract.stateTagPrefix mailContract.states
    // axis "domain" mailContract.domainTagPrefix mailContract.domains
    // axis "fact" mailContract.traitTagPrefix mailContract.factTags;
  legacy = {
    action = "tag:action AND tag:unread";
    finance = "tag:finance AND tag:unread";
    newsletter = "tag:newsletter AND tag:unread";
    notifications = "tag:notification AND tag:unread";
    focus = "tag:inbox AND tag:unread AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:trash";
    today = "tag:inbox AND date:1d.. AND NOT tag:trash";
    week = "tag:inbox AND date:1w.. AND NOT tag:trash";
    people = "tag:inbox AND NOT tag:notification AND NOT tag:newsletter AND NOT tag:sent AND NOT tag:trash";
    business = "tag:inbox AND (tag:work OR tag:office OR tag:hwcmt) AND NOT tag:trash";
    money = "tag:inbox AND (tag:finance OR tag:bank OR tag:insurance) AND NOT tag:trash";
    growth = "tag:inbox AND (tag:admin OR tag:coaching) AND NOT tag:trash";
    system = "tag:inbox AND (tag:tech OR tag:website) AND NOT tag:trash";
    "inbox:hwc" = "tag:inbox AND tag:hwc";
    "inbox:proton-hwc" = "tag:inbox AND tag:proton-hwc";
    "inbox:proton-personal" = "tag:inbox AND tag:proton-personal";
    "inbox:gmail" = "tag:inbox AND (path:gmail-personal/inbox/** OR path:gmail-business/inbox/**)";
    family = "tag:family";
    "family:unread" = "tag:family AND tag:unread";
    "all:work" = "tag:inbox AND tag:hwc";
    "all:personal" = "tag:inbox AND tag:proton-personal";
    "label:work" = "tag:work AND NOT tag:trash";
    "label:finance" = "tag:finance AND NOT tag:trash";
    "label:coaching" = "tag:coaching AND NOT tag:trash";
    "label:tech" = "tag:tech AND NOT tag:trash";
    "label:bank" = "tag:bank AND NOT tag:trash";
    "label:insurance" = "tag:insurance AND NOT tag:trash";
    "label:personal" = "tag:gmail-personal AND NOT tag:trash";
    "label:hwcmt" = "tag:hwcmt AND NOT tag:trash";
  } // builtins.listToAttrs (map (tag: {
    name = tag.display or tag.tag;
    value = "(${tag.query or "tag:${tag.tag} AND NOT tag:trash"}) AND tag:inbox";
  }) (taxonomy.categories ++ (custom.categories or [])));
  history = lib.mapAttrs' (name: value: lib.nameValuePair "history:${name}" value) legacy;
  searches = current // customFacts // history // (cfg.savedSearches or {});
  text = "# mail-searches-v1\n" + lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: query: "${name}=${query}") searches) + "\n";
  # Aerc's INI parser treats ':' as a key/value delimiter. Keep the shared
  # address vocabulary and substitute '/' only in its transport rendering.
  aercText = "# mail-searches-v1\n" + lib.concatStringsSep "\n"
    (lib.mapAttrsToList (name: query:
      "${lib.replaceStrings [ ":" ] [ "/" ] name}=${query}") searches) + "\n";
in { inherit searches text aercText; }
