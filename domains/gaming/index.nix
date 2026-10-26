# domains/gaming/index.nix
#
# Gaming Domain - Emulation and game streaming services
#
# NAMESPACE: hwc.gaming.{retroarch,webdav}.*
#
# USED BY:
#   - machines/home/config.nix

{ lib, config, pkgs, ... }:

{
  imports = [
    ./retroarch/index.nix
    ./webdav/index.nix
  ];

  options.hwc.gaming.steam = {
    enable = lib.mkEnableOption "Steam with declarative Proton-GE";
    gpuOffload = lib.mkEnableOption ''
      running Steam and every game it starts on the NVIDIA dGPU of a PRIME
      offload laptop, so no per-game launch option is needed'';
  };

  config = lib.mkIf config.hwc.gaming.steam.enable (let
    gpu = config.hwc.system.hardware.gpu;
  in {
    assertions = [{
      assertion = !config.hwc.gaming.steam.gpuOffload
        || (gpu.enable && gpu.type == "nvidia" && gpu.nvidia.prime.enable);
      message = "hwc.gaming.steam.gpuOffload requires an enabled NVIDIA GPU with prime.enable.";
    }];
    programs.steam = {
      enable = true;
      extraCompatPackages = [ pkgs.proton-ge-bin ];
      # The steam module's apply re-overrides this and keeps extraProfile.
      package = lib.mkIf config.hwc.gaming.steam.gpuOffload
        (pkgs.steam.override { extraProfile = gpu.nvidia.prime.offloadProfile; });
    };
  });
}
