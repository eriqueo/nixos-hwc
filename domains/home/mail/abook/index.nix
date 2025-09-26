{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.mail;
  on  = (cfg.enable or true) && (cfg.abook.enable or true);in
{
  config = lib.mkIf enabled {
    home.packages = [ pkgs.abook ];

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
