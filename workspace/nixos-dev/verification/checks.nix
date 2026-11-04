# Pure verification function; not a NixOS or Home Manager module.
{ inputs, laptopRuntimeScope, lib, machines, pkgs, repoRoot, self, serverCudaRuntimeScope, serverRuntimeScope, system }:
{
temporary-pin-retirement = let
  # Raw locked recipes, before our overlays: overridden versions prove no expiry.
  raw = source: import source { inherit system; config.allowUnfree = true; };
  stable = raw inputs.nixpkgs-stable;
  channels = [ stable (raw inputs.nixpkgs) ];
in
assert lib.assertMsg (lib.any (p: lib.versionOlder p.electron_44.version "44.10.1") channels)
  "Retire the Electron44 overlay: both locked channels now supply >=44.10.1";
assert lib.assertMsg (lib.any (p: lib.versionOlder p.python3Packages.streamlit.version "1.66.1") channels)
  "Retire the Streamlit override: both locked channels now supply >=1.66.1";
assert lib.assertMsg (lib.versionOlder stable.ghidra.version "12.1")
  "Retire the Ghidra backport: locked stable now supplies >=12.1; retain REA's supported-range check";
pkgs.runCommand "temporary-pin-retirement" {} ''touch "$out"'';

local-release-wiring = let
  homes = map (system: system.config.home-manager.users.eric)
    (lib.attrValues self.nixosConfigurations)
    ++ map (home: home.config) (lib.attrValues self.homeConfigurations);
  gated = home: let init = home.programs.zsh.initContent; in
    builtins.length (lib.splitString "verification/release.py\" deploy" init) == 3
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
  work = self.nixosConfigurations.hwc-work;
  applications = lib.attrValues work.pkgs.pythonHttpApplications ++ [ work.pkgs.piper-tts ];
  finance = work.pkgs.pythonHttpApplications.pnc-statement-pipeline;
  clientContract = pkgs.writeText "python-finance-http-contract.py" ''
    import json
    from pathlib import Path
    import queue
    import runpy
    import socket
    import sys
    import threading

    inner = Path(sys.argv[1])
    assert sys.argv[2] in {"baseline", "fixed"}, "HTTP_CONTRACT_MODE"
    baseline = sys.argv[2] == "baseline"
    # Reuse the shipped entry's dependency prelude without calling its CLI.
    # The actual app imports its HTTP client before any test observer does.
    runpy.run_path(str(inner), run_name="runtime_client_probe")
    import http.client
    from pnc_statement_pipeline.http import JsonApi

    value = {"ok": True}
    payload = json.dumps(value, separators=(",", ":")).encode()

    def serve(listener, response, errors):
        try:
            with listener:
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(3)
                    request = b""
                    while b"\r\n\r\n" not in request:
                        data = connection.recv(1024)
                        assert data and len(request) + len(data) <= 16384, "OWNED_PEER_REQUEST_LIMIT"
                        request += data
                    assert request.startswith(b"GET /fixture HTTP/1.1\r\n"), "OWNED_PEER_METHOD"
                    connection.sendall(response)
        except BaseException as error:
            errors.put_nowait(error)

    def accepted(kind):
        listener = socket.socket()
        listener.settimeout(3)
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        address = "http://127.0.0.1:" + str(listener.getsockname()[1])
        head = b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n"
        if kind == "bad-chunk":
            response = head + b"Transfer-Encoding: chunked\r\n\r\n+" + format(len(payload), "x").encode() + b"\r\n" + payload + b"\r\n0\r\n\r\n"
        else:
            response = head + b"Content-Length: " + str(len(payload)).encode() + (b" \t" if kind == "ows" else b"") + b"\r\n\r\n" + payload
        errors = queue.Queue(maxsize=1)
        worker = threading.Thread(target=serve, args=(listener, response, errors), daemon=True)
        worker.start()
        try:
            try:
                result = JsonApi(address, "fixture-only", auth_scheme="Bearer").get("/fixture") == value
            except http.client.HTTPException:
                result = False
        finally:
            listener.close()
            worker.join(4)
            assert not worker.is_alive(), "OWNED_PEER_DRAIN"
        if not errors.empty():
            raise errors.get_nowait()
        return result

    assert accepted("normal") and accepted("ows"), "ACTUAL_FINANCE_HTTP_COMPATIBILITY"
    malformed = accepted("bad-chunk")
    assert malformed == baseline, "ACTUAL_FINANCE_HTTP_FRAMING"
    print(json.dumps({"passed": True, "actualJsonApi": True, "baseline": baseline, "malformedChunkAccepted": malformed, "httpClient": http.client.__file__, "onlyOwnedLoopbackPeers": True}))
  '';
  homeValid = home: !(home.programs.workbench.enable || home.programs.workbench.mailHelper.enable)
    || (home.programs.workbench.package.pythonHttpRuntime.httpFramingPatched or false);
  disabledWorkbench = (work.extendModules { modules = [{
    systemd.services.workbench-web.serviceConfig.ExecStart = lib.mkForce
      "${inputs.workbench.packages.${system}.default}/bin/workbench serve";
  }]; }).config;
  disabledFirefly = (work.extendModules { modules = [{
    hwc.business.firefly.explorer.package = lib.mkForce inputs.pnc-statement-pipeline.packages.${system}.default;
  }]; }).config;
  cases = map (host: let
    hostPkgs = self.nixosConfigurations."hwc-${host}".pkgs;
    original = hostPkgs.python3.runtimeSource or hostPkgs.python3;
    runtime = hostPkgs.mkPythonHttpRuntime original;
  in { inherit original runtime;
    selected = hostPkgs.python3;
    environment = runtime.withPackages (p: [ p.httpx ]);
  }) hosts;
  valid = host: let
    python = self.nixosConfigurations."hwc-${host}".pkgs.python3Packages;
  in lib.versionAtLeast python.streamlit.version "1.66.1"
    # Force the real package boundary, including upstream problem checks.
    && builtins.isString python.posthog.drvPath;
in assert lib.assertMsg (lib.all valid hosts)
  "Python compatibility overlay must reach normal and CUDA host package sets";
assert lib.assertMsg (lib.all (case:
  (case.selected.httpFramingPatched or false)
  && case.selected.outPath == case.runtime.outPath
  && case.runtime.runtimeSource.outPath == case.original.outPath
  && case.runtime.pkgs.torch.drvPath == case.original.pkgs.torch.drvPath
  && case.runtime.pkgs.torchvision.drvPath == case.original.pkgs.torchvision.drvPath
) cases) "Python runtime must preserve the native package build graph";
assert lib.assertMsg (lib.all (host: machines.${host}.hmPkgs.python3.httpFramingPatched or false) hosts
  && lib.all (host: !(self.nixosConfigurations.${host}.pkgs.python3.httpFramingPatched or false))
    [ "hwc-xps" "hwc-kids" "hwc-firestick" ])
  "Python runtime selection must cover both owned lanes and exclude other instances";
assert lib.assertMsg (lib.all (host:
  homeValid self.nixosConfigurations."hwc-${host}".config.home-manager.users.eric
  && homeValid self.homeConfigurations."eric@hwc-${host}".config
) hosts) "Workbench TUI and mail-helper must use the qualified runtime in both home lanes";
pkgs.runCommand "python-runtime-wiring" {} ''
  ${lib.concatMapStrings (case: ''
    ${case.original.interpreter} -B ${case.runtime.runtimeContract} --baseline
    ${case.runtime.interpreter} -B ${case.runtime.runtimeContract} ${case.runtime}
    ${case.environment.interpreter} -B ${case.runtime.runtimeContract} ${case.environment}
    ${case.environment.interpreter} -B -c 'import httpx; assert httpx.__version__'
  '') cases}
  ${finance.sourcePython.interpreter} -B ${clientContract} ${finance.sourceApplication}/bin/.pnc-statements-wrapped baseline
  ${finance.pythonHttpRuntime.interpreter} -B ${clientContract} ${finance}/bin/.pnc-statements-wrapped fixed
  ${pkgs.python3}/bin/python3 -B - <<'PY'
import json
from pathlib import Path
import subprocess
import tempfile

cases = json.loads(Path('${pkgs.writeText "python-runtime-cases.json" (builtins.toJSON (map (case: {
  original = case.original.interpreter;
  runtime = toString case.runtime;
  contract = toString case.runtime.runtimeContract;
  builder = toString case.runtime.runtimeBuilder;
  manifest = toString case.runtime.runtimeManifest;
  inherit (case.original) executable libPrefix;
}) cases))}').read_text())
for case in cases:
    # The real raw interpreter passes normal/OWS controls above, but fails the
    # production contract when the runtime integration is disabled.
    disabled = subprocess.run([case['original'], '-B', case['contract'], case['runtime']], capture_output=True, text=True)
    assert disabled.returncode != 0 and 'MALFORMED_HTTP_FRAMING' in disabled.stderr, 'MISSING_RUNTIME_SEED'
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        source = root / 'input/lib' / case['libPrefix'] / 'http'
        source.mkdir(parents=True)
        target = source / 'client.py'
        target.write_text('unrecognized source\n')
        command = [case['original'], '-B', case['builder'], str(root / 'input'), str(root / 'output'), case['executable'], case['libPrefix'], case['manifest']]
        drift = subprocess.run(command, capture_output=True, text=True)
        assert drift.returncode != 0 and 'PYTHON_HTTP_SOURCE_DRIFT' in drift.stderr, 'SOURCE_DRIFT_SEED'
        assert not (root / 'output').exists(), 'SOURCE_DRIFT_CREATED_OUTPUT'
print('Python raw/fixed/env/native contracts and disabled/source-drift seeds pass')
PY
  ${pkgs.python3}/bin/python3 -B - <<'PY'
import json
from pathlib import Path
import shlex
import subprocess

apps = json.loads(Path('${pkgs.writeText "python-runtime-applications.json" (builtins.toJSON (map (app: {
  path = toString app;
  original = toString app.sourceApplication;
  python = toString app.pythonHttpRuntime;
  executable = app.sourcePython.executable;
}) applications))}').read_text())
for app in apps:
    root, original, runtime = map(Path, (app['path'], app['original'], app['python']))
    proof = json.loads((root / 'nix-support/http-framing-application.json').read_text())
    assert proof['original'] == str(original) and proof['runtime'] == str(runtime), 'APP_SOURCE_BINDING'
    for entry in original.iterdir():
        if entry.name not in {'bin', 'nix-support'}:
            assert (root / entry.name).is_symlink() and (root / entry.name).resolve() == entry.resolve(), 'APP_ASSET_PARITY'
    for name, node in proof['wrapperGraph'].items():
        text = (root / 'bin' / name).read_text()
        if node['kind'] == 'python':
            assert text.splitlines()[0] == '#!' + str(runtime / 'bin' / app['executable']), 'APP_OLD_INTERPRETER'
        elif node['kind'] == 'shell':
            forwards = [shlex.split(line) for line in text.splitlines() if line.startswith('exec -a "$0" ')]
            assert len(forwards) == 1 and forwards[0][3] == str(root / 'bin' / node['target']), 'APP_OLD_FORWARD'
        else:
            raise AssertionError('APP_WRAPPER_KIND')
    for command in proof['commands']:
        normal = subprocess.run([str(root / 'bin' / command), '--help'], capture_output=True, text=True, timeout=30)
        assert normal.returncode == 0 and 'usage:' in normal.stdout.lower(), 'APP_CLI'

wiring = json.loads(Path('${pkgs.writeText "python-runtime-consumers.json" (builtins.toJSON {
  workbench = work.config.systemd.services.workbench-web.serviceConfig.ExecStart;
  workbenchPackage = toString work.pkgs.pythonHttpApplications.workbench;
  meals = work.config.systemd.services.meals.serviceConfig.ExecStart;
  mealsPackage = toString work.pkgs.pythonHttpApplications.meals;
  firefly = work.config.systemd.services.firefly-explorer.serviceConfig.ExecStart;
  fireflyPackage = toString work.pkgs.pythonHttpApplications.pnc-statement-pipeline;
  wall = work.config.systemd.services.wall-display.serviceConfig.ExecStart;
  wallConfig = toString work.config.systemd.services.wall-display.environment.WALL_CONFIG;
  piperPackage = toString work.pkgs.piper-tts;
  classifier = toString work.config.systemd.services.mail-classifier-model.serviceConfig.ExecStart;
  disabledWorkbench = disabledWorkbench.systemd.services.workbench-web.serviceConfig.ExecStart;
  disabledFirefly = disabledFirefly.systemd.services.firefly-explorer.serviceConfig.ExecStart;
  oldFinanceArgv = [ finance.sourcePython.interpreter "-B" (toString clientContract)
    "${finance.sourceApplication}/bin/.pnc-statements-wrapped" "fixed" ];
})}').read_text())
def selected(command, package, name):
    return shlex.split(command)[0] == str(Path(package) / 'bin' / name)
for key, name in [('workbench', 'workbench'), ('meals', 'hwc-meals'), ('firefly', 'firefly-explorer')]:
    assert selected(wiring[key], wiring[key + 'Package'], name), 'SERVICE_RUNTIME_BINDING:' + key
assert not selected(wiring['disabledWorkbench'], wiring['workbenchPackage'], 'workbench'), 'WORKBENCH_WIRING_SEED'
assert not selected(wiring['disabledFirefly'], wiring['fireflyPackage'], 'firefly-explorer'), 'FIREFLY_WIRING_SEED'
old_finance = subprocess.run(wiring['oldFinanceArgv'], capture_output=True, text=True, timeout=30)
assert old_finance.returncode != 0 and 'ACTUAL_FINANCE_HTTP_FRAMING' in old_finance.stderr, 'ACTUAL_FINANCE_OLD_SOURCE_RED'
wall = json.loads(Path(wiring['wallConfig']).read_text())
if wall['voice'] is not None:
    assert wall['voice']['piper'] == str(Path(wiring['piperPackage']) / 'bin/piper'), 'PIPER_CONSUMER_BINDING'
wall_python = Path(shlex.split(wiring['wall'])[0]).parent.parent
assert (wall_python / 'nix-support/http-framing.json').is_file(), 'WALL_PYTHON_BINDING'
classifier = Path(wiring['classifier'])
for _ in range(4):
    package = classifier.parent.parent
    if (package / 'nix-support/http-framing.json').is_file():
        break
    assert classifier.read_bytes().startswith(b'#!'), 'CLASSIFIER_RUNTIME_BINDING'
    forwards = [shlex.split(line.rstrip('\\').strip()) for line in classifier.read_text().splitlines() if line.strip().startswith('exec ')]
    assert len(forwards) == 1 and len(forwards[0]) >= 2, 'CLASSIFIER_FORWARD'
    classifier = Path(forwards[0][1])
else:
    raise AssertionError('CLASSIFIER_RUNTIME_BINDING')
assert (classifier.parent.parent / 'nix-support/http-framing.json').is_file(), 'CLASSIFIER_RUNTIME_BINDING'
print('Actual Python app assets, launchers, CLI, service/home/CPU wiring and disabled-caller seeds pass')
PY
  touch "$out"
'';

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
