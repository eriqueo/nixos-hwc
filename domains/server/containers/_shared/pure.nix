{ lib, pkgs }:

rec {
  mkContainer =
    { name
    , image
    , networkMode ? "media"
    , gpuEnable ? true
    , gpuMode ? "intel"
    , timeZone ? "UTC"
    , ports ? []
    , volumes ? []
    , environment ? {}
    , extraOptions ? []
    , dependsOn ? []
    , user ? null
    }:
    let
      podmanNetworkOpts =
        if networkMode == "vpn" then [ "--network=container:gluetun" ] else [ "--network=media-network" ];
      gpuOpts = if (!gpuEnable) then [] else [ "--device=/dev/dri:/dev/dri" ];
      baseEnv = { PUID = "1000"; PGID = "1000"; TZ = timeZone; };
    in {
      virtualisation.oci-containers.containers.${name} = {
        inherit image dependsOn user;
        autoStart = true;
        environment = baseEnv // environment;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ extraOptions
          ++ [ "--memory=2g" "--cpus=1.0" "--memory-swap=4g" ];
        ports = ports;
        volumes = volumes;
      };
    };
}
