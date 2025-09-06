# modules/home/theme/adapters/waybar-css.nix
{ }:
let
  palette = import ../palettes/deep-nord.nix {};
in {
  css = ''
    /* Base CSS vars from palette */
    :root {
      --bg: ${palette.bg};
      --bg-alt: ${palette.bgAlt};
      --fg: ${palette.fg};
      --muted: ${palette.muted};
      --accent: ${palette.accent};
      --accent-alt: ${palette.accentAlt};
      --good: ${palette.good};
      --warn: ${palette.warn};
      --crit: ${palette.crit};

      /* 16-color map (approx; feel free to refine from your expanded palette) */
      --color1:  ${palette.crit};
      --color2:  ${palette.good};
      --color3:  ${palette.warn};
      --color4:  ${palette.accent};
      --color5:  #d3869b;   /* magenta */
      --color6:  ${palette.accentAlt};
      --color7:  ${palette.fg};
      --color8:  ${palette.muted};
      --color9:  #ea6962;   /* bright red */
      --color10: #a9b665;   /* bright green */
      --color11: #d8a657;   /* bright yellow */
      --color12: #7daea3;   /* bright blue-ish teal */
      --color13: #d3869b;   /* bright magenta */
      --color14: #89b482;   /* bright cyan-ish green */
      --color15: #d4be98;   /* bright white */
    }

    /* GTK-style aliases so existing Waybar rules can use @name */
    @define-color background var(--bg);
    @define-color foreground var(--fg);
    @define-color muted      var(--muted);
    @define-color accent     var(--accent);
    @define-color accentAlt  var(--accent-alt);
    @define-color good       var(--good);
    @define-color warn       var(--warn);
    @define-color crit       var(--crit);

    @define-color color1  var(--color1);
    @define-color color2  var(--color2);
    @define-color color3  var(--color3);
    @define-color color4  var(--color4);
    @define-color color5  var(--color5);
    @define-color color6  var(--color6);
    @define-color color7  var(--color7);
    @define-color color8  var(--color8);
    @define-color color9  var(--color9);
    @define-color color10 var(--color10);
    @define-color color11 var(--color11);
    @define-color color12 var(--color12);
    @define-color color13 var(--color13);
    @define-color color14 var(--color14);
    @define-color color15 var(--color15);
  '';
}
