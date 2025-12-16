{ lib, config, ... }:

let
  palette = config.hwc.home.theme.palette.tokens;
in
{
  userChrome = ''
    :root {
      --hwc-bg: ${palette.bg};
      --hwc-fg: ${palette.fg};
      --hwc-accent: ${palette.accent};
      --hwc-muted: ${palette.muted};
    }

    #TabsToolbar { background: var(--hwc-bg) !important; }
    #nav-bar { background: var(--hwc-bg) !important; }
    #urlbar, #searchbar { color: var(--hwc-fg) !important; }
  '';

  userContent = ''
    :root {
      --hwc-bg: ${palette.bg};
      --hwc-fg: ${palette.fg};
      --hwc-accent: ${palette.accent};
      --hwc-muted: ${palette.muted};
    }
  '';
}
