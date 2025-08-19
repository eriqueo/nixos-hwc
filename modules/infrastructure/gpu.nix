{ config, lib, pkgs, ... }:
     let
       cfg = config.hwc.gpu;
     in {
       options.hwc.gpu = {
         nvidia = {
           enable = lib.mkEnableOption "NVIDIA GPU support";
           driver = lib.mkOption {
             type = lib.types.enum [ "stable" "beta" "production"
     ];
             default = "stable";
             description = "NVIDIA driver version";
           };
           prime = {
             enable = lib.mkOption {
               type = lib.types.bool;
               default = true;
               description = "Enable NVIDIA Prime for hybrid
     graphics";
             };
             nvidiaBusId = lib.mkOption {
               type = lib.types.str;
               default = "PCI:1:0:0";
               description = "NVIDIA GPU bus ID";
             };
             intelBusId = lib.mkOption {
               type = lib.types.str;
               default = "PCI:0:2:0";
               description = "Intel GPU bus ID";
             };
           };
           containerRuntime = lib.mkEnableOption "NVIDIA container
     runtime";
         };
       };

       config = lib.mkMerge [
         (lib.mkIf cfg.nvidia.enable {
           # Enable OpenGL
           hardware.opengl = {
             enable = true;
             driSupport = true;
             driSupport32Bit = true;
           };

           # NVIDIA drivers
           services.xserver.videoDrivers = [ "nvidia" ];
           hardware.nvidia = {
             modesetting.enable = true;
             powerManagement.enable = false;
             powerManagement.finegrained = false;
             open = false;
             nvidiaSettings = true;
             package = config.boot.kernelPackages.nvidiaPackages.${
     cfg.nvidia.driver};
           };

           # Prime configuration
           hardware.nvidia.prime = lib.mkIf cfg.nvidia.prime.enable
      {
             sync.enable = true;
             nvidiaBusId = cfg.nvidia.prime.nvidiaBusId;
             intelBusId = cfg.nvidia.prime.intelBusId;
           };

           # Container runtime
           hardware.nvidia-container-toolkit.enable =
     cfg.nvidia.containerRuntime;
         })
       ];
     }
