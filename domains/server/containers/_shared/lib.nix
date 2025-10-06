{ lib, config, pkgs, ... }:
let
  inherit (lib) mkOption mkEnableOption types mkIf mkDefault mkMerge concatLists concatStringsSep;
in
{
  options.hwc.services.shared = {
    # accumulator used by services to publish reverse proxy routes
    routes = mkOption {
      internal = true;
      type = types.listOf (types.attrsOf types.anything);
      default = [];
      description = "Aggregated reverse proxy routes (service-provided).";
    };
  };

  # exported helpers - NOW PURE (no config reads)
  config.hwc.services.shared.lib = rec {
    mkBoolOption = { default ? false, description ? "" }:
      mkOption { type = types.bool; inherit default description; };

    mkImageOption = { default, description ? "" }:
      mkOption { type = types.str; inherit default description; };

    mkPathOption = { default ? null, description ? "" }:
      mkOption { type = types.nullOr types.path; inherit default description; };

    mkRoute = { path, upstream, stripPrefix ? false }:
      { inherit path upstream stripPrefix; };

    # PURE: accepts GPU mode and timezone as arguments
    mkContainer = {
      name, image, networkMode ? "media", gpuEnable ? true,
      gpuMode ? "intel", timeZone ? "UTC",
      ports ? [], volumes ? [], environment ? {}, extraOptions ? [], dependsOn ? []
    }:
    let
      podmanNetworkOpts =
        if networkMode == "vpn"
        then [ "--network=container:gluetun" ]
        else [ "--network=media-network" ];
      gpuOpts =
        if (!gpuEnable) then []
        else if gpuMode == "cuda" then [
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
          "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
          "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
          "--device=/dev/dri:/dev/dri:rwm"
        ] else [
          "--device=/dev/dri:/dev/dri"
        ];
      baseEnv = {
        PUID = "1000";
        PGID = "1000";
        TZ = timeZone;
      };
    in
    {
      virtualisation.oci-containers.containers.${name} = {
        inherit image dependsOn;
        autoStart = true;
        environment = baseEnv // environment;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ extraOptions
          ++ [ "--memory=2g" "--cpus=1.0" "--memory-swap=4g" ];
        ports = ports;
        volumes = volumes;
      };
    };
  };
}
