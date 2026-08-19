# gluetun container configuration
{ lib, config, pkgs, ... }:
let
  # Import infrastructure container helper
  infraHelpers = import ../../../lib/mkInfraContainer.nix { inherit lib pkgs; };
  inherit (infraHelpers) mkInfraContainer;

  cfg = config.hwc.networking.gluetun;
  appsRoot = config.hwc.paths.apps.root;
  cfgRoot = "${appsRoot}/gluetun";
  mediaNetworkName = "media-network";
in
{
  config = lib.mkIf cfg.enable (lib.mkMerge [
    # Container definition using mkInfraContainer
    (mkInfraContainer {
      name = "gluetun";
      image = cfg.image;

      # Network configuration
      networkMode = "media-network";
      networkAliases = [ "gluetun" ];

      # Infrastructure capabilities
      capabilities = [ "NET_ADMIN" "SYS_MODULE" ];
      devices = [ "/dev/net/tun:/dev/net/tun" ];
      privileged = true;

      # Ports exposed through gluetun for VPN-dependent containers
      ports = [
        "127.0.0.1:8080:8080"  # qBittorrent UI (Caddy proxies to localhost)
        "127.0.0.1:8081:8085"  # SABnzbd (container uses 8085 internally)
        "127.0.0.1:5010:5010"  # Mousehole (MAM IP updater)
        "127.0.0.1:8000:8000"  # Gluetun control server (port forwarding status)
      ];

      # Volume mounts
      volumes = [ "${cfgRoot}:/gluetun" ];

      # Environment from agenix-generated file
      environmentFiles = [ "${cfgRoot}/.env" ];

      # Static environment
      environment = {
        TZ = config.time.timeZone or "America/Denver";
        DOT = "off";  # Disable DNS over TLS - was causing timeouts
        DNS_ADDRESS = "1.1.1.1";  # Use Cloudflare DNS
        # Disable control server auth so port-sync service can query forwarded port
        HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE = ''{"auth":"none"}'';
      };

      # Pre-start script to generate env file from agenix secrets
      preStartScript = ''
        mkdir -p ${cfgRoot}
        WG_PRIVATE_KEY=$(cat ${config.age.secrets.vpn-wireguard-private-key.path})
        cat > ${cfgRoot}/.env <<EOF
# ProtonVPN WireGuard + NAT-PMP port forwarding.
#
# Server pin, and why it is a known weakness: VPN_SERVICE_PROVIDER=custom means
# gluetun talks to exactly ONE server and can never fail over. On 2026-08-18
# 19:20 the previous pin (US-CO#243 / 95.173.221.158, mislabelled "US-UT#52" in
# this comment for months) stopped answering handshakes. gluetun then restarted
# the tunnel 4,219 times in 24h against the same dead peer, and the stack was
# down ~33h. Verified during that outage: the private key, the account and
# egress were all fine — three other Proton servers handshook instantly with
# this same key while this one refused.
#
# If this pin dies again the symptom is identical: `wg show` inside the netns
# reads "0 B received", and journalctl shows the healthcheck restart loop.
# Re-point below to any port-forward-capable Proton WireGuard server; the
# current list is in the container at /gluetun/servers.json:
#   podman exec gluetun cat /gluetun/servers.json \
#     | jq -r '.protonvpn.servers[] | select(.vpn=="wireguard" and .port_forward
#              and .country=="United States") | "\(.server_name) \(.ips[0]) \(.wgpubkey)"'
# Proper failover (VPN_SERVICE_PROVIDER=protonvpn, which rotates servers on
# failure) is the real fix and is tracked separately — it rotates correctly but
# needs healthcheck tuning that was not verified during this incident.
VPN_SERVICE_PROVIDER=custom
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=$WG_PRIVATE_KEY
WIREGUARD_ADDRESSES=10.2.0.2/32
# US-VA#1 (Ashburn), port-forward capable. Handshake verified 2026-08-19.
WIREGUARD_PUBLIC_KEY="zAIZj//t14xuriUMSlWk4/J2jox6I/JMzHL1Y3D/WUE="
WIREGUARD_ENDPOINT_IP=185.156.46.33
WIREGUARD_ENDPOINT_PORT=51820
WIREGUARD_PERSISTENT_KEEPALIVE_INTERVAL=25s
VPN_PORT_FORWARDING=on
VPN_PORT_FORWARDING_PROVIDER=protonvpn
HEALTH_VPN_DURATION_INITIAL=30s
HEALTH_TARGET_ADDRESS=1.1.1.1:443
EOF
        chmod 600 ${cfgRoot}/.env
        chown root:root ${cfgRoot}/.env
      '';
      preStartDeps = [ "agenix.service" ];

      # Systemd dependencies
      systemdAfter = [ "network-online.target" "init-media-network.service" ];
      systemdWants = [ "network-online.target" ];
    })

    # Port forwarding sync service - keeps qBittorrent in sync with Gluetun's forwarded port
    # This is separate because it's a long-running service, not a oneshot
    (lib.mkIf (cfg.portForwarding.enable && cfg.portForwarding.syncToQbittorrent) {
      systemd.services.gluetun-port-sync = {
        description = "Sync Gluetun forwarded port to qBittorrent";
        after = [ "podman-gluetun.service" "podman-qbittorrent.service" ];
        requires = [ "podman-gluetun.service" ];
        wantedBy = [ "multi-user.target" ];

        path = with pkgs; [ curl jq gawk ];

        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = 30;
        };

        script = ''
          set -euo pipefail

          GLUETUN_API="http://127.0.0.1:8000"
          QBT_API="http://127.0.0.1:8080"
          CHECK_INTERVAL=${toString cfg.portForwarding.checkInterval}
          LAST_PORT=""

          echo "Starting Gluetun port forwarding sync service..."

          # Wait for Gluetun to be ready
          while ! curl -sf "$GLUETUN_API/v1/portforward" >/dev/null 2>&1; do
            echo "Waiting for Gluetun API..."
            sleep 10
          done

          while true; do
            # Get current forwarded port from Gluetun
            FORWARDED_PORT=$(curl -sf "$GLUETUN_API/v1/portforward" | jq -r '.port // empty')

            if [ -z "$FORWARDED_PORT" ] || [ "$FORWARDED_PORT" = "0" ]; then
              echo "No forwarded port available yet, waiting..."
              sleep $CHECK_INTERVAL
              continue
            fi

            # Only update if port changed
            if [ "$FORWARDED_PORT" != "$LAST_PORT" ]; then
              echo "Port changed: $LAST_PORT -> $FORWARDED_PORT"

              # Get qBittorrent SID (login)
              SID=$(curl -sf -c - "$QBT_API/api/v2/auth/login" \
                --data "username=admin&password=il0wwlm?" 2>/dev/null | awk '/SID/ {print $NF}' || true)

              if [ -n "$SID" ]; then
                # Update qBittorrent listening port
                curl -sf -b "SID=$SID" "$QBT_API/api/v2/app/setPreferences" \
                  --data "json={\"listen_port\":$FORWARDED_PORT}" && \
                  echo "Updated qBittorrent listening port to $FORWARDED_PORT" || \
                  echo "Failed to update qBittorrent port"
              else
                echo "Could not authenticate with qBittorrent"
              fi

              LAST_PORT="$FORWARDED_PORT"
            fi

            sleep $CHECK_INTERVAL
          done
        '';
      };
    })
  ]);
}
