{ lib, config, pkgs, ... }:
let
  inherit (lib) mkEnableOption mkOption types mkIf concatStringsSep;

  tailscaleDomain = config.hwc.networking.shared.tailscaleDomain;
  rootHost        = config.hwc.networking.shared.rootHost;
  # During the service split, legacy Caddy hosts keep their existing route
  # table. A host with routeOwner set serves only explicitly assigned routes;
  # remove the legacy null mode once every route has an owner and xps has an
  # explicit serving role.
  routeOwner      = config.hwc.networking.reverseProxy.routeOwner;
  routes          = lib.filter
    (r: routeOwner == null || (r.owner or "main") == routeOwner)
    config.hwc.networking.shared.effectiveRoutes;

  # Route ownership has one producer: shared.routeOwners (routes.nix), the
  # same on every host. It stamps `owner` onto the matching local route, and
  # for a vhost whose owner is another host and which has no local route (its
  # module is off here) it adds a name-only stub, so this host still proxies
  # the name and the laptop still pins it.
  hostAliases = config.hwc.networking.hosts.servers;
  ownerMap = config.hwc.networking.shared.routeOwners;
  declaredRoutes = config.hwc.networking.shared.routes;
  localRouteNames = map (r: r.name) declaredRoutes;
  ownedRoutes = map
    (r: if ownerMap ? ${r.name} then r // { owner = ownerMap.${r.name}.owner; } else r)
    declaredRoutes;
  # A port route belongs to one host's tailnet name (rootHost); another
  # owner's port route has nothing to serve here, so it is not rendered.
  isRemoteOwned = r: r ? owner && hostAliases.${r.owner} != config.networking.hostName;
  localPortRoutes = lib.filter (r: r.mode == "port" && !(isRemoteOwned r)) routes;

  # The root site's /mcp handler follows the gateway to its host.
  mcpAlias = config.hwc.system.mcp.serverAlias or "main";
  mcpUpstream =
    if hostAliases.${mcpAlias} == config.networking.hostName
    then "127.0.0.1:${toString (config.hwc.system.mcp.port or 6200)}"
    else "${config.hwc.networking.hosts.ips.${mcpAlias}}:${toString (config.hwc.system.mcp.port or 6200)}";

  remoteStubs = lib.mapAttrsToList
    (name: o: { inherit name; mode = "vhost"; owner = o.owner; })
    (lib.filterAttrs
      (name: o: o.mode == "vhost"
        && !(lib.elem name localRouteNames)
        && hostAliases.${o.owner} != config.networking.hostName)
      ownerMap);
  vhostDomain     = config.hwc.networking.shared.vhostDomain;
  subpathRoutes   = lib.filter (r: r.mode == "subpath") routes;

  # This host's own tailnet FQDN, derived from its hostname + the one shared
  # tailnet suffix (see domains/networking/hosts.nix). A server's serving domain
  # always follows its own hostname, so a rename auto-propagates to every route.
  selfDomain = "${config.networking.hostName}.${config.hwc.networking.hosts.tailnetSuffix}";

  # Common reverse_proxy block, shared by the subpath/port and vhost renderers.
  # (No invalid transport stanza.)
  mkProxyBlock = r:
    let
      ws = r.ws or true;  # websocket support by default
      renderHeaders = concatStringsSep "\n"
        (lib.mapAttrsToList (name: value: "header_up ${name} ${value}") (r.headers or {}));
    in ''
      reverse_proxy ${r.upstream} {
        header_up Host {host}
        header_up X-Real-IP {remote}
        header_up X-Forwarded-For {remote}
        header_up X-Forwarded-Proto {scheme}
        header_up X-Forwarded-Host {host}
        ${renderHeaders}
        ${lib.optionalString ws "flush_interval -1"}
        ${lib.optionalString (r ? tlsServerName) ''
          transport http {
            tls_server_name ${r.tlsServerName}
          }
        ''}
      }
    '';

  # Render a route -> Caddy snippet
  renderRoute = r:
    let
      # schema defaults
      assetGlobs    = r.assetGlobs or [ "/css/*" "/js/*" "/assets/*" "/images/*" "/static/*" "/fonts/*" "/webfonts/*" "/favicon.ico" ];
      assetStrategy = r.assetStrategy or "none";
      needsUrlBase  = r.needsUrlBase or false;      # NEW: drives preserve vs strip
      stripPrefix   = r.stripPrefix or false;       # deprecated; ignored when needsUrlBase = true
      timeouts      = r.timeouts or { try = "10s"; fail = "5s"; };

      # common reverse_proxy block (shared helper)
      proxyBlock = mkProxyBlock r;

      # legacy/optional asset handlers (default is none)
      assetHandlers = {
        none = "";
        rewrite = ''
          @assets_${r.name} path ${concatStringsSep " " assetGlobs}
          rewrite @assets_${r.name} ${r.path}{uri}
        '';
        referer = ''
          @assets_${r.name} {
            path ${concatStringsSep " " assetGlobs}
            header Referer *${r.path}*
          }
          handle @assets_${r.name} {
            ${proxyBlock}
          }
        '';
      };

      # helpers to emit preserve/strip variants for subpaths
      subpathPreserve = ''
        @${r.name} path ${r.path}*
        redir ${r.path} ${r.path}/ 301
        handle @${r.name} {
          ${proxyBlock}
        }
        ${assetHandlers.${assetStrategy}}
      '';

      subpathStrip = ''
        redir ${r.path} ${r.path}/ 301
        handle_path ${r.path}* {
          ${proxyBlock}
        }
        ${assetHandlers.${assetStrategy}}
      '';
      # Static file server block (for mode = "static")
      staticBlock = ''
        # Static file server on dedicated TLS port
        ${rootHost}:${toString r.port} {
          tls {
            get_certificate tailscale
            protocols tls1.2 tls1.3
            alpn h2 http/1.1
          }
          encode zstd gzip

          # CORS headers for cross-origin embedding
          header Access-Control-Allow-Origin "*"
          header Access-Control-Allow-Methods "GET, OPTIONS"
          header Access-Control-Allow-Headers "Content-Type"

          # Cache static assets
          header Cache-Control "public, max-age=31536000, immutable"

          root * ${r.root}
          try_files {path} /index.html
          file_server
        }
      '';
    in
      if r.mode == "subpath" then
        # If the app has a URL base, we must preserve the path; otherwise we may strip.
        (if needsUrlBase then subpathPreserve else subpathStrip)
      else if r.mode == "port" then ''
        # Dedicated TLS listener on the tailscale host:port
        ${rootHost}:${toString r.port} {
          tls {
            get_certificate tailscale
            protocols tls1.2 tls1.3
            alpn h2 http/1.1
          }
          encode zstd gzip
          ${proxyBlock}
        }
      ''
      else if r.mode == "static" then staticBlock
      else "";

  # Name-based virtual hosts under the wildcard subzone (mode = "vhost").
  # Each app gets a clean root path on :443 — no dedicated port, no firewall
  # hole — served behind a single wildcard cert (*.<vhostDomain>) via ACME DNS-01.
  vhostRoutes = lib.filter (r: (r.mode or "") == "vhost") routes;

  renderVhostRoute = r:
    let
      # An owner is the one host with the local backend. Legacy Caddy hosts
      # proxy to it during DNS propagation and while clients retain a pinned
      # server address; the tailnet IP avoids a DNS loop through this Caddy.
      ownerHost = if r ? owner then config.hwc.networking.hosts.servers.${r.owner} else null;
      remoteOwner = ownerHost != null && config.networking.hostName != ownerHost;
      remoteRoute = r // {
        upstream = "https://${config.hwc.networking.hosts.ips.${r.owner}}";
        tlsServerName = "${r.name}.${vhostDomain}";
      };
      # A vhost route is either a reverse proxy (has `upstream`) or a static
      # file server (has `root`), served under its own host matcher on :443.
      body =
        if remoteOwner then mkProxyBlock remoteRoute
        else if r ? root then ''
          # Static file server (CORS-enabled for cross-origin embedding).
          # Only hashed build assets are cached immutably; the SPA/PWA shell and
          # generated data files revalidate so updates are picked up.
          header Access-Control-Allow-Origin "*"
          header Access-Control-Allow-Methods "GET, OPTIONS"
          header Access-Control-Allow-Headers "Content-Type"
          header /assets/* Cache-Control "public, max-age=31536000, immutable"
          ${if (r ? api) then ''
          # Same-origin API proxy (optional `api = { path; upstream; }` on a
          # static vhost) — lets a served SPA call a loopback service without
          # CORS or a second vhost. The static half sits in a sibling catch-all
          # handle: bare try_files is a REWRITE and would run before `handle`
          # in Caddy's directive order, turning POST ${r.api.path} into
          # /index.html (file_server → 405). Sibling handles are mutually
          # exclusive and most-specific-path wins, which is what we want.
          handle ${r.api.path}* {
            reverse_proxy ${r.api.upstream}
          }
          handle {
            root * ${r.root}
            try_files {path} /index.html
            file_server
          }
          '' else ''
          root * ${r.root}
          try_files {path} /index.html
          file_server
          ''}
        ''
        else mkProxyBlock r;
    in ''
      @${r.name} host ${r.name}.${vhostDomain}
      handle @${r.name} {
        ${body}
      }
    '';

  # Single wildcard site block; emitted only when at least one vhost route
  # exists (so the config is byte-for-byte unchanged until the first migration).
  vhostBlock = lib.optionalString (vhostRoutes != [ ]) ''
    *.${vhostDomain} {
      tls {
        dns desec {
          token {env.DESEC_TOKEN}
        }
        resolvers 1.1.1.1
        # deSEC publishes zone changes on a ~60s batch cycle and Let's Encrypt
        # does multi-perspective (secondary) validation — wait for the TXT to
        # land on all deSEC nameservers before asking LE to validate.
        propagation_delay 120s
        propagation_timeout 600s
      }
      encode zstd gzip
      # Access log for all name-based vhosts; per-route split via the host field.
      log {
        output file /var/log/caddy/access-vhosts.log {
          roll_size 50MiB
          roll_keep 5
          roll_keep_for 30d
        }
        format json
      }
      ${concatStringsSep "\n" (map renderVhostRoute vhostRoutes)}

      # A name with no route is a 404, not Caddy's empty 200: the empty 200
      # made a retired app (market-intelligence) look alive and would let a
      # blackbox probe on a vanished vhost stay green. Matcher-less handle =
      # fallback after every host-matched handle above.
      handle {
        respond "no route for {host}" 404
      }
    }
  '';

  # A work-only vhost host has no legacy tailnet-root routes. Do not publish a
  # root site with an inert /mcp handler and no backend on that host.
  rootBlock = lib.optionalString
    (subpathRoutes != [ ] || (config.hwc.ai.mcp.proxy.enable or false)) ''
      ${rootHost} {
        tls {
          get_certificate tailscale
          protocols tls1.2 tls1.3
          alpn h2 http/1.1
        }
        encode zstd gzip

        # Access log (route-level analytics derive from the host+uri fields).
        # Size-capped rolling — caddy logs once filled the disk here.
        log {
          output file /var/log/caddy/access-root.log {
            roll_size 50MiB
            roll_keep 5
            roll_keep_for 30d
          }
          format json
        }

        # MCP routes — proxy to hwc-sys Express server (priority over subpath routes)
        @mcp_routes {
          path /mcp /mcp/* /health /.well-known/*
        }
        handle @mcp_routes {
          reverse_proxy ${mcpUpstream} {
            flush_interval -1
            transport http {
              read_timeout 0
              write_timeout 0
            }
          }
        }

        # All subpath routes (sonarr, radarr, navidrome, etc.)
        ${concatStringsSep "\n" (map renderRoute subpathRoutes)}
      }
    '';

in
{
  options.hwc.networking.reverseProxy = {
    enable = mkEnableOption "Reverse proxy service (Caddy)";
    routeOwner = mkOption {
      type = types.nullOr (types.enum (lib.attrNames config.hwc.networking.hosts.servers));
      default = null;
      description = "When set, serve only routes assigned to this host alias; null retains legacy route behavior during the split.";
    };
    domain = mkOption {
      type = types.str;
      default = selfDomain;
      defaultText = "\${config.networking.hostName}.\${config.hwc.networking.hosts.tailnetSuffix}";
      description = "Domain for reverse proxy services (defaults to this host's own tailnet FQDN).";
    };
  };

  options.hwc.networking.shared = {
    tailscaleDomain = mkOption {
      type = types.str;
      default = selfDomain;
      defaultText = "\${config.networking.hostName}.\${config.hwc.networking.hosts.tailnetSuffix}";
      description = "This host's own Tailscale (MagicDNS) FQDN.";
    };
    rootHost = mkOption {
      type = types.str;
      default = selfDomain;
      defaultText = "\${config.networking.hostName}.\${config.hwc.networking.hosts.tailnetSuffix}";
      description = "Root host for subpath and port-based services (this host's own tailnet FQDN).";
    };
    routes = mkOption {
      # New schema keys supported per route:
      # name, mode=("subpath"|"port"|"static"|"vhost"), path, port, upstream,
      # root (static), needsUrlBase=bool, stripPrefix=bool (deprecated),
      # headers=attrs, assetGlobs, assetStrategy, ws=bool, timeouts={try,fail}
      # mode="vhost": served as <name>.<vhostDomain> on :443 (no port field).
      #
      # lazyAttrsOf, not attrsOf (2026-09-16): attrsOf forces EVERY attribute of
      # an element as soon as one is read, so a route whose `root` is derived
      # from the other routes (hwc.business.workbench resolves its area
      # destinations from this list) recursed infinitely on its own `name`.
      # lazyAttrsOf merges per attribute on access; values are unchanged.
      type = types.listOf (types.lazyAttrsOf types.anything);
      default = [];
      description = "Aggregated reverse proxy routes for all services.";
    };
    routeOwners = mkOption {
      # A bare alias means a vhost; port routes say so, because a missing
      # port route gets no stub (there is no name to proxy).
      type = types.attrsOf (types.coercedTo
        (types.enum (lib.attrNames config.hwc.networking.hosts.servers))
        (owner: { inherit owner; })
        (types.submodule {
          options = {
            owner = mkOption { type = types.enum (lib.attrNames config.hwc.networking.hosts.servers); };
            mode = mkOption { type = types.enum [ "vhost" "port" ]; default = "vhost"; };
          };
        }));
      default = { };
      example = { calculator = "work"; brain-mcp = { owner = "work"; mode = "port"; }; };
      description = ''
        Route name → host alias (hwc.networking.hosts.servers) that runs its
        backend. Routes not listed belong to "main". Declared once (routes.nix)
        and evaluated identically on every host: a routeOwner host renders only
        its own routes, legacy hosts proxy other owners' vhosts to them over the
        tailnet, and the laptop pins each vhost name to its owner. Moving an
        app's route is one entry here.
      '';
    };
    effectiveRoutes = mkOption {
      type = types.listOf (types.lazyAttrsOf types.anything);
      readOnly = true;
      description = ''
        `routes` with `owner` applied from `routeOwners`, plus a name-only vhost
        stub for each remotely owned vhost that has no local route. Every
        consumer of route ownership (Caddy rendering, laptop pins, workbench
        area resolution) reads this, not `routes`.
      '';
    };
    vhostDomain = mkOption {
      type = types.str;
      default = "hwc.iheartwoodcraft.com";
      description = ''
        Wildcard subzone for name-based vhost routes (mode = "vhost").
        Each such route is served at <name>.<vhostDomain> on :443 behind a single
        *.<vhostDomain> cert obtained via ACME DNS-01 (deSEC). The subzone is
        NS-delegated to a separate DNS account so the DNS-01 token on this host
        cannot touch the apex zone or its MX records.
      '';
    };
  };

  config = lib.mkMerge [
  { hwc.networking.shared.effectiveRoutes = ownedRoutes ++ remoteStubs; }

  (mkIf config.hwc.networking.reverseProxy.enable {
    services.caddy = {
      enable = true;
      # Caddy with the deSEC DNS provider compiled in, for ACME DNS-01 issuance
      # of the *.<vhostDomain> wildcard cert used by mode = "vhost" routes.
      package = pkgs.caddy.withPlugins {
        plugins = [ "github.com/caddy-dns/desec@v1.1.0" ];
        # FOD hash tracks the vendored Go deps of caddy+plugin; nixpkgs source
        # or packaging changes can alter it even when caddy's version is unchanged.
        # Last refreshed for the 26.05 input update (2026-09).
        hash = "sha256-oEKfWN5U1LI25vNvr/QZE2C8PQyIgBAGH/1YhUDoGr0=";
      };
      extraConfig = ''
        # Root tailnet listener exists only where subpath routes or MCP need it.
        ${rootBlock}

        ${concatStringsSep "\n" (map renderRoute localPortRoutes)}

        ${concatStringsSep "\n" (map renderRoute (lib.filter (r: r.mode == "static") routes))}

        # Name-based wildcard vhosts (mode = "vhost"); empty until first migration.
        ${vhostBlock}
      '';
    };

    # Run caddy as eric user for simplified permissions
    systemd.services.caddy = {
      serviceConfig = {
        User = lib.mkForce "root";
        Group = lib.mkForce "root";
        # Disable security restrictions so eric can access directories
        PrivateUsers = lib.mkForce false;
        ProtectHome = lib.mkForce false;
        # deSEC API token (DESEC_TOKEN=...) for the *.vhostDomain DNS-01 wildcard.
        EnvironmentFile = config.age.secrets.caddy-desec-token.path;
      };
    };

    networking.firewall.allowedTCPPorts =
      [ 80 443 ]
      ++ (lib.map (r: r.port) (localPortRoutes ++ lib.filter (r: r.mode == "static") routes));
  })
  ];
}
