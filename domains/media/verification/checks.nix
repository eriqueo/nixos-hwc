# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, repoRoot, self }:
{

books-runtime-security = let
  c = self.nixosConfigurations.hwc-home.config;
  container = c.virtualisation.oci-containers.containers.books;
  assets = c.system.build.calibreRuntimeAssets;
  withoutDesktop = (self.nixosConfigurations.hwc-home.extendModules {
    modules = [ { hwc.media.calibre.enable = lib.mkForce false; } ];
  }).config;
  invalidBinding = (self.nixosConfigurations.hwc-home.extendModules {
    modules = [ { system.build.booksRuntimeBinding = lib.mkForce
      (pkgs.writeText "books-invalid-binding.json" (builtins.toJSON {
        schemaVersion = 0; image = "invalid"; environment = {};
      })); } ];
  }).config;
  binding = pkgs.writeText "books-runtime-binding.json" (builtins.toJSON {
    selected = container.image;
    configured = c.hwc.media.books.image;
    preStart = c.systemd.services.podman-books.preStart;
    environment = container.environment;
    pull = container.pull;
    declared = builtins.fromJSON c.system.build.booksRuntimeBinding.text;
  });
in
assert withoutDesktop.system.build.calibreRuntimeAssets.text == assets.text;
assert builtins.getContext assets.text == {};
assert !(builtins.tryEval (builtins.deepSeq invalidBinding.virtualisation.oci-containers.containers.books.environment true)).success;
pkgs.runCommand "books-runtime-security" { nativeBuildInputs = [ pkgs.python3 pkgs.dpkg ]; } ''
  python3 - ${binding} ${c.system.build.booksRuntimeImageContext} ${c.system.build.booksRuntimeInputGuard} ${assets} ${c.system.build.calibreRuntimeImageContext} <<'PYBOOKS'
  import copy, hashlib, json, pathlib, runpy, stat, sys, tempfile
  binding = json.loads(pathlib.Path(sys.argv[1]).read_text())
  context, guard, asset_file, calibre_context = map(pathlib.Path, sys.argv[2:])
  spec = json.loads((context / 'inputs/manifest.json').read_text())
  provider = json.loads(asset_file.read_text())
  recipe = (context / 'Dockerfile').read_text()
  assert provider == spec['calibre'] and provider['schemaVersion'] == 1
  assert binding['selected'] == binding['configured'] == 'localhost/books-runtime:schema' + str(spec['app']['databaseVersion']) + '-python' + spec['pythonVersion'] + '-' + hashlib.sha256(recipe.encode()).hexdigest()[:12]
  assert binding['pull'] == 'never' and binding['selected'] in binding['preStart'] and 'image exists' in binding['preStart'] and 'exit 1' in binding['preStart']
  assert binding['declared']['schemaVersion'] == 1 and binding['declared']['image'] == binding['selected']
  assert binding['declared']['environment'] == spec['environment']
  canonical = json.dumps(spec, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
  input_marker = '# Qualified inputs ' + hashlib.sha256((canonical + guard.read_text()).encode()).hexdigest()
  hook_modes = 'RUN chmod 0555 ' + provider['http']['rootPath'] + ' ' + provider['http']['rootPath'] + '/http'
  version_copy = 'COPY --from=app-source /defaults/version.txt /defaults/version.txt'
  version_guard = "RUN echo '" + spec['app']['versionMarkerSha256'] + "  /defaults/version.txt' | sha256sum -c -"
  assert all(binding['environment'][name] == value for name, value in spec['environment'].items())
  assert binding['environment']['DOCKER_MODS'] == ""
  assert binding['environment'][provider['http']['selectionVariable']] == provider['http']['rootPath']
  def wiring(text):
      assert input_marker in text
      assert 'FROM ' + spec['sourceImage'] + ' AS app-source' in text
      assert 'FROM ' + provider['image'] + ' AS calibre-source' in text
      assert 'FROM ' + spec['baseImage'] + '\n' in text
      assert 'COPY --from=app-source /app/lazylibrarian/ /tmp/hwc-books-app/' in text
      assert version_copy in text and version_guard in text
      assert 'COPY --from=calibre-source ' + provider['rootPath'] + '/ ' + provider['rootPath'] + '/' in text
      assert 'COPY --from=calibre-source ' + provider['http']['rootPath'] + '/ ' + provider['http']['rootPath'] + '/' in text
      assert 'RUN python3 -B /tmp/hwc-books/guard.py ' + spec['commands']['verify'] + ' /tmp/hwc-books/manifest.json /tmp/hwc-books-app ' in text
      assert hook_modes in text and text.index(hook_modes) < text.index('RUN python3 -B /tmp/hwc-books/guard.py ' + spec['commands']['verify'])
      assert text.index(version_copy) < text.index(version_guard) < text.index('RUN python3 -B /tmp/hwc-books/guard.py ' + spec['commands']['verify'])
      assert 'RUN python3 -B /tmp/hwc-books/guard.py ' + spec['commands']['apply'] + ' /tmp/hwc-books/manifest.json /app/lazylibrarian' in text
      assert 'rm -rf /app/lazylibrarian && mv /tmp/hwc-books-app /app/lazylibrarian' in text
      assert 'ln -s ' + provider['rootPath'] + ' /app/calibre' in text
      assert 'RUN dpkg --unpack ' in text and 'dpkg --configure --pending' in text and 'dpkg --audit' in text
      assert 'sourcelist=/tmp/hwc-books-empty.list' in text and 'sourceparts=/tmp/hwc-books-empty-sources check' in text
      assert provider['rootPath'] + '/calibre_postinstall' in text and 'calibredb --version' in text and 'ebook-convert --version' in text
      assert spec['framing']['modules']['httpClient']['sourceSha256'] in text
      assert spec['framing']['modules']['urllib3']['patchedSha256'] in text
      assert 'linuxserver/mods' not in text and 'apt-get update' not in text
      assert 'ENTRYPOINT' not in text and 'CMD [' not in text and 'EXPOSE' not in text
  wiring(recipe)
  for token in [input_marker, hook_modes, version_copy, version_guard, 'COPY --from=app-source /app/lazylibrarian/ /tmp/hwc-books-app/',
                'COPY --from=calibre-source ' + provider['http']['rootPath'] + '/ ' + provider['http']['rootPath'] + '/',
                '/guard.py ' + spec['commands']['verify'] + ' ',
                '/guard.py ' + spec['commands']['apply'] + ' ',
                'rm -rf /app/lazylibrarian && mv /tmp/hwc-books-app /app/lazylibrarian',
                'dpkg --configure --pending',
                spec['framing']['modules']['urllib3']['patchedSha256']]:
      assert token in recipe
      try: wiring(recipe.replace(token, 'omitted-integration'))
      except AssertionError: pass
      else: raise AssertionError('omitted Books runtime integration passed')
  assert (context / 'inputs/guard.py').read_bytes() == guard.read_bytes()
  api = runpy.run_path(str(guard))
  sha = lambda value: hashlib.sha256(value).hexdigest()
  def tree(root):
      result = {}
      for path in sorted(root.rglob('*')):
          if path.is_file() and '__pycache__' not in path.parts:
              raw = path.read_bytes()
              result[str(path.relative_to(root))] = {'sha256': sha(raw), 'bytes': len(raw), 'mode': path.stat().st_mode & 0o777}
      return result
  tree_hash = lambda files: sha(json.dumps(files, sort_keys=True, separators=(',', ':')).encode())
  with tempfile.TemporaryDirectory() as directory:
      root = pathlib.Path(directory)
      app = root / 'app'; (app / 'lazylibrarian').mkdir(parents=True)
      cache = app / spec['app']['requestOptions']['path']
      original = ('def fetch(url, payload, headers):\n'
          '    a = requests.get(url, params=payload, headers=headers)\n'
          '    b = requests.get(url, params=payload, headers=headers)\n'
          '    return requests.get(url, params=payload, headers=headers)\n').encode()
      cache.write_bytes(original)
      db_module = app / 'lazylibrarian/dbupgrade.py'
      db_module.write_text('db_current_version = ' + str(spec['app']['databaseVersion']) + '\n')
      fixture = copy.deepcopy(spec)
      files = tree(app)
      fixture['app']['fileCount'] = len(files)
      fixture['app']['sourceDistributionSha256'] = tree_hash(files)
      backport = fixture['app']['requestOptions']
      backport['sourceSha256'] = sha(original)
      expected = original.decode().replace(backport['old'], backport['new']).encode()
      backport['patchedSha256'] = sha(expected)
      updated = copy.deepcopy(files)
      updated[backport['path']].update(sha256=sha(expected), bytes=len(expected))
      fixture['app']['patchedDistributionSha256'] = tree_hash(updated)
      for name, entry in fixture['framing']['modules'].items():
          path = root / name / ('http/client.py' if name == 'httpClient' else 'urllib3/response.py')
          path.parent.mkdir(parents=True); path.write_bytes(b'owned_parser_fixture = True\n')
          entry['path'] = str(path); entry['sourceSha256'] = sha(path.read_bytes())
      calibre, hook = root / 'calibre', root / 'hook'
      bundle = calibre / pathlib.Path(provider['http']['frozenBundle']).relative_to(provider['rootPath'])
      bundle.parent.mkdir(parents=True); bundle.write_bytes(b'owned-frozen-archive-fixture')
      fixture['calibre']['http']['frozenBundleSha256'] = sha(bundle.read_bytes())
      (hook / 'http').mkdir(parents=True)
      (hook / 'http/client.py').write_bytes(b'owned_http_fixture = True\n')
      (hook / 'site.py').write_bytes(b'owned_site_fixture = True\n')
      fixture['calibre']['http']['patchedSha256'] = sha((hook / 'http/client.py').read_bytes())
      fixture['calibre']['http']['bootstrapSha256'] = sha((hook / 'site.py').read_bytes())
      (hook / 'http-framing.json').write_text(json.dumps(fixture['calibre']['http']))
      for path in [hook / 'http/client.py', hook / 'site.py', hook / 'http-framing.json']: path.chmod(0o444)
      for entry in fixture['calibre']['stdlib']['modules'].values():
          (hook / entry['file']).write_bytes((calibre_context / 'stdlib/lib' / entry['file']).read_bytes())
          (hook / entry['file']).chmod(0o444)
      (hook / 'stdlib.json').write_text(json.dumps(fixture['calibre']['stdlib']))
      (hook / 'stdlib.json').chmod(0o444)
      (hook / 'http').chmod(0o555)
      hook.chmod(0o555)
      ssl_value = fixture['calibre']['nativeSsl']['spec']
      ssl_input = root / 'ssl-input'
      import shutil
      shutil.copytree(calibre_context / 'native-ssl', ssl_input)
      module = calibre / pathlib.Path(ssl_value['native']['original']['path']).relative_to(ssl_value['rootPath'])
      module.write_bytes(b'owned-original-ssl-fixture'); module.chmod(0o755)
      ssl_value['native']['original'].update(sha256=sha(module.read_bytes()),bytes=module.stat().st_size)
      cert = calibre / pathlib.Path(ssl_value['privateCa']['path']).relative_to(ssl_value['rootPath'])
      cert.parent.mkdir(parents=True); cert.write_bytes(b'owned-private-ca-fixture')
      ssl_value['privateCa']['sha256']=sha(cert.read_bytes())
      ssl_manifest=json.loads((ssl_input/'manifest.json').read_text());ssl_manifest['descriptor']=ssl_value['native']
      (ssl_input/'manifest.json').chmod(0o644)
      (ssl_input/'manifest.json').write_text(json.dumps(ssl_manifest))
      ssl_api={'__name__':'test_calibre_ssl'}
      exec(compile((ssl_input/'guard.py').read_bytes(),'<actual-ssl-installer>','exec',optimize=0),ssl_api)
      ssl_api['install'](ssl_value,ssl_input,calibre,ssl_input/'guard.py')
      native = context / 'inputs/native'
      def verify(value):
          api['verify'](value, app, native, calibre, hook, fixture['pythonVersion'], fixture['pythonPackages'], api['metadata'])
      try:
          verify(fixture)
          for name, entry in fixture['calibre']['stdlib']['modules'].items():
              target = hook / entry['file']; saved = target.read_bytes()
              target.chmod(0o644); target.write_bytes(b'corrupt-installed-stdlib')
              try: verify(fixture)
              except AssertionError: pass
              else: raise AssertionError('Books accepted corrupt stdlib:' + name)
              target.write_bytes(saved); target.chmod(0o444)
          verify(fixture)
          # Corrupt the actual shared DLL: removing the Books call to the
          # canonical installed guard must reopen this exact fixture.
          preserved=module.read_bytes();module.write_bytes(b'corrupt-installed-ssl')
          try: verify(fixture)
          except AssertionError as error: assert str(error)=='CALIBRE_SSL_INSTALLED_HASH'
          else: raise AssertionError('Books accepted changed shared SSL module')
          omission="namespace['installed'](native_ssl['spec'], calibre)"
          guard_source=guard.read_text();assert guard_source.count(omission)==1
          omitted_api={'__name__':'test_omitted_ssl'}
          exec(compile(guard_source.replace(omission,'pass # omitted shared SSL verification'),'<omitted-books-ssl>','exec',optimize=0),omitted_api)
          omitted_api['verify'](fixture,app,native,calibre,hook,fixture['pythonVersion'],fixture['pythonPackages'],api['metadata'])
          module.write_bytes(preserved);verify(fixture)
          # Reproduce the actual image COPY destination's mode before the
          # recipe restores it. The unmodified guard must reject that root.
          hook.chmod(0o755)
          try: verify(fixture)
          except AssertionError as error: assert str(error) == 'BOOKS_CALIBRE_ROOT_MODE'
          else: raise AssertionError('writable copied hook root passed')
          assert cache.read_bytes() == original
          hook.chmod(0o555)
          verify(fixture)
          for kind in ['version', 'package', 'parser', 'app', 'database', 'native', 'missing-native', 'duplicate-native', 'native-metadata', 'archive', 'bootstrap', 'provider-version']:
              bad = copy.deepcopy(fixture)
              if kind == 'version': bad['pythonVersion'] = '0.0.0'
              elif kind == 'package': bad['pythonPackages']['requests'] = 'wrong'
              elif kind == 'parser': bad['framing']['modules']['urllib3']['sourceSha256'] = '0' * 64
              elif kind == 'app': bad['app']['sourceDistributionSha256'] = '0' * 64
              elif kind == 'database': bad['app']['databaseVersion'] += 1
              elif kind == 'native': bad['nativePackages'][-1]['sha256'] = '0' * 64
              elif kind == 'missing-native': bad['nativePackages'].pop()
              elif kind == 'duplicate-native': bad['nativePackages'].append(bad['nativePackages'][0])
              elif kind == 'native-metadata': bad['nativePackages'][0]['version'] = 'wrong'
              elif kind == 'archive': bad['calibre']['http']['frozenBundleSha256'] = '0' * 64
              elif kind == 'bootstrap': bad['calibre']['http']['bootstrapSha256'] = '0' * 64
              else: bad['calibre']['schemaVersion'] = 0
              try: verify(bad)
              except AssertionError: pass
              else: raise AssertionError('invalid Books input passed: ' + kind)
              assert cache.read_bytes() == original and db_module.read_text().endswith(str(fixture['app']['databaseVersion']) + '\n')
          for kind in ['source-tree', 'source', 'hunk', 'count', 'result', 'result-tree', 'path']:
              bad = copy.deepcopy(fixture)
              if kind == 'source-tree': bad['app']['sourceDistributionSha256'] = '0' * 64
              elif kind == 'result-tree': bad['app']['patchedDistributionSha256'] = '0' * 64
              else:
                  key = {'source':'sourceSha256', 'hunk':'old', 'count':'count', 'result':'patchedSha256', 'path':'path'}[kind]
                  bad['app']['requestOptions'][key] = 2 if kind == 'count' else '../escape.py' if kind == 'path' else 'missing' if kind == 'hunk' else '0' * 64
              try: api['apply_request_options'](bad, app)
              except AssertionError: pass
              else: raise AssertionError('invalid Books app adapter passed: ' + kind)
              assert cache.read_bytes() == original, 'app guard wrote before validation: ' + kind
          api['apply_request_options'](fixture, app)
          assert cache.read_bytes() == expected and tree_hash(tree(app)) == fixture['app']['patchedDistributionSha256']
      finally:
          hook.chmod(0o755)
          (hook / 'http').chmod(0o755)
  print('Books production context/wiring, actual native input hashes/metadata, source/frozen guards and request-adapter pre-write negatives pass; installed runtime still needs qualification')
  PYBOOKS
  touch "$out"
'';



soularr-runtime-security = let
  c = self.nixosConfigurations.hwc-home.config;
  container = c.virtualisation.oci-containers.containers.soularr;
  fixture = pkgs.writeText "soularr-runtime-binding.json" (builtins.toJSON {
    selected = container.image;
    configured = c.hwc.media.soularr.image;
    preStart = c.systemd.services.podman-soularr.preStart;
    ports = container.ports;
  });
in pkgs.runCommand "soularr-runtime-security" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${c.system.build.soularrRuntimeImageContext} ${c.system.build.soularrRuntimeInputGuard} <<'PY'
  import copy, hashlib, json, pathlib, runpy, tempfile
  from unittest.mock import patch
  import sys
  binding = json.loads(pathlib.Path(sys.argv[1]).read_text())
  context, guard = map(pathlib.Path, sys.argv[2:])
  spec = json.loads((context / 'inputs/manifest.json').read_text())
  recipe = (context / 'Dockerfile').read_text()
  assert binding['selected'] == binding['configured'] and binding['selected'].startswith('localhost/soularr-runtime:')
  assert binding['ports'] == [] and binding['selected'] in binding['preStart']
  assert 'image exists' in binding['preStart'] and 'exit 1' in binding['preStart']
  def wiring(text):
      assert 'FROM ' + spec['sourceImage'] + ' AS app-source' in text
      assert 'FROM ' + spec['baseImage'] + '\n' in text
      assert 'COPY --from=app-source /app/soularr.py /app/run.sh /app/' in text
      assert 'RUN python3 -B /tmp/hwc-soularr/guard.py /tmp/hwc-soularr/manifest.json' in text
      assert '--no-index --no-deps --no-compile' in text and 'pip check' in text
      assert 'uninstall --yes pip setuptools wheel' in text
      assert 'ENTRYPOINT ["tini", "-g", "--"]' in text and 'CMD ["/app/run.sh"]' in text
      assert 'WORKDIR /app' in text and 'soularr.py --help && ps aux' in text
      assert 'IN_DOCKER=' + spec['environment']['IN_DOCKER'] in text
      assert 'PYTHONUNBUFFERED=' + spec['environment']['PYTHONUNBUFFERED'] in text
      assert 'WEBUI' not in text and 'EXPOSE' not in text
      assert spec['framing']['modules']['httpClient']['sourceSha256'] in text
      assert spec['framing']['modules']['urllib3']['patchedSha256'] in text
  wiring(recipe)
  for old in ['COPY --from=app-source /app/soularr.py /app/run.sh /app/',
              'RUN python3 -B /tmp/hwc-soularr/guard.py /tmp/hwc-soularr/manifest.json',
              '--no-index --no-deps --no-compile', 'ENTRYPOINT ["tini", "-g", "--"]',
              'IN_DOCKER=' + spec['environment']['IN_DOCKER'],
              spec['framing']['modules']['urllib3']['patchedSha256']]:
      assert old in recipe
      try: wiring(recipe.replace(old, 'omitted-integration'))
      except AssertionError: pass
      else: raise AssertionError('omitted runtime integration passed')
  assert (context / 'inputs/guard.py').read_bytes() == guard.read_bytes()
  api = runpy.run_path(str(guard))
  with tempfile.TemporaryDirectory() as directory:
      app = pathlib.Path(directory)
      fixture = copy.deepcopy(spec)
      for name in fixture['appFiles']:
          raw = ('owned fixture ' + name).encode()
          (app / name).write_bytes(raw)
          fixture['appFiles'][name] = hashlib.sha256(raw).hexdigest()
      versions = {x['name']: x['version'] for x in spec['preservedPackages']}
      with patch('importlib.metadata.version', side_effect=versions.__getitem__):
          api['verify'](fixture, app, context / 'inputs', spec['pythonVersion'], spec['environment'])
          for kind in ['schema', 'version', 'app', 'missing', 'input', 'package', 'environment']:
              bad = copy.deepcopy(fixture)
              version = spec['pythonVersion']
              environment = dict(spec['environment'])
              if kind == 'schema': bad['schemaVersion'] = 0
              if kind == 'version': version = '3.11.0'
              if kind == 'app': bad['appFiles']['soularr.py'] = '0' * 64
              if kind == 'missing': bad['wheels'][0]['filename'] = 'missing.whl'
              if kind == 'input': bad['debs'][-1]['sha256'] = '0' * 64
              if kind == 'package': bad['preservedPackages'][-1]['version'] = 'wrong'
              if kind == 'environment': environment.pop('IN_DOCKER')
              try: api['verify'](bad, app, context / 'inputs', version, environment)
              except (AssertionError, FileNotFoundError): pass
              else: raise AssertionError('invalid runtime input passed: ' + kind)
      assert all((app / name).read_bytes() == ('owned fixture ' + name).encode() for name in fixture['appFiles'])
  print('Soularr emitted runtime binding, source guards and omitted-integration negatives pass')
  PY
  touch "$out"
'';

soularr-config-security = let
  c = self.nixosConfigurations.hwc-home.config;
  service = c.systemd.services.soularr-config;
  containerService = c.systemd.services.podman-soularr;
  updater = c.system.build.soularrConfigUpdater;
  privatePaths = map (name: "${c.hwc.paths.apps.root}/${name}") [
    "books" "lidarr" "radarr" "sonarr" "prowlarr" "readarr" "soularr"
  ] ++ [ "${c.hwc.paths.apps.root}/soularr/data" ];
  fixture = pkgs.writeText "soularr-config-security.json" (builtins.toJSON {
    command = service.serviceConfig.ExecStart;
    readiness = map toString (lib.toList containerService.serviceConfig.ExecStartPre);
    keyFile = c.age.secrets.lidarr-api-key.path;
    inherit privatePaths;
    privateRules = lib.filter (rule:
      builtins.any (path: lib.hasInfix " ${path} " rule) privatePaths) c.systemd.tmpfiles.rules;
  });
in
assert service.serviceConfig.User == "eric" && service.serviceConfig.Group == "users";
assert service.serviceConfig.SupplementaryGroups == [ "secrets" ];
assert service.serviceConfig.UMask == "0077" && service.serviceConfig.TimeoutStartSec == "30s";
assert lib.elem c.age.secrets.lidarr-api-key.file service.restartTriggers;
assert lib.elem c.age.secrets.slskd-api-key.file service.restartTriggers;
assert lib.elem "soularr-config.service" containerService.after;
assert lib.elem "soularr-config.service" containerService.requires;
assert lib.elem service.serviceConfig.ExecStart containerService.restartTriggers;
assert containerService.serviceConfig.TimeoutStartSec == "30s";
assert c.virtualisation.oci-containers.containers.soularr.image == c.hwc.media.soularr.image;
pkgs.runCommand "soularr-config-security" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${updater} ${pkgs.bash}/bin/bash <<'PY'
  import configparser, grp, http.server, json, os, pathlib, re, runpy, shlex, subprocess, sys, tempfile
  from unittest.mock import patch
  fixture = json.loads(pathlib.Path(sys.argv[1]).read_text())
  updater, bash = sys.argv[2:]
  def private_directories(rules):
      parsed = [shlex.split(rule) for rule in rules]
      for path in fixture['privatePaths']:
          entries = [fields for fields in parsed if len(fields) >= 5 and fields[1] == path]
          assert len(entries) == 1 and entries[0][0] == 'd', 'one producer must own each private directory'
          assert entries[0][2:5] == ['0750', '1000', '100'], 'private parent must preserve the app writer identity'
  private_directories(fixture['privateRules'])
  for invalid in [fixture['privateRules'][1:],
                  fixture['privateRules'] + fixture['privateRules'][:1],
                  [rule.replace(' 0750 ', ' 0755 ') for rule in fixture['privateRules']]]:
      try: private_directories(invalid)
      except AssertionError: pass
      else: raise AssertionError('missing, duplicated or public directory integration passed')
  def wiring(command):
      assert updater in command.split(), 'production must invoke the tested updater'
  wiring(fixture['command'])
  try:
      wiring(fixture['command'].replace(updater, '/omitted-integration'))
  except AssertionError:
      pass
  else:
      raise AssertionError('omitted updater integration passed')
  api = runpy.run_path(updater)
  with tempfile.TemporaryDirectory() as directory:
      root = pathlib.Path(directory)
      config = root / 'config.ini'
      lidarr, slskd = root / 'lidarr-key', root / 'slskd-key'
      lidarr.write_text('private-dummy-lidarr\n'); slskd.write_text('private-dummy-slskd\n')
      spec = {'path': str(config), 'group': grp.getgrgid(os.getgid()).gr_name,
              'services': {'Lidarr': {'url': 'http://lidarr:8686', 'keyFile': str(lidarr)},
                           'Slskd': {'url': 'http://gluetun:5030', 'keyFile': str(slskd)}}}
      specpath = root / 'inputs.json'; specpath.write_text(json.dumps(spec))
      original = ('; saved comment\n[Lidarr]\nhost_url : http://old\napi_key = old\n'
                  'download_dir = /saved/music\n\n[Slskd]\napi_key = old\n'
                  '\n[General]\ninterval = 901\n\n[SavedChoice]\ncustom_option = preserve-this\n')
      def invoke():
          return subprocess.run([sys.executable, updater, str(specpath)], capture_output=True, timeout=10)
      config.write_text(original); config.chmod(0o644)
      result = invoke(); assert result.returncode == 0, result.stderr
      output = config.read_text(); parser = configparser.RawConfigParser(); parser.read_string(output)
      assert '; saved comment\n' in output and 'host_url : http://lidarr:8686' in output
      assert parser['General']['interval'] == '901' and parser['SavedChoice']['custom_option'] == 'preserve-this'
      assert parser['Lidarr']['download_dir'] == '/saved/music'
      assert parser['Slskd']['download_dir'] == '/downloads/music'
      assert parser['Slskd']['api_key'] == 'private-dummy-slskd'
      assert config.stat().st_mode & 0o777 == 0o440
      inode = config.stat().st_ino
      assert invoke().returncode == 0 and config.read_text() == output and config.stat().st_ino == inode
      # Missing/invalid SECOND key, invalid INI, oversized file and symlink all
      # fail through the real CLI before changing the original or leaking input.
      for bad in ['missing', 'newline', 'ini', 'size', 'link', 'multiline']:
          if config.exists(): config.chmod(0o600)
          config.write_text(original)
          slskd.write_text('private-dummy-slskd\n')
          if bad == 'missing': slskd.unlink()
          if bad == 'newline': slskd.write_text('sensitive-value\nInjected: value\n')
          if bad == 'ini': config.write_text('[Bad]\nsensitive-value\n')
          if bad == 'size': config.write_text('x' * (1024 * 1024 + 1))
          if bad == 'multiline': config.write_text(original.replace('api_key = old', 'api_key = old\n  sensitive-value', 1))
          target = None
          if bad == 'link':
              target = root / 'untouched'; target.write_text(original)
              config.unlink(); config.symlink_to(target)
          before, metadata = config.read_bytes(), config.lstat()
          result = invoke()
          assert result.returncode != 0 and b'sensitive-value' not in result.stderr
          assert config.read_bytes() == before and config.lstat().st_ino == metadata.st_ino
          assert not list(root.glob('.config-*'))
          if config.is_symlink(): config.unlink()
      # Concurrent edit is preserved and own temporary file is removed.
      config.write_text(original); slskd.write_text('private-dummy-slskd\n')
      real_fsync = os.fsync
      def concurrent_edit(fd):
          real_fsync(fd); config.write_text(original + '; concurrent user edit\n')
      with patch('os.fsync', side_effect=concurrent_edit):
          try: api['update'](spec)
          except api['ConfigError'] as error: assert str(error) == 'SOULARR_CONFIG_CHANGED'
          else: raise AssertionError('concurrent edit overwritten')
      assert config.read_text().endswith('; concurrent user edit\n') and not list(root.glob('.config-*'))
      config.unlink(); assert invoke().returncode == 0
      parser.read_string(config.read_text()); assert parser['General']['interval'] == '300'
      assert config.stat().st_mode & 0o777 == 0o440

      readiness_scripts = [pathlib.Path(path).read_text() for path in fixture['readiness']]
      readiness_scripts = [script for script in readiness_scripts if '--header @<(' in script]
      assert len(readiness_scripts) == 1, 'the composed container must select exactly one guarded readiness script'
      ready = readiness_scripts[0]
      assert '--max-time 2' in ready and 'attempt <= 6' in ready
      assert '--header @<(' in ready and 'RANDOM % 500' in ready
      # Hold an actual HTTP GET while inspecting only that bash's descendants.
      observations = []
      key = lidarr.read_text().strip()
      class Handler(http.server.BaseHTTPRequestHandler):
          def log_message(self, *args): pass
          def do_GET(self):
              try:
                  assert self.headers.get('X-Api-Key') == key
                  pending = [process.pid]; seen = set(); found = False
                  while pending:
                      pid = pending.pop()
                      if pid in seen: continue
                      seen.add(pid)
                      proc = pathlib.Path('/proc') / str(pid)
                      try:
                          pending.extend(map(int, (proc / 'task' / str(pid) / 'children').read_text().split()))
                          argv = (proc / 'cmdline').read_bytes().split(b'\0')
                          if argv and pathlib.Path(os.fsdecode(argv[0])).name == 'curl':
                              found = True
                              observations.append(key.encode() not in b'\0'.join(argv))
                      except FileNotFoundError: pass
                  assert found
                  self.send_response(200); self.end_headers()
              except Exception:
                  observations.append(False); self.send_response(500); self.end_headers()
      server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
      endpoint = 'http://127.0.0.1:' + str(server.server_port) + '/api/v1/system/status'
      ready = ready.replace('http://localhost:8686/api/v1/system/status', endpoint).replace(fixture['keyFile'], str(lidarr))
      script = root / 'ready.sh'; script.write_text(ready)
      process = subprocess.Popen([bash, str(script)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      server.timeout = 5; server.handle_request()
      stdout, stderr = process.communicate(timeout=5)
      assert process.returncode == 0 and observations == [True] and key.encode() not in stdout + stderr
      # Reverting just the FD integration must be detected by the same observer.
      mutant, count = re.subn(r'--header @<\([^\n]+\)', '--header "X-Api-Key: ' + key + '"', ready)
      assert count == 1
      observations.clear(); script.write_text(mutant)
      process = subprocess.Popen([bash, str(script)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      server.handle_request(); process.communicate(timeout=5); server.server_close()
      assert process.returncode == 0 and observations == [False], 'inline argv regression escaped observer'
  print('Actual seeder preserves settings, fails closed and stays private; actual curl FD wiring and argv regression proved')
  PY
  touch "$out"
'';

transcripts-deepgram = let
  c = self.nixosConfigurations.hwc-home.config;
  service = c.systemd.services.transcripts;
  python = pkgs.python3.withPackages (ps: with ps; [
    fastapi uvicorn youtube-transcript-api requests httpx playwright
  ]);
in
assert lib.assertMsg (c.hwc.media.youtube.transcripts.deepgram.enable
  && service.serviceConfig.User == "eric"
  && lib.elem "secrets" service.serviceConfig.SupplementaryGroups
  && lib.elem c.age.secrets.deepgram-api-key.file service.restartTriggers)
  "Transcripts Deepgram credential, identity or reload wiring failed";
pkgs.runCommand "transcripts-deepgram" { nativeBuildInputs = [ python pkgs.ripgrep ]; } ''
  export PYTHONPATH=${(repoRoot + "/workspace/media/youtube-services")}
  cd ${(repoRoot + "/workspace/media/youtube-services")}
  python3 -c "import api"
  python3 -m unittest -q test_transcript
  rg -F ${lib.escapeShellArg ''export YT_TRANSCRIPTS_DEEPGRAM_KEY_FILE="${c.hwc.secrets.api.deepgram-api-key}"''} ${service.serviceConfig.ExecStart} >/dev/null
  if rg 'YT_TRANSCRIPTS_WHISPER_' ${service.serviceConfig.ExecStart}; then
    echo "Transcripts still exports a Whisper execution path" >&2
    exit 1
  fi
  touch "$out"
'';

mousehole-runtime-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  image = c.hwc.media.mousehole.image;
  container = c.virtualisation.oci-containers.containers.mousehole;
  fixture = pkgs.writeText "mousehole-runtime-wiring.json" (builtins.toJSON {
    inherit image container;
    preStart = c.systemd.services.podman-mousehole.preStart;
    hook = c.services.borgbackup.jobs.hwc-backup.preHook;
    paths = c.services.borgbackup.jobs.hwc-backup.paths;
    snapshot = c.system.build.mouseholeStateSnapshot or null;
  });
in
assert lib.assertMsg (lib.hasPrefix "localhost/mousehole-runtime:0.2.0-bun1.4.4-" image)
  "Mousehole must consume its qualified same-app Bun runtime";
assert container.image == image && container.pull == "never";
assert lib.elem "--network=container:gluetun" container.extraOptions;
assert container.dependsOn == [ "gluetun" ];
assert c.systemd.services.podman-mousehole.bindsTo == [ "podman-gluetun.service" ];
assert lib.assertMsg (lib.hasInfix (builtins.unsafeDiscardStringContext (toString c.system.build.mouseholeStateSnapshot))
  c.services.borgbackup.jobs.hwc-backup.preHook)
  "Mousehole state snapshot must run in the effective Borg producer hook";
pkgs.runCommand "mousehole-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${c.system.build.mouseholeRuntimeImageRecipe} <<'PY'
  import hashlib, json, os, pathlib, re, runpy, subprocess, sys, tempfile
  from unittest.mock import patch
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  recipe = pathlib.Path(sys.argv[2]).read_text()
  assert spec['image'] == 'localhost/mousehole-runtime:0.2.0-bun1.4.4-' + hashlib.sha256(recipe.encode()).hexdigest()[:12]
  assert re.findall(r'^FROM (\S+)', recipe, re.M) == [
      'docker.io/oven/bun@sha256:b740c3f5600e6360684f240d31c67ffb759def968bfa98ed98c4cce970707735',
      'docker.io/tmmrtn/mousehole@sha256:9adfcfddb3395d33f0fbef50a6dc52a930769c57f2c0af2b3b9d6f7bfda6195c']
  assert 'COPY --from=secure-bun /usr/local/bin/bun /usr/local/bin/bun' in recipe
  assert len(recipe.strip().splitlines()) == 3
  assert spec['image'] in spec['preStart'] and ' image exists ' in spec['preStart']
  assert 'podman build' not in spec['preStart']
  script = spec['snapshot']
  assert script and script in spec['hook']
  assert '/var/lib/backups/mousehole/state.json' in spec['hook']
  assert '/opt/mousehole/data/state.json' in spec['hook']
  assert '/var/lib/backups' in spec['paths']
  with tempfile.TemporaryDirectory() as d:
      root = pathlib.Path(d); source = root / 'live.json'; dest = root / 'snapshot/state.json'
      good = b'{"currentCookie":"fixture-only","lastMam":{"response":{"httpStatus":200}}}'
      source.write_bytes(good)
      def run(): return subprocess.run([script, str(source), str(dest)], capture_output=True)
      first = run()
      assert first.returncode == 0, first.stderr.decode()[:300]
      assert dest.read_bytes() == good
      assert dest.stat().st_mode & 0o777 == 0o600
      assert dest.parent.stat().st_mode & 0o777 == 0o700
      for bad in (b'{"currentCookie":', b'[]', b'{}', b'x' * (1048576 + 1)):
          source.write_bytes(bad)
          assert run().returncode != 0 and dest.read_bytes() == good
      source.unlink()
      assert run().returncode != 0 and dest.read_bytes() == good
      source.write_bytes(good)
      real_open = pathlib.Path.open; reads = [0]
      def raced_open(p, *args, **kwargs):
          if p == source and args and args[0] == 'rb':
              reads[0] += 1
              if reads[0] == 2:
                  with real_open(source, 'wb') as f: f.write(b'{"currentCookie":"changed"}')
          return real_open(p, *args, **kwargs)
      try:
          with patch.object(sys, 'argv', [script, str(source), str(dest)]), patch.object(pathlib.Path, 'open', raced_open):
              runpy.run_path(script, run_name='__main__')
      except (RuntimeError, ValueError): pass
      else: raise AssertionError('racing input must fail before snapshot publication')
      assert reads[0] == 2 and dest.read_bytes() == good
      assert not list(dest.parent.glob('*.pending'))
  PY
  touch "$out"
'';

sabnzbd-runtime-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  container = c.virtualisation.oci-containers.containers.sabnzbd;
  recipe = c.system.build.sabnzbdRuntimeImageRecipe;
  context = c.system.build.sabnzbdRuntimeImageContext;
  data = "${c.hwc.paths.apps.root}/sabnzbd/config";
in
assert lib.assertMsg
  (container.image == "localhost/sabnzbd-runtime:5.1.3-security-${builtins.substring 0 12 (builtins.hashString "sha256" (builtins.readFile recipe))}")
  "SABnzbd must consume the qualified stable security recipe";
assert container.image == c.hwc.media.sabnzbd._runtimeImage;
assert container.pull == "never";
assert lib.elem "--security-opt=no-new-privileges" container.extraOptions;
assert lib.elem "${data}:/config" container.volumes;
assert lib.elem "${c.hwc.paths.hot.root}/events:/mnt/hot/events" container.volumes;
assert lib.elem "${c.hwc.paths.hot.downloads}/scripts:/config/scripts:ro" container.volumes;
assert c.hwc.data.borg.sqliteSnapshots.sabnzbd.source == "${data}/admin/history1.db";
assert c.hwc.data.borg.sqliteSnapshots.sabnzbd.user == "eric";
assert lib.elem data c.hwc.data.borg.sources;
assert lib.hasInfix "podman image exists" c.systemd.services.podman-sabnzbd.preStart;
pkgs.runCommand "sabnzbd-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${context} ${recipe} <<'PY'
  import ast, hashlib, json, pathlib, sys
  root=pathlib.Path(sys.argv[1]); recipe=pathlib.Path(sys.argv[2]).read_text()
  assert (root/'Dockerfile').read_text()==recipe
  assert recipe.startswith('FROM lscr.io/linuxserver/sabnzbd@sha256:2b69019ef0b01bcdb9fb5d6641516bd57cb73b8f98b1a34f61ab749c5ea63376\n')
  assert '--repositories-file /dev/null --no-network --no-cache' in recipe
  assert '--no-index --no-deps --no-cache-dir --force-reinstall' in recipe
  assert '/lsiopy/bin/python3 /tmp/hwc/apply-backports.py' in recipe
  assert 'pip check' in recipe and 'apk verify' in recipe
  manifest=json.loads((root/'manifest.json').read_text()); assert manifest['schemaVersion']==1
  assert json.loads((root/'backports.json').read_text())==manifest['backports']
  assert {p['name']:p['version'] for p in manifest['wheels']} == {'certifi':'2026.10.23','PyJWT':'2.15.1','urllib3':'2.8.0','oauthlib':'4.0.1'}
  assert {p['name']:p['version'] for p in manifest['apks']} == {'curl':'8.23.0-r0','libcurl':'8.23.0-r0','libexpat':'2.10.0-r0','ca-certificates-bundle':'20261020-r0'}
  import base64
  for p in manifest['apks']+manifest['wheels']:
      assert 'sha256-'+base64.b64encode(hashlib.sha256((root/p['file']).read_bytes()).digest()).decode()==p['hash']
      assert '/tmp/hwc/'+p['file'] in recipe
  expected={'sabnzbd/postproc.py':'dbcd60746ae1b8890ce3ac6f85715bfe244080ec4f957dfaaa141b4242bc3e97',
    'interfaces/Glitter/templates/static/javascripts/knockout-extensions.js':'a344b7a1aea287934f36154eb5d3d73ca57592b688bcba51454134cd44e8b35b',
    'interfaces/wizard/static/javascript/checkserver.js':'332318b1bcad64fa7565b4272313c7ef4adeca9c14ba0516fc119037a4fe0360',
    'interfaces/Config/templates/config_server.tmpl':'ee5516fdb731f859a518633387c361a7996bbc2f3e7fc2cca875cfe80f1efe34'}
  assert {k:v['patchedSha256'] for k,v in manifest['backports'].items()}==expected
  program=(root/'apply-backports.py').read_text();ast.parse(program)
  assert 'SOURCE_MISMATCH:' in program and 'PATCH_MISMATCH:' in program and 'MISSING_HUNK:' in program
  assert 'postproc.*.pyc' in program and 'client.*.pyc' in program
  assert manifest['pythonHttpBackport']['patchedSha256']=='1bf66af1b10a72bb91ae15c3f935fd80cdcc38cc10f57aed05797702c4785ad2'
  assert "/usr/lib/python3.14/http/client.py" in program
  PY
  touch "$out"
'';

navidrome-runtime-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  archive = c.system.build.navidromeRuntimeImage;
  package = c.system.build.navidromeRuntimePackage;
  ffmpeg = c.system.build.navidromeRuntimeFfmpeg;
  container = c.virtualisation.oci-containers.containers.navidrome;
  data = c.hwc.media.navidrome.dataDir;
in
assert lib.assertMsg (container.image == "${archive.imageName}:${archive.imageTag}") "Navidrome must consume its qualified runtime";
assert container.pull == "never";
assert lib.elem "${data}:/data" container.volumes;
assert lib.all (v: !(lib.hasSuffix ":/config" v)) container.volumes;
assert lib.elem "--security-opt=no-new-privileges" container.extraOptions;
assert c.hwc.data.borg.sqliteSnapshots.navidrome.source == "${data}/navidrome.db";
assert c.hwc.data.borg.sqliteSnapshots.navidrome.user == "root";
assert lib.elem data c.hwc.data.borg.sources;
assert lib.hasInfix "test -s ${lib.escapeShellArg "${data}/navidrome.db"}" c.systemd.services.podman-navidrome.preStart;
assert lib.hasInfix (builtins.unsafeDiscardStringContext "podman load --input ${archive}")
  (builtins.unsafeDiscardStringContext c.systemd.services.podman-navidrome.preStart);
pkgs.runCommand "navidrome-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${archive} ${package} ${pkgs.go_1_27}/bin/go ${ffmpeg} <<'PY'
  import json, pathlib, subprocess, sys, tarfile
  archive, package, go, ffmpeg = sys.argv[1:]
  with tarfile.open(archive) as t:
      manifest = json.load(t.extractfile('manifest.json'))
      assert len(manifest) == 1
      cfg = json.load(t.extractfile(manifest[0]['Config']))['config']
  assert cfg['Entrypoint'] == [package + '/bin/navidrome']
  assert cfg['WorkingDir'] == '/data'
  assert 'ND_DATAFOLDER=/data' in cfg['Env'] and 'ND_MUSICFOLDER=/music' in cfg['Env']
  assert not cfg.get('Volumes'), 'data must not silently fall back to an anonymous volume'
  version = subprocess.check_output([package + '/bin/navidrome', '--version'], text=True)
  assert version.startswith('0.64.2 ')
  assert ffmpeg + '/bin' in pathlib.Path(package + '/bin/navidrome').read_text()
  metadata = subprocess.check_output([go, 'version', '-m', package + '/bin/.navidrome-wrapped'], text=True)
  assert ': go1.27.3' in metadata
  expected = {'github.com/go-chi/chi/v5':'v5.4.0','golang.org/x/net':'v0.62.0','golang.org/x/crypto':'v0.58.0',
      'golang.org/x/sys':'v0.49.0','golang.org/x/text':'v0.43.0'}
  modules = {p[1]:p[2] for line in metadata.splitlines() if len(p := line.split()) >= 3 and p[0] == 'dep'}
  assert all(modules.get(k) == v for k,v in expected.items())
  PY
  touch "$out"
'';

audiobookshelf-runtime-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  image = c.hwc.media.audiobookshelf.image;
  fixture = pkgs.writeText "audiobookshelf-runtime-wiring.json" (builtins.toJSON { inherit image; });
in
assert lib.assertMsg (lib.hasPrefix "localhost/audiobookshelf-runtime:2.37.2-node24.22.2-" image)
  "Audiobookshelf must consume its qualified application and Node24 image";
assert c.virtualisation.oci-containers.containers.audiobookshelf.image == image;
assert c.virtualisation.oci-containers.containers.audiobookshelf.pull == "never";
assert lib.hasInfix "image exists ${lib.escapeShellArg image}" c.systemd.services.podman-audiobookshelf.preStart;
pkgs.runCommand "audiobookshelf-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${c.system.build.audiobookshelfRuntimeImageRecipe} ${c.system.build.audiobookshelfRuntimeImageContext} <<'PY'
  import base64, hashlib, json, pathlib, re, shlex, sys
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  recipe = pathlib.Path(sys.argv[2]).read_text()
  assert spec['image'] == 'localhost/audiobookshelf-runtime:2.37.2-node24.22.2-' + hashlib.sha256(recipe.encode()).hexdigest()[:12]
  sources = re.findall(r'^FROM (\S+)', recipe, re.M)
  assert sources == [
      'docker.io/library/node@sha256:4eefa1bfce4197942661ef9148247d779ddf1bb0ee006d3294a467609de60724',
      'ghcr.io/advplyr/audiobookshelf@sha256:37c2057e150694970442579815c646fe6bdc01c95b9d1547c4c9068be8844ef3']
  assert 'COPY --from=secure-node /usr/local/bin/node /usr/local/bin/node' in recipe
  assert 'ENV NODE_VERSION=24.22.2' in recipe
  context = pathlib.Path(sys.argv[3])
  assert (context / 'Dockerfile').read_text() == recipe
  manifest = context / 'manifest.json'
  assert '# Fixed dependency inputs ' + hashlib.sha256(manifest.read_bytes()).hexdigest() in recipe
  spec = json.loads(manifest.read_text())
  assert spec['schemaVersion'] == 1 and len(spec['packages']) == 15
  top = {p['name']:p['version'] for p in spec['packages'] if p['path'] == p['name']}
  assert top == {'form-data':'4.0.6', 'proxy-addr':'2.0.8'}
  assert {p.name for p in (context / 'npm').iterdir()} == {p['file'] for p in spec['packages']}
  active = [line for line in recipe.splitlines() if line.strip() and not line.lstrip().startswith('#')]
  assert len(active) == 6 and 'COPY npm/ /tmp/hwc-audiobookshelf-npm/' in active
  run = next(line[4:] for line in active if line.startswith('RUN '))
  commands = [[]]
  for arg in shlex.split(run):
      if arg == '&&': commands.append([])
      else: commands[-1].append(arg)
  expected = []
  for p in spec['packages']:
      assert p['path'] in top or re.fullmatch(r'form-data/node_modules/[a-z0-9][a-z0-9._-]*', p['path'])
      assert p['hash'].startswith('sha512-')
      assert hashlib.sha512((context / 'npm' / p['file']).read_bytes()).digest() == base64.b64decode(p['hash'][7:])
      destination = '/app/node_modules/' + p['path']
      expected.extend([['rm','-rf',destination], ['mkdir','-p',destination],
          ['tar','-xzf','/tmp/hwc-audiobookshelf-npm/'+p['file'],'-C',destination,'--strip-components=1','--no-same-owner']])
  expected.append(['rm','-r','/tmp/hwc-audiobookshelf-npm'])
  assert commands == expected, 'production must install the complete isolated closure without a resolver'
  PY
  touch "$out"
'';

starlette-host-backport-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  frigate = c.system.build.frigateRuntimeImageRecipe.text;
  ml = c.system.build.immichMlRuntimeImageRecipe.text;
  expectedFrigate = "localhost/frigate-runtime:0.18.2-tensorrt-hostfix-${builtins.substring 0 12 (builtins.hashString "sha256" frigate)}";
  expectedMl = "localhost/immich-ml-runtime:2.5.6-${builtins.substring 0 12 (builtins.hashString "sha256" ml)}";
in
assert c.virtualisation.oci-containers.containers.frigate.image == expectedFrigate;
assert c.virtualisation.oci-containers.containers.immich-machine-learning.image == expectedMl;
assert c.virtualisation.oci-containers.containers.frigate.pull == "never";
assert lib.hasInfix "FROM ghcr.io/blakeblackshear/frigate@sha256:1cafb6ebbaff0aaf275cc3f31951bcf7e29f3989f18a10ba9565091367d8736c" frigate;
assert lib.hasInfix "image exists ${lib.escapeShellArg expectedFrigate}" c.systemd.services.podman-frigate.preStart;
pkgs.runCommand "starlette-host-backport-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${c.system.build.frigateRuntimeImageRecipe} ${c.system.build.immichMlBaseRuntimeImageRecipe} ${c.system.build.frigateRuntimeImageContext} <<'PYTEST'
  import base64, hashlib, json, pathlib, shlex, sys
  expected = [('0.47.3', 'ce16c619c99e45507a3aebedf47c2807c8122bd9396e21f7cd48636f9715fa8c', '5c163e52df0a615c7860136b30d010c48696c0774011db8879a3299e025ed441'),
              ('0.50.0', 'dde752330006431c7ebc1ccb948a95825be5bd6b8c03839133cdee59899c3030', '77253c43dce33af8b92b1b76794c6b39205419a520663246dfba595e4c76b283')]
  programs = []
  for path, hashes in zip(sys.argv[1:3], expected):
      recipe = pathlib.Path(path).read_text()
      assert all(line.split()[0] in {'FROM', 'RUN', 'COPY', 'ADD', 'ENV'} for line in recipe.splitlines() if line.strip() and not line.startswith('#'))
      at = recipe.rindex('RUN ')
      args = shlex.split(recipe[at + 4:])
      assert args[1] == '-c' and tuple(args[3:]) == hashes
      compile(args[2], '<backport>', 'exec')
      assert '_HOST_RE.fullmatch(host_header)' in args[2]
      assert 'hashlib.sha256(source.encode()).hexdigest() == patched' in args[2]
      programs.append(args[2])
  assert programs[0] == programs[1], 'backport must have one producer'
  context = pathlib.Path(sys.argv[3])
  recipe = pathlib.Path(sys.argv[1]).read_text()
  manifest = context / 'manifest.json'
  assert (context / 'Dockerfile').read_text() == recipe
  assert '# Fixed runtime inputs ' + hashlib.sha256(manifest.read_bytes()).hexdigest() in recipe
  assert 'apt-get --no-download' in recipe and 'pip install --no-index --no-deps' in recipe
  inputs = json.loads(manifest.read_text())
  assert len(inputs['debian']) == 11 and len(inputs['wheels']) == 2
  assert {p['name'].lower():p['version'] for p in inputs['wheels']} == {'pillow':'13.0.0','certifi':'2026.10.18'}
  for group, directory in [('debian', 'debian'), ('wheels', 'wheels')]:
      assert {p.name for p in (context / directory).iterdir()} == {p['file'] for p in inputs[group]}
      for p in inputs[group]:
          actual = hashlib.sha256((context / directory / p['file']).read_bytes()).digest()
          assert actual == base64.b64decode(p['hash'].removeprefix('sha256-')), p['name']
  PYTEST
  touch "$out"
'';

frigate-http-framing = let
  host = self.nixosConfigurations.hwc-home;
  c = host.config;
  shared = builtins.fromJSON (builtins.readFile (repoRoot + "/overlays/python-http-framing.json"));
in
assert host.pkgs.pythonHttpFramingBackport == {
  inherit (shared) upstreamCommits replacements;
};
pkgs.runCommand "frigate-http-framing" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${c.system.build.frigateRuntimeImageContext} <<'PY'
  import copy, hashlib, json, pathlib, shlex, subprocess, sys, tempfile
  context = pathlib.Path(sys.argv[1])
  recipe = (context / 'Dockerfile').read_text()
  manifest = json.loads((context / 'manifest.json').read_text())['pythonHttpBackport']
  assert manifest['schemaVersion'] == 1 and set(manifest['modules']) == {'httpClient', 'urllib3'}
  assert len(manifest['stdlibUpstreamCommits']) == 2
  assert manifest['modules']['httpClient']['path'] == '/usr/lib/python3.11/http/client.py'
  assert manifest['modules']['urllib3']['path'] == '/usr/local/lib/python3.11/dist-packages/urllib3/response.py'
  def emitted(value, expected):
    matches = []
    for line in value.splitlines():
      if not line.startswith('RUN '):
        continue
      args = shlex.split(line[4:])
      if '-c' in args and 'HTTP_BACKPORT_PAIR' in args[args.index('-c') + 1]:
        assert args[:3] == ['python3', '-B', '-c'] and len(args) == 5
        assert json.loads(args[4]) == expected
        compile(args[3], '<actual-image-builder>', 'exec')
        matches.append((line, args[3]))
    assert len(matches) == 1, 'HTTP_BACKPORT_INTEGRATION_MISSING'
    return matches[0]
  line, program = emitted(recipe, manifest)
  without_integration = '\n'.join(value for value in recipe.splitlines() if value != line)
  try:
    emitted(without_integration, manifest)
  except AssertionError:
    pass
  else:
    raise AssertionError('OMITTED_BACKPORT_ACCEPTED')
  # Run the actual emitted builder. A bad second module must fail before the
  # first file changes. This tests the guard; actual image tests own success.
  sha = lambda value: hashlib.sha256(value).hexdigest()
  cases = {'source': 'HTTP_SOURCE_DRIFT', 'result': 'HTTP_RESULT_DRIFT',
    'hunk': 'HTTP_HUNK_DRIFT', 'pair': 'HTTP_BACKPORT_PAIR', 'bound': 'HTTP_SOURCE_BOUND'}
  for kind, code in cases.items():
    with tempfile.TemporaryDirectory(prefix='http-builder-guard-') as folder:
      root = pathlib.Path(folder)
      fixture = copy.deepcopy(manifest)
      originals = {}
      for name, suffix in [('httpClient', 'http/client.py'), ('urllib3', 'urllib3/response.py')]:
        path = root / suffix
        path.parent.mkdir(parents=True)
        original = b'sentinel=1\n'
        path.write_bytes(original)
        originals[path] = original
        fixture['modules'][name] = {'path': str(path), 'sourceSha256': sha(original),
          'patchedSha256': sha(b'sentinel=2\n'), 'replacements': [['sentinel=1', 'sentinel=2']]}
      second = fixture['modules']['urllib3']
      if kind == 'source':
        second['sourceSha256'] = '0' * 64
      elif kind == 'result':
        second['patchedSha256'] = '0' * 64
      elif kind == 'hunk':
        second['replacements'] = [['missing_sentinel', 'sentinel=2']]
      elif kind == 'pair':
        del fixture['modules']['urllib3']
      elif kind == 'bound':
        path = pathlib.Path(second['path'])
        originals[path] = b'x' * 262145
        path.write_bytes(originals[path])
      result = subprocess.run([sys.executable, '-B', '-c', program, json.dumps(fixture)], capture_output=True, timeout=10)
      assert result.returncode != 0 and code.encode() in result.stderr, kind
      assert all(path.read_bytes() == original for path, original in originals.items()), 'PARTIAL_PAIR_WRITE:' + kind
  PY
  touch "$out"
'';

immich-database-auth-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  db = c.hwc.media.immich.database;
  container = c.virtualisation.oci-containers.containers.immich-server;
  app = c.systemd.services.podman-immich-server;
  operator = c.systemd.services.postgresql-application-roles;
  secret = c.age.secrets.immich-db-password;
  dependency = "postgresql-application-roles.service";
  fixture = pkgs.writeText "immich-database-auth-wiring.json" (builtins.toJSON {
    inherit (c.services.postgresql) authentication;
    inherit (container) environment volumes;
    role = c.hwc.data.databases.postgresql.applicationRoles.immich;
  });
in
assert lib.assertMsg (c.hwc.data.databases.postgresql.authenticationMode == "peer-scram") "Home must use peer/SCRAM authentication";
assert db.user == "immich" && db.name == "immich" && db.passwordSecret == "immich-db-password";
assert !(container.environment ? DB_URL) && !(container.environment ? DB_PASSWORD);
assert builtins.elem dependency app.after && builtins.elem dependency app.requires;
assert builtins.elem secret.file app.restartTriggers && builtins.elem secret.file operator.restartTriggers;
assert operator.serviceConfig.LoadCredential == [ "immich:${secret.path}" ];
assert secret.owner == "root" && secret.group == "secrets" && secret.mode == "0440";
assert operator.serviceConfig.User == "eric" && operator.serviceConfig.RestrictAddressFamilies == [ "AF_UNIX" ];
assert builtins.elem "postgresql-setup.service" operator.after && builtins.elem "postgresql-setup.service" operator.requires;
pkgs.runCommand "immich-database-auth-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${c.system.build.postgresqlApplicationRoleTool} ${c.system.build.postgresqlApplicationRoleConfig} ${(repoRoot + "/domains/data/databases/application-roles.py")} <<'PY'
  import json, pathlib, sys
  binding = json.loads(pathlib.Path(sys.argv[1]).read_text())
  tool = pathlib.Path(sys.argv[2]).read_text()
  spec = json.loads(pathlib.Path(sys.argv[3]).read_text())
  assert sys.argv[4] in tool and sys.argv[3] in tool
  assert '--socket /run/postgresql' in tool and '--admin-role eric' in tool
  assert spec == {'schemaVersion': 2, 'roles': {'immich': {
    'credential': {'password': 'immich-db-password'},
    'authority': {'owned': {'schemas': ['public', 'vectors'], 'takeOwnershipFrom': 'eric'}},
    'prepareSql': "",
  }}}
  assert '--contract ' in tool
  assert binding['environment']['DB_USERNAME'] == 'immich'
  target = binding['environment']['DB_PASSWORD_FILE']
  assert '/run/agenix/immich-db-password:' + target + ':ro' in binding['volumes']
  lines = [s.split() for s in binding['authentication'].splitlines() if s.strip() and not s.lstrip().startswith('#')]
  assert lines[:2] == [['local', 'all', 'postgres', 'peer', 'map=postgres'], ['local', 'all', 'all', 'peer']]
  assert not any('trust' in row for row in lines)
  assert all(row[-1] == 'scram-sha-256' for row in lines if row[0] == 'host')
  PY
  touch "$out"
'';

immich-runtime-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  cfg = c.hwc.media.immich;
  fixture = pkgs.writeText "immich-runtime-wiring.json" (builtins.toJSON {
    server = cfg.images.server;
    ml = cfg.images.machineLearning;
    seerr = c.hwc.media.jellyseerr.image;
  });
in
assert lib.assertMsg (lib.hasPrefix "localhost/immich-runtime:2.5.6-node24.22.1-" cfg.images.server
  && lib.hasPrefix "localhost/immich-ml-runtime:2.5.6-" cfg.images.machineLearning)
  "Immich must consume its qualified same-app Node and ML TLS/CA images";
assert c.virtualisation.oci-containers.containers.immich-server.image == cfg.images.server;
assert c.virtualisation.oci-containers.containers.immich-machine-learning.image == cfg.images.machineLearning;
pkgs.runCommand "immich-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${c.system.build.immichServerRuntimeImageRecipe} ${c.system.build.immichMlRuntimeImageRecipe} ${c.system.build.seerrRuntimeImageRecipe} ${c.system.build.immichMlBaseRuntimeImageRecipe} ${c.system.build.immichMlRuntimeImageContext} <<'PY'
  import ast, copy, hashlib, json, pathlib, re, shlex, subprocess, sys, tempfile, zipfile
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  server, ml, seerr, base = [pathlib.Path(p).read_text() for p in sys.argv[2:6]]
  context = pathlib.Path(sys.argv[6])
  sha = lambda value: hashlib.sha256(value.encode()).hexdigest()
  assert spec['server'] == 'localhost/immich-runtime:2.5.6-node24.22.1-' + sha(server)[:12]
  assert spec['ml'] == 'localhost/immich-ml-runtime:2.5.6-' + sha(ml)[:12]
  for recipe in [server, base]:
      sources = re.findall(r'^FROM (\S+)', recipe, re.M)
      assert len(sources) == 2 and all(re.search(r'@sha256:[0-9a-f]{64}$', s) for s in sources)
  assert 'ENV NODE_VERSION=24.22.1' in server
  assert '--only-upgrade' in base and 'libssl3=3.0.2-0ubuntu1.30' in base and 'openssl=3.0.2-0ubuntu1.30' in base
  assert 'ca-certificates=20260816ubuntu0.22.04.1' in base
  assert '--checksum=sha256:e9b54de76e530bb6cf0ccd036787103acb58fd42ba930ea8bf948ddbaa2f61d1' in base
  assert '--no-index --no-deps' in base and 'certifi-2026.10.23' in base
  assert 'emSign Root CA - C1' in base and 'emSign ECC Root CA - C3' in base
  assert 'update-ca-certificates --fresh' in base
  # The previous consumed producer stays byte-identical and is the new parent.
  base_image='localhost/immich-ml-runtime:2.5.6-'+sha(base)[:12]
  assert base_image=='localhost/immich-ml-runtime:2.5.6-9e53cacc2f21'
  manifest=json.loads((context/'manifest.json').read_text())
  assert manifest['schemaVersion']==1 and manifest['baseImage']==base_image
  assert manifest['sitePackages']=='/opt/venv/lib/python3.11/site-packages'
  assert manifest['wheelDirectory']=='/tmp/hwc-http'
  assert set(manifest['wheels'])=={'requests','urllib3'}
  assert {k:v['version'] for k,v in manifest['wheels'].items()}=={'requests':'2.33.0','urllib3':'2.8.0'}
  assert (context/'Dockerfile').read_text()==ml
  for entry in manifest['wheels'].values():
      assert hashlib.sha256((context/'wheels'/entry['filename']).read_bytes()).hexdigest()==entry['sha256']
  def emitted(text):
      installers=[];framing=[]
      for line in text.splitlines():
          if not line.startswith('RUN '):continue
          argv=shlex.split(line[4:])
          if '-c' not in argv:continue
          assert argv[:3]==['/opt/venv/bin/python','-B','-c']
          if 'ML_HTTP_PACKAGE_PAIR' in argv[3]:
              module=ast.parse(argv[3]);invoke=module.body[-1].value
              assert invoke.func.id=='exec' and invoke.args[0].func.id=='compile'
              assert next(x.value.value for x in invoke.args[0].keywords if x.arg=='optimize')==0
              assert json.loads(ast.literal_eval(module.body[1].value.elts[1]))==manifest
              installers.append(ast.literal_eval(invoke.args[0].args[0]))
          elif 'HTTP_BACKPORT_PAIR' in argv[3]:
              assert json.loads(argv[4])==manifest['framing'];framing.append(line)
      return installers,framing
  def wired(text):
      try:
          install,framing=emitted(text)
          return (re.findall(r'^FROM (\S+)',text,re.M)==[base_image] and len(install)==len(framing)==1
              and 'COPY wheels/ /tmp/hwc-http/' in text)
      except (AssertionError,ValueError,StopIteration):return False
  assert wired(ml)
  for marker in ['ML_HTTP_PACKAGE_PAIR','HTTP_BACKPORT_PAIR']:
      omitted='\n'.join(line for line in ml.splitlines() if marker not in line)+'\n'
      assert omitted!=ml and not wired(omitted),'ML_HTTP_INTEGRATION_SEED:'+marker
  assert not wired(ml.replace('FROM '+base_image,'FROM unrelated-base'))
  installer=emitted(ml)[0][0]
  # Execute the emitted installer on disposable package owners and real wheels.
  # A bad second input must leave the entire original tree intact.
  for failure in ['none','missing-second','corrupt-second','escape-second','link-second']:
      with tempfile.TemporaryDirectory() as directory:
          root=pathlib.Path(directory);site=root/'site';inputs=root/'wheels';site.mkdir();inputs.mkdir()
          value=copy.deepcopy(manifest);value['sitePackages']=str(site);value['wheelDirectory']=str(inputs)
          for name,entry in value['wheels'].items():
              (site/name).mkdir();(site/name/'sentinel').write_text('original-'+name)
              (site/(name+'-'+entry['originalVersion']+'.dist-info')).mkdir()
              (inputs/entry['filename']).write_bytes((context/'wheels'/entry['filename']).read_bytes())
          second=value['wheels']['urllib3'];path=inputs/second['filename']
          if failure=='missing-second':path.unlink()
          elif failure=='corrupt-second':path.write_bytes(b'corrupt')
          elif failure=='escape-second':
              with zipfile.ZipFile(path,'w') as archive:archive.writestr('../escape','wrong-owner')
              second['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
          elif failure=='link-second':
              with zipfile.ZipFile(path,'w') as archive:
                  link=zipfile.ZipInfo('urllib3/escape');link.external_attr=0o120777<<16
                  archive.writestr(link,'wrong-owner')
              second['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
          before={str(p.relative_to(site)):p.read_bytes() for p in site.rglob('*') if p.is_file()}
          harness="import importlib.metadata,json,pathlib,sys,types;spec=json.loads(sys.argv[1]);root=pathlib.Path(spec['sitePackages']);importlib.metadata.distribution=lambda n:types.SimpleNamespace(version=spec['wheels'][n]['originalVersion'],locate_file=lambda _:root,files=[pathlib.Path(n)/'sentinel']);exec(compile("+repr(installer)+",'<actual-installer>','exec',optimize=0),{'__name__':'__main__'})"
          result=subprocess.run([sys.executable,'-OO','-c',harness,json.dumps(value)],capture_output=True,timeout=10)
          after={str(p.relative_to(site)):p.read_bytes() for p in site.rglob('*') if p.is_file()}
          if failure=='none':
              assert result.returncode==0,(failure,result.stderr)
              assert before.keys().isdisjoint(after) and all((site/name/'__init__.py').is_file() for name in value['wheels'])
          else:
              assert result.returncode!=0 and after==before,(failure,result.stderr)
              wanted={'missing-second':b'FileNotFoundError','corrupt-second':b'ML_HTTP_WHEEL_DRIFT','escape-second':b'ML_HTTP_ARCHIVE_PATH','link-second':b'ML_HTTP_ARCHIVE_TYPE'}[failure]
              assert wanted in result.stderr,(failure,result.stderr)
  # Security backports preserve the accepted same-app Node recipe prefix.
  assert sha(seerr.split('# Security backports', 1)[0].replace(' AS seerr-base', "")) == 'b9482a37e259fcd93442be29ae2b1cfce0653bc5e738e68fab403a84297953ea'
  assert spec['seerr'] == 'localhost/seerr-runtime:3.1.0-node22.23.4-' + sha(seerr)[:12]
  PY
  touch "$out"
'';

immich-shared-brotli-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  cfg = c.hwc.media.immich;
  serverContext = c.system.build.immichServerRuntimeImageContext;
  mlContext = c.system.build.immichMlBaseRuntimeImageContext;
  libraries = c.system.build.immichPillowBrotliLibraries;
  manifest = builtins.fromJSON c.system.build.immichRuntimeSecurityManifest.text;
  server = c.system.build.immichServerRuntimeImageRecipe.text;
  ml = c.system.build.immichMlBaseRuntimeImageRecipe.text;
  finalMl = c.system.build.immichMlRuntimeImageRecipe.text;
in
assert lib.assertMsg (lib.hasInfix "COPY ${manifest.brotli.filename} /tmp/hwc-brotli.deb" server
  && lib.hasInfix "dpkg -i /tmp/hwc-brotli.deb" server
  && lib.hasInfix "COPY pillow-brotli/" ml
  && lib.hasInfix "RUN chmod ${manifest.pillowLibraryMode}" ml)
  "Immich recipes must consume both corrected shared Brotli inputs";
assert cfg.images.server == "localhost/immich-runtime:2.5.6-node24.22.1-${builtins.substring 0 12 (builtins.hashString "sha256" server)}";
assert cfg.images.machineLearning == "localhost/immich-ml-runtime:2.5.6-${builtins.substring 0 12 (builtins.hashString "sha256" finalMl)}";
assert lib.hasPrefix "FROM localhost/immich-ml-runtime:2.5.6-${builtins.substring 0 12 (builtins.hashString "sha256" ml)}\n" finalMl;
assert c.virtualisation.oci-containers.containers.immich-server.image == cfg.images.server;
assert c.virtualisation.oci-containers.containers.immich-machine-learning.image == cfg.images.machineLearning;
assert c.virtualisation.oci-containers.containers.immich-server.pull == "never";
assert c.virtualisation.oci-containers.containers.immich-machine-learning.pull == "never";
assert lib.hasInfix "image exists ${lib.escapeShellArg cfg.images.server}" c.systemd.services.podman-immich-server.preStart;
assert lib.hasInfix "image exists ${lib.escapeShellArg cfg.images.machineLearning}" c.systemd.services.podman-immich-machine-learning.preStart;
pkgs.runCommand "immich-shared-brotli-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${serverContext} ${mlContext} ${libraries} <<'PY'
  import ctypes, hashlib, json, pathlib, stat, sys
  server, ml, libraries = map(pathlib.Path, sys.argv[1:])
  spec = json.loads((server / 'manifest.json').read_text())
  assert spec == json.loads((ml / 'manifest.json').read_text())
  assert spec['brotli']['version'] == '1.1.0-2+deb13u1'
  assert spec['brotli']['sha256'] == 'db46824c60fee46aff3cc0be3e5f736bc606cae669b1fb17516a41e8073251a9'
  package = server / spec['brotli']['filename']
  assert hashlib.sha256(package.read_bytes()).hexdigest() == spec['brotli']['sha256']
  for name in spec['pillowLibraries'].values():
      copied = ml / 'pillow-brotli' / name
      assert copied.read_bytes() == (libraries / name).read_bytes()
      # Nix canonicalizes executable store inputs to read-only. The
      # image recipe restores the original container mode explicitly.
      assert stat.S_IMODE(copied.stat().st_mode) == int(spec['pillowLibraryMode'], 8) & ~0o222
  common = libraries / spec['pillowLibraries']['common']
  decoder = libraries / spec['pillowLibraries']['decoder']
  ctypes.CDLL(str(common), mode=ctypes.RTLD_GLOBAL)
  lib = ctypes.CDLL(str(decoder))
  lib.BrotliDecoderErrorString.argtypes = [ctypes.c_int]
  lib.BrotliDecoderErrorString.restype = ctypes.c_char_p
  assert any(b'BLOCK_SWITCH' in lib.BrotliDecoderErrorString(i) for i in range(-64, 1)), 'security backport absent from generated loader input'
  PY
  touch "$out"
'';

calibre-security-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  nativePackage = c.system.build.calibreRuntimeNativePackage;
  rejectCatalog = args: !(builtins.tryEval (builtins.deepSeq
    (helpers.selectFfmpegSecurityBackports args).commits true)).success;
  rejectContext = args: !(builtins.tryEval
    (helpers.adaptFfmpegPatchContext args).drvPath).success;
  binding = pkgs.writeText "calibre-security-binding.json" (builtins.toJSON {
    native = (builtins.fromJSON c.system.build.calibreRuntimeAssets.text).native;
    nativeSourceGuard = toString c.system.build.calibreRuntimeNativeSourceGuard;
    nativeSourceSpec = toString c.system.build.calibreRuntimeNativeSourceSpec;
    nativePostPatch = nativePackage.postPatch;
    nativePatchFlags = nativePackage.patchFlags;
    nativePatchCount = builtins.length nativePackage.patches;
    stdlib = {
      spec = toString c.system.build.calibreRuntimeStdlibSpec;
      guard = toString c.system.build.calibreRuntimeStdlibSourceGuard;
      command = c.system.build.calibreRuntimeStdlibPackage.buildCommand;
      package = toString c.system.build.calibreRuntimeStdlibPackage;
    };
    ssl = {
      spec = toString c.system.build.calibreRuntimeSslSpec;
      guard = toString c.system.build.calibreRuntimeSslSourceGuard;
      postPatch = c.system.build.calibreRuntimeSslPackage.postPatch;
      build = c.system.build.calibreRuntimeSslPackage.buildPhase;
      patchFlags = c.system.build.calibreRuntimeSslPackage.patchFlags;
      patchCount = builtins.length c.system.build.calibreRuntimeSslPackage.patches;
      runtime = (builtins.fromJSON c.system.build.calibreRuntimeAssets.text).nativeSsl;
    };
    contextTransforms = map (patch: { path = toString patch; command = patch.buildCommand; })
      (builtins.filter (patch: builtins.isAttrs patch
        && lib.hasSuffix "-7.1.patch" (patch.name or "")) nativePackage.patches);
    selected = c.hwc.media.calibre.image;
    container = c.virtualisation.oci-containers.containers.calibre.image;
    volumes = c.virtualisation.oci-containers.containers.calibre.volumes;
    library = toString c.hwc.media.calibre.library;
    config = "${c.hwc.paths.apps.root}/calibre/config";
    pull = c.virtualisation.oci-containers.containers.calibre.pull;
    preStart = c.systemd.services.podman-calibre.preStart;
  });
in
assert rejectCatalog { advisories = []; };
assert rejectCatalog { advisories = [ "unknown" ]; };
assert rejectCatalog { advisories = [ "CVE-2026-107676" "CVE-2026-107676" ]; };
assert rejectCatalog { advisories = [ "CVE-2026-107676" ]; contextEdits.unknown = []; };
assert rejectContext { upstream = ""; name = "../escape"; edits = [ [ "old" "new" ] ]; };
assert rejectContext { upstream = ""; name = "empty"; edits = []; };
assert rejectContext { upstream = ""; name = "excess"; edits = [ [] [] [] ]; };
pkgs.runCommand "calibre-security-wiring" { nativeBuildInputs = [ pkgs.python3 pkgs.patchelf ]; } ''
  python3 - ${binding} ${c.system.build.calibreRuntimeImageRecipe} ${c.system.build.calibreRuntimeImageContext} <<'PYTEST'
  import ast, copy, hashlib, json, os, pathlib, shlex, subprocess, sys, tempfile
  v=json.loads(pathlib.Path(sys.argv[1]).read_text())
  stdlib=v['stdlib'];stdlib_spec=json.loads(pathlib.Path(stdlib['spec']).read_text())
  stdlib_package=pathlib.Path(stdlib['package'])
  assert json.loads((stdlib_package/'manifest.json').read_text())==stdlib_spec
  assert set(stdlib_spec['modules'])=={'poplib','shutil','tarfile','tempfile'}
  assert [p['advisory'] for p in stdlib_spec['patches']]==['CVE-2026-87910','CVE-2026-114583','CVE-2026-12345','CVE-2025-15367']
  expected_stdlib_files={'manifest.json'}
  for name,entry in stdlib_spec['modules'].items():
      for folder,size_key,hash_key in [('original','originalBytes','originalSha256'),('lib','bytes','sha256')]:
          relative=folder+'/'+entry['file'];expected_stdlib_files.add(relative)
          raw=(stdlib_package/relative).read_bytes()
          assert len(raw)==entry[size_key] and hashlib.sha256(raw).hexdigest()==entry[hash_key]
  assert {str(p.relative_to(stdlib_package)) for p in stdlib_package.rglob('*') if p.is_file()}==expected_stdlib_files
  try:exec(compile(pathlib.Path(stdlib['guard']).read_bytes(),'<optimized-stdlib-source-guard>','exec',optimize=2),{'__name__':'test_stdlib_optimized'})
  except AssertionError as error:assert str(error)=='CALIBRE_STDLIB_OPTIMIZED_GUARD'
  else:raise AssertionError('STDLIB_OPTIMIZED_GUARD_SEED')
  # Replay the emitted producer itself on bounded disposable source members.
  # Removing each patch must fail the complete producer before publication.
  producer=stdlib['command'];producer_lines=producer.splitlines()
  patch_lines=[line for line in producer_lines if shlex.split(line) and shlex.split(line)[0].endswith('/bin/patch')]
  assert len(patch_lines)==len(stdlib_spec['patches'])==4
  for line in patch_lines:assert shlex.split(line)[1:1+len(stdlib_spec['patchFlags'])]==stdlib_spec['patchFlags']
  assert '--fuzz=0' in stdlib_spec['patchFlags'] and '--no-backup-if-mismatch' in stdlib_spec['patchFlags']
  phases={mode:next(line for line in producer_lines if stdlib['guard']+' '+mode+' '+stdlib['spec'] in line)
      for mode in stdlib_spec['commands'].values()}
  cases=[('none',None)]+[('patch-'+str(i),line) for i,line in enumerate(patch_lines)]+list(phases.items())
  for kind,omission in cases:
      with tempfile.TemporaryDirectory() as directory:
          root=pathlib.Path(directory);output=root/'published';env=os.environ|{'out':str(output)}
          command=producer if omission is None else producer.replace(omission,'# omitted '+kind)
          assert omission is None or command!=producer
          run=subprocess.run(['${pkgs.bash}/bin/bash','-e','-u','-c',command],cwd=root,env=env,capture_output=True,timeout=25)
          assert len(run.stdout)+len(run.stderr)<=65536,'STDLIB_PRODUCER_LOG_BOUND'
          if kind=='none':
              assert run.returncode==0,(kind,run.stderr)
              assert json.loads((output/'manifest.json').read_text())==stdlib_spec
          else:
              assert not output.exists(),'STDLIB_OMITTED_STEP_PUBLISHED:'+kind
              if kind!=stdlib_spec['commands']['finish']:assert run.returncode!=0,kind
  ssl=v['ssl'];ssl_spec=json.loads(pathlib.Path(ssl['spec']).read_text())
  def ssl_wired(value):
      return (value['patchFlags']==['-p1','--fuzz=0'] and value['patchCount']==1
          and value['guard']+' '+value['spec']+' .' in value['postPatch']
          and 'Modules/_ssl.c' in value['build'] and '-shared -fPIC' in value['build']
          and '-bluez-' in value['build']
          and '-lssl -lcrypto' in value['build'] and '-lpython' not in value['build'])
  assert ssl_wired(ssl)
  for key in ['postPatch','build']:
      missing=copy.deepcopy(ssl);missing[key]=""
      assert not ssl_wired(missing),'CALIBRE_SSL_WIRING_SEED:'+key
  assert ssl_spec['pythonVersion']==[3,14,8] and ssl_spec['opensslVersion']=='3.5.9'
  assert ssl_spec['patch']['includes']==sorted(ssl_spec['sourceFiles'])
  assert ssl_spec['patch']['hash']=='sha256-golYkxggS4HEq/zTjv3TeI3AVKuqTqtKXCBrU+0Ky4E='
  assert ssl_spec['original']['needed']==['libc.so.6','libcrypto.so.3','libssl.so.3']
  assert ssl_spec['rpath']=='$ORIGIN/..'
  assert ssl_spec['apiConstantChanges']=={'_OPENSSL_API_VERSION':{'original':[3,5,0,8,0],'rebuilt':[3,5,0,9,0]}}
  assert ssl_spec['apiSha256']!=ssl_spec['original']['apiSha256']
  guard={};exec(compile(pathlib.Path(ssl['guard']).read_text(),'<actual-ssl-source-guard>','exec',optimize=0),guard)
  with tempfile.TemporaryDirectory() as directory:
      root=pathlib.Path(directory);value=copy.deepcopy(ssl_spec)
      for name in value['sourceFiles']:
          path=root/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(name)
          value['sourceFiles'][name]=hashlib.sha256(path.read_bytes()).hexdigest()
      py=root/'pyconfig.h';openssl=root/'opensslv.h'
      py.write_text("".join('#define '+name+' '+str(number)+'\n' for name,number in value['abiMacros'].items()))
      openssl.write_text("".join('# define OPENSSL_VERSION_'+name+' '+number+'\n'
          for name,number in zip(['MAJOR','MINOR','PATCH'],value['opensslVersion'].split('.'))))
      for name,path in [('python',py),('openssl',openssl)]:
          value['headers'][name]=hashlib.sha256(path.read_bytes()).hexdigest()
      guard['check'](value,root,py,openssl)
      for kind in ['schema','source','header','abi','openssl']:
          bad=copy.deepcopy(value)
          if kind=='schema':bad['schemaVersion']=0
          elif kind=='source':bad['sourceFiles']['Modules/_ssl.c']='0'*64
          elif kind=='header':bad['headers']['python']='0'*64
          elif kind=='abi':bad['abiMacros']['Py_GIL_DISABLED']=1
          else:bad['opensslVersion']='3.6.5'
          try:guard['check'](bad,root,py,openssl)
          except AssertionError:pass
          else:raise AssertionError('CALIBRE_SSL_GUARD_SEED:'+kind)
  recipe=pathlib.Path(sys.argv[2]).read_text()
  context=pathlib.Path(sys.argv[3])
  manifest=json.loads((context/'manifest.json').read_text())
  assert (context/'Dockerfile').read_text()==recipe
  ssl_context=context/'native-ssl';ssl_runtime=ssl['runtime'];ssl_runtime_spec=ssl_runtime['spec']
  assert json.loads((ssl_context/'spec.json').read_text())==ssl_runtime_spec
  assert ssl_runtime_spec['native']==ssl_spec
  assert hashlib.sha256((ssl_context/'guard.py').read_bytes()).hexdigest()==ssl_runtime_spec['guardSha256']
  ssl_api={'__name__':'test_ssl_installer'}
  exec(compile((ssl_context/'guard.py').read_bytes(),'<actual-ssl-installer>','exec',optimize=0),ssl_api)
  try:exec(compile((ssl_context/'guard.py').read_bytes(),'<optimized-ssl-guard>','exec',optimize=2),{'__name__':'test_optimized_ssl'})
  except AssertionError as error:assert str(error)=='CALIBRE_SSL_OPTIMIZED_GUARD'
  else:raise AssertionError('SSL_OPTIMIZED_GUARD_SEED')
  ssl_api['package'](ssl_runtime_spec,ssl_context)
  import shutil
  for kind in ['none','payload','source','mode','guard','proof','ca','needed','link']:
      with tempfile.TemporaryDirectory() as directory:
          root=pathlib.Path(directory);distribution=root/'calibre';inputs=root/'inputs'
          shutil.copytree(ssl_context,inputs);value=copy.deepcopy(ssl_runtime_spec)
          path=distribution/pathlib.Path(value['native']['original']['path']).relative_to(value['rootPath'])
          path.parent.mkdir(parents=True);path.write_bytes(b'owned-original-ssl');path.chmod(0o755)
          value['native']['original'].update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(),bytes=path.stat().st_size)
          cert=distribution/pathlib.Path(value['privateCa']['path']).relative_to(value['rootPath'])
          cert.parent.mkdir(parents=True);cert.write_bytes(b'owned-private-ca')
          value['privateCa']['sha256']=hashlib.sha256(cert.read_bytes()).hexdigest()
          incoming=inputs/'lib/_ssl.so'
          if kind=='payload':incoming.chmod(0o644);incoming.write_bytes(b'corrupt-payload')
          elif kind=='source':value['native']['original']['sha256']='0'*64
          elif kind=='mode':path.chmod(0o444)
          elif kind=='guard':(inputs/'guard.py').chmod(0o644);(inputs/'guard.py').write_bytes(b'corrupt-guard')
          elif kind=='proof':(distribution/value['proofDirectory']).mkdir()
          elif kind=='ca':value['privateCa']['sha256']='0'*64
          elif kind=='link':incoming.parent.chmod(0o755);incoming.unlink();incoming.symlink_to(path)
          metadata=json.loads((inputs/'manifest.json').read_text());metadata['descriptor']=value['native']
          if kind=='needed':metadata['file']['needed'].append('libpython3.14.so')
          (inputs/'manifest.json').chmod(0o644);(inputs/'manifest.json').write_text(json.dumps(metadata))
          before={str(p.relative_to(distribution)):(p.read_bytes(),p.stat().st_mode) for p in distribution.rglob('*') if p.is_file()}
          try:ssl_api['install'](value,inputs,distribution,inputs/'guard.py')
          except AssertionError:
              assert kind!='none',kind
              after={str(p.relative_to(distribution)):(p.read_bytes(),p.stat().st_mode) for p in distribution.rglob('*') if p.is_file()}
              assert after==before,'SSL_FAILED_INPUT_CHANGED_ORIGINAL:'+kind
          else:
              assert kind=='none','SSL_BAD_INPUT_ACCEPTED:'+kind
              ssl_api['installed'](value,distribution)
              path.write_bytes(b'corrupt-installed')
              try:ssl_api['installed'](value,distribution)
              except AssertionError:pass
              else:raise AssertionError('SSL_INSTALLED_HASH_SEED')
  assert manifest['schemaVersion']==1 and manifest['pythonVersion']==[3,14,8]
  assert manifest['frozenBundle']=='/opt/calibre/lib/calibre-extensions/python-lib.bypy.frozen'
  assert manifest['frozenBundleSha256']=='558037f93bef7df037ff1c38519680ed1083263b9e86b38407c4e819a2acffb2'
  assert manifest['selectionVariable']=='CALIBRE_DEVELOP_FROM' and manifest['rootPath']=='/opt/hwc-calibre-http'
  assert manifest['sourcePath']=='/tmp/hwc-calibre-http/client.py'
  raw=(context/'client.py').read_bytes()
  assert hashlib.sha256(raw).hexdigest()==manifest['sourceSha256']
  source=raw.decode()
  for old,new in manifest['replacements']:
      assert source.count(old)==1
      source=source.replace(old,new)
  assert hashlib.sha256(source.encode()).hexdigest()==manifest['patchedSha256']
  assert recipe.startswith('FROM lscr.io/linuxserver/calibre@sha256:b198fc03a6abc6be7e251a9958e50e74634b00e447c7b25e92c191c8077ba378\n')
  def commands(text):
      result=[]
      for line in text.splitlines():
          if not line.startswith('RUN ') or '/opt/calibre/calibre-debug' not in line: continue
          argv=shlex.split(line[4:]); at=argv.index('/opt/calibre/calibre-debug')
          assert argv[at+1]=='-c'
          module=ast.parse(argv[at+2]); invoke=module.body[-1].value
          assert isinstance(invoke,ast.Call) and invoke.func.id=='exec'
          compiler=invoke.args[0]
          assert compiler.func.id=='compile'
          optimize=next(x.value.value for x in compiler.keywords if x.arg=='optimize')
          body=ast.literal_eval(compiler.args[0])
          selected=json.loads(ast.literal_eval(module.body[1].value.elts[1]))
          result.append((body,optimize,selected))
      return result
  def wired(binding,text):
      wanted='localhost/calibre-runtime:9.17.0-http-framing-'+hashlib.sha256(text.encode()).hexdigest()[:12]
      emitted=commands(text)
      if len(emitted)!=2: return False
      builder=ast.parse(emitted[0][0]); verify=ast.parse(emitted[1][0])
      bootstraps=[ast.literal_eval(n.value) for n in builder.body if isinstance(n,ast.Assign)
          and any(isinstance(t,ast.Name) and t.id=='bootstrap' for t in n.targets)]
      gui=any(isinstance(n,ast.Import) and any(a.name=='calibre.gui2' for a in n.names) for n in verify.body)
      worker=any(isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='fork_job' for n in ast.walk(verify))
      def ssl_probe_wired(body):
          tree=ast.parse(body)
          definitions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='native_ssl_proof']
          calls=[n for n in ast.walk(tree) if isinstance(n,ast.Call) and isinstance(n.func,ast.Name) and n.func.id=='native_ssl_proof']
          if len(definitions)!=1 or len(calls)!=1:return False
          assignments=[n.value for n in ast.walk(definitions[0]) if isinstance(n,ast.Assign)
              and any(isinstance(t,ast.Name) and t.id=='spec' for t in n.targets)]
          return len(assignments)==1 and json.loads(ast.literal_eval(assignments[0].args[0]))==ssl_runtime_spec
      workers=[ast.literal_eval(n.value) for n in verify.body if isinstance(n,ast.Assign)
          and any(isinstance(t,ast.Name) and t.id=='worker' for t in n.targets)]
      ssl_copy='COPY native-ssl /tmp/hwc-calibre-native-ssl'
      ssl_install='RUN python3 -I -B /tmp/hwc-calibre-native-ssl/guard.py /tmp/hwc-calibre-native-ssl/spec.json /tmp/hwc-calibre-native-ssl '+ssl_runtime_spec['rootPath']
      stdlib_wiring=('COPY stdlib /tmp/hwc-calibre-stdlib' in text and 'FROZEN_STDLIB_SOURCE_CODE_DRIFT' in emitted[0][0] and 'CALIBRE_STDLIB_SELECTION' in emitted[1][0] and len(workers)==1 and 'CALIBRE_STDLIB_SELECTION' in workers[0])
      ssl_wiring=(ssl_copy in text and ssl_install in text and '# Native SSL inputs '+ssl_runtime['inputHash'] in text
          and text.index(ssl_copy)<text.index(ssl_install)<text.index('def native_ssl_proof')
          and ssl_probe_wired(emitted[1][0]) and len(workers)==1 and ssl_probe_wired(workers[0]))
      return (binding['selected']==binding['container']==wanted and binding['pull']=='never'
          and 'ENV '+manifest['selectionVariable']+'='+manifest['rootPath'] in text
          and all(x[1]==0 and x[2]==manifest for x in emitted)
          and len(bootstraps)==1 and hashlib.sha256(bootstraps[0].encode()).hexdigest()==manifest['bootstrapSha256']
          and gui and worker and ssl_wiring and stdlib_wiring)
  assert wired(v,recipe)
  for before,after in [('COPY stdlib /tmp/hwc-calibre-stdlib','# omitted stdlib copy'),
      ('FROZEN_STDLIB_SOURCE_CODE_DRIFT','omitted original parity'),
      ('CALIBRE_STDLIB_SELECTION','omitted stdlib consumers'),
      ('COPY native-ssl /tmp/hwc-calibre-native-ssl','# omitted SSL copy'),
      ('RUN python3 -I -B /tmp/hwc-calibre-native-ssl/guard.py','# omitted SSL installer'),
      ('native_ssl = native_ssl_proof()','native_ssl = None'),
      ('native_ssl_proof(),stdlib_proof())','None,stdlib_proof())')]:
      omitted=recipe.replace(before,after)
      assert omitted!=recipe
      # Rebind the selected image so this fails on its missing consumer wiring.
      rebound_ssl=copy.deepcopy(v)
      rebound_ssl['selected']=rebound_ssl['container']='localhost/calibre-runtime:9.17.0-http-framing-'+hashlib.sha256(omitted.encode()).hexdigest()[:12]
      assert not wired(rebound_ssl,omitted),'SSL_RUNTIME_WIRING_SEED:'+before
  def rebound(text):
      binding=copy.deepcopy(v)
      binding['selected']=binding['container']='localhost/calibre-runtime:9.17.0-http-framing-'+hashlib.sha256(text.encode()).hexdigest()[:12]
      return binding
  omitted=recipe.replace('ENV '+manifest['selectionVariable']+'='+manifest['rootPath'], '# omitted source selection')
  assert not wired(rebound(omitted),omitted)
  optimized=recipe.replace('optimize=0','optimize=2')
  assert not wired(rebound(optimized),optimized)
  for before,after in [('import calibre.gui2','pass # omitted GUI import'),
      ("actual = fork_job(worker,", "actual = omitted_worker(worker,")]:
      omitted=recipe.replace(before,after)
      assert omitted!=recipe and not wired(rebound(omitted),omitted)
  wrong=copy.deepcopy(v);wrong['container']='lscr.io/linuxserver/calibre@sha256:b198fc03a6abc6be7e251a9958e50e74634b00e447c7b25e92c191c8077ba378'
  assert not wired(wrong,recipe)
  assert ' image exists ' in v['preStart'] and v['selected'] in v['preStart']
  assert 'podman build' not in v['preStart']
  assert v['library'] + ':/books' in v['volumes']
  assert v['config'] + ':/config' in v['volumes']
  program=commands(recipe)[0][0]
  assert 'FROZEN_HTTP_SOURCE_CODE_DRIFT' in program
  import types
  shape_node=next(n for n in ast.parse(program).body if isinstance(n,ast.FunctionDef) and n.name=='shape')
  shapes={'types':types}
  exec(compile(ast.Module(body=[shape_node],type_ignores=[]),'<actual-source-parity>','exec'),shapes)
  nested=compile('value=1','<vendor-module>','exec',optimize=2)
  root_code=compile('pass','<same-root>','exec',optimize=2)
  vendor=root_code.replace(co_consts=((nested,),))
  source_code=root_code.replace(co_consts=((nested.replace(co_filename='<source-module>'),),))
  assert shapes['shape'](vendor)==shapes['shape'](source_code),'NESTED_CODE_FILENAME_PARITY'
  changed=root_code.replace(co_consts=((nested.replace(co_firstlineno=nested.co_firstlineno+1),),))
  assert shapes['shape'](vendor)!=shapes['shape'](changed),'NESTED_CODE_POSITION_DRIFT_ACCEPTED'
  bootstrap=next(ast.literal_eval(n.value) for n in ast.parse(program).body if isinstance(n,ast.Assign)
      and any(isinstance(t,ast.Name) and t.id=='bootstrap' for t in n.targets))
  # Execute the emitted bootstrap with an opaque frozen entry point. The
  # observer checks importer mode, precise selection and original site metadata.
  harness="""import sys,types
  class FrozenByteCodeLoader:
      def get_filename(self,name): return '/vendor/site.pyc'
      def get_code(self,name): return compile("def main(): return 'original-vendor-entry'",'/vendor/site.pyc','exec')
  class BypyFrozenImporter:
      develop_mode_path='/opt/hwc-calibre-http'
      def find_spec(self,name,path=None,target=None):
          if name=='site': return types.SimpleNamespace(loader=FrozenByteCodeLoader())
          return None
  importer=BypyFrozenImporter()
  sys.meta_path.insert(0,importer)
  namespace={'__name__':'__main__'}
  exec(compile(BOOTSTRAP,'<emitted-bootstrap>','exec',optimize=2),namespace)
  assert importer.develop_mode_path is None, 'MODE_NOT_RESTORED'
  assert namespace['__name__']=='__main__' and namespace['__file__']=='/vendor/site.pyc'
  assert namespace['main']()=='original-vendor-entry'
  assert namespace['__spec__'].loader is namespace['__loader__']
  finder=sys.meta_path[0]
  assert finder.find_spec('http.client').origin==ROOT+'/http/client.py', 'HTTP_SELECTION_MISSING'
  for name in LIBRARIES:
      assert finder.find_spec(name).origin==ROOT+'/'+LIBRARIES[name]['file'], 'STDLIB_SELECTION_MISSING'
  assert finder.find_spec('calibre') is None and finder.find_spec('urllib.request') is None
  """
  for variant,source in [('actual',bootstrap),
      ('develop-mode',bootstrap.replace('importer.develop_mode_path = None','pass')),
      ('selection',bootstrap.replace('source_modules.get(fullname)', 'source_modules.get("missing.client")')),
      ('vendor-entry',bootstrap.replace("exec(original.loader.get_code('site'), namespace)",'pass'))]:
      with tempfile.TemporaryDirectory() as directory:
          root=pathlib.Path(directory);(root/'http').mkdir()
          # The table contains the patched HTTP source, not its original input.
          patched=raw.decode()
          for old,new in manifest['replacements']: patched=patched.replace(old,new)
          (root/'http/client.py').write_text(patched)
          for entry in stdlib_spec['modules'].values():
              (root/entry['file']).write_bytes((stdlib_package/'lib'/entry['file']).read_bytes())
          body=source.replace(manifest['rootPath'],str(root))
          test=harness.replace('BOOTSTRAP',repr(body)).replace('ROOT',repr(str(root))).replace('LIBRARIES',repr(stdlib_spec['modules']))
          result=subprocess.run([sys.executable,'-c',test],capture_output=True,timeout=10)
      assert (result.returncode==0)==(variant=='actual'), (variant,result.stderr)
      if variant!='actual': assert b'AssertionError' in result.stderr or b'KeyError' in result.stderr or b'AttributeError' in result.stderr
  sha=lambda b:hashlib.sha256(b).hexdigest()
  for kind,code in [('source','FROZEN_HTTP_SOURCE_DRIFT'),('result','FROZEN_HTTP_RESULT_DRIFT'),
      ('hunk','FROZEN_HTTP_HUNK_DRIFT'),('bound','FROZEN_HTTP_SOURCE_BOUND'),('bundle','FROZEN_HTTP_ARCHIVE_DRIFT')]:
      with tempfile.TemporaryDirectory() as d:
          root=pathlib.Path(d); original=root/'client.py'; archive=root/'bundle'; output=root/'selected'
          original.write_bytes(b'sentinel=1\n');archive.write_bytes(b'fixture-bundle')
          spec=copy.deepcopy(manifest)
          spec.update(sourcePath=str(original),sourceSha256=sha(original.read_bytes()),
              patchedSha256=sha(b'sentinel=2\n'),replacements=[['sentinel=1','sentinel=2']],
              frozenBundle=str(archive),frozenBundleSha256=sha(archive.read_bytes()),rootPath=str(output))
          if kind=='source':spec['sourceSha256']='0'*64
          elif kind=='result':spec['patchedSha256']='0'*64
          elif kind=='hunk':spec['replacements']=[['missing-sentinel','sentinel=2']]
          elif kind=='bound':original.write_bytes(b'x'*262145)
          elif kind=='bundle':spec['frozenBundleSha256']='0'*64
          before=original.read_bytes()
          def execute(optimize):
              command='import sys;sys.argv='+repr(['fixture',json.dumps(spec)])+';exec(compile('+repr(program)+',"<frozen-http>","exec",optimize='+str(optimize)+'),{"__name__":"__main__"})'
              return subprocess.run([sys.executable,'-OO','-c',command],capture_output=True,timeout=10)
          result=execute(0)
          assert result.returncode!=0 and code.encode() in result.stderr,kind
          assert not output.exists() and original.read_bytes()==before,'PARTIAL_FROZEN_WRITE:'+kind
          if kind=='source':
              seeded=execute(2)
              assert seeded.returncode!=0 and b'FROZEN_STDLIB_OPTIMIZED_INSTALLER' in seeded.stderr and not output.exists(),'OPTIMIZED_INSTALLER_ACCEPTED'
  # Native metadata, actual portable bytes and the production command order
  # share the canonical Calibre producer. The fault fixtures below touch only
  # disposable fake libraries, never a vendor or application data directory.
  import runpy
  native_dir = context / 'native'
  native_spec = json.loads((native_dir / 'spec.json').read_text())
  native_source = (native_dir / 'guard.py').read_text()
  native = v['native']
  assert native['schemaVersion'] == 1 and native['descriptor'] == native_spec
  backports = native_spec['securityBackports']
  source_spec = json.loads(pathlib.Path(v['nativeSourceSpec']).read_text())
  assert all(backports[key] == value for key, value in source_spec.items())
  assert backports['schemaVersion'] == 1 and len(backports['commits']) == 25
  assert len(backports['advisories']) == 21 and len(backports['sourceSha256']) >= 20
  assert v['nativePatchFlags'] == ['-p1','--fuzz=0'] and v['nativePatchCount'] == 27
  def source_wired(text):
      return v['nativeSourceGuard'] + ' ' + v['nativeSourceSpec'] + ' .' in text
  assert source_wired(v['nativePostPatch'])
  omitted = v['nativePostPatch'].replace(v['nativeSourceGuard'], '/omitted-source-guard')
  assert omitted != v['nativePostPatch'] and not source_wired(omitted)
  with tempfile.TemporaryDirectory() as source_temp:
      root = pathlib.Path(source_temp)
      fake = root / 'lib.c'; fake.write_bytes(b'qualified source')
      spec_file = root / 'spec.json'
      good = {'schemaVersion':1,'sourceRevision':backports['sourceRevision'],
          'sourceSha256':{'lib.c':hashlib.sha256(fake.read_bytes()).hexdigest()}}
      spec_file.write_text(json.dumps(good))
      command = [sys.executable,'-I','-B',v['nativeSourceGuard'],str(spec_file),str(root)]
      subprocess.run(command,check=True,capture_output=True,timeout=10)
      for kind in ['schema','revision','empty','path','missing','hash']:
          bad = copy.deepcopy(good)
          if kind == 'schema': bad['schemaVersion'] = 2
          elif kind == 'revision': bad['sourceRevision'] = 'unknown'
          elif kind == 'empty': bad['sourceSha256'] = {}
          elif kind == 'path': bad['sourceSha256']['../escape.c'] = bad['sourceSha256'].pop('lib.c')
          elif kind == 'missing': bad['sourceSha256']['missing.c'] = bad['sourceSha256'].pop('lib.c')
          elif kind == 'hash': bad['sourceSha256']['lib.c'] = '0' * 64
          spec_file.write_text(json.dumps(bad))
          result = subprocess.run(command,capture_output=True,timeout=10)
          assert result.returncode != 0 and fake.read_bytes() == b'qualified source', kind
      spec_file.write_text(json.dumps(good))
      result = subprocess.run([sys.executable,'-OO',v['nativeSourceGuard'],str(spec_file),str(root)],capture_output=True,timeout=10)
      assert result.returncode != 0 and b'CALIBRE_NATIVE_SOURCE_OPTIMIZED' in result.stderr
      assert len(v['contextTransforms']) == 3
      for transform in v['contextTransforms']:
          # Exercise the emitted builder program, including its real inputs.
          command_text = transform['command']
          args = shlex.split(command_text.splitlines()[0])
          assert args[:4] == ['python3','-I','-B','-']
          program = command_text.split("<<'PYPATCH'\n",1)[1].split('\nPYPATCH',1)[0]
          ast.parse(program)
          source = root / 'upstream.patch'; source.write_bytes(pathlib.Path(args[4]).read_bytes())
          edits = root / 'edits.json'; original_edits = json.loads(pathlib.Path(args[5]).read_text())
          output = root / 'result.patch'
          command = [sys.executable,'-I','-B','-',str(source),str(edits),str(output)]
          edits.write_text(json.dumps(original_edits))
          subprocess.run(command,input=program.encode(),check=True,capture_output=True,timeout=10)
          assert output.read_bytes() == pathlib.Path(transform['path']).read_bytes()
          for bad in [[], [['absent hunk','replacement']], [[original_edits[0][0],""]]]:
              edits.write_text(json.dumps(bad)); output.write_bytes(b'unchanged')
              result = subprocess.run(command,input=program.encode(),capture_output=True,timeout=10)
              assert result.returncode != 0 and output.read_bytes() == b'unchanged'
          edits.write_text(json.dumps(original_edits)); output.write_bytes(b'unchanged')
          result = subprocess.run([sys.executable,'-OO','-',str(source),str(edits),str(output)],input=program.encode(),capture_output=True,timeout=10)
          assert result.returncode != 0 and b'FFMPEG_CONTEXT_OPTIMIZED' in result.stderr and output.read_bytes() == b'unchanged'
  input_hash = hashlib.sha256(((native_dir / 'spec.json').read_text() + native_source + native['bundleInput']).encode()).hexdigest()
  assert input_hash == native['inputHash']
  api = runpy.run_path(str(native_dir / 'guard.py'))
  native_manifest = api['package'](native_spec, native_dir)
  for name, entry in native_manifest['files'].items():
      library = native_dir / 'lib' / name
      def elf(flag): return subprocess.check_output(['patchelf',flag,str(library)],text=True).strip()
      assert elf('--print-soname') == entry['soname']
      assert elf('--print-rpath') == entry['rpath']
      assert elf('--print-needed').splitlines() == entry['needed']
  def native_wired(text):
      marker = '# Native inputs ' + input_hash
      lines = ['RUN python3 -I -B /tmp/hwc-calibre-native/guard.py ' + native_spec['commands'][mode]
          + ' /tmp/hwc-calibre-native/spec.json /tmp/hwc-calibre-native /opt/calibre/lib /opt/calibre/lib'
          for mode in ['verify','apply','installed']]
      if marker not in text or 'COPY native /tmp/hwc-calibre-native' not in text: return False
      if not all(text.count(line) == 1 for line in lines): return False
      return (text.index('COPY native /tmp/hwc-calibre-native') < text.index(lines[0]) < text.index(lines[1])
          < text.index(lines[2]) < text.index('RUN ', text.index(lines[2]) + len(lines[2])))
  assert native_wired(recipe)
  for omitted_mode in ['verify','apply','installed']:
      omitted = recipe.replace('/guard.py ' + native_spec['commands'][omitted_mode] + ' ', '/guard.py omitted ')
      assert omitted != recipe and not native_wired(omitted), omitted_mode
  for before, after in [('# Native inputs ' + input_hash, '# omitted native identity'),
      ('COPY native /tmp/hwc-calibre-native', '# omitted native copy')]:
      omitted = recipe.replace(before, after)
      assert omitted != recipe and not native_wired(omitted)
  optimized = subprocess.run([sys.executable,'-OO',str(native_dir / 'guard.py')],capture_output=True,timeout=10)
  assert optimized.returncode != 0 and b'CALIBRE_NATIVE_OPTIMIZED_GUARD' in optimized.stderr
  import copy
  import hashlib
  import json
  from pathlib import Path
  import runpy
  import stat
  import sys
  import tempfile

  guard, spec_file = native_dir / 'guard.py', native_dir / 'spec.json'
  api = runpy.run_path(str(guard))
  original_spec = json.loads(spec_file.read_text())
  sha = lambda raw: hashlib.sha256(raw).hexdigest()
  cases = []
  for kind in ["positive", "schema", "descriptor", "missing-second", "corrupt-second",
               "source-hash", "source-mode", "unexpected", "link", "manifest-link",
               "path", "soname", "rpath", "dependency", "minimum-version",
               "candidate-version", "feature-loss", "installed-hash", "snapshot", "dependency-alias"]:
      with tempfile.TemporaryDirectory() as name:
          folder = Path(name)
          root, inputs = folder / "installed", folder / "inputs"
          root.mkdir(); (inputs / "lib").mkdir(parents=True)
          spec = copy.deepcopy(original_spec)
          files = {}
          for i, (name, entry) in enumerate(spec["libraries"].items()):
              old, new = ("old-" + name).encode(), ("new-" + name).encode()
              (root / name).write_bytes(old); (root / name).chmod(entry["sourceMode"])
              entry["sourceSha256"] = sha(old)
              (inputs / "lib" / name).write_bytes(new)
              files[name] = dict(sha256=sha(new), bytes=len(new), soname=name,
                                 rpath="$ORIGIN", needed=list(entry["needed"]))
          (root / "unrelated-library").write_bytes(b"preserved")
          second = list(files)[1]
          manifest = dict(schemaVersion=1, descriptor=copy.deepcopy(spec), files=files)
          if kind == "schema": manifest["schemaVersion"] = 2
          elif kind == "descriptor": manifest["descriptor"]["version"] = "8.1.0"
          elif kind == "missing-second": (inputs / "lib" / second).unlink()
          elif kind == "corrupt-second": (inputs / "lib" / second).write_bytes(b"wrong")
          elif kind == "source-hash": (root / second).write_bytes(b"changed source")
          elif kind == "source-mode": (root / second).chmod(0o644)
          elif kind == "unexpected": (inputs / "lib" / "extra").write_bytes(b"extra")
          elif kind == "link":
              path = inputs / "lib" / second
              path.rename(inputs / "link-target"); path.symlink_to(inputs / "link-target")
          elif kind == "path":
              item = manifest["files"].pop(second); manifest["files"]["../" + second] = item
          elif kind == "soname": files[second]["soname"] = "wrong.so.1"
          elif kind == "rpath": files[second]["rpath"] = "/nix/store/not-portable"
          elif kind == "dependency": files[second]["needed"].append("libunexpected.so.1")
          elif kind == "minimum-version":
              spec["minimumVersion"] = "7.1.6"; manifest["descriptor"] = copy.deepcopy(spec)
          elif kind == "dependency-alias":
              spec["dependencyAliases"] = {"libbz2.so.1": "libunexpected.so.1"}
              manifest["descriptor"] = copy.deepcopy(spec)
          (inputs / "manifest.json").write_text(json.dumps(manifest))
          if kind == "manifest-link":
              (inputs / "manifest.json").rename(inputs / "manifest-real.json")
              (inputs / "manifest.json").symlink_to(inputs / "manifest-real.json")
          before = {p.name: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode)) for p in root.iterdir()}
          reads = []
          def feature_reader(path):
              installed = (path / second).read_bytes().startswith(b"new-")
              reads.append(str(path))
              version = spec["version"] if installed else spec["sourceVersion"]
              feature = ["old-feature", "extra-feature"] if installed else ["old-feature"]
              if installed and kind == "candidate-version": version = "7.1.4"
              if installed and kind == "feature-loss": feature = ["extra-feature"]
              return dict(version=version, features={"decoders": feature})
          error = None
          try: api["apply"](spec, inputs, root, feature_reader)
          except (AssertionError, FileNotFoundError) as caught: error = str(caught)
          should_pass = kind in ["positive", "installed-hash", "snapshot"]
          assert (error is None) == should_pass, (kind, error)
          expected = {"schema": "CALIBRE_NATIVE_SCHEMA", "descriptor": "CALIBRE_NATIVE_DESCRIPTOR",
                      "source-hash": "CALIBRE_NATIVE_SOURCE_HASH", "source-mode": "CALIBRE_NATIVE_SOURCE_MODE",
                      "soname": "CALIBRE_NATIVE_ABI_RPATH", "rpath": "CALIBRE_NATIVE_ABI_RPATH",
                      "dependency": "CALIBRE_NATIVE_DEPENDENCY", "minimum-version": "CALIBRE_NATIVE_VERSION",
                      "candidate-version": "CALIBRE_NATIVE_SELECTED_VERSION", "feature-loss": "CALIBRE_NATIVE_FEATURE_LOST:decoders",
                      "dependency-alias": "CALIBRE_NATIVE_DEPENDENCY_ALIAS"}
          if kind in expected: assert error == expected[kind], (kind, error)
          if not should_pass:
              after = {p.name: (p.read_bytes(), stat.S_IMODE(p.stat().st_mode)) for p in root.iterdir()}
              assert before == after, "PARTIAL_NATIVE_WRITE:" + kind
              assert not (inputs / spec["snapshotFile"]).exists(), "EARLY_SNAPSHOT:" + kind
          else:
              assert len(reads) == 3 and reads[0] == reads[2], reads
              assert (root / "unrelated-library").read_bytes() == b"preserved"
              api["verify_installed"](spec, inputs, root, feature_reader)
              if kind == "installed-hash": (root / second).write_bytes(b"wrong")
              if kind == "snapshot":
                  snapshot = inputs / spec["snapshotFile"]
                  content = json.loads(snapshot.read_text()); content["descriptorSha256"] = "0" * 64
                  snapshot.write_text(json.dumps(content))
              if kind != "positive":
                  try: api["verify_installed"](spec, inputs, root, feature_reader)
                  except AssertionError: pass
                  else: raise AssertionError("INSTALLED_DRIFT_ACCEPTED:" + kind)
          cases.append(kind)
  assert api["dependency_order"]({"second": {"needed": ["first"]}, "first": {"needed": []}}) == ["first", "second"]
  try: api["dependency_order"]({"first": {"needed": ["second"]}, "second": {"needed": ["first"]}})
  except AssertionError: pass
  else: raise AssertionError("DEPENDENCY_CYCLE_ACCEPTED")
  print(json.dumps({"schemaVersion": 1, "state": "pass", "cases": cases,
                    "allRejectedInputsPreserveInstalledBytesAndModes": True,
                    "disposableFixtureRemoved": True}))
  print('actual Calibre recipe/context/selection and optimized-launcher drift guards pass; actual image consumer remains a runtime qualification')
  PYTEST
  touch "$out"
'';

seerr-security-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  binding = pkgs.writeText "seerr-security-binding.json" (builtins.toJSON {
    selected = c.hwc.media.jellyseerr.image;
    container = c.virtualisation.oci-containers.containers.jellyseerr.image;
  });
in pkgs.runCommand "seerr-security-wiring" { nativeBuildInputs = [ pkgs.python3 pkgs.nodejs ]; } ''
  python3 - ${binding} ${c.system.build.seerrRuntimeImageRecipe} ${c.system.build.seerrRuntimeImageContext} ${c.system.build.seerrRequestPermissions} <<'PYTEST'
  import hashlib, json, pathlib, subprocess, sys
  binding = json.loads(pathlib.Path(sys.argv[1]).read_text())
  recipe = pathlib.Path(sys.argv[2]).read_text()
  context = pathlib.Path(sys.argv[3]); producer = pathlib.Path(sys.argv[4]).read_text()
  manifest = json.loads((context / 'manifest.json').read_text())
  patcher = (context / 'apply-backports.cjs').read_text()
  sha = lambda value: hashlib.sha256(value.encode()).hexdigest()
  assert (context / 'Dockerfile').read_text() == recipe, 'context bypasses recipe'
  assert binding['selected'] == binding['container'] == 'localhost/seerr-runtime:3.1.0-node22.23.4-' + sha(recipe)[:12], 'container bypasses security recipe'
  assert binding['selected'] in producer, 'permission vocabulary uses a different image'
  assert 'COPY --chown=node:node . /tmp/hwc-seerr/' in recipe and '&& node /tmp/hwc-seerr/apply-backports.cjs &&' in recipe, 'image bypasses security backports'
  assert sha(recipe.split('# Security backports', 1)[0].replace(' AS seerr-base', "")) == 'b9482a37e259fcd93442be29ae2b1cfce0653bc5e738e68fab403a84297953ea', 'unrelated base image change'
  canonical = json.dumps(manifest, separators=(',', ':'), sort_keys=True)
  assert '# Security backports ' + sha(canonical + patcher) in recipe, 'backport inputs not bound to image'
  assert manifest['schemaVersion'] == 1
  assert 'RUN apk verify ' in recipe and 'apk --repositories-file /dev/null --no-network --no-cache add ' in recipe, 'image bypasses signed offline native update'
  assert recipe.rstrip().endswith('USER node:node'), 'native build leaves runtime root'
  assert {p['name']: p['version'] for p in manifest['apks']} == {'libcrypto3':'3.5.9-r0', 'libssl3':'3.5.9-r0', 'musl':'1.2.5-r13', 'musl-utils':'1.2.5-r13', 'zlib':'1.3.2-r1'}
  import base64
  for package in manifest['apks']:
      assert package['url'].startswith('https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/')
      archive = context / package['file']
      assert 'sha256-' + base64.b64encode(hashlib.sha256(archive.read_bytes()).digest()).decode() == package['hash'], 'context archive drift'
      assert recipe.count('/tmp/hwc-seerr/' + package['file']) == 2, 'native input bypasses verify or install'
  assert set(manifest['advisories']) == {'GHSA-mc6w-69r3-62h8', 'GHSA-8j73-j6rc-q8xh', 'GHSA-xc6j-6p6h-p799', 'GHSA-c4j6-fc7j-m34r'}
  assert set(manifest['backports']) == {'dist/lib/imageproxy.js', 'dist/entity/User.js', 'dist/entity/Media.js', 'dist/routes/auth.js', 'dist/routes/movie.js', 'dist/routes/tv.js', 'node_modules/next/dist/server/lib/router-server.js'}, 'schema or unrelated app change'
  next_spec = manifest['backports']['node_modules/next/dist/server/lib/router-server.js']
  assert next_spec['patchedSha256'] == 'bf28825f0722216ac23dfdee8fa74f594867996d48fbadc592427a3f6eb49f6c', 'Next upstream routing repair missing'
  assert len(next_spec['replacements']) == 2
  for spec in manifest['backports'].values():
      assert len(spec['sourceSha256']) == len(spec['patchedSha256']) == 64 and spec['sourceSha256'] != spec['patchedSha256']
      assert spec['replacements'] and all(len(pair) == 2 and pair[0] != pair[1] for pair in spec['replacements'])
  assert 'SEERR_BACKPORT_SOURCE_MISMATCH' in patcher and 'SEERR_BACKPORT_RESULT_MISMATCH' in patcher and 'SEERR_BACKPORT_HUNK_MISMATCH' in patcher
  subprocess.run(['node', '--check', str(context / 'apply-backports.cjs')], check=True)
  dependencies = json.loads((context / 'dependencies/dependencies.json').read_text())
  builder = (context / 'dependencies/build.cjs').read_text()
  canonical = json.dumps(dependencies, separators=(',', ':'), sort_keys=True)
  assert '# Frozen dependency inputs ' + sha(canonical + builder) in recipe, 'resolver source bypasses image identity'
  assert dependencies['schemaVersion'] == 1 and dependencies['lock']['lockfileVersion'] == '9.0'
  assert dependencies['package']['version'] == '3.1.0' and dependencies['package']['dependencies']['typeorm'] == '0.3.28'
  assert dependencies['package']['dependencies']['next'] == '15.5.29'
  assert dependencies['package']['dependencies']['sharp'] == '0.35.5'
  assert dependencies['package']['dependencies']['nodemailer'] == '10.3.1'
  assert len(dependencies['lock']['packages']) <= 2500
  assert all(item['resolution'].get('integrity', "").startswith('sha512-') for item in dependencies['lock']['packages'].values()), 'unbound registry input'
  def wired(text):
      return all(part in text for part in [
          'FROM seerr-base AS dependency-builder',
          'RUN --network=none node /tmp/hwc-seerr-dependencies/build.cjs compile /app /tmp/hwc-seerr-native',
          'COPY --from=dependency-builder --chown=node:node /app/node_modules /app/node_modules',
          'COPY --from=dependency-builder --chown=node:node /app/.next /app/.next',
          'COPY --from=dependency-builder --chown=node:node /app/package.json /app/pnpm-lock.yaml /app/'])
  assert wired(recipe)
  assert not wired(recipe.replace('RUN --network=none node ', 'RUN node ')), 'compiler network seed did not fail'
  assert not wired(recipe.replace('COPY --from=dependency-builder --chown=node:node /app/node_modules /app/node_modules', "")), 'runtime copy seed did not fail'
  assert '--frozen-lockfile' in builder and '--ignore-scripts' in builder and "['--prod','--offline']" in builder
  assert 'SEERR_NATIVE_SOURCE' in builder and 'SEERR_NATIVE_ABI' in builder and 'SEERR_MAIL_TYPE_PATCH' in builder
  assert 'build.cjs strip-tools /app /tmp/hwc-seerr-native' in recipe
  assert 'ENV NODE_ENV=production' in recipe and 'CMD ["node", "dist/index.js"]' in recipe
  subprocess.run(['node', '--check', str(context / 'dependencies/build.cjs')], check=True)
  print('production image, base parity, app and Next security context and app-owned permission wiring pass')
  PYTEST
  touch "$out"
'';

seerr-settings-preservation = let
  secret = name: value: pkgs.writeText "seerr-fixture-${name}" value;
  original = {
    "jellyfin-api-key" = secret "jellyfin" "fixture-jellyfin\n";
    "radarr-api-key" = secret "radarr" "fixture-radarr\n";
    "sonarr-api-key" = secret "sonarr" "fixture-sonarr\n";
  };
  generator = secrets: (import (repoRoot + "/domains/media/jellyseerr/parts/settings.nix") {
    inherit pkgs;
    config.hwc.secrets.api = secrets;
  }).generateSettingsScript;
  rotated = original // { "radarr-api-key" = secret "radarr-rotated" "fixture-rotated\n"; };
  empty = original // { "sonarr-api-key" = secret "empty" ""; };
  missing = original // { "sonarr-api-key" = "/no-such-seerr-fixture-secret"; };
  home = self.nixosConfigurations.hwc-home;
  liveGenerator = (import (repoRoot + "/domains/media/jellyseerr/parts/settings.nix") {
    inherit (home) pkgs;
    inherit (home) config;
  }).generateSettingsScript;
  liveProducer = home.config.system.build.seerrRequestPermissions;
  liveUpdater = home.config.system.build.seerrUserPermissions;
  preStart = pkgs.writeText "seerr-production-prestart" home.config.systemd.services.podman-jellyseerr.preStart;
in pkgs.runCommand "seerr-settings-preservation" {
  nativeBuildInputs = [ pkgs.python3 pkgs.jq pkgs.coreutils ];
} ''
  python3 - ${generator original} ${generator rotated} ${generator empty} ${generator missing} ${preStart} ${liveGenerator} ${liveProducer} ${liveUpdater} <<'PYTEST'
  import hashlib, json, pathlib, re, subprocess, sys, tempfile
  original, rotated, empty, missing, prestart, live, producer, updater = sys.argv[1:]
  startup = pathlib.Path(prestart).read_text()
  helpers = re.findall(r'/nix/store/[^\s]+jellyseerr-ensure-settings', pathlib.Path(prestart).read_text())
  assert len(helpers) == 1 and live in pathlib.Path(helpers[0]).read_text(), 'production preStart bypasses settings owner'
  ensure = pathlib.Path(helpers[0]).read_text()
  assert startup.count(producer) == 1, 'production bypasses app-owned permission vocabulary'
  assert startup.index(producer) < startup.index(helpers[0]) < startup.index(updater), 'permissions resolve after persistent writes'
  assert re.search(re.escape(helpers[0]) + r' "\$permissionMask"', startup), 'settings bypasses shared mask'
  assert re.search(re.escape(updater) + r' "\$permissionMask"', startup), 'SQL bypasses shared mask'
  assert live + ' "' in ensure and '"$1"' in ensure, 'generator bypasses shared mask'
  assert 'install -d -m 0700' in ensure and 'chmod 0600' in ensure, 'settings privacy lost'
  seed = {'main': {'apiKey': 'keep-api', 'localLogin': True, 'clientSetting': 'keep-main'},
          'clientId': 'keep-client', 'vapidPrivate': 'keep-private', 'vapidPublic': 'keep-public',
          'network': {'proxy': 'keep-network'}, 'migrations': {'fixture': True},
          'jellyfin': {'libraries': [{'id': 'fixture-library', 'enabled': True}]},
          'radarr': [{'id': 0, 'hostname': 'old-host', 'appOwnedOption': 'keep-radarr'}, {'id': 9, 'hostname': 'undeclared'}],
          'sonarr': [{'id': 0, 'appOwnedOption': 'keep-sonarr'}]}
  def run(script, target, *mask):
      return subprocess.run([script, str(target), *mask], capture_output=True, text=True, timeout=5)
  def preserved(value, mask=160):
      for key in ['clientId', 'vapidPrivate', 'vapidPublic', 'network', 'migrations']:
          assert value.get(key) == seed[key], 'lost app-owned ' + key
      assert value['main']['apiKey'] == 'keep-api' and value['main']['clientSetting'] == 'keep-main'
      assert value['jellyfin']['libraries'] == seed['jellyfin']['libraries']
      assert value['radarr'][0]['appOwnedOption'] == 'keep-radarr'
      assert value['sonarr'][0]['appOwnedOption'] == 'keep-sonarr'
      assert value['main']['localLogin'] is False and value['main']['defaultPermissions'] == mask
      assert value['jellyfin']['apiKey'] == 'fixture-jellyfin'
      assert [v['id'] for v in value['radarr']] == [0] and value['radarr'][0]['hostname'] == 'radarr'
  with tempfile.TemporaryDirectory() as root:
      target = pathlib.Path(root) / 'settings.json'
      target.write_text(json.dumps(seed))
      assert run(original, target, '160').returncode == 0
      preserved(json.loads(target.read_text()))
      first = target.read_bytes()
      assert run(original, target, '160').returncode == 0 and target.read_bytes() == first, 'reconciliation is not idempotent'
      assert run(rotated, target, '160').returncode == 0
      value = json.loads(target.read_text()); preserved(value)
      assert value['radarr'][0]['apiKey'] == 'fixture-rotated', 'rotation was ignored'
      for bad in [empty, missing]:
          before = target.read_bytes()
          assert run(bad, target, '160').returncode != 0 and target.read_bytes() == before, 'failed secret damaged old settings'
      for args in [(), ("",), ('0',), ('-1',), ('1;SELECT 1',), ('01',), ('2147483648',), ('999999999999999999999',)]:
          before = target.read_bytes()
          assert run(original, target, *args).returncode != 0 and target.read_bytes() == before, 'invalid mask damaged old settings'
      assert run(original, target, '32').returncode == 0
      preserved(json.loads(target.read_text()), mask=32)
      assert target.stat().st_mode & 0o777 == 0o600, 'settings file is not private'
      target.write_text('{malformed')
      before = target.read_bytes()
      assert run(original, target, '160').returncode != 0 and target.read_bytes() == before, 'malformed settings were overwritten'
      assert sorted(p.name for p in pathlib.Path(root).iterdir()) == ['settings.json'], 'temporary files leaked'
      target.unlink()
      assert run(original, target, '160').returncode == 0
      fresh = json.loads(target.read_text())
      assert fresh['main']['initialized'] and fresh['main']['defaultPermissions'] == 160
  print('production wiring, preservation, ownership, rotation, atomic failures and bootstrap pass')
  PYTEST
  touch "$out"
'';

sonarr-runtime-wiring = let
  c = self.nixosConfigurations.hwc-home.config;
  binding = pkgs.writeText "sonarr-runtime-binding.json" (builtins.toJSON {
    image = c.virtualisation.oci-containers.containers.sonarr.image;
    pull = c.virtualisation.oci-containers.containers.sonarr.pull;
    ports = c.virtualisation.oci-containers.containers.sonarr.ports;
    volumes = c.virtualisation.oci-containers.containers.sonarr.volumes;
    context = c.system.build.sonarrRuntimeImageContext;
  });
in pkgs.runCommand "sonarr-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${binding} <<'PY'
  import json,hashlib,pathlib,sys
  b=json.loads(pathlib.Path(sys.argv[1]).read_text());context=pathlib.Path(b['context'])
  recipe=(context/'Dockerfile').read_text()
  def valid(binding):
    return binding['image'].startswith('localhost/sonarr-runtime:') and binding['image'].endswith('-'+hashlib.sha256(recipe.encode()).hexdigest()[:12]) and binding['pull']=='never'
  assert valid(b)
  assert not valid(dict(b,image='lscr.io/linuxserver/sonarr:latest'))
  assert not valid(dict(b,pull='missing'))
  assert b['ports']==['127.0.0.1:8989:8989']
  assert len(b['volumes'])==3 and all(any(v.endswith(':'+p) for v in b['volumes']) for p in ['/config','/tv','/downloads'])
  script=(context/'apply-runtime.sh').read_text()
  assert 'comm -12 /tmp/runtime-owned.txt /tmp/app-owned.txt' in script
  assert 'sha256sum -c -' in script
  assert 'includedFrameworks' in script and 'frameworks' in script
  packages=json.loads((context/'manifest.json').read_text())
  assert packages
  def valid_payload(data, expected): return hashlib.sha256(data).hexdigest()==expected
  for p in packages:
    data=(context/(p['name']+'.dll')).read_bytes()
    assert valid_payload(data,p['dllSha256'])
    assert not valid_payload(data+b'violation',p['dllSha256'])
  assert 'sha256sum -c -' in script and '--slurpfile packages manifest.json' in script
  native=(context/'libsqlite3.so.0').read_bytes()
  assert native.startswith(b'\x7fELF')
  expected=(context/'sqlite-sha256').read_text().strip()
  assert valid_payload(native,expected) and not valid_payload(native+b'violation',expected)
  assert (context/'sqlite-version').read_text().strip()
  assert 'del sqlite-libs' in script and 'cp libsqlite3.so.0 /usr/lib/libsqlite3.so.0' in script
  hashes=dict(line.split()[::-1] for line in (context/'utilities-sha256').read_text().splitlines())
  assert set(hashes)=={'busybox','uniq','unexpand'}
  for name,expected in hashes.items():
    data=(context/name).read_bytes()
    assert data.startswith(b'\x7fELF') and valid_payload(data,expected)
    assert not valid_payload(data+b'violation',expected)
  assert 'sha256sum -c utilities-sha256' in script
  assert 'for name in busybox uniq unexpand' in script
  assert 'install -m 0755 "$name" "$target.hwc-new"' in script and 'mv -fT "$target.hwc-new" "$target"' in script
  PY
  touch "$out"
'';
frigate-contract = let
  server = self.nixosConfigurations.hwc-home.config;
  frigate = server.hwc.media.frigate;
  fixture = pkgs.writeText "frigate-contract.json" (builtins.toJSON {
    settings = frigate._settings;
    inherit (frigate) port;
    configTemplate = frigate._configTemplate;
    configScript = server.systemd.services.frigate-config.script;
    credentials = server.systemd.services.frigate-config.serviceConfig.LoadCredential;
    inherit (server.systemd.services.podman-frigate) requires restartTriggers;
    inherit (server.virtualisation.oci-containers.containers.frigate) ports volumes extraOptions;
    startupTimeout = server.systemd.services.podman-frigate.serviceConfig.TimeoutStartSec;
    exporterPresent = server.virtualisation.oci-containers.containers ? frigate-exporter;
    scrapes = server.hwc.monitoring.prometheus.scrapeConfigs;
    rules = import (repoRoot + "/domains/monitoring/prometheus/parts/alerts.nix") { inherit lib; };
    # Exported for the central Prometheus (another host since wave 3).
    configurationRules = server.hwc.monitoring.prometheus.rules;
  });
in pkgs.runCommand "frigate-contract" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.onnx p.pillow ])) pkgs.prometheus.cli ];
} ''
  python3 ${(repoRoot + "/domains/media/frigate/parts/test_config.py")} ${fixture} ${(repoRoot + "/domains/media/frigate/parts/labelmap.py")}
  touch $out
'';

xps-media-readiness = let
  peer = self.nixosConfigurations.hwc-xps.config;
  service = peer.systemd.services.jellyfin;
  readiness = peer.systemd.services.xps-media-ready or {};
  preflight = readiness.script or "";
  encoding = (builtins.head service.restartTriggers).text;
  homeEncoding = (builtins.head self.nixosConfigurations.hwc-home.config.systemd.services.jellyfin.restartTriggers).text;
  fixture = pkgs.writeText "xps-media-readiness.json" (builtins.toJSON {
    script = builtins.unsafeDiscardStringContext preflight;
    zpool = builtins.unsafeDiscardStringContext "${peer.boot.zfs.package}/bin/zpool";
    pool = builtins.head peer.boot.zfs.extraPools;
  });
in
assert lib.assertMsg (lib.hasInfix "pool_health=" preflight)
  "XPS Jellyfin needs its independent pool readiness service";
assert lib.elem "xps-media-ready.service" service.requires && lib.elem "xps-media-ready.service" service.after;
assert readiness.serviceConfig.User == "eric" && readiness.serviceConfig.Group == "users";
assert readiness.serviceConfig.Type == "oneshot" && !(readiness.serviceConfig.RemainAfterExit or false);
assert readiness.serviceConfig.DevicePolicy == "closed" && readiness.serviceConfig.DeviceAllow == [ "/dev/zfs rw" ];
assert readiness.serviceConfig.NoNewPrivileges && readiness.serviceConfig.ProtectSystem == "strict";
assert readiness.serviceConfig.TimeoutStartSec == "15s" && readiness.serviceConfig.TimeoutStopSec == "5s";
assert readiness.unitConfig.AssertPathIsMountPoint == peer.hwc.paths.media.root;
assert !(lib.elem "/dev/zfs rw" service.serviceConfig.DeviceAllow);
assert !(lib.hasInfix "pool_health=" service.preStart) && lib.hasInfix "DATA_DIR=" service.preStart;
assert service.unitConfig.AssertPathIsMountPoint == peer.hwc.paths.media.root;
assert lib.elem "zfs-mount.service" service.requires;
assert lib.hasInfix "<HardwareAccelerationType>none</HardwareAccelerationType>" encoding;
assert lib.hasInfix "<EnableHardwareEncoding>false</EnableHardwareEncoding>" encoding;
assert lib.hasInfix "<HardwareAccelerationType>nvenc</HardwareAccelerationType>" homeEncoding;
pkgs.runCommand "xps-media-readiness" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} ${pkgs.bash}/bin/bash ${pkgs.coreutils}/bin/timeout <<'PY'
  import json, pathlib, re, subprocess, sys, tempfile, time
  fixture = json.loads(pathlib.Path(sys.argv[1]).read_text())
  bash, timeout = sys.argv[2:]
  original = fixture["script"]
  matches = re.findall(r"(/nix/store/[^\s]+/bin/timeout) 10s", original)
  assert len(matches) == 1, "production probe must have one 10-second deadline"
  with tempfile.TemporaryDirectory() as directory:
      root = pathlib.Path(directory)
      fake = root / "zpool"
      script = root / "preflight"
      script.write_text(original.replace(matches[0], timeout).replace(fixture["zpool"], str(fake)))
      def run(state):
          fake.write_text("#!${pkgs.python3}/bin/python3\n"
              "import sys,time\n"
              + "assert sys.argv[1:] == " + repr(["list", "-H", "-o", "health", fixture["pool"]]) + "\n"
              + ("time.sleep(30)\n" if state == "TIMEOUT" else
                 "sys.exit(3)\n" if state == "PROBE_FAILED" else "print(" + repr(state) + ")\n"))
          fake.chmod(0o700)
          start = time.monotonic()
          result = subprocess.run([bash, "-e", str(script)], capture_output=True, text=True, timeout=15)
          return result, time.monotonic() - start
      for state in ["ONLINE", "DEGRADED"]:
          result, _ = run(state)
          assert result.returncode == 0, (state, result.stderr)
          if state == "DEGRADED":
              assert result.stderr, "degraded storage must emit a warning"
      for state in ["SUSPENDED", "UNAVAIL", "FAULTED", "UNKNOWN", "PROBE_FAILED", "TIMEOUT"]:
          result, elapsed = run(state)
          assert result.returncode != 0, (state, "startup unexpectedly passed")
          assert elapsed < 15, (state, "probe exceeded its ceiling")
      print("XPS production preflight: healthy/degraded accepted; unavailable, suspended, failed and timed-out probes rejected")
  PY
  touch "$out"
'';
}
