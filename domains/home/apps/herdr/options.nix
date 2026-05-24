{ lib, ... }:

{
  options.hwc.home.apps.herdr = {
    enable = lib.mkEnableOption "herdr — terminal agent multiplexer (tmux for AI agents)";

    package = lib.mkOption {
      type        = lib.types.nullOr lib.types.package;
      default     = null;
      description = "Herdr package to use. If null, builds from upstream release binary via parts/package.nix.";
    };
  };
}
