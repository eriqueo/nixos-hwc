# domains/server/native/ai/hwc-control-bot/index.nix
#
# HWC control bot — one private Discord control surface (`/next`) over the
# HWC apps' typed control APIs (Lead Scout now; CRM, Research, Home in later
# slices). It owns no business state and no database: every action crosses
# the owning app's /api/control/v1 routes, keyed by the Discord interaction
# id, and lands in that app's ledger.
#
# Discord identity is declared ONCE, in
# hwc.server.ai.leadScout.discordApprovalBots.<program> with
# `gateway = "hwc-control-bot"`. Lead Scout keeps delivering that program's
# review cards over the REST API (which does not consume the Gateway); this
# unit is the sole Gateway client of the token, so the old per-program
# approval unit is not rendered for a delegated program and the two can
# never run side by side.
#
# The target registry below is the one producer of adapter URLs, token
# mounts, and service dependencies; it is rendered into HWC_CONTROL_TARGETS
# and parsed once by the app at boot.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.hwc.server.ai.hwcControlBot;
  leadScout = config.hwc.server.ai.leadScout;

  delegated = lib.filterAttrs (
    _: bot: bot.enable && bot.gateway == "hwc-control-bot"
  ) leadScout.discordApprovalBots;
  delegatedIds = builtins.attrNames delegated;
  programId = if delegatedIds == [ ] then null else builtins.head delegatedIds;
  discord =
    if programId == null then
      {
        botTokenSecret = "";
        guildId = "";
        channelId = "";
        allowedUserId = "";
      }
    else
      delegated.${programId};
  botTokenFile = "/run/agenix/${discord.botTokenSecret}";

  node = "/run/current-system/sw/bin/node";
  tsx = "${cfg.workspaceRoot}/node_modules/tsx/dist/cli.mjs";
  cli = "${cfg.projectDir}/src/cli.ts";

  # ── Target registry ──
  leadControlTokenFile = "/run/agenix/${toString leadScout.controlTokenSecret}";
  researchScout = config.hwc.server.ai.researchScout;
  researchControlTokenFile = "/run/agenix/${toString researchScout.controlTokenSecret}";
  crm = config.hwc.business.crm;
  crmControlTokenFile = "/run/agenix/${toString crm.controlTokenSecretRef}";
  homeScout = config.hwc.server.ai.homeScout;
  homeControlTokenFile = "/run/agenix/${toString homeScout.controlTokenSecret}";
  targets =
    lib.optionalAttrs cfg.targets.leadScout {
      lead = {
        url = "http://127.0.0.1:${toString leadScout.port}";
        tokenFile = leadControlTokenFile;
        program = programId;
      };
    }
    // lib.optionalAttrs cfg.targets.researchScout.enable {
      research = {
        url = "http://127.0.0.1:${toString researchScout.port}";
        tokenFile = researchControlTokenFile;
        profile = cfg.targets.researchScout.profile;
      };
    }
    // lib.optionalAttrs cfg.targets.crm.enable {
      crm = {
        url = "http://${crm.bindAddr}:${toString crm.port}";
        tokenFile = crmControlTokenFile;
      };
    }
    // lib.optionalAttrs cfg.targets.homeScout.enable {
      home = {
        url = "http://127.0.0.1:${toString homeScout.port}";
        tokenFile = homeControlTokenFile;
        profile = cfg.targets.homeScout.profile;
      };
    };
  targetTokenFiles = map (target: target.tokenFile) (builtins.attrValues targets);
  targetUnits =
    lib.optional cfg.targets.leadScout "lead-scout.service"
    ++ lib.optional cfg.targets.researchScout.enable "research-scout.service"
    ++ lib.optional cfg.targets.crm.enable "hwc-crm.service"
    ++ lib.optional cfg.targets.homeScout.enable "home-scout.service";

  # Deterministic systemd restart delays plus 0–5 s of jitter, so a Discord
  # outage does not restart every Gateway client in lock-step.
  restartJitter = pkgs.writeShellScript "hwc-control-bot-restart-jitter" ''
    exec ${pkgs.coreutils}/bin/sleep "$((RANDOM % 6))"
  '';
in
{
  #============================================================================
  # OPTIONS
  #============================================================================
  options.hwc.server.ai.hwcControlBot = {
    enable = lib.mkEnableOption "HWC Discord control bot (/next over the HWC control APIs)";

    projectDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/scout/apps/hwc-control-bot";
      description = "Checkout of the hwc-control-bot app inside the scout monorepo.";
    };

    workspaceRoot = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.user.home}/600_apps/scout";
      description = "Monorepo root whose node_modules carries the hoisted tsx.";
    };

    targets.leadScout = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable the Lead Scout adapter: HWC reply reviews via
        hwc.server.ai.leadScout's control API, authenticated with its
        controlTokenSecret. Disabling removes the domain from /next.
      '';
    };

    targets.researchScout = {
      enable = lib.mkEnableOption "the Research Scout adapter (review lane via its control API)";
      profile = lib.mkOption {
        type = lib.types.str;
        default = "llm_engineering_v1";
        description = "Research Scout classifier profile whose review queue /next serves.";
      };
    };

    targets.crm.enable = lib.mkEnableOption "the hwc-crm adapter (next actions: note, snooze, disqualify via its control API)";

    targets.homeScout = {
      enable = lib.mkEnableOption "the Home Scout adapter (listing review lane via its control API)";
      profile = lib.mkOption {
        type = lib.types.str;
        default = "hwc_remodel_v1";
        description = "Home Scout classifier profile whose review queue /next serves.";
      };
    };
  };

  #============================================================================
  # IMPLEMENTATION
  #============================================================================
  config = lib.mkIf cfg.enable {
    systemd.services.hwc-control-bot = {
      description = "HWC Discord control bot (/next over Lead Scout, CRM, Research, Home)";
      after = [ "network-online.target" ] ++ targetUnits;
      # `wants`, not `requires`: a target app being down degrades one
      # domain in /next; it must not take the whole control surface down.
      wants = [ "network-online.target" ] ++ targetUnits;
      wantedBy = [ "multi-user.target" ];

      # Five failed starts in five minutes leave the unit visibly failed
      # rather than hammering Discord; the next deploy or an operator
      # restarts it explicitly.
      startLimitIntervalSec = 300;
      startLimitBurst = 5;

      environment = {
        NODE_ENV = "production";
        LOG_LEVEL = "info";
        DISCORD_BOT_TOKEN_FILE = botTokenFile;
        HWC_CONTROL_GUILD_ID = discord.guildId;
        HWC_CONTROL_CHANNEL_ID = discord.channelId;
        HWC_CONTROL_ALLOWED_USER_ID = discord.allowedUserId;
        HWC_CONTROL_TARGETS = builtins.toJSON targets;
      };

      path = [ pkgs.nodejs ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -f ${cli}"
          "${pkgs.coreutils}/bin/test -f ${tsx}"
          "${pkgs.coreutils}/bin/test -s ${botTokenFile}"
        ]
        ++ map (file: "${pkgs.coreutils}/bin/test -s ${file}") targetTokenFiles
        ++ [ restartJitter ];
        ExecStart = "${node} ${tsx} ${cli} serve";
        WorkingDirectory = cfg.projectDir;
        User = "eric";
        Group = "users";
        Restart = "on-failure";
        RestartSec = "15s";
        # Backstop for the app's own 10 s drain deadline.
        TimeoutStopSec = "30s";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        SystemCallArchitectures = "native";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;

        ReadWritePaths = [ "/tmp" ];
      };
    };

    # VALIDATION
    assertions = [
      {
        assertion = builtins.length delegatedIds == 1;
        message = "hwc-control-bot needs exactly one enabled hwc.server.ai.leadScout.discordApprovalBots.<program> with gateway = \"hwc-control-bot\" (found ${toString (builtins.length delegatedIds)}).";
      }
      {
        assertion = programId == null || builtins.hasAttr discord.botTokenSecret config.age.secrets;
        message = "hwc-control-bot: Discord bot token secret ${discord.botTokenSecret} has no generated agenix mount.";
      }
      {
        assertion = !cfg.targets.leadScout || (leadScout.enable && leadScout.controlTokenSecret != null);
        message = "hwc-control-bot targets Lead Scout, so hwc.server.ai.leadScout must be enabled with a controlTokenSecret.";
      }
      {
        assertion =
          !cfg.targets.leadScout
          || leadScout.controlTokenSecret == null
          || builtins.hasAttr leadScout.controlTokenSecret config.age.secrets;
        message = "hwc-control-bot: Lead Scout control token secret ${toString leadScout.controlTokenSecret} has no generated agenix mount.";
      }
      {
        assertion =
          !cfg.targets.researchScout.enable
          || (researchScout.enable && researchScout.controlTokenSecret != null);
        message = "hwc-control-bot targets Research Scout, so hwc.server.ai.researchScout must be enabled with a controlTokenSecret.";
      }
      {
        assertion =
          !cfg.targets.crm.enable
          || (crm.enable && crm.controlTokenSecretRef != null
            && builtins.hasAttr crm.controlTokenSecretRef config.age.secrets);
        message = "hwc-control-bot targets hwc-crm, so hwc.business.crm must be enabled with a controlTokenSecretRef that has an agenix mount.";
      }
      {
        assertion =
          !cfg.targets.homeScout.enable
          || (homeScout.enable && homeScout.controlTokenSecret != null);
        message = "hwc-control-bot targets Home Scout, so hwc.server.ai.homeScout must be enabled with a controlTokenSecret.";
      }
    ];
  };
}
