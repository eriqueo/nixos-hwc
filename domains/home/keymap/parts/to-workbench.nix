# One mail row set produces aerc bindings and the schema-2 hub overlay.
{ lib, grammar, mailContract }:
let
  rows = grammar.aerc.bindings;
  valid = row: row ? wb && lib.length (builtins.attrNames row.wb) == 1
    && lib.elem (builtins.head (builtins.attrNames row.wb)) [ "verb" "menu" "handoff" "omit" ];
  entry = row: chord: intent: target: description: { inherit chord intent target description; };
  expand = row:
    if row.wb ? omit then []
    else if row.wb ? menu then
      let menu = row.wb.menu;
          choice = key: intent: desc: entry row "${row.keys} ${key}" intent "item" desc;
      in if menu == "state" then map (state: choice grammar.aerc.stateKeys.${state}
          "state-${state}" mailContract.stateDisplayNames.${state}) mailContract.states
      else if menu == "domain" then map (domain: choice grammar.aerc.domainKeys.${domain}
          "domain-${domain}" domain) mailContract.domains
      else if menu == "read-status" then [ (choice "r" "mark-read" "Read") (choice "u" "mark-unread" "Unread") ]
      else throw "Unknown Workbench mail menu: ${menu}"
    else [ (entry row row.keys (row.wb.verb or row.wb.handoff)
      (if row.wb ? verb then "item" else "handoff") row.desc) ];
  registry = {
    schemaVersion = 2;
    groups = grammar.groups;
    bindings = map (row: { chord = row.keys; intent = row.cmd.workbench; description = row.desc; })
      (lib.filter (row: (row.cmd or {}) ? workbench) grammar.shared);
    hubs.mail = {
      bindings = lib.concatMap expand rows;
      bare = lib.concatMap (row: map (alias: {
        key = if builtins.isString alias then alias else alias.key;
        intent = if builtins.isString alias then row.wb.verb else alias.verb;
      }) ((row.bare or {}).list or [])) (lib.filter (row: builtins.any (binding: binding.target == "item") (expand row)) rows);
      omitted = map (row: { chord = row.keys; reason = row.wb.omit; })
        (lib.filter (row: row.wb ? omit) rows);
    };
  };
in
assert lib.assertMsg (builtins.all valid rows) "Every aerc row must declare exactly one wb realization";
{ inherit registry;
  # Native argv suffixes live on the same rows that declare handoff intents.
  handoffCommands = aercCommand: builtins.listToAttrs (map (row: {
    name = row.wb.handoff;
    value = aercCommand + " " + lib.escapeShellArgs row.handoffArgs;
  }) (lib.filter (row: row.wb ? handoff) rows));
  json = builtins.toJSON registry; }
