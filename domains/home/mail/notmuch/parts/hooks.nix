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
    # Proton: tag by destination address (all addresses share one IMAP connection)
    # HWC addresses: eric@iheartwoodcraft.com, office@, admin@, g_hwcmt@proton.me
    ${nm} tag +proton-hwc -- \
      'path:proton/** AND (to:eric@iheartwoodcraft.com OR to:office@iheartwoodcraft.com OR to:admin@iheartwoodcraft.com OR to:g_hwcmt@proton.me OR from:eric@iheartwoodcraft.com OR from:office@iheartwoodcraft.com OR from:admin@iheartwoodcraft.com OR from:g_hwcmt@proton.me)'
    # Personal Proton addresses: eriqueo@proton.me, g_erique@proton.me
    ${nm} tag +proton-personal -- 'path:proton/** AND NOT tag:proton-hwc'

    # Gmail account tags
    ${nm} tag +gmail-business -- 'path:gmail-business/**'
    ${nm} tag +gmail-personal -- 'path:gmail-personal/**'

    # Domain rollup tags (work vs personal)
    ${nm} tag +hwc -- 'tag:proton-hwc OR path:gmail-business/**'
    ${nm} tag +personal -- 'tag:proton-personal OR path:gmail-personal/**'

    # Folder state tags - use explicit path: queries (folder: globs don't work in notmuch)
    ${nm} tag +inbox -- \
      'path:proton/inbox/** OR path:gmail-business/inbox/** OR path:gmail-personal/inbox/**'
    ${nm} tag +sent -inbox -unread -- \
      'path:proton/Sent/** OR path:gmail-business/[Gmail]/Sent\ Mail/** OR path:gmail-personal/[Gmail]/Sent\ Mail/**'
    ${nm} tag +draft -inbox -unread -- \
      'path:proton/Drafts/** OR path:gmail-business/[Gmail]/Drafts/** OR path:gmail-personal/[Gmail]/Drafts/**'
    ${nm} tag +trash -inbox -unread -- \
      'path:proton/Trash/** OR path:gmail-business/[Gmail]/Trash/** OR path:gmail-personal/[Gmail]/Trash/**'
    ${nm} tag +spam -inbox -unread -- \
      'path:proton/Spam/** OR path:gmail-business/[Gmail]/Spam/** OR path:gmail-personal/[Gmail]/Spam/**'
    ${nm} tag +archive -inbox -- \
      'path:proton/Archive/** OR path:gmail-business/[Gmail]/All\ Mail/** OR path:gmail-personal/[Gmail]/All\ Mail/**'
  '';
  tail = rulesPatched + "\n" + accountTags + extra;
in
{
  text = head + "\n" + body + "\n" + tail;
}
