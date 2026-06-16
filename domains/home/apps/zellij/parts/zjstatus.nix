# domains/home/apps/zellij/parts/zjstatus.nix
#
# Pure function: palette colors + wasm path -> a zjstatus plugin KDL block that
# renders a themed TRUE-POWERLINE tab bar. Drops into the workbench layout's
# default_tab_template in place of the built-in `zellij:tab-bar` (which can't do
# powerline segments). Colors are baked from the ACTIVE theme, so the bar
# restyles on a `hwc.home.theme.palette` switch — same consume-contract as
# parts/appearance.nix (apps consume the palette, never define it).
#
# Look: each tab is a powerline segment ( left-cap …  right-cap) sitting on the
# bar background; inactive tabs use a muted fill, the active tab pops in `accent`
# (bold, dark text). Tune the token choices below to taste.

{ lib, colors, wasm }:

let
  # palette token -> "#rrggbb" (fallback keeps the bar valid if a token is absent)
  c = name: fallback: "#" + (colors.${name} or fallback);
  bg0    = c "bg0" "1d2021";   # bar background (matches the host)
  bg2    = c "bg2" "2c3338";   # inactive segment fill
  fg2    = c "fg2" "a7aaad";   # inactive segment text
  accent = c "accent" "d08770"; # active segment fill
  # Powerline caps (Nerd Font / powerline glyphs):  = U+E0B2 (left),  = U+E0B0 (right)
  capL = "";
  capR = "";
in
''
  plugin location="file:${wasm}" {
      format_left  "{tabs}"
      format_right ""
      format_space "#[bg=${bg0}]"
      hide_frame_for_single_pane "false"
      // inactive tab: muted segment with powerline caps into the bar bg
      tab_normal "#[fg=${bg2},bg=${bg0}]${capL}#[fg=${fg2},bg=${bg2}] {name} #[fg=${bg2},bg=${bg0}]${capR}"
      // active tab: accent segment, bold dark text, same caps
      tab_active "#[fg=${accent},bg=${bg0}]${capL}#[fg=${bg0},bg=${accent},bold] {name} #[fg=${accent},bg=${bg0}]${capR}"
  }
''
