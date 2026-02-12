{ lib, pkgs, special, afewPkg, afewEnabled ? true, rulesText, extraHook, osConfig ? {}}:
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
    export PATH=${lib.makeBinPath ([ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.findutils pkgs.ripgrep pkgs.notmuch ] ++ lib.optional afewEnabled afewPkg)}

    # Ensure we use your hm-generated config
    export NOTMUCH_CONFIG="$HOME/.notmuch-config"
  '';

  body = ''
    ${lib.optionalString afewEnabled ''    # Automated tagging via afew (non-fatal on errors)
    ${afewPkg}/bin/afew --tag --new || true
''}

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
    # Domain tags (work HWC vs personal)
    ${nm} tag +hwc -- 'path:.100_proton/** OR path:.110_gmail-business/**'
    ${nm} tag +personal -- 'path:.210_gmail-personal/**'

    # Account-specific tags (for granular filtering)
    ${nm} tag +proton-hwc -- 'path:.100_proton/**'
    ${nm} tag +gmail-business -- 'path:.110_gmail-business/**'
    ${nm} tag +gmail-personal -- 'path:.210_gmail-personal/**'

    # Folder state tags (apply to all accounts)
    # NOTE: parentheses required - AND binds tighter than OR in notmuch query syntax
    ${nm} tag +inbox -- '(folder:**/INBOX OR folder:**/inbox) AND NOT tag:trash'
    ${nm} tag +sent -- '(folder:**/Sent OR folder:**/"[Gmail].Sent Mail") AND NOT tag:trash'
    ${nm} tag +draft -- '(folder:**/Drafts OR folder:**/"[Gmail].Drafts") AND NOT tag:trash'
    ${nm} tag +trash -- 'folder:**/Trash OR folder:**/"[Gmail].Trash" OR folder:**/"[Gmail].Bin"'
  '';
  tail = rulesPatched + "\n" + accountTags + extra;
in
{
  text = head + "\n" + body + "\n" + tail;
}
