# Pure verification function; not a NixOS or Home Manager module.
{ inputs, lib, pkgs, repoRoot, self }:
{

brainvec-deployment = let
  service = self.nixosConfigurations.hwc-work.config.systemd.services.brainvec-ingest;
  env = lib.filterAttrs (name: _: lib.hasPrefix "BRAINVEC_" name) service.environment;
  source = inputs.brainvec;
  reader = self.nixosConfigurations.hwc-work.config.systemd.services.brain-mcp.environment;
in assert reader.BRAINVEC_SOURCE == toString source;
assert lib.all (name: reader.${name} == env.${name})
  (builtins.filter (lib.hasPrefix "BRAINVEC_EMBED_") (builtins.attrNames env));
pkgs.runCommand "brainvec-deployment" { nativeBuildInputs = [ pkgs.nodejs_22 pkgs.deno ]; } ''
  node --test ${source}/contract.test.mjs
  # Test the actual rendered wrapper and environment, not a second launcher.
  ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") env)}
  export BRAINVEC_VAULT="$TMPDIR/vault" BRAINVEC_CACHE="$TMPDIR/cache"
  mkdir -p "$BRAINVEC_VAULT" "$BRAINVEC_CACHE"
  printf '# Woodworking\nCabinet joinery and wood.\n' > "$BRAINVEC_VAULT/wood.md"
  printf '# Cooking\nSoup recipes.\n' > "$BRAINVEC_VAULT/food.md"
  cat > "$TMPDIR/embed-fixture.mjs" <<'JS'
  globalThis.fetch = async (_url, options) => ({
    ok: true,
    json: async () => ({ data: JSON.parse(options.body).input.map((text, index) => ({
      index, embedding: text.toLowerCase().includes('wood') ? [1, 0] : [0, 1],
    })) }),
  });
  JS
  export NODE_OPTIONS="--import=$TMPDIR/embed-fixture.mjs"
  ${service.serviceConfig.ExecStart}
  node ${source}/query.mjs --json --k 1 woodworking > result.json
  node -e 'const r=require("./result.json"); if(r.hits[0].path!=="wood.md") process.exit(1)'
  cp "$BRAINVEC_CACHE/index.jsonl" expected.jsonl
  # Rebuild from source after discarding the derived fixture index.
  rm "$BRAINVEC_CACHE/index.jsonl" "$BRAINVEC_CACHE/meta.json"
  ${service.serviceConfig.ExecStart}
  cmp expected.jsonl "$BRAINVEC_CACHE/index.jsonl"
  # No changed notes: no embedder, GitHub, git, SSH or writable checkout.
  unset NODE_OPTIONS
  export BRAINVEC_EMBED_BASE_URL=http://127.0.0.1:1
  ${service.serviceConfig.ExecStart}
  cmp expected.jsonl "$BRAINVEC_CACHE/index.jsonl"
  node ${source}/query.mjs --json --related wood.md > related.json
  node -e 'const r=require("./related.json"); if(r.hits[0].path!=="food.md") process.exit(1)'
  # Deno consumes the same Node-compatible adapter and identity.
  export DENO_DIR="$TMPDIR/deno"
  node --input-type=module -e 'import {EMBED_ID} from "${source}/embed.mjs"; console.log(EMBED_ID)' > node-id
  deno eval 'import {EMBED_ID} from "${source}/embed.mjs"; console.log(EMBED_ID)' > deno-id
  cmp node-id deno-id
  # Pin source provenance and prove the production wrapper consumes it.
  ${pkgs.ripgrep}/bin/rg -F '${source}/ingest.mjs' ${service.serviceConfig.ExecStart}
  if ${pkgs.ripgrep}/bin/rg 'git |ssh |600_apps' ${service.serviceConfig.ExecStart}; then
    echo 'brainvec-deployment: mutable checkout or timer-side updater remains' >&2
    exit 1
  fi
  touch "$out"
'';

scout-member-backup = let
  c = self.nixosConfigurations.hwc-work.config;
  member = c.hwc.server.ai.leadScout.memberInstance;
  browserSnapshot = c.systemd.services.scout-member-snapshot or null;
  producer = c.system.build.scoutMemberSnapshot or null;
  job = c.services.borgbackup.jobs.hwc-backup;
  spec = pkgs.writeText "scout-member-backup.json" (builtins.toJSON {
    inherit producer;
    core = (repoRoot + "/domains/server/native/ai/lead-scout/member-snapshot.py");
    config = c.system.build.scoutMemberSnapshotConfig;
    unit = browserSnapshot.serviceConfig;
    unitText = c.systemd.units."scout-member-snapshot.service".text;
    hook = job.preHook;
    paths = job.paths;
    exclude = job.exclude;
    writable = job.readWritePaths;
    user = c.hwc.server.ai.leadScout.user;
    container = "${member.projectName}_db_1";
    raw = "${member.directory}/pgdata";
    graph = "${c.users.users.eric.home}/.local/share/containers/storage";
    runtime = "/run/user/1000/containers";
  });
in
assert lib.assertMsg (browserSnapshot != null
  && browserSnapshot.serviceConfig.Type == "oneshot"
  && browserSnapshot.serviceConfig.KillMode == "control-group"
  && browserSnapshot.serviceConfig.KillSignal == "SIGKILL"
  && browserSnapshot.serviceConfig.TimeoutStartSec == "15s"
  && browserSnapshot.serviceConfig.TimeoutStopSec == "5s"
  && lib.hasInfix "thaw" browserSnapshot.serviceConfig.ExecStopPost
  && lib.hasInfix "scout-member-snapshot.service" job.preHook)
  "Scout recurring browser backup needs its bounded oneshot/thaw in the actual Borg hook";
assert lib.assertMsg (producer != null && lib.hasInfix
  (builtins.unsafeDiscardStringContext (toString producer)) browserSnapshot.serviceConfig.ExecStart
  && lib.hasInfix (builtins.unsafeDiscardStringContext (toString producer)) browserSnapshot.serviceConfig.ExecStopPost)
  "Scout capture and cleanup must use the same composed producer";
pkgs.runCommand "scout-member-backup" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${spec} <<'PY'
  import json, os, pathlib, runpy, subprocess, sys, tempfile, time
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  script = pathlib.Path(spec['producer'])
  text = pathlib.Path(spec['core']).read_text()
  config = json.loads(pathlib.Path(spec['config']).read_text())
  assert spec['unit']['User'] == spec['user'] == 'eric'
  assert spec['unit']['MemoryMax'] == '2G'
  assert spec['unit']['ExecStartPre'] == str(script) + ' prepare'
  assert pathlib.PurePosixPath(config['destination']).parent == pathlib.PurePosixPath(config['data']).parent.parent
  assert spec['unit']['StateDirectory'] == config['destination'].removeprefix('/var/lib/')
  assert 'Environment=' in spec['unitText'] and '/run/wrappers/bin' in spec['unitText']
  assert 'XDG_RUNTIME_DIR=/run/user/1000' in spec['unitText']
  assert spec['container'] in config['pg'] and 'runuser' not in config['pg']
  assert 'POSTGRES_USER' in text and 'POSTGRES_DB' in text
  assert 'scout-member-snapshot.service' in spec['hook']
  assert '/var/lib/backups' in spec['paths']
  assert 'pp:' + spec['raw'] in spec['exclude']
  assert 'pp:' + config['data'] in spec['exclude']
  assert 'pp:' + config['destination'] + '/pending' in spec['exclude']
  assert 'pp:' + config['destination'] + '/previous' in spec['exclude']
  assert spec['graph'] not in spec['writable'] and spec['runtime'] not in spec['writable']
  assert '|| exit' in spec['hook'].split('scout-member-snapshot.service', 1)[1].splitlines()[0]
  module = runpy.run_path(str(script))
  snapshot = module['snapshot']
  with tempfile.TemporaryDirectory() as tmp:
      root = pathlib.Path(tmp); dest = root / 'snapshot/current.dump'
      fake = root / 'pg-port'
      fake.write_text('#!' + sys.executable + '\n' + """
  import os, sys, time
  mode = os.environ.get('SCOUT_FIXTURE_MODE', 'good')
  if 'pg_dump' in sys.argv[-1]:
      if mode == 'dump-fail': sys.exit(9)
      if mode == 'timeout': time.sleep(3)
      sys.stdout.buffer.write(b'PGDMP' + b'x' * (8192 if mode == 'oversize' else 32))
  else:
      raw = sys.stdin.buffer.read()
      if mode == 'invalid' or not raw.startswith(b'PGDMP'): sys.exit(7)
  """.strip() + '\n')
      fake.chmod(0o700)
      command = [str(fake)]
      snapshot(dest, command, max_bytes=4096, timeout_seconds=2)
      good = dest.read_bytes()
      assert good == b'PGDMP' + b'x' * 32
      assert dest.stat().st_mode & 0o777 == 0o600
      assert dest.parent.stat().st_mode & 0o777 == 0o700
      for mode in ('dump-fail', 'invalid', 'oversize', 'timeout'):
          os.environ['SCOUT_FIXTURE_MODE'] = mode
          started = time.monotonic()
          try: snapshot(dest, command, max_bytes=4096, timeout_seconds=.15)
          except (RuntimeError, subprocess.SubprocessError, OSError): pass
          else: raise AssertionError('bad producer accepted: ' + mode)
          assert time.monotonic() - started < 2
          assert dest.read_bytes() == good, mode
          assert not dest.with_name('pending.dump').exists(), mode
      os.environ.pop('SCOUT_FIXTURE_MODE')
      # A killed previous producer may leave only its pending slot. It is
      # replaced under the same lock, without accumulating timestamp files.
      dest.with_name('pending.dump').write_bytes(b'stale')
      snapshot(dest, command, max_bytes=4096, timeout_seconds=2)
      assert dest.read_bytes() == good
      import fcntl
      with (dest.parent / 'snapshot.lock').open('rb') as lock:
          fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
          try: snapshot(dest, command, max_bytes=4096, timeout_seconds=2)
          except BlockingIOError: pass
          else: raise AssertionError('concurrent snapshot acquired occupied slot')
      assert dest.read_bytes() == good
      core = runpy.run_path(spec['core'])
      # BEGIN SCOUT PROFILE PREPARATION
      profile = root / 'prepare-profile'; profile.mkdir()
      (profile / 'first').write_bytes(b'abcd')
      (profile / 'nested').mkdir()
      (profile / 'nested/second').write_bytes(b'xyz')
      (root / 'outside').write_bytes(b'not part of the profile')
      (profile / 'link').symlink_to(root / 'outside')
      (profile / 'directory-link').symlink_to(root, target_is_directory=True)
      os.mkfifo(profile / 'pipe')
      prepare = core['prepare_profile']
      settings = {'data':str(profile),'uid':os.getuid(),
          'maxBundleBytes':7,'copySeconds':1}
      assert prepare(settings, lambda: 0) == {'files':2,'bytes':7}
      for changed, clock, code in [
          ({'maxBundleBytes':6}, lambda: 0, 'profile_prepare_byte_limit'),
          ({'uid':os.getuid()+1}, lambda: 0, 'profile_owner_changed'),
          ({}, iter(range(10)).__next__, 'profile_prepare_deadline'),
      ]:
          try: prepare(settings | changed, clock)
          except core['BackupError'] as error: assert error.code == code
          else: raise AssertionError('invalid preparation accepted: ' + code)
      alias = root / 'profile-alias'; alias.symlink_to(profile, target_is_directory=True)
      try: prepare(settings | {'data':str(alias)}, lambda: 0)
      except core['BackupError'] as error: assert error.code == 'profile_path'
      else: raise AssertionError('symlink profile accepted for preparation')
      assert (profile / 'first').read_bytes() == b'abcd'
      assert (profile / 'nested/second').read_bytes() == b'xyz'
      assert (root / 'outside').read_bytes() == b'not part of the profile'
      # END SCOUT PROFILE PREPARATION
      bundle = root / 'bundles'; bundle.mkdir()
      def stage(value):
          pending = bundle / 'pending'; pending.mkdir()
          (pending / 'manifest.json').write_text('{"schemaVersion":1}')
          (pending / 'marker').write_text(value)
      stage('one'); core['publish'](bundle)
      assert (bundle / 'current/marker').read_text() == 'one'
      (bundle / 'pending').mkdir()
      try: core['publish'](bundle)
      except RuntimeError: pass
      else: raise AssertionError('incomplete bundle published')
      assert (bundle / 'current/marker').read_text() == 'one'
      (bundle / 'pending').rmdir()
      stage('two'); core['publish'](bundle)
      assert (bundle / 'current/marker').read_text() == 'two'
      assert (bundle / 'previous/marker').read_text() == 'one'
      stage('three'); core['publish'](bundle)
      assert (bundle / 'current/marker').read_text() == 'three'
      assert (bundle / 'previous/marker').read_text() == 'two'
      assert sorted(p.name for p in bundle.iterdir()) == ['current', 'previous']
      pending = bundle / 'pending'; pending.symlink_to(bundle / 'previous', target_is_directory=True)
      try: core['publish'](bundle)
      except RuntimeError: pass
      else: raise AssertionError('symlink bundle accepted')
      assert (bundle / 'current/marker').read_text() == 'three'
      pending.unlink()
      state = root / 'state.json'
      state.write_text(json.dumps({'phase':'armed','pauseRequested':True,'cid':'wrong',
          'identity':{'pid':os.getpid(),'start':'wrong','cgroup':'wrong'}}))
      try: core['thaw']({}, state)
      except RuntimeError: pass
      else: raise AssertionError('wrong process identity accepted for thaw')
      state.write_text('{"phase":"unpaused"}')
      core['thaw']({}, state)  # terminal cleanup has no repeated effect
      # The real Podman boundary rejects top after pause (exit125).
      # A frozen check must use its injected cgroup/proc reader instead.
      control = root / 'control-port'
      control.write_text('#!' + sys.executable + '\n' + """
  import sys
  if sys.argv[1] == 'top': sys.exit(125)
  print('{"jobs":0,"inline":0,"transactions":0}')
  """.strip() + '\n')
      control.chmod(0o700)
      private = {'pg':[str(control)],'podman':[str(control)],'app':'private','uid':1000}
      try: core['quiescent'](private)
      except RuntimeError: pass
      else: raise AssertionError('paused top rejection was ignored')
      core['quiescent'](private, {'phase':'frozen'}, lambda state, uid: ['podman-init','node'])
      for names in (['node','chromium'], ['podman-init'], []):
          try: core['quiescent'](private, {'phase':'frozen'}, lambda state, uid: names)
          except RuntimeError: pass
          else: raise AssertionError('invalid frozen writer set accepted')
  print('valid/failure/invalid/oversize/deadline/stale/lock/permissions/lastgood passed')
  PY
  touch "$out"
'';

scout-member-runtime = let
  c = self.nixosConfigurations.hwc-work.config;
  context = c.system.build.scoutMemberRuntimeImageContext;
  guard = c.system.build.scoutMemberImageCheck;
in pkgs.runCommand "scout-member-runtime" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${context} ${guard} <<'PY'
  import base64, hashlib, json, pathlib, sys, tarfile
  root = pathlib.Path(sys.argv[1])
  manifest = json.loads((root/'manifest.json').read_text())
  recipe = (root/'Dockerfile').read_text()
  assert manifest['schemaVersion'] == 1
  assert recipe.splitlines()[0] == 'FROM '+manifest['baseImage']
  def current(m):
      assert tuple(map(int,m['chrome']['version'].split('.'))) >= (156,0,8078,79), 'stale browser'
  current(manifest)
  old = json.loads(json.dumps(manifest)); old['chrome']['version'] = '148.0.7778.96'
  try: current(old)
  except AssertionError: print('seeded stale browser rejected')
  else: raise AssertionError('stale browser accepted')
  assert hashlib.sha256((root/manifest['chrome']['archive']).read_bytes()).hexdigest() == manifest['chrome']['sha256']
  assert len(manifest['debian']) == 65
  assert len({p['archive'] for p in manifest['debian']}) == 65
  for p in manifest['debian']:
      assert hashlib.sha256((root/'debian'/p['archive']).read_bytes()).hexdigest() == p['sha256']
  assert {p['name'] for p in manifest['npm']} == {'playwright','playwright-core','shell-quote','proxy-addr'}
  for p in manifest['npm']:
      archive = root/'npm'/p['archive']
      assert 'sha512-'+base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode() == p['hash']
      with tarfile.open(archive) as tar:
          metadata = json.load(tar.extractfile('package/package.json'))
          assert metadata['name'] == p['name'] and metadata['version'] == p['version']
      assert p['target'] in recipe and p['archive'] in recipe
  assert '--no-download' in recipe and 'apt-get update' not in recipe
  assert 'ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/google-chrome-stable' in recipe
  assert '/ms-playwright/chromium-1223' in recipe and '/ms-playwright/chromium_headless_shell-1223' in recipe
  assert '/etc/opt/chrome/policies/managed/hwc-emsign-distrust.json' in recipe
  expected = 'localhost/scout-member-runtime:51a6a0eb-chrome'+manifest['chrome']['version']+'-'+hashlib.sha256(recipe.encode()).hexdigest()[:12]
  check = pathlib.Path(sys.argv[2]).read_text()
  assert expected in check and 'existing app image differs' in check
  print('PASS fixed archives, browser floor, dependency metadata and actual image guard')
  PY
  touch "$out"
'';

lead-scout-member-recovery = let
  work = self.nixosConfigurations.hwc-work;
  candidate = work.config;
  disabled = (work.extendModules { modules = [{
    hwc.server.ai.leadScout.memberInstance.enable = lib.mkForce false;
  }]; }).config;
  member = candidate.hwc.server.ai.leadScout.memberInstance;
  unit = candidate.systemd.user.services.lead-scout-member-instance;
  s = unit.serviceConfig;
  u = unit.unitConfig;
  commandPath = command: builtins.head (lib.splitString " " command);
  budget = command: lib.toInt (lib.last (lib.splitString " " command));
in
assert lib.assertMsg (member.enable && member.projectName == "lead-scout-datax")
  "member recovery: actual work activation/project wiring missing";
assert lib.assertMsg (!(disabled.systemd.user.services ? lead-scout-member-instance)
  && !(disabled.systemd.user.units ? "lead-scout-member-instance.service")
  && disabled.hwc.server.ai.leadScout.memberInstance.vhost.enable
  && disabled.hwc.server.ai.leadScout.modelBridge.enable)
  "member recovery: disabled compatibility must omit supervision and retain vhost/bridge";
assert lib.assertMsg (unit.wantedBy == [ "default.target" ]
  && u.ConditionUser == candidate.hwc.server.ai.leadScout.user
  && candidate.users.users.eric.linger
  && unit.environment.COMPOSE_PROJECT_NAME == member.projectName
  && s.WorkingDirectory == member.directory
  && lib.hasSuffix " ${member.projectName}_app_1 ${member.projectName}_db_1" s.ExecStart)
  "member recovery: user activation/adoption wiring missing";
assert lib.assertMsg (s.Type == "exec" && !(s.RemainAfterExit or false)
  && lib.hasInfix " wait --condition=stopped --exit-first-match " s.ExecStart)
  "member recovery: foreground waiter missing";
assert lib.assertMsg (builtins.isString s.ExecStartPre && !(s ? ExecStartPost)
  && !(s ? ExecStop)) "member recovery: duplicate preparation/cleanup phases";
assert lib.assertMsg (s.Restart == "always" && s.RestartSteps == 4
  && s.RestartSec == 15 && s.RestartMaxDelaySec == 240
  && u.StartLimitBurst == 5
  && u.StartLimitIntervalSec > u.StartLimitBurst * (
    budget s.ExecStartPre + s.TimeoutStartSec + s.TimeoutStopSec
    + budget s.ExecStopPost + s.RestartMaxDelaySec))
  "member recovery: start window does not contain failed-start budgets";
assert lib.assertMsg (builtins.isString s.ExecStartPre && !(s ? ExecStartPost)
  && !(s ? ExecStop) && s.TimeoutStopSec == 90
  && s.KillSignal == "SIGTERM" && s.KillMode == "mixed"
  && s.TimeoutStartFailureMode == "kill" && s.TimeoutStopFailureMode == "kill"
  && !(s ? SuccessExitStatus) && lib.hasPrefix "-" s.ExecStart
  && budget s.ExecStartPre == 300 && budget s.ExecStopPost == 90)
  "member recovery: aggregate preparation/sole cleanup boundary missing";
assert lib.assertMsg (u.OnFailure == "hwc-service-failure-notifier@lead-scout-member-instance.service"
  && lib.hasSuffix " --user %i" candidate.systemd.user.services."hwc-service-failure-notifier@".serviceConfig.ExecStart)
  "member recovery: user terminal notifier missing";
pkgs.runCommand "lead-scout-member-recovery" {} ''
  units=${candidate.environment.etc."systemd/user".source}
  test -L "$units/default.target.wants/lead-scout-member-instance.service"
  ${pkgs.ripgrep}/bin/rg -F 'ConditionUser=${candidate.hwc.server.ai.leadScout.user}' "$units/lead-scout-member-instance.service"
  ${pkgs.ripgrep}/bin/rg -F 'OnFailure=${u.OnFailure}' "$units/lead-scout-member-instance.service"
  ${pkgs.ripgrep}/bin/rg -F 'ExecStart=${s.ExecStart}' "$units/lead-scout-member-instance.service"
  ${pkgs.ripgrep}/bin/rg -F 'ExecStartPre=${s.ExecStartPre}' "$units/lead-scout-member-instance.service"
  ${pkgs.ripgrep}/bin/rg -F 'ExecStopPost=${s.ExecStopPost}' "$units/lead-scout-member-instance.service"
  test ! -e ${disabled.environment.etc."systemd/user".source}/lead-scout-member-instance.service
  ${pkgs.ripgrep}/bin/rg -F 'timeout --signal=KILL "$1"' ${commandPath s.ExecStartPre}
  ${pkgs.ripgrep}/bin/rg -F 'timeout --signal=KILL "$1"' ${commandPath s.ExecStopPost}
  steps=$(${pkgs.gawk}/bin/awk 'NF {last=$NF} END {print last}' ${commandPath s.ExecStartPre})
  ${pkgs.python3}/bin/python3 - "$steps" <<'PYORDER'
  import pathlib, sys
  lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
  starts = [line.strip() for line in lines if ' up -d --no-build --no-recreate' in line]
  assert len(starts) == 2 and starts[0].endswith(' db') and starts[1] == starts[0][:-3], 'DB must start before app creation'
  PYORDER
  preflight=$(${pkgs.ripgrep}/bin/rg --no-config --no-line-number '^/nix/store/.*-lead-scout-member-preflight$' "$steps")
  ${pkgs.ripgrep}/bin/rg -Fx '${candidate.system.build.scoutMemberImageCheck}' "$preflight"
  jitter=$(${pkgs.ripgrep}/bin/rg --no-config --no-line-number '^/nix/store/.*-lead-scout-restart-jitter$' "$steps")
  ${pkgs.ripgrep}/bin/rg -F 'sleep "$((RANDOM % 6))"' "$jitter"
  ${pkgs.ripgrep}/bin/rg -F 'start-limit-hit' ${candidate.hwc.notifications._internal.serviceFailureNotify}/bin/hwc-service-failure-notify
  touch "$out"
'';

scout-layout = let
  work = self.nixosConfigurations.hwc-work;
  cfg = work.config;
  root = "${cfg.hwc.paths.user.home}/600_apps/scout";
  check = name: option:
    let
      app = "${root}/apps/${name}";
      service = cfg.systemd.services.${name}.serviceConfig;
      defaults = work.options.hwc.server.ai.${option};
    in lib.assertMsg (
      toString defaults.workspaceRoot.default == root
      && toString defaults.projectDir.default == app
      && toString service.WorkingDirectory == app
      # Direct node, not the tsx CLI wrapper (a second process that
      # relays its own SIGTERM): the unit's main process is node itself,
      # loading the monorepo's hoisted tsx loader and this app's CLI.
      && lib.hasSuffix "/bin/node" (builtins.head (lib.splitString " " service.ExecStart))
      && lib.hasInfix " --import ${root}/node_modules/tsx/dist/loader.mjs ${app}/src/cli.ts serve" service.ExecStart
    ) "scout-layout: ${name} defaults, rendered service or direct-node launcher left the monorepo";
in
assert check "lead-scout" "leadScout";
assert check "home-scout" "homeScout";
assert lib.all (name:
  toString cfg.systemd.services.${name}.serviceConfig.WorkingDirectory == "${root}/apps/home-scout/ingest"
  && cfg.systemd.services.${name}.environment.PYTHONPATH == "${root}/apps/home-scout/ingest"
) [ "home-scout-harvest" "home-scout-cadastral" "home-scout-redfin" "home-scout-schools" "home-scout-overlays" ];
pkgs.runCommand "scout-layout" {} ''touch "$out"'';
}
