# modules/home/theme/adapters/neomutt.nix
# Adapter: palette -> NeoMutt color configuration
{ config, lib, ... }:

let
  # Palette resolver: support both {colors = {...}} and flat tokens
  T = config.hwc.home.theme or {};
  C = T.colors or T;

  # NeoMutt color mapping function
  # Maps semantic colors to appropriate NeoMutt terminal colors
  toNeomuttColor = semanticColor: fallback:
    let
      colorMap = {
        # Map hex colors to terminal color names
        "ECEFF4" = "white";      # fg
        "2e3440" = "black";      # bg  
        "BF616A" = "red";        # crit
        "A3BE8C" = "green";      # good
        "EBCB8B" = "yellow";     # warn
        "7daea3" = "cyan";       # accent
        "81A1C1" = "blue";       # info
        "d3869b" = "magenta";    # accentAlt
        "4C566A" = "brightblack"; # muted
        "d8dee9" = "brightwhite"; # fgDim
      };
      
      # Remove # prefix and normalize
      normalized = lib.removePrefix "#" (toString semanticColor);
    in
    if colorMap ? ${normalized} then colorMap.${normalized}
    else fallback;

in
{
  # NeoMutt color scheme using theme palette
  colors = {
    normal = {
      fg = toNeomuttColor (C.fg or "ECEFF4") "white";
      bg = "default";
    };
    attachment = {
      fg = toNeomuttColor (C.warn or "EBCB8B") "yellow";
      bg = "default";
    };
    hdrdefault = {
      fg = toNeomuttColor (C.accent2 or C.accent or "7daea3") "cyan";
      bg = "default";
    };
    indicator = {
      fg = toNeomuttColor (C.bg or "2e3440") "black";
      bg = toNeomuttColor (C.accent or "7daea3") "green";
    };
    markers = {
      fg = toNeomuttColor (C.crit or "BF616A") "red";
      bg = "default";
    };
    quoted = {
      fg = toNeomuttColor (C.good or "A3BE8C") "green";
      bg = "default";
    };
    signature = {
      fg = toNeomuttColor (C.fgDim or C.muted or "4C566A") "brightblack";
      bg = "default";
    };
    status = {
      fg = toNeomuttColor (C.fg or "ECEFF4") "white";
      bg = toNeomuttColor (C.info or "81A1C1") "blue";
    };
    tilde = {
      fg = toNeomuttColor (C.info or "81A1C1") "brightblue";
      bg = "default";
    };
    tree = {
      fg = toNeomuttColor (C.accent or "7daea3") "green";
      bg = "default";
    };
  };
}