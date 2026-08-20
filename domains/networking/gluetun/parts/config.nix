# gluetun container configuration — one container per tunnel instance
{ lib, config, pkgs, ... }:
let
  # Import infrastructure container helper
  infraHelpers = import ../../../lib/mkInfraContainer.nix { inherit lib pkgs; };
  inherit (infraHelpers) mkInfraContainers;

  cfg = config.hwc.networking.gluetun;
  appsRoot = config.hwc.paths.apps.root;
  instances = lib.filterAttrs (_: i: i.enable) cfg.instances;

  # Instance "gluetun" resolves to the pre-existing ${appsRoot}/gluetun, so the
  # multi-instance conversion did not move the live tunnel's servers.json or
  # state. No special case — the name IS the directory.
  dataDir = name: "${appsRoot}/${name}";
  stateDir = name: "${cfg.stateRoot}/${name}";

  #==========================================================================
  # CONTAINER — one per instance
  #==========================================================================
  tunnelSpec = name: i: {
    image = i.image;

    # The tunnel itself sits on the media network; its passengers sit in ITS
    # netns and are reachable from the media network at i.networkAlias.
    networkMode = "media-network";
    networkAliases = [ i.networkAlias ];

    capabilities = [ "NET_ADMIN" "SYS_MODULE" ];
    devices = [ "/dev/net/tun:/dev/net/tun" ];
    privileged = true;

    # Every port belonging to a container in this netns, plus the control
    # server (container side is always 8000).
    ports = i.ports ++ [ "127.0.0.1:${toString i.controlPort}:8000" ];

    volumes = [ "${dataDir name}:/gluetun" ];

    environmentFiles = [ "${dataDir name}/.env" ];

    environment = {
      TZ = config.time.timeZone or "America/Denver";
      DOT = "off";                # DNS over TLS was causing timeouts
      DNS_ADDRESS = i.dns;
      # Control server auth off so port-sync and the health check can query the
      # forwarded port over loopback.
      HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE = ''{"auth":"none"}'';
    };

    # Env file is generated from agenix at start; the private key never lands
    # in the nix store.
    preStartScript = ''
      mkdir -p ${dataDir name}
      WG_PRIVATE_KEY=$(cat ${config.age.secrets.${i.privateKeySecret}.path})
      cat > ${dataDir name}/.env <<EOF
# GENERATED — edit domains/networking/gluetun, not this file.
# ProtonVPN WireGuard + NAT-PMP port forwarding for instance '${name}'.
#
# Pinned server: ${if i.wireguard.serverLabel != "" then i.wireguard.serverLabel else "(unlabelled)"}
#
# VPN_SERVICE_PROVIDER=custom talks to exactly ONE server and can never fail
# over. If this pin dies the symptom is: `wg show` inside the netns reads
# "0 B received", and the health check escalates to `failed` after its backoff
# rather than restarting forever. Re-point hwc.networking.gluetun.instances.
# ${name}.wireguard.* at any port-forward-capable Proton WireGuard server; the
# current list is inside the container at /gluetun/servers.json:
#   podman exec ${name} cat /gluetun/servers.json \
#     | jq -r '.protonvpn.servers[] | select(.vpn=="wireguard" and .port_forward
#              and .country=="United States") | "\(.server_name) \(.ips[0]) \(.wgpubkey)"'
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=$WG_PRIVATE_KEY
WIREGUARD_ADDRESSES=${i.wireguard.addresses}
WIREGUARD_PUBLIC_KEY="${i.wireguard.publicKey}"
WIREGUARD_ENDPOINT_IP=${i.wireguard.endpointIp}
WIREGUARD_ENDPOINT_PORT=${toString i.wireguard.endpointPort}
WIREGUARD_PERSISTENT_KEEPALIVE_INTERVAL=${i.wireguard.keepalive}
VPN_PORT_FORWARDING=${if i.portForwarding.enable then "on" else "off"}
VPN_PORT_FORWARDING_PROVIDER=protonvpn
HEALTH_VPN_DURATION_INITIAL=30s
HEALTH_TARGET_ADDRESS=1.1.1.1:443
EOF
      chmod 600 ${dataDir name}/.env
      chown root:root ${dataDir name}/.env
    '';
    preStartDeps = [ "agenix.service" ];

    systemdAfter = [ "network-online.target" "init-media-network.service" ];
    systemdWants = [ "network-online.target" ];
  };

  #==========================================================================
  # PORT SYNC — the forwarded port is dynamic; the client must follow it
  #==========================================================================
  # Proton rotates the NAT-PMP port. A client left on a stale port keeps
  # working outbound and silently stops accepting inbound, which looks exactly
  # like health — the same absence-of-evidence trap that hid the slskd leak for
  # six weeks. So the port is published to ONE file per instance, and each
  # client's follower reads that file.
  portFile = name: "${stateDir name}/forwarded-port";

  # qBittorrent: live preference update over its API, no restart needed.
  syncQbittorrent = name: i: ''
    QBT_API="http://127.0.0.1:${toString config.hwc.media.qbittorrent.webPort}"
    SID=$(curl -sf -c - "$QBT_API/api/v2/auth/login" \
      --data "username=admin&password=il0wwlm?" 2>/dev/null | awk '/SID/ {print $NF}' || true)

    if [ -n "$SID" ]; then
      curl -sf -b "SID=$SID" "$QBT_API/api/v2/app/setPreferences" \
        --data "json={\"listen_port\":$FORWARDED_PORT}" && \
        echo "Updated qBittorrent listening port to $FORWARDED_PORT" || \
        echo "Failed to update qBittorrent port"
    else
      echo "Could not authenticate with qBittorrent"
    fi
  '';

  # slskd: its listen port lives in slskd.yml, which is generated from agenix
  # secrets by slskd-config-generator. Rather than rewriting the generated file
  # behind the generator's back (two producers of one line), the generator reads
  # the port file — so re-running it and restarting the container is the whole
  # sync. Restart only on change, so a steady port costs nothing.
  syncSlskd = name: i: ''
    echo "Regenerating slskd config for port $FORWARDED_PORT and restarting slskd"
    systemctl restart slskd-config-generator.service
    systemctl restart podman-slskd.service
  '';

  syncImpl = {
    qbittorrent = syncQbittorrent;
    slskd = syncSlskd;
  };

  mkPortSync = name: i: {
    "${name}-port-sync" = {
      description = "Sync ${name} forwarded port to ${i.portForwarding.syncTo}";
      # Ordered after the client too: the loop recovers either way, but starting
      # before it exists means a guaranteed failed auth on every boot.
      after = [ "podman-${name}.service" "podman-${i.portForwarding.syncTo}.service" ];
      requires = [ "podman-${name}.service" ];
      wantedBy = [ "multi-user.target" ];

      path = with pkgs; [ curl jq gawk systemd ];

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = 30;
      };

      script = ''
        set -euo pipefail

        GLUETUN_API="http://127.0.0.1:${toString i.controlPort}"
        CHECK_INTERVAL=${toString i.portForwarding.checkInterval}
        PORT_FILE="${portFile name}"
        LAST_PORT=""

        mkdir -p "$(dirname "$PORT_FILE")"
        echo "Starting ${name} port forwarding sync..."

        while ! curl -sf "$GLUETUN_API/v1/portforward" >/dev/null 2>&1; do
          echo "Waiting for ${name} control API..."
          sleep 10
        done

        while true; do
          FORWARDED_PORT=$(curl -sf "$GLUETUN_API/v1/portforward" | jq -r '.port // empty')

          if [ -z "$FORWARDED_PORT" ] || [ "$FORWARDED_PORT" = "0" ]; then
            echo "No forwarded port available yet, waiting..."
            sleep $CHECK_INTERVAL
            continue
          fi

          if [ "$FORWARDED_PORT" != "$LAST_PORT" ]; then
            echo "Port changed: $LAST_PORT -> $FORWARDED_PORT"
            # Publish first, then act: the follower reads this file, and a crash
            # between the two leaves the file authoritative rather than stale.
            printf '%s' "$FORWARDED_PORT" > "$PORT_FILE"

            ${(syncImpl.${i.portForwarding.syncTo}) name i}

            LAST_PORT="$FORWARDED_PORT"
          fi

          sleep $CHECK_INTERVAL
        done
      '';
    };
  };
  tunnels = mkInfraContainers (lib.mapAttrs tunnelSpec instances);

  portSyncServices = lib.concatMapAttrs
    (name: i: lib.optionalAttrs
      (i.portForwarding.enable && i.portForwarding.syncTo != null)
      (mkPortSync name i))
    instances;
in
{
  # NOTE ON SHAPE: `config` here is a PLAIN attrset, and it has to stay one.
  # A top-level lib.mkIf/lib.mkMerge whose contents are derived from `config`
  # (here: the instance set) is forced by the module system's pushDownProperties
  # before config is fixed — infinite recursion, which is exactly what the first
  # multi-instance attempt hit. Keep the top-level names literal and let the
  # VALUES depend on config; mkIf belongs inside a value, never around this set.
  config = {
    virtualisation = tunnels.virtualisation;

    systemd.services = lib.mkMerge [ tunnels.systemd.services portSyncServices ];

    systemd.tmpfiles.rules =
      lib.optionals (instances != {}) (
        [ "d ${cfg.stateRoot} 0755 root root -" ]
        ++ lib.mapAttrsToList (name: _: "d ${stateDir name} 0755 root root -") instances
      );
  };
}
