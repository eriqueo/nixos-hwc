# Pure verification function; not a NixOS or Home Manager module.
{ laptopRuntimeScope, lib, pkgs, repoRoot, self, serverCudaRuntimeScope, serverRuntimeScope, system }:
{
local-release-wiring = let
  homes = map (system: system.config.home-manager.users.eric)
    (lib.attrValues self.nixosConfigurations)
    ++ map (home: home.config) (lib.attrValues self.homeConfigurations);
  gated = home: let init = home.programs.zsh.initContent; in
    lib.hasInfix "verification/release.py\" deploy" init
    && lib.hasInfix "--lane system --action" init
    && lib.hasInfix "--lane home" init
    && !(lib.hasInfix "sudo env HOME=/root nixos-rebuild" init)
    && !(lib.hasInfix "activator=$(nix build" init);
in
assert lib.assertMsg (lib.all gated homes) "Both generated activation helpers must use the local release gate";
pkgs.runCommand "local-release-wiring" {} ''touch "$out"'';

claude-installation = let
  hasClaude = packages: lib.any (p: lib.getName p == "claude-code") packages;
  coherent = home:
    let cfg = home.hwc.home.apps.claude-code; in
    cfg.enable
    && hasClaude home.home.packages == (cfg.installMethod == "nix")
    && (home.home.sessionVariables ? NODE_EXTRA_CA_CERTS) == cfg.obsidianCert.enable;
  homes = map (system: system.config.home-manager.users.eric)
    (lib.attrValues self.nixosConfigurations)
    ++ map (home: home.config) (lib.attrValues self.homeConfigurations);
  laptop = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
in
assert lib.assertMsg (lib.all coherent homes
  && laptop.hwc.home.apps.claude-code.installMethod == "native"
  && laptop.hwc.home.apps.claude-code.obsidianCert.enable
  && lib.elem "${laptop.home.homeDirectory}/.local/bin" laptop.home.sessionPath
  && lib.all (system: !hasClaude system.config.environment.systemPackages)
    (lib.attrValues self.nixosConfigurations))
  "Claude must have one app-owned installation, with native laptop updates and opt-in Obsidian trust";
pkgs.runCommand "claude-installation" { } ''touch $out'';

python-runtime-wiring = let
  hosts = [ "work" "home" "laptop" ];
  valid = host: let
    python = self.nixosConfigurations."hwc-${host}".pkgs.python3Packages;
  in lib.versionAtLeast python.streamlit.version "1.66.1"
    # Force the real package boundary, including upstream problem checks.
    && builtins.isString python.posthog.drvPath;
in assert lib.assertMsg (lib.all valid hosts)
  "Python compatibility overlay must reach normal and CUDA host package sets";
pkgs.runCommand "python-runtime-wiring" {} ''touch "$out"'';

node-runtime-wiring =
  let
    server = host: self.nixosConfigurations."hwc-${host}";
    scope = host: {
      home = serverCudaRuntimeScope;
      work = serverRuntimeScope;
      laptop = laptopRuntimeScope;
      xps = serverRuntimeScope;
    }.${host};
    runtime22 = host: (scope host).pkgs.nodejsRuntime_22;
    runtime24 = host: (scope host).pkgs.nodejsRuntime_24;
    hasRuntime = host: packages: lib.any (package: package.outPath == (runtime24 host).outPath) packages;
    hostValid = host:
      let system = server host; baseline = (scope host).buildPkgs; in
      system.pkgs.nodejs.outPath == (runtime24 host).outPath
      && system.pkgs.nodejs_22.outPath == (runtime22 host).outPath
      && system.pkgs.chromium.browser.drvPath == baseline.chromium.browser.drvPath
      && system.pkgs.python3Packages.torch.drvPath == baseline.python3Packages.torch.drvPath
      && system.pkgs.python3Packages.torchvision.drvPath == baseline.python3Packages.torchvision.drvPath
      && hasRuntime host system.config.home-manager.users.eric.hwc.home.apps.t3code.serve.packages
      && hasRuntime host self.homeConfigurations."eric@hwc-${host}".config.hwc.home.apps.t3code.serve.packages;
    commandUsesRuntime = unit:
      lib.hasPrefix "${runtime22 "work"}/bin/node "
        (server "work").config.systemd.services.${unit}.serviceConfig.ExecStart;
  in
  assert lib.assertMsg (lib.all hostValid [ "work" "home" "laptop" "xps" ])
    "Node runtime selection, Home Manager parity or no-cascade contract failed";
  assert lib.assertMsg (lib.all commandUsesRuntime [ "hwc-notify" "hwc-sys-mcp" "heartwood-cms" "hwc-leads" ])
    "Native Node22 service command did not select the corrected runtime";
  pkgs.runCommand "node-runtime-wiring" { } ''
    touch "$out"
  '';

home-rename = let
  renamed = self.nixosConfigurations ? hwc-home;
  home = self.nixosConfigurations.${if renamed then "hwc-home" else "hwc-server"}.config;
  job = home.services.borgbackup.jobs.hwc-backup;
in
assert lib.assertMsg (renamed && !(self.nixosConfigurations ? hwc-server))
  "home rename: only hwc-home may name the home machine/output";
assert home.networking.hostName == "hwc-home";
assert home.hwc.networking.hosts.servers.main == home.networking.hostName;
assert lib.elem "--hostname=${home.networking.hostName}" home.services.tailscale.extraSetFlags;
assert job.repo == "/mnt/backup/borg-hwc-server";
assert job.archiveBaseName == "hwc-server-hwc-backup";
assert job.prune.prefix == job.archiveBaseName;
assert builtins.hashFile "sha256" (repoRoot + "/machines/home/AGE_PUBLIC_KEY.txt")
  == "a98fc2db8fd8507418f110474d5a83f62e24fa4b1af10b7c92fc8066ea8a64d7";
assert lib.all (name: let c = self.nixosConfigurations.${name}.config; in
  c.hwc.networking.hosts.fqdn.main == "hwc-home.${c.hwc.networking.hosts.tailnetSuffix}"
  && lib.elem "hwc-home" c.home-manager.users.eric.hwc.home.apps.agent-harness.fleetHosts
  && !(lib.elem "hwc-server" c.home-manager.users.eric.hwc.home.apps.agent-harness.fleetHosts)
) [ "hwc-home" "hwc-work" "hwc-laptop" ];
pkgs.runCommand "home-rename" {} ''touch "$out"'';

phone-ingest-ownership = let
  home = self.nixosConfigurations.hwc-home.config;
  work = self.nixosConfigurations.hwc-work.config;
  vhost = "whisper.${work.hwc.networking.shared.vhostDomain}";
  ingestUnits = [ "inbox-processor-audio" "inbox-processor-screenshots" ];
in
assert lib.assertMsg (home.hwc.server.ai.whisper.enable && home.hwc.server.ai.whisper.gpu
  && !(work.hwc.server.ai.whisper.enable or false)
  && !(work.systemd.services ? whisper-server)
  && home.hwc.server.services.bloxelsCv.enable
  && lib.all (name: !(builtins.hasAttr name home.systemd.paths)
    && !(builtins.hasAttr name home.systemd.services)
    && builtins.hasAttr name work.systemd.paths) ingestUnits)
  "phone ingestion: home owns GPU Whisper/Bloxels; work alone processes audio/screenshots";
assert lib.elem "hwc-work" home.hwc.data.syncthing.folders.inbox-mobile.devices;
assert work.hwc.data.syncthing.folders.inbox-mobile.path == work.hwc.paths.brain.inbox-mobile;
assert work.hwc.server.services.inboxProcessor.audioInboxPath == "${work.hwc.paths.brain.inbox-mobile}/audio";
assert work.hwc.server.services.inboxProcessor.whisperUrl == "https://${vhost}";
assert !(lib.elem "whisper-server.service" work.systemd.services.inbox-processor-audio.wants);
assert lib.hasInfix "WHISPER_URL=\"https://${vhost}/v1/audio/transcriptions\""
  (builtins.readFile work.systemd.services.inbox-processor-audio.serviceConfig.ExecStart);
assert (work.hwc.networking.shared.routeOwners.whisper.owner or "main") == "main";
assert lib.hasInfix vhost home.services.caddy.extraConfig;
pkgs.runCommand "phone-ingest-ownership" {} ''touch "$out"'';

service-split-retirement = let
  server = self.nixosConfigurations.hwc-home.config;
  work = self.nixosConfigurations.hwc-work.config;
  laptopHome = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
  mailCommand = "ssh -t ${work.hwc.networking.hosts.fqdn.work} aerc";
  workHome = work.home-manager.users.eric;
  prune = workHome.systemd.user.services.podman-image-prune or {};
  peer = self.nixosConfigurations.hwc-xps.config;
  peerHome = peer.home-manager.users.eric;
  absent = units: names: lib.all (name: !(builtins.hasAttr name units)) names;
in
assert lib.assertMsg (
  lib.any (cmd: lib.hasSuffix "/bin/podman image prune --force --filter until=12h" cmd)
    (prune.Service.ExecStart or [])
  && (prune.Service.TimeoutStartSec or "") == "10min"
  && workHome.systemd.user.timers.podman-image-prune.Timer.Persistent
  && !(server.home-manager.users.eric.systemd.user.services ? podman-image-prune)
) "service split: rootless build-cache retention must be bounded and preserve referenced/named images";
assert lib.assertMsg (laptopHome.hwc.home.core.shell.aliases.aerc == mailCommand
  && lib.any (b: builtins.elemAt b._args 0 == "SUPER + E"
    && lib.hasInfix "kitty -e ${mailCommand}" (builtins.toJSON b))
    laptopHome.wayland.windowManager.hyprland.settings.bind)
  "service split: laptop shell and desktop mail must reach the work mail owner";
assert !peerHome.hwc.mail.enable && !peerHome.hwc.mail.aerc.enable && !peerHome.hwc.mail.afew.enable
  && absent peerHome.systemd.user.services [ "mbsync" "protonmail-bridge" ];
assert lib.assertMsg (absent server.systemd.services [
  "podman-authentik-server" "podman-authentik-worker" "authentik-env"
  "llama-embed" "podman-n8n" "nightly-builds"
  "proton-bridge-relay-1025" "proton-bridge-relay-1143"
]) "service split: a retired server unit returned";
assert lib.assertMsg (absent server.home-manager.users.eric.systemd.user.services
  [ "mbsync" "mbsync-trash" "mail-health" "vdirsyncer" "protonmail-bridge" ])
  "service split: retired server mail service returned";
assert lib.assertMsg (server.services.postgresql.enable
  && server.hwc.media.immich.enable && server.hwc.data.couchdb.enable
  && server.hwc.business.paperless.receipts.enable
  && builtins.hasAttr "podman-immich-redis" server.systemd.services
  && builtins.hasAttr "paperless-receipts-mover" server.systemd.paths)
  "service split: media storage or receipt ingress lost";
assert lib.assertMsg (work.hwc.automation.n8n.enable
  && work.hwc.automation.refinery.enable && work.hwc.automation.nightlyBuilds.enable
  && work.home-manager.users.eric.hwc.mail.bridge.enable
  && !work.hwc.mail.bridge.relay.enable
  && !peer.hwc.data.couchdb.enable && !peer.hwc.automation.refinery.enable
  && !peer.hwc.automation.nightlyBuilds.enable)
  "service split: application ownership regressed";
assert lib.assertMsg (lib.all (name:
  work.systemd.services.${name}.serviceConfig.ReadOnlyPaths == [ "-/mnt" ])
  [ "nightly-builds" "nightly-builds-runnow" ])
  "service split: nightly sandbox must tolerate absent media mounts";
pkgs.runCommand "service-split-retirement" {} ''touch "$out"'';
}
