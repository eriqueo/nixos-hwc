# domains/home/apps/tetro/index.nix
#
# tetro — terminal-based tetromino-stacking game (TUI). Unlike todui/khalt, this
# is a THIRD-PARTY upstream app (Strophox/tetro-tui) consumed as the `tetro`
# flake input, and it ships only a package — no reusable Home Manager module.
# So this module is the minimal inbound adapter: install the flake's prebuilt
# binary and publish a launcher entry. Nothing HWC-specific to translate (no
# theme/keymap surface on the app side yet).
#
# NAMESPACE: hwc.home.apps.tetro.*   (Charter Law 2: namespace = folder)
# USAGE:     hwc.home.apps.tetro.enable = true;   (set in profiles/desktop)

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.home.apps.tetro;
  tetroPkg = inputs.tetro.packages.${pkgs.system}.default;
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.home.apps.tetro = {
    enable = lib.mkEnableOption "tetro — terminal tetromino-stacking game (TUI)";
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [ tetroPkg ];

    # Launcher entry — tetro is a TUI, so host it in kitty (the session
    # terminal). Makes it appear in wofi/rofi `drun`; terminal = false because
    # `kitty -e` already supplies the window (mirrors domains/home/apps/todui).
    xdg.desktopEntries.tetro = {
      name = "Tetro";
      genericName = "Tetromino Game";
      comment = "Terminal-based modern tetromino-stacking game";
      exec = "kitty --class tetro-tui --title Tetro -e tetro-tui";
      terminal = false;
      categories = [ "Game" "BlocksGame" ];
      settings.StartupWMClass = "tetro-tui";
      settings.Keywords = "tetris;tetromino;blocks;puzzle;game;";
    };
  };
}
