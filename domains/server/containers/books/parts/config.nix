{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.services.containers.books;
in
{
  config = lib.mkIf cfg.enable {
    # Systemd service dependencies for books container
    systemd.services."podman-books" = {
      after = [
        "network-online.target"
        "init-media-network.service"
        "agenix.service"
        "mnt-hot.mount"
      ];
      wants = [
        "network-online.target"
        "agenix.service"
      ];
      requires = [ "mnt-hot.mount" ];
    };
  };
}
