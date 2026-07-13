# domains/business/morning-briefing/index.nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.business.morningBriefing;
  paths = config.hwc.paths;
  agentDir = "${paths.nixos}/domains/business/morning-briefing";

  # Mail-triage prompt: reasoning template (prompts/mail-triage.txt) + the
  # known-senders section generated from the canonical taxonomy
  # (domains/mail/taxonomy/ — same data.nix the notmuch rules and the MCP
  # gateway derive from; docs/plans/unified-triage-architecture.md). Rendered
  # to a store path at build and handed to run.sh via MAIL_PROMPT, so the 6am
  # run always classifies with the vocabulary of the deployed commit.
  taxonomy = import ../../mail/taxonomy/lib.nix { inherit lib; };
  mailTriagePrompt = pkgs.writeText "mail-triage-prompt.txt"
    (builtins.replaceStrings
      [ "@KNOWN_SENDERS@" ]
      [ taxonomy.promptFragment ]
      (builtins.readFile ./prompts/mail-triage.txt));
in
{
  options.hwc.business.morningBriefing = {
    enable = lib.mkEnableOption "Morning briefing agent (Claude Code CLI + MCP)";
    onCalendar = lib.mkOption {
      type = with lib.types; either str (listOf str);
      default = "*-*-* 06:00:00";
      description = ''
        systemd calendar expression(s). A list adds midday/evening dashboard
        refreshes; run.sh only emails on the pre-9am run, so extra firings
        never re-send the briefing email.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.morning-briefing = {
      description = "Morning Briefing — Claude Code CLI data gathering agent";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment.HOME = paths.user.home;
      environment.MAIL_PROMPT = "${mailTriagePrompt}";
      # git: config-drift tile (HEAD/unpushed/dirty). coredumpctl comes from
      # systemd which is always on the base PATH via /run/current-system.
      # pass+gnupg: msmtp's passwordeval for the Step-5 email (proton bridge).
      # curl: website tile (umami stats via loopback API). postgresql client
      # comes from /run/current-system/sw/bin (absolute path in run.sh).
      path = [ pkgs.bash pkgs.coreutils pkgs.findutils pkgs.gawk pkgs.gnugrep pkgs.jq pkgs.nodejs_22 pkgs.notmuch pkgs.git pkgs.msmtp pkgs.pass pkgs.gnupg pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run.sh";
        # Step 1b (gateway gather, ≤120s) + Step 2 (claude triage) both fit
        TimeoutSec = 420;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ReadWritePaths = [
          "${agentDir}/output"
          "${agentDir}/logs"
          "${agentDir}/dashboard"
          paths.user.claude
          "/tmp"
        ];
      };
    };

    systemd.timers.morning-briefing = {
      description = "Daily morning briefing timer (6am MT)";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };

    # ── On-demand mail retriage (unified-triage Phase 4) ─────────────────────
    # triage-mail.sh `delta`: classify ONLY unread inbox threads with no
    # triage/* tag and append them to the cached board — never re-buckets
    # already-classified threads, so manual moves survive (unlike the 6am
    # baseline, which deliberately re-stamps everything).
    #
    # Trigger: the MCP gateway (hwc_mail_triage action=retriage) touches
    # ~/.cache/hwc/retriage.request — a file the gateway's sandbox can already
    # write — and the path unit below starts the service. No sudo/polkit
    # needed, and the gateway's hardening stays untouched.
    systemd.services.mail-retriage = {
      description = "Mail retriage — classify unclassified unread threads on demand";
      environment.HOME = paths.user.home;
      environment.MAIL_PROMPT = "${mailTriagePrompt}";
      path = [ pkgs.bash pkgs.coreutils pkgs.jq pkgs.nodejs_22 pkgs.notmuch ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/triage-mail.sh delta";
        TimeoutSec = 300;
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        ReadWritePaths = [
          "${agentDir}/output"
          "${agentDir}/logs"
          paths.user.claude
          "/tmp"
        ];
      };
    };

    systemd.paths.mail-retriage = {
      description = "Watch for gateway retriage requests";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathModified = "${paths.user.home}/.cache/hwc/retriage.request";
        Unit = "mail-retriage.service";
      };
    };

    # ── Today-queue agent dispatch (hwc_today `agent` verb) ──────────────────
    # hwc_today queues a pre-written, Eric-approved prompt card into
    # output/dispatch/; this unit runs it through a READ-ONLY headless claude
    # (allowlist in run-dispatch.sh) and writes the report to output/reports/,
    # where the dashboard's reports/ symlink serves it. Same path-unit pattern
    # as mail-retriage above.
    systemd.services.today-dispatch = {
      description = "Today queue — run queued read-only diagnosis cards";
      environment.HOME = paths.user.home;
      path = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.jq pkgs.git pkgs.ripgrep ];
      serviceConfig = {
        Type = "oneshot";
        User = lib.mkForce "eric";
        Group = "users";
        WorkingDirectory = agentDir;
        ExecStart = "${agentDir}/run-dispatch.sh";
        TimeoutSec = 1800; # up to ~3 cards a run at the 600s per-card budget
        StandardOutput = "journal";
        StandardError = "journal";
        NoNewPrivileges = true;
        ReadWritePaths = [
          "${agentDir}/output"
          "${agentDir}/logs"
          paths.user.claude
          "/tmp"
        ];
      };
    };

    systemd.paths.today-dispatch = {
      description = "Watch for queued today-dispatch cards";
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        # PathExistsGlob, NOT DirectoryNotEmpty: only actual prompt cards may
        # fire the runner. A stray non-.md file under DirectoryNotEmpty
        # re-fired the runner in a tight loop until systemd's start-rate limit
        # killed BOTH units (observed 2026-07-12 23:39, start-limit-hit).
        PathExistsGlob = "${agentDir}/output/dispatch/*.md";
        Unit = "today-dispatch.service";
      };
    };

    # The trigger file (and its dir) must exist for PathModified to arm.
    systemd.tmpfiles.rules = [
      "d ${paths.user.home}/.cache/hwc 0755 eric users -"
      "f ${paths.user.home}/.cache/hwc/retriage.request 0644 eric users -"
      "d ${agentDir}/output/dispatch 0755 eric users -"
      "d ${agentDir}/output/reports 0755 eric users -"
    ];
  };
}
