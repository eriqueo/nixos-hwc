{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.home.apps.mtg;
in
{
  # OPTIONS
  options.hwc.home.apps.mtg = {
    enable = lib.mkEnableOption "Modern Terminal Games arcade collection";
    package = lib.mkOption {
      type = lib.types.package;
      description = "MTG launcher and its four terminal arcade games.";
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "modern-terminal-games";
        version = "0.7.0";
        src = inputs.mtg;
        cargoLock.lockFile = inputs.mtg + "/Cargo.lock";
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.alsa-lib ];
        cargoTestFlags = [ "--workspace" ];
        meta = {
          description = "Terminal Breaker, Paddle Battle, Snek and Alien Raid";
          homepage = "https://github.com/modern-terminal-games/mtg";
          license = lib.licenses.mit;
          mainProgram = "mtg";
        };
      };
    };
  };

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];
  };
}
