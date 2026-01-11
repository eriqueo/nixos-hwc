{ config, lib, ... }:
let
  cfg = config.hwc.paths;
in
{
  config = {
    systemd.tmpfiles.rules = [
      "d ${cfg.user.home} 0755 root root -"
      "d ${cfg.hot.root} 0755 root root -"
      "d ${cfg.media.root} 0755 root root -"
      "d ${cfg.backup} 0755 root root -"
      "d ${cfg.nixos} 0755 root root -"
    ];

    # VALIDATION
    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.user.home;
        message = "hwc.paths.user.home must be absolute (filesystem materializer)";
      }
    ];
  };
}
