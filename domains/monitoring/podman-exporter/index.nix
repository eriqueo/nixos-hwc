# domains/monitoring/podman-exporter/index.nix
#
# prometheus-podman-exporter — per-container metrics WITH names, straight from
# the podman API. This is what cAdvisor cannot do: cAdvisor sees cgroups but
# can't map podman's machine.slice/libpod-*.scope back to container names. The
# exporter talks to the podman socket, so every metric carries a `name` label.
#
# NAMESPACE: hwc.monitoring.podman-exporter.*
# DEPENDENCIES: hwc.monitoring.prometheus (scrape), podman.socket (API)
# PORTS: 9882 (metrics, localhost only)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.podman-exporter;
in
{
  options.hwc.monitoring.podman-exporter = {
    enable = lib.mkEnableOption "prometheus-podman-exporter (named per-container metrics)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9882;
      description = "Host port for the podman exporter metrics endpoint";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "quay.io/navidys/prometheus-podman-exporter:latest";
      description = "Exporter container image";
    };
  };

  config = lib.mkIf cfg.enable {
    # Podman's API socket must be listening for the exporter to query it.
    virtualisation.podman.dockerSocket.enable = lib.mkDefault true;
    systemd.sockets.podman.wantedBy = [ "sockets.target" ];

    # HWC-EXCEPTION(Law 5): infra exporter, not a media app.
    # Justification: reads the host podman socket + localhost metrics port; no
    # media mounts / PUID/PGID / VPN netns. Revocable: yes.
    virtualisation.oci-containers.containers.podman-exporter = {
      image = cfg.image;
      autoStart = true;

      ports = [ "127.0.0.1:${toString cfg.port}:9882" ];

      environment = {
        CONTAINER_HOST = "unix:///run/podman/podman.sock";
      };

      volumes = [
        "/run/podman/podman.sock:/run/podman/podman.sock:ro"
      ];

      # --collector.enhance-metrics adds the human `name` (and image/pod) labels
      # to every container metric instead of bare ids.
      cmd = [ "--collector.enhance-metrics" ];

      extraOptions = [
        "--security-opt=label=disable"
      ];
    };

    hwc.monitoring.prometheus.scrapeConfigs = [
      {
        job_name = "podman";
        static_configs = [{ targets = [ "localhost:${toString cfg.port}" ]; }];
        scrape_interval = "30s";
      }
    ];

    assertions = [
      {
        assertion = !cfg.enable || config.hwc.monitoring.prometheus.enable;
        message = "podman-exporter requires Prometheus (hwc.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
