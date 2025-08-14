{ config, lib, ... }:
{
  options.hwc.test = {
    enable = lib.mkEnableOption "Test module";
  };
  
  config = lib.mkIf config.hwc.test.enable {
    environment.etc."nixos-refactor-test.txt".text = "Working!";
  };
}
