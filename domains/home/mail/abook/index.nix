{ config, lib, ... }:
let
  enabled = config.hwc.home.mail.enable or false;
in
{
  config = lib.mkIf enabled {
    home.packages = [pkgs.abook];
    home.file.".abook/abookrc".text = ''
      [format]
      field delim = :
      addrfield delim = ;
      tuple delim = ,
      [options]
      autosave = yes
    '';
    home.file.".abook/addressbook".text = "# abook addressbook\n";
  };
}
