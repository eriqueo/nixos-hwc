# modules/home/theme/palettes/gruv.nix
{ }:
{
  name = "gruv";

  # Neutrals
  bg       = "282828";
  bgAlt    = "3b4252";
  bgDark   = "0B1115";
  surface0 = "2f3541";
  surface1 = "343b49";
  surface2 = "394152";

  # Foregrounds
  fg    = "d4be98";
  fgDim = "d8dee9";
  muted = "4C566A";

  # Accents / status
  accent    = "7daea3";   # teal
  accentAlt = "d3869b";   # magenta-ish
  accent2   = "88c0d0";   # frost blue

  good = "a9b665";
  warn = "d8a657";
  crit = "ea6962";
  info = "81A1C1";

  # UI roles
  selectionFg = "282828";
  selectionBg = "7daea3";
  cursorColor = "d4be98";
  caret       = "d4be98";
  link        = "88c0d0";
  border      = "434C5E";
  borderDim   = "3b4252";

  # ANSI 16
  ansi = {
    black="32302F"; red="ea6962"; green="a9b665"; yellow="d8a657";
    blue="7daea3"; magenta="d3869b"; cyan="89b482"; white="d4be98";

    brightBlack="45403d"; brightRed="ea6962"; brightGreen="a9b665";
    brightYellow="d8a657"; brightBlue="7daea3"; brightMagenta="d3869b";
    brightCyan="89b482"; brightWhite="d4be98";
  };

  alpha = { opaque="ff"; strong="cc"; soft="aa"; faint="66"; };

  hypr = { teal="7daea3"; green="89b482"; muted="45403d"; };

  # Cursor block to match deep-nord structure (used by other adapters)
  cursor = {
    size = 24;
    xcursor = { name = "Nordzy-cursors"; package = "nordzy-cursor-theme"; };
    hyprcursor = {
      name = "Nordzy-hyprcursors";
      assetPathRel = "modules/home/theme/assets/cursors/Nordzy-hyprcursors";
    };
  };
}
