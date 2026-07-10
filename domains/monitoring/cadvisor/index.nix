# domains/monitoring/cadvisor/index.nix
#
# cAdvisor - Container Advisor for resource usage and performance metrics
#
# NAMESPACE: hwc.monitoring.cadvisor.*
#
# DEPENDENCIES:
#   - hwc.monitoring.prometheus (metrics collector)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.monitoring.cadvisor;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.cadvisor = {
    enable = lib.mkEnableOption "cAdvisor container metrics exporter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9120;
      description = "cAdvisor metrics port";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    # cAdvisor container for container metrics
    # HWC-EXCEPTION(Law 5): infra container, not a media app
    # Justification: needs --privileged + whole-host ro mounts (/,/sys,/var/run) for container metrics; mkContainer PUID/PGID + media-network model does not apply
    # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
    # Revocable: yes
    virtualisation.oci-containers.containers.cadvisor = {
      image = "gcr.io/cadvisor/cadvisor:latest";
      autoStart = true;

      ports = [
        "127.0.0.1:${toString cfg.port}:8080"
      ];

      volumes = [
        "/:/rootfs:ro"
        "/var/run:/var/run:ro"
        "/sys:/sys:ro"
        "/var/lib/containers:/var/lib/containers:ro"
        "/dev/disk:/dev/disk:ro"
        # Podman's Docker-compatible API socket → enables cAdvisor's docker
        # manager so it enumerates containers and labels cgroup metrics with
        # their NAME (podman runs oci-containers as machine.slice/libpod-*.scope;
        # without this cAdvisor only sees the root cgroup id=/ and name="").
        "/run/podman/podman.sock:/var/run/docker.sock:ro"
      ];

      extraOptions = [
        "--privileged"
        "--device=/dev/kmsg"
        # Only report container cgroups (drop host raw-cgroup noise) now that
        # the docker manager can identify them.
        "--docker_only=true"
        "--store_container_labels=false"
      ];
    };

    # Register with Prometheus
    hwc.monitoring.prometheus.scrapeConfigs = [
      {
        job_name = "cadvisor";
        static_configs = [{
          targets = [ "localhost:${toString cfg.port}" ];
        }];
        scrape_interval = "30s";
      }
    ];

    #==========================================================================
    # VALIDATION
    #==========================================================================
    assertions = [
      {
        assertion = !cfg.enable || config.hwc.monitoring.prometheus.enable;
        message = "cAdvisor requires Prometheus to be enabled (hwc.monitoring.prometheus.enable = true)";
      }
    ];
  };
}
