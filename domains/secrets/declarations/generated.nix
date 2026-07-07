# domains/secrets/declarations/generated.nix
#
# Generated age.secrets mounts. Replaces the hand-maintained
# services.nix / home.nix / infrastructure.nix / system.nix declaration files.
#
# The directory of *.age files under domains/secrets/parts/ is the single
# source of truth: every secret (excluding the runtime-selected caddy/ certs,
# which domains/secrets/parts/caddy.nix still mounts by hand) is mounted with
# the default permission set, overridden per-name only where it historically
# differed. See domains/secrets/parts/lib.nix for the walk + name derivation.
#
# Adding a secret = drop a .age into parts/<category>/ and add a recipient via
# the agenix workflow; no edits to this file are required unless the new secret
# needs non-default ownership/mode.
{ config, lib, ... }:
let
  gen      = import ../parts/lib.nix { };
  partsDir = ../parts;

  defaultMount = { mode = "0440"; owner = "root"; group = "secrets"; };

  # Per-name deviations from the default. Carried verbatim from the previous
  # explicit declarations (proven by the parity harness).
  mountOverrides = {
    # User-owned (read by services running as eric) — mode/group unchanged.
    discord-webhook-url        = { owner = "eric"; };
    discord-webhook-hwc-alerts = { owner = "eric"; };
    discord-webhook-hwc-leads  = { owner = "eric"; };
    discord-webhook-nightly-builds = { owner = "eric"; };
    hwc-leads-hmac-secret      = { owner = "eric"; };
    slack-signing-secret       = { owner = "eric"; };
    grafana-admin-password     = { owner = "eric"; };
    jellyfin-api-key           = { owner = "eric"; };
    jellyfin-admin-password    = { owner = "eric"; };
    jellyfin-eric-password     = { owner = "eric"; };
    n8n-owner-password-hash    = { owner = "eric"; };
    n8n-api-key                = { owner = "eric"; };

    # Restrictive root-only secrets (camera/backup config).
    frigate-rtsp-username = { mode = "0400"; group = "root"; };
    frigate-camera-ips    = { mode = "0400"; group = "root"; };
    borg-passphrase       = { mode = "0400"; group = "root"; };
    rclone-proton-config  = { mode = "0600"; group = "root"; };
  };

  # Nix resolves path literals relative to THIS file, so the file path is
  # constructed here (lib.nix cannot emit a path rooted at ../parts).
  fileFor = rel: partsDir + ("/" + rel);

  entries = gen.walkParts partsDir;
in
{
  config = lib.mkIf config.hwc.secrets.declarations.enable {
    age.secrets = gen.mkMounts {
      inherit partsDir fileFor defaultMount mountOverrides;
    };

    # No two .age paths may derive the same age.secrets name (would silently
    # clobber a mount). Fails the build loudly if a future file collides.
    assertions = [{
      assertion =
        let names = map (e: e.name) entries;
        in builtins.length names == builtins.length (lib.unique names);
      message = "secrets generator: two .age files derive the same secret name "
              + "(see domains/secrets/parts/lib.nix deriveName)";
    }];
  };
}
