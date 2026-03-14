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

    # Gmail account tags (disabled - Gmail now forwards to Proton; paths no longer synced)
    # ${nm} tag +gmail-business -- 'path:gmail-business/**'
    # ${nm} tag +gmail-personal -- 'path:gmail-personal/**'

    # Domain rollup tags (work vs personal) - Gmail paths removed, Proton-only now
    ${nm} tag +hwc -- 'tag:proton-hwc'
    ${nm} tag +personal -- 'tag:proton-personal'

    # Folder state tags - Proton only (Gmail sync disabled)
    ${nm} tag +inbox -- 'path:proton/inbox/**'
    ${nm} tag +sent -inbox -unread -- 'path:proton/Sent/**'
    ${nm} tag +draft -inbox -unread -- 'path:proton/Drafts/**'
    ${nm} tag +trash -inbox -unread -- 'path:proton/Trash/**'
    ${nm} tag +spam -inbox -unread -- 'path:proton/Spam/**'
    ${nm} tag +archive -inbox -- 'path:proton/Archive/**'
    # Disabled Gmail folder state tags:
    # ${nm} tag +inbox -- 'path:gmail-business/inbox/** OR path:gmail-personal/inbox/**'
    # ${nm} tag +sent  -- 'path:gmail-business/[Gmail]/Sent\ Mail/** OR path:gmail-personal/[Gmail]/Sent\ Mail/**'
    # ${nm} tag +draft -- 'path:gmail-business/[Gmail]/Drafts/** OR path:gmail-personal/[Gmail]/Drafts/**'
    # ${nm} tag +trash -- 'path:gmail-business/[Gmail]/Trash/** OR path:gmail-personal/[Gmail]/Trash/**'
    # ${nm} tag +spam  -- 'path:gmail-business/[Gmail]/Spam/** OR path:gmail-personal/[Gmail]/Spam/**'
  '';

  # Proton Labels → notmuch tags (dynamic discovery)
  # Bridge exposes labels as IMAP folders under "Labels/"; mbsync syncs them to
  # proton/Labels/<name>/. notmuch deduplicates by Message-ID so a message in
  # both proton/inbox/ and proton/Labels/finance/ becomes one indexed entry with
  # both +inbox and +finance tags — labels are additive, not exclusive.
  #
  # Dynamic approach: scan proton/Labels/ at runtime so new Proton labels are
  # auto-discovered without needing a NixOS rebuild.
  protonLabelTags = ''
    # Dynamic Proton label → notmuch tag mapping
    # Scans proton/Labels/<name>/ directories; skips Bridge's _underscore mirrors
    _LABELS_DIR="$HOME/400_mail/Maildir/proton/Labels"
    if [ -d "$_LABELS_DIR" ]; then
      for _ldir in "$_LABELS_DIR"/*/; do
        [ -d "$_ldir" ] || continue
        _lname=$(basename "$_ldir")
        # Skip Bridge's underscore-prefixed internal mirror folders
        case "$_lname" in _*) continue ;; esac
        # Special case: eriqueokeefe folder → gmail-personal tag
        if [ "$_lname" = "eriqueokeefe" ]; then
          ${nm} tag +gmail-personal -- "path:proton/Labels/eriqueokeefe/**"
        else
          ${nm} tag "+$_lname" -- "path:proton/Labels/$_lname/**"
        fi
        # hide label also removes inbox
        if [ "$_lname" = "hide" ]; then
          ${nm} tag -inbox -- "path:proton/Labels/hide/**"
        fi
      done
    fi
  '';

  tail = rulesPatched + "\n" + accountTags + protonLabelTags + extra;
in
{
  text = head + "\n" + body + "\n" + tail;
}
