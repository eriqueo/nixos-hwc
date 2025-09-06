# modules/home/theme/adapters/waybar-css.nix
{ }:
let
  palette = import ../palettes/deep-nord.nix {};
in {
  css = ''
    /* Palette → GTK/Waybar color tokens */
    @define-color bg        ${palette.bg};
    @define-color bg_alt    ${palette.bgAlt};
    @define-color bg_dark   ${palette.bgDark};

    @define-color fg        ${palette.fg};
    @define-color muted     ${palette.muted};

    @define-color accent    ${palette.accent};
    @define-color accentAlt ${palette.accentAlt};

    @define-color good      ${palette.good};
    @define-color warn      ${palette.warn};
    @define-color crit      ${palette.crit};
  '';
}
