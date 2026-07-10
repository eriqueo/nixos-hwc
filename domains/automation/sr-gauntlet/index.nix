# domains/automation/sr-gauntlet/index.nix
#
# SR Gauntlet — daily unattended investigation of DataX support requests.
#
# Fetches open SRs (SR2 board phases new+engaged) from the DataX Firestore,
# runs one headless read-only Claude Code investigation per SR against
# origin/main worktrees of the datax + jt-mcp repos (with the customer's
# Firestore context pack and OpenSearch log access), writes a reviewable
# REPORT.md per SR, and posts each report to Eric's Discord webhook.
#
# Containment model (mirrors nightly-builds gate 7): the pipeline never
# changes code and never replies to customers — reports + a thread-hash
# ledger are its only outputs. The human applies fixes / sends replies.
#
# The pipeline itself (run.sh, fetch-srs.mjs, aggregate-context.mjs,
# opensearch-query.mjs, send-report.sh) lives in its own repo at
# ~/700_datax/sr_gauntlet — this module only provides the schedule.
# Credentials are late-bound at runtime from ~/600_apps/sr_analyzer/.env
# (Firestore fetch) and /var/lib/sr-gauntlet/datax.env (Firestore admin +
# OpenSearch — a trimmed copy, not the dev tree); nothing secret passes
# through the Nix store.
#
# NAMESPACE: hwc.automation.srGauntlet.*
#
# DEPENDENCIES:
#   - ~/700_datax/sr_gauntlet checkout (the pipeline)
#   - /var/lib/sr-gauntlet/{datax,jt-mcp} — service-owned clones of the official
#     elstruck repos (worktree sources, origin/main). Set up once, fetch-only;
#     decoupled from Eric's ~/700_datax dev worktrees.
#   - /var/lib/sr-gauntlet/datax.env — trimmed 0600 cred file (9 keys: 7
#     required NEXT_PUBLIC_FIREBASE_* + OPENSEARCH_*, plus optional
#     SRG_PUSH_URL/SRG_PUSH_SECRET for report push into the datax admin UI —
#     push is skipped gracefully while those two are absent)
#   - Claude Code CLI authenticated for the eric user
#   - hwc-notify on 127.0.0.1:11600 (run summaries; best-effort)

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.srGauntlet;
  paths = config.hwc.paths;

  # Shared spool dir for the refinery board's "▶ re-investigate now" button: the
  # (sandboxed) board drops an <srId> request file here; the path-triggered drain
  # below runs `run.sh --id <srId>` for that one SR. Mirrors the nightly-builds
  # run-now pattern. MUST match the board's REFINERY_SR_RUNNOW_SPOOL
  # (domains/automation/refinery/index.nix).
  spoolDir = "/var/lib/refinery/sr-run-now";

  # Env + tool path shared by the daily run and the run-now drain (same needs).
  srgEnv = {
    HOME = paths.user.home;
    SRG_MAX_SRS = toString cfg.maxSrs;
    # Late-bind Firestore creds from sr_analyzer's single .env (declare once,
    # derive everywhere). Without this the script falls back to a stale default
    # path and fetch FATALs with ENOENT.
    SRG_ENV_FILE = "${paths.user.home}/600_apps/sr_analyzer/.env";
    # Service-owned source clones (origin = official elstruck, pinned to main),
    # NOT Eric's ~/700_datax dev worktrees. run.sh fetches origin/main from these
    # and builds throwaway /tmp worktrees — nothing edits them. Decouples the
    # long-running service from the interactive dev tree (laptop-only editing).
    SRG_DATAX_REPO = "/var/lib/sr-gauntlet/datax";
    SRG_JTMCP_REPO = "/var/lib/sr-gauntlet/jt-mcp";
    # aggregate-context.mjs + opensearch-query.mjs + push-report.mjs read
    # Firestore-admin, OpenSearch, and datax-push creds from this file (was
    # ~/700_datax/datax/.env.local — gone with the dev tree). Plain 0600 file,
    # eric-owned; refresh by hand on rotation — run.sh's check-creds.mjs
    # preflight now alerts Discord with the NAME of any missing key.
    SRG_DATAX_ENV = "/var/lib/sr-gauntlet/datax.env";
  };
  srgPath = [
    pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
    # python3 retired 2026-07: the ledger/prompt/verdict heredocs it served are
    # now node subcommands in the pipeline's lib.mjs (single implementation).
    pkgs.nodejs_22 pkgs.jq pkgs.ripgrep
    pkgs.curl  # Discord webhook delivery + hwc-notify
  ];

  # Drains the run-now spool: for each requested SR, consume the request file
  # first (so a re-click during the run re-queues cleanly and the path unit
  # doesn't re-fire on the same file), then run run.sh forced on that one SR.
  # run.sh's own lock serializes this against the 15-min poll timer — if that's
  # mid-run, the targeted kick logs "already running" and exits 0.
  runnowDrain = pkgs.writeShellScript "sr-gauntlet-runnow-drain" ''
    set -uo pipefail
    SPOOL="${spoolDir}"
    [ -d "$SPOOL" ] || exit 0
    shopt -s nullglob
    for f in "$SPOOL"/*; do
      [ -e "$f" ] || continue
      srId="$(basename "$f")"
      rm -f "$f"
      echo "sr-run-now: investigating SR '$srId'"
      ${cfg.gauntletDir}/run.sh --id "$srId" || echo "sr-run-now: run.sh exited $? for '$srId'"
    done
  '';
in
{
  # OPTIONS
  options.hwc.automation.srGauntlet = {
    enable = lib.mkEnableOption "Daily SR investigation pipeline (headless Claude Code)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*:0/15";
      description = ''
        systemd calendar expression for the investigation poll. Default: every
        15 minutes. run.sh Phase A fetches waiting SRs from Firestore and the
        thread-hash ledger dedups, so most ticks find nothing new and exit fast;
        a genuinely new/changed waiting SR is investigated within ~15 min of
        arrival (the "auto-run on arrival" behaviour). run.sh's lock prevents
        overlap with an in-flight run.
      '';
    };

    maxSrs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5;
      description = "Maximum SRs investigated per run";
    };

    gauntletDir = lib.mkOption {
      type = lib.types.path;
      default = "${paths.user.home}/700_datax/sr_gauntlet";
      description = "sr_gauntlet pipeline checkout (run.sh lives here)";
    };
  };

  config = lib.mkIf cfg.enable {
    # The run-now spool dir must exist (owned by eric, group-writable so the
    # refinery board — also eric — can drop request files there).
    systemd.tmpfiles.rules = [
      "d ${spoolDir} 0775 eric users - -"
    ];

    systemd.services.sr-gauntlet = {
      description = "SR Gauntlet — DataX support-request investigations (headless Claude Code)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = srgEnv;
      path = srgPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = cfg.gauntletDir;
        ExecStart = "${cfg.gauntletDir}/run.sh";
        # maxSrs * 30 min agent budget + fetch/context overhead
        TimeoutSec = 3 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.sr-gauntlet = {
      description = "SR Gauntlet investigation poll timer (every 15 min)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Not Persistent: with a 15-min cadence a missed tick is irrelevant (the
        # next is ≤15 min away), and a boot-time catch-up burst is undesirable.
        Persistent = false;
        RandomizedDelaySec = "60s";
      };
    };

    # ── Run-now: targeted, on-demand re-investigation from the refinery board ──
    # The board can't run run.sh itself (hardened/sandboxed). It drops an <srId>
    # file in spoolDir; this path unit fires the drain, which runs
    # `run.sh --id <srId>`. This is the executor behind the SR page's
    # "▶ re-investigate now" button. (New tickets are picked up automatically by
    # the poll timer above; this is for forcing a specific SR immediately.)
    systemd.services.sr-gauntlet-runnow = {
      description = "SR Gauntlet — targeted run-now drain (refinery board trigger)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = srgEnv;
      path = srgPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = cfg.gauntletDir;
        ExecStart = "${runnowDrain}";
        TimeoutSec = 3 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.paths.sr-gauntlet-runnow = {
      description = "Watch the refinery SR run-now spool for targeted investigations";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        DirectoryNotEmpty = spoolDir;
        Unit = "sr-gauntlet-runnow.service";
      };
    };
  };
}
