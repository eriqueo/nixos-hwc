{ lib, pkgs, cfg, clientIdPath, clientSecretPath }:
let
  dataDir = "~/.local/share/vdirsyncer";

  mkPair = name: acc: ''
    [pair ${name}]
    a = "${name}_remote"
    b = "${name}_local"
    collections = ["from a", "from b"]
    metadata = ["color"]

    [storage ${name}_remote]
    type = "google_calendar"
    token_file = "${dataDir}/tokens/${name}"
    client_id.fetch = ["command", "cat", "${clientIdPath}"]
    client_secret.fetch = ["command", "cat", "${clientSecretPath}"]

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
