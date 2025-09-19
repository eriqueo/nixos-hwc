# modules/home/core/mail/parts/abook.nix
{ lib, ... }:

{
  home.file.".abook/abookrc".text = ''
    [format]
    field delim = :
    addrfield delim = ;
    tuple delim = ,
    [options]
    autosave = yes
  '';

  home.file.".abook/addressbook".text = "# abook addressbook\n";
}
