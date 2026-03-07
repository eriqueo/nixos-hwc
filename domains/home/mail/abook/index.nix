{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.mail;
  on  = (cfg.enable or true) && (cfg.abook.enable or true);
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.mail.abook = {
    enable = lib.mkEnableOption "address book functionality";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf on {
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

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}