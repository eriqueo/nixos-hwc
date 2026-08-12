# domains/networking/hosts.nix
#
# HOST REGISTRY — single source of truth for tailnet (MagicDNS) identities.
#
# Two distinct concepts, deliberately separated:
#
#   * "My own serving domain"  -> hwc.networking.shared.{rootHost,tailscaleDomain}
#       (declared in reverseProxy.nix; defaults derive from THIS host's
#        networking.hostName). Only ever the local host's own name, so a
#        server's Caddy can never accidentally advertise another host's name.
#
#   * "Address of a SPECIFIC named server" -> hwc.networking.hosts.fqdn.<alias>
#       (this file). For any cross-host reference (xps -> main, a laptop app ->
#       main, a customer-facing webhook base). Names the target explicitly and
#       is identical on every host, so it never derives from the local hostname.
#
# The tailnet suffix lives in ONE place (tailnetSuffix). Rename the tailnet or
# migrate off Tailscale -> change it here. Rename a box -> change its entry in
# `servers` (and its networking.hostName). Add a server -> one line.
#
# Folder->namespace: domains/networking/ -> hwc.networking.*

{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.hwc.networking.hosts;
  mkFqdn = host: "${host}.${cfg.tailnetSuffix}";
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.networking.hosts = {
    tailnetSuffix = mkOption {
      type = types.str;
      default = "ocelot-wahoo.ts.net";
      description = ''
        Tailnet (MagicDNS) domain suffix shared by every host. The ONE place to
        change if the tailnet is renamed or you migrate off Tailscale.
      '';
    };

    servers = mkOption {
      type = types.attrsOf types.str;
      default = {
        main = "hwc-server";   # primary server
        xps  = "hwc-xps";      # peer server
        # work = "hwc-work";   # future work server — uncomment when built
      };
      description = ''
        Server registry: logical alias -> tailnet hostname. The canonical set of
        valid servers. Reference an address via `fqdn.<alias>` or the `url`
        helper; never derive a cross-host address from the local hostname.
      '';
    };

    ips = mkOption {
      type = types.attrsOf types.str;
      default = {
        main = "100.77.195.118";
        xps  = "100.126.80.42";
      };
      description = ''
        Server alias -> Tailscale IP. The single producer for every raw tailnet
        address in the repo; consumers read `ips.<alias>` instead of retyping.

        Why IPs at all, when MagicDNS exists: hwc-laptop has a recorded failure
        mode where a suspend/resume or wifi flap drops the per-tailnet route and
        `*.ts.net` lookups return NXDOMAIN. Consumers that pin an IP do so
        deliberately, to keep working when MagicDNS does not. That fence stands
        — this option moves the literal, it does not remove it.

        These values are NOT stable identifiers. A node that re-registers (a
        `tailscale logout`, a reinstall, OAuth re-registration) can come back as
        a new device with a new address: on 2026-08-12 hwc-server moved
        100.114.232.124 -> 100.77.195.118 exactly that way, and because the old
        value had been copied into four live files, one re-registration broke
        ssh, the `server` alias, syncthing, and every `*.local` name at once.
        That cascade is the reason this option exists. Re-address a box -> edit
        one line here.
      '';
    };

    primary = mkOption {
      type = types.str;
      default = "main";
      description = "Alias (a key of `servers`) of the primary server.";
    };

    # ---- derived, read-only ----
    fqdn = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Derived: server alias -> full tailnet FQDN (`<hostname>.<tailnetSuffix>`).";
    };

    url = mkOption {
      type = types.functionTo types.str;
      readOnly = true;
      description = ''
        Helper to compose a full service URL on a registered server. Port and
        subpath live at the call site (they are per-service, not per-host):

          config.hwc.networking.hosts.url { server = "main"; port = 6443; path = "/sab"; }
            => "https://hwc-server.ocelot-wahoo.ts.net:6443/sab"
          config.hwc.networking.hosts.url { path = "/webhook/estimate-push"; }
            => "https://hwc-server.ocelot-wahoo.ts.net/webhook/estimate-push"

        Args (all optional): server (default = primary), scheme (default
        "https"), port (default null = omit), path (default "").
      '';
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config.hwc.networking.hosts = {
    fqdn = lib.mapAttrs (_alias: host: mkFqdn host) cfg.servers;

    url = { server ? cfg.primary, scheme ? "https", port ? null, path ? "" }:
      let
        host     = cfg.fqdn.${server};
        portPart = lib.optionalString (port != null) ":${toString port}";
      in "${scheme}://${host}${portPart}${path}";
  };

  #============================================================================
  # VALIDATION
  #============================================================================
  config.assertions = [
    {
      assertion = builtins.hasAttr cfg.primary cfg.servers;
      message = "hwc.networking.hosts.primary (\"${cfg.primary}\") must be a key in hwc.networking.hosts.servers (${lib.concatStringsSep ", " (lib.attrNames cfg.servers)}).";
    }
    {
      # Keep the two halves of the registry in lockstep. Without this a server
      # can be added to `servers` with no address, and the gap only surfaces at
      # the consumer as a missing-attribute error far from the cause.
      assertion = lib.attrNames cfg.ips == lib.attrNames cfg.servers;
      message = ''
        hwc.networking.hosts.ips and .servers must cover the same aliases.
          servers: ${lib.concatStringsSep ", " (lib.attrNames cfg.servers)}
          ips:     ${lib.concatStringsSep ", " (lib.attrNames cfg.ips)}
        Adding a server means adding both its hostname and its Tailscale IP.
      '';
    }
  ];
}
