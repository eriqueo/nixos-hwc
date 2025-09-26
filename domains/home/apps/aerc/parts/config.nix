{ lib, pkgs, config, ... }:
let
  common   = import ../../../domains/home/mail/parts/common.nix { inherit lib; };
  accounts = config.hwc.home.mail.accounts or {};
  accVals  = lib.attrValues accounts;

  # notmuch DB lives at ~/Maildir in your stack
  notmuchSource = "notmuch://?database-path=${config.home.homeDirectory}/Maildir";

  # derive “Sent” and “Drafts” folder paths for copy-to/postpone
  sentFolder   = a: let r = common.rolesFor a; in lib.head (r.sent);
  draftsFolder = a: let r = common.rolesFor a; in lib.head (r.drafts);

  accountBlock = a: ''
    [${a.name}]
    default  = ${if (a.primary or false) then "true" else "false"}
    from     = ${a.realName or ""} <${a.address}>
    source   = ${notmuchSource}
    outgoing = exec:msmtp -a ${a.send.msmtpAccount}
    postpone = maildir://${config.home.homeDirectory}/Maildir/${draftsFolder a}
    copy-to  = maildir://${config.home.homeDirectory}/Maildir/${sentFolder a}
  '';

  accountsConf = lib.concatStringsSep "\n\n" (map accountBlock accVals);

  aercConf = ''
    [ui]
    index-columns=From,Subject,Date
    threading-enabled=true
    confirm-quit=false
    check-mail-cmd=mbsync -a
    check-mail-timeout=0

    [viewer]
    pager=${pkgs.less}/bin/less -R

    [compose]
    editor=${pkgs.kitty}/bin/kitty -e ${pkgs.neovim}/bin/nvim
  '';
in
{
  files = profileBase: {
    ".config/aerc/aerc.conf".text = aercConf;
    ".config/aerc/accounts.conf".text = accountsConf;
  };

  # Install aerc (and helpers) via your session part
  packages = with pkgs; [ aerc msmtp isync notmuch urlscan abook w3m ripgrep ];
}
