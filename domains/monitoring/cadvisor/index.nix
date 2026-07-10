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

      # cAdvisor binary args (entrypoint flags, NOT podman flags).
      cmd = [
        "--store_container_labels=false"
      ];

      extraOptions = [
        "--privileged"
        "--device=/dev/kmsg"
        # CRITICAL for podman: without this, podman gives cAdvisor its OWN cgroup
        # namespace, so /sys/fs/cgroup inside shows tmpfs (empty) and it only
        # reports the root cgroup id=/. Sharing the host cgroup namespace lets it
        # read every container's machine.slice/libpod-*.scope stats.
        "--cgroupns=host"
      ];
    };

    # Register with Prometheus. cAdvisor can't resolve podman container NAMES
    # (name="" — the Docker factory doesn't map libpod scopes), but the
    # systemd-managed oci-containers each run in a /system.slice/podman-<name>.service
    # cgroup with the name in the path. Extract it into a `container` label so
    # dashboards can group by a friendly name. Non-container cgroups get no label.
    hwc.monitoring.prometheus.scrapeConfigs = [
      {
        job_name = "cadvisor";
        static_configs = [{
          targets = [ "localhost:${toString cfg.port}" ];
        }];
        scrape_interval = "30s";
        metric_relabel_configs = [
          {
            source_labels = [ "id" ];
            regex = "/system\\.slice/podman-(.+)\\.service";
            target_label = "container";
            replacement = "$1";
          }
        ];
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
