# secrets.nix - Agenix secrets configuration
# This file defines all secrets used by the system and their access permissions

let
  # Age public keys for each machine
  laptop = "age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne";
  server = "age14rghg6wtzujzmhd0hxhf8rp3vkj8d7uu6f3ppm2grcj5c0gfn4wqz3l0zh";
  
  # User keys (if you have personal age keys)
  eric = "age1dyegtj68gpyhwvus4wlt8azyas2sslwwt8fwyqwz3vu2jffl8chsk2afne";  # Use laptop key for now

  # Define machine sets
  all_machines = [ laptop server ];
  server_only = [ server ];
  laptop_only = [ laptop ];
in
{
  # VPN Configuration (both machines need this)
  "secrets/vpn-username.age".publicKeys = all_machines;
  "secrets/vpn-password.age".publicKeys = all_machines;

  # Database secrets (server only)
  "secrets/database-password.age".publicKeys = server_only;
  "secrets/database-user.age".publicKeys = server_only;
  "secrets/database-name.age".publicKeys = server_only;

  # CouchDB secrets (server only)
  "secrets/couchdb-admin-username.age".publicKeys = server_only;
  "secrets/couchdb-admin-password.age".publicKeys = server_only;

  # User configuration (both machines)
  "secrets/user-initial-password.age".publicKeys = all_machines;
  "secrets/user-ssh-public-key.age".publicKeys = all_machines;

  # Service API keys (server only)
  "secrets/jellyfin-admin.age".publicKeys = server_only;
  "secrets/homeassistant-admin.age".publicKeys = server_only;
  "secrets/caddy-admin.age".publicKeys = server_only;

  # ARR stack API keys (will be migrated from arr_api_keys.env)
  "secrets/sonarr-api-key.age".publicKeys = server_only;
  "secrets/radarr-api-key.age".publicKeys = server_only;
  "secrets/lidarr-api-key.age".publicKeys = server_only;
  "secrets/prowlarr-api-key.age".publicKeys = server_only;

  # NTFY tokens (server only) 
  "secrets/ntfy-token.age".publicKeys = server_only;

  # Surveillance secrets (server only)
  "secrets/surveillance-admin.age".publicKeys = server_only;
}