{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.home.mail.notmuch or {};
  # Defaults so the module is self-contained; your options.nix can still override.
  maildirRoot  = cfg.maildirRoot or "${config.home.homeDirectory}/Maildir";
  userName     = cfg.userName     or "eric okeefe";
  primaryEmail = cfg.primaryEmail or "eriqueo@proton.me";
  otherEmails  = cfg.otherEmails  or [ "eric@iheartwoodcraft.com" "eriqueokeefe@gmail.com" "heartwoodcraftmt@gmail.com" ];
  newTags      = cfg.newTags      or [ "unread" "inbox" ];

  mkSemi = xs: lib.concatStringsSep ";" xs;

  savedSearchesText = ''
    inbox=tag:inbox AND tag:unread
    action=tag:action AND tag:unread
    finance=tag:finance AND tag:unread
    newsletter=tag:newsletter AND tag:unread
    notifications=tag:notification AND tag:unread
    sent=tag:sent
    archive=tag:archive
  '';

  # NOTE: escape \[Gmail] for mbsync-style paths; notmuch matches plain strings.
  postNewHookText = ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Sent / Trash / Spam / Drafts / Archive tagging across providers
    notmuch tag +sent   -inbox -unread -- 'path:"proton/Sent" OR path:"gmail-*/[Gmail]/Sent Mail" OR path:"gmail-*/[Google Mail]/Sent Mail"'
    notmuch tag +trash  -inbox -unread -- 'path:"proton/Trash" OR path:"gmail-*/[Gmail]/Trash" OR path:"gmail-*/[Google Mail]/Trash"'
    notmuch tag +spam   -inbox -unread -- 'path:"proton/Spam"  OR path:"gmail-*/[Gmail]/Spam"  OR path:"gmail-*/[Google Mail]/Spam"'
    notmuch tag +draft  -inbox -unread -- 'path:"proton/Drafts" OR path:"gmail-*/[Gmail]/Drafts" OR path:"gmail-*/[Google Mail]/Drafts"'
    notmuch tag +archive        -inbox        -- 'path:"proton/Archive" OR path:"proton/All Mail" OR path:"gmail-*/[Gmail]/All Mail" OR path:"gmail-*/[Google Mail]/All Mail"'
  '';

  dashboardScript = ''
    #!/usr/bin/env bash
    set -euo pipefail
    printf "inbox (unread): %s\n" "$(notmuch count 'tag:inbox and tag:unread')"
    printf "sent:           %s\n" "$(notmuch count 'tag:sent')"
    printf "archive:        %s\n" "$(notmuch count 'tag:archive')"
    printf "drafts:         %s\n" "$(notmuch count 'tag:draft')"
    printf "spam:           %s\n" "$(notmuch count 'tag:spam')"
    printf "trash:          %s\n" "$(notmuch count 'tag:trash')"
  '';

in {
  # IMPORTANT: don’t gate this behind an extra enable unless you want to.
  config = {
    home.packages = [ pkgs.notmuch pkgs.ripgrep pkgs.coreutils pkgs.gnused ];

    programs.notmuch = {
      enable = true;
      new.tags = newTags;
      extraConfig = {
        database.path = maildirRoot;
        user = {
          name = userName;
          primary_email = primaryEmail;
          other_email = mkSemi otherEmails;
        };
        maildir.synchronize_flags = "true";
      };
      # Do NOT use hooks.postNew here; we write the real hook file below.
    };

    # Saved searches (declarative)
    xdg.configFile."notmuch/saved-searches".text = savedSearchesText;

    # Real post-new hook file at the path Notmuch will execute
    home.file."${maildirRoot}/.notmuch/hooks/post-new" = {
      text = postNewHookText;
      executable = true;
    };

    # Optional helper; toggle by an option if you prefer.
    home.file.".local/bin/mail-dashboard" = {
      text = dashboardScript;
      executable = true;
    };
  };
}
