{ lib, pkgs, special, rulesText, extraHook }:
let
  mk = clause: tag: minus:
    if clause == "" then "" else ''notmuch tag ${tag} ${minus} -- '${clause}'\n'';

  head = ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
  '';

  body = ''
    ${mk special.sent   "+sent"    "-inbox -unread"}
    ${mk special.drafts "+draft"   "-inbox -unread"}
    ${mk special.trash  "+trash"   "-inbox -unread"}
    ${mk special.spam   "+spam"    "-inbox -unread"}
    ${mk special.archive "+archive" "-inbox"}
  '';

  extra =
    if (builtins.isString extraHook && extraHook != "")
    then "\n" + extraHook
    else "";

  tail = rulesText + extra;
in
{
  text = head + body + "\n" + tail;
}
