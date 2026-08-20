{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.books;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  options.hwc.media.books = {
    enable = lib.mkEnableOption "LazyLibrarian books management container";

    image = lib.mkOption {
      type = lib.types.str;
      default = "lscr.io/linuxserver/lazylibrarian:latest";
      description = "Container image for LazyLibrarian";
    };

    network.mode = lib.mkOption {
      type = lib.types.enum [ "media" "vpn" ];
      default = "media";
      description = "Network mode: media or vpn (through Gluetun)";
    };

    gpu.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable GPU support (not typically needed for LazyLibrarian)";
    };

    httpRoot = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        HTTP root path for reverse proxy. Empty is correct for the current
        name-based vhost (books.<vhostDomain>), where LazyLibrarian serves at
        root. A non-empty value makes it 404 everything at "/", so it must
        change in the same commit as the route mode, never before or after.
      '';
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = helpers.mkVpnAssertions {
      name = "books";
      networkMode = cfg.network.mode;
      gluetunInstances = config.hwc.networking.gluetun.instances;
    };
  };
}
