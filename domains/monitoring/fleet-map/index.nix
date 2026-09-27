{ config, lib, pkgs, inputs, ... }:
let
  cfg = config.hwc.monitoring.fleet-map;
  state = "${config.hwc.paths.state}/fleet-map";
  source = inputs.fleet-map;
in {
  # OPTIONS
  options.hwc.monitoring.fleet-map.enable = lib.mkEnableOption "private fleet topology map";

  # IMPLEMENTATION
  config = lib.mkIf cfg.enable {
    hwc.networking.shared.routes = [{
      name = "map";
      mode = "vhost";
      root = "${state}/site";
    }];
    # REPLACEABLE: one snapshot plus one atomically replaced HTML page.
    # No growing history; refresh replaces the fixed file set. Git owns code.
    systemd.tmpfiles.rules = [
      "d ${state} 0750 eric users -"
      "d ${state}/evidence 0700 eric users -"
      "d ${state}/site 0755 eric users -"
    ];
    systemd.services.fleet-map-publish = {
      description = "Capture and publish the private fleet map";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      path = [ "/run/wrappers" "/run/current-system/sw" pkgs.python3 pkgs.git pkgs.nix pkgs.openssh pkgs.sudo pkgs.systemd pkgs.iproute2 pkgs.coreutils pkgs.podman pkgs.postgresql ];
      environment = {
        HOME = config.hwc.paths.user.home;
        XDG_RUNTIME_DIR = "/run/user/1000";
      };
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric"; # Charter Law 4
        Group = "users";
        TimeoutStartSec = "10min";
        TimeoutStopSec = "15s";
        KillMode = "control-group";
        Nice = 10;
        UMask = "0022";
      };
      # Atomic, idempotent publication; no retries or work triggered by the UI.
      script = ''
        test -r ${source}/view.html
        test -d ${config.hwc.paths.nixos}/.git
        ${pkgs.python3}/bin/python3 ${source}/refresh.py \
          --capture --repo ${config.hwc.paths.nixos} \
          --evidence ${state}/evidence --output ${state}/site
      '';
    };
    # VALIDATION
    assertions = [{
      assertion = config.hwc.networking.reverseProxy.enable;
      message = "fleet-map requires the existing Caddy reverse proxy";
    }];
  };
}
