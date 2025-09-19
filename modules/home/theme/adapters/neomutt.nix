# modules/home/theme/adapters/neomutt.nix
# Adapter: palette -> NeoMutt color configuration
# modules/home/theme/adapters/neomutt.nix
{ lib, config, palette ? null, ... }:

let
  # Prefer explicit palette; else global; else {}
  T = if palette != null then palette else (config.hwc.home.theme or {});
  C = T.colors or T;

  # Map hex → terminal color names (fallbacks are terminal names)
  toNeomuttColor = semanticColor: fallback:
    let
      colorMap = {
        "ECEFF4" = "white";        # fg
        "2e3440" = "black";        # bg
        "BF616A" = "red";          # crit
        "A3BE8C" = "green";         # good
        "EBCB8B" = "yellow";        # warn
        "7daea3" = "cyan";          # accent
        "81A1C1" = "blue";          # info
        "d3869b" = "magenta";       # accentAlt
        "4C566A" = "brightblack";   # muted
        "d8dee9" = "brightwhite";   # fgDim
      };
      normalized = lib.removePrefix "#" (toString semanticColor);
    in if colorMap ? ${normalized} then colorMap.${normalized} else fallback;
in
{
  colors = {
    # ---------- core ----------
   normal     = { fg = toNeomuttColor (C.fg or "ECEFF4") "white";        bg = "default"; };
   attachment = { fg = toNeomuttColor (C.warn or "EBCB8B") "yellow";      bg = "default"; };
   hdrdefault = { fg = toNeomuttColor (C.accent2 or C.accent or "7daea3") "cyan"; bg = "default"; };                 
   indicator  = { fg = toNeomuttColor (C.bg or "2e3440") "black";          bg = toNeomuttColor (C.accent or "7daea3") "green"; };
    markers    = { fg = toNeomuttColor (C.crit or "BF616A") "red";         bg = "default"; };
    quoted     = { fg = toNeomuttColor (C.good or "A3BE8C") "green";       bg = "default"; };
    signature  = { fg = toNeomuttColor (C.fgDim or C.muted or "4C566A") "brightblack"; bg = "default"; };
    status     = { fg = toNeomuttColor (C.fg or "ECEFF4") "white";
                   bg = toNeomuttColor (C.info or "81A1C1") "blue"; };
    tilde      = { fg = toNeomuttColor (C.info or "81A1C1") "brightblue";  bg = "default"; };
    tree       = { fg = toNeomuttColor (C.accent or "7daea3") "green";     bg = "default"; };
    search     = { fg = toNeomuttColor (C.accentAlt or "d3869b") "magenta"; bg = "default"; };

    # ---------- index accents ----------
    indexNew    = { fg = toNeomuttColor (C.warn  or "EBCB8B") "yellow";  bg = "default"; };
    indexFlag   = { fg = toNeomuttColor (C.accent or "7daea3") "cyan";   bg = "default"; };
    indexDel    = { fg = toNeomuttColor (C.crit  or "BF616A") "red";     bg = "default"; };
    indexToMe   = { fg = toNeomuttColor (C.good  or "A3BE8C") "green";   bg = "default"; };
    indexFromMe = { fg = toNeomuttColor (C.info  or "81A1C1") "blue";    bg = "default"; };

    # ---------- per-column colors ----------
    index_number  = { fg = toNeomuttColor (C.muted     or "4C566A") "brightblack"; bg = "default"; };
    index_flags   = { fg = toNeomuttColor (C.warn      or "EBCB8B") "yellow";      bg = "default"; };
    index_date    = { fg = toNeomuttColor (C.info      or "81A1C1") "blue";        bg = "default"; };
    index_author  = { fg = toNeomuttColor (C.good      or "A3BE8C") "green";       bg = "default"; };
    index_size    = { fg = toNeomuttColor (C.accentAlt or "4C566A") "brightblack";     bg = "default"; };
    index_subject = { fg = toNeomuttColor (C.fg        or "ECEFF4") "white";       bg = "default"; };

    # ---------- sidebar ----------
    sidebar_ordinary  = { fg = toNeomuttColor (C.fgDim or "d8dee9") "brightwhite"; bg = "default"; };
    sidebar_highlight = { fg = toNeomuttColor (C.bg or "2e3440") "black";
                          bg = toNeomuttColor (C.accent or "7daea3") "cyan"; };
    sidebar_divider   = { fg = toNeomuttColor (C.info or "81A1C1") "blue";  bg = "default"; };
    sidebar_flagged   = { fg = toNeomuttColor (C.accentAlt or "d3869b") "magenta"; bg = "default"; };
    sidebar_new       = { fg = toNeomuttColor (C.warn or "EBCB8B") "yellow"; bg = "default"; };
  };
}
