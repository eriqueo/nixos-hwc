# modules/home/theme/adapters/waybar-css.nix
{ }:
let
  palette = import ../palettes/deep-nord.nix {};
in {
  css = ''
    :root {
      /* base tokens */
      --bg: ${palette.bg};
      --bg-alt: ${palette.bgAlt};
      --bg-dark: ${palette.bgDark};
      --fg: ${palette.fg};
      --muted: ${palette.muted};

      --accent: ${palette.accent};
      --accent-alt: ${palette.accentAlt};

      --good: ${palette.good};
      --warn: ${palette.warn};
      --crit: ${palette.crit};

      /* convenience shades (hex with alpha AA=~67%, CC=~80%, E6=~90%) */
      --bg-90: ${palette.bg}E6;
      --bg-80: ${palette.bg}CC;
      --bg-67: ${palette.bg}AA;

      --panel: var(--bg-90);
      --panel-border: ${palette.muted};
      --chip: var(--bg-alt);
      --chip-border: ${palette.muted};

      --ok: var(--good);
      --warn-fg: #1a1a1a;
      --crit-fg: #1a1a1a;
    }

    /* bar frame */
    #waybar {
      background: var(--panel);
      color: var(--fg);
      border-bottom: 1px solid var(--panel-border);
      font-family: "Inter", "CaskaydiaCove Nerd Font", monospace;
      font-size: 12.5pt;
    }

    /* modules look like kitty’s chips: rounded, subtle border, same fg/bg */
    .modules-left > widget,
    .modules-center > widget,
    .modules-right > widget,
    .module {
      background: var(--chip);
      color: var(--fg);
      border: 1px solid var(--chip-border);
      border-radius: 10px;
      padding: 6px 10px;
      margin: 4px 6px;
    }

    /* accent states */
    .module:hover { border-color: var(--accent); }
    .warning { color: var(--warn); }
    .critical { color: var(--crit); }

    /* workspace pills */
    #workspaces button {
      background: var(--chip);
      color: var(--fg);
      border: 1px solid var(--chip-border);
      border-radius: 10px;
      padding: 4px 10px;
      margin: 2px 3px;
    }
    #workspaces button.active {
      background: var(--accent);
      color: var(--bg);
      border-color: var(--accent);
    }
    #workspaces button.urgent {
      background: var(--crit);
      color: var(--crit-fg);
      border-color: var(--crit);
    }

    /* battery */
    #battery.charging { color: var(--accent-alt); }
    #battery.warning { color: var(--warn); }
    #battery.critical { color: var(--crit); }

    /* pulseaudio */
    #pulseaudio.muted { color: var(--muted); }

    /* tooltip (matches kitty’s panel) */
    tooltip {
      background: var(--panel);
      color: var(--fg);
      border: 1px solid var(--panel-border);
    }
  '';
}
