# modules/home/core/mail/index.nix
{ config, lib, pkgs, ... }:

let
  enabled = config.hwc.home.core.mail.enable or false;

  parts = [
    (import ./parts/sync_send_search.nix { inherit config lib pkgs; })
    (import ./parts/abook.nix            { inherit lib;             })
    (import ./parts/services.nix         { inherit config lib pkgs; })
  ];
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf enabled (lib.mkMerge parts);
}
