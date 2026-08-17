# domains/automation/dx1-gauntlet/index.nix
#
# DX1 Gauntlet — unattended investigation of open DX1 health-ledger cases.
#
# Fetches open `dx1Cases` (triage platform/prompt, above the failure
# threshold) from the DataX Firestore, runs one headless read-only Claude Code
# investigation per case against pinned worktrees of the datax + jt-mcp repos
# (with the case's transcript/OpenSearch context pack), writes a reviewable
# REPORT.md per case, and posts each report to Eric's Discord webhook.
# Sibling of sr-gauntlet (same containment model: reports + a state-hash
# ledger are the only outputs; the human applies fixes).
#
# The pipeline itself (run.sh, fetch-cases.mjs, aggregate-case-context.mjs,
# write-results.mjs) lives in its own repo at ~/700_datax/dx1_gauntlet — this
# module only provides the schedule + the board's run-now drain. Credentials
# are late-bound at runtime from the same files sr-gauntlet uses; nothing
# secret passes through the Nix store.
#
# NAMESPACE: hwc.automation.dx1Gauntlet.*
#
# DEPENDENCIES (why machines/server sets enable = false until provisioned):
#   - ~/700_datax/dx1_gauntlet checkout (the pipeline; laptop-authored repo,
#     no remote yet — clone/rsync to the server before enabling)
#   - /var/lib/sr-gauntlet/{datax,jt-mcp} — the SAME service-owned clones
#     sr-gauntlet uses (read-only worktree sources; DXG_PIN_REMOTE prefers
#     the upstream remote)
#   - ~/600_apps/sr_analyzer/.env (Firestore fetch) + /var/lib/sr-gauntlet/
#     datax.env (Firestore admin + OpenSearch) — same cred files as sr-gauntlet
#   - sr-gauntlet-claude-oauth agenix secret — the SAME long-lived Claude
#     subscription token (one credential, two consumers; see sr-gauntlet's
#     rationale for the isolated CLAUDE_CONFIG_DIR pairing)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.dx1Gauntlet;
  paths = config.hwc.paths;

  # Shared spool dir for the refinery board's "▶ re-investigate now" button on
  # /dx1: the (sandboxed) board drops a request file here; the path-triggered
  # drain below runs `run.sh --id <fingerprint>`. MUST match the board's
  # REFINERY_DX1_RUNNOW_SPOOL (domains/automation/refinery/index.nix).
  # Spool filenames carry the case fingerprint with ":" encoded as "+"
  # (fingerprints are `agent:<org>:<agent>:<family>`); the drain decodes.
  spoolDir = "/var/lib/refinery/dx1-run-now";

  # Same isolated Claude config dir as sr-gauntlet (no credentials.json, so
  # CLAUDE_CODE_OAUTH_TOKEN is the sole credential) — the two gauntlets share
  # one headless identity, so they share the dir + token.
  claudeConfigDir = "/var/lib/sr-gauntlet/claude-config";

  dxgEnv = {
    HOME = paths.user.home;
    DXG_MAX_CASES = toString cfg.maxCases;
    # Firestore fetch creds (same file sr_gauntlet's fetch uses).
    DXG_ENV_FILE = "${paths.user.home}/600_apps/sr_analyzer/.env";
    # Firestore-admin + OpenSearch creds for the context aggregator — the
    # trimmed service copy, not a dev tree .env.local.
    DXG_DATAX_ENV = "/var/lib/sr-gauntlet/datax.env";
    # Service-owned source clones shared with sr-gauntlet (read-only worktree
    # sources). run.sh pins to the upstream remote when present.
    DXG_DATAX_REPO = "/var/lib/sr-gauntlet/datax";
    DXG_JTMCP_REPO = "/var/lib/sr-gauntlet/jt-mcp";
    # Board-written per-gauntlet cap (key "dx1"); run.sh reads it with
    # DXG_MAX_CASES as fallback.
    DXG_CAPS_FILE = "/var/lib/refinery/caps.json";
    CLAUDE_CONFIG_DIR = claudeConfigDir;
  };

  # Same dedicated long-lived Claude subscription token as sr-gauntlet
  # (agenix; a single env line, sourced as EnvironmentFile so it never enters
  # the Nix store). One credential, two consumers — declared once in
  # domains/secrets, referenced here.
  claudeOauthEnvFile = config.age.secrets.sr-gauntlet-claude-oauth.path;

  dxgPath = [
    pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
    pkgs.nodejs_22 pkgs.jq pkgs.ripgrep
    pkgs.curl # Discord webhook delivery + hwc-notify
  ];

  # Drains the run-now spool: consume the request file first (a re-click
  # mid-run re-queues cleanly), decode the "+"-encoded fingerprint, then run
  # run.sh forced on that one case. run.sh's own lock serializes this against
  # the poll timer.
  runnowDrain = pkgs.writeShellScript "dx1-gauntlet-runnow-drain" ''
    set -uo pipefail
    SPOOL="${spoolDir}"
    [ -d "$SPOOL" ] || exit 0
    shopt -s nullglob
    for f in "$SPOOL"/*; do
      [ -e "$f" ] || continue
      fp="$(basename "$f" | tr '+' ':')"
      rm -f "$f"
      echo "dx1-run-now: investigating case '$fp'"
      ${cfg.gauntletDir}/run.sh --id "$fp" || echo "dx1-run-now: run.sh exited $? for '$fp'"
    done
  '';
in
{
  # OPTIONS
  options.hwc.automation.dx1Gauntlet = {
    enable = lib.mkEnableOption "DX1 case investigation pipeline (headless Claude Code)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 07:30:00";
      description = ''
        systemd calendar expression for the investigation poll. Default: once
        daily (07:30) — deliberately low-cadence while the gauntlet earns
        trust (strangler-fig; sr-gauntlet's 15-min cadence is the eventual
        shape). run.sh's fetch + state-hash ledger dedup make a tick with no
        new/worsened case exit fast.
      '';
    };

    maxCases = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Maximum cases investigated per run (board cap file overrides)";
    };

    gauntletDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.user.home}/700_datax/dx1_gauntlet";
      description = "dx1_gauntlet pipeline checkout (run.sh lives here)";
    };
  };

  config = lib.mkIf cfg.enable {
    # The run-now spool dir must exist (owned by eric, group-writable so the
    # refinery board — also eric — can drop request files there). The shared
    # claude-config dir is owned by sr-gauntlet's tmpfiles rule.
    systemd.tmpfiles.rules = [
      "d ${spoolDir} 0775 eric users - -"
    ];

    systemd.services.dx1-gauntlet = {
      description = "DX1 Gauntlet — case-ledger investigations (headless Claude Code)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = dxgEnv;
      path = dxgPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = cfg.gauntletDir;
        ExecStart = "${cfg.gauntletDir}/run.sh";
        EnvironmentFile = claudeOauthEnvFile;
        # maxCases * 30 min agent budget + fetch/context overhead
        TimeoutSec = 3 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.dx1-gauntlet = {
      description = "DX1 Gauntlet investigation poll timer (daily while earning trust)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Persistent: at a daily cadence a missed tick IS worth catching up
        # (unlike sr-gauntlet's 15-min poll).
        Persistent = true;
        RandomizedDelaySec = "300s";
      };
    };

    # ── Run-now: targeted, on-demand re-investigation from the refinery board ──
    # The board can't run run.sh itself (hardened/sandboxed). It drops a
    # "+"-encoded <fingerprint> file in spoolDir; this path unit fires the
    # drain, which runs `run.sh --id <fingerprint>`. Executor behind the /dx1
    # page's "▶ re-investigate now" button.
    systemd.services.dx1-gauntlet-runnow = {
      description = "DX1 Gauntlet — targeted run-now drain (refinery board trigger)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = dxgEnv;
      path = dxgPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = cfg.gauntletDir;
        ExecStart = "${runnowDrain}";
        EnvironmentFile = claudeOauthEnvFile;
        TimeoutSec = 3 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.paths.dx1-gauntlet-runnow = {
      description = "Watch the refinery DX1 run-now spool for targeted investigations";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        DirectoryNotEmpty = spoolDir;
        Unit = "dx1-gauntlet-runnow.service";
      };
    };
  };
}
