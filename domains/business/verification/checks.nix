# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, repoRoot, self }:
{

estimator-private-api = let
  c = self.nixosConfigurations.hwc-work.config;
  route = lib.findFirst (r: r.name == "estimator") null c.hwc.networking.shared.effectiveRoutes;
  fixture = pkgs.writeText "estimator-private-api.json" (builtins.toJSON {
    caddy = c.services.caddy.extraConfig;
    inherit route;
    origin = "https://estimator.${c.hwc.networking.shared.vhostDomain}";
    secret = c.hwc.secrets.api.estimator-api-key;
    build = c.systemd.services.estimator-build.serviceConfig.ExecStart;
  });
in pkgs.runCommand "estimator-private-api" {
  nativeBuildInputs = [ pkgs.python3 c.services.caddy.package ];
} ''
  python3 - ${fixture} <<'PY'
  import http.server, json, os, pathlib, socket, subprocess, sys, tempfile, threading, time
  import urllib.request, urllib.error
  f = json.loads(pathlib.Path(sys.argv[1]).read_text())
  # Exercise the real rendered handler, not a copy of its policy.
  marker = '@estimator host '
  start = f['caddy'].index(marker)
  opening = f['caddy'].index('{', f['caddy'].index('handle @estimator {', start))
  depth, end = 1, opening + 1
  while depth:
      depth += (f['caddy'][end] == '{') - (f['caddy'][end] == '}')
      end += 1
  handler = f['caddy'][start:end]
  script = pathlib.Path(f['build']).read_text()
  assert 'VITE_API_KEY' not in script and f['secret'] not in script
  assert 'VITE_WEBHOOK_URL' in script
  seen = []
  class Backend(http.server.BaseHTTPRequestHandler):
      def do_GET(self): self.reply()
      def do_POST(self): self.reply()
      def reply(self):
          n = int(self.headers.get('Content-Length', '0'))
          seen.append((self.command, self.path, self.headers.get('x-api-key'), self.rfile.read(n)))
          self.send_response(200); self.send_header('Content-Type', 'application/json')
          self.end_headers(); self.wfile.write(b'{"ok":true}')
      def log_message(self, *_): pass
  backend = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Backend)
  threading.Thread(target=backend.serve_forever, daemon=True).start()
  def free_port():
      with socket.socket() as s:
          s.bind(('127.0.0.1', 0)); return s.getsockname()[1]
  with tempfile.TemporaryDirectory() as tmp:
      p = pathlib.Path(tmp); secret = p / 'key'; secret.write_text('fixture-key-one')
      (p / 'index.html').write_text('estimator fixture')
      handler = handler.replace(f['route']['root'], str(p)).replace(f['secret'], str(secret))
      for api in f['route']['api']:
          handler = handler.replace(api['upstream'], 'http://127.0.0.1:' + str(backend.server_port))
      host = f['origin'].removeprefix('https://')
      def exercise(text, seeded=False):
          port = free_port(); cfg = p / 'Caddyfile'
          cfg.write_text('{\n admin off\n auto_https off\n persist_config off\n}\nhttp://:' + str(port) + ' {\n bind 127.0.0.1\n' + text + '\n}\n')
          adapted = subprocess.run(['caddy','adapt','--adapter','caddyfile','--config',str(cfg)], capture_output=True)
          assert adapted.returncode == 0, adapted.stderr.decode()
          assert b'fixture-key-one' not in adapted.stdout, 'credential entered adapted config'
          out = p / 'config.json'; out.write_bytes(adapted.stdout)
          with (p/'caddy.log').open('w') as log:
              proc = subprocess.Popen(['caddy','run','--config',str(out)], stdout=log, stderr=log,
                  env={**os.environ, 'XDG_CONFIG_HOME':str(p/'config'), 'XDG_DATA_HOME':str(p/'data')})
              try:
                  for _ in range(100):
                      try:
                          with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                      except OSError:
                          if proc.poll() is not None: raise AssertionError('Caddy startup failed')
                          time.sleep(.02)
                  else: raise AssertionError('Caddy startup timeout')
                  def request(path, method='GET', headers=None):
                      req = urllib.request.Request('http://127.0.0.1:' + str(port) + path,
                          data=b'fixture-body' if method == 'POST' else None,
                          method=method, headers={'Host':host, **(headers or {})})
                      try:
                          with urllib.request.urlopen(req, timeout=3) as r: return r.status, r.read(), r.headers
                      except urllib.error.HTTPError as e: return e.code, e.read(), e.headers
                  before = len(seen)
                  status, _, headers = request('/webhook/jt-customers?page=two', headers={'x-api-key':'forged'})
                  assert status == 200 and len(seen) == before + 1, 'customer API not wired'
                  if seeded: return
                  assert seen[-1][:3] == ('GET','/webhook/jt-customers?page=two','fixture-key-one')
                  assert headers.get('Cache-Control') == 'no-store' and not headers.get('Access-Control-Allow-Origin')
                  secret.write_text('fixture-key-two')
                  assert request('/webhook/jt-jobs?customerId=fixture')[0] == 200
                  assert seen[-1][2] == 'fixture-key-two', 'key must reload from runtime file'
                  assert request('/webhook/estimate-push','POST', {'Origin':f['origin'],'Sec-Fetch-Site':'same-origin','x-api-key':'forged'})[0] == 200
                  assert seen[-1] == ('POST','/webhook/estimate-push','fixture-key-two',b'fixture-body')
                  before = len(seen)
                  for path, method, h, expected in [
                      ('/webhook/jt-customers','POST',{},405),
                      ('/webhook/jt-jobs','GET',{'Origin':'https://evil.test'},403),
                      ('/webhook/jt-customers','GET',{'Sec-Fetch-Site':'cross-site'},403),
                      ('/webhook/jt-customers','GET',{'Sec-Fetch-Site':'same-site'},403),
                      ('/webhook/estimate-push','GET',{},405),
                      ('/webhook/estimate-push','POST',{},403),
                      ('/webhook/estimate-push','POST',{'Origin':'https://evil.test'},403),
                      ('/webhook/estimate-push','OPTIONS',{},405),
                  ]:
                      assert request(path, method, h)[0] == expected, (path, method, expected)
                  assert request('/webhook/jt-customers/extra')[1] == b'estimator fixture'
                  assert len(seen) == before, 'denied request reached backend'
                  assert request('/api/jobs/fixture/calculator-intake')[0] == 200
                  assert seen[-1][2] is None, 'credential leaked to CRM handler'
                  assert request('/')[1] == b'estimator fixture'
              finally:
                  proc.terminate(); proc.wait(timeout=5)
      exercise(handler)
      # Removing the actual production API matcher must break the proof.
      try: exercise(handler.replace('/webhook/jt-customers', '/not-the-customer-route'), seeded=True)
      except AssertionError as e:
          assert str(e) == 'customer API not wired'; print('seeded missing API wiring rejected')
      else: raise AssertionError('missing API wiring accepted')
  backend.shutdown()
  print('PASS real estimator Caddy routing, runtime credentials, origin/method guards and static/CRM parity')
  PY
  touch "$out"
'';

paperless-converter-isolation = let
  work = self.nixosConfigurations.hwc-work;
  c = work.config;
  helper = import (repoRoot + "/domains/lib/mkContainer.nix") { inherit lib; pkgs = work.pkgs; };
  network = builtins.head c.hwc.networking.internalContainerNetworks;
  unit = lib.removeSuffix ".service" (helper.internalNetworkUnit network);
  options = mode: (helper.mkContainer { name = "probe"; image = "probe"; networkMode = mode; gpuEnable = false; }).virtualisation.oci-containers.containers.probe.extraOptions;
  rejects = mode: !(builtins.tryEval (builtins.deepSeq (options mode) true)).success;
  fixture = pkgs.writeText "paperless-converter-isolation.json" (builtins.toJSON {
    inherit network unit;
    containers = lib.genAttrs [ "paperless" "paperless-tika" "paperless-gotenberg" ] (name: {
      networks = builtins.filter (lib.hasPrefix "--network=") c.virtualisation.oci-containers.containers.${name}.extraOptions;
      after = c.systemd.services.${"podman-"+name}.after;
      requires = c.systemd.services.${"podman-"+name}.requires;
    });
    initializer = c.systemd.services.${unit}.script;
  });
in
assert c.hwc.networking.internalContainerNetworks == [ "paperless-conversion" ];
assert builtins.head (options "media") == "--network=media-network";
assert builtins.head (options "host") == "--network=host";
assert builtins.head (options "vpn") == "--network=container:gluetun";
assert builtins.head (options { kind = "named"; names = [ "one" "two" ]; }) == "--network=one,two";
assert lib.all rejects [ {} { kind = "unknown"; names = ["one"]; } {kind="named";names=[];} {kind="named";names=["one" "one"];} {kind="named";names=["bad,name"];} ];
pkgs.runCommand "paperless-converter-isolation" { nativeBuildInputs = [pkgs.python3]; } ''
  python3 - ${fixture} <<'PYISO'
  import copy, json, pathlib, subprocess, sys
  from unittest.mock import patch
  from types import SimpleNamespace
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  def check(value):
      for name,c in value['containers'].items():
          expected = 'media-network,'+value['network'] if name == 'paperless' else value['network']
          assert c['networks'] == ['--network='+expected]
          assert value['unit']+'.service' in c['after'] and value['unit']+'.service' in c['requires']
  check(spec)
  leaked = copy.deepcopy(spec); leaked['containers']['paperless-gotenberg']['networks'] = ['--network=media-network']
  try: check(leaked)
  except AssertionError: print('seeded shared converter network rejected')
  else: raise AssertionError('converter egress escaped isolation check')
  source = spec['initializer'].split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
  good = {'internal':True,'dns_enabled':True,'ipv6_enabled':False,'driver':'bridge'}
  def execute(metadata,code=0):
      effects=[]
      def run(argv,**kwargs):
          effects.append(argv)
          return SimpleNamespace(returncode=code if 'exists' in argv else 0)
      with patch('subprocess.run',side_effect=run), patch('subprocess.check_output',return_value=json.dumps([metadata]).encode()):
          exec(compile(source,'actual-network-initializer','exec'),{})
      return effects
  execute(good)
  assert any('create' in argv for argv in execute(good,1))
  for field,value in [('internal',False),('dns_enabled',False),('ipv6_enabled',True),('driver','macvlan')]:
      bad={**good,field:value}
      try: execute(bad)
      except SystemExit as e: assert str(e)=='internal_network_policy_mismatch'
      else: raise AssertionError('unsafe network accepted')
  try: execute(good,125)
  except SystemExit as e: assert str(e)=='internal_network_inspection_failed'
  else: raise AssertionError('inspection error accepted')
  print('PASS actual named-network wiring and fail-closed initializer')
  PYISO
  touch "$out"
'';

gotenberg-runtime-wiring = let
  c = self.nixosConfigurations.hwc-work.config;
  fixture = pkgs.writeText "gotenberg-runtime-wiring.json" (builtins.toJSON {
    context = c.system.build.gotenbergRuntimeImageContext;
    image = c.hwc.business.paperless.officeIngest.gotenbergImage;
    container = c.virtualisation.oci-containers.containers.paperless-gotenberg;
    preStart = c.systemd.services.podman-paperless-gotenberg.preStart;
    paperless = c.hwc.business.paperless.image;
    paperlessContext = c.system.build.paperlessRuntimeImageContext;
    paperlessContainer = c.virtualisation.oci-containers.containers.paperless;
    paperlessPreStart = c.systemd.services.podman-paperless.preStart;
    tika = c.virtualisation.oci-containers.containers.paperless-tika;
    tikaRecipe = c.system.build.tikaRuntimeImageRecipe;
    tikaPreStart = c.systemd.services.podman-paperless-tika.preStart;
  });
in pkgs.runCommand "gotenberg-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} <<'PYGOT'
  import base64, copy, hashlib, json, pathlib, sys
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  root = pathlib.Path(spec['context'])
  recipe = (root/'Dockerfile').read_text()
  packages = json.loads((root/'manifest.json').read_text())
  assert len(packages) == 4
  assert {p['name'] for p in packages} == {'chromium','chromium-common','libnss3','tzdata'}
  for p in packages:
      data = (root/'debian'/p['file']).read_bytes()
      assert p['hash'] == 'sha256-'+base64.b64encode(hashlib.sha256(data).digest()).decode()
      if p['name'].startswith('chromium'):
          assert p['version'] == '156.0.8078.79-1~deb13u1'
  expected = 'localhost/paperless-gotenberg-runtime:8.39.0-chromium156.0.8078.79-'+hashlib.sha256(recipe.encode()).hexdigest()[:12]
  def check(value):
      assert value['image'] == expected and value['container']['image'] == expected
      assert value['container']['pull'] == 'never'
      assert expected in value['preStart'] and ' image exists ' in value['preStart']
      assert '--chromium-disable-javascript=true' in value['container']['cmd']
      assert '--chromium-allow-list=file:///tmp/.*' in value['container']['cmd']
      assert {'--libreoffice-deny-list=.*','--api-disable-download-from=true','--webhook-disable=true'} <= set(value['container']['cmd'])
      assert not value['container']['ports'] and not value['container']['volumes']
      assert value['paperless'] == expected_paperless
      assert value['paperlessContainer']['image'] == expected_paperless
      assert value['paperlessContainer']['pull'] == 'never'
      assert expected_paperless in value['paperlessPreStart']
      assert value['tika']['image'] == expected_tika and value['tika']['pull'] == 'never'
      assert expected_tika in value['tikaPreStart']
      assert not value['tika']['ports'] and not value['tika']['volumes']
  client_context = pathlib.Path(spec['paperlessContext'])
  client_recipe = (client_context/'Dockerfile').read_text()
  assert 'FROM ghcr.io/paperless-ngx/paperless-ngx@sha256:aa810a36942c63d4ee70d00eda7236cd3d6acfb7eb3f7987fb568ed14df8817a' in client_recipe
  assert '--no-index --no-deps' in client_recipe
  assert 'FROM docker.io/library/python@sha256:ec6a14df5b63e3fbb3498e3240f7f640c230f9dca67683d23265db3866697f2d AS patched-python' in client_recipe
  assert '! -name site-packages' in client_recipe and '--no-download' in client_recipe
  client_packages = json.loads((client_context/'manifest.json').read_text())
  assert len(client_packages['debian']) == 64
  assert {'libbrotli1','ghostscript','libgs10','libc6','libraw23t64','perl','libglib2.0-0t64','curl'} <= {p['name'] for p in client_packages['debian']}
  assert {p['name'].lower():p['version'] for p in client_packages['wheels']} == {
      'tika-client':'2.0.0','pillow':'13.0.0','brotli':'1.2.1','anyio':'4.14.2','pyjwt':'2.14.0','certifi':'2026.10.18'}
  for group,folder in [('debian','debian'),('wheels','wheels')]:
      for p in client_packages[group]:
          digest = hashlib.sha256((client_context/folder/p['file']).read_bytes()).digest()
          assert p['hash'] == 'sha256-'+base64.b64encode(digest).decode()
  assert hashlib.sha256((client_context/'wheels/tika_client-2.0.0-py3-none-any.whl').read_bytes()).hexdigest() == '44dd7a5227ab2d25bc88b8ff282039602eaac0592e542ee0486d9535ec1be9b2'
  expected_paperless = 'localhost/paperless-runtime:3.1.3-python3.14.10-'+hashlib.sha256(client_recipe.encode()).hexdigest()[:12]
  tika_recipe = pathlib.Path(spec['tikaRecipe']).read_text()
  assert 'FROM docker.io/apache/tika@sha256:b99f19c4fd76237dafe7d22f719b9bddfa9a449da687c597a41e2f6d9a595418' in tika_recipe
  assert 'test -f /usr/bin/pebble && rm /usr/bin/pebble' in tika_recipe
  assert tika_recipe.rstrip().endswith('USER 35002:35002')
  expected_tika = 'localhost/paperless-tika-runtime:4.2.0-'+hashlib.sha256(tika_recipe.encode()).hexdigest()[:12]
  check(spec)
  stale = copy.deepcopy(spec); stale['container']['image'] = 'docker.io/gotenberg/gotenberg:8.34'
  try: check(stale)
  except AssertionError: print('seeded missing production integration rejected')
  else: raise AssertionError('old converter escaped production check')
  stale_client = copy.deepcopy(spec); stale_client['paperlessContainer']['image'] = 'ghcr.io/paperless-ngx/paperless-ngx:3.1.3'
  try: check(stale_client)
  except AssertionError: print('seeded incompatible old client rejected')
  else: raise AssertionError('old client escaped paired runtime check')
  assert '--no-download' in recipe and 'apt-get update' not in recipe
  assert recipe.rstrip().endswith('USER gotenberg')
  print('PASS exact converter inputs and actual Paperless wiring')
  PYGOT
  touch "$out"
'';

firefly-php-runtime-wiring = let
  c = self.nixosConfigurations.hwc-work.config;
  disabledImporter = (self.nixosConfigurations.hwc-work.extendModules {
    modules = [ { hwc.business.firefly.importer.enable = lib.mkForce false; } ];
  }).config;
  specs = map (spec: spec // {
    image = c.hwc.business.firefly.images.${spec.kind};
    container = c.virtualisation.oci-containers.containers.${spec.name};
    preStart = c.systemd.services.${"podman-" + spec.name}.preStart;
  }) [
    { kind = "core"; name = "firefly"; appVersion = "6.6.6"; context = c.system.build.fireflyCoreRuntimeImageContext; }
    { kind = "importer"; name = "firefly-importer"; appVersion = "2.3.4"; context = c.system.build.fireflyImporterRuntimeImageContext; }
  ];
  fixture = pkgs.writeText "firefly-php-runtime-wiring.json" (builtins.toJSON specs);
in
assert !(disabledImporter.virtualisation.oci-containers.containers ? firefly-importer);
assert !(disabledImporter.systemd.services ? podman-firefly-importer);
pkgs.runCommand "firefly-php-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} <<'PY'
  import base64, hashlib, json, pathlib, re, sys
  for spec in json.loads(pathlib.Path(sys.argv[1]).read_text()):
      recipe = (pathlib.Path(spec['context']) / 'Dockerfile').read_text()
      expected = 'localhost/' + spec['name'] + '-runtime:' + spec['appVersion'] + '-php8.5.12-'
      assert spec['image'] == expected + hashlib.sha256(recipe.encode()).hexdigest()[:12]
      assert spec['container']['image'] == spec['image'] and spec['container']['pull'] == 'never'
      assert spec['image'] in spec['preStart'] and ' image exists ' in spec['preStart']
      sources = re.findall(r'^FROM (\S+)', recipe, re.M)
      assert len(sources) == 3 and all('@sha256:' in image for image in sources)
      assert 'COPY --from=native-build /native/ /' in recipe
      assert 'RUN sh /build-native.sh' in recipe
      assert 'apt-get --yes purge curl libcurl4t64 libxml2' in recipe
      assert 'chown www-data:www-data /run' in recipe
      native = (pathlib.Path(spec['context']) / 'native-runtime-build.sh').read_text()
      assert hashlib.sha256(native.encode()).hexdigest() in recipe
      assert 'make check' in native and 'make test' in native
      assert 'REPORT_EXIT_STATUS=1 sapi/cli/php -n run-tests.php' in native
      assert '-c php.ini-development' in native
      assert 'getent hosts localhost' in native
      assert 'SKIP_' not in native
      for directory, manifest_name in [('native-sources', 'native-sources/manifest.json'), ('native-build-debs', 'native-build-packages.json')]:
          manifest_path = pathlib.Path(spec['context']) / manifest_name
          assert hashlib.sha256(manifest_path.read_bytes()).hexdigest() in recipe
          for package in json.loads(manifest_path.read_text()):
              data = (pathlib.Path(spec['context']) / directory / package['file']).read_bytes()
              assert package['hash'] == 'sha256-' + base64.b64encode(hashlib.sha256(data).digest()).decode()
      assert 'COPY --from=secure-php /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/' in recipe
      assert '/var/www/html' not in recipe and 'ENV PHP_VERSION=8.5.12 ' in recipe
      context = pathlib.Path(spec['context'])
      manifest = context / 'manifest.json'
      assert hashlib.sha256(manifest.read_bytes()).hexdigest() in recipe
      packages = json.loads(manifest.read_text())
      assert len({p['file'] for p in packages}) == len(packages)
      for package in packages:
          data = (context / package['file']).read_bytes()
          assert package['hash'] == 'sha256-' + base64.b64encode(hashlib.sha256(data).digest()).decode()
      assert 'COPY *.deb /tmp/hwc-runtime-debs/' in recipe
      assert 'apt-get --no-download --yes -o Dir::Cache::archives=/tmp/hwc-runtime-debs -o Dpkg::Options::=--force-confold install /tmp/hwc-runtime-debs/*.deb' in recipe
      assert recipe.rstrip().endswith('USER www-data')
      assert 'COMPOSER_DISABLE_NETWORK=1' in recipe
      assert 'install --no-dev --no-scripts --no-plugins' in recipe
      assert 'cp /tmp/hwc-composer.phar /usr/bin/composer' in recipe
      assert 'rm -f bootstrap/cache/packages.php bootstrap/cache/services.php' in recipe
      assert 'chown www-data:www-data bootstrap/cache' in recipe
      assert {'composer.json', 'composer.lock', 'composer.phar', 'composer-cache'} <= {p.name for p in context.iterdir()}
  PY
  touch "$out"
'';

firefly-pico-runtime-wiring = let
  c = self.nixosConfigurations.hwc-work.config;
  image = c.hwc.business.firefly.images.pico;
  fixture = pkgs.writeText "firefly-pico-runtime-wiring.json" (builtins.toJSON {
    inherit image;
    container = c.virtualisation.oci-containers.containers.firefly-pico;
    preStart = c.systemd.services.podman-firefly-pico.preStart;
    context = c.system.build.fireflyPicoRuntimeImageContext or null;
  });
in
assert lib.assertMsg (lib.hasPrefix "localhost/firefly-pico-runtime:1.10.1-node22.23.4-" image)
  "Firefly-Pico must consume its qualified same-app runtime and shared libraries";
assert c.virtualisation.oci-containers.containers.firefly-pico.image == image;
pkgs.runCommand "firefly-pico-runtime-wiring" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} <<'PY'
  import base64, hashlib, json, pathlib, re, sys
  spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
  context = pathlib.Path(spec['context'])
  recipe = (context / 'Dockerfile').read_text()
  manifest = json.loads((context / 'manifest.json').read_text())
  assert manifest['schemaVersion'] == 1
  assert spec['image'] == 'localhost/firefly-pico-runtime:1.10.1-node22.23.4-' + hashlib.sha256(recipe.encode()).hexdigest()[:12]
  assert spec['container']['image'] == spec['image'] and spec['container']['pull'] == 'never'
  assert spec['image'] in spec['preStart'] and ' image exists ' in spec['preStart']
  assert str(context) in spec['preStart'] and '/bin/podman build ' not in spec['preStart']
  assert re.findall(r'^FROM (\S+)', recipe, re.M) == [
      'docker.io/library/node@sha256:9fee3a1d85a49993660c8ffc774ceafadc0b52eda69b4c981f6b6a1cfabcfe98',
      'docker.io/cioraneanu/firefly-pico@sha256:2bc76980f6be5a4e36581dbed8c381e119a2318031d2f1cf5d9cb14b7286a633']
  assert 'COPY --from=secure-node /usr/local/bin/node /usr/bin/node' in recipe
  assert 'ENV NODE_VERSION=22.23.4' in recipe
  assert 'apk add --no-network --no-cache --repositories-file /dev/null' in recipe
  assert 'update-ca-certificates --fresh' in recipe and '--allow-untrusted' not in recipe
  expected = {'c-ares':'1.34.9-r0', 'brotli-libs':'1.1.1-r0',
      'libcrypto3':'3.5.9-r0', 'libssl3':'3.5.9-r0',
      'ca-certificates':'20261020-r0', 'ca-certificates-bundle':'20261020-r0'}
  php_packages = ['php82', 'php82-common', 'php82-ctype', 'php82-curl', 'php82-dom',
      'php82-fileinfo', 'php82-fpm', 'php82-iconv', 'php82-mbstring', 'php82-mysqlnd',
      'php82-opcache', 'php82-openssl', 'php82-pdo', 'php82-pdo_mysql', 'php82-pdo_pgsql',
      'php82-pdo_sqlite', 'php82-phar', 'php82-session', 'php82-simplexml', 'php82-tokenizer',
      'php82-xml', 'php82-xmlwriter', 'php82-zip']
  expected.update({name: '8.2.35-r0' for name in php_packages})
  actual = {p['name']:p['version'] for p in manifest['packages']}
  assert all(actual[name] == version for name, version in expected.items())
  assert len(actual) == len(manifest['packages'])  # no competing package pins
  assert {'nginx', 'libcurl', 'libpq', 'libexpat', 'python3', 'nodejs',
      'musl', 'zlib', 'pcre2', 'nghttp2-libs', 'libxml2'} <= actual.keys()
  assert {p.name for p in context.iterdir()} == {'Dockerfile','manifest.json',
      'composer.json','composer.lock','composer.phar','composer-cache',
      'pico-front-package.json','pico-front-package-lock.json','pico-frontend.patch',
      'pico-frontend-test.mjs','pico-frontend-cache.mjs','npm.tgz','npm-packages',
      'npm-packages.json','python-vendor.json','python-vendor','pico-python-vendor.py'} | {p['file'] for p in manifest['packages']}
  assert 'npm-cli.js ci --cache /tmp/npm-cache --offline --include=dev' in recipe
  assert 'npm-cli.js run build && node hwc-frontend-test.mjs' in recipe
  assert 'RUN python3 /tmp/pico-python-vendor.py' in recipe
  for directory, manifest_name in [('npm-packages', 'npm-packages.json'), ('python-vendor', 'python-vendor.json')]:
      manifest_path = context / manifest_name
      assert hashlib.sha256(manifest_path.read_bytes()).hexdigest() in recipe
      for package in json.loads(manifest_path.read_text()):
          algorithm, expected = package['hash'].split('-', 1)
          data = (context / directory / package['file']).read_bytes()
          assert expected == base64.b64encode(hashlib.new(algorithm, data).digest()).decode()
  for name in ['pico-front-package.json','pico-front-package-lock.json','pico-frontend.patch',
               'pico-frontend-test.mjs','pico-frontend-cache.mjs','pico-python-vendor.py']:
      assert hashlib.sha256((context / name).read_bytes()).hexdigest() in recipe
  assert 'chown www-data:www-data bootstrap/cache' in recipe
  assert 'COMPOSER_DISABLE_NETWORK=1' in recipe
  assert 'install --no-dev --no-scripts --no-plugins' in recipe
  for package in manifest['packages']:
      data = (context / package['file']).read_bytes()
      assert package['hash'] == 'sha256-' + base64.b64encode(hashlib.sha256(data).digest()).decode()
      assert '# APK ' + package['file'] + ' ' + package['hash'] in recipe
      assert package['url'] == 'https://dl-cdn.alpinelinux.org/alpine/v3.22/' + ('community' if package['name'].startswith('php82') else 'main') + '/x86_64/' + package['file']
  PY
  touch "$out"
'';

# Exercise the actual laptop module wiring, not a second layout renderer.
workbench-web-service = let
  work = self.nixosConfigurations.hwc-work;
  command = work.config.systemd.services.workbench-web.serviceConfig.ExecStart;
  disabledHandoff = (work.extendModules { modules = [{
    hwc.business.workbench.web.handoff.enable = lib.mkForce false;
  }]; }).config;
  handoffOnly = (work.extendModules { modules = [{
    hwc.business.workbench.web = {
      writeTiles = lib.mkForce [];
      handoff.enable = true;
    };
  }]; }).config;
  handoffService = handoffOnly.systemd.services.workbench-web;
  publicTargets = builtins.fromJSON (builtins.readFile (repoRoot + "/domains/business/workbench/t3-targets.json"));
  handoffEnvironment = handoffService.environment;
  handoffMount = builtins.fromJSON handoffEnvironment.WORKBENCH_HANDOFF_CREDENTIAL_MOUNT;
  handoffSecret = handoffOnly.age.secrets.${handoffOnly.hwc.business.workbench.web.handoff.credentialsSecret};
  overridePath = "/tmp/workbench explicit styles";
  overridden = (work.extendModules { modules = [{
    hwc.business.workbench.web.stylesDir = lib.mkForce overridePath;
  }]; }).config.systemd.services.workbench-web.serviceConfig.ExecStart;
in
assert lib.assertMsg (work.config.hwc.business.workbench.web.enable
  && work.config.hwc.business.workbench.web.stylesDir == null
  && !(lib.hasInfix "--styles-dir" command))
  "workbench-web: default service must consume bundled styles";
assert lib.assertMsg (lib.hasInfix
  (lib.escapeShellArgs [ "--styles-dir" overridePath ]) overridden)
  "workbench-web: explicit styles override must survive argv escaping";
assert lib.assertMsg (disabledHandoff.systemd.services.workbench-web.environment.WORKBENCH_HANDOFF_TARGETS == "{}")
  "workbench-web: disabled handoffs must override ambient targets";
assert lib.assertMsg (builtins.fromJSON handoffEnvironment.WORKBENCH_HANDOFF_TARGETS == publicTargets.targets
  && handoffMount.linkDirectory == handoffOnly.age.secretsDir
  && handoffMount.generationDirectory == handoffOnly.age.secretsMountPoint
  && handoffEnvironment.WORKBENCH_HANDOFF_CREDENTIALS_FILE == handoffOnly.hwc.secrets.api."workbench-t3-credentials")
  "workbench-web: handoff configuration must use the public registry and generated secret facade";
assert lib.assertMsg (handoffSecret.owner == "root" && handoffSecret.group == "secrets"
  && handoffSecret.mode == "0440" && lib.elem handoffSecret.file handoffService.restartTriggers)
  "workbench-web: generated private credentials must reload their consumer on rotation";
assert lib.assertMsg (lib.hasInfix (lib.escapeShellArgs [ "--state-file"
  handoffOnly.hwc.data.borg.sqliteSnapshots.workbench-actions.source ]) handoffService.serviceConfig.ExecStart
  && lib.elem handoffOnly.hwc.business.workbench.web.stateDir handoffService.serviceConfig.ReadWritePaths)
  "workbench-web: handoff-only service needs the backed-up writable journal";
pkgs.runCommand "workbench-web-service" {} ''
  touch "$out"
'';

morning-briefing-async = pkgs.runCommand "morning-briefing-async" {
  nativeBuildInputs = [ pkgs.nodejs_22 ];
} ''
  node --test ${(repoRoot + "/domains/business/morning-briefing")}/gather.test.mjs
  touch "$out"
'';
website-security = let
  c = self.nixosConfigurations.hwc-work.config;
  origin = c.services.caddy.virtualHosts."http://:${toString c.hwc.business.website.originPort}".extraConfig;
  fixture = pkgs.writeText "website-security.caddy" (builtins.replaceStrings
    [ (toString c.hwc.business.website.publishDir + "/current") ] [ "__fixture_root__" ] origin);
in pkgs.runCommand "website-security" { nativeBuildInputs = [ pkgs.python3 c.services.caddy.package ]; } ''
  python3 - ${fixture} "$(command -v caddy)" <<'PY'
  import pathlib,socket,subprocess,tempfile,time,urllib.request,urllib.error,sys
  class NoRedirect(urllib.request.HTTPRedirectHandler):
   def redirect_request(self,*args): return None
  opener=urllib.request.build_opener(NoRedirect)
  def exercise(config):
   with tempfile.TemporaryDirectory() as d:
    root=pathlib.Path(d);(root/'index.html').write_text('website fixture');(root/'app.js').write_text('console.log(1)')
    (root/'report').mkdir();(root/'report/index.html').write_text('private fixture')
    with socket.socket() as s: s.bind(('127.0.0.1',0));port=s.getsockname()[1]
    config=config.replace('root * __fixture_root__','root * '+d)
    cf=root/'Caddyfile';cf.write_text('{ admin off\n auto_https off\n}\nhttp://:'+str(port)+' {\n'+config+'\n}')
    proc=subprocess.Popen([sys.argv[2],'run','--config',str(cf),'--adapter','caddyfile'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    def get(path,scheme='https',host='iheartwoodcraft.com'):
     req=urllib.request.Request('http://127.0.0.1:'+str(port)+path,headers={'X-Forwarded-Proto':scheme,'Host':host})
     try:return opener.open(req,timeout=2)
     except urllib.error.HTTPError as e:return e
    try:
     for _ in range(100):
      try:r=get('/');break
      except OSError:time.sleep(.05)
     else:raise AssertionError('Caddy failed startup')
     for path,status in [('/',200),('/app.js',200),('/missing',404),('/.env',404)]:
      r=get(path);assert r.status==status,(path,r.status)
      for h,v in [('X-Content-Type-Options','nosniff'),('X-Frame-Options','SAMEORIGIN'),('Referrer-Policy','strict-origin-when-cross-origin'),('Strict-Transport-Security','max-age=31536000')]:assert r.headers.get(h)==v,(path,h,r.headers.get(h))
      assert "object-src 'none'" in r.headers['Content-Security-Policy']
      assert 'camera=()' in r.headers['Permissions-Policy']
     assert get('/').headers['Cache-Control'] == 'public, max-age=0, must-revalidate'
     for path in ['/report/', '/report/?id=fixture', '/report/fixture', '/report/fixture/']:
      r=get(path);assert r.status==200,(path,r.status)
      assert r.headers['Cache-Control']=='no-store',(path,'private report cache policy')
      assert r.headers['Referrer-Policy']=='no-referrer',(path,'private report referrer policy')
      assert r.headers['X-Robots-Tag']=='noindex, nofollow, noarchive'
     r=get('/contact/?from=fixture','http','attacker.invalid');assert r.status==308,r.status
     assert r.headers['Location']=='https://iheartwoodcraft.com/contact/?from=fixture',r.headers['Location']
    finally:proc.terminate();proc.wait(timeout=5)
  config=pathlib.Path(sys.argv[1]).read_text();exercise(config);print('PASS production Caddy security headers, errors, assets, HTTPS redirect, path/query and fixed redirect host')
  PY
  touch "$out"
'';
}
