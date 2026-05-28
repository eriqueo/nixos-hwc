# domains/home/apps/dxlog/index.nix
{ config, lib, pkgs, osConfig ? {}, ... }:
let
  cfg = config.hwc.home.apps.dxlog;

  # Secrets come in via agenix at /run/agenix/<name>. eric is in the `secrets`
  # group (gid 975), so 0440 root:secrets files are readable.
  # PORT is not a secret; pinned to the DO managed-OpenSearch default.
  dxlogSh = ./parts/dxlog.sh;

  dxlogScript = pkgs.writeShellScriptBin "dxlog" ''
    set -u

    secret_dir=/run/agenix

    read_secret() {
      local f="$secret_dir/$1"
      if [[ -r "$f" ]]; then
        cat "$f"
      else
        echo "dxlog: missing or unreadable secret: $f" >&2
        echo "       (is eric in the 'secrets' group? has nixos-rebuild run since the secret was added?)" >&2
        exit 1
      fi
    }

    export DXLOG_OPENSEARCH_HOST="$(read_secret opensearch-host)"
    export DXLOG_OPENSEARCH_USER="$(read_secret opensearch-user)"
    export DXLOG_OPENSEARCH_PASS="$(read_secret opensearch-pw)"
    export DXLOG_DO_APP_ID="$(read_secret opensearch-app-id)"
    export DXLOG_OPENSEARCH_PORT=25060

    exec ${pkgs.bash}/bin/bash ${dxlogSh} "$@"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.dxlog = {
    enable = lib.mkEnableOption "dxlog — DataX OpenSearch log diagnostic CLI";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    home.packages = [
      dxlogScript
      pkgs.curl
      pkgs.jq
      pkgs.doctl
    ];
  };
}
