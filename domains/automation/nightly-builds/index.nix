# domains/automation/nightly-builds/index.nix
#
# Nightly Builds — unattended overnight execution of gauntlet cards.
#
# Picks up cards marked `status: queued` from the brain vault's
# _inbox/nightly_builds/ goal folders, runs each in a disposable git
# worktree of the nixos repo via headless Claude Code, writes a
# self-verifying REPORT.md into the vault's runs/ tree, pushes the
# result branch to origin, and flips the card status. A card-smith
# pre-pass drafts new cards from _ideas.md (drafts only — a human
# flips draft -> queued; that flip IS the Phase-4 gate).
#
# Containment model (gauntlet gate 7): output goes to branches and the
# vault only. The agent never runs nixos-rebuild and never touches live
# services; morning review is the only thing that promotes anything.
#
# NAMESPACE: hwc.automation.nightlyBuilds.*
#
# DEPENDENCIES:
#   - hwc.paths.nixos (repo working copy)
#   - hwc.paths.brain.server-replica / .vault (Syncthing'd brain vault)
#   - Claude Code CLI authenticated for the eric user

{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.automation.nightlyBuilds;
  paths = config.hwc.paths;
  agentDir = "${paths.nixos}/domains/automation/nightly-builds";

  # Shared spool dir for the refinery board's "▶ Run now" / IMMEDIATE mode: the
  # (sandboxed) board drops a <goal> request file here; the path-triggered
  # drain unit below executes run.sh scoped to that one project. This MUST match
  # the board's REFINERY_RUNNOW_SPOOL (domains/automation/refinery/index.nix).
  spoolDir = "/var/lib/refinery/run-now";

  # Env + tool path shared by the nightly run and the run-now drain (same script,
  # same needs: git push, headless claude, jq/rg/awk/curl).
  nbEnv = {
    HOME = paths.user.home;
    NB_VAULT_DIR = toString cfg.vaultDir;
    NB_REPO_DIR = toString cfg.repoDir;
    NB_MAX_CARDS = toString cfg.maxCards;
    # Discord webhook for rich per-card report delivery (summary + REPORT.md
    # attached). send-report.sh posts directly here; metadata-only fallbacks
    # still go through hwc-notify. Same secret the discord-nightly-builds
    # notify channel uses; readable by the eric-run service (owner).
    NB_DISCORD_WEBHOOK_FILE = config.age.secrets."discord-webhook-nightly-builds".path;
  };
  nbPath = [
    pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
    pkgs.nodejs_22 pkgs.python3 pkgs.jq pkgs.ripgrep
    pkgs.gawk  # send-report.sh parses REPORT.md with awk
    pkgs.curl  # POST run results to hwc-notify + Discord webhook
    # JS toolchain for non-nixos cards (the per-card `repo:` field): kidpix and
    # other web repos run `yarn test`/`yarn build` as their done-condition.
    # Yarn 1.x classic — matches kidpix's pinned `packageManager: yarn@1.22.22`
    # and its v1 yarn.lock. (Playwright e2e additionally needs browser binaries;
    # see the gauntlet-venue note — `yarn test` + `yarn build` work as-is.)
    pkgs.yarn
  ];

  # ── Morning PR-review pass ─────────────────────────────────────────────────
  # The refinery engine's morning-review CLI, exposed as a runnable by the
  # refinery module (one bundle, one npmDepsHash — we don't rebuild it here).
  reviewBin = "${config.hwc.automation.refinery.package}/bin/refinery-morning-review";

  # Where the CLI writes its per-review JSON (and what the board's /morning view
  # reads). Lives under the refinery StateDirectory so the board (also eric) can
  # read it; created group-writable via tmpfiles below.
  reviewsDir = "/var/lib/refinery/reviews";

  # Env for the review pass: late-bound vault + repo + reviews dir + provider.
  # HOME is set so headless `claude` (claude-cli) and `gh` find their creds.
  reviewEnv = {
    HOME = paths.user.home;
    REFINERY_VAULT_DIR = toString cfg.vaultDir;
    REFINERY_DEFAULT_REPO = toString cfg.repoDir;
    REFINERY_REVIEWS_DIR = reviewsDir;
    REFINERY_LLM_PROVIDER = cfg.reviewLlmProvider;
  } // lib.optionalAttrs (config.hwc.automation.refinery.claudeBin != null) {
    # The claude-cli LlmPort shells out to `claude`, which is NOT on the service
    # PATH. Point it at the same headless binary the refinery board uses, else
    # every review fails ENOENT and no verdicts are ever produced.
    REFINERY_CLAUDE_BIN = config.hwc.automation.refinery.claudeBin;
  };
  # PATH for the review pass: git + gh (open PRs), node (the CLI is a node
  # bundle but the wrapper supplies node; gh/git are shelled out to), jq (parse
  # the JSON summary), curl (POST the consolidated notify).
  reviewPath = [
    pkgs.bash pkgs.coreutils pkgs.git pkgs.openssh
    pkgs.gh pkgs.nodejs_22 pkgs.jq pkgs.curl
  ];

  # Runs the review CLI, captures its JSON summary (stdout), then sends ONE
  # consolidated hwc-notify summarizing reviewed/opened/byVerdict. The CLI's
  # per-PR side effects (opening PRs, writing review JSON) are its own; this
  # wrapper only adds the single morning digest — mirrors run.sh's notify().
  reviewRun = pkgs.writeShellScript "nightly-builds-review-run" ''
    set -uo pipefail
    NOTIFY_URL="''${NB_NOTIFY_URL:-http://127.0.0.1:11600/notify}"
    OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
    # No date window needed: the CLI skips any step that already has a review
    # record (idempotent) and complete projects graduate off the gauntlet into
    # _finished/, so the active board never holds stale done work to re-sweep.
    echo "morning-review: starting (reviews -> ${reviewsDir})"
    # stdout is the machine-readable JSON summary (parsed below); stderr is the
    # CLI's human line — let it flow to the journal. Do NOT 2>&1 them together,
    # or the trailing human line corrupts the JSON and jq yields an empty digest.
    ${reviewBin} > "$OUT"
    rc=$?
    # Persist the full CLI JSON (incl .errors[]) BEFORE the trap deletes $OUT.
    # A transient per-record failure otherwise leaves only a count in the journal
    # and the detail is unrecoverable (the CLI is idempotent + graduates done
    # work, so it can't be re-derived). Keep a dated archive under reviews/_runs/.
    ARCHIVE_DIR="${reviewsDir}/_runs"
    mkdir -p "$ARCHIVE_DIR" 2>/dev/null || true
    ARCHIVE="$ARCHIVE_DIR/$(date +%Y-%m-%d-%H%M%S)-morning-review.json"
    cp "$OUT" "$ARCHIVE" 2>/dev/null && echo "morning-review: archived summary -> $ARCHIVE"
    nerr="$(jq -r '(.errors // []) | length' "$OUT" 2>/dev/null || echo 0)"
    # The CLI prints a JSON summary to stdout and a human line to stderr (both
    # captured above). Pull the digest fields with jq; degrade to a raw tail if
    # the output isn't the expected JSON (e.g. an early fatal).
    summary="$(jq -r '
        "reviewed=\(.reviewed) opened=\(.opened) " +
        "merge-ready=\(.byVerdict["merge-ready"] // 0) " +
        "needs-work=\(.byVerdict["needs-work"] // 0) " +
        "reject=\(.byVerdict.reject // 0)" +
        (if (.graduated|length) > 0 then " graduated=\(.graduated|length)" else "" end) +
        (if (.errors|length) > 0 then " errors=\(.errors|length)" else "" end)
      ' "$OUT" 2>/dev/null)" || summary=""
    if [ -z "$summary" ]; then
      summary="morning-review exited $rc; output: $(tail -c 400 "$OUT")"
      prio=2; title="⚠️ Morning review — incomplete"
    elif [ "$rc" -eq 0 ]; then
      prio=4; title="🔎 Morning review — $summary"
    else
      prio=2; title="⚠️ Morning review (exit $rc) — $summary"
    fi
    body="$summary
Review them in workbench → Nightly Builds hub (live: merge / requeue / rebuild)."
    # Loud at the edge: if any record errored, override to a high-priority notify
    # that quotes the per-record errors and points at the archived JSON — never
    # let a swallowed count hide a branch that pushed but never got a PR.
    if [ "''${nerr:-0}" -gt 0 ] 2>/dev/null; then
      prio=2; title="⚠️ Morning review — ''${nerr} review error(s)"
      errdetail="$(jq -r '(.errors // []) | map("• \(.id // .step // "?"): \(.error // .message // .)") | join("\n")' "$OUT" 2>/dev/null)"
      body="$summary

Review errors (full JSON: $ARCHIVE):
$errdetail

A branch may have pushed without a PR — run \`gh pr list\` and open any missing ones."
    fi
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
      # hwc-notify's schema caps title at 200 and body at 4000 chars and
      # REJECTS oversized payloads (400) — a long errdetail list made the
      # whole morning digest silently vanish (observed 2026-07-11/12, daily
      # "schema validation failed: body too_big" in the hwc-notify journal).
      # Truncate at the edge; the archived JSON keeps the full detail.
      title="$(printf '%s' "$title" | head -c 197)"
      body="$(printf '%s' "$body" | head -c 3800)"
      payload=$(jq -nc --arg t "$title" --arg b "$body" --argjson p "$prio" \
        '{topic:"nightly-builds", title:$t, body:$b, priority:$p, source:"nightly-builds", tags:["nightly-builds","morning-review"]}')
      curl -fsS -m 8 -X POST -H 'content-type: application/json' \
        -d "$payload" "$NOTIFY_URL" >/dev/null 2>&1 \
        && echo "morning-review: notify sent" \
        || echo "morning-review: WARN notify POST failed ($NOTIFY_URL)"
    fi
    exit "$rc"
  '';

  # ── Rebuild-request consumer (PRIVILEGED) ──────────────────────────────────
  # The workbench "rebuild" button drops a spool file named after the target
  # host in this dir; the path unit fires a ROOT service that runs the actual
  # `nixos-rebuild switch`. This is the ONE privileged, human-triggered action
  # in this module — everything else is unprivileged (eric) and touches only
  # branches/vault. Guarded hard: the host is validated against a fixed
  # allowlist before it is ever interpolated into a command; unknown hosts are
  # ignored and the spool file deleted. No part of the spooled file's *content*
  # is ever evaluated — only its basename, and only after allowlist match.
  rebuildSpoolDir = "/var/lib/refinery/rebuild-request";
  rebuildAllowedHosts = [ "hwc-server" "hwc-laptop" ];

  rebuildDrain = pkgs.writeShellScript "nightly-builds-rebuild-drain" ''
    set -uo pipefail
    SPOOL="${rebuildSpoolDir}"
    NOTIFY_URL="''${NB_NOTIFY_URL:-http://127.0.0.1:11600/notify}"
    FLAKE="${toString cfg.repoDir}"
    # Fixed allowlist — the ONLY hosts that may be rebuilt. Anything else is
    # dropped without eval.
    ALLOWED="${lib.concatStringsSep " " rebuildAllowedHosts}"

    notify() { # <prio> <title> <body>
      command -v curl >/dev/null 2>&1 || return 0
      command -v jq   >/dev/null 2>&1 || return 0
      local payload
      payload=$(jq -nc --arg t "$2" --arg b "$3" --argjson p "$1" \
        '{topic:"nightly-builds", title:$t, body:$b, priority:$p, source:"nightly-builds", tags:["nightly-builds","rebuild"]}')
      curl -fsS -m 8 -X POST -H 'content-type: application/json' \
        -d "$payload" "$NOTIFY_URL" >/dev/null 2>&1 || true
    }

    [ -d "$SPOOL" ] || exit 0
    shopt -s nullglob
    for f in "$SPOOL"/*; do
      [ -e "$f" ] || continue
      host="$(basename "$f")"
      # Consume the request first so a re-click during the rebuild re-arms the
      # path unit on a fresh file rather than racing this one.
      rm -f "$f"

      # Allowlist guard: exact match against the fixed list, nothing else runs.
      ok=0
      for a in $ALLOWED; do [ "$host" = "$a" ] && ok=1 && break; done
      if [ "$ok" -ne 1 ]; then
        echo "rebuild: IGNORING unknown host '$host' (not in allowlist: $ALLOWED)"
        notify 3 "🚫 Rebuild ignored — unknown host" \
          "Rejected rebuild request for '$host' (allowlist: $ALLOWED). No action taken."
        continue
      fi

      echo "rebuild: switching $host from $FLAKE"
      notify 4 "🔧 Rebuild started — $host" "nixos-rebuild switch --flake $FLAKE#$host"
      if nixos-rebuild switch --flake "$FLAKE#$host" 2>&1; then
        echo "rebuild: $host switched OK"
        notify 5 "✅ Rebuild done — $host" "nixos-rebuild switch succeeded for $host."
      else
        rc=$?
        echo "rebuild: $host FAILED (exit $rc)"
        notify 2 "❌ Rebuild failed — $host" "nixos-rebuild switch exited $rc for $host. Check journalctl -u nightly-builds-rebuild."
      fi
    done
  '';

  # Drains the run-now spool: for each requested goal, consume the request file
  # first (so a re-click during the run is captured as a fresh request and the
  # path unit doesn't re-fire on the same file), then run run.sh scoped to that
  # goal. run.sh's own lock serializes this against the 01:30 timer — if that's
  # mid-run, the targeted kick logs "previous run active" and exits 0.
  runnowDrain = pkgs.writeShellScript "nightly-builds-runnow-drain" ''
    set -uo pipefail
    SPOOL="${spoolDir}"
    [ -d "$SPOOL" ] || exit 0
    shopt -s nullglob
    for f in "$SPOOL"/*; do
      [ -e "$f" ] || continue
      goal="$(basename "$f")"
      rm -f "$f"
      echo "run-now: executing nightly-builds for goal '$goal'"
      NB_ONLY_GOAL="$goal" ${agentDir}/run.sh || echo "run-now: run.sh exited $? for '$goal'"
    done
  '';
in
{
  # OPTIONS
  options.hwc.automation.nightlyBuilds = {
    enable = lib.mkEnableOption "Nightly gauntlet-card runner (headless Claude Code)";

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 01:30:00";
      description = "systemd calendar expression for the nightly launch";
    };

    reviewOnCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 07:30:00";
      description = ''
        systemd calendar expression for the morning PR-review pass. Must fire
        AFTER onCalendar (default 01:30) so the night's branches exist to review.
      '';
    };

    reviewLlmProvider = lib.mkOption {
      type = lib.types.str;
      default = "claude-cli";
      description = "LLM provider for the morning-review pass (claude-cli | anthropic-api | ollama).";
    };

    # PRIVILEGED, off-by-default. Gates the root rebuild-request consumer: the
    # .path + root nightly-builds-rebuild.service that runs `nixos-rebuild
    # switch` for an allowlisted host when the workbench drops a spool file.
    # Ships OFF — Eric opts in per host. See the rebuildDrain comment.
    enableRebuildButton = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable the privileged, human-triggered rebuild-request consumer: a
        .path unit watching ${rebuildSpoolDir} that runs `nixos-rebuild switch`
        (as root) for a host in the fixed allowlist
        (${lib.concatStringsSep ", " rebuildAllowedHosts}). OFF by default.
      '';
    };

    maxCards = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Maximum number of queued cards to run per night";
    };

    vaultDir = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default =
        if paths.brain.server-replica != null
        then paths.brain.server-replica
        else paths.brain.vault;
      description = "Brain vault root (contains _inbox/nightly_builds/ and runs/)";
    };

    repoDir = lib.mkOption {
      type = lib.types.path;
      default = paths.nixos;
      description = "nixos repo working copy that worktrees are created from";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.vaultDir != null;
        message = "hwc.automation.nightlyBuilds: vaultDir is null — brain vault path not defined on this host";
      }
    ];

    # The run-now spool dir must exist (owned by eric, group-writable so the
    # refinery board — also eric — drops request files there).
    # The reviews dir holds the morning-review CLI's per-review JSON (and feeds
    # the board's /morning view); group-writable so both the eric-run review
    # pass and the eric-run board can read/write it.
    # The rebuild-request spool is group-writable so the (eric-run) workbench
    # MCP server can drop a <host> file; the ROOT consumer reads it (only when
    # enableRebuildButton is on).
    systemd.tmpfiles.rules = [
      "d ${spoolDir} 0775 eric users - -"
      "d ${reviewsDir} 0775 eric users - -"
    ] ++ lib.optional cfg.enableRebuildButton
      "d ${rebuildSpoolDir} 0775 eric users - -";

    systemd.services.nightly-builds = {
      description = "Nightly Builds — gauntlet card runner (headless Claude Code)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = nbEnv;
      path = nbPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        # Whole-run ceiling for the oneshot (all queued cards, sequential).
        # Per-card execution is bounded inside run.sh by NB_CARD_TIMEOUT (5h);
        # this must comfortably exceed one card + overhead, and give a small
        # queue room to drain. A wedged run still can't outlive this and block
        # the next night's timer (which also skips while the lock is held).
        TimeoutSec = 12 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        # OS-enforced Gate 7 (contained — no live side effects). Cards routinely
        # READ /mnt (media/hot audits) but must NEVER mutate it; the guarantee
        # was prompt-only. Bind /mnt read-only so a misbehaving agent physically
        # cannot move/delete media. Worktrees (/tmp/nightly), the vault
        # (runs/REPORT), the repo, and /var/lib/refinery stay writable.
        ReadOnlyPaths = [ "/mnt" ];
      };
    };

    systemd.timers.nightly-builds = {
      description = "Nightly Builds launch timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        # Not Persistent: a missed night must not fire mid-day while the
        # repo/vault are being actively worked on.
        Persistent = false;
        RandomizedDelaySec = "60s";
      };
    };

    # ── Run-now: targeted, on-demand execution from the refinery board ─────────
    # The board can't run run.sh itself (hardened/sandboxed). It drops a <goal>
    # file in spoolDir; this path unit fires the drain service, which runs
    # run.sh scoped to that one project. This is the executor behind the board's
    # "▶ Run now" button and IMMEDIATE mode.
    systemd.services.nightly-builds-runnow = {
      description = "Nightly Builds — targeted run-now drain (refinery board trigger)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = nbEnv;
      path = nbPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${runnowDrain}";
        # One targeted card is bounded by run.sh's NB_CARD_TIMEOUT (5h); allow a
        # little headroom. A queued backlog of requests drains sequentially.
        TimeoutSec = 6 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        # Same OS-enforced Gate 7 as the nightly runner: run-now executes the
        # same cards, so /mnt is read-only here too.
        ReadOnlyPaths = [ "/mnt" ];
      };
    };

    systemd.paths.nightly-builds-runnow = {
      description = "Watch the refinery run-now spool for targeted build requests";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        # Fires whenever the board drops a request file. The drain consumes the
        # files; once empty, the path unit re-arms.
        DirectoryNotEmpty = spoolDir;
        Unit = "nightly-builds-runnow.service";
      };
    };

    # ── Morning PR-review pass ─────────────────────────────────────────────────
    # AFTER the 01:30 build pass: review each night's pushed branch (the refinery
    # morning-review CLI), open PRs, write review JSON to /var/lib/refinery/reviews,
    # then send ONE consolidated digest. Same eric/hardening style as the runner.
    systemd.services.nightly-builds-review = {
      description = "Nightly Builds — morning PR-review pass (refinery morning-review CLI)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = reviewEnv;
      path = reviewPath;
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${reviewRun}";
        # Review is bounded LLM work over a handful of branches; an hour is ample
        # headroom and keeps a wedged run from lingering.
        TimeoutSec = 3600;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
      };
    };

    systemd.timers.nightly-builds-review = {
      description = "Nightly Builds morning PR-review timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.reviewOnCalendar;
        # Not Persistent: a missed morning shouldn't fire mid-day and start
        # opening PRs while the repo is being actively worked on.
        Persistent = false;
        RandomizedDelaySec = "120s";
      };
    };

    # ── Rebuild-request consumer (PRIVILEGED, opt-in) ──────────────────────────
    # !!! This is the ONLY privileged unit in this module. It runs as ROOT and
    # !!! executes `nixos-rebuild switch` for a host in the FIXED allowlist when
    # !!! the workbench rebuild button drops a spool file. Human-triggered only;
    # !!! off by default (hwc.automation.nightlyBuilds.enableRebuildButton).
    # !!! The drain validates the host against the allowlist BEFORE any
    # !!! interpolation and never evaluates spooled file content.
    systemd.services.nightly-builds-rebuild = lib.mkIf cfg.enableRebuildButton {
      description = "Nightly Builds — PRIVILEGED rebuild-request consumer (nixos-rebuild switch)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      # Root: needs the system nixos-rebuild + switch privileges. PATH carries
      # the system rebuild tool + git (flake eval) + jq/curl (notify).
      path = [ pkgs.nixos-rebuild pkgs.git pkgs.openssh pkgs.jq pkgs.curl pkgs.coreutils pkgs.bash ];
      serviceConfig = {
        Type = "oneshot";
        # Runs as root (default) — deliberately NOT the eric/hardened profile:
        # nixos-rebuild switch needs to activate the system.
        ExecStart = "${rebuildDrain}";
        TimeoutSec = 2 * 3600;
        StandardOutput = "journal";
        StandardError = "journal";
      };
    };

    systemd.paths.nightly-builds-rebuild = lib.mkIf cfg.enableRebuildButton {
      description = "Watch the refinery rebuild-request spool (workbench rebuild button)";
      wantedBy = [ "paths.target" ];
      pathConfig = {
        DirectoryNotEmpty = rebuildSpoolDir;
        Unit = "nightly-builds-rebuild.service";
      };
    };
  };
}
