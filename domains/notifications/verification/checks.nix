{ pkgs, lib, repoRoot }:
let
  post = import ../send/post.nix { inherit pkgs; };
  cli = import ../send/cli.nix {
    inherit pkgs lib;
    config.hwc.notifications = {
      send.cli = { defaultSeverity = "info"; defaultEndpoint = "system"; };
      notify.url = "http://127.0.0.1:$NOTIFY_TEST_PORT";
    };
  };
in {
  notification-delivery-cli = pkgs.runCommand "notification-delivery-cli" {
    nativeBuildInputs = [ pkgs.python3 ];
  } ''
    python3 ${./delivery.py} ${post}/bin/hwc-notify-post ${cli}/bin/hwc-alert
    touch "$out"
  '';
}
