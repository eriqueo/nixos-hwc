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

    # Folder state tags - use explicit path: queries (folder: globs don't work in notmuch)
    ${nm} tag +inbox -- \
      'path:.100_proton/inbox/** OR path:.110_gmail-business/inbox/** OR path:.210_gmail-personal/inbox/**'
    ${nm} tag +sent -inbox -unread -- \
      'path:.100_proton/Sent/** OR path:.110_gmail-business/[Gmail]/Sent\ Mail/** OR path:.210_gmail-personal/[Gmail]/Sent\ Mail/**'
    ${nm} tag +draft -inbox -unread -- \
      'path:.100_proton/Drafts/** OR path:.110_gmail-business/[Gmail]/Drafts/** OR path:.210_gmail-personal/[Gmail]/Drafts/**'
    ${nm} tag +trash -inbox -unread -- \
      'path:.100_proton/Trash/** OR path:.110_gmail-business/[Gmail]/Trash/** OR path:.210_gmail-personal/[Gmail]/Trash/**'
    ${nm} tag +spam -inbox -unread -- \
      'path:.100_proton/Spam/** OR path:.110_gmail-business/[Gmail]/Spam/** OR path:.210_gmail-personal/[Gmail]/Spam/**'
    ${nm} tag +archive -inbox -- \
      'path:.100_proton/Archive/** OR path:.110_gmail-business/[Gmail]/All\ Mail/** OR path:.210_gmail-personal/[Gmail]/All\ Mail/**'
  '';
  tail = rulesPatched + "\n" + accountTags + extra;
in
{
  text = head + "\n" + body + "\n" + tail;
}
