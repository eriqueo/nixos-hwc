# secrets.nix — agenix recipient rules for nixos-hwc
#
# Defines which public keys can decrypt each secret.
# After editing, run: sudo agenix -r -i /etc/age/keys.txt
# from this directory to re-encrypt all affected secrets.
#
# Key type note: host keys are age X25519 keys (matching /etc/age/keys.txt identity).
# Eric's user key is SSH ed25519 (for agenix -e from any workstation with his privkey).

let
  # ── helpers ──
  readKey = f: builtins.replaceStrings [ "\n" "\r" ] [ "" "" ] (builtins.readFile f);

  # ── machine host keys (age public keys matching /etc/age/keys.txt on each host) ──
  # laptop = readKey ./machines/hwc-laptop/AGE_PUBLIC_KEY.txt;  # TODO: retrieve from laptop, add here, rekey
  server = readKey ./machines/hwc-server/AGE_PUBLIC_KEY.txt;
  xps    = readKey ./machines/hwc-xps/AGE_PUBLIC_KEY.txt;

  # ── user keys ──
  eric = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPpGuiR4JKb0EyK8z+QmWo7qayRC01IHqUYspUbxgVgB eriqueo@homeserver";

  # ── recipient groups ──
  allHosts = [ server xps ];       # laptop added after key retrieval
  allUsers = [ eric ];
  everyone = allHosts ++ allUsers;

in
{
  # ═══════════════════════════════════════════════════════════════════════════
  # Caddy TLS certificates
  # ═══════════════════════════════════════════════════════════════════════════

  # Server-scoped Caddy certs — all hosts
  "domains/secrets/parts/caddy/hwc.ocelot-wahoo.ts.net.crt.age".publicKeys       = everyone;
  "domains/secrets/parts/caddy/hwc.ocelot-wahoo.ts.net.key.age".publicKeys       = everyone;

  # XPS-scoped Caddy certs — xps + eric only (machine-specific TLS)
  "domains/secrets/parts/caddy/hwc-xps.ocelot-wahoo.ts.net.crt.age".publicKeys   = [ xps eric ];
  "domains/secrets/parts/caddy/hwc-xps.ocelot-wahoo.ts.net.key.age".publicKeys   = [ xps eric ];

  # ═══════════════════════════════════════════════════════════════════════════
  # Home — email, API keys, personal credentials
  # ═══════════════════════════════════════════════════════════════════════════

  "domains/secrets/parts/home/apple-app-pw.age".publicKeys                       = everyone;
  "domains/secrets/parts/home/gmail-business-password.age".publicKeys             = everyone;
  "domains/secrets/parts/home/gmail-oauth-client.json.age".publicKeys             = everyone;
  "domains/secrets/parts/home/gmail-personal-password.age".publicKeys             = everyone;
  "domains/secrets/parts/home/google-oauth-client-id.age".publicKeys              = everyone;
  "domains/secrets/parts/home/google-oauth-client-secret.age".publicKeys          = everyone;
  "domains/secrets/parts/home/openai-api-key.age".publicKeys                      = everyone;
  "domains/secrets/parts/home/proton-bridge-password.age".publicKeys              = everyone;
  "domains/secrets/parts/home/scraper/facebook-email.age".publicKeys              = everyone;
  "domains/secrets/parts/home/scraper/facebook-password.age".publicKeys           = everyone;
  "domains/secrets/parts/home/scraper/nextdoor-email.age".publicKeys              = everyone;
  "domains/secrets/parts/home/scraper/nextdoor-password.age".publicKeys           = everyone;

  # ═══════════════════════════════════════════════════════════════════════════
  # Infrastructure — databases, cameras, VPN
  # ═══════════════════════════════════════════════════════════════════════════

  "domains/secrets/parts/infrastructure/database-name.age".publicKeys             = everyone;
  "domains/secrets/parts/infrastructure/database-password.age".publicKeys         = everyone;
  "domains/secrets/parts/infrastructure/database-user.age".publicKeys             = everyone;
  "domains/secrets/parts/infrastructure/frigate-camera-ips.age".publicKeys        = everyone;
  "domains/secrets/parts/infrastructure/frigate-reolink-password.age".publicKeys  = everyone;
  "domains/secrets/parts/infrastructure/frigate-reolink-username.age".publicKeys  = everyone;
  "domains/secrets/parts/infrastructure/frigate-rtsp-password.age".publicKeys     = everyone;
  "domains/secrets/parts/infrastructure/frigate-rtsp-username.age".publicKeys     = everyone;
  "domains/secrets/parts/infrastructure/surveillance-rtsp-password.age".publicKeys = everyone;
  "domains/secrets/parts/infrastructure/surveillance-rtsp-username.age".publicKeys = everyone;
  "domains/secrets/parts/infrastructure/vpn-password.age".publicKeys              = everyone;
  "domains/secrets/parts/infrastructure/vpn-username.age".publicKeys              = everyone;
  "domains/secrets/parts/infrastructure/vpn-wireguard-private-key.age".publicKeys = everyone;

  # ═══════════════════════════════════════════════════════════════════════════
  # Services — application API keys, passwords, tokens
  # ═══════════════════════════════════════════════════════════════════════════

  "domains/secrets/parts/services/audiobookshelf-api-key.age".publicKeys         = everyone;
  "domains/secrets/parts/services/authentik-db-password.age".publicKeys           = everyone;
  "domains/secrets/parts/services/authentik-secret-key.age".publicKeys            = everyone;
  "domains/secrets/parts/services/cms-api-key.age".publicKeys                    = everyone;
  "domains/secrets/parts/services/couchdb-admin-password.age".publicKeys         = everyone;
  "domains/secrets/parts/services/couchdb-admin-username.age".publicKeys         = everyone;
  "domains/secrets/parts/services/estimator-api-key.age".publicKeys              = everyone;
  "domains/secrets/parts/services/firefly-app-key.age".publicKeys                = everyone;
  "domains/secrets/parts/services/gemini_api_key.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/gotify-admin-password.age".publicKeys          = everyone;
  "domains/secrets/parts/services/gotify-home-admin.age".publicKeys              = everyone;
  "domains/secrets/parts/services/gotify-home-media.age".publicKeys              = everyone;
  "domains/secrets/parts/services/gotify-home-security.age".publicKeys           = everyone;
  "domains/secrets/parts/services/gotify-home-social.age".publicKeys             = everyone;
  "domains/secrets/parts/services/gotify-hwc-admin.age".publicKeys               = everyone;
  "domains/secrets/parts/services/gotify-hwc-dev.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/gotify-hwc-financial.age".publicKeys           = everyone;
  "domains/secrets/parts/services/gotify-hwc-ops.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/gotify-token-alerts.age".publicKeys            = everyone;
  "domains/secrets/parts/services/gotify-token-backup.age".publicKeys            = everyone;
  "domains/secrets/parts/services/gotify-token-laptop.age".publicKeys            = everyone;
  "domains/secrets/parts/services/gotify-token-leads.age".publicKeys             = everyone;
  "domains/secrets/parts/services/gotify-token-mail.age".publicKeys              = everyone;
  "domains/secrets/parts/services/gotify-token-monitoring.age".publicKeys        = everyone;
  "domains/secrets/parts/services/grafana-admin-password.age".publicKeys         = everyone;
  "domains/secrets/parts/services/hostinger-sftp.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/immich-api-key.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/jellyfin-api-key.age".publicKeys               = everyone;
  "domains/secrets/parts/services/jellyfin/admin-password.age".publicKeys        = everyone;
  "domains/secrets/parts/services/jellyfin/eric-password.age".publicKeys         = everyone;
  "domains/secrets/parts/services/jobtread-grant-key.age".publicKeys             = everyone;
  "domains/secrets/parts/services/lidarr-api-key.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/n8n-api-key.age".publicKeys                    = everyone;
  "domains/secrets/parts/services/n8n-owner-password-hash.age".publicKeys        = everyone;
  "domains/secrets/parts/services/nanoclaw-anthropic-key.age".publicKeys         = everyone;
  "domains/secrets/parts/services/nanoclaw-slack-app-token.age".publicKeys       = everyone;
  "domains/secrets/parts/services/nanoclaw-slack-bot-token.age".publicKeys       = everyone;
  "domains/secrets/parts/services/navidrome-admin-password.age".publicKeys       = everyone;
  "domains/secrets/parts/services/ninjacentral-api-key.age".publicKeys           = everyone;
  "domains/secrets/parts/services/ntfy-user.age".publicKeys                      = everyone;
  "domains/secrets/parts/services/paperless-admin-password.age".publicKeys       = everyone;
  "domains/secrets/parts/services/paperless-secret-key.age".publicKeys           = everyone;
  "domains/secrets/parts/services/prowlarr-api-key.age".publicKeys               = everyone;
  "domains/secrets/parts/services/radarr-api-key.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/slack-signing-secret.age".publicKeys           = everyone;
  "domains/secrets/parts/services/slack-webhook-url.age".publicKeys              = everyone;
  "domains/secrets/parts/services/slskd-api-key.age".publicKeys                  = everyone;
  "domains/secrets/parts/services/slskd-soulseek-password.age".publicKeys        = everyone;
  "domains/secrets/parts/services/slskd-soulseek-username.age".publicKeys        = everyone;
  "domains/secrets/parts/services/slskd-web-password.age".publicKeys             = everyone;
  "domains/secrets/parts/services/slskd-web-username.age".publicKeys             = everyone;
  "domains/secrets/parts/services/sonarr-api-key.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/vaultwarden-admin-token.age".publicKeys        = everyone;
  "domains/secrets/parts/services/webdav-password.age".publicKeys                = everyone;
  "domains/secrets/parts/services/webdav-username.age".publicKeys                = everyone;
  "domains/secrets/parts/services/youtube-api-key.age".publicKeys                = everyone;
  "domains/secrets/parts/services/youtube-db-url.age".publicKeys                 = everyone;
  "domains/secrets/parts/services/youtube-videos-db-url.age".publicKeys          = everyone;

  # ═══════════════════════════════════════════════════════════════════════════
  # System — authentication, backups, SSH
  # ═══════════════════════════════════════════════════════════════════════════

  "domains/secrets/parts/system/borg-passphrase.age".publicKeys                  = everyone;
  "domains/secrets/parts/system/emergency-password.age".publicKeys               = everyone;
  "domains/secrets/parts/system/rclone-proton-config.age".publicKeys             = everyone;
  "domains/secrets/parts/system/user-initial-password.age".publicKeys            = everyone;
  "domains/secrets/parts/system/user-ssh-public-key.age".publicKeys              = everyone;
}
