# domains/monitoring/prometheus/index.nix
#
# PROMETHEUS — the fleet's metrics, in two halves (service split wave 3):
#
#   agent   (every serving host; server role): node exporter + blackbox
#           exporter bound to this host's tailnet address, plus this host's
#           EXPORTS — `scrapeConfigs` (targets written as localhost:<port>),
#           `probes` (run by this host's blackbox agent against its own
#           loopback services) and `rules`. Exporter modules (cadvisor,
#           podman-exporter, exportarr, frigate) append to the same exports.
#   central (`enable`; monitoring role): the one Prometheus. It unions every
#           registered server's exports (read from that host's evaluated
#           config), rewrites localhost targets to the host's tailnet IP,
#           labels each series with `host`, and routes probes through the
#           host's own blackbox agent.
#
# One producer per fact: a service's probe is declared where the service runs
# (gated on its module's enable), so moving an app moves its probe.
#
# NAMESPACE: hwc.monitoring.prometheus.*
#
# DEPENDENCIES:
#   - hwc.paths.state (data directory)
#   - hwc.networking.hosts (self/selfIp, ips, servers)
#   - inputs.self.nixosConfigurations (central: the other hosts' exports)
#
# USED BY:
#   - Grafana (metrics datasource), Alertmanager (alert source)

{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.hwc.monitoring.prometheus;
  agent = cfg.agent;
  paths = config.hwc.paths;
  hosts = config.hwc.networking.hosts;
  on = path: lib.attrByPath path false config;
  containers = config.virtualisation.oci-containers.containers;
  vhost = name: "https://${name}.${config.hwc.networking.shared.vhostDomain}";

  # Blackbox prober modules, shared by every agent.
  blackboxModules = {
    http_health_check = {
      prober = "http";
      timeout = "15s";
      http = { method = "GET"; preferred_ip_protocol = "ip4"; valid_status_codes = [ 200 ]; };
    };
    # CORS preflight — proves a public webhook ingress chain (Cloudflare proxy
    # → tunnel → app) end to end without creating a lead.
    http_options_2xx = {
      prober = "http";
      timeout = "15s";
      http = {
        method = "OPTIONS";
        preferred_ip_protocol = "ip4";
        headers = { "Origin" = "https://iheartwoodcraft.com"; "Access-Control-Request-Method" = "POST"; };
        valid_status_codes = [ 200 204 ];
      };
    };
    # Unsigned POST — a 401 proves hwc-leads is up AND its HMAC verification
    # is active, without persisting anything.
    http_post_401 = {
      prober = "http";
      timeout = "15s";
      http = {
        method = "POST";
        preferred_ip_protocol = "ip4";
        headers = { "Content-Type" = "application/json"; };
        body = "{}";
        valid_status_codes = [ 401 ];
      };
    };
    # Auth-walled services: reachable = 200 or 401.
    http_2xx_or_401 = {
      prober = "http";
      timeout = "15s";
      http = { method = "GET"; preferred_ip_protocol = "ip4"; valid_status_codes = [ 200 401 ]; };
    };
    # "Alive" semantics for internal liveness: a login redirect or auth wall
    # is still REACHABLE. Up/down, not content validation.
    http_reachable = {
      prober = "http";
      timeout = "15s";
      http = {
        method = "GET";
        preferred_ip_protocol = "ip4";
        valid_status_codes = [ 200 201 204 301 302 307 308 401 403 ];
      };
    };
    # Raw TCP connect — datastores/daemons with no HTTP surface.
    tcp_connect = { prober = "tcp"; timeout = "10s"; tcp = { preferred_ip_protocol = "ip4"; }; };
  };

  # ---- this host's service probes: only what runs HERE ---------------------
  svc = name: url: { inherit url; labels.service = name; };
  box = name: svcName: url: lib.optional (containers ? ${name}) (svc svcName url);
  localHttp =
    lib.optional (on [ "services" "caddy" "enable" ]) (svc "Caddy" "http://127.0.0.1:2019/config/")
    ++ lib.optional cfg.enable (svc "Prometheus" "http://127.0.0.1:${toString cfg.port}/-/healthy")
    ++ lib.optional (on [ "hwc" "monitoring" "alertmanager" "enable" ]) (svc "Alertmanager" "http://127.0.0.1:9093/-/healthy")
    ++ lib.optional (on [ "hwc" "monitoring" "grafana" "enable" ]) (svc "Grafana" "http://127.0.0.1:3000/api/health")
    ++ box "homepage" "Homepage" "http://127.0.0.1:3080/"
    ++ box "vaultwarden" "Vaultwarden" "http://127.0.0.1:8222/alive"
    ++ box "authentik-server" "Authentik" "http://127.0.0.1:9200/-/health/live/"
    ++ box "paperless" "Paperless-NGX" "http://127.0.0.1:8102/api/"
    ++ box "firefly" "Firefly III" "http://127.0.0.1:8085/"
    ++ box "firefly-pico" "Firefly-Pico" "http://127.0.0.1:8086/"
    ++ lib.optional (on [ "hwc" "system" "mcp" "enable" ]) (svc "Heartwood MCP" "http://127.0.0.1:${toString config.hwc.system.mcp.port}/health")
    ++ lib.optional (on [ "hwc" "notifications" "notify" "enable" ]) (svc "hwc-notify" "http://127.0.0.1:${toString config.hwc.notifications.notify.port}/health")
    ++ lib.optional (on [ "hwc" "data" "couchdb" "enable" ]) (svc "CouchDB" "http://127.0.0.1:5984/")
    # llama.cpp embeddings: /health is 200 only when the model is loaded.
    ++ lib.optional (on [ "hwc" "server" "ai" "llamaCpp" "embed" "enable" ]) (svc "llama.cpp Embed" "http://127.0.0.1:11502/health")
    # Media stack (hwc-server). *arr apps run with an empty URL base.
    ++ lib.optional (on [ "services" "jellyfin" "enable" ]) (svc "Jellyfin" "http://127.0.0.1:8096/health")
    ++ box "jellyseerr" "Jellyseerr" "http://127.0.0.1:5055/api/v1/status"
    ++ box "immich-server" "Immich" "http://127.0.0.1:2283/api/server/ping"
    ++ box "sonarr" "Sonarr" "http://127.0.0.1:8989/ping"
    ++ box "radarr" "Radarr" "http://127.0.0.1:7878/ping"
    ++ box "lidarr" "Lidarr" "http://127.0.0.1:8686/ping"
    ++ box "readarr" "Readarr" "http://127.0.0.1:8787/ping"
    ++ box "prowlarr" "Prowlarr" "http://127.0.0.1:9696/ping"
    ++ box "navidrome" "Navidrome" "http://127.0.0.1:4533/ping"
    ++ box "audiobookshelf" "Audiobookshelf" "http://127.0.0.1:13378/healthcheck"
    ++ box "sabnzbd" "SABnzbd" "http://127.0.0.1:8081/"
    ++ box "qbittorrent" "qBittorrent" "http://127.0.0.1:8080/"
    ++ box "slskd" "slskd" "http://127.0.0.1:5031/"
    ++ box "pinchflat" "Pinchflat" "http://127.0.0.1:8945/"
    ++ box "books" "LazyLibrarian" "http://127.0.0.1:5299/"
    ++ box "calibre" "Calibre" "http://127.0.0.1:8083/"
    ++ box "gluetun" "Gluetun VPN" "http://127.0.0.1:8000/v1/publicip/ip"
    ++ lib.optional (on [ "hwc" "media" "frigate" "enable" ])
         (svc "Frigate NVR" "http://127.0.0.1:${toString config.hwc.media.frigate.port}/api/stats");
  localTcp =
    lib.optional (on [ "services" "postgresql" "enable" ]) (svc "PostgreSQL" "127.0.0.1:5432")
    ++ lib.optional (on [ "hwc" "data" "databases" "redis" "enable" ]) (svc "Redis" "127.0.0.1:6379")
    ++ box "immich-redis" "Immich Redis" "127.0.0.1:6380"
    ++ lib.optional (on [ "services" "mosquitto" "enable" ]) (svc "Mosquitto" "127.0.0.1:1883")
    ++ [ (svc "SSH" "127.0.0.1:22") ];

  # ---- central: aggregate the fleet ----------------------------------------
  selfName = config.networking.hostName;
  fleetConfigs = inputs.self.nixosConfigurations;
  hostCfg = h: if h == selfName then config else fleetConfigs.${h}.config;
  aliasOf = h: lib.findFirst (a: hosts.servers.${a} == h) null (lib.attrNames hosts.servers);
  members = lib.filter
    (h: (h == selfName || fleetConfigs ? ${h})
        && lib.attrByPath [ "hwc" "monitoring" "prometheus" "agent" "enable" ] false (hostCfg h))
    (lib.attrValues hosts.servers);
  ipOf = h: hosts.ips.${aliasOf h};
  localTarget = ip: t:
    let m = builtins.match "(localhost|127\\.0\\.0\\.1):([0-9]+)" t;
    in if m == null then t else "${ip}:${builtins.elemAt m 1}";

  hostJobs = h: map (j: j // {
    static_configs = map (sc: sc // {
      targets = map (localTarget (ipOf h)) sc.targets;
      labels = (sc.labels or { }) // { host = h; }
        // lib.optionalAttrs (builtins.length sc.targets == 1) { instance = h; };
    }) j.static_configs;
  }) (hostCfg h).hwc.monitoring.prometheus.scrapeConfigs;

  hostProbes = h:
    let a = (hostCfg h).hwc.monitoring.prometheus.agent; in
    map (p: {
      job_name = p.job;
      metrics_path = "/probe";
      scrape_interval = p.interval;
      params.module = [ p.module ];
      static_configs = map (t: {
        targets = [ t.url ];
        labels = t.labels // { host = h; __blackbox = "${ipOf h}:${toString a.blackboxPort}"; };
      }) p.targets;
      relabel_configs = [
        { source_labels = [ "__address__" ]; target_label = "__param_target"; }
        { source_labels = [ "__param_target" ]; target_label = "instance"; }
        { source_labels = [ "__blackbox" ]; target_label = "__address__"; }
      ];
    }) (hostCfg h).hwc.monitoring.prometheus.probes;

  # One job per name: the same job exported by several hosts merges its
  # static_configs (so rules/dashboards keep matching job="node" etc.).
  mergeJobs = jobs: lib.mapAttrsToList
    (_: group: (builtins.head group) // { static_configs = lib.concatMap (j: j.static_configs) group; })
    (lib.groupBy (j: j.job_name) jobs);

  fleetScrapeConfigs = mergeJobs (lib.concatMap (h: hostJobs h ++ hostProbes h) members);
  fleetRules = lib.concatMap (h: (hostCfg h).hwc.monitoring.prometheus.rules) members;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.monitoring.prometheus = {
    enable = lib.mkEnableOption "the central Prometheus (collects every serving host's exports)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Prometheus HTTP server port";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.state}/prometheus";
      description = "Data directory for Prometheus time-series database";
    };

    retention = lib.mkOption {
      type = lib.types.str;
      default = "30d";
      description = "Data retention period (e.g., '30d', '90d')";
    };

    agent = {
      enable = lib.mkEnableOption "this host's metrics agent (node + blackbox exporters on the tailnet)";
      listenAddress = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = hosts.selfIp;
        defaultText = lib.literalExpression "config.hwc.networking.hosts.selfIp";
        description = ''
          Address the exporters bind. The host's tailnet IP, never 0.0.0.0:
          a LAN interface can be trusted on a serving host, and the blackbox
          exporter will probe any URL it is handed.
        '';
      };
      nodePort = lib.mkOption { type = lib.types.port; default = 9100; description = "node exporter port"; };
      blackboxPort = lib.mkOption { type = lib.types.port; default = 9115; description = "blackbox exporter port"; };
    };

    scrapeConfigs = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      description = ''
        EXPORT: scrape jobs for exporters running on THIS host, with targets
        written as localhost:<port> (or 127.0.0.1:<port>). The central
        Prometheus rewrites them to this host's tailnet IP and adds a `host`
        label. Exporters must listen on agent.listenAddress to be reachable.
      '';
    };

    probes = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          job = lib.mkOption { type = lib.types.str; description = "Prometheus job name (rules/dashboards key on it)."; };
          module = lib.mkOption { type = lib.types.str; description = "Blackbox module (see blackboxModules)."; };
          interval = lib.mkOption { type = lib.types.str; default = "60s"; description = "Scrape interval."; };
          targets = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                url = lib.mkOption { type = lib.types.str; description = "Probe target."; };
                labels = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; description = "Extra series labels."; };
              };
            });
            description = "What to probe.";
          };
        };
      });
      default = [ ];
      description = "EXPORT: blackbox probes that THIS host's agent runs (loopback services here, or public URLs on the central host).";
    };

    rules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "EXPORT: extra rule groups (JSON/YAML strings) this host's modules contribute, e.g. Frigate's per-camera recording rules.";
    };
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    (lib.mkIf agent.enable {
      services.prometheus.exporters.node = {
        enable = true;
        port = agent.nodePort;
        listenAddress = agent.listenAddress;
      };
      services.prometheus.exporters.blackbox = {
        enable = true;
        port = agent.blackboxPort;
        listenAddress = agent.listenAddress;
        configFile = pkgs.writeText "blackbox.yml" (builtins.toJSON { modules = blackboxModules; });
      };

      # The tailnet address may appear after the unit starts at boot: wait for
      # tailscaled and retry instead of failing.
      systemd.services.prometheus-node-exporter = {
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        startLimitIntervalSec = 0;
        serviceConfig = {
          User = lib.mkForce "eric";
          Group = lib.mkForce "users";
          Restart = lib.mkForce "always";
          RestartSec = 5;
        };
      };
      systemd.services.prometheus-blackbox-exporter = {
        after = [ "tailscaled.service" ];
        wants = [ "tailscaled.service" ];
        startLimitIntervalSec = 0;
        serviceConfig = {
          User = lib.mkForce "eric";
          Group = lib.mkForce "users";
          Restart = lib.mkForce "always";
          RestartSec = 5;
        };
      };

      hwc.monitoring.prometheus.scrapeConfigs = [{
        job_name = "node";
        static_configs = [{ targets = [ "localhost:${toString agent.nodePort}" ]; }];
      }];

      # Internal service liveness for what runs on this host (replaces the
      # Uptime Kuma monitors). Each entry carries a human `service` label.
      hwc.monitoring.prometheus.probes =
        lib.optional (localHttp != [ ]) { job = "probe-services-http"; module = "http_reachable"; targets = localHttp; }
        ++ [ { job = "probe-services-tcp"; module = "tcp_connect"; targets = localTcp; } ]
        ++ lib.optional (containers ? n8n)
             { job = "probe-n8n"; module = "http_health_check"; interval = "30s"; targets = [ { url = "http://127.0.0.1:5678/healthz"; } ]; };

      assertions = [{
        assertion = agent.listenAddress != null;
        message = "hwc.monitoring.prometheus.agent needs a listenAddress (this host is not in hwc.networking.hosts.servers).";
      }];
    })

    (lib.mkIf cfg.enable {
      # Public and cross-host probes live with the central host (they are the
      # same from anywhere); its own agent runs them.
      hwc.monitoring.prometheus.probes = [
        # Public website pages + GEO artifacts (through Cloudflare, like a visitor)
        { job = "probe-website"; module = "http_health_check"; targets = map (url: { inherit url; }) [
            "https://iheartwoodcraft.com/"
            "https://iheartwoodcraft.com/calculator/"
            "https://iheartwoodcraft.com/deck-calculator/"
            "https://iheartwoodcraft.com/contact/"
            "https://iheartwoodcraft.com/sitemap.xml"
            "https://iheartwoodcraft.com/robots.txt"
            "https://iheartwoodcraft.com/llms.txt"
            "https://iheartwoodcraft.com/js/calculator.bundle.js"
          ]; }
        # Public webhook ingress (Cloudflare proxy → tunnel → n8n) via CORS
        # preflight on a live webhook (estimate-push; calculator-lead was retired 2026-09-25)
        { job = "probe-webhook-ingress"; module = "http_options_2xx";
          targets = [ { url = "https://api.iheartwoodcraft.com/webhook/estimate-push"; } ]; }
        # hwc-crm public intake via CORS preflight (touches no data)
        { job = "probe-crm-intake"; module = "http_options_2xx"; targets = map (url: { inherit url; }) [
            "https://crm.iheartwoodcraft.com/hooks/contact"
            "https://crm.iheartwoodcraft.com/hooks/calculator"
          ]; }
        # hwc-leads liveness + HMAC enforcement (401 on unsigned POST)
        { job = "probe-leads-service"; module = "http_post_401"; interval = "30s";
          targets = [ { url = "${vhost "hwc-leads"}/leads"; } ]; }
        # CMS API (auth-walled: 200 or 401 = alive)
        { job = "probe-cms"; module = "http_2xx_or_401";
          targets = [ { url = "${vhost "heartwood-cms"}/api/health"; } ]; }
        # Umami — heartbeat + public collect ingress
        { job = "probe-umami"; module = "http_health_check"; targets = map (url: { inherit url; }) [
            "${vhost "umami"}/api/heartbeat"
            "https://stats.iheartwoodcraft.com/api/heartbeat"
          ]; }
      ];

      services.prometheus = {
        enable = true;
        port = cfg.port;
        stateDir = "hwc/prometheus";
        retentionTime = cfg.retention;
        globalConfig = {
          scrape_interval = "15s";
          evaluation_interval = "15s";
        };
        scrapeConfigs = fleetScrapeConfigs;
        # Alert rules organized by severity (P5/P4/P3), plus every host's
        # exported rule groups (e.g. Frigate's camera recording rules).
        ruleFiles = [
          (pkgs.writeText "prometheus-alerts.yml" (builtins.toJSON (import ./parts/alerts.nix { inherit lib; })))
        ];
        rules = fleetRules;
      };

      systemd.services.prometheus.serviceConfig = {
        User = lib.mkForce "eric";
        Group = lib.mkForce "users";
        StateDirectory = lib.mkForce "hwc/prometheus";
        WorkingDirectory = lib.mkForce "${paths.state}/prometheus";
      };

      #========================================================================
      # VALIDATION
      #========================================================================
      assertions = [
        {
          assertion = builtins.match "^[0-9]+d$" cfg.retention != null;
          message = "Prometheus retention must be in format '<number>d' (e.g., '30d', '90d')";
        }
        {
          assertion = members != [ ];
          message = "The central Prometheus found no serving host with hwc.monitoring.prometheus.agent enabled.";
        }
      ];
    })
  ];
}
