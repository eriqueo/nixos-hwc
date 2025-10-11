{ lib, pkgs, special, rulesText, extraHook }:
let
  nm = "${pkgs.notmuch}/bin/notmuch";

  # Rewrite any ‘notmuch ’ occurrences coming from rulesText into the absolute path.
  rulesPatched = builtins.replaceStrings [ "notmuch " ] [ "${nm} " ] rulesText;

   mk = clause: tag: minus:
    if clause == "" then "" else ''
  ${pkgs.notmuch}/bin/notmuch tag ${tag} ${minus} -- '${clause}'
  '';
  head = ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail
    umask 077

    # Minimal, predictable PATH for systemd
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils pkgs.ripgrep pkgs.notmuch ]}

    # Ensure we use your hm-generated config
    export NOTMUCH_CONFIG="$HOME/.notmuch-config"
  '';

  body = ''
    ${mk special.sent    "+sent"     "-inbox -unread"}
    ${mk special.drafts  "+draft"    "-inbox -unread"}
    ${mk special.trash   "+trash"    "-inbox -unread"}
    ${mk special.spam    "+spam"     "-inbox -unread"}
    ${mk special.archive "+archive"  "-inbox"}

    # Safety: never action/newsletter/notification on system folders
    ${nm} tag -action -newsletter -notification -- 'tag:sent OR tag:trash OR tag:spam OR tag:draft'
  '';

  extra =
    if (builtins.isString extraHook && extraHook != "") then "\n" + extraHook else "";

  accountTags = ''
    # Tag by source account (path-based - infallible)
    ${nm} tag +hwc_email -- 'path:100_hwc/** and not tag:hwc_email'
    ${nm} tag +gmail_work -- 'path:110_gmail-business/** and not tag:gmail_work'
    ${nm} tag +proton_pers -- 'path:200_personal/** and not tag:proton_pers'
    ${nm} tag +gmail_pers -- 'path:210_gmail-personal/** and not tag:gmail_pers'

    # Tag by domain (work vs personal)
    ${nm} tag +work -- '(tag:hwc_email or tag:gmail_work) and not tag:work'
    ${nm} tag +personal -- '(tag:proton_pers or tag:gmail_pers) and not tag:personal'

    # Tag unified inbox
    ${nm} tag +inbox -- 'folder:000_inbox and not tag:inbox'
  '';
  tail = rulesPatched + "\n" + accountTags + extra;
in
{
  text = head + "\n" + body + "\n" + tail;
}
