{ lib, ... }:
{
  options.hwc.filesystem.structure.dirs = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule ({ lib, ... }: {
      options = {
        path  = lib.mkOption { type = lib.types.str; };
        mode  = lib.mkOption { type = lib.types.str; default = "0755"; };
        user  = lib.mkOption { type = lib.types.str; default = "root"; };
        group = lib.mkOption { type = lib.types.str; default = "root"; };
      };
    }));
    default = [];
    description = "Additional directories to create via tmpfiles.d";
  };
}
