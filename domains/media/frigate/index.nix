# domains/media/frigate/index.nix
#
# Frigate NVR — nix-native configuration
# Namespace: hwc.media.frigate.*
#
# Config is generated from nix (parts/config.nix) with runtime secret substitution.
#
# DEPENDENCIES:
#   - hwc.system.hardware.gpu (for GPU acceleration)
#   - hwc.secrets (for RTSP credentials)
#   - virtualisation.oci-containers.backend = "podman"
#
{ lib, config, pkgs, utils, ... }:
let
  cfg = config.hwc.media.frigate;
  mediaMount = builtins.head (lib.sort (a: b: builtins.stringLength a > builtins.stringLength b)
    (lib.filter (p: lib.hasPrefix "${lib.removeSuffix "/" p}/" cfg.storage.mediaPath)
      (builtins.attrNames config.fileSystems)));
  mediaMountUnit = "${utils.escapeSystemdPath mediaMount}.mount";
  credentialNames = [ "frigate-rtsp-username" "frigate-rtsp-password" "frigate-camera-ips"
    "frigate-reolink-username" "frigate-reolink-password" ];
  healthState = "${config.hwc.paths.state}/frigate-recording-health";
  healthSettings = pkgs.writeText "frigate-recording-health.json" (builtins.toJSON {
    database = "${cfg.storage.configPath}/frigate.db";
    media = cfg.storage.mediaPath;
    state = healthState;
    metrics = "${healthState}/metrics/recording.prom";
    ffmpeg = "${pkgs.ffmpeg}/bin/ffmpeg";
    cameras = builtins.attrNames (lib.filterAttrs (_: camera: camera.enabled) cfg._settings.cameras);
  });
  labelPython = pkgs.python3.withPackages (p: [ p.onnx ]);
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  runtimeDebs = builtins.fromJSON ''
    [{"name":"libsasl2-modules-db","version":"2.1.28+dfsg-10+deb12u1","file":"libsasl2-modules-db_2.1.28+dfsg-10+deb12u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/cyrus-sasl2/libsasl2-modules-db_2.1.28+dfsg-10+deb12u1_amd64.deb","hash":"sha256-bIbKj+mn1lLmGIdLh1O0tuxrQu12SbPziOONCpkEe6U="},{"name":"libsasl2-2","version":"2.1.28+dfsg-10+deb12u1","file":"libsasl2-2_2.1.28+dfsg-10+deb12u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/cyrus-sasl2/libsasl2-2_2.1.28+dfsg-10+deb12u1_amd64.deb","hash":"sha256-1vIECOK+kuvZ9eOxwZNbB177PwOrtfSPe5kaCtPi1qU="},{"name":"libbrotli1","version":"1.0.9-2+deb12u1","file":"libbrotli1_1.0.9-2+deb12u1_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/b/brotli/libbrotli1_1.0.9-2+deb12u1_amd64.deb","hash":"sha256-4ns9ZV+m+t16VvcGaH6UVzwK9ot9bfOUoyo4GjpsbYs="},{"name":"tzdata","version":"2026f-0+deb12u1","file":"tzdata_2026f-0+deb12u1_all.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/t/tzdata/tzdata_2026f-0+deb12u1_all.deb","hash":"sha256-MlTrhwyKlJUYIUgFruXkJ2r3aZmI6ouaOlg80PHqsxw="},{"name":"libssl3","version":"3.0.22-1~deb12u2","file":"libssl3_3.0.22-1~deb12u2_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/libssl3_3.0.22-1~deb12u2_amd64.deb","hash":"sha256-y0eEdA2qmzsOrqK0RLvvpoZ5Svu/PWeNI4wf2YdfLv0="},{"name":"libjq1","version":"1.6-2.1+deb12u3","file":"libjq1_1.6-2.1+deb12u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/j/jq/libjq1_1.6-2.1+deb12u3_amd64.deb","hash":"sha256-XppwgboQzoJvbT0QOqm5EhcMWtyDbiVhAAczVxmV3Vs="},{"name":"libexpat1","version":"2.5.0-1+deb12u5","file":"libexpat1_2.5.0-1+deb12u5_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/e/expat/libexpat1_2.5.0-1+deb12u5_amd64.deb","hash":"sha256-yuXe1mbYVz3TMGC8ZvusIe6osQGmtW4q+L1ZD8+mXXk="},{"name":"perl-base","version":"5.36.0-7+deb12u4","file":"perl-base_5.36.0-7+deb12u4_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/p/perl/perl-base_5.36.0-7+deb12u4_amd64.deb","hash":"sha256-19GUOuyVl2Kb9zB178xe9tyb2pbXjoDYQxVuzUSEeLg="},{"name":"ca-certificates","version":"20250419~deb12u2","file":"ca-certificates_20250419~deb12u2_all.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/c/ca-certificates/ca-certificates_20250419~deb12u2_all.deb","hash":"sha256-ufdrUnGnrDc/1efhtbgmpx3dcCtCoNEElV7LGs//yUs="},{"name":"openssl","version":"3.0.22-1~deb12u2","file":"openssl_3.0.22-1~deb12u2_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/o/openssl/openssl_3.0.22-1~deb12u2_amd64.deb","hash":"sha256-XN8Lc1scipauC/g+0yjIPCFw+DIN7bA16YcFtgstDP4="},{"name":"jq","version":"1.6-2.1+deb12u3","file":"jq_1.6-2.1+deb12u3_amd64.deb","url":"https://deb.debian.org/debian-security/pool/updates/main/j/jq/jq_1.6-2.1+deb12u3_amd64.deb","hash":"sha256-wl8/2iASB+2YsdY2hvLYG53+uZ8astHTX7P3tqHBB9w="}]
  '';
  runtimeWheels = builtins.fromJSON ''
    [{"name":"Pillow","version":"13.0.0","url":"https://files.pythonhosted.org/packages/36/46/f509b74787f40ce0627501089d630b2c741b63b244c1f40b640b3b01e181/pillow-13.0.0-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl","file":"pillow-13.0.0-cp311-cp311-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl","hash":"sha256-piXfmipVl/peUmbgGu/IJgS7hdKR41R5gehjVg112mw="},{"name":"certifi","version":"2026.10.18","url":"https://files.pythonhosted.org/packages/08/ba/95dd616042484f7c83a06974388b37b837732740ee70bc5dc715b5fcd55a/certifi-2026.10.18-py3-none-any.whl","file":"certifi-2026.10.18-py3-none-any.whl","hash":"sha256-cxkcR6qnnaOU6P7i28LsgnQyyrVjERIsnker9545D2I="}]
  '';
  httpBackport = helpers.mkPythonHttpFramingBackport {
    python = "python3";
    stdlibUpstreamCommits = pkgs.pythonHttpFramingBackport.upstreamCommits;
    modules = {
      httpClient = {
        path = "/usr/lib/python3.11/http/client.py";
        sourceSha256 = "de4ab4c192ceee43d5c8515718d07cc12a92a9232b450440a4c04157e5c9c66a";
        patchedSha256 = "a5c4370e13466c7d7856711b86c135d533be1ee05611e43da4cada3cd5aedb86";
        replacements = pkgs.pythonHttpFramingBackport.replacements;
      };
      urllib3 = {
        path = "/usr/local/lib/python3.11/dist-packages/urllib3/response.py";
        inherit (pkgs.pythonUrllib3FramingBackport.sources."2.8.0") sourceSha256 patchedSha256;
        replacements = pkgs.pythonUrllib3FramingBackport.replacements;
      };
    };
  };
  # Upstream 06a956fbcd9e676d926fc35d8b400cf3853bc69c (#24682).
  # Temporary backport: remove when the pinned base contains patchedSha below.
  nginxAuthPatch = pkgs.writeText "frigate-nginx-auth-patch.py" ''
    import hashlib
    from pathlib import Path
    import sys
    path = Path(sys.argv[1])
    source = path.read_bytes()
    assert hashlib.sha256(source).hexdigest() == "048a9ba9d32a45e308ab62944891659c6aa89c8ad0c67b506f6e0034e7ec276a", "NGINX_AUTH_SOURCE_DRIFT"
    result = source.replace(b"    proxy_pass $upstream_auth;", b"    proxy_pass $upstream_auth;\n    # $go2rtc_stream_proxy is only set by the go2rtc stream locations\n    uninitialized_variable_warn off;")
    assert hashlib.sha256(result).hexdigest() == "2901c2c09b37f3cf0e389853b141b0cefa1cb6bfbf407b5a68f21e8bd2e90400", "NGINX_AUTH_RESULT_DRIFT"
    path.write_bytes(result)
  '';
  runtimeInputs = { debian = runtimeDebs; wheels = runtimeWheels;
    pythonHttpBackport = httpBackport.manifest; };
  # Temporary URL parser repair; remove after upstream passes the
  # malformed-Host, current-data recovery and actual GPU consumer checks.
  runtime = helpers.mkRuntimeImage {
    name = "frigate";
    version = "0.18.2-tensorrt-hostfix";
    recipe = ''
      FROM ghcr.io/blakeblackshear/frigate@sha256:1cafb6ebbaff0aaf275cc3f31951bcf7e29f3989f18a10ba9565091367d8736c
      # Fixed runtime inputs ${builtins.hashString "sha256" (builtins.toJSON runtimeInputs)}
      COPY nginx-auth-patch.py /tmp/nginx-auth-patch.py
      RUN python3 /tmp/nginx-auth-patch.py /usr/local/nginx/conf/auth_location.conf && rm /tmp/nginx-auth-patch.py
      COPY debian/ /tmp/hwc-frigate-debs/
      RUN DEBIAN_FRONTEND=noninteractive apt-get --no-download --yes -o Dir::Cache::archives=/tmp/hwc-frigate-debs -o Dpkg::Options::=--force-confold install /tmp/hwc-frigate-debs/*.deb && test -z "$(dpkg --audit)" && rm -r /tmp/hwc-frigate-debs
      COPY wheels/ /tmp/hwc-frigate-wheels/
      # The image uses distro Python with vendor wheels in /usr/local. This
      # build owns exactly these two replacements; retain its PEP668 marker.
      RUN python3 -m pip install --no-index --no-deps --no-cache-dir --force-reinstall --break-system-packages /tmp/hwc-frigate-wheels/*.whl && rm -r /tmp/hwc-frigate-wheels
    ''
      + httpBackport.recipe
      + helpers.mkStarletteHostBackport {
        python = "python3";
        version = "0.47.3";
        sourceSha256 = "ce16c619c99e45507a3aebedf47c2807c8122bd9396e21f7cd48636f9715fa8c";
        patchedSha256 = "5c163e52df0a615c7860136b30d010c48696c0774011db8879a3299e025ed441";
      };
  };
  runtimeManifest = pkgs.writeText "frigate-runtime-packages.json" (builtins.toJSON runtimeInputs);
  runtimeContext = pkgs.runCommand "frigate-runtime-context" {} ''
    mkdir -p "$out/debian" "$out/wheels"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${nginxAuthPatch} "$out/nginx-auth-patch.py"
    cp ${runtimeManifest} "$out/manifest.json"
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/debian/${p.file}"
    '') runtimeDebs}
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/wheels/${p.file}"
    '') runtimeWheels}
  '';
in
{
  imports = [
    ./parts/config.nix
    ./parts/cleanup.nix
  ];

  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.frigate = {
    enable = lib.mkEnableOption "Frigate NVR (config-first pattern)";

    image = lib.mkOption {
      type = lib.types.str;
      default = runtime.image;
      description = ''
        Container image for Frigate NVR.
        Uses -tensorrt variant which includes CUDA support for ONNX detector.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = (import ../../networking/ports.nix).frigate.port;
      description = "Frigate internal HTTP port (host networking; fixed at 5000)";
    };

    gpu = {
      enable = lib.mkEnableOption "GPU acceleration for object detection";
      device = lib.mkOption { type = lib.types.int; default = 0; description = "GPU device number (NVIDIA)"; };
    };

    storage = {
      configPath = lib.mkOption { type = lib.types.str; default = "/var/lib/frigate/config"; description = "Configuration directory path"; };
      mediaPath = lib.mkOption { type = lib.types.str; default = "${config.hwc.paths.media.root}/surveillance/frigate/media"; description = "Media storage path (recordings)"; };
    };

    resources = {
      memory = lib.mkOption { type = lib.types.str; default = "4g"; description = "Container memory limit"; };
      cpus = lib.mkOption { type = lib.types.str; default = "1.5"; description = "Container CPU limit"; };
      shmSize = lib.mkOption { type = lib.types.str; default = "1g"; description = "Shared memory size"; };
    };

    cleanup = {
      enable = lib.mkEnableOption "Automated surveillance recording cleanup";

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "daily";
        description = "systemd OnCalendar schedule for cleanup";
      };

    };

    firewall.tailscaleOnly = lib.mkOption { type = lib.types.bool; default = true; description = "Restrict access to Tailscale interface only"; };

    _configTemplate = lib.mkOption { type = lib.types.package; internal = true; description = "Generated YAML config template"; };
    _settings = lib.mkOption { type = lib.types.attrs; internal = true; readOnly = true; description = "Structured config shared by YAML generation and camera expectations"; };
  };

  config = lib.mkIf cfg.enable {
    system.build.frigateRuntimeImageRecipe = runtime.dockerfile;
    system.build.frigateRuntimeImageContext = runtimeContext;
    virtualisation.oci-containers.containers.frigate.pull = lib.mkIf (cfg.image == runtime.image) "never";

    # Config generation service (substitutes secrets into nix-generated YAML template)
    systemd.services.frigate-config = {
      description = "Generate Frigate NVR configuration";
      wantedBy = [ "podman-frigate.service" ];
      before = [ "podman-frigate.service" ];
      serviceConfig = {
        Type = "oneshot";
        # Run again for every container start, including a secret-only restart.
        RemainAfterExit = false;
        User = lib.mkForce "eric";
        Group = "users";
        # PID 1 reads root-only agenix mounts; the service receives private,
        # read-only copies without broadening permissions on the source files.
        LoadCredential = map (name: "${name}:${config.age.secrets.${name}.path}") credentialNames;
        UMask = "0077";
      };

      script = ''
        # REPLACEABLE: derived on every run from the model, including upgrades.
        ${labelPython}/bin/python3 ${./parts/labelmap.py} \
          ${cfg.storage.configPath}/models/${builtins.baseNameOf cfg._settings.model.path} \
          ${cfg.storage.configPath}/labelmap/coco-80.txt

        # Read secrets - Cobra cameras
        RTSP_USER=$(cat "$CREDENTIALS_DIRECTORY/frigate-rtsp-username")
        RTSP_PASS=$(cat "$CREDENTIALS_DIRECTORY/frigate-rtsp-password")
        RTSP_PASS_ENCODED=$(echo "$RTSP_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")

        CAMERA_IPS=$(cat "$CREDENTIALS_DIRECTORY/frigate-camera-ips")
        CAM1_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_1')
        CAM2_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_2')
        CAM3_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.cobra_cam_3')

        # Read secrets - Reolink camera
        REOLINK_USER=$(cat "$CREDENTIALS_DIRECTORY/frigate-reolink-username")
        REOLINK_PASS=$(cat "$CREDENTIALS_DIRECTORY/frigate-reolink-password")
        REOLINK_PASS_ENCODED=$(echo "$REOLINK_PASS" | ${pkgs.python3}/bin/python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))")
        REOLINK_IP=$(echo "$CAMERA_IPS" | ${pkgs.jq}/bin/jq -r '.reolink')

        # Substitute secrets into nix-generated config template
        export RTSP_USER RTSP_PASS_ENCODED CAM1_IP CAM2_IP CAM3_IP REOLINK_USER REOLINK_PASS_ENCODED REOLINK_IP
        # Idempotent derived configuration. Replace atomically; never expose a
        # partially written credential-bearing file to a restarting container.
        temporary=$(mktemp ${cfg.storage.configPath}/.config.XXXXXX)
        trap 'rm -f "$temporary"' EXIT
        ${pkgs.envsubst}/bin/envsubst < ${cfg._configTemplate} > "$temporary"
        chmod 0600 "$temporary"
        mv -f "$temporary" ${cfg.storage.configPath}/config.yaml
      '';

      path = with pkgs; [ coreutils jq python3 envsubst ];
    };

    # Create all required directories
    systemd.tmpfiles.rules = [
      "d ${healthState} 0755 eric users -"
      "d ${healthState}/metrics 0755 eric users -"
      "d ${cfg.storage.configPath} 0755 eric users -"
      "d ${cfg.storage.configPath}/models 0755 eric users -"
      "d ${cfg.storage.configPath}/labelmap 0755 eric users -"
      "d ${cfg.storage.mediaPath} 0755 eric users -"
    ];

    services.prometheus.exporters.node.enabledCollectors = [ "textfile" ];
    services.prometheus.exporters.node.extraFlags = [ "--collector.textfile.directory=${healthState}/metrics" ];
    systemd.timers.frigate-recording-health = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnBootSec = "3min"; OnUnitInactiveSec = "30s"; AccuracySec = "1s"; };
    };
    systemd.services.frigate-recording-health = {
      description = "Check finalized Frigate recordings";
      after = [ "podman-frigate.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        ExecStart = "${pkgs.python3}/bin/python3 ${./parts/recording-health.py} ${healthSettings}";
        TimeoutStartSec = 55;
        TimeoutStopSec = 5;
        MemoryMax = "512M";
        CPUQuota = "100%";
        Nice = 10;
        UMask = "0022";
        ProtectSystem = "strict";
        ReadWritePaths = [ healthState ];
        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };

    # Ensure Frigate starts after mosquitto (for MQTT events) and CDI spec generation
    systemd.services.podman-frigate = {
      preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
          echo "Prebuild Frigate from ${runtime.dockerfile} before activation" >&2
          exit 1
        }
      '');
      bindsTo = [ mediaMountUnit ];
      after = [ "mosquitto.service" "frigate-config.service" mediaMountUnit ]
        ++ lib.optional cfg.gpu.enable "nvidia-container-toolkit-cdi-generator.service";
      wants = [ "mosquitto.service" ];
      requires = [ "frigate-config.service" ] ++ lib.optionals cfg.gpu.enable [ "nvidia-container-toolkit-cdi-generator.service" ];
      restartTriggers = [ cfg._configTemplate ./parts/labelmap.py ]
        ++ map (name: config.age.secrets.${name}.file) credentialNames;
      serviceConfig.BindPaths = [ cfg.storage.mediaPath ];
      serviceConfig.ExecStartPre = lib.mkBefore [
        "${pkgs.writeShellScript "frigate-media-mount-check" ''
          actual=$(${pkgs.coreutils}/bin/stat -c %d ${lib.escapeShellArg cfg.storage.mediaPath})
          expected=$(${pkgs.coreutils}/bin/stat -Lc %r ${lib.escapeShellArg config.fileSystems.${mediaMount}.device})
          test "$actual" = "$expected" || { echo 'FRIGATE_MEDIA_MOUNT: wrong filesystem' >&2; exit 1; }
        ''}"
      ];
      # Report startup only after the API health check passes. Bound a failed
      # initialization instead of inheriting the container module's infinity.
      serviceConfig.TimeoutStartSec = lib.mkForce 120;
    };

    # Frigate container
    # HWC-EXCEPTION(Law 5): NVR owns its device/shm/startup contract
    # Justification: camera-network and s6 UID behavior differ from Linuxserver media apps. NVIDIA CDI grants the GPU explicitly; privileged mode is unnecessary.
    # Plan: permanent by design (revisit if an infra-shaped helper grows to fit)
    # Revocable: yes
    virtualisation.oci-containers.containers.frigate = {
      image = cfg.image;
      autoStart = true;

      # Host networking exposes the application's listeners directly.

      extraOptions = [
        "--network=host"
        "--security-opt=label=disable"
        "--security-opt=no-new-privileges"
        "--tmpfs=/tmp/cache:size=1g"
        "--shm-size=${cfg.resources.shmSize}"
        "--memory=${cfg.resources.memory}"
        "--cpus=${cfg.resources.cpus}"
        "--health-cmd=curl -fsS http://127.0.0.1:5000/api/stats || exit 1"
        "--health-interval=30s"
        "--health-timeout=5s"
        "--health-retries=3"
        "--sdnotify=healthy"
      ]
      ++ lib.optionals cfg.gpu.enable [
        "--device=nvidia.com/gpu=${toString cfg.gpu.device}"
      ];

      environment = {
        TZ = "America/Denver";
      } // lib.optionalAttrs cfg.gpu.enable {
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,video,utility";
        CUDA_VISIBLE_DEVICES = toString cfg.gpu.device;
        LD_LIBRARY_PATH = "/run/opengl-driver/lib:/run/opengl-driver-32/lib";
      };

      volumes = [
        "${cfg.storage.configPath}:/config"
        "${cfg.storage.configPath}/models:/config/models:ro"
        "${cfg.storage.configPath}/labelmap:/labelmap:ro"
        "${cfg.storage.mediaPath}:/media/frigate"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };

    # Firewall rules
    networking.firewall = {
      interfaces."lo".allowedTCPPorts = [ cfg.port ];
      interfaces."tailscale0" = lib.mkIf cfg.firewall.tailscaleOnly {
        allowedTCPPorts = [ 8555 ];
        allowedUDPPorts = [ 8555 ];
      };
    };

    # CRITICAL state: existing Borg producer makes a consistent online snapshot.
    hwc.data.borg.sqliteSnapshots.frigate = lib.mkIf config.hwc.data.borg.enable {
      source = "${cfg.storage.configPath}/frigate.db";
      user = "eric";
      maxBytes = 536870912;
      timeoutSeconds = 120;
    };
    hwc.data.borg.sources = lib.mkIf config.hwc.data.borg.enable [
      "${cfg.storage.configPath}/go2rtc_homekit.yml"
      "${cfg.storage.configPath}/models"
    ];

    # Frigate owns its metrics. The former sidecar duplicated /api/metrics.
    hwc.monitoring.prometheus.scrapeConfigs = [{
      job_name = "frigate";
      scheme = "https";
      metrics_path = "/api/metrics";
      static_configs = [{ targets = [ "frigate.${config.hwc.networking.shared.vhostDomain}:443" ]; }];
      scrape_interval = "30s";
      # Process command lines are unnecessary high-cardinality labels.
      metric_relabel_configs = [{ action = "labeldrop"; regex = "cmdline"; }];
    }];
    # Exported: the central Prometheus (another host) loads it.
    hwc.monitoring.prometheus.rules = [ (builtins.toJSON {
      groups = [{
        name = "frigate_configuration";
        rules = lib.mapAttrsToList (name: camera: {
          record = "frigate_camera_expected_fps";
          expr = "vector(${toString (if camera.enabled then camera.detect.fps else 0)})";
          labels.camera_name = name;
        }) cfg._settings.cameras;
      } {
        name = "frigate_recording_health";
        rules = [
          {
            alert = "FrigateRecordingUnavailable";
            expr = "((frigate_recording_age_seconds > 60) or (frigate_recording_gap_seconds > 30) or (frigate_recording_decode_failed > 0)) and on() (frigate_service_uptime_seconds > 180)";
            for = "30s";
            labels = { severity = "P4"; category = "frigate"; };
            annotations = {
              summary = "Frigate recording is missing or damaged";
              description = "Inspect camera {{ $labels.camera_name }} recordings and the recording-health service on hwc-home.";
            };
          }
          {
            alert = "FrigateRecordingCheckUnavailable";
            expr = "(frigate_recording_check_failed > 0) or (time() - frigate_recording_check_timestamp_seconds > 120) or absent(frigate_recording_check_timestamp_seconds)";
            for = "1m";
            labels = { severity = "P4"; category = "frigate"; };
            annotations = {
              summary = "Frigate recording checks are unavailable";
              description = "Inspect frigate-recording-health.service on hwc-home. Healthy detection does not prove recording health.";
            };
          }
        ];
      }];
    }) ];

    assertions = [
      {
        assertion = !cfg.gpu.enable || config.hwc.system.hardware.gpu.enable;
        message = "hwc.media.frigate.gpu requires hwc.system.hardware.gpu.enable = true";
      }
      {
        assertion = cfg.storage.mediaPath != "";
        message = "hwc.media.frigate.storage.mediaPath must be set";
      }
      {
        assertion = cfg.port == 5000;
        message = "Frigate uses host networking and listens on 5000; port mappings cannot change it";
      }
      {
        assertion = builtins.match "^/mnt/.*" cfg.storage.mediaPath != null;
        message = "hwc.media.frigate.storage.mediaPath must be under /mnt";
      }
      {
        assertion = config.hwc.secrets.enable;
        message = "hwc.media.frigate requires hwc.secrets.enable = true for RTSP credentials";
      }
      {
        assertion = config.virtualisation.oci-containers.backend == "podman";
        message = "hwc.media.frigate requires Podman as OCI container backend";
      }
      {
        assertion = config.hwc.monitoring.prometheus.agent.enable;
        message = "Frigate exports its metrics through this host's agent (hwc.monitoring.prometheus.agent.enable = true)";
      }
    ];
  };
}
