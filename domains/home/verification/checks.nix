# Pure verification function; not a NixOS or Home Manager module.
{ inputs, lib, mailHost, mailOwner, pkgs, repoRoot, self, system }:
{

# The agent-harness app owns the one build recipe; consumers take it as
# `tracker.package`. Here it is built with the check packages and its contract
# tests on, with the pinned Python hub as the oracle.
tracker-rust-contracts = import (repoRoot + "/domains/home/apps/agent-harness/parts/tracker-package.nix") {
  inherit pkgs;
  harness = inputs.agent-harness;
  doCheck = true;
};

onlyoffice-runtime = let
  home = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
  package = lib.findFirst (p: (p.pname or "") == "onlyoffice-desktopeditors") null home.home.packages;
in assert package != null;
assert lib.all (p: !((p.pname or "") == "gtk+" && lib.versions.major (p.version or "0") == "2")) package.derivation.buildInputs;
pkgs.runCommand "onlyoffice-runtime" {} ''
  # Realizing the vendor derivation also runs strict autoPatchelf. A
  # remaining mandatory GTK2 dependency must fail there, never be ignored.
  test -x ${package}/bin/onlyoffice-desktopeditors
  test -x ${package.derivation}/share/desktopeditors/DesktopEditors
  touch "$out"
'';

hyprland-lua-config = let
  home = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
  hypr = home.wayland.windowManager.hyprland;
  candidate = pkgs.writeText "hyprland.lua" home.xdg.configFile."hypr/hyprland.lua".text;
  launcher = lib.findFirst (p: (p.name or "") == "waybar-launch") null home.home.packages;
  switcher = lib.findFirst (p: (p.name or "") == "hwc-workspace-switch") null
    self.nixosConfigurations.hwc-laptop.config.environment.systemPackages;
  bars = pkgs.writeText "waybar-fixture.json" (builtins.toJSON home.programs.waybar.settings);
  cursor = home.hwc.home.theme.cursor.hyprcursor.name;
  cursorAssets = home.home.file.".local/share/icons/${cursor}".source;
  preservesPopupPosition = rules: lib.all (rule:
    !(rule.match ? float) || !(rule ? center)) rules;
in assert preservesPopupPosition hypr.settings.window_rule;
assert !preservesPopupPosition [{ match.float = "1"; center = "1"; }];
assert lib.any (rule: (rule.match.title or "") == "^(Open).*" && rule ? center)
  hypr.settings.window_rule;
assert hypr.configType == "lua";
assert !(home.xdg.configFile ? "hypr/hyprland.conf");
pkgs.runCommand "hyprland-lua-config" { nativeBuildInputs = [ hypr.package pkgs.python3 pkgs.jq ]; } ''
  export HOME="$TMPDIR" XDG_RUNTIME_DIR="$TMPDIR"
  mkdir -p "$TMPDIR/hypr"
  Hyprland --verify-config -c ${candidate} > parser.log 2>&1
  cat parser.log
  test -f ${cursorAssets}/manifest.hl
  python3 - ${candidate} ${launcher}/bin/waybar-launch ${switcher}/bin/hwc-workspace-switch ${bars} <<'PYTEST'
  import json, os, pathlib, re, signal, subprocess, sys, time
  cfg = pathlib.Path(sys.argv[1]).read_text()
  def mouse_flags(text):
      blocks = re.findall(r'hl.bind\("SUPER \+ mouse:27[23]".*?\n}\)', text, re.S)
      return len(blocks) == 2 and all('["mouse"] = true' in b for b in blocks)
  assert mouse_flags(cfg), "Mouse bindings lost their mouse flag"
  assert not mouse_flags(cfg.replace('["mouse"] = true', '["mouse"] = false'))
  assert 'hl.env("HYPRCURSOR_THEME", "${cursor}")' in cfg
  root = pathlib.Path.cwd()/'desktop-fixture'
  root.mkdir(); (root/'bin').mkdir(); (root/'waybar').mkdir()
  (root/'waybar/config').write_text(pathlib.Path(sys.argv[4]).read_text())
  monitors = [dict(name='HWC-GAME', make="", focused=False),
              dict(name='eDP-1', make='BOE', focused=True),
              dict(name='DP-2', make='Ancor', focused=False)]
  log = root/'dispatch.log'
  hyprctl = root/'bin/hyprctl'
  hyprctl.write_text('#!${pkgs.python3}/bin/python3\nimport json,sys\n'
      + 'if sys.argv[1]=="monitors": print('+repr(json.dumps(monitors))+')\n'
      + 'else: open('+repr(str(log))+',"a").write(" ".join(sys.argv[1:])+"\\n")\n')
  hyprctl.chmod(0o755)
  bar = root/'bin/waybar'
  bar.write_text('#!${pkgs.python3}/bin/python3\nimport os,sys,signal,time,pathlib\n'
      + 'p=pathlib.Path(sys.argv[sys.argv.index("-c")+1])\n'
      + 'signal.signal(signal.SIGUSR2,lambda *_: print("RELOAD",flush=True))\n'
      + 'print("START",os.getpid(),flush=True)\nprint(p.read_text(),flush=True)\nwhile True: time.sleep(0.05)\n')
  bar.chmod(0o755)
  env = os.environ | dict(XDG_CONFIG_HOME=str(root), XDG_RUNTIME_DIR=str(root),
      PATH=str(root/'bin')+':'+os.environ['PATH'])
  launch = (root/'launch')
  launch.write_text(re.sub(r'export PATH=.*', 'export PATH='+env['PATH'], pathlib.Path(sys.argv[2]).read_text()))
  output = root/'output'
  with output.open('w') as out:
      proc = subprocess.Popen(['bash',str(launch)],env=env,stdout=out,stderr=out)
      try:
          deadline=time.monotonic()+5
          while time.monotonic()<deadline and 'DP-2' not in output.read_text(): time.sleep(0.05)
          assert 'DP-2' in output.read_text() and 'HWC-GAME' not in output.read_text(), output.read_text()
          proc.send_signal(signal.SIGUSR2)
          deadline=time.monotonic()+5
          while time.monotonic()<deadline and output.read_text().count('START ')<2: time.sleep(0.05)
          children = re.findall(r'START ([0-9]+)', output.read_text())
          assert proc.poll() is None and len(children)==2 and children[0]!=children[1], output.read_text()
          assert not pathlib.Path('/proc/'+children[0]).exists(), 'Old bar survived reload'
      finally:
          proc.terminate()
          proc.wait(timeout=5)
  assert not list(pathlib.Path(os.environ['TMPDIR']).glob('tmp.*')), "Launcher leaked temp config"
  switch = root/'switch'
  switch.write_text(re.sub(r'/nix/store/[^ /]+/bin/hyprctl',str(hyprctl),pathlib.Path(sys.argv[3]).read_text()))
  (root/'hwc-workspace-link').touch()
  subprocess.run(['bash',str(switch),'2'],env=env,check=True,timeout=5)
  dispatches=log.read_text()
  assert "monitor='DP-2'" in dispatches and 'HWC-GAME' not in dispatches, dispatches
  PYTEST
  printf 'exec-once = true\n' > legacy.conf
  if Hyprland --verify-config -c "$PWD/legacy.conf" > legacy.log 2>&1; then
    echo "Parser accepted the retired configuration format" >&2
    exit 1
  fi
  touch "$out"
'';

workbench-desktop-consumer = let
  home = self.homeConfigurations."eric@hwc-laptop".config;
  systemHome = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
  mailSystemHome = self.nixosConfigurations.${mailHost}.config.home-manager.users.eric;
  mailStandaloneHome = self.homeConfigurations."eric@${mailHost}".config;
  helper = mailSystemHome.programs.workbench.mailHelper;
  launch = mailSystemHome.hwc.mail.aerc.launchInfo;
  origin = home.hwc.home.apps.workbench.serverUrl;
  native = inputs.workbench.packages.${system}.desktop;
  # Inspect public rendered JSON as data; retain real tool contexts in
  # payload.tools and the production HM file, never execute parsed paths.
  desktopJson = cfg: builtins.fromJSON (builtins.unsafeDiscardStringContext
    cfg.xdg.configFile."workbench/desktop.json".text);
  # The real generic module wraps this harmless probe. Never execute a
  # source tool or a graphical program from a configuration check.
  probe = pkgs.writeShellScriptBin "workbench" ''
    exec ${pkgs.python3}/bin/python3 -c 'import json,os; print(json.dumps({k:v for k,v in os.environ.items() if k.startswith("WORKBENCH_HANDOFF_")}))'
  '';
  # HWC-EXCEPTION(Law 10): fixture-only declarations for sibling ports;
  # real HWC and application modules remain the producers under test.
  fixture = settings: systemConfig: inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit inputs; osConfig = systemConfig; workbenchMailTarget = null; };
    modules = [ (repoRoot + "/domains/home/apps/workbench/index.nix")
      ({ lib, ... }: {
        options.hwc.home = {
          apps.zellij.package = lib.mkOption { type = lib.types.package; default = probe; };
          apps.codex.package = lib.mkOption { type = lib.types.nullOr lib.types.package; default = null; };
          theme = lib.mkOption { type = lib.types.attrs; default = {}; };
          keymap = lib.mkOption { type = lib.types.attrs; default = {}; };
          core.shell = lib.mkOption { type = lib.types.attrs; default = {}; };
        };
        config = {
          home = { username = "fixture"; homeDirectory = "/tmp/workbench-consumer"; stateVersion = "26.05"; };
          hwc.home.apps.workbench = settings;
          programs.workbench = {
            package = probe;
            desktop.package = probe;
            agentCommand = lib.mkForce "";
            extraRuntimePackages = lib.mkForce [];
          };
        };
      })
    ];
  };
  valid = cfg: let attempt = builtins.tryEval (lib.all (entry: entry.assertion) cfg.assertions);
    in attempt.success && attempt.value;
  independent = (fixture {} {}).config;
  missing = (fixture { desktop.enable = true; } {}).config;
  centralMissing = (fixture { enable = true; handoff.enable = true; } {}).config;
  centralInvalid = (fixture { enable = true; handoff.enable = true;
    serverUrl = "http://fixture.invalid"; } {}).config;
  explicit = (fixture { serverUrl = "https://fixture.invalid"; desktop.enable = true; } {}).config;
  summaryOnly = (fixture { serverUrl = "https://fixture.invalid"; desktop = {
    enable = true; summary.enable = true;
  }; } {}).config;
  linksOnly = (fixture { serverUrl = "https://fixture.invalid"; desktop = {
    enable = true; externalLinks.enable = true;
  }; } {}).config;
  missingMailTarget = (fixture { serverUrl = "https://fixture.invalid";
    desktop = { enable = true; mail.enable = true; };
  } {}).config;
  missingMailOwner = (fixture { mailHelper.enable = true; } {}).config;
  fixtureMailTarget = { host = "mail.fixture.invalid";
    remoteHelper = "/opt/workbench/bin/workbench";
    remoteProfile = "/opt/workbench/mail.json";
  };
  explicitMail = (fixture { serverUrl = "https://fixture.invalid";
    desktop = { enable = true; mail = {
      enable = true;
      target = fixtureMailTarget;
    }; };
  } {}).config;
  mailTargetOnly = (fixture { serverUrl = "https://fixture.invalid";
    desktop = { enable = true; mail.target = fixtureMailTarget; };
  } {}).config;
  off = (fixture { serverUrl = "https://fixture.invalid"; desktop = {
    summary.enable = true; externalLinks.enable = true;
    mail = { enable = true; target = fixtureMailTarget; };
  }; } {}).config;
  central = (fixture { enable = true; serverUrl = origin; handoff.enable = true; } {}).config;
  centralOff = (fixture { enable = true; serverUrl = origin; } {}).config;
  wrapped = cfg: builtins.head (lib.filter (pkg: (pkg.name or "") == "workbench-wrapped") cfg.home.packages);
  fromRoutes = routes: domain: (fixture {} { hwc.networking.shared = {
    effectiveRoutes = routes; vhostDomain = domain;
  }; }).config.hwc.home.apps.workbench.serverUrl;
  route = { name = "workbench"; mode = "vhost"; owner = "work"; };
  checkOrigin = cfg: cfg.programs.workbench.desktop.origin == cfg.hwc.home.apps.workbench.serverUrl
    && cfg.programs.workbench.handoff.serviceUrl == cfg.hwc.home.apps.workbench.serverUrl;
  mailTarget = cfg: cfg.programs.workbench.desktop.mail;
  checkMailTarget = cfg: let target = mailTarget cfg; in target != null
    && target.host == self.nixosConfigurations.${mailHost}.config.hwc.networking.hosts.fqdn.${mailOwner}
    && target.remoteHelper == helper.executable && target.remoteProfile == helper.profilePath
    && builtins.getContext target.remoteHelper == {} && builtins.getContext target.remoteProfile == {}
    && builtins.getContext target.terminal != {} && builtins.getContext target.ssh != {};
  payload = pkgs.writeText "workbench-desktop-consumers.json" (builtins.toJSON {
    inherit origin;
    standalone = desktopJson home;
    nixos = desktopJson systemHome;
    expectedMail = {
      host = self.nixosConfigurations.${mailHost}.config.hwc.networking.hosts.fqdn.${mailOwner};
      remoteHelper = helper.executable;
      remoteProfile = helper.profilePath;
      terminal = lib.getExe pkgs.kitty;
      ssh = lib.getExe pkgs.openssh;
    };
    inherit launch;
    localCache = home.xdg.cacheHome;
    remoteCache = mailSystemHome.xdg.cacheHome;
    tools = { terminal = lib.getExe pkgs.kitty; editor = lib.getExe pkgs.neovim-unwrapped;
      opener = lib.getExe' pkgs.xdg-utils "xdg-open"; };
  });
in
assert lib.assertMsg (origin != "" && checkOrigin home && checkOrigin systemHome
  && desktopJson home == desktopJson systemHome)
  "workbench desktop: both HM lanes must consume the one resolved HTTPS origin";
assert lib.assertMsg (fromRoutes [route] "fixture.invalid" == "https://workbench.fixture.invalid"
  && fromRoutes [] "fixture.invalid" == ""
  && fromRoutes [route route] "fixture.invalid" == ""
  && fromRoutes [(route // { mode = "subpath"; })] "fixture.invalid" == ""
  && fromRoutes [route] "" == "")
  "workbench desktop: URL must derive only from one named vhost and its domain";
assert lib.assertMsg (independent.hwc.home.apps.workbench.serverUrl == "" && valid independent
  && !valid missing && !valid centralMissing && !valid centralInvalid
  && valid explicit && !explicit.programs.workbench.enable)
  "workbench desktop: independent HM must stay guarded and require explicit origin only when enabled";
assert lib.assertMsg ((desktopJson explicit).editor == null && (desktopJson explicit).externalOpener == null
  && (desktopJson summaryOnly).editor != null && (desktopJson summaryOnly).externalOpener == null
  && (desktopJson linksOnly).editor == null && (desktopJson linksOnly).externalOpener != null
  && !(off.xdg.configFile ? "workbench/desktop.json"))
  "workbench desktop: each native capability requires its own enable and desktop enable";
assert lib.assertMsg (!valid missingMailTarget && !valid missingMailOwner
  && valid explicitMail && (desktopJson explicitMail).mail != null
  && (desktopJson explicitMail).editor == null && (desktopJson explicitMail).externalOpener == null
  && valid mailTargetOnly && !((desktopJson mailTargetOnly) ? mail)
  && !((desktopJson explicit) ? mail))
  "workbench Mail: independent clients need a fixed target and helpers need an aerc owner";
assert lib.assertMsg (checkMailTarget home && checkMailTarget systemHome
  && helper.enable && mailStandaloneHome.programs.workbench.mailHelper.enable
  && helper.executable == mailStandaloneHome.programs.workbench.mailHelper.executable
  && helper.profilePath == mailStandaloneHome.programs.workbench.mailHelper.profilePath
  && helper.profilePath == toString mailSystemHome.xdg.configFile."workbench/mail-helper.json".source
  && helper.profilePath == toString mailStandaloneHome.xdg.configFile."workbench/mail-helper.json".source)
  "workbench Mail: both HM lanes must retain the matching helper/profile and consume the fleet target";
assert lib.assertMsg (launch == mailStandaloneHome.hwc.mail.aerc.launchInfo
  && launch.aercConf == toString mailSystemHome.home.file.".config/aerc/aerc.conf".source
  && launch.bindsConf == toString mailSystemHome.home.file.".config/aerc/binds.conf".source
  # Regex needles cannot carry store context; this comparison inspects
  # text only. The launch/profile values above retain their dependencies.
  && lib.hasInfix (builtins.unsafeDiscardStringContext launch.accountsConf)
    mailSystemHome.home.activation.aercAccounts.data
  && lib.any (package: "${package}/bin/aerc" == launch.aerc) mailSystemHome.home.packages)
  "workbench Mail: launch facts must match the actual aerc configuration and installed client";
assert lib.assertMsg (!checkOrigin (home // { programs = home.programs // {
    workbench = home.programs.workbench // { handoff.serviceUrl = "https://wrong.invalid"; };
  }; }) && !checkOrigin (home // { programs = home.programs // {
    workbench = home.programs.workbench // { desktop = home.programs.workbench.desktop // { origin = "https://wrong.invalid"; }; };
  }; }))
  "workbench desktop: mismatched native/central wiring must fail the origin contract";
assert lib.assertMsg (lib.elem native home.home.packages && lib.elem native systemHome.home.packages
  && lib.all (host: !self.homeConfigurations."eric@hwc-${host}".config.hwc.home.apps.workbench.desktop.enable)
    [ "home" "work" "xps" "kids" "firestick" ])
  "workbench desktop: install only on the qualified laptop, in both HM lanes";
pkgs.runCommand "workbench-desktop-consumer" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  WORKBENCH_HANDOFF_SERVICE_URL=ambient-invalid ${wrapped central}/bin/workbench > central.json
  env -u WORKBENCH_HANDOFF_SERVICE_URL ${wrapped centralOff}/bin/workbench > disabled.json
  python3 - ${payload} ${native} ${helper.profilePath} <<'PY'
  import configparser, json, pathlib, sys
  value = json.loads(pathlib.Path(sys.argv[1]).read_text())
  for cfg in (value['standalone'], value['nixos']):
      assert cfg == dict(schemaVersion=1, origin=value['origin'],
          editor=dict(terminal=value['tools']['terminal'], editor=value['tools']['editor']),
          externalOpener=value['tools']['opener'], mail=cfg['mail']), cfg
      target = cfg['mail']
      assert set(target) == set(value['expectedMail']) | {'runtimeRoot'}, target
      assert all(target[key] == expected for key, expected in value['expectedMail'].items()), target
      assert pathlib.Path(target['runtimeRoot']).parent == pathlib.Path(value['localCache']), target
      assert len((target['runtimeRoot'] + '/' + '0'*32).encode()) < 108, target
  profile = json.loads(pathlib.Path(sys.argv[3]).read_text())
  assert set(profile) == set(value['launch']) | {'schemaVersion', 'protocol', 'runtime'}, profile
  assert profile['schemaVersion'] == 1 and isinstance(profile['protocol'], str) and profile['protocol']
  assert all(profile[key] == expected for key, expected in value['launch'].items()), profile
  assert pathlib.Path(profile['runtime']).parent == pathlib.Path(value['remoteCache']), profile
  assert len((profile['runtime'] + '/' + '0'*32 + '/aerc.sock').encode()) < 108, profile
  account = configparser.ConfigParser(interpolation=None)
  account.read(profile['accountsConf'])
  assert profile['account'] in account.sections(), 'Declared account is absent from the real generated file'
  assert json.loads(pathlib.Path('central.json').read_text()) == {'WORKBENCH_HANDOFF_SERVICE_URL': value['origin']}
  assert json.loads(pathlib.Path('disabled.json').read_text()) == {}
  package = pathlib.Path(sys.argv[2])
  entry = (package/'share/applications/com.iheartwoodcraft.workbench.desktop').read_text()
  assert 'Exec=workbench-desktop\n' in entry and 'Icon=workbench\n' in entry
  assert 'StartupWMClass=Workbench-desktop\n' in entry
  assert (package/'bin/workbench-desktop').is_file()
  assert (package/'share/icons/hicolor/192x192/apps/workbench.png').read_bytes()[:8] == b'\x89PNG\r\n\x1a\n'
  PY
  touch "$out"
'';

bitwarden-portal = let
  client = lib.findFirst (p: (p.meta.mainProgram or "") == "bitwarden")
    (throw "bitwarden-portal: laptop no longer installs Bitwarden")
    self.homeConfigurations."eric@hwc-laptop".config.home.packages;
in pkgs.runCommand "bitwarden-portal" {
  nativeBuildInputs = [ pkgs.python3 pkgs.ripgrep ];
} ''
  # The actual HM package must invoke the tested relay launcher.
  rg --text --fixed-strings '${client.portalLauncher}' '${client}/bin/bitwarden'
  BITWARDEN_PORTAL_TEST_LAUNCHER='${client.portalLauncher}' \
    python3 ${(repoRoot + "/domains/home/apps/bitwarden/test_portal_launcher.py")}
  touch "$out"
'';

t3-update-gate = let
  root = "/tmp/t3-update-gate";
  fixture = (self.nixosConfigurations.hwc-work.extendModules {
    modules = [ ({ lib, ... }: {
      home-manager.users.eric = {
        home.homeDirectory = lib.mkForce "${root}/home";
        hwc.home.apps.t3code.repo = lib.mkForce "${root}/primary";
        hwc.home.apps.agent-harness = {
          nixosRepo = lib.mkForce "${root}/nixos";
          workspaceRoot = lib.mkForce "${root}/workspace";
        };
      };
    }) ];
  }).config.home-manager.users.eric;
  updater = builtins.head (builtins.filter (p: (p.name or "") == "t3-update") fixture.home.packages);
  python = pkgs.python3.withPackages (p: [ p.jsonschema ]);
in pkgs.runCommand "t3-update-gate" { nativeBuildInputs = [ python pkgs.git ]; } ''
  python3 -B ${(repoRoot + "/domains/home/apps/t3code/test_update_gate.py")} \
    --updater ${updater}/bin/t3-update --root ${root}
  python3 -B ${inputs.agent-harness}/lifecycle/tracker/t3_release.test.py
  touch "$out"
'';

t3-switch-policy = let
  targets = [
    { host = "hwc-home"; unit = "t3-serve"; }
    { host = "hwc-work"; unit = "t3-serve"; }
    { host = "hwc-laptop"; unit = "t3code"; }
  ];
  units = map (target: let
    home = self.nixosConfigurations.${target.host}.config.home-manager.users.eric;
    standalone = self.homeConfigurations."eric@${target.host}".config;
    updater = builtins.head (builtins.filter (p: (p.name or "") == "t3-update") home.home.packages);
    desktopLauncher = builtins.head (builtins.filter (p: (p.name or "") == "t3code") home.home.packages);
  in {
    inherit (target) host unit;
    policy = home.systemd.user.services.${target.unit}.Unit.X-SwitchMethod or null;
    file = home.home.file."${home.xdg.configHome}/systemd/user/${target.unit}.service".source;
    # Schema inspection only; these paths are never executed by this fixture.
    runtime = builtins.unsafeDiscardStringContext updater.releaseRuntime.drvAttrs.text;
  } // lib.optionalAttrs (target.unit == "t3code") {
    launcherFile = lib.getExe desktopLauncher;
    profileLauncher = "${home.home.profileDirectory}/bin/t3code";
    desktopEntry = home.xdg.dataFile."applications/t3code.desktop".source;
    defaultHandler = home.xdg.mimeApps.defaultApplications."x-scheme-handler/t3code" or [];
    standaloneEntry = standalone.xdg.dataFile."applications/t3code.desktop".source;
    standaloneLauncher = "${standalone.home.profileDirectory}/bin/t3code";
    standaloneDefault = standalone.xdg.mimeApps.defaultApplications."x-scheme-handler/t3code" or [];
  }) targets;
  fixtures = pkgs.writeText "t3-switch-policy.json" (builtins.toJSON units);
in
assert lib.assertMsg (lib.all (unit: unit.policy == "keep-old") units)
  "t3-switch-policy: an implicit home switch must preserve each running T3 shape";
pkgs.runCommand "t3-switch-policy" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.jsonschema ])) ];
} ''
  python3 -B - ${fixtures} ${inputs.agent-harness}/lifecycle/tracker/t3_release.py <<'PY'
  import configparser, importlib.util, json, pathlib, shlex, sys, tempfile
  spec = importlib.util.spec_from_file_location('t3_release', sys.argv[2])
  release = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(release)
  def keeps_active(text):
      unit = configparser.RawConfigParser(strict=False)
      unit.optionxform = str
      unit.read_string(text)
      return unit.get('Unit', 'X-SwitchMethod', fallback=None) == 'keep-old'
  for item in json.loads(pathlib.Path(sys.argv[1]).read_text()):
      with tempfile.NamedTemporaryFile(mode='w+', suffix='.json') as runtime_file:
          runtime_file.write(item['runtime']); runtime_file.flush()
          runtime = release.load_runtime(pathlib.Path(runtime_file.name))
      assert runtime['serviceUnit'] == item['unit'] + '.service', item['host']
      assert runtime['headless'] == (item['unit'] == 't3-serve'), item['host']
      text = pathlib.Path(item['file']).read_text()
      assert keeps_active(text), item
      if item['unit'] == 't3code':
          def read_entry(path):
              config = configparser.ConfigParser(interpolation=None)
              config.read(path)
              return dict(config['Desktop Entry'])
          def bound_handler(entry, default, launcher):
              return (shlex.split(entry['exec']) == [launcher, '%U']
                  and 'x-scheme-handler/t3code' in entry.get("mimetype", "").split(";")
                  and default == ['t3code.desktop'])
          entry = read_entry(item['desktopEntry'])
          assert bound_handler(entry, item['defaultHandler'], item['profileLauncher']), 'OS handler bypasses T3 launcher or drops URI'
          assert bound_handler(read_entry(item['standaloneEntry']), item['standaloneDefault'], item['standaloneLauncher']), 'HM lanes disagree on T3 URL routing'
          assert not bound_handler(dict(entry, exec=item['profileLauncher']), item['defaultHandler'], item['profileLauncher']), 'missing URI seed escaped'
          assert not bound_handler(entry, ['bare-electron.desktop'], item['profileLauncher']), 'wrong OS default seed escaped'
          def managed_shutdown(script):
              unit = configparser.RawConfigParser(strict=False)
              unit.optionxform = str
              unit.read_string(script)
              return (not unit.has_option('Service', 'ExecStartPre')
                  and not unit.has_option('Service', 'ExecStopPost')
                  and unit.get('Service', 'KillMode', fallback=None) == 'control-group'
                  and unit.get('Service', 'TimeoutStopSec', fallback=None) == '30')
          assert managed_shutdown(text), 'laptop retained unsafe process sweeps or lost bounded shutdown'
          assert not managed_shutdown(text.replace('[Service]', '[Service]\nExecStopPost=/bin/false', 1)), 'cleanup-hook control escaped'
          missing_deadline = '\n'.join(line for line in text.splitlines()
              if not line.startswith('TimeoutStopSec='))
          assert not managed_shutdown(missing_deadline), 'missing shutdown deadline control escaped'
          launcher = pathlib.Path(item['launcherFile']).read_text()
          def bound_launcher(script):
              return any(shlex.split(line.strip()) ==
                  ['export', 'T3CODE_DESKTOP_LAUNCHER=' + item['profileLauncher']]
                  for line in script.splitlines()
                  if line.strip().startswith('export T3CODE_DESKTOP_LAUNCHER='))
          assert bound_launcher(launcher), 'T3 URI registration lost the trusted launcher'
          removed = '\n'.join(line for line in launcher.splitlines()
              if not line.strip().startswith('export T3CODE_DESKTOP_LAUNCHER='))
          assert not bound_launcher(removed), 'missing-launcher control escaped'
      missing = '\n'.join(line for line in text.splitlines() if not line.startswith('X-SwitchMethod='))
      assert missing != text and not keeps_active(missing), 'missing-policy control escaped'
      print(item['host'] + '/' + item['unit'] + ': runtime schema, rendered keep-old and removal control pass')
  PY
  touch "$out"
'';

user-runtime-paths = let
  laptopSystem = self.nixosConfigurations.hwc-laptop;
  laptop = laptopSystem.config.home-manager.users.eric;
  paths = laptopSystem.config.hwc.paths;
  standalone = self.homeConfigurations."eric@hwc-laptop".config;
  stable = self.nixosConfigurations.hwc-home.config.home-manager.users.eric;
  stableStandalone = self.homeConfigurations."eric@hwc-home".config;
  overridden = (laptopSystem.extendModules {
    modules = [{
      hwc.paths.user.apps = "/tmp/hwc-test-apps";
      hwc.paths.user.go.workspace = "/tmp/hwc-test-go";
      hwc.paths.user.go.moduleCache = "/tmp/hwc-test-modules";
    }];
  }).config.home-manager.users.eric;
  homes = [ laptop standalone stable stableStandalone ];
  modelPaths = laptop.hwc.home.apps.whisper-cpp.modelPaths;
  cleanup = laptop.systemd.user.services.go-cache-clean.Service;
  noHomeModels = home: !(lib.any (lib.hasPrefix "models/") (lib.attrNames home.home.file));
  projectMapping = home:
    home.xdg.userDirs.extraConfig.PROJECTS == home.home.sessionVariables.PROJECTS
    && !(lib.hasInfix "${home.home.homeDirectory}/Projects"
      home.home.activation.createXdgUserDirectories.data);
in
assert lib.assertMsg (lib.all projectMapping homes)
  "user-runtime-paths: XDG Projects must use the app root in both HM API lanes";
assert lib.assertMsg (laptop.home.sessionVariables.PROJECTS == toString paths.user.apps
  && laptop.home.sessionVariables.GOPATH == toString paths.user.go.workspace
  && laptop.home.sessionVariables.GOMODCACHE == toString paths.user.go.moduleCache
  && laptop.home.sessionVariables.GOCACHE == toString paths.user.go.buildCache
  && laptop.home.sessionVariables.GOBIN == toString paths.user.go.bin)
  "user-runtime-paths: integrated environment must consume hwc.paths";
assert lib.assertMsg (overridden.home.sessionVariables.PROJECTS == "/tmp/hwc-test-apps"
  && overridden.home.sessionVariables.GOPATH == "/tmp/hwc-test-go"
  && overridden.home.sessionVariables.GOMODCACHE == "/tmp/hwc-test-modules")
  "user-runtime-paths: changing the central paths must change their consumers";
assert lib.assertMsg (lib.all (home:
  home.home.sessionVariables.GOPATH != "${home.home.homeDirectory}/go"
  && home.home.sessionVariables.GOMODCACHE != "${home.home.homeDirectory}/go/pkg/mod") homes)
  "user-runtime-paths: Go must not recreate ~/go";
assert lib.assertMsg (noHomeModels laptop && noHomeModels standalone
  && laptop.hwc.home.apps.hwc-dictation.model == toString modelPaths."base.en"
  && standalone.hwc.home.apps.hwc-dictation.model == toString standalone.hwc.home.apps.whisper-cpp.modelPaths."base.en"
  && lib.all (model: lib.elem (toString model) (map toString laptop.home.extraDependencies))
    (lib.attrValues modelPaths))
  "user-runtime-paths: dictation must use store files and every model must retain a GC root";
assert lib.assertMsg (laptop.systemd.user.timers.go-cache-clean.Timer.OnCalendar == "monthly"
  && lib.elem "GOMODCACHE=${paths.user.go.moduleCache}" cleanup.Environment)
  "user-runtime-paths: cache retention must use the declared cache";
pkgs.runCommand "user-runtime-paths" { } ''
  # The actual Go defaults file reaches callers without a fresh shell.
  export GOENV=${pkgs.writeText "go-env-test" laptop.xdg.configFile."go/env".text}
  test "$(${pkgs.go}/bin/go env GOPATH)" = '${paths.user.go.workspace}'
  test "$(${pkgs.go}/bin/go env GOMODCACHE)" = '${paths.user.go.moduleCache}'

  # Exercise the actual cleaner against isolated derived data. Source
  # and installed binaries must survive; the build cache must regenerate.
  runtime_test="$TMPDIR/go-runtime"
  mkdir -p "$runtime_test/workspace/src" "$runtime_test/bin" "$runtime_test/modules/example"
  echo keep > "$runtime_test/workspace/src/keep"
  echo keep > "$runtime_test/bin/keep"
  echo replaceable > "$runtime_test/modules/example/data"
  export GOPATH="$runtime_test/workspace" GOMODCACHE="$runtime_test/modules"
  export GOCACHE="$runtime_test/build" GOBIN="$runtime_test/bin" GOTOOLCHAIN=local
  echo 'package main; func main() {}' > "$runtime_test/main.go"
  ${pkgs.go}/bin/go build -o "$runtime_test/app" "$runtime_test/main.go"
  ${lib.head cleanup.ExecStart}
  test ! -e "$GOMODCACHE/example/data"
  test -f "$GOPATH/src/keep"
  test -f "$GOBIN/keep"
  ${pkgs.go}/bin/go build -o "$runtime_test/app" "$runtime_test/main.go"
  "$runtime_test/app"
  touch "$out"
'';

# Exercise the XPS dependency guard before the native database preStart.
# Its own sandbox permits only the ZFS device; Jellyfin stays restricted. The fixture replaces OS probes and drops their string
# contexts so this check does not build ZFS/FFmpeg merely to mock them.
xps-household-desktop = let
  c = self.nixosConfigurations.hwc-xps.config;
  dad = c.users.users.dad;
  session = c.hwc.system.core.session.loginManager;
in
assert session.backend == "plasma" && session.autoLoginUser == "dad";
assert c.services.displayManager.sddm.enable && !c.services.greetd.enable;
assert c.services.desktopManager.plasma6.enable && c.services.displayManager.autoLogin.user == "dad";
assert c.systemd.services."getty@tty2".enable;
assert dad.uid != c.users.users.eric.uid && dad.group == "dad" && dad.homeMode == "0700";
assert lib.all (group: !(lib.elem group dad.extraGroups)) [ "wheel" "secrets" "users" "disk" "storage" "docker" "podman" ];
assert dad.hashedPasswordFile == c.hwc.secrets.api.dad-login-password-hash;
assert !(c.environment.sessionVariables ? HOME);
assert c.home-manager.users.dad.home.homeDirectory == dad.home;
assert c.hardware.graphics.enable32Bit && c.programs.steam.enable;
assert lib.elem self.nixosConfigurations.hwc-xps.pkgs.proton-ge-bin c.programs.steam.extraCompatPackages;
assert c.services.openssh.enable && c.services.tailscale.enable && c.users.users.eric.linger;
assert c.hwc.media.jellyfin.enable && !c.hwc.media.jellyfin.gpu.enable;
assert c.services.logind.settings.Login.HandleLidSwitch == "ignore";
assert c.home-manager.users.dad.hwc.home.apps.plasma.enable;
assert lib.elem "${dad.home}/Documents" c.hwc.data.borg.sources;
assert !c.programs.steam.remotePlay.openFirewall;
pkgs.runCommand "xps-household-desktop" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  node - ${pkgs.writeText "dad-polkit.js" c.security.polkit.extraConfig} <<'JS'
  const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
  const rules = [];
  vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), {
    polkit: { addRule: f => rules.push(f), Result: { YES:'yes', NO:'no' } }
  });
  const decide = (id, local=true, active=true) => {
    for (const rule of rules) {
      const answer = rule({id, lookup:()=>null}, {user:'dad', local, active, isInGroup:()=>false});
      if (answer !== undefined) return answer;
    }
  };
  const wifi = ['enable-disable-wifi','wifi.scan','network-control','settings.modify.own'];
  for (const suffix of wifi) {
    const id = 'org.freedesktop.NetworkManager.'+suffix;
    assert.equal(decide(id), 'yes', id);
    assert.equal(decide(id, false, true), 'no', id+' remote');
    assert.equal(decide(id, true, false), 'no', id+' inactive');
  }
  for (const id of [
    'org.freedesktop.NetworkManager.settings.modify.system',
    'org.freedesktop.NetworkManager.enable-disable-network',
    'org.freedesktop.NetworkManager.settings.modify.hostname',
    'org.freedesktop.login1.power-off', 'org.freedesktop.login1.suspend',
    'org.freedesktop.udisks2.filesystem-mount-system',
    'org.freedesktop.systemd1.manage-units'
  ]) assert.equal(decide(id), 'no', id);
  console.log('Actual Dad policy: local Wi-Fi permitted; remote/system/power/disk authority denied.');
  JS
  touch $out
'';

home-untangle = let
  laptop = self.nixosConfigurations.hwc-laptop;
  home = laptop.config.home-manager.users.eric;
  raw = package: builtins.unsafeDiscardStringContext package.drvAttrs.text;
  browser = name: import (repoRoot + "/domains/home/apps/${name}/parts/launcher.nix") { inherit lib pkgs; };
  chromium = (browser "chromium").packages;
  workspacePlan = { slots = [ 2 4 ]; externalOffset = 20; externalSlots = [ 22 24 ]; };
  hardware = import (repoRoot + "/domains/home/apps/hyprland/parts/hardware.nix") {
    inherit lib pkgs workspacePlan;
  };
  behavior = import (repoRoot + "/domains/home/apps/hyprland/parts/behavior.nix") {
    inherit lib pkgs workspacePlan; config = home;
  };
  scripts = import (repoRoot + "/domains/home/apps/hyprland/parts/scripts.nix") {
    inherit lib pkgs workspacePlan;
  };
  bars = import (repoRoot + "/domains/home/apps/waybar/parts/behavior.nix") {
    inherit lib pkgs workspacePlan; config = home; osConfig = laptop.config;
  };
  fixture = {
    init = builtins.unsafeDiscardStringContext home.programs.zsh.initContent;
    browsers = {
      firefox = raw (builtins.head (browser "firefox").packages);
      chromium = raw (builtins.head chromium);
      workbench = raw (builtins.elemAt chromium 1);
    };
    workspace = {
      mapping = hardware.workspace;
      bindings = behavior.keybinds;
      inherit bars;
      script = raw (lib.findFirst (package: package.name == "hwc-workspace-switch") null scripts);
    };
  };
  overridden = (laptop.extendModules { modules = [{ hwc.paths.nixos = "/tmp/hwc-nixos-fixture"; }]; })
    .config.home-manager.users.eric;
  work = self.nixosConfigurations.hwc-work;
  mismatched = (work.extendModules { modules = [{
    hwc.system.apps.agent-harness.userMcp.brainUrl = lib.mkForce "https://wrong.invalid/mcp";
  }]; }).config;
  validSystem = config: lib.all (entry: entry.assertion) config.assertions;
  neomutt = accounts: (inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ (repoRoot + "/domains/home/apps/neomutt/index.nix") ({ lib, ... }: {
      options.hwc.mail.accounts = lib.mkOption { type = lib.types.attrs; default = {}; };
      config = {
        home = { username = "fixture"; homeDirectory = "/tmp/neomutt-fixture"; stateVersion = "24.05"; };
        hwc.home.apps.neomutt.enable = true;
        hwc.mail.accounts = accounts;
      };
    }) ];
  }).config;
  first = { name = "First"; maildirName = "first"; };
  second = { name = "Second"; maildirName = "second"; primary = true; };
  empty = neomutt {};
  fallback = neomutt { a = first; b = second // { primary = false; }; };
  primary = neomutt { a = first; b = second; };
in
assert lib.assertMsg (lib.all (config:
  config.hwc.system.apps.agent-harness.userMcp.brainUrl == "https://hwc-work.ocelot-wahoo.ts.net:23443/mcp")
  (map (system: system.config) (builtins.attrValues self.nixosConfigurations)))
  "home composition: all hosts must receive the shared Brain MCP URL";
assert lib.assertMsg (validSystem work.config && !validSystem mismatched)
  "home composition: a wrong local Brain MCP URL must fail its consumer assertion";
assert lib.assertMsg (overridden.home.sessionVariables.HWC_NIXOS_DIR == "/tmp/hwc-nixos-fixture"
  && lib.all (name: overridden.home.sessionVariables.${name} == "/tmp/hwc-nixos-fixture/workspace")
    [ "HWC_WORKSPACE_ROOT" "WORKSPACE" "SCRIPTS" ])
  "home paths: overriding the central checkout must reach every shell runtime path";
assert lib.assertMsg (!(empty.home.file ? ".config/neomutt/neomuttrc") && empty.warnings != []
  && lib.hasInfix ''set spoolfile = "=first/INBOX"'' fallback.home.file.".config/neomutt/neomuttrc".text
  && lib.hasInfix ''set spoolfile = "=second/INBOX"'' primary.home.file.".config/neomutt/neomuttrc".text
  && lib.hasInfix ''Go: Second INBOX'' primary.home.file.".config/neomutt/behavior.muttrc".text)
  "neomutt: no-account, fallback and explicit primary must reach the generated files";
pkgs.runCommand "home-untangle" {
  nativeBuildInputs = with pkgs; [ python3 zsh bash jq coreutils ripgrep ];
  passthru = { inherit fixture; };
} ''
  python3 -B ${(repoRoot + "/domains/home/verification/test_untangle.py")} \
    ${pkgs.writeText "home-untangle.json" (builtins.toJSON fixture)}
  touch "$out"
'';

# The stale-lock decision against real GnuPG: a lock from an earlier boot whose
# PID was reused must go; a lock a live keyboxd holds must stay even when its
# mtime looks pre-boot (clock jump); a dead-PID lock goes only once 15 minutes old.
gpg-stale-lock = let
  home = self.nixosConfigurations.hwc-laptop.config.home-manager.users.eric;
  helper = lib.getExe home.hwc.home.apps.gpg.staleLock.package;
  unit = home.systemd.user.services.gpg-stale-lock;
in assert lib.assertMsg (unit.Unit.Before == [ "basic.target" ] && !unit.Unit.DefaultDependencies
  && unit.Install.WantedBy == [ "basic.target" ] && lib.hasSuffix "--apply" (lib.head (lib.toList unit.Service.ExecStart)))
  "gpg-stale-lock: the oneshot must run --apply before basic.target";
pkgs.runCommand "gpg-stale-lock" { nativeBuildInputs = [ pkgs.gnupg pkgs.coreutils ]; } ''
  set -euo pipefail
  export HOME="$TMPDIR"
  boot=$(awk '/^btime/ { print $2 }' /proc/stat)
  lockline() { printf '%10d\nfixture-host\n' "$1"; }

  # (b) live keyboxd holds public-keys.d/pubring.db.lock; backdate it past boot.
  GNUPGHOME=$(mktemp -d "$TMPDIR/g.XXXX"); export GNUPGHOME; chmod 700 "$GNUPGHOME"
  echo use-keyboxd > "$GNUPGHOME/common.conf"
  gpg --batch --list-keys >/dev/null 2>&1 || true
  live="$GNUPGHOME/public-keys.d/pubring.db.lock"
  test -f "$live"
  touch -d "@$((boot - 60))" "$live"

  # (a) pre-boot lock whose PID now belongs to an unrelated live process.
  sleep 600 & reused=$!
  lockline "$reused" > "$GNUPGHOME/trustdb.gpg.lock"; touch "$GNUPGHOME/trustdb.gpg"
  touch -d "@$((boot - 60))" "$GNUPGHOME/trustdb.gpg.lock"

  # (c) dead PID: old lock goes, fresh lock stays.
  lockline 999999 > "$GNUPGHOME/old.kbx.lock"; touch -d "@$(( $(date +%s) - 1000 ))" "$GNUPGHOME/old.kbx.lock"
  lockline 999999 > "$GNUPGHOME/fresh.kbx.lock"

  set +e; ${helper} --check > check.out; checkRc=$?; set -e
  cat check.out
  test "$checkRc" = 1
  grep -q "stale $GNUPGHOME/trustdb.gpg.lock reason=pre-boot" check.out
  grep -q "stale $GNUPGHOME/old.kbx.lock reason=dead-pid" check.out
  if grep -q -e pubring.db.lock -e fresh.kbx.lock check.out; then exit 1; fi
  test -f "$GNUPGHOME/trustdb.gpg.lock"   # --check never removes

  ${helper} --apply > apply.out; cat apply.out
  test ! -e "$GNUPGHOME/trustdb.gpg.lock"
  test ! -e "$GNUPGHOME/old.kbx.lock"
  test -f "$GNUPGHOME/fresh.kbx.lock"
  test -f "$live"
  gpg --batch --list-keys >/dev/null   # the live keyboxd still serves

  rm "$GNUPGHOME/fresh.kbx.lock"
  ${helper} --check > clean.out
  gpgconf --kill all; kill "$reused"
  touch "$out"
'';

# agent-harness control.sh against fixture repos: doctor drift cases, and
# publish going through the release runner only. A publish that runs
# nixos-rebuild, sudo or home-manager itself, builds a toplevel, moves main
# without the runner, or activates a remote host unasked fails here.
agent-harness-control = pkgs.runCommand "agent-harness-control" {
  nativeBuildInputs = with pkgs; [ bash git jq ripgrep coreutils findutils gawk diffutils hostname gnutar ];
} ''
  set -euo pipefail
  export HOME="$TMPDIR" LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive
  cp ${repoRoot + "/domains/home/apps/agent-harness/control.sh"} control.sh
  cp ${repoRoot + "/domains/home/apps/agent-harness/control.test.sh"} control.test.sh
  # The sandbox has no /usr/bin/env for the test's stub commands.
  substituteInPlace control.test.sh --replace-fail '#!/usr/bin/env bash' '#!${pkgs.bash}/bin/bash'
  bash control.test.sh
  touch "$out"
'';

}
