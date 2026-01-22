{ lib, pkgs, special, afewPkg, rulesText, extraHook, osConfig ? {}}:
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
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils pkgs.ripgrep pkgs.notmuch afewPkg ]}

    # Ensure we use your hm-generated config
    export NOTMUCH_CONFIG="$HOME/.notmuch-config"
  '';

  body = ''
    # Automated tagging via afew (non-fatal on errors)
    ${afewPkg}/bin/afew --tag --new || true

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
    # Tag by per-account Maildir root (following runbook exactly)
    ${nm} tag +acc:hwc   -- 'path:100_hwc/**'
    ${nm} tag +acc:gbiz  -- 'path:110_gmail-business/**'
    ${nm} tag +acc:pers  -- 'path:200_personal/**'
    ${nm} tag +acc:gpers -- 'path:210_gmail-personal/**'

    # (Optional) reconstruct inbox/unread by folder names
    ${nm} tag +inbox  -- 'folder:inbox and not tag:trash and not tag:spam'
    ${nm} tag +unread -- 'folder:new   and not tag:trash and not tag:spam'
  '';
  tail = rulesPatched + "\n" + accountTags + extra;
in
{
  text = head + "\n" + body + "\n" + tail;
}
