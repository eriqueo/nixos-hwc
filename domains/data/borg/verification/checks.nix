# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, repoRoot, self }:
{
laptop-critical-state = let
  machine = self.nixosConfigurations.hwc-laptop;
  c = machine.config;
  job = c.services.borgbackup.jobs.hwc-backup;
  probe = mount: minimum: let
    config = (machine.extendModules { modules = [ {
      hwc.data.borg.repo = {
        path = lib.mkForce "${lib.removeSuffix "/" mount}/borg-probe";
        requiredMountPoint = lib.mkForce mount;
        minimumFreeBytes = lib.mkForce minimum;
      };
    } ]; }).config;
  in builtins.head (lib.splitString "\n" config.services.borgbackup.jobs.hwc-backup.preHook);
  fixtures = pkgs.writeText "laptop-borg-admission.json" (builtins.toJSON {
    absent = probe "/borg-mount-absent" 1;
    full = probe "/" 9223372036854775807;
    valid = probe "/" 1;
  });
in
assert c.hwc.data.borg.enable;
assert c.hwc.data.borg.repo.storageQuotaBytes == 21474836480;
assert c.hwc.data.borg.repo.minimumFreeBytes == 21474836480;
assert c.systemd.services.borgbackup-job-hwc-backup.unitConfig.AssertPathIsMountPoint == c.hwc.paths.backup;
assert lib.hasInfix "--storage-quota" job.extraInitArgs;
assert c.hwc.data.borg.sqliteSnapshots ? t3 && c.hwc.data.borg.sqliteSnapshots ? t3-v2;
assert lib.elem "${c.hwc.paths.user.home}/.t3/userdata" job.paths;
assert lib.elem "${c.hwc.paths.user.home}/.ssh" job.paths;
assert !(lib.elem c.hwc.paths.backup job.paths);
pkgs.runCommand "laptop-critical-state" { nativeBuildInputs = [ pkgs.python3 pkgs.borgbackup ]; } ''
  python3 - ${fixtures} <<'PY'
  import json, os, pathlib, sqlite3, subprocess, sys, tempfile
  fixtures = json.loads(pathlib.Path(sys.argv[1]).read_text())
  for name, expected in [('absent', 72), ('full', 73), ('valid', 0)]:
      result = subprocess.run([fixtures[name]], capture_output=True, timeout=10)
      assert result.returncode == expected, (name, result.returncode, result.stderr)
  # A real encrypted repository, quota refusal and isolated SQLite restore.
  # All data and credentials below are synthetic; no user state is accessed.
  with tempfile.TemporaryDirectory() as temp:
      root = pathlib.Path(temp)
      source = root / 'source'
      source.mkdir()
      with sqlite3.connect(source / 'state.sqlite') as db:
          db.execute('CREATE TABLE proof(value TEXT)')
          db.execute("INSERT INTO proof VALUES('last-good')")
      repository = str(root / 'repository')
      env = dict(os.environ, BORG_PASSPHRASE='synthetic-fixture-only', BORG_CACHE_DIR=str(root/'cache'), BORG_SECURITY_DIR=str(root/'security'))
      def borg(*args, okay=True):
          result = subprocess.run(['borg', *args], cwd=source, env=env, capture_output=True, timeout=30)
          if okay:
              assert result.returncode == 0, (args, result.stderr)
          return result
      borg('init', '--encryption=repokey-blake2', '--storage-quota=10M', repository)
      borg('create', repository + '::good', '.')
      (source/'oversize').write_bytes(os.urandom(16 * 1024 * 1024))
      assert borg('create', repository + '::too-big', '.', okay=False).returncode != 0
      restore = root/'restore'
      restore.mkdir()
      result = subprocess.run(['borg', 'extract', repository + '::good'], cwd=restore, env=env, capture_output=True, timeout=30)
      assert result.returncode == 0, result.stderr
      with sqlite3.connect(restore/'state.sqlite') as db:
          assert db.execute('PRAGMA quick_check').fetchone() == ('ok',)
          assert db.execute('SELECT value FROM proof').fetchone() == ('last-good',)
  print('mount/space refusal, encrypted archive, quota refusal and last-good SQLite restore pass')
  PY
  touch "$out"
'';

xps-offsite-storage = let
  c = self.nixosConfigurations.hwc-xps.config;
  repositories = c.services.borgbackup.repos;
  unit = c.systemd.services.xps-offsite-storage;
  fixture = pkgs.writeText "xps-offsite-storage.json" (builtins.unsafeDiscardStringContext (builtins.toJSON {
    script = unit.script;
    root = c.hwc.paths.backup;
  }));
in
assert unit.unitConfig.AssertPathIsMountPoint == c.hwc.paths.media.root;
assert unit.serviceConfig.TimeoutStartSec == "60s";
assert !c.hwc.monitoring.prometheus.agent.enable;
assert builtins.attrNames c.services.borgbackup.jobs == [ "hwc-backup-home" ];
assert lib.all (name:
  lib.elem "xps-offsite-storage.service" c.systemd.services."borgbackup-repo-${name}".requires
  && c.systemd.services."borgbackup-repo-${name}".unitConfig.AssertPathIsMountPoint == repositories.${name}.path
  && repositories.${name}.allowSubRepos == false
  && c.systemd.services."borgbackup-repo-${name}".wantedBy == []
) [ "hwc-home" "hwc-work" ];
assert lib.all (name: let
  host = (self.nixosConfigurations.${name}.extendModules { specialArgs.offsiteStorage = {
    ready = true;
    repositories = c.services.borgbackup.repos;
    address = c.hwc.networking.hosts.selfIp;
    hostKey = lib.removeSuffix "\n" (builtins.readFile (repoRoot + "/machines/xps/SSH_HOST_ED25519_PUBLIC_KEY.txt"));
  }; }).config;
in host.hwc.data.borg.additionalDestinations.maryland.repository == repositories.${name}.path
  && host.systemd.services.borgbackup-job-hwc-backup-maryland.serviceConfig.TimeoutStartSec == 28800
  && lib.hasInfix "--upload-ratelimit 2048" host.services.borgbackup.jobs.hwc-backup-maryland.extraCreateArgs
) [ "hwc-home" "hwc-work" ];
pkgs.runCommand "xps-offsite-storage" { nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils pkgs.ripgrep ]; } ''
  python3 - ${fixture} <<'PY'
  import copy,json,os,pathlib,re,shutil,subprocess,sys,tempfile
  spec=json.loads(pathlib.Path(sys.argv[1]).read_text())
  with tempfile.TemporaryDirectory() as temporary:
      root=pathlib.Path(temporary)
      state=root/'state.json';events=root/'events'
      probe=root/'probe'
      probe.write_text('#!'+sys.executable+'\n'+r"""
  import json,os,pathlib,sys
  name=pathlib.Path(sys.argv[0]).name;a=sys.argv[1:]
  state=pathlib.Path(os.environ['PROBE_STATE']);data=json.loads(state.read_text())
  def event(value):
      with open(os.environ['PROBE_EVENTS'],'a') as log:log.write(value+'\n')
  if name=='zpool':print(os.environ.get('PROBE_HEALTH','ONLINE'))
  elif name=='zfs':
      if a[0]=='list':
          if os.environ.get('PROBE_LIST_FAIL')=='1':raise SystemExit(2)
          print('media-pool');print('\n'.join(data))
      elif a[0]=='get':print(data[a[-1]][a[-2]])
      elif a[0]=='create':
          props=dict(a[i+1].split('=',1) for i,v in enumerate(a) if v=='-o')
          assert a[-1] not in data
          data[a[-1]]=props;state.write_text(json.dumps(data));event('create '+a[-1])
      else:raise SystemExit(2)
  elif name=='mountpoint':
      if a[-1]==os.environ.get('PROBE_BAD_MOUNT'):raise SystemExit(1)
  else:event(name)
  """)
      probe.chmod(0o755)
      for name in ['zpool','zfs','mountpoint','chmod','chown']:(root/name).symlink_to(probe)
      script=re.sub(r'/nix/store/[^/]+/bin/(zpool|zfs|mountpoint|chmod|chown)',lambda m:str(root/m[1]),spec['script'])
      script=re.sub(r'/nix/store/[^/]+/bin/(timeout|rg)',lambda m:shutil.which(m[1]),script)
      def run(initial,**extra):
          state.write_text(json.dumps(initial));events.write_text("")
          answer=subprocess.run(['bash','-c',script],env=dict(os.environ,PROBE_STATE=str(state),PROBE_EVENTS=str(events),**extra),capture_output=True,text=True,timeout=10)
          return answer,json.loads(state.read_text()),events.read_text().splitlines()
      answer,created,writes=run({})
      assert answer.returncode==0,answer.stderr
      assert set(created)=={'media-pool/offsite','media-pool/offsite/home','media-pool/offsite/work'}
      assert created['media-pool/offsite']['quota']=='1099511627776'
      assert created['media-pool/offsite/home']['quota']=='805306368000'
      assert created['media-pool/offsite/work']['quota']=='161061273600'
      answer,again,writes=run(created)
      assert answer.returncode==0 and again==created and not any(x.startswith('create ') for x in writes)
      for bad in ['media-pool/offsite','media-pool/offsite/work']:
          drift=copy.deepcopy(created);drift[bad]['quota']='1'
          answer,retained,writes=run(drift)
          assert answer.returncode!=0 and retained==drift and writes==[], 'existing drift was changed'
      for extra in [{'PROBE_HEALTH':'SUSPENDED'},{'PROBE_LIST_FAIL':'1'}]:
          answer,retained,writes=run({},**extra)
          assert answer.returncode!=0 and retained=={} and writes==[]
      answer,retained,writes=run(created,PROBE_BAD_MOUNT=created['media-pool/offsite/work']['mountpoint'])
      assert answer.returncode!=0 and retained==created and writes==[]
  print('bounded dataset creation, repeat startup, drift/missing mount/unavailable pool refusal passed')
  PY
  touch $out
'';
# Run the generated native jobs against a transport probe. Native Borg
# encryption/restore/quota behavior is independently exercised in fixtures.
borg-destinations = let
  base = self.nixosConfigurations.hwc-home;
  fixtureModule = { lib, config, ... }: {
    services.postgresql.enable = lib.mkForce false;
    hwc.data.borg.sqliteSnapshots = lib.mkForce {};
    hwc.data.borg.preBackupScript = lib.mkForce ''
      printf 'producer\n' >> "$PROBE_EVENTS"
      if [ "$PROBE_FAIL" = 1 ]; then exit 23; fi
    '';
    age.secrets.borg-fixture-ssh = {
      file = (repoRoot + "/domains/secrets/parts/system/borg-passphrase.age");
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    age.secrets.borg-fixture-pass.file = (repoRoot + "/domains/secrets/parts/system/borg-passphrase.age");
    hwc.data.borg.additionalDestinations.test = {
      host = "192.0.2.10";
      repository = "/fixture/offsite";
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEnjV1K+7pHtjsFJKKm07ty4fTayNLQ+lOPoUhTkEP50";
      sshKeySecret = "borg-fixture-ssh";
      passphraseSecret = "borg-fixture-pass";
      startAt = "*-*-* 04:00:00";
    };
    services.borgbackup.jobs = lib.genAttrs [ "hwc-backup" "hwc-backup-test" ]
      (_: { inhibitsSleep = lib.mkForce false; });
  };
  c = (base.extendModules { modules = [ fixtureModule ]; }).config;
  xps = (self.nixosConfigurations.hwc-xps.extendModules { specialArgs.offsiteStorage = {
    ready = true;
    repositories = self.nixosConfigurations.hwc-xps.config.services.borgbackup.repos;
    address = self.nixosConfigurations.hwc-xps.config.hwc.networking.hosts.selfIp;
    hostKey = lib.removeSuffix "\n" (builtins.readFile (repoRoot + "/machines/xps/SSH_HOST_ED25519_PUBLIC_KEY.txt"));
    recovery = {
      ready = true;
      address = base.config.hwc.networking.hosts.selfIp;
      repository = base.config.services.borgbackup.repos.hwc-xps;
      hostKey = lib.removeSuffix "\n" (builtins.readFile (repoRoot + "/machines/home/SSH_HOST_ED25519_PUBLIC_KEY.txt"));
    };
  }; }).config;
  primary = c.services.borgbackup.jobs.hwc-backup;
  secondary = c.services.borgbackup.jobs.hwc-backup-test;
  # Inspect this module's real assertion without forcing unrelated fleet
  # assertion messages whose interpolation may require optional settings.
  valid = config: let
    module = import (repoRoot + "/domains/data/borg/index.nix") { inherit config lib pkgs; };
    assertions = (builtins.head module.config.content.contents).assertions;
  in (lib.findFirst (a: lib.hasPrefix "Additional Borg destinations" a.message)
    (throw "destination assertion absent") assertions).assertion;
  invalid = settings: (base.extendModules { modules = [ fixtureModule settings ]; }).config;
  unit = name: c.systemd.services."borgbackup-job-${name}";
  xpsSnapshot = pkgs.writeText "xps-state-snapshot.json" (builtins.toJSON {
    hook = xps.services.borgbackup.jobs.hwc-backup-home.preHook;
    sources = lib.mapAttrs (_: snapshot: snapshot.source) xps.hwc.data.borg.sqliteSnapshots;
    state = "${xps.hwc.paths.state}/borg-sqlite";
    locks = "${xps.hwc.paths.state}/borg-jobs";
  });
  scripts = map (name: pkgs.writeText "${name}-entry.sh" (unit name).script)
    [ "hwc-backup" "hwc-backup-test" ];
in
assert lib.all (name: xps.systemd.services."borgbackup-repo-${name}".wantedBy == [ "multi-user.target" ]) [ "hwc-home" "hwc-work" ];
assert valid xps;
assert builtins.attrNames xps.services.borgbackup.jobs == [ "hwc-backup-home" ];
assert !(builtins.hasAttr "borg-check" xps.systemd.services);
assert builtins.attrNames xps.hwc.data.borg.sqliteSnapshots == [ "jellyfin" "t3-v2" ];
assert xps.hwc.data.borg.sqliteSnapshots.t3-v2.source == "${xps.hwc.paths.user.home}/.t3/userdata/statev2.sqlite";
assert xps.hwc.data.borg.sources == [ xps.services.jellyfin.dataDir "${xps.hwc.paths.user.home}/.t3/userdata" ] ++ map (relative: "${xps.users.users.dad.home}/${relative}") [ "Documents" "Desktop" "Pictures" ".config" ".local/share/Steam/userdata" ".local/share/Steam/steamapps/compatdata" ];
assert xps.services.borgbackup.jobs.hwc-backup-home.repo == "ssh://${base.config.services.borgbackup.repos.hwc-xps.user}@${base.config.hwc.networking.hosts.selfIp}${base.config.services.borgbackup.repos.hwc-xps.path}";
assert xps.systemd.services.borgbackup-job-hwc-backup-home.serviceConfig.LoadCredential == [ "borg-ssh-key:/run/agenix/borg-xps-state-ssh-key" ];
assert xps.systemd.services.borgbackup-job-hwc-backup-home.serviceConfig.TimeoutStartSec == 3600;
assert lib.elem "pf:/var/lib/hwc/jellyfin/data/jellyfin.db" xps.services.borgbackup.jobs.hwc-backup-home.exclude;
assert lib.elem "/var/lib/hwc/jellyfin/data" xps.services.borgbackup.jobs.hwc-backup-home.readWritePaths;
assert base.config.services.borgbackup.repos.hwc-xps.quota == "10G";
assert base.config.systemd.services.borgbackup-repo-hwc-xps.unitConfig.AssertPathIsMountPoint == base.config.hwc.paths.backup;
assert valid c;
assert !(valid (invalid { hwc.data.borg.encryption.mode = lib.mkForce "none"; }));
assert !(valid (invalid { hwc.data.borg.additionalDestinations.test.passphraseSecret = lib.mkForce "borg-passphrase"; }));
assert !(valid (invalid { hwc.data.borg.additionalDestinations.test.host = lib.mkForce "bad host"; }));
assert primary.repo == base.config.services.borgbackup.jobs.hwc-backup.repo;
assert secondary.repo == "ssh://borg@192.0.2.10/fixture/offsite";
assert primary.paths == secondary.paths && primary.exclude == secondary.exclude;
assert primary.preHook == secondary.preHook;
assert secondary.encryption.passCommand == "cat /run/agenix/borg-fixture-pass";
assert (unit "hwc-backup-test").serviceConfig.LoadCredential == [ "borg-ssh-key:/run/agenix/borg-fixture-ssh" ];
assert !(lib.any (lib.hasPrefix "ssh:") secondary.readWritePaths);
assert (unit "hwc-backup-test").serviceConfig.TimeoutStartSec == 43200;
assert c.systemd.services.borg-check-test.environment.BORG_RSH == secondary.environment.BORG_RSH;
assert c.systemd.services.borg-check-test.serviceConfig.LoadCredential == (unit "hwc-backup-test").serviceConfig.LoadCredential;
assert lib.hasSuffix "check --lock-wait 300 ssh://borg@192.0.2.10/fixture/offsite" c.systemd.services.borg-check-test.serviceConfig.ExecStart;
assert c.systemd.timers.borgbackup-job-hwc-backup-test.timerConfig.OnCalendar == "*-*-* 04:00:00";
pkgs.runCommand "borg-destinations" { nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils pkgs.util-linux ]; } ''
  python3 - ${lib.concatStringsSep " " (map toString scripts)} ${secondary.environment.BORG_RSH} ${xpsSnapshot} <<'PY'
  import json, os, pathlib, pwd, re, shutil, sqlite3, subprocess, sys, tempfile, time
  with tempfile.TemporaryDirectory() as temporary:
      root = pathlib.Path(temporary)
      spec = json.loads(pathlib.Path(sys.argv[4]).read_text())
      (root/'locks').mkdir()
      hook = spec['hook'].replace(spec['state'],str(root/'snapshots')).replace(spec['locks'],str(root/'locks'))
      sources = {}
      def create_source(name):
          with sqlite3.connect(sources[name]) as db:
              db.execute('CREATE TABLE history(value TEXT)')
              db.execute('INSERT INTO history VALUES(?)', ('last-good-' + name,))
      for name, live_path in spec['sources'].items():
          sources[name] = root / (name + '.db')
          create_source(name)
          hook = hook.replace(live_path, str(sources[name]))
      hook = re.sub(r"(--user\s+)(?:'eric'|eric)(?=\s|$)", lambda m:m[1]+pwd.getpwuid(os.getuid()).pw_name,hook)
      subprocess.run(['bash','-c',hook],check=True,timeout=20,capture_output=True)
      for name in sources:
          ready = root / 'snapshots/ready' / (name + '.sqlite')
          with sqlite3.connect(ready) as db:
              assert db.execute('PRAGMA quick_check').fetchone() == ('ok',)
              assert db.execute('SELECT value FROM history').fetchone() == ('last-good-' + name,)
          before = ready.read_bytes()
          sources[name].unlink()
          failed = subprocess.run(['bash','-c',hook],timeout=20,capture_output=True)
          assert failed.returncode != 0 and ready.read_bytes() == before, 'failed XPS snapshot replaced last-good copy: ' + name
          create_source(name)
  with tempfile.TemporaryDirectory() as temporary:
      root = pathlib.Path(temporary)
      lockdir = root / 'locks'
      lockdir.mkdir()
      bindir = root / 'bin'
      bindir.mkdir()
      # Execute the native generated job, replacing only repository I/O.
      probe = bindir / 'borg'
      probe.write_text('#!' + shutil.which('bash') + '\n'
          'printf "%s\n" "$1" >> "$PROBE_EVENTS"\n'
          'if [ "$PROBE_TRANSPORT_FAIL" = 1 ]; then exit 42; fi\n'
          'if [ "$1" = create ]; then\n'
          '  touch "$PROBE_ENTERED"\n'
          '  while [ ! -e "$PROBE_RELEASE" ]; do sleep .02; done\n'
          'fi\n')
      probe.chmod(0o755)
      transport = pathlib.Path(sys.argv[3]).read_text()
      assert 'StrictHostKeyChecking=yes' in transport and 'IdentitiesOnly=yes' in transport
      assert 'UserKnownHostsFile=' in transport and '$CREDENTIALS_DIRECTORY/borg-ssh-key' in transport
      scripts = []
      for index, entry in enumerate(sys.argv[1:3]):
          command = pathlib.Path(entry).read_text().strip()
          assert command.startswith('exec '), command
          native = pathlib.Path(command.removeprefix('exec ')).read_text()
          assert 'exec 9>' in native and 'flock --wait 300 9' in native, 'serialization integration absent'
          native = native.replace('${c.hwc.paths.state}/borg-jobs', str(lockdir))
          # One accelerated deadline; the production value remains pinned above.
          native = native.replace('flock --wait 300 9', 'flock --wait 1 9')
          script = root / ('job-' + str(index))
          script.write_text(native)
          scripts.append(script)
      def environment(label, fail=False, transport_fail=False):
          return dict(os.environ, PATH=str(bindir) + ':' + os.environ['PATH'],
              PROBE_EVENTS=str(root / (label + '-events')), PROBE_FAIL='1' if fail else '0',
              PROBE_TRANSPORT_FAIL='1' if transport_fail else '0',
              PROBE_ENTERED=str(root / (label + '-entered')), PROBE_RELEASE=str(root / (label + '-release')))
      def launch(index, label, fail=False, transport_fail=False):
          return subprocess.Popen(['bash', str(scripts[index])], env=environment(label, fail, transport_fail),
              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      def finish(process):
          process.communicate(timeout=8)
          return process.returncode
      def wait_for(path):
          until = time.monotonic() + 5
          while not path.exists():
              assert time.monotonic() < until, path
              time.sleep(.02)
      processes = []
      try:
          first = launch(0, 'first'); processes.append(first)
          wait_for(root / 'first-entered')
          # The lock must cover create, not only the producer's preHook.
          (root / 'blocked-release').touch()
          second = launch(1, 'blocked'); processes.append(second)
          assert finish(second) != 0
          assert not (root / 'blocked-events').exists(), 'producer ran despite held archive lock'
          (root / 'first-release').touch()
          assert finish(first) == 0
          (root / 'next-release').touch()
          next_job = launch(1, 'next'); processes.append(next_job)
          assert finish(next_job) == 0
          assert (root / 'next-events').read_text().splitlines()[0] == 'producer'
          failed = launch(1, 'failed', True); processes.append(failed)
          assert finish(failed) == 23
          assert (root / 'failed-events').read_text().splitlines() == ['producer'], 'archive ran after producer failure'
          offline = launch(1, 'offline', transport_fail=True); processes.append(offline)
          assert finish(offline) == 42
          assert not (root / 'offline-entered').exists()
          (root / 'primary-after-outage-release').touch()
          primary_after = launch(0, 'primary-after-outage'); processes.append(primary_after)
          assert finish(primary_after) == 0, 'offsite failure disabled the primary job'
      finally:
          for process in processes:
              if process.poll() is None:
                  process.kill()
                  process.communicate(timeout=5)
  print('native jobs: serialization, lock timeout, recovery and producer failure passed')
  PY
  touch $out
'';
# Exercise rendered Borg hooks and helpers, including their failure paths.
borg-recovery = let
  hosts = map (name: self.nixosConfigurations.${name}.config) [ "hwc-home" "hwc-work" ];
  fixtures = map (c: pkgs.writeText "borg-recovery.json" (builtins.toJSON {
    host = c.networking.hostName;
    hook = c.services.borgbackup.jobs.hwc-backup.preHook;
    customHook = c.hwc.data.borg.preBackupScript;
    snapshots = c.hwc.data.borg.sqliteSnapshots;
    stateRoot = "${c.hwc.paths.state}/borg-sqlite";
    lockRoot = "${c.hwc.paths.state}/borg-jobs";
    paths = c.services.borgbackup.jobs.hwc-backup.paths;
    exclude = c.services.borgbackup.jobs.hwc-backup.exclude;
    immich = lib.optionalAttrs (c.hwc.media.immich.enable or false) {
      root = c.hwc.media.immich.storage.basePath;
      originals = with c.hwc.media.immich.storage.locations; [ library profile ];
      regenerable = with c.hwc.media.immich.storage.locations; [ thumbs encodedVideo ];
    };
    cli = "${lib.findFirst (p: (p.name or "") == "borg-sqlite-snapshot") null c.environment.systemPackages}/bin/borg-sqlite-snapshot";
  })) hosts;
  restore = lib.findFirst (p: (p.name or "") == "borg-restore") null
    self.nixosConfigurations.hwc-work.config.environment.systemPackages;
in
assert lib.all (c: !(lib.hasInfix "break-lock"
  (c.systemd.services.borgbackup-job-hwc-backup.preStart or ""))) hosts;
assert lib.all (c: lib.all (snapshot: lib.elem (builtins.dirOf snapshot.source)
  c.services.borgbackup.jobs.hwc-backup.readWritePaths) (builtins.attrValues c.hwc.data.borg.sqliteSnapshots)) hosts;
assert lib.all (c: lib.hasInfix (builtins.unsafeDiscardStringContext "${c.services.postgresql.package}/bin/pg_dumpall")
  c.services.borgbackup.jobs.hwc-backup.preHook) hosts;
assert lib.assertMsg (lib.all (c:
  let snapshots = c.hwc.data.borg.sqliteSnapshots;
  in snapshots ? t3 && snapshots ? t3-v2
    && snapshots.t3-v2.source == "${dirOf snapshots.t3.source}/statev2.sqlite"
    && snapshots.t3-v2.user == snapshots.t3.user
) hosts) "T3 current statev2.sqlite needs an online snapshot alongside retained V1 history";
assert lib.assertMsg (lib.all (c: !c.hwc.automation.n8n.enable || (
  c.hwc.data.borg.sqliteSnapshots ? n8n
  && c.hwc.data.borg.sqliteSnapshots.n8n.source == "${c.hwc.automation.n8n.dataDir}/database.sqlite"
  && c.hwc.data.borg.sqliteSnapshots.n8n.user == "eric"
  && lib.any (p: p == c.hwc.automation.n8n.dataDir
    || lib.hasPrefix "${lib.removeSuffix "/" p}/" c.hwc.automation.n8n.dataDir)
    c.services.borgbackup.jobs.hwc-backup.paths
)) hosts) "n8n needs its online SQLite snapshot and config/key directory in Borg";
assert lib.assertMsg (lib.all (c: !(c.hwc.media.audiobookshelf.enable or false) || (
  let
    cfg = c.hwc.media.audiobookshelf;
    snapshot = c.hwc.data.borg.sqliteSnapshots.audiobookshelf or null;
    covered = path: lib.any (p: p == path
      || lib.hasPrefix "${lib.removeSuffix "/" p}/" path)
      c.services.borgbackup.jobs.hwc-backup.paths;
  in snapshot != null
    && lib.baseNameOf snapshot.source == "absdatabase.sqlite"
    && snapshot.user == "root"
    && lib.elem "${dirOf snapshot.source}:/config"
      c.virtualisation.oci-containers.containers.audiobookshelf.volumes
    && covered (dirOf snapshot.source)
    && covered (toString cfg.metadata)
)) hosts) "Audiobookshelf needs its online SQLite snapshot and mounted config/metadata in Borg";
pkgs.runCommand "borg-recovery" { nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.coreutils pkgs.borgbackup pkgs.util-linux ]; } ''
  python3 - ${lib.concatStringsSep " " (map toString fixtures)} ${restore}/bin/borg-restore <<'PY'
  import gzip, hashlib, json, os, pathlib, pwd, re, shlex, shutil, sqlite3, subprocess, sys, tempfile, threading, time

  def run(argv, *, cwd=None, env=None, check=True):
      return subprocess.run(argv, cwd=cwd, env=env, check=check, capture_output=True, text=True, timeout=30)

  def coherent(path, marker=None, *, wal=False):
      uri = path.as_uri() + ('?mode=ro' if wal else '?mode=ro&immutable=1')
      with sqlite3.connect(uri, uri=True, timeout=2) as db:
          assert db.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
          row = db.execute('SELECT a.value,b.value,c.epoch,c.marker FROM alpha a,beta b,control c').fetchone()
      assert row[0] == row[1] == row[2], ('mixed transaction', row)
      if marker is not None:
          assert row[3] == marker, ('stale snapshot', row)
      return row

  def initialize(path):
      db = sqlite3.connect(path, timeout=2)
      db.execute('PRAGMA journal_mode=WAL')
      db.execute('PRAGMA wal_autocheckpoint=0')
      db.executescript('CREATE TABLE alpha(value INTEGER); CREATE TABLE beta(value INTEGER); '
          'CREATE TABLE control(epoch INTEGER,marker TEXT); CREATE TABLE payload(data BLOB); '
          "INSERT INTO alpha VALUES(0); INSERT INTO beta VALUES(0); INSERT INTO control VALUES(0,'initial');")
      db.executemany('INSERT INTO payload VALUES(?)', [(b'x' * 4096,) for _ in range(200)])
      db.commit()
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
      return db

  def transaction(db, epoch, marker):
      with db:
          db.execute('UPDATE alpha SET value=?', (epoch,))
          db.execute('UPDATE beta SET value=?', (epoch,))
          db.execute('UPDATE control SET epoch=?,marker=?', (epoch, marker))

  def require_failure(script, marker):
      marker.unlink(missing_ok=True)
      result = run(['bash', '-c', script + '\nprintf downstream > ' + shlex.quote(str(marker))], check=False)
      assert result.returncode != 0, ('snapshot failure swallowed', result.stdout, result.stderr)
      assert not marker.exists(), 'Borg create boundary reached after failed snapshot'

  def must_detect(check, label):
      try:
          check()
      except AssertionError:
          return
      raise AssertionError('seeded wiring violation escaped: ' + label)

  with tempfile.TemporaryDirectory() as temp:
      root = pathlib.Path(temp)
      producer = root / "su"
      producer.write_text("#!${pkgs.bash}/bin/bash\nif [ -e " + str(root / "fail") + " ]; then exit 23; fi\nprintf 'valid SQL snapshot\\n'\n")
      producer.chmod(0o700)
      cases = []
      for fixture in sys.argv[1:-1]:
          spec = json.loads(pathlib.Path(fixture).read_text())
          assert 't3' in spec['snapshots'], 'T3 backup registration absent'
          cases.extend((spec, name) for name in sorted(spec['snapshots']))
      for i, (spec, snapshot_name) in enumerate(cases):
          dest = root / str(i)
          dest.mkdir()
          nested = dest / "service-split" / "recovery.json"
          nested.parent.mkdir()
          nested.write_text("keep")
          os.utime(nested, (1, 1))
          old = dest / "postgresql-old.sql.gz"
          old.write_text("expired")
          os.utime(old, (1, 1))
          script = spec['hook']
          if 'exec 9>' in script:
              locks = dest / 'borg-jobs'
              locks.mkdir()
              script = script.replace(spec['lockRoot'], str(locks))
          # Remove ONLY the exact declared custom suffix: Meals, CouchDB
          # and arr belong to their own owners, not this shared-hook test.
          custom = spec['customHook']
          if custom:
              assert script.endswith(custom), 'custom-hook composition changed'
              script = script[:-len(custom)]
          assert 'borg-sqlite-snapshot' in script, 'shared snapshot caller absent'
          config = spec['snapshots'][snapshot_name]
          state = dest / 'borg-sqlite'
          userdata = dest / 'userdata'
          userdata.mkdir()
          source = userdata / 'state.sqlite'
          # Substitute composition ports only; production helper and its
          # namespace/identity/permission/failure behavior remain intact.
          source_ports = {config['source']: str(source)}
          other_databases = []
          for name, entry in spec['snapshots'].items():
              if name != snapshot_name:
                  other = dest / ('other-' + name) / 'state.sqlite'
                  other.parent.mkdir()
                  other_databases.append(initialize(other))
                  source_ports[entry['source']] = str(other)
              # Replace an argument, never substrings such as --state-root.
              user_argument = r"(--user\s+)(?:'" + re.escape(entry['user']) + r"'|" + re.escape(entry['user']) + r")(?=\s|$)"
              script = re.sub(user_argument,
                  lambda match: match[1] + shlex.quote(pwd.getpwuid(os.getuid()).pw_name), script)
          script = script.replace(spec['stateRoot'], str(state))
          for original, replacement in source_ports.items():
              script = script.replace(original, replacement)
          script = script.replace('/var/lib/backups', str(dest))
          script = script.replace("/run/wrappers/bin/su", str(producer))
          db = initialize(source)
          run(["bash", "-c", script])
          output = next(dest.glob("postgresql-2*.sql.gz"))
          before = output.read_bytes()
          assert gzip.decompress(before) == b"valid SQL snapshot\n"
          assert not old.exists() and nested.read_text() == "keep"
          (root / "fail").touch()
          assert run(["bash", "-c", script], check=False).returncode != 0
          assert output.read_bytes() == before
          assert not list(dest.glob(".postgresql-*"))
          (root / "fail").unlink()
          ready = state / 'ready' / (snapshot_name + '.sqlite')
          coherent(ready, 'initial')
          assert ready.stat().st_uid == os.getuid()
          assert ready.stat().st_mode & 0o777 == 0o600

          # A main(epoch0)/WAL(epoch1) tuple can pass integrity_check yet
          # violate transaction invariants. This is a known-bad control,
          # not attribution of any particular production archive failure.
          raw = dest / 'raw.sqlite'
          shutil.copyfile(source, raw)
          transaction(db, 1, 'checkpointed')
          db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
          db.execute("UPDATE control SET marker='later-committed'")
          db.commit()
          shutil.copyfile(pathlib.Path(str(source) + '-wal'), pathlib.Path(str(raw) + '-wal'))
          with sqlite3.connect(raw.as_uri() + '?mode=ro', uri=True) as mixed:
              assert mixed.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
              assert mixed.execute('SELECT a.value,b.value,c.epoch FROM alpha a,beta b,control c').fetchone() == (0, 0, 1)
          must_detect(lambda: coherent(raw, wal=True), 'raw file-copy consistency')

          # Remove the actual caller. A still-valid old snapshot must not
          # satisfy the fresh committed marker required by this consumer.
          cli = spec['cli']
          omitted = script.replace(cli, 'true')
          assert omitted != script
          run(['bash', '-c', omitted])
          must_detect(lambda: coherent(ready, 'later-committed'), 'snapshot invocation removed')
          run(['bash', '-c', script])
          coherent(ready, 'later-committed')

          # Separate real writer runs while the actual rendered hook/CLI
          # execute. The fixture's atomic invariant must survive churn.
          stop, started = threading.Event(), threading.Event()
          commits, errors = [], []
          def writing():
              writer = None
              try:
                  writer = sqlite3.connect(source, timeout=2)
                  writer.execute('PRAGMA wal_autocheckpoint=0')
                  epoch = 2
                  deadline = time.monotonic() + 20
                  while not stop.is_set():
                      assert epoch < 10002 and time.monotonic() < deadline, 'owned writer exceeded budget'
                      transaction(writer, epoch, 'active-writer')
                      commits.append(time.monotonic())
                      started.set()
                      epoch += 1
                      # Remain active until the caller finishes, with a
                      # strict budget and low WAL churn on slow builders.
                      stop.wait(.005)
              except BaseException as error:
                  errors.append(repr(error))
                  started.set()
              finally:
                  if writer is not None:
                      writer.close()
          thread = threading.Thread(target=writing)
          thread.start()
          try:
              assert started.wait(5) and not errors
              begin = time.monotonic()
              run(['bash', '-c', script])
              end = time.monotonic()
              coherent(ready)
              assert any(begin < tick < end for tick in commits), 'writer did not overlap snapshot caller'
          finally:
              stop.set()
              thread.join(5)
          assert not thread.is_alive() and not errors, errors

          # Exercise standalone CLI, including required source and size
          # failures; each preserves the old published bytes and staging.
          argv = [cli, 'create', '--state-root', str(state), '--name', snapshot_name, '--source', str(source),
              '--user', pwd.getpwuid(os.getuid()).pw_name, '--max-bytes', str(config['maxBytes']),
              '--timeout-seconds', str(config['timeoutSeconds'])]
          run(argv)
          coherent(ready)
          lastgood = ready.read_bytes()
          slot = state / 'staging' / snapshot_name
          slot.mkdir(mode=0o700)
          held_file = slot / 'keep-existing-slot'
          held_file.write_text('another attempt owns this slot')
          assert run(argv, check=False).returncode != 0
          assert held_file.read_text() == 'another attempt owns this slot'
          assert ready.read_bytes() == lastgood
          held_file.unlink()
          slot.rmdir()
          alias = userdata / 'source-alias.sqlite'
          alias.symlink_to(source)
          invalid = userdata / 'invalid.sqlite'
          invalid.write_bytes(b'not a SQLite database' * 100)
          for broken in [argv[:argv.index('--source') + 1] + [str(userdata / 'missing.sqlite')] + argv[argv.index('--source') + 2:],
                         argv[:argv.index('--source') + 1] + [str(alias)] + argv[argv.index('--source') + 2:],
                         argv[:argv.index('--source') + 1] + [str(invalid)] + argv[argv.index('--source') + 2:],
                         argv[:argv.index('--max-bytes') + 1] + ['1'] + argv[argv.index('--max-bytes') + 2:]]:
              assert run(broken, check=False).returncode != 0
              assert ready.read_bytes() == lastgood
              assert not list((state / 'staging').glob('**/*.sqlite'))
          alias.unlink()
          invalid.unlink()
          # A last-good symlink cannot redirect publication or modify its
          # target. Restore only this fixture's exact saved regular file.
          saved = ready.with_name('saved-lastgood')
          ready.rename(saved)
          target = dest / 'symlink-target'
          target.write_text('keep target intact')
          ready.symlink_to(target)
          try:
              assert run(argv, check=False).returncode != 0
              assert ready.is_symlink() and target.read_text() == 'keep target intact'
              assert saved.read_bytes() == lastgood
          finally:
              ready.unlink()
              saved.rename(ready)
          # Rollback-journal EXCLUSIVE lock forces a genuine reader wait;
          # the real worker must fail within its configured small budget.
          locked = userdata / 'locked.sqlite'
          locker = initialize(locked)
          locker.execute('PRAGMA journal_mode=DELETE')
          locker.execute('BEGIN EXCLUSIVE')
          bounded = argv.copy()
          bounded[bounded.index('--source') + 1] = str(locked)
          bounded[bounded.index('--timeout-seconds') + 1] = '1'
          begin = time.monotonic()
          try:
              assert run(bounded, check=False).returncode != 0
              assert time.monotonic() - begin < 8, 'worker deadline did not bound lock wait'
              assert ready.read_bytes() == lastgood
              assert not list((state / 'staging').glob('**/*.sqlite'))
          finally:
              locker.rollback()
              locker.close()
              locked.unlink()
          # Real failed producer through rendered call site must stop
          # before the next archive step. A wrapper swallowing its error
          # is an independent wiring mutation, required to be detected.
          failed = script.replace(str(source), str(userdata / 'missing.sqlite'))
          downstream = dest / 'borg-create-started'
          require_failure(failed, downstream)
          assert ready.read_bytes() == lastgood
          swallow = dest / 'swallow-snapshot-error'
          swallow.write_text('#!${pkgs.bash}/bin/bash\n' + shlex.quote(cli) + ' "$@" || true\n')
          swallow.chmod(0o700)
          must_detect(lambda: require_failure(failed.replace(cli, str(swallow)), downstream), 'producer failure swallowed')
          assert ready.read_bytes() == lastgood

          # Local disposable Borg repository: actual evaluated excludes
          # and ready-snapshot coverage, plus synthetic userdata inputs
          # to stress raw-database exclusion and unrelated-file retention.
          (userdata / 'pairing-fixture').write_text('synthetic credential placeholder')
          (userdata / 'state.sqlite-journal').write_bytes(b'rollback-journal fixture')
          staging = state / 'staging' / 'not-an-archive-input'
          staging.write_text('partial')
          assert any(pathlib.PurePosixPath(spec['stateRoot'] + '/ready').is_relative_to(p) for p in spec['paths'])
          # T3 also owns non-database userdata; database-only journals
          # such as Workbench are covered by the published ready snapshot.
          if snapshot_name in ('t3', 't3-v2'):
              assert str(pathlib.PurePosixPath(config['source']).parent) in spec['paths']
          def remap(value):
              value = value.replace(spec['stateRoot'], str(state))
              for original, replacement in source_ports.items():
                  value = value.replace(original, replacement)
              return value
          excludes = [remap(value) for value in spec['exclude']]
          env = {k: v for k, v in os.environ.items() if not k.startswith('BORG_')}
          env.update(BORG_CACHE_DIR=str(dest / 'cache'), BORG_CONFIG_DIR=str(dest / 'config'),
              BORG_SECURITY_DIR=str(dest / 'security'), BORG_CHECK_I_KNOW_WHAT_I_AM_DOING='YES')
          repo = dest / 'repo'
          run(['borg', 'init', '--encryption=none', str(repo)], env=env)
          def archive(name, patterns):
              args = ['borg', 'create', '--compression', 'none']
              for pattern in patterns:
                  args += ['--exclude', pattern]
              run([*args, str(repo) + '::' + name, str(state), str(userdata)], env=env)
              extracted = dest / ('extract-' + name)
              extracted.mkdir()
              run(['borg', 'extract', str(repo) + '::' + name], cwd=extracted, env=env)
              return extracted
          def verify_archive(extracted):
              copied = extracted / str(state).lstrip('/')
              restored_user = extracted / str(userdata).lstrip('/')
              coherent(copied / 'ready' / (snapshot_name + '.sqlite'))
              assert (restored_user / 'pairing-fixture').read_text() == 'synthetic credential placeholder'
              assert not any((restored_user / ('state.sqlite' + suffix)).exists() for suffix in ("", '-wal', '-shm', '-journal')), 'raw SQLite entered archive'
              assert not (copied / 'staging' / 'not-an-archive-input').exists(), 'staging entered archive'
          verify_archive(archive('valid', excludes))
          if spec['immich']:
              # Use the evaluated media namespace and real Borg patterns.
              # Cache exclusion must retain originals, not just drop data.
              media = spec['immich']
              origin = next(p for p in spec['paths'] if pathlib.PurePosixPath(media['root']).is_relative_to(p))
              photos = dest / 'photos'
              def media_fixture(original, name):
                  path = photos / pathlib.PurePosixPath(original).relative_to(origin) / name
                  path.parent.mkdir(parents=True, exist_ok=True)
                  path.write_text('media fixture')
                  return path
              originals = [media_fixture(p, 'original.jpg') for p in media['originals']]
              originals += [media_fixture(media['root'] + '/upload', 'new.jpg'),
                  media_fixture(origin + '/external', 'original.jpg'),
                  media_fixture(origin + '/archive', 'original.jpg')]
              caches = [media_fixture(p, 'regenerated.cache') for p in media['regenerable']]
              media_patterns = [p.replace(origin, str(photos)) for p in spec['exclude']]
              def media_archive(name, patterns):
                  args = ['borg', 'create', '--compression', 'none']
                  for pattern in patterns:
                      args += ['--exclude', pattern]
                  target = str(repo) + '::' + name
                  run([*args, target, str(photos)], env=env)
                  return set(run(['borg', 'list', '--short', target], env=env).stdout.splitlines())
              def verify_media(paths):
                  assert all(str(p).lstrip('/') in paths for p in originals), 'original media absent'
                  assert all(str(p).lstrip('/') not in paths for p in caches), 'regenerable Immich cache entered archive'
              verify_media(media_archive('media-valid', media_patterns))
              without_caches = [p for p in media_patterns if not any(
                  cache.replace(origin, str(photos)) in p for cache in media['regenerable'])]
              must_detect(lambda: verify_media(media_archive('media-exclusions-removed', without_caches)),
                  'Immich cache exclusions removed')
          raw_patterns = [value for value in excludes if str(source) in value]
          assert len(raw_patterns) == 4, raw_patterns
          journal_pattern = 'pf:' + str(source) + '-journal'
          assert journal_pattern in excludes
          must_detect(lambda: verify_archive(archive('journal-exclusion-removed',
              [value for value in excludes if value != journal_pattern])), 'raw journal exclusion removed')
          must_detect(lambda: verify_archive(archive('raw-exclusion-removed', [value for value in excludes if value not in raw_patterns])), 'raw SQLite exclusions removed')
          db.close()
          for connection in other_databases:
              connection.close()
          print(json.dumps({'host': spec['host'], 'database': snapshot_name, 'state': 'passed',
              'snapshotSha256': hashlib.sha256(ready.read_bytes()).hexdigest(),
              'checks': ['postgresql-publication-retention-failure', 'rendered-hook-sqlite-publication',
                  'raw-wal-mixed-transaction-red', 'concurrent-writer-snapshot', 'standalone-cli',
                  'existing-slot-held', 'source-symlink-missing-invalid-size-held',
                  'lastgood-symlink-held', 'real-lock-deadline', 'lastgood-preserved',
                  'failed-hook-stops-downstream', 'local-borg-archive-extract',
                  'non-database-userdata-preserved', 'raw-and-staging-excluded'],
              'mutationsDetected': ['snapshot-caller-removed', 'producer-failure-swallowed',
                  'raw-sqlite-exclusions-removed', 'raw-journal-exclusion-removed']}), flush=True)
      fake = root / "borg"
      fake.write_text("#!${pkgs.bash}/bin/bash\nexit 42\n")
      fake.chmod(0o700)
      script, replacements = re.subn(r"/nix/store/[^\s]+/bin/borg\b", str(fake), pathlib.Path(sys.argv[-1]).read_text())
      assert replacements >= 1
      result = subprocess.run(["bash", "-c", script, "restore", "absent", str(root / "restore")])
      assert result.returncode == 42, result.returncode
  PY
  touch "$out"
'';
}
