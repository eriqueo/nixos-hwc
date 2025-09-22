{ lib, pkgs, ... }:
rec {
  # Pure helper functions - no config dependencies at all
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
}
