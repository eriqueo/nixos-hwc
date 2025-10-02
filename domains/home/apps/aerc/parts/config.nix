{ lib, pkgs, config, ... }:
let
  common    = import ../../../mail/parts/common.nix { inherit lib; };
  accounts  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues accounts;
  themePart = import ./theme.nix { inherit lib config; };
  notmuchSource = "notmuch://${config.home.homeDirectory}/Maildir";
  maildirBase   = "maildir://${config.home.homeDirectory}/Maildir";
  
  sentFolder    = a: let r = common.rolesFor a; in lib.head (r.sent);
  draftsFolder  = a: let r = common.rolesFor a; in lib.head (r.drafts);
  accountRoot   = a: common.md a;
  

  accountBlock = a: ''
    [${a.name}]
    from                 = ${a.realName or ""} <${a.address}>
    source               = ${maildirBase}/${accountRoot a}
    outgoing             = exec:msmtp -a ${a.send.msmtpAccount}
    postpone             = ${maildirBase}/${draftsFolder a}
    copy-to              = ${maildirBase}/${sentFolder a}
  '';
    
  accountsConf = lib.concatStringsSep "\n\n" (map accountBlock accVals);
  
  stylesetConf = let
    tokens = themePart.tokens;
    viewerTokens = themePart.viewerTokens;
    renderStyle = name: style:
      "${name}.fg = ${style.fg}\n${name}.bg = ${style.bg}\n${name}.bold = ${if style.bold then "true" else "false"}";
    mainStyleLines = lib.mapAttrsToList renderStyle tokens;
    mainSection = lib.concatStringsSep "\n" mainStyleLines;
    viewerStyleLines = lib.mapAttrsToList renderStyle viewerTokens;
    viewerSection = "[viewer]\n" + (lib.concatStringsSep "\n" viewerStyleLines);
  in mainSection + "\n\n" + viewerSection;
  
 aercConf = ''
    [ui]
    index-columns=date<20,name<17,flags>4,subject<*
    threading-enabled=true
    confirm-quit=false
    styleset-name=hwc-theme
    dirlist-tree=true
    dirlist-collapse=1
    column-date = {{.DateAutoFormat .Date.Local}}
    column-name = {{index (.From | names) 0}}
    column-flags = {{.Flags | join ""}}
    column-subject = {{.ThreadPrefix}}{{.Subject}}
    [viewer]
    pager=${pkgs.less}/bin/less -R
    [compose]
    editor=${pkgs.kitty}/bin/kitty -e ${pkgs.neovim}/bin/nvim
  '';
in
{
  files = profileBase:{ 
      ".config/aerc/aerc.conf".text = aercConf;
      ".config/aerc/accounts.conf.source".text = accountsConf;
      ".config/aerc/stylesets/hwc-theme".text = stylesetConf;
    };
  packages = with pkgs; [ aerc msmtp isync notmuch urlscan abook w3m ripgrep ];
}
