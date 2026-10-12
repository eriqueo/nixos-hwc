# Pure grammar -> deterministic Markdown reference. No runtime commands are needed.
{ lib, grammar }:
let
  escape = lib.replaceStrings [ "|" "\n" ] [ "&#124;" "<br>" ];
  table = headings: rows: lib.concatStringsSep "\n"
    ([ "| ${lib.concatStringsSep " | " headings} |"
       "| ${lib.concatStringsSep " | " (map (_: "---") headings)} |" ]
     ++ map (cells: "| ${lib.concatStringsSep " | " (map escape cells)} |") rows);
  sorted = builtins.sort (a: b: a.keys < b.keys);
  chord = row: "Space ${row.keys}";
  appRows = app: sorted (lib.filter (row: (row.cmd or {}) ? ${app})
    (grammar.shared ++ (grammar.apps.${app} or [])));
  app = name: let rows = appRows name;
    aliases = lib.concatMap (row: map (key: [ key row.desc ]) (row.bare or [])) rows;
  in "## ${name}\n\n" + table [ "Chord" "Description" ]
    (map (row: [ (chord row) row.desc ]) rows)
    + "\n\n### Bare aliases\n\n" + (if aliases == [] then
      "No bare aliases declared in the grammar; native app keys remain unchanged."
      else table [ "Key" "Description" ] aliases);
  mailRows = sorted grammar.aerc.bindings;
  aliasKey = alias: if builtins.isString alias then alias else alias.key;
  aercAliases = lib.concatMap (row: lib.concatLists (lib.mapAttrsToList
    (context: aliases: map (alias: [ (aliasKey alias) context
      (if builtins.isString alias then row.desc else alias.action) ]) aliases)
    (row.bare or {}))) mailRows;
  wbAliases = lib.concatMap (row: map (alias: [ (aliasKey alias)
    (if builtins.isString alias then row.wb.verb else alias.verb) ])
    ((row.bare or {}).list or []))
    (lib.filter (row: row.wb ? verb || row.wb ? menu) mailRows);
  realization = row:
    if row.wb ? verb then "native verb: ${row.wb.verb}"
    else if row.wb ? menu then "menu: ${row.wb.menu}"
    else if row.wb ? handoff then "handoff: ${row.wb.handoff}"
    else "omitted: ${row.wb.omit}";
in
lib.concatStringsSep "\n\n" ([
  "<!-- generated — do not edit; run `nix run .#keymap-docs` -->\n# Unified keymap"
  "Space acts inside the focused app. ${grammar.metaLeader} opens the inter-app layer. Rows and groups are sorted by chord/letter."
  ("## Groups\n\n" + table [ "Letter" "Meaning" ]
    (lib.mapAttrsToList (key: meaning: [ key meaning ]) grammar.groups))
] ++ map app (builtins.attrNames grammar.apps) ++ [
  ("## aerc\n\n" + table [ "Chord" "Description" "Scope" ]
    (map (row: [ (chord row) row.desc row.scope ]) mailRows)
    + "\n\n### Bare aliases\n\n" + table [ "Key" "Context" "Description / action" ] aercAliases)
  ("## Workbench globals\n\n" + table [ "Chord" "Description" ]
    (map (row: [ (chord row) row.desc ]) (appRows "workbench")))
  ("## Workbench Mail\n\nOmitted rows are reference entries, not active bindings. Menu rows open choices supplied by the mail contract.\n\n"
    + table [ "Chord" "Description" "Realization" ]
      (map (row: [ (chord row) row.desc (realization row) ]) mailRows)
    + "\n\n### Bare aliases\n\n" + table [ "Key" "Native verb" ] wbAliases)
  "## Accepted differences\n\nBare `a` adds in todui/khalt but archives in aerc/Workbench Mail. In the aerc viewer, bare `r` replies and bare `u` opens the URL picker; list aliases mark read/unread. Native keys absent from the grammar are not listed here."
]) + "\n"
