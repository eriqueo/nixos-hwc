{
  config,
  lib,
  pkgs,
  inputs,
  osConfig ? { },
  ...
}:
let
  cfg = config.hwc.home.apps.agent-harness;
  home = config.home.homeDirectory;
  harness = inputs.agent-harness;
  revision = inputs.agent-harness.rev or "dirty";
  # The Workbench area registry lives in the system config (hwc.business.workbench);
  # null when the host has no workbench, so the tracker shows no switcher there.
  workbenchSite =
    if lib.attrByPath [ "hwc" "business" "workbench" "enable" ] false osConfig
    then lib.attrByPath [ "hwc" "business" "workbench" "site" ] null osConfig
    else null;
  # The harness manifest: programs feed the ownership contract; the matrix and
  # outside-skill lists feed `agent-harness matrix` and the doctor.
  manifest = builtins.fromTOML (builtins.readFile "${harness}/manifest.toml");
  contract = import ./contract.nix { inherit revision manifest; };
  matrixJson = pkgs.writeText "agent-harness-matrix.json" (builtins.toJSON { inherit (manifest) matrix outside; });
  expectedManifest = pkgs.writeText "agent-harness-manifest.json" (builtins.toJSON contract);
  configDirs = map (name: "${home}/${name}") ([ ".claude" ] ++ cfg.claudeConfigDirs);
  stateValidator = pkgs.writeShellApplication {
    name = "agent-state-validate";
    runtimeInputs = with pkgs; [
      git
      coreutils
      findutils
      jq
      ripgrep
      gawk
    ];
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      exec ${pkgs.bash}/bin/bash ${./state-validate.sh} "$@"
    '';
  };
  stateSync = pkgs.writeShellApplication {
    name = "agent-state-sync";
    runtimeInputs = [
      stateValidator
    ]
    ++ (with pkgs; [
      git
      coreutils
      findutils
      util-linux
      openssh
      curl
      jq
      gawk
    ]);
    text = ''
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      export AGENT_CONFIG_DIRS=${lib.escapeShellArg (lib.concatStringsSep ":" configDirs)}
      export AGENT_STATE_VALIDATOR=${stateValidator}/bin/agent-state-validate
      export AGENT_STATE_NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      exec ${pkgs.bash}/bin/bash ${./state-sync.sh} "$@"
    '';
  };
  # The commit gate's skill checks parse frontmatter with pyyaml. claimcheck,
  # which needed jsonschema, was retired 2026-11-12 (agent-harness C1).
  harnessPython = pkgs.python3.withPackages (p: [
    p.pyyaml
  ]);
  policyHook = pkgs.writeShellScriptBin "pre-commit" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.git
        pkgs.jq
        pkgs.ripgrep
        harnessPython
        pkgs.uv
      ]
    }:$PATH
    root=$(${pkgs.git}/bin/git rev-parse --show-toplevel)
    exec ${pkgs.bash}/bin/bash "$root/checks/harness-policy-check"
  '';
  cli = pkgs.writeShellApplication {
    name = "agent-harness";
    runtimeInputs = [
      stateSync
      stateValidator
      # publish runs the commit gate's skill checks.
      harnessPython
    ]
    ++ (with pkgs; [
      git
      coreutils
      findutils
      jq
      ripgrep
      openssh
      nix
      systemd
      gawk
      curl
    ]);
    text = ''
      export AGENT_HARNESS_SKILL_SET=${agentSkills}
      export AGENT_HARNESS_SKILL_ROOTS=${lib.escapeShellArg (lib.concatMapStringsSep ":" (r: "${home}/${r}") skillRoots)}
      export AGENT_HARNESS_NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      export AGENT_HARNESS_EXPECTED_MANIFEST=${expectedManifest}
      export AGENT_HARNESS_MATRIX=${matrixJson}
      export AGENT_HARNESS_SYSTEM_MANIFEST=/etc/agent-harness-manifest.json
      export AGENT_HARNESS_SOURCE=${lib.escapeShellArg cfg.editableSource}
      export AGENT_HARNESS_NIXOS=${lib.escapeShellArg cfg.nixosRepo}
      export AGENT_HARNESS_FLEET_HOSTS=${lib.escapeShellArg (lib.concatStringsSep ":" cfg.fleetHosts)}
      export AGENT_STATE_DIR=${lib.escapeShellArg cfg.stateDir}
      exec ${pkgs.bash}/bin/bash ${./control.sh} "$@"
    '';
  };
  doctor = pkgs.writeShellScriptBin "agent-harness-doctor" ''exec ${cli}/bin/agent-harness doctor "$@"'';

  # The one skill set every runtime loads: Claude (~/.claude/skills and each
  # claudeConfigDirs root), Codex (~/.agents/skills) and Pi (skillPaths). Before
  # this, Codex got two hand allowlists plus hand copies that went stale, and
  # third-party skills sat in one runtime on two hosts.
  #
  # Only top-level directories with a SKILL.md are skills. skills/synced/ is
  # Claude Code's claude.ai sync, committed by mistake; Codex and Pi recursed into
  # it and loaded a second, older copy of 25 skills.
  #
  # Copied, not linked per entry: one real tree reads the same to every runtime's
  # discovery. A name taken by both sources fails the build.
  agentSkills = pkgs.runCommand "agent-skills" { nativeBuildInputs = [ harnessPython ]; } ''
    mkdir "$out"
    for dir in ${harness}/skills/*/; do
      name=$(basename "$dir")
      [ -f "$dir/SKILL.md" ] || continue
      cp -R --no-preserve=mode "$dir" "$out/$name"
    done
    for name in ${lib.escapeShellArgs cfg.adoptedSkills}; do
      src=${inputs.cloudflare-skills}/skills/$name
      if [ ! -f "$src/SKILL.md" ]; then
        echo "agent-skills: adopted skill '$name' has no SKILL.md in cloudflare/skills" >&2
        exit 1
      fi
      if [ -e "$out/$name" ]; then
        echo "agent-skills: adopted skill '$name' collides with a harness skill; drop it from adoptedSkills" >&2
        exit 1
      fi
      cp -R --no-preserve=mode "$src" "$out/$name"
    done
    ${lib.concatStrings (
      lib.mapAttrsToList (name: src: ''
        if [ ! -f ${src}/SKILL.md ]; then
          echo "agent-skills: extra skill '${name}' has no SKILL.md at ${src}" >&2
          exit 1
        fi
        if [ -e "$out/${name}" ]; then
          echo "agent-skills: extra skill '${name}' collides with a harness or adopted skill" >&2
          exit 1
        fi
        cp -R --no-preserve=mode ${src} "$out/${name}"
      '') cfg.extraSkills
    )}
    python3 ${harness}/checks/skill-curation-check --root ${harness} --packaged "$out" \
      ${lib.optionalString (!(cfg.extraSkills ? reverse-engineer-anything)) "--without-skill reverse-engineer-anything"}
  '';
  skillRoots = map (dir: "${dir}/skills") ([ ".claude" ] ++ cfg.claudeConfigDirs) ++ [ ".agents/skills" ];

  # HELPERS: the Rust tracker (hub and `hwc-tracker` client), one recipe shared
  # with the `tracker-rust-contracts` check, which runs its contract tests.
  trackerPackage = import ./parts/tracker-package.nix { inherit pkgs harness; };

  # How tracker/t3.py reaches T3 Code: its CLI issues short bearer sessions
  # from T3's own state dir, so no token is stored. Used on each host by
  # tracker-link and tracker-relay, never by the hub.
  t3Env = {
    T3CODE_NODE = "${pkgs.nodejs}/bin/node";
    T3CODE_BIN = "${lib.attrByPath [ "hwc" "home" "apps" "t3code" "repo" ] "${home}/600_apps/t3code" config}/apps/server/dist/bin.mjs";
  };
  # Herdr for tracker links in Herdr terminals (tracker/herdr.py): the managed
  # core where apps/herdr-core is on (the servers), else the laptop's unmanaged
  # trial in ~/.local/bin. Harmless where it is absent: herdr.py probes the
  # core's socket first and reports "not running".
  herdrCore = config.hwc.home.apps.herdr-core;
  herdrEnv = {
    # serve.binary (the laptop): the app's own copy, which it keeps updated.
    TRACKER_HC_BIN = if herdrCore.enable && herdrCore.serve.binary == null then "${herdrCore.package}/bin/hc" else "${home}/.local/bin/hc";
    TRACKER_HERDR_APP_BIN = "${home}/.local/bin/herdr-app";
  };
  # tracker-open's variables; `:=` lets a caller's own values win.
  trackerOpenEnv = lib.concatStrings (lib.mapAttrsToList (k: v: '': "''${${k}:=${v}}"; export ${k}
  '') (herdrEnv // {
    TRACKER_URL = cfg.tracker.url;
    TRACKER_ROOT = cfg.tracker.root;
    WS_ROOT = cfg.workspaceRoot;
  }));
  # The herdr:// handler (tracker/herdr_link.py): a terminal link focuses it in
  # the Herdr app; a project link runs tracker-open. Failures reach notify-send.
  herdrLink = pkgs.writeShellScriptBin "herdr-link" ''
    ${trackerOpenEnv}
    : "''${TRACKER_OPEN_BIN:=${config.home.profileDirectory}/bin/tracker-open}"; export TRACKER_OPEN_BIN
    export PATH=${lib.makeBinPath [ pkgs.libnotify ]}:$PATH
    exec ${pkgs.python3}/bin/python3 ${harness}/lifecycle/tracker/herdr_link.py "$@"
  '';

  # Agents that survive a reboot in Herdr terminals (tracker/herdr_restore.py):
  # the harness hook herdr-session records each agent's session as `agent.*`
  # labels on its terminal; this command lists them and resumes waiting ones,
  # and the zsh init below resumes one at a recovered shell's first prompt.
  # Not in tracker-open: herdr.py is the tracker's project transport, and this
  # serves every Herdr terminal, tracked or not.
  herdrRestore = pkgs.writeShellScriptBin "herdr-restore" ''
    exec ${pkgs.python3}/bin/python3 -I ${harness}/lifecycle/tracker/herdr_restore.py "$@"
  '';

  # The agent-workspace allocator. Its code is static policy (the harness
  # bin/ws); the dependencies are declared here so it also runs from the
  # state-sync unit, whose PATH is systemd's alone.
  # Only inspection is elevated. Existing sudo authority is required; no new
  # sudoers grant is installed. -I excludes caller-controlled Python imports.
  wsPreservation = pkgs.writeShellScript "ws-preservation" ''
    exec /run/wrappers/bin/sudo -n -- ${pkgs.python3}/bin/python3 -I ${harness}/lifecycle/tracker/preservation.py --sudo "$@"
  '';
  ws = pkgs.writeShellApplication {
    name = "ws";
    runtimeInputs = with pkgs; [
      git
      jq
      ripgrep
      coreutils
      findutils
      gawk
      util-linux
      python3
      bash
      systemd
      # ws changes tracker records only through the hub's client.
      trackerPackage
    ];
    text = ''
      export WS_ROOT=${lib.escapeShellArg cfg.workspaceRoot}
      : "''${TRACKER_URL:=${cfg.tracker.url}}"; export TRACKER_URL
      export WS_PRESERVATION_HELPER=${wsPreservation}
      exec ${pkgs.bash}/bin/bash ${harness}/lifecycle/ws "$@"
    '';
  };

  # Keep ws's own store path outside this JSON to avoid a derivation cycle.
  # The relay binds the two immutable ports at its composition root.
  closeRuntime = pkgs.writeText "tracker-close-runtime.json" (builtins.toJSON {
    schemaVersion = 1;
    inherit revision;
    workspaceRoot = cfg.workspaceRoot;
    brainRoot = cfg.tracker.lifecycle.close.brainRoot;
    profile = cfg.tracker.lifecycle.close.profile;
  });

  # Nothing else updates the npm-global provider CLIs on a host that drives
  # them headless (T3 serve, nightly builds). Measured 2026-09-24 on hwc-server:
  # ~/.claude.json had autoUpdates=false, claude sat at 2.1.274 and codex at
  # 0.154.0. T3's model manifest gates Opus 5.5 on claude >= 2.1.280, so the
  # model never appeared. hwc-laptop, where both are used interactively, was
  # current.
  cliUpdater = pkgs.writeShellApplication {
    name = "agent-cli-update";
    # bash supplies `sh`: npm runs lifecycle scripts through the `sh` on PATH,
    # and a user unit's PATH is systemd's bin alone. Measured 2026-09-24:
    # without it, claude-code's postinstall failed with `spawn sh ENOENT`.
    runtimeInputs = with pkgs; [
      nodejs
      bash
      jq
      curl
      coreutils
    ];
    text = ''
      export NPM_CONFIG_PREFIX=${lib.escapeShellArg cfg.cliUpdates.npmPrefix}
      NOTIFY_URL=${lib.escapeShellArg cfg.notifyUrl}
      HOST=$(uname -n)
      # One line: the failing packages of the last run, empty after a clean run.
      # Alerts fire on a change to it, so a lasting failure alerts once.
      CASE_FILE="''${XDG_STATE_HOME:-$HOME/.local/state}/agent-cli-update/failed"
      mkdir -p "$(dirname "$CASE_FILE")"

      # npm ls exits 1 for a package that is not installed; that means "none".
      installed() {
        local json
        json=$(npm ls -g --depth=0 --json "$1" 2>/dev/null || true)
        [ -n "$json" ] || json='{}'
        jq -r --arg p "$1" '.dependencies[$p].version // "none"' <<< "$json"
      }

      notify() {
        jq -n --arg title "$1" --arg body "$2" \
          '{topic:"monitoring",title:$title,body:$body,priority:2,source:"agent-cli-update"}' \
          | curl -fsS --max-time 5 -H 'content-type: application/json' -d @- "$NOTIFY_URL" >/dev/null 2>&1
      }

      failed=()
      for pkg in ${lib.escapeShellArgs cfg.cliUpdates.packages}; do
        before=$(installed "$pkg")
        # npm's stderr stays in the journal; that is where a failure is read.
        if npm install -g --no-fund --no-audit "$pkg@latest" >/dev/null; then
          after=$(installed "$pkg")
          # The previous version is the rollback target: npm install -g "$pkg@<it>".
          if [ "$before" = "$after" ]; then
            echo "$pkg $after (current)"
          else
            echo "$pkg $before -> $after"
          fi
        else
          echo "$pkg: npm install failed, still $before" >&2
          failed+=("$pkg")
        fi
      done

      current="''${failed[*]}"
      previous=$(cat "$CASE_FILE" 2>/dev/null || true)
      if [ "$current" != "$previous" ]; then
        if [ -n "$current" ]; then
          title="Agent CLI update failed"
          body="$HOST could not update $current. T3 hides models that need a newer CLI. Check: journalctl --user -u agent-cli-update"
        else
          title="Agent CLI update recovered"
          body="$HOST updated $previous again. No action needed."
        fi
        # Record the case only once its alert is out, so a missed alert retries.
        if notify "$title" "$body"; then printf '%s' "$current" > "$CASE_FILE"; fi
      fi

      [ -z "$current" ]
    '';
  };
in
{
  options.hwc.home.apps.agent-harness = {
    enable = lib.mkEnableOption "shared agent harness control plane";
    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "${cfg.workspaceRoot}/state";
      defaultText = lib.literalExpression ''"''${workspaceRoot}/state"'';
      description = "The agent-state git clone: memories, MISTAKES.md, ledger/ and guard/.";
    };
    stateHub = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/home/eric/git/agent-state.git";
      description = ''
        The bare agent-state hub, set only on the host that holds it. Its
        pre-receive hook (pinned through hwc.home.core.repoHooks) refuses any
        push whose tip fails agent-state-validate, so a hand push cannot land
        state that would block every host. Emergency bypass on that host:
        git -C <hub> config --unset core.hooksPath (the next activation re-pins).
      '';
    };
    workspaceRoot = lib.mkOption {
      type = lib.types.str;
      default = osConfig.hwc.paths.user.agents or "${home}/800_agents";
      defaultText = lib.literalExpression ''osConfig.hwc.paths.user.agents or "''${home}/800_agents"'';
      description = ''
        Agent workspace root: projects/, closed/, state/ (the agent-state
        clone), log/ and LEDGER.md. Local to each host and never a Syncthing
        folder; the system module asserts that.
      '';
    };
    editableSource = lib.mkOption {
      type = lib.types.str;
      default = "${home}/800_agents/harness";
    };
    nixosRepo = lib.mkOption {
      type = lib.types.str;
      default = "${home}/.nixos";
    };
    fleetHosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "hwc-home"
        "hwc-laptop"
        "hwc-work"
      ];
    };
    notifyUrl = lib.mkOption {
      type = lib.types.str;
      # Derived from the system's hwc.notifications.notify.url (the one
      # producer); the literal is only the standalone-HM fallback.
      default = "${
        lib.attrByPath [ "hwc" "notifications" "notify" "url" ] "https://hwc-work.ocelot-wahoo.ts.net:29443" osConfig
      }/notify";
      description = "hwc-notify endpoint used for state-sync failure and recovery transitions";
    };
    tracker = {
      enable = lib.mkEnableOption ''
        the project tracker hub (`hwc-tracker serve`, harness lifecycle/tracker/rust): every agent
        project's roadmap, plan and Eric's decision cards, on one tailnet page.
        Run it on ONE host; project data syncs through the deliverables folder'';
      # Review/Close retired with the Rust hub (2026-11-14): the hub has no
      # lifecycle settings. `close.*` remains only because T3's release drill
      # (apps/t3code `t3-update`, t3_release.py) still reads it and the relay's
      # TRACKER_CLOSE_RUNTIME; remove it with that drill.
      lifecycle = {
        close = {
          enable = lib.mkEnableOption "canonical Close after ordinary native, owning cleanup and shutdown acceptance";
          brainRoot = lib.mkOption {
            type = lib.types.str;
            default = toString (lib.findFirst (p: p != null) "${home}/900_vaults/brain" [
              (lib.attrByPath [ "hwc" "paths" "brain" "vault" ] null osConfig)
              (lib.attrByPath [ "hwc" "paths" "brain" "server-replica" ] null osConfig)
            ]);
            description = "Existing brain vault used for the verified Close outcome note.";
          };
          profile = {
            instanceId = lib.mkOption {
              type = lib.types.str;
              default = "codex";
              description = "Explicit ordinary T3 provider instance; never the reserved reviewer.";
            };
            model = lib.mkOption {
              type = lib.types.str;
              default = "gpt-6.1-sol";
              description = "Ordinary model used for the bounded Close assessment.";
            };
          };
        };
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8765;
        description = "Listening port (tailnet-only: the host firewall trusts tailscale0).";
      };
      root = lib.mkOption {
        type = lib.types.str;
        default = "${home}/000_inbox/downloads/agent";
        description = "Deliverables root scanned for <project>/tracker.json.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://hwc-work:8765";
        description = "The hub as every host's tracker-relay reaches it (tailnet).";
      };
      herdrLinks.enable = lib.mkEnableOption ''
        the herdr:// link handler (harness lifecycle/tracker/herdr_link.py):
        herdr://terminal/<machine>/<tN> focuses that terminal in the Herdr app and
        herdr://project/[<machine>/]<id> runs tracker-open. Workbench and Herdr
        alerts emit these links. Desktop hosts only'';
      herdrAlerts = {
        enable = lib.mkEnableOption ''
          one hwc-notify alert (topic `projects`) when a Herdr agent on this host
          becomes blocked on input (harness lifecycle/tracker/herdr_alerts.py). It
          follows this host's core over its socket, never starts one, and repeats
          no alert for one blocked episode'';
        done = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Also alert, at priority 4, when an agent finishes a turn while nobody watched.";
        };
        notifyUrl = lib.mkOption {
          type = lib.types.str;
          default = lib.attrByPath [ "hwc" "notifications" "notify" "url" ] "" osConfig;
          defaultText = lib.literalExpression ''osConfig.hwc.notifications.notify.url or ""'';
          description = "The hwc-notify base URL; the one producer is the system option, handed to the standalone lane by flake.nix.";
        };
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = trackerPackage;
        defaultText = lib.literalMD "the Rust tracker built from the pinned harness's `lifecycle/tracker/rust`";
        readOnly = true;
        description = ''
          `hwc-tracker`: the hub's client CLI (one command to the hub per call, no
          local write). Jobs that change tracker records run this; mail-health
          sends its `sync-health-cards` through it. Declaring it installs
          nothing: only a consumer's reference builds it. Built without the
          crate's tests; `tracker-rust-contracts` runs them on the same recipe.'';
      };
      refineryUrl = lib.mkOption {
        type = lib.types.str;
        default = "http://127.0.0.1:${toString (lib.attrByPath [ "hwc" "automation" "refinery" "port" ] 8060 osConfig)}";
        defaultText = lib.literalExpression ''"http://127.0.0.1:''${osConfig.hwc.automation.refinery.port or 8060}"'';
        description = ''
          The Refinery board as the hub reaches it. The Refinery is the one store of
          work items; the hub's Backlog tab proxies GET /api/items?project=<id> from
          here with a short timeout, so a slow board never holds the single-threaded hub.'';
      };
      refineryPublicUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://refinery.hwc.iheartwoodcraft.com";
        description = "The Refinery board as Eric's browser reaches it: item links and the add-to-backlog form.";
      };
      discordCards = lib.mkOption {
        type = lib.types.submodule {
          options = {
            enable = lib.mkOption { type = lib.types.bool; description = "Post open decision cards to Discord and accept presses."; };
            tokenFile = lib.mkOption { type = lib.types.str; description = "Mounted file holding the shared hub/bot control token."; };
            ingressUrl = lib.mkOption { type = lib.types.str; description = "The control bot's loopback card ingress."; };
            since = lib.mkOption { type = lib.types.str; description = "Cards created before this date never post."; };
            summary = lib.mkOption {
              type = lib.types.bool;
              description = ''
                Keep one standing message in the projects channel showing the top
                five of the hub's ranked list. The hub edits it in place and keeps
                its message id in `~/.local/state/hwc-tracker/summary.json`.'';
            };
            publicUrl = lib.mkOption {
              type = lib.types.str;
              description = ''
                The hub as a card's Open link reaches it from Eric's phone. It needs
                the full tailnet host name: Discord rejects a link button whose host
                has no dot, so `tracker.url` (`http://hwc-work:8765`) cannot be used.'';
            };
          };
        };
        # One producer: the control bot's `targets.projects` in the system
        # config. Under system Home Manager this default reads it; the
        # standalone lane receives the same value from flake.nix.
        default =
          let
            bot = lib.attrByPath [ "hwc" "server" "ai" "hwcControlBot" ] null osConfig;
            on = bot != null && bot.enable && bot.targets.projects.enable;
          in {
            enable = on;
            tokenFile = if on then "/run/agenix/${bot.targets.projects.tokenSecret}" else "";
            ingressUrl = if on then "http://127.0.0.1:${toString bot.targets.projects.cardPort}" else "";
            since = if on then bot.targets.projects.postSince else "";
            summary = on;
            publicUrl =
              if on then
                "http://${lib.attrByPath [ "networking" "hostName" ] "localhost" osConfig}.${
                  lib.attrByPath [ "hwc" "networking" "hosts" "tailnetSuffix" ] "invalid" osConfig
                }:${toString cfg.tracker.port}"
              else "";
          };
        defaultText = lib.literalMD "derived from the system control bot's `targets.projects`; off without a system config";
        description = ''
          Discord decision cards through the HWC control bot. The hub posts each
          open card once and records Eric's Approve, Reject or Answer press.'';
      };
    };
    claudeConfigDirs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".claude_dx2_home" ];
    };
    adoptedSkills = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      # C5 removed the old global adoption set. Retained domain workflows live
      # in the pinned harness's explicit project packs; they are not discovery roots.
      default = [ ];
      description = ''
        Skills from the cloudflare-skills flake input added to the shared skill
        set. The curated inventory check rejects unapproved discovery entries.
      '';
    };
    extraSkills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = ''
        Skills other home modules add to the one skill set: name → directory
        holding SKILL.md (a store path, so the set stays one fingerprint across
        hosts). A name already taken fails the build. `rg extraSkills domains`
        lists the producers (rea).
      '';
    };
    syncInterval = lib.mkOption {
      type = lib.types.str;
      default = "1min";
    };
    cliUpdates = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Update the npm-global provider CLIs on a timer, for headless hosts.
          Off by default: hwc-laptop's claude is the native install, which
          updates itself, and its npm codex was current when this was added.
        '';
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "@anthropic-ai/claude-code"
          "@openai/codex"
        ];
        description = "npm packages installed globally at @latest on each run.";
      };
      npmPrefix = lib.mkOption {
        type = lib.types.str;
        default = "${home}/.npm-global";
        description = "npm global prefix; the T3 serve PATH reads its bin/ first.";
      };
      onCalendar = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 04:30:00";
        description = ''
          When to update. Clear of nightly-builds (01:30 launch) and its
          07:30 review, so no headless run sees the binary swapped under it.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [ {
      assertion = !cfg.tracker.herdrAlerts.enable || cfg.tracker.herdrAlerts.notifyUrl != "";
      message = "agent-harness: tracker.herdrAlerts needs notifyUrl (hwc.notifications.notify.url); without it every alert would be dropped.";
    } ];

    hwc.home.core.repoHooks.repos = lib.mkIf (cfg.stateHub != null) [ {
      path = cfg.stateHub;
      dispatched = [ ];
      pinned.pre-receive = pkgs.writeShellScript "agent-state-hub-pre-receive" ''
        exec ${stateValidator}/bin/agent-state-validate pre-receive
      '';
    } ];

    home.packages = [
      cli
      doctor
      ws
      # `hwc-tracker`: agents change tracker records only through the hub.
      trackerPackage
      stateSync
      stateValidator
      (pkgs.writeShellScriptBin "log-mistake" ''exec ${pkgs.python3}/bin/python3 ${harness}/guards/log-mistake "$@"'')
      # Fire counts per blocking guard from hooks/lib/fire-log.sh; names the
      # guards with no fire in the window (the removal budget).
      (pkgs.writeShellApplication {
        name = "guard-audit";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          jq
          openssh
        ];
        text = ''exec ${pkgs.bash}/bin/bash ${harness}/guards/guard-audit "$@"'';
      })
      # Blocks until Eric presses "Done deciding" on the tracker hub, then prints
      # the next prompt; the fallback for agents outside T3 Code.
      (pkgs.writeShellScriptBin "tracker-wait" ''exec ${pkgs.python3}/bin/python3 ${harness}/lifecycle/tracker/wait.py "$@"'')
      # Binds the calling T3 thread (or, outside T3, the Herdr terminal it runs
      # in) to a tracker project, so "Done deciding" posts the next prompt there.
      (pkgs.writeShellScriptBin "tracker-link" ''
        export ${lib.concatStringsSep " " (lib.mapAttrsToList (k: v: "${k}=${lib.escapeShellArg v}") (t3Env // herdrEnv))}
        : "''${TRACKER_URL:=${cfg.tracker.url}}"; export TRACKER_URL
        exec ${pkgs.python3}/bin/python3 ${harness}/lifecycle/tracker/t3.py "$@"
      '')
      # Shows a project's Herdr terminal, or starts its agent there with the
      # hub's next prompt (tracker/herdr.py). Variables already set win.
      (pkgs.writeShellScriptBin "tracker-open" ''
        ${trackerOpenEnv}
        exec ${pkgs.python3}/bin/python3 ${harness}/lifecycle/tracker/herdr.py "$@"
      '')
      herdrRestore
      # Stamps a project's live handoff (agent/<project>/handoff.md) with the
      # writer and each checkout's HEAD, which the hub checks against the ledgers.
      (pkgs.writeShellScriptBin "tracker-handoff" ''
        export TRACKER_ROOT=${lib.escapeShellArg cfg.tracker.root} WS_ROOT=${lib.escapeShellArg cfg.workspaceRoot} TRACKER_WS_BIN=${ws}/bin/ws
        exec ${pkgs.python3}/bin/python3 ${harness}/lifecycle/tracker/handoff_doc.py "$@"
      '')
    ]
    ++ lib.optional cfg.tracker.herdrLinks.enable herdrLink
    ++ lib.optional cfg.cliUpdates.enable cliUpdater;

    # A Herdr terminal's own interactive shell asks herdr-restore at its first
    # prompt, and again after a command that started an agent: it resumes the
    # session a reboot took (one attempt; a failure is labelled and waits), and
    # forgets one the person ended. `hwc_herdr_resume` is also what
    # `herdr-restore resume` types into a waiting terminal. Elsewhere (no
    # HC_TERMINAL_ID) this defines nothing and costs nothing.
    programs.zsh.initContent = lib.mkAfter ''
      if [[ -o interactive && -n $HC_TERMINAL_ID ]]; then
        autoload -Uz add-zsh-hook
        _hwc_herdr_due=1
        function hwc_herdr_resume {
          local code rc
          code=$(${herdrRestore}/bin/herdr-restore shell $$) || return 0
          [[ -n $code ]] || return 0
          eval "$code"
          rc=$?
          ${herdrRestore}/bin/herdr-restore settle $$ $rc
          return 0
        }
        function hwc_herdr_precmd {
          (( _hwc_herdr_due )) || return 0
          _hwc_herdr_due=0
          hwc_herdr_resume
        }
        function hwc_herdr_preexec {
          case ''${''${(z)1}[1]:t} in claude|codex|pi) _hwc_herdr_due=1 ;; esac
        }
        add-zsh-hook precmd hwc_herdr_precmd
        add-zsh-hook preexec hwc_herdr_preexec
      fi
    '';

    # herdr:// links open the exact agent. Herdr registers no scheme itself.
    xdg.dataFile."applications/herdr-link.desktop" = lib.mkIf cfg.tracker.herdrLinks.enable {
      source = "${pkgs.makeDesktopItem {
        name = "herdr-link";
        desktopName = "Herdr link";
        comment = "Focus the Herdr agent a herdr:// link names";
        exec = "${herdrLink}/bin/herdr-link %u";
        terminal = false;
        noDisplay = true;
        mimeTypes = [ "x-scheme-handler/herdr" ];
      }}/share/applications/herdr-link.desktop";
    };
    xdg.mimeApps.defaultApplications."x-scheme-handler/herdr" =
      lib.mkIf cfg.tracker.herdrLinks.enable [ "herdr-link.desktop" ];

    home.file = lib.mkMerge (
      [ (lib.genAttrs skillRoots (_: { source = agentSkills; })) ]
      # The same commands for Codex (/prompts:<name>, measured on 0.167) and Pi
      # (prompt templates in ~/.pi/agent/prompts). Both expand $ARGUMENTS.
      ++ [
        {
          ".codex/prompts".source = harness + "/adapters/claude/commands";
          ".pi/agent/prompts".source = harness + "/adapters/claude/commands";
        }
      ]
      ++ map (dir: {
        "${dir}/agents".source = harness + "/adapters/claude/agents";
        "${dir}/commands".source = harness + "/adapters/claude/commands";
        "${dir}/CLAUDE.md".source = harness + "/rules/AGENTS.md";
        "${dir}/standing-instructions.md".source = harness + "/rules/standing-instructions.md";
        "${dir}/engineering-principles.md".source = harness + "/rules/engineering-principles.md";
      }) ([ ".claude" ] ++ cfg.claudeConfigDirs)
    );

    # The delegate skill's Herdr templates (reviewer, worker, codex-reviewer,
    # codex-worker). hc reads them on whichever host runs the child terminal.
    # One link per file, so a hand-made template beside them stays.
    xdg.configFile."herdr-core/templates" = {
      source = harness + "/skills/delegate/templates";
      recursive = true;
    };

    # The S2 one-time move of the state clone into the workspace root ran on all
    # three hosts and was deleted in S8 (2026-10-01).
    # Home Manager will not replace a directory it does not own with the
    # skill-set link, and Codex keeps loading whatever sits in ~/.codex/skills.
    # So hand-made skill dirs move to a timestamped backup first; nothing is
    # deleted. Dot entries stay: ~/.codex/skills/.system is Codex's own,
    # rewritten at its startup. A second run finds nothing to move.
    home.activation.agentSkillsMigrate = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
      _skBak="${home}/.local/state/agent-harness/pre-skillset-$(date +%Y%m%dT%H%M%S)"
      _skMove() {
        run mkdir -p "$_skBak/$2"
        run mv "$1" "$_skBak/$2/"
        echo "agent-harness: moved $1 to $_skBak/$2/"
      }
      if [ -d "${home}/.agents/skills" ] && [ ! -L "${home}/.agents/skills" ]; then
        _skMove "${home}/.agents/skills" agents
      fi
      if [ -d "${home}/.codex/skills" ] && [ ! -L "${home}/.codex/skills" ]; then
        for _sk in "${home}/.codex/skills"/*; do
          [ -e "$_sk" ] || [ -L "$_sk" ] || continue
          _skMove "$_sk" codex-skills
        done
      fi
    '';

    home.activation.agentWorkspace = lib.hm.dag.entryBefore [ "agentHarnessMemoryLinks" ] ''
      root=${lib.escapeShellArg cfg.workspaceRoot}
      run mkdir -p "$root/projects" "$root/closed" "$root/log"
    '';

    home.activation.agentHarnessMemoryLinks = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${stateSync}/bin/agent-state-sync link || echo "agent-harness: state clone missing; run agent-harness doctor" >&2
      if [ -d ${lib.escapeShellArg cfg.editableSource}/.git ]; then
        run ${pkgs.git}/bin/git -C ${lib.escapeShellArg cfg.editableSource} config core.hooksPath ${policyHook}/bin
      fi
    '';

    systemd.user.services.agent-state-sync = {
      Unit.Description = "Synchronize mutable agent memories and mistakes ledger";
      Service = {
        Type = "oneshot";
        ExecStart = "${stateSync}/bin/agent-state-sync sync";
        # Re-render ~/800_agents/LEDGER.md from the ledgers just pulled, so each
        # host shows the others' projects within one sync interval. A render
        # failure never fails the sync.
        ExecStartPost = "-${ws}/bin/ws ledger --write";
        SuccessExitStatus = [ 75 ];
      };
    };
    systemd.user.timers.agent-state-sync = {
      Unit.Description = "Periodic agent state synchronization";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.syncInterval;
        Unit = "agent-state-sync.service";
      };
    };

    # Hourly per-host audit (agent-workspace S8): writes this host's ledger,
    # renders LEDGER.md, expires closed/ folders past 30 days and logs findings
    # to the journal. About 3-4 s per run, measured on all three hosts.
    systemd.user.services.ws-audit = {
      Unit.Description = "Agent workspace audit (ledger, closed/ expiry, findings)";
      Service = {
        Type = "oneshot";
        ExecStart = "${ws}/bin/ws audit";
      };
    };
    systemd.user.timers.ws-audit = {
      Unit.Description = "Hourly agent workspace audit";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    # Hourly skill and harness drift check; alerts once per change of the
    # doctor's FAIL lines. Exits non-zero while drift lasts, so it shows in
    # `systemctl --user --failed` too.
    systemd.user.services.agent-harness-drift = {
      Unit.Description = "Agent harness drift check (skill roots, hand installs, hooks)";
      Service = {
        Type = "oneshot";
        ExecStart = "${cli}/bin/agent-harness drift";
      };
    };
    systemd.user.timers.agent-harness-drift = {
      Unit.Description = "Hourly agent harness drift check";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = "hourly";
        RandomizedDelaySec = "5min";
        Persistent = true;
      };
    };

    # The hub is the one writer of each project's tracker.json, decisions.json
    # and next-prompt.md in the synced deliverables folder; agents, ws and
    # mail-health change them through `hwc-tracker`. Those files are not state
    # of this unit, so no StateDirectory or retention timer. Every setting is a
    # flag (the binary reads no environment); the crate README is the contract.
    # A refused setting exits 78, which RestartPreventExitStatus keeps from
    # looping; a held root or a busy port is exit 1 and restarts.
    # Rollback: the previous generation runs the Python hub (server.py, kept in
    # the harness) on the same files; Python reads everything Rust writes.
    systemd.user.services.hwc-tracker = lib.mkIf cfg.tracker.enable {
      Unit = {
        Description = "HWC project tracker hub (roadmaps, plans, decision cards)";
        After = [ "network-online.target" ];
        # The binary and the page are pinned; a new build or page restarts it.
        X-Restart-Triggers = [ "${trackerPackage}" "${harness}/lifecycle/tracker/index.html" ];
      };
      Service = {
        ExecStart = lib.escapeShellArgs ([
          "${trackerPackage}/bin/hwc-tracker" "serve" "--production"
          "--root" cfg.tracker.root
          "--bind" "0.0.0.0:${toString cfg.tracker.port}"
          # Every host's ws ledger, for the handoff coverage check.
          "--ledgers" "${cfg.stateDir}/ledger"
          # summary.json (the standing Discord message), outside the synced root.
          "--state-dir" "${home}/.local/state/hwc-tracker"
          "--index" "${harness}/lifecycle/tracker/index.html"
          # The page's palette and theme CSS (Python's TRACKER_TOKENS default).
          "--tokens-dir" "${home}/600_apps/scout/packages/ui/src/styles"
          # The Backlog tab's read model lives on the Refinery board.
          "--refinery-url" cfg.tracker.refineryUrl
          "--refinery-public-url" cfg.tracker.refineryPublicUrl
        ] ++ lib.optionals cfg.tracker.discordCards.enable [
          # Discord cards: the hub reads the token on each control request, so
          # a rotated token needs no restart here.
          "--control-token-file" cfg.tracker.discordCards.tokenFile
          "--card-ingress-url" cfg.tracker.discordCards.ingressUrl
          "--post-since" cfg.tracker.discordCards.since
          "--public-url" cfg.tracker.discordCards.publicUrl
        ] ++ lib.optional (cfg.tracker.discordCards.enable && cfg.tracker.discordCards.summary) "--summary"
        # Workbench area switcher: the page renders the Nix-produced registry
        # (hwc.business.workbench, the one producer of the area list) from the
        # hub's own areas.json. Absent → the switcher is not shown.
        ++ lib.optionals (workbenchSite != null) [ "--areas-file" "${workbenchSite}/areas.json" ]);
        Restart = "on-failure";
        RestartSec = 5;
        RestartPreventExitStatus = 78;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Each minute: ask the hub to post new open cards to Discord. The hub runs
    # one call at a time and records each file step under its writer lease, so
    # it cannot race Eric's clicks on decisions.json. The hub bounds it (3 sends per call, 30 a day)
    # and never repeats a card. The same call keeps the standing summary
    # message current. Stopping this timer stops all posting.
    systemd.user.services.tracker-post-cards = lib.mkIf (cfg.tracker.enable && cfg.tracker.discordCards.enable) {
      Unit = {
        Description = "Post new tracker decision cards to Discord";
        After = [ "hwc-tracker.service" ];
      };
      Service = {
        Type = "oneshot";
        # The token reaches curl on stdin, never in its arguments.
        ExecStart = pkgs.writeShellScript "tracker-post-cards" ''
          set -eu
          printf 'header = "Authorization: Bearer %s"\n' "$(${pkgs.coreutils}/bin/cat ${cfg.tracker.discordCards.tokenFile})" \
            | ${pkgs.curl}/bin/curl --silent --show-error --fail --max-time 30 --config - \
                --request POST "http://127.0.0.1:${toString cfg.tracker.port}/api/control/v1/post-cards"
        '';
      };
    };
    systemd.user.timers.tracker-post-cards = lib.mkIf (cfg.tracker.enable && cfg.tracker.discordCards.enable) {
      Unit.Description = "Post new tracker decision cards to Discord each minute";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = "minutely";
        AccuracySec = "5s";
      };
    };

    # Every host: posts the hub's pings for this host's T3 threads into the
    # local T3 and reports back (tracker/relay.py). Polls every 5 s; while the
    # host sleeps, the page shows the ping as "not answering" and it is
    # delivered on wake. A T3 that is not running is reported as a failure.
    systemd.user.services.tracker-relay = {
      Unit = {
        Description = "Deliver tracker pings into this host's T3 threads";
        After = [ "network-online.target" ];
        # relay.py imports handoff_doc; a change there must restart the relay too.
        X-Restart-Triggers = map (f: "${harness}/lifecycle/tracker/${f}") [ "relay.py" "t3.py" "herdr.py" "handoff_doc.py" "lifecycle.py" "closeout.py" "close-contract.json" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${harness}/lifecycle/tracker/relay.py";
        Environment = [
          "TRACKER_URL=${cfg.tracker.url}"
          "TRACKER_WS_BIN=${ws}/bin/ws"
          "TRACKER_LOCAL_LEDGER=${cfg.stateDir}/ledger/%H.json"
          "TRACKER_CLOSE_RUNTIME=${if cfg.tracker.lifecycle.close.enable then toString closeRuntime else ""}"
          "PATH=${lib.makeBinPath [ pkgs.systemd pkgs.git pkgs.coreutils ]}:/run/current-system/sw/bin"
        ] ++ lib.mapAttrsToList (k: v: "${k}=${v}") (t3Env // herdrEnv);
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };

    # Every Herdr host: one notification when an agent here needs Eric. The
    # Herdr mobile app shows its banner only while open, so this is the alert
    # path. Remote machines' terminals are left to their own host's watcher.
    systemd.user.services.herdr-alerts = lib.mkIf cfg.tracker.herdrAlerts.enable {
      Unit = {
        Description = "Alert when a Herdr agent on this host needs input";
        After = [ "network-online.target" ];
        X-Restart-Triggers = [ "${harness}/lifecycle/tracker/herdr_alerts.py" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 -I ${harness}/lifecycle/tracker/herdr_alerts.py";
        Environment = [
          "HERDR_ALERT_NOTIFY_URL=${cfg.tracker.herdrAlerts.notifyUrl}"
          "HERDR_ALERT_DONE=${if cfg.tracker.herdrAlerts.done then "1" else "0"}"
        ];
        Restart = "always";
        RestartSec = 10;
      };
      Install.WantedBy = [ "default.target" ];
    };

    systemd.user.services.agent-cli-update = lib.mkIf cfg.cliUpdates.enable {
      Unit = {
        Description = "Update npm-global agent CLIs (${lib.concatStringsSep ", " cfg.cliUpdates.packages})";
        After = [ "network-online.target" ];
        Wants = [ "network-online.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = lib.getExe cliUpdater;
        TimeoutStartSec = "10min";
      };
    };
    systemd.user.timers.agent-cli-update = lib.mkIf cfg.cliUpdates.enable {
      Unit.Description = "Daily npm-global agent CLI update";
      Install.WantedBy = [ "timers.target" ];
      Timer = {
        OnCalendar = cfg.cliUpdates.onCalendar;
        # A run missed while the host was down happens at the next boot.
        Persistent = true;
        Unit = "agent-cli-update.service";
      };
    };
  };
}
