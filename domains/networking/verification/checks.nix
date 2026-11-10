# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, self, repoRoot }:
{

public-webhook-ingress = let
  c = self.nixosConfigurations.hwc-work.config;
  tunnel = c.services.cloudflared.tunnels.${c.hwc.networking.cloudflared.tunnelId};
  fixture = pkgs.writeText "public-webhook-ingress.json" (builtins.toJSON {
    ingress = (lib.mapAttrsToList (hostname: rule:
      { inherit hostname; } // (if builtins.isString rule then { service = rule; } else rule)
    ) tunnel.ingress) ++ [ { service = tunnel.default; } ];
  });
in pkgs.runCommand "public-webhook-ingress" { nativeBuildInputs = [ pkgs.python3 pkgs.cloudflared ]; } ''
  python3 - ${fixture} <<'PY'
  import json, pathlib, subprocess, sys
  config = json.loads(pathlib.Path(sys.argv[1]).read_text())
  def route(data, path):
      pathlib.Path('ingress.json').write_text(json.dumps(data))
      result = subprocess.run(['cloudflared', 'tunnel', '--config', 'ingress.json',
          'ingress', 'rule', 'https://api.iheartwoodcraft.com' + path],
          check=True, capture_output=True, text=True)
      return result.stdout + result.stderr
  def denied(data, path):
      assert 'hostname: api.iheartwoodcraft.com' not in route(data, path), path
  for path in ['/webhook/mail-action', '/webhook/media-pipeline', '/webhook/frigate-events',
               '/webhook/', '/rest/workflows', '/webhook/quo-sms/extra',
               '/webhook/jt-jobs', '/webhook/jt-customers', '/webhook/estimate-push']:
      denied(config, path)
  for name in ['quo-sms']:
      assert 'hostname: api.iheartwoodcraft.com' in route(config, '/webhook/' + name), name
  broad = json.loads(json.dumps(config))
  for rule in broad['ingress']:
      if rule.get('hostname') == 'api.iheartwoodcraft.com':
          rule['path'] = '^/webhook/'
  try:
      denied(broad, '/webhook/mail-action')
  except AssertionError:
      print('seeded public mail exposure rejected')
  else:
      raise AssertionError('broad public route was accepted')
  PY
  touch $out
'';

public-origin-logging = let
  c = self.nixosConfigurations.hwc-work.config;
  cfg = c.hwc.networking.cloudflared;
  site = c.services.caddy.virtualHosts."http://:${toString cfg.accessLog.port}";
  tunnel = c.services.cloudflared.tunnels.${cfg.tunnelId};
  fixture = pkgs.writeText "public-origin-logging.json" (builtins.toJSON {
    inherit (site) extraConfig logFormat;
    inherit (cfg) extraIngress accessLog;
    inherit (tunnel) ingress default;
    websiteLog = c.services.caddy.virtualHosts."http://:${toString c.hwc.business.website.originPort}".logFormat;
  });
in pkgs.runCommand "public-origin-logging" { nativeBuildInputs = [ pkgs.python3 c.services.caddy.package ]; } ''
  python3 - ${fixture} <<'PY'
  import http.server, json, pathlib, socket, subprocess, sys, threading, time, urllib.request, urllib.error
  f = json.loads(pathlib.Path(sys.argv[1]).read_text())
  proxy = 'http://127.0.0.1:' + str(f['accessLog']['port'])
  assert f['default'] == proxy and f['websiteLog'] is None
  assert all(r['service'] == proxy for r in f['ingress'].values()), 'origin bypasses logger'
  # The former direct-origin wiring must fail this same assertion.
  old = json.loads(json.dumps(f))
  old['ingress']['api.iheartwoodcraft.com']['service'] = 'http://localhost:5678'
  assert not all(r['service'] == proxy for r in old['ingress'].values())
  seen = []
  class Backend(http.server.BaseHTTPRequestHandler):
      def do_POST(self):
          body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
          seen.append((self.path, dict(self.headers), body))
          self.send_response(201); self.send_header('Set-Cookie', 'ORIGIN_PRIVACY_CANARY'); self.end_headers()
          self.wfile.write(b'ok')
      do_GET = do_POST
      def log_message(self, *args): pass
  backend = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Backend)
  threading.Thread(target=backend.serve_forever, daemon=True).start()
  with socket.socket() as sock:
      sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
  extra = f['extraConfig']
  for rule in f['extraIngress'].values():
      upstream = rule if isinstance(rule, str) else rule['service']
      extra = extra.replace('reverse_proxy ' + upstream + ' {', 'reverse_proxy http://127.0.0.1:' + str(backend.server_port) + ' {')
  log = pathlib.Path.cwd() / 'access.log'
  fmt = f['logFormat'].replace('/var/log/caddy/access-public-origin.log', str(log))
  config = '{\n admin off\n}\nhttp://:' + str(port) + ' {\nlog {\n' + fmt + '\n}\n' + extra + '\n}\n'
  pathlib.Path('Caddyfile').write_text(config)
  subprocess.run(['caddy', 'validate', '--config', 'Caddyfile', '--adapter', 'caddyfile'], check=True)
  process = subprocess.Popen(['caddy', 'run', '--config', 'Caddyfile', '--adapter', 'caddyfile'], stdout=subprocess.DEVNULL, stderr=open('runtime.log', 'w'))
  def request(host, path, body=None):
      headers = {'Host': host, 'Cf-Ray': 'test-request-id', 'Cf-Connecting-Ip': '192.0.2.1',
                 'Authorization': 'Bearer ORIGIN_PRIVACY_CANARY', 'Cookie': 'ORIGIN_PRIVACY_CANARY',
                 'X-Secret': 'ORIGIN_PRIVACY_CANARY', 'X-Forwarded-Proto': 'https', 'X-Forwarded-For': '192.0.2.1'}
      try:
          r = urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:' + str(port) + path, data=body, headers=headers), timeout=3)
      except urllib.error.HTTPError as error: r = error
      status = r.status; r.read(); r.close(); return status
  try:
      for attempt in range(100):
          try:
              with socket.create_connection(('127.0.0.1', port), timeout=.1): break
          except OSError: time.sleep(.02)
      else: raise AssertionError('Caddy did not start')
      for host, rule in f['extraIngress'].items():
          path = '/webhook/quo-sms' if host.startswith('api.') else '/hooks/contact' if host.startswith('crm.') else '/api/reports/ORIGIN_PRIVACY_CANARY' if host.startswith('reports.') else '/security-review'
          assert request(host, path + '?token=ORIGIN_PRIVACY_CANARY', b'ORIGIN_PRIVACY_CANARY') == 201, host
          actual, headers, body = seen[-1]
          assert actual.endswith('?token=ORIGIN_PRIVACY_CANARY') and body == b'ORIGIN_PRIVACY_CANARY'
          assert headers['Host'] == host and headers['Authorization'] == 'Bearer ORIGIN_PRIVACY_CANARY'
          assert headers['X-Forwarded-Proto'] == 'https'
          assert headers['X-Forwarded-For'] == '192.0.2.1'
      for host, path in [('api.iheartwoodcraft.com', '/webhook/mail-action'),
                         ('api.iheartwoodcraft.com', '/webhook/media-pipeline'),
                         ('api.iheartwoodcraft.com', '/rest/workflows'),
                         ('crm.iheartwoodcraft.com', '/api/leads'),
                         ('unknown.example', '/')]:
          assert request(host, path) == 404, (host, path)
  finally:
      process.terminate(); process.wait(timeout=5); backend.shutdown()
  data = log.read_text()
  assert 'ORIGIN_PRIVACY_CANARY' not in data, 'sensitive metadata leaked'
  rows = [json.loads(line) for line in data.splitlines()]
  assert len(rows) == len(f['extraIngress']) + 5
  assert all(str(r['schemaVersion']) == '1' and r['request_id'] == 'test-request-id' and r['client_ip'] == '192.0.2.1' for r in rows)
  assert all('uri' not in r['request'] and 'headers' not in r['request'] and 'resp_headers' not in r for r in rows)
  assert any(r['path'] == '/report/[redacted]' for r in rows)
  for bound in ['mode 0600', 'roll_size 50MiB', 'roll_at 00:00', 'roll_keep 30', 'roll_keep_for 30d']:
      assert bound in fmt
  print('all origin routes, denied fallbacks, body/auth/proxy identity and log privacy pass')
  PY
  touch $out
'';

wall-lan-access = let
  home = self.nixosConfigurations.hwc-home.config;
  work = self.nixosConfigurations.hwc-work.config;
  disabled = (self.nixosConfigurations.hwc-home.extendModules {
    modules = [ { hwc.networking.reverseProxy.lanAccess.enable = lib.mkForce false; } ];
  }).config;
  lan = home.hwc.networking.reverseProxy.lanAccess;
  address = home.hwc.networking.hosts.lanIps.${home.hwc.networking.hosts.self};
  route = lib.head lan.routes;
  hostname = "${route}.${home.hwc.networking.shared.vhostDomain}";
  owner = home.hwc.networking.shared.routeOwners.${route}.owner;
  fixture = pkgs.writeText "wall-lan-access.json" (builtins.toJSON {
    inherit address hostname route;
    caddy = home.services.caddy.extraConfig;
    disabledCaddy = disabled.services.caddy.extraConfig;
    dns = home.services.dnsmasq.settings;
    workDns = work.services.dnsmasq.enable;
    dnsEnabled = home.services.dnsmasq.enable;
    disabledDns = disabled.services.dnsmasq.enable;
    workLan = work.hwc.networking.reverseProxy.lanAccess.enable;
    upstream = "https://${home.hwc.networking.hosts.ips.${owner}}";
    lanFirewall = home.networking.firewall.interfaces.${lan.interface};
    workGlobalPorts = work.networking.firewall.allowedTCPPorts;
    preStart = home.systemd.services.dnsmasq.preStart;
  });
in pkgs.runCommand "wall-lan-access" { nativeBuildInputs = [ pkgs.python3 pkgs.dnsmasq ]; } ''
  dnsmasq --test --conf-file=${home.services.dnsmasq.configFile}
  python3 - ${fixture} <<'PY'
  import copy, json, pathlib, sys
  cfg = json.loads(pathlib.Path(sys.argv[1]).read_text())
  def check(c):
      route, name, address = c['route'], c['hostname'], c['address']
      assert c['dnsEnabled'] and not c['disabledDns']
      assert not c['workDns'] and not c['workLan']
      assert c['dns']['listen-address'] == [address]
      assert c['dns']['bind-interfaces'] == [True] and c['dns']['no-resolv'] == [True]
      assert c['dns']['host-record'] == [name + ',' + address]
      assert c['dns']['local'] == ['/' + name + '/']
      assert address not in c['dns']['server'] and c['dns']['server']
      assert c['dns']['cache-size'][0] <= 256 and c['dns']['dns-forward-max'][0] <= 64
      assert {53, 443} <= set(c['lanFirewall']['allowedTCPPorts'])
      assert 53 in c['lanFirewall']['allowedUDPPorts']
      assert 53 not in c['workGlobalPorts'] and 443 not in c['workGlobalPorts']
      assert 'dnsmasq --test' in c['preStart']
      marker = '@' + route + ' host ' + name
      assert marker in c['caddy'] and marker not in c['disabledCaddy']
      block = c['caddy'].split('handle @' + route + ' {', 1)[1].split('\n      }', 1)[0]
      guard = '@' + route + '_lan_write'
      assert guard + ' not method GET HEAD' in [line.strip() for line in block.splitlines()]
      assert '@' + route + '_outside_lan not remote_ip ' + address + '/' in block
      assert 'respond @' + route + '_outside_lan "Use Tailscale to reach the service owner" 403' in block
      assert 'respond ' + guard + ' "LAN display access is read-only" 405' in block
      assert block.index('respond ' + guard) < block.index('reverse_proxy ')
      assert 'reverse_proxy ' + c['upstream'] in block
      assert 'tls_server_name ' + name in block
  check(cfg)
  for key in ['caddy', 'dns']:
      bad = copy.deepcopy(cfg)
      if key == 'caddy':
          bad[key] = bad[key].replace('not method GET HEAD', 'not method GET HEAD POST')
      else:
          bad[key]['listen-address'] = ['0.0.0.0']
      try:
          check(bad)
      except AssertionError:
          pass
      else:
          raise AssertionError(('unsafe LAN configuration accepted', key))
  print('LAN DNS, read-only proxy and independent remote access wiring checked')
  PY
  touch "$out"
'';

private-origin-firewall = let
  fixture = pkgs.writeText "private-origin-firewall.json" (builtins.toJSON
    (lib.genAttrs [ "hwc-work" "hwc-home" ] (host: let
      c = self.nixosConfigurations.${host}.config;
    in {
      inherit (c.networking.firewall) enable allowedTCPPorts allowedTCPPortRanges trustedInterfaces;
      tailnet = c.networking.firewall.interfaces.tailscale0.allowedTCPPorts;
      tailnetRanges = c.networking.firewall.interfaces.tailscale0.allowedTCPPortRanges;
      caddy = c.services.caddy.extraConfig;
      brainPort = if c.hwc.server.ai.brainMcp.enable then c.hwc.server.ai.brainMcp.port else null;
      logPort = c.hwc.networking.cloudflared.accessLog.port;
    })));
in pkgs.runCommand "private-origin-firewall" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  python3 - ${fixture} <<'PY'
  import copy, json, pathlib, re, sys
  configs = json.loads(pathlib.Path(sys.argv[1]).read_text())
  def contains(ports, ranges, port):
      return port in ports or any(r['from'] <= port <= r['to'] for r in ranges)
  def check(host, c):
      # Extract the actual rendered tailnet listeners, independently of
      # the Nix route filter that also generates firewall allowances.
      ports = {80, 443} | {int(p) for p in re.findall(r'^\s*[^\s{}]+\.ts\.net:(\d+)\s*\{', c['caddy'], re.M)}
      if c['brainPort'] is not None:
          ports.add(c['brainPort'])
      assert c['enable']
      for port in ports:
          # Home has its own explicit global HTTPS policy. This repair
          # preserves that separate policy; work is the public origin.
          if host == 'hwc-work' or port != 443:
              assert not contains(c['allowedTCPPorts'], c['allowedTCPPortRanges'], port), (host, 'global private port', port)
          assert 'tailscale0' in c['trustedInterfaces'] or contains(c['tailnet'], c['tailnetRanges'], port), (host, 'missing tailnet port', port)
      # Explicit service rules must survive even if Tailscale's blanket
      # trust is narrowed later. Dev previews use that existing trust.
      assert {80, 443} <= set(c['tailnet'])
      if c['brainPort'] is not None:
          assert c['brainPort'] in c['tailnet']
      assert not contains(c['allowedTCPPorts'], c['allowedTCPPortRanges'], c['logPort'])
      if host == 'hwc-work':
          assert set(c['allowedTCPPorts']) == {22, 22000}
          assert not c['allowedTCPPortRanges']
  for host, c in configs.items():
      check(host, c)
  for port in [80, 443, configs['hwc-work']['brainPort']]:
      bad = copy.deepcopy(configs['hwc-work'])
      bad['allowedTCPPorts'].append(port)
      try:
          check('hwc-work', bad)
      except AssertionError:
          pass
      else:
          raise AssertionError(('seeded global leak accepted', port))
  print('work/home private listeners retain tailnet access; global leaks rejected')
  PY
  touch "$out"
'';

# Wave 4 compatibility contract: the old entry point survives while
# only work owns the application. Remove the legacy-port assertion only
# with wave 5 evidence that old clients have moved.
n8n-route-compatibility = let
  server = self.nixosConfigurations."hwc-home".config;
  work = self.nixosConfigurations."hwc-work".config;
  route = lib.findFirst (r: r.name == "n8n") null
    work.hwc.networking.shared.effectiveRoutes;
  port = toString route.port;
  ownerIp = work.hwc.networking.hosts.ips.work;
  ownerName = work.hwc.networking.hosts.fqdn.work;
  oldListener = "${server.hwc.networking.shared.rootHost}:${port}";
  serverCaddy = server.services.caddy.extraConfig;
  workVhosts = lib.attrNames (lib.filterAttrs (name: o: o.owner == "work" && o.mode == "vhost"
    && !(lib.elem name server.hwc.networking.reverseProxy.lanAccess.routes))
    work.hwc.networking.shared.routeOwners);
in
assert lib.assertMsg (lib.all (name:
  !(lib.hasInfix "@${name} host ${name}." serverCaddy)) workVhosts)
  "route cleanup: a work vhost fallback returned on home";
assert lib.assertMsg (lib.hasInfix "handle @webhook" serverCaddy
  && lib.hasInfix "reverse_proxy ${ownerIp}:${toString work.hwc.system.mcp.port}" serverCaddy)
  "route cleanup: shared webhook or MCP entrypoint missing";
assert lib.assertMsg (!server.hwc.automation.n8n.enable && work.hwc.automation.n8n.enable)
  "n8n compatibility: work must be the only declared writer";
assert lib.assertMsg (lib.hasInfix oldListener serverCaddy
  && lib.hasInfix "reverse_proxy https://${ownerIp}:${port}" serverCaddy
  && lib.hasInfix "tls_server_name ${ownerName}" serverCaddy
  && lib.hasInfix "header_up Host ${ownerName}" serverCaddy
  && lib.elem route.port server.networking.firewall.interfaces.tailscale0.allowedTCPPorts
  && !(lib.elem route.port server.networking.firewall.allowedTCPPorts))
  "n8n compatibility: former-owner listener, upstream, TLS identity or firewall missing";
assert lib.assertMsg (lib.hasInfix "${ownerName}:${port}" work.services.caddy.extraConfig
  && lib.hasInfix "reverse_proxy http://127.0.0.1:${toString work.hwc.automation.n8n.port}" work.services.caddy.extraConfig)
  "n8n compatibility: work does not serve the local application";
pkgs.runCommand "n8n-route-compatibility" {} ''touch "$out"'';

briefing-mcp-routing = let
  c = self.nixosConfigurations.hwc-work.config;
  route = lib.findFirst (r: r.name == "briefing") null c.hwc.networking.shared.effectiveRoutes;
  fixture = pkgs.writeText "briefing-mcp-routing.json" (builtins.toJSON {
    caddy = c.services.caddy.extraConfig;
    hostname = "briefing.${c.hwc.networking.shared.vhostDomain}";
    inherit (route) root;
    upstream = lib.removePrefix "http://" (lib.head route.api).upstream;
    source = repoRoot + "/domains/business/morning-briefing/dashboard";
  });
in pkgs.runCommand "briefing-mcp-routing" {
  nativeBuildInputs = [ pkgs.python3 c.services.caddy.package ];
} ''
  python3 - ${fixture} <<'PY'
  import copy, http.server, json, pathlib, shutil, socket, subprocess, sys, threading, time, urllib.request
  f = json.loads(pathlib.Path(sys.argv[1]).read_text())
  pathlib.Path('production.Caddyfile').write_text(f['caddy'])
  adapted = json.loads(subprocess.check_output(['caddy', 'adapt', '--config', 'production.Caddyfile', '--adapter', 'caddyfile']))
  matches = []
  def find(value):
      if isinstance(value, dict):
          if isinstance(value.get('match'), list) and any(isinstance(m, dict) and f['hostname'] in m.get('host', []) for m in value['match']):
              matches.append(value)
          for child in value.values(): find(child)
      elif isinstance(value, list):
          for child in value: find(child)
  find(adapted)
  assert len(matches) == 1, 'expected one actual briefing host route'
  site = pathlib.Path('site').resolve()
  site.mkdir()
  for name in ['mcp-client.mjs', 'view-policy.json']:
      shutil.copyfile(pathlib.Path(f['source']) / name, site / name)
  class Gateway(http.server.BaseHTTPRequestHandler):
      def do_GET(self):
          self.send_response(201); self.end_headers(); self.wfile.write(b'gateway fixture')
      def log_message(self, *args): pass
  backend = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Gateway)
  threading.Thread(target=backend.serve_forever, daemon=True).start()
  def substitute(value):
      if isinstance(value, dict): return {k: substitute(v) for k, v in value.items()}
      if isinstance(value, list): return [substitute(v) for v in value]
      if value == f['root']: return str(site)
      if value == f['upstream']: return '127.0.0.1:' + str(backend.server_port)
      return value
  actual = substitute(matches[0])
  def exercise(route):
      with socket.socket() as sock:
          sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
      config = {'admin': {'disabled': True}, 'apps': {'http': {'servers': {'fixture': {
          'listen': ['127.0.0.1:' + str(port)], 'automatic_https': {'disable': True}, 'routes': [route]
      }}}}}
      pathlib.Path('fixture.json').write_text(json.dumps(config))
      with open('runtime.log', 'a') as log:
          process = subprocess.Popen(['caddy', 'run', '--config', 'fixture.json'], stdout=subprocess.DEVNULL, stderr=log)
          try:
              for attempt in range(100):
                  try:
                      with socket.create_connection(('127.0.0.1', port), timeout=.1): break
                  except OSError: time.sleep(.02)
              else: raise AssertionError('Caddy fixture did not start')
              def read(path):
                  request = urllib.request.Request('http://127.0.0.1:' + str(port) + path, headers={'Host': f['hostname']})
                  with urllib.request.urlopen(request, timeout=3) as response:
                      return response.status, response.headers, response.read()
              for path in ['/mcp', '/mcp/session']:
                  status, headers, body = read(path)
                  assert status == 201 and body == b'gateway fixture', path
              status, headers, body = read('/mcp-client.mjs')
              assert status == 200 and body == (site / 'mcp-client.mjs').read_bytes(), 'MCP proxy captured the static transport'
              assert 'javascript' in headers['Content-Type'], headers['Content-Type']
              status, headers, body = read('/view-policy.json')
              assert status == 200 and json.loads(body)['schemaVersion'] == 1
          finally:
              process.terminate(); process.wait(timeout=5)
  try:
      exercise(actual)
      bad = copy.deepcopy(actual)
      replaced = []
      def broaden(value):
          if isinstance(value, dict):
              if isinstance(value.get('path'), list) and set(value['path']) == {'/mcp', '/mcp/*'}:
                  value['path'] = ['/mcp*']; replaced.append(True)
              for child in value.values(): broaden(child)
          elif isinstance(value, list):
              for child in value: broaden(child)
      broaden(bad)
      assert replaced, 'MCP matcher missing from adapted production route'
      try: exercise(bad)
      except AssertionError as error:
          assert 'captured the static transport' in str(error), error
          print('seeded broad MCP proxy rejected')
      else: raise AssertionError('broad MCP proxy regression was accepted')
  finally:
      backend.shutdown(); backend.server_close()
  print('actual briefing API and static assets route independently')
  PY
  touch "$out"
'';

gluetun-client-contract = let
  c = self.nixosConfigurations.hwc-home.config;
  fixture = pkgs.writeText "gluetun-client-contract.json" (builtins.toJSON {
    stateRoot = c.hwc.networking.gluetun.stateRoot;
    qbittorrent = pkgs.writeText "qbittorrent-port-sync.sh" c.systemd.services.gluetun-port-sync.script;
    slskd = pkgs.writeText "slskd-port-sync.sh" c.systemd.services.gluetun-slskd-port-sync.script;
  });
in pkgs.runCommand "gluetun-client-contract" {
  nativeBuildInputs = [ pkgs.python3 pkgs.bash pkgs.jq pkgs.gawk pkgs.coreutils ];
} ''
  export PYTHONDONTWRITEBYTECODE=1
  python3 ${./gluetun-clients.py} ${fixture}
  touch "$out"
'';
}
