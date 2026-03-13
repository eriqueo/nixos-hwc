{ lib, pkgs, config, osConfig ? {}, ... }:
let
  common    = import ../../../mail/parts/common.nix { inherit lib; };
  accounts  = config.hwc.home.mail.accounts or {};
  accVals   = lib.attrValues accounts;
  themePart = import ./theme.nix { inherit lib config; };

  maildirBase =
    let nmRoot = config.hwc.home.mail.notmuch.maildirRoot or "";
        pathBase = config.hwc.paths.user.mail or "${config.home.homeDirectory}/400_mail";
    in if nmRoot != "" then nmRoot else "${pathBase}/Maildir";

  # ── Query maps (unchanged — perfect) ─────────────────────────────────────
  queriesUnified = '' ... your existing queriesUnified ... '';
  mkLabelQueries = label: '' ... your existing ... '';

  mkLabelAccount = { name, from, outgoing }:
    let qmPath = "${config.home.homeDirectory}/.config/aerc/notmuch-queries-${name}";
    in ''
      [${name}]
      source              = notmuch://${maildirBase}
      maildir-store       = ${maildirBase}
      folders-exclude     = ~^\\..*,~^proton$,~^gmail-business$,~^gmail-personal$
      multi-file-strategy = act-one-delete-rest
      query-map           = ${qmPath}
      from                = ${from}
      outgoing            = exec:msmtp -a ${outgoing}
      default             = inbox
    '';

  unifiedAccount = '' ... your existing ... '';
  workLabelAccount    = mkLabelAccount { name = "work";     from = "..."; outgoing = "proton-hwc"; };
  financeAccount      = mkLabelAccount { name = "finance";  ... };
  coachingAccount     = mkLabelAccount { name = "coaching"; ... };
  personalLabelAcct   = mkLabelAccount { name = "personal"; ... };

  accountsConf = lib.concatStringsSep "\n" [ unifiedAccount workLabelAccount financeAccount coachingAccount personalLabelAcct ];
  accountsFile = pkgs.writeText "aerc-accounts.conf" accountsConf;

  # ── Clean styleset generation (already correct) ───────────────────────────
  stylesetConf = let
    tokens       = themePart.tokens;
    viewerTokens = themePart.viewerTokens;
    userTokens   = themePart.userTokens;
    renderStyle  = name: style: "${name}.fg = ${style.fg}\n${name}.bg = ${style.bg}\n${name}.bold = ${if style.bold then "true" else "false"}";

    mainSection   = lib.concatStringsSep "\n" (lib.mapAttrsToList renderStyle tokens);
    viewerSection = "[viewer]\n" + lib.concatStringsSep "\n" (lib.mapAttrsToList renderStyle viewerTokens);
    userSection   = "[user]\n"   + lib.concatStringsSep "\n" (lib.mapAttrsToList renderStyle userTokens);
  in lib.concatStringsSep "\n\n" [ mainSection viewerSection userSection ];

  # ── Modern aerc.conf (0.21+ best practices) ───────────────────────────────
  aercConf = ''
    [general]
    enable-osc8 = true
    # address-book-cmd = ${pkgs.abook}/bin/abook --mutt-query "%s"   # uncomment if you want abook

    [ui]
    index-columns = date<12,name<17,flags>4,tags<16,subject<*
    column-headers = true
    threading-enabled = true
    confirm-quit = false
    styleset-name = hwc-theme
    dirlist-tree = true
    dirlist-collapse = 1
    dirlist-exclude = ^\..*
    mouse-enabled = true
    fuzzy-complete = true

    # ── Powerful live templates ───────────────────────────────────────────
    column-date    = {{.DateAutoFormat .Date.Local}}
    column-name    = {{index (.From | names) 0}}
    column-flags   = {{.Flags | join ""}}
    column-subject = {{.ThreadPrefix}}{{if .ThreadFolded}}[{{.ThreadCount}}]{{end}}{{.Subject}}
    column-tags    = {{.StyleMap .Labels
        (exclude "inbox") (exclude "unread") (exclude "new") (exclude "sent")
        (exclude "draft") (exclude "trash") (exclude "spam") (exclude "archive")
        (exclude "flagged") (exclude "replied") (exclude "passed")
        (case "finance" "finance") (case "bank" "bank") (case "insurance" "insurance")
        (case "work" "work") (case "coaching" "coaching") (case "hwcmt" "hwcmt")
        (case "personal" "personal") (case "gmail-personal" "personal")
        (case "tech" "tech") (case "hide" "hide")
        (case "action" "action") (case "starred" "starred")
        (default "default")
      | join " " }}

    # Dashboard statusline + tab titles
    statusline = {{.Account}} | {{.StatusInfo}} | {{humanReadable .Unread}} unread | {{.TrayInfo}}
    tab-title-account = {{.Account}}{{if .HasNew}} 🛎️{{.Unread}}{{end}}

    [viewer]
    pager = ${pkgs.ov}/bin/ov -F --wrap --hscroll-width 10%
    alternatives = text/plain,text/html

    [compose]
    editor = ${pkgs.kitty}/bin/kitty -e ${pkgs.neovim}/bin/nvim
    # format = {{.Signature}}   # add templates/new_message later

    [filters]
    # your excellent filters — unchanged (keep everything)

    [hooks]
    new-email      = exec notify-send "New Email" "{{.From}} - {{.Subject}}"
    tag-modified   = exec notify-send "Tag changed" "{{.Subject}} → {{.AddedTags}}"

    [openers]
    # your excellent openers — unchanged
  '';
in
{
  files = profileBase: {
    ".config/aerc/aerc.conf".text = aercConf;
    ".config/aerc/stylesets/hwc-theme".text = stylesetConf;
    ".config/aerc/notmuch-queries-unified".text  = queriesUnified;
    ".config/aerc/notmuch-queries-work".text     = mkLabelQueries "work";
    ".config/aerc/notmuch-queries-finance".text  = mkLabelQueries "finance";
    ".config/aerc/notmuch-queries-coaching".text = mkLabelQueries "coaching";
    ".config/aerc/notmuch-queries-personal".text = mkLabelQueries "gmail-personal";

    # NEW: compose templates
    ".config/aerc/templates/new_message".text = ''
      {{.Signature}}
      -- 
      Sent from aerc (https://aerc-mail.org)
    '';
    ".config/aerc/templates/quoted_reply".text = ''
      On {{.DateAutoFormat .OriginalDate.Local}}, {{index (.OriginalFrom | names) 0}} wrote:

      {{quote .OriginalText}}
    '';
  };

  packages = with pkgs; [ aerc msmtp isync notmuch urlscan abook ripgrep ... your list ... ];

  inherit accountsFile;
}
