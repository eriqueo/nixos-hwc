# Pure adapter: shared action table -> context bindings, popup groups and help.
{ lib, grammar, commands, menus }:
let
  lhs = keys: "<Space>" + lib.concatStrings (lib.splitString " " keys);
  available = context: b:
    b.scope == "global"
    || (context == "messages" && lib.elem b.scope [ "account" "message" ])
    || (context == "view" && lib.elem b.scope [ "account" "message" "view" "closable" ])
    || (context == "terminal" && b.scope == "closable");
  bindings = context: lib.filter (available context) grammar.aerc.bindings;
  line = context: b: "      ${lhs b.keys} = "
    + lib.optionalString (context == "view" && b.scope == "account") ":close<Enter>"
    + commands.${b.action} + " # ${b.desc}";
  groupNames = grammar.groups // { m = "mail"; w = "view"; o = "handoff"; q = "app"; };
  activeGroups = lib.unique (map (b: builtins.substring 0 1 b.keys)
    (lib.filter (b: b.keys != "?") grammar.aerc.bindings));
  helpRow = b: "| Space ${b.keys} | ${b.desc} | ${b.scope} |";
  menuRows = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: choices:
    "\n${name}:\n" + lib.concatStringsSep "\n" (map (c: "  ${c.key}  ${c.desc}") choices)
  ) menus);
in {
  bindsFor = context: lib.concatStringsSep "\n" (map (line context) (bindings context));
  whichKeyGroups = lib.concatStringsSep ", " (map (g: "${g}:${groupNames.${g}}") activeGroups);
  markdown = lib.concatStringsSep "\n" ([
    "| Keys | Action | Context |"
    "|---|---|---|"
  ] ++ map helpRow grammar.aerc.bindings);
  leaderHelp = ''
    AERC — Space is the leader. Space ? opens this sheet.
    Press Space, then a group letter. Pause to see the available actions.
    Esc cancels a menu. Context: account = list (returns there from viewer),
    message = list or viewer, view = opened message, global = list/view/terminal.
    Close tab is available in the viewer and terminal tabs.

    ${lib.concatStringsSep "\n" (map (b: "Space ${b.keys}   ${b.desc} [${b.scope}]") grammar.aerc.bindings)}

    SUBMENUS (choose the displayed key after opening the named menu)
    ${menuRows}

    QUICK KEYS
    j/k move; J/K mark and move; V visual mark; Enter open.
    a archive; d trash; c compose; / filter words in the message list.
    r marks read in the list; r replies in the viewer. u marks unread in list.
    Alt+j/k folders; Alt+h/l tabs; q closes a viewer or preview.
    Bare i/I are retired. Use Space o c for calendar, Space w i for preview.
    Space w n/p selects MIME parts. An image part can show sharp local images.
    The inline preview still uses blocks. Remote images stay blocked.
    Leave a preview with q before changing MIME parts.
  '';
}
