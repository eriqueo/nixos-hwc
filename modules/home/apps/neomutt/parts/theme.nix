# modules/home/apps/neomutt/parts/theme.nix
# Adapter: palette → NeoMutt color tokens (names only; no regex/rules/layout here)
{ config, lib, ... }:

let
  cfg = config.features.neomutt or {};
  # palette resolution: per-app override > global theme
  paletteName =
    if (cfg ? theme && cfg.theme ? palette && cfg.theme.palette != null) then cfg.theme.palette
    else (config.hwc.home.theme.name or "deep-nord");

  # import the chosen palette (must match your repo layout)
  palettesBase = ../../.. + "/theme/palettes";
  palettePath  = palettesBase + ("/" + paletteName + ".nix");
  P            = import palettePath {};

  # Helpers ----------------------------------------------------------

  # Restrict to NeoMutt's named color vocabulary.
  # We don't compute 256 indexes here; we map palette roles to sane names.
  roleToName = {
    red         = "red";
    brightRed   = "brightred";
    green       = "green";
    brightGreen = "brightgreen";
    yellow      = "yellow";
    brightYellow= "brightyellow";
    blue        = "blue";
    brightBlue  = "brightblue";
    magenta     = "magenta";
    brightMagenta = "brightmagenta";
    cyan        = "cyan";
    brightCyan  = "brightcyan";
    black       = "black";
    brightBlack = "brightblack";
    white       = "white";
    brightWhite = "brightwhite";
    default     = "default";
  };

  # Map palette roles → named colors used by NeoMutt style.
  # This is the only “semantics → name” bridge; palettes stay pure hex.
  # Tweak these if you want a different vibe per app.
  pick = {
    # core roles
    fg           = roleToName.white;
    fgDim        = roleToName.brightWhite;
    bg           = roleToName.black;
    muted        = roleToName.brightBlack;

    good         = roleToName.green;
    warn         = roleToName.yellow;
    crit         = roleToName.red;
    info         = roleToName.blue;

    accent       = roleToName.cyan;
    accentAlt    = roleToName.magenta;
    accent2      = roleToName.brightBlue;

    selectionFg  = roleToName.black;
    selectionBg  = roleToName.cyan;

    # bright variants
    b_good       = roleToName.brightGreen;
    b_warn       = roleToName.brightYellow;
    b_crit       = roleToName.brightRed;
    b_info       = roleToName.brightBlue;
    b_accent     = roleToName.brightCyan;
    b_accentAlt  = roleToName.brightMagenta;
    b_fg         = roleToName.brightWhite;
  };

  token = fg: bg: { inherit fg bg; };
in
{
  # Expose a flat token set consumed by appearance.nix
  tokens = {
    # ---- Index defaults (message list) ----
    index_default = token pick.warn roleToName.default;          # color index yellow default '.*'
    index_author  = token pick.crit roleToName.default;          # color index_author red default '.*'
    index_number  = token pick.info roleToName.default;          # color index_number blue default
    index_subject = token pick.accent roleToName.default;        # color index_subject cyan default '.*'

    # New (~N)
    index_new_default = token pick.b_warn pick.bg;               # brightyellow on bg
    index_new_author  = token pick.b_crit pick.bg;               # brightred on bg
    index_new_subject = token pick.b_accent pick.bg;             # brightcyan on bg

    # ---- Header colors (pager) ----
    hdr_default = token pick.info roleToName.default;            # blue default ".*"
    hdr_from    = token pick.b_accentAlt roleToName.default;     # brightmagenta default "^(From)"
    hdr_subject = token pick.b_accent roleToName.default;        # brightcyan default "^(Subject)"
    hdr_ccbcc   = token pick.b_fg roleToName.default;            # brightwhite default "^(CC|BCC)"

    # ---- Core UI ----
    normal          = token roleToName.default roleToName.default
                      // {};  # keep terminal default text/ground
    indicator       = token pick.muted roleToName.white;         # brightblack on white (selected line)
    sidebar_highlight = token pick.crit roleToName.default;
    sidebar_divider   = token pick.muted pick.bg;
    sidebar_flagged   = token pick.crit pick.bg;
    sidebar_new       = token pick.good pick.bg;

    error           = token pick.crit roleToName.default;
    tilde           = token roleToName.black roleToName.default;
    message         = token pick.accent roleToName.default;
    markers         = token pick.crit roleToName.white;
    attachment      = token roleToName.white roleToName.default;
    search          = token pick.b_accentAlt roleToName.default;
    status          = token pick.b_warn pick.bg;                 # brightyellow on bg
    hdrdefault      = token pick.good roleToName.default;

    quoted0         = token pick.good roleToName.default;
    quoted1         = token pick.info roleToName.default;
    quoted2         = token pick.accent roleToName.default;
    quoted3         = token pick.warn roleToName.default;
    quoted4         = token pick.crit roleToName.default;
    quoted5         = token pick.b_crit roleToName.default;

    signature       = token pick.good roleToName.default;

    boldTok         = token roleToName.black roleToName.default;
    underlineTok    = token roleToName.black roleToName.default;

    # ---- Body regex categories ----
    body_email      = token pick.b_crit roleToName.default;
    body_url        = token pick.b_info roleToName.default;
    body_code       = token pick.good roleToName.default;

    body_h1         = token pick.b_info roleToName.default;
    body_h2         = token pick.b_accent roleToName.default;
    body_h3         = token pick.b_good roleToName.default;
    body_listitem   = token pick.warn roleToName.default;

    body_emote      = token pick.b_accent roleToName.default;

    body_sig_bad    = token pick.crit roleToName.default;        # "(BAD signature)"
    body_sig_good   = token pick.accent roleToName.default;      # "(Good signature)"
    body_gpg_goodln = token pick.muted roleToName.default;       # "^gpg: Good signature .*"
    body_gpg_anyln  = token pick.b_warn roleToName.default;      # "^gpg: "
    body_gpg_badln  = token pick.b_warn pick.crit;               # "^gpg: BAD signature from.*"

    # ---- Columnized index colors (optional; used if you enable per-column) ----
    col_number  = token pick.muted roleToName.default;
    col_flags   = token pick.warn roleToName.default;
    col_date    = token pick.info roleToName.default;
    col_author  = token pick.good roleToName.default;
    col_size    = token pick.accentAlt roleToName.default;
    col_subject = token pick.fg roleToName.default;
  };

  # Mono/attribute mapping requested by the imported style
  mono = {
    bold       = "bold";
    underline  = "underline";
    indicator  = "reverse";
    error      = "bold";
  };
}
