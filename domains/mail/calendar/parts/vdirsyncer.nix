{ lib, pkgs, cfg, applePwPath }:
let
  dataDir = "~/.local/share/vdirsyncer";

  mkPair = name: acc: ''
    [pair ${name}]
    a = "${name}_remote"
    b = "${name}_local"
    collections = ["from a", "from b"]
    metadata = ["color", "displayname"]

    [storage ${name}_remote]
    type = "caldav"
    url = "https://caldav.icloud.com/"
    username = "${acc.email}"
    password.fetch = ["command", "cat", "${applePwPath}"]

    [storage ${name}_local]
    type = "filesystem"
    path = "${dataDir}/calendars/${name}/"
    fileext = ".ics"
  '';

  pairs = lib.concatStringsSep "\n" (lib.mapAttrsToList mkPair cfg.accounts);
in
{
  config = ''
    [general]
    status_path = "${dataDir}/status/"

    ${pairs}
  '';
}
