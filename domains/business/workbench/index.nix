# domains/business/workbench — HWC Workbench hub
#
# The product home for the seven HWC operator areas (CRM, Finance, Lead Scout,
# Home Scout, Research Scout, Event Scout, Refinery). This module is the ONE producer of the
# area registry: ids, labels, order and descriptions are declared here; each
# area's destination is RESOLVED from hwc.networking.shared.routes rather than
# copied, so a route rename or removal fails evaluation instead of shipping a
# dead link. Apps consume the same registry at runtime from
# https://workbench.<vhostDomain>/areas.json (static vhosts already answer with
# Access-Control-Allow-Origin: *), so adding a seventh area is one entry in
# `areas` plus that area's own route/deploy work — no edit in any app shell.
#
# The hub itself is rendered at evaluation time into a store path and served by
# a static `root` vhost (briefing precedent). No service, no port, no runtime
# JavaScript needed to list the areas: an unavailable area cannot break the page.
#
# Living architecture: brain tech/development/builds/hwc_web_app_shell.md.
#
# NAMESPACE: hwc.business.workbench.*

{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.business.workbench;
  vhostDomain = config.hwc.networking.shared.vhostDomain;
  # effectiveRoutes: includes stubs for vhosts another host owns (routeOwners).
  routes = config.hwc.networking.shared.effectiveRoutes;
  # Routes this host serves, plus routes declared as served by another host
  # of the fleet (cfg.remoteRoutes). Both resolve to the same
  # https://<route>.<vhostDomain>/ URL because DNS, not this host, picks the
  # server for a name.
  vhostNames = map (r: r.name) (lib.filter (r: (r.mode or "") == "vhost") routes)
    ++ cfg.remoteRoutes;

  homeUrl = "https://${cfg.routeName}.${vhostDomain}/";

  resolveArea = area:
    let deployed = lib.elem area.route vhostNames;
    in area // {
      available = deployed;
      href = if deployed then "https://${area.route}.${vhostDomain}/" else null;
    };
  resolved = map resolveArea cfg.areas;

  ids = map (a: a.id) cfg.areas;
  # subtractLists (unique ids) ids is always [] (it removes every id); count
  # each distinct id instead. Seeded and watched fail on 2026-09-16.
  duplicateIds = lib.filter (id: lib.count (x: x == id) ids > 1) (lib.unique ids);
  unresolvedRequired = lib.filter (a: a.required && !(lib.elem a.route vhostNames)) cfg.areas;

  registry = {
    product = cfg.productName;
    home = homeUrl;
    areas = map (a: {
      inherit (a) id label description available href;
    }) resolved;
  };
  areasJson = pkgs.writeText "hwc-workbench-areas.json" (builtins.toJSON registry);

  esc = lib.escapeXML;
  # Glyph = initials of the label ("Lead Scout" → LS, "Refinery" → RE), so a
  # new area needs no icon asset and siblings stay distinguishable.
  glyph = a:
    let
      words = lib.filter (w: w != "") (lib.splitString " " a.label);
      initials =
        if builtins.length words >= 2
        then lib.concatMapStrings (w: builtins.substring 0 1 w) (lib.take 2 words)
        else builtins.substring 0 2 a.label;
    in esc (lib.toUpper initials);
  renderArea = a:
    if a.available then ''
      <li>
        <a class="area" href="${esc a.href}">
          <span class="area-glyph" aria-hidden="true">${glyph a}</span>
          <span class="area-label">${esc a.label}</span>
          <span class="area-desc">${esc a.description}</span>
          <span class="area-foot">
            <span class="area-host">${esc a.route}.${esc vhostDomain}</span>
            <span class="area-go" aria-hidden="true">open →</span>
          </span>
        </a>
      </li>
    '' else ''
      <li>
        <span class="area area-unavailable" aria-disabled="true">
          <span class="area-glyph" aria-hidden="true">${glyph a}</span>
          <span class="area-label">${esc a.label}</span>
          <span class="area-desc">${esc a.description}</span>
          <span class="area-foot">
            <span class="area-host">not deployed on this host</span>
            <span class="area-go">unavailable</span>
          </span>
        </span>
      </li>
    '';

  indexHtml = pkgs.writeText "hwc-workbench-index.html" ''
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <meta name="theme-color" content="#1d2021">
    <title>${esc cfg.productName}</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@600&family=DM+Sans:wght@400;500;600&family=JetBrains+Mono:wght@400;600&display=swap">
    <link rel="stylesheet" href="/palette.css">
    <link rel="stylesheet" href="/hub.css">
    </head>
    <body>
    <main class="hub">
      <header class="hub-head">
        <span class="hub-mark" aria-hidden="true">H</span>
        <div>
          <p class="hub-eyebrow">heartwood craft · operator tools</p>
          <h1>${esc cfg.productName}<em>.</em></h1>
          <p class="hub-sub">Choose an area. Each one opens in place at its own address.</p>
        </div>
      </header>
      <nav aria-label="Workbench areas">
        <ul class="areas">
    ${lib.concatMapStringsSep "\n" renderArea resolved}
        </ul>
      </nav>
      <footer class="hub-foot">
        <span>${toString (lib.count (a: a.available) resolved)} of ${toString (builtins.length resolved)} areas deployed</span>
        <a href="/areas.json">areas.json</a>
      </footer>
    </main>
    </body>
    </html>
  '';

  hubSite = pkgs.runCommand "hwc-workbench-hub" { } ''
    mkdir -p $out
    cp ${indexHtml} $out/index.html
    cp ${areasJson} $out/areas.json
    cp ${./hub/palette.css} $out/palette.css
    cp ${./hub/hub.css} $out/hub.css
  '';

  areaType = lib.types.submodule {
    options = {
      id = lib.mkOption {
        type = lib.types.strMatching "[a-z][a-z0-9-]*";
        description = "Stable area id. Consumers key on this; never rename casually.";
      };
      label = lib.mkOption {
        type = lib.types.str;
        description = "Operator-facing label.";
      };
      route = lib.mkOption {
        type = lib.types.str;
        description = ''
          Name of the `mode = "vhost"` route in hwc.networking.shared.routes that
          serves this area. The destination is resolved from it, never typed here.
        '';
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "One-line purpose shown on the hub.";
      };
      required = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          When true, a missing route fails evaluation. When false, the area is
          listed as unavailable ("not deployed on this host") instead.
        '';
      };
    };
  };
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.business.workbench = {
    enable = lib.mkEnableOption "HWC Workbench hub (area registry + launcher)";

    productName = lib.mkOption {
      type = lib.types.str;
      default = "HWC Workbench";
      description = "Product identity shown by the hub and returned in areas.json.";
    };

    routeName = lib.mkOption {
      type = lib.types.str;
      default = "workbench";
      description = "Vhost name of the hub: <routeName>.<vhostDomain>.";
    };

    remoteRoutes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "crm" "event-scout" ];
      description = ''
        Vhost route names served by another host in the fleet, treated as
        deployed for the area list and the `required` assertion. Service
        split scaffolding: each name leaves this list when its app moves to
        the host serving the hub (the assertion then re-checks it locally).
      '';
    };


    areas = lib.mkOption {
      type = lib.types.listOf areaType;
      description = ''
        Ordered area registry. The order here is the order every switcher
        shows. DataX Monitor is deliberately absent: it is an adjacent operator
        tool, not a Workbench area (living note, "Related surfaces").
      '';
      default = [
        { id = "crm"; label = "CRM"; route = "crm";
          description = "Funnel board, follow-ups, intake"; }
        { id = "finance"; label = "Finance"; route = "firefly-explorer";
          description = "Recurring payments and transaction review"; }
        { id = "lead-scout"; label = "Lead Scout"; route = "lead-scout";
          description = "Lead discovery and triage"; }
        { id = "home-scout"; label = "Home Scout"; route = "home-scout";
          description = "Real-estate intelligence"; }
        { id = "research-scout"; label = "Research Scout"; route = "research-scout";
          description = "Research and paper intake"; }
        { id = "event-scout"; label = "Event Scout"; route = "event-scout";
          description = "Event discovery and curation"; }
        { id = "refinery"; label = "Refinery"; route = "refinery";
          description = "Automated work hopper"; }
      ];
    };

    registry = lib.mkOption {
      type = lib.types.attrs;
      readOnly = true;
      default = registry;
      description = "The resolved registry as served at /areas.json (for other modules/tests).";
    };

    site = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = hubSite;
      description = "The rendered hub (index.html, areas.json, css) served as the vhost root.";
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    # Tailnet-private vhost: workbench.<vhostDomain>, static store path.
    hwc.networking.shared.routes = [({
      name = cfg.routeName;
      mode = "vhost";
      root = "${hubSite}";
    })];

    # VALIDATION
    assertions = [
      {
        assertion = duplicateIds == [ ];
        message = "hwc.business.workbench: duplicate area id(s): ${lib.concatStringsSep ", " duplicateIds}";
      }
      {
        assertion = unresolvedRequired == [ ];
        message = "hwc.business.workbench: required area(s) name no vhost route: ${
          lib.concatMapStringsSep ", " (a: "${a.id} -> ${a.route}") unresolvedRequired
        }";
      }
      {
        assertion = !(lib.any (a: a.route == "monitor") cfg.areas);
        message = "hwc.business.workbench: DataX Monitor (route `monitor`) is outside HWC Workbench and must not be registered.";
      }
      {
        assertion = cfg.areas != [ ];
        message = "hwc.business.workbench: at least one area must be registered.";
      }
    ];
  };
}
