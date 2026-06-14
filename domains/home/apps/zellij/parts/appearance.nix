# domains/home/apps/zellij/parts/appearance.nix
# Pure function: palette colors -> a zellij KDL `themes` block.
# No options, no side-effects (mirrors yazi/parts/appearance.nix).
#
# zellij theme keys take hex strings. We map the flat HWC token set onto
# zellij's named theme roles. Tokens are stored WITHOUT a leading '#', so we
# add it here.
{ lib, colors }:

let
  c = colors;
  hex = t: "#${t}";

  # Defensive: a machine with no theme yields colors = {}. Fall back to a
  # neutral token so eval never crashes (fail-soft at the boundary), matching
  # the "runs on built-in defaults" contract of the whole stack.
  pick = name: fallback: hex (c.${name} or fallback);

  bg0 = pick "bg0" "1d2021";
  bg1 = pick "bg1" "282828";
  bg2 = pick "bg2" "3c3836";
  fg0 = pick "fg0" "ebdbb2";
  fg1 = pick "fg1" "d4be98";
  accent  = pick "accent"  "7daea3";
  success = pick "success" "a9b665";
  warning = pick "warning" "d8a657";
  error   = pick "error"   "ea6962";
  marked  = pick "marked"  "d3869b";
  info    = pick "info"    "7daea3";
in
{
  # A single `themes { hwc { ... } }` KDL block. zellij's palette role names:
  #   fg bg black red green yellow blue magenta cyan white orange
  themeBlock = ''
    themes {
        hwc {
            fg "${fg1}"
            bg "${bg1}"
            black "${bg0}"
            red "${error}"
            green "${success}"
            yellow "${warning}"
            blue "${accent}"
            magenta "${marked}"
            cyan "${info}"
            white "${fg0}"
            orange "${warning}"
        }
    }
  '';
}
