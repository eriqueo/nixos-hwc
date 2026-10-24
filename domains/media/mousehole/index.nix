# domains/media/mousehole/index.nix
{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.mousehole;
  # Temporary same-app correction. Retire after an upstream image passes actual
  # Bun trust, existing-state, frontend and compatible-current-data recovery checks.
  runtime = helpers.mkRuntimeImage {
    name = "mousehole";
    version = "0.2.0-bun1.4.4";
    recipe = ''
      FROM docker.io/oven/bun@sha256:b740c3f5600e6360684f240d31c67ffb759def968bfa98ed98c4cce970707735 AS secure-bun
      FROM docker.io/tmmrtn/mousehole@sha256:9adfcfddb3395d33f0fbef50a6dc52a930769c57f2c0af2b3b9d6f7bfda6195c
      COPY --from=secure-bun /usr/local/bin/bun /usr/local/bin/bun
    '';
  };
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.mousehole = {
    enable = lib.mkEnableOption "Mousehole - MyAnonamouse seedbox IP updater";
    image = lib.mkOption { type = lib.types.str; default = "docker.io/tmmrtn/mousehole@sha256:5d4ec733d7eb9c20300f7976da4f4778e744b4089969bdd0478d3c4b2353420a"; description = "Original compatible image for availability recovery against current state"; };
    port = lib.mkOption { type = lib.types.int; default = 5010; description = "Port for Mousehole web UI"; };
    checkInterval = lib.mkOption { type = lib.types.int; default = 300; description = "Interval in seconds between IP checks"; };
    staleResponseSeconds = lib.mkOption { type = lib.types.int; default = 86400; description = "How long a MAM response is considered valid"; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.mouseholeRuntimeImageRecipe = runtime.dockerfile;
    # Prebuild the reviewed image outside startup; explicit recovery overrides work.
    systemd.services.podman-mousehole.preStart = lib.mkIf (cfg.image == runtime.image) ''
      if ! ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg cfg.image}; then
        echo "Prebuild Mousehole using ${runtime.dockerfile} before activation" >&2
        exit 1
      fi
    '';

    # Container definition is in sys.nix
    # Service dependencies are in parts/config.nix

    #==========================================================================
    # VALIDATION
    #==========================================================================
    # mousehole has no network.mode option — it is unconditionally a passenger
    # of the main tunnel (sys.nix pins networkMode = "vpn").
    assertions = helpers.mkVpnAssertions {
      name = "mousehole";
      networkMode = "vpn";
      gluetunInstances = config.hwc.networking.gluetun.instances;
    };
  };
}
