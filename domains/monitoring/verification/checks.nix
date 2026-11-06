# Pure verification function; not a NixOS or Home Manager module.
{ inputs, lib, pkgs, repoRoot, self, system }:
{

# ── Prometheus tier ladders are mutually exclusive ──────────────────
# Parses the ACTUAL rule expressions (not a second copy of the numbers)
# and proves no sample value can satisfy two tiers of one family. Before
# the 2026-09-07 change a 96%-full filesystem matched Moderate, Elevated
# and High at once and sent three messages about one fact.
alert-tier-exclusivity = let
  alertRules = import (repoRoot + "/domains/monitoring/prometheus/parts/alerts.nix") { inherit lib; };
  allRules = lib.concatMap (g: g.rules) alertRules.groups;
  ruleNamed = name:
    let hits = lib.filter (r: r.alert == name) allRules;
    in if hits == [] then null else builtins.head hits;
  # Expressions are multi-line; flatten before matching so `.` never has
  # to cross a newline.
  flat = s: lib.concatStringsSep " " (lib.splitString "\n" s);
  boundsOf = name:
    let
      rule = ruleNamed name;
      e = flat rule.expr;
      lower = builtins.match ".*> ([0-9.]+).*" e;
      upper = builtins.match ".*<= ([0-9.]+).*" e;
    in
      assert lib.assertMsg (rule != null)
        "alert-tier-exclusivity: no rule named ${name} — a rename silently empties this check";
      assert lib.assertMsg (lower != null)
        "alert-tier-exclusivity: ${name} has no `> N` lower bound to parse";
      {
        inherit name;
        lower = lib.toInt (builtins.head lower);
        upper = if upper == null then null else lib.toInt (builtins.head upper);
      };
  # Ordered high tier first. Only the top tier may be unbounded above.
  families = {
    cpu    = [ "HighCPUUsage" "ElevatedCPUUsage" ];
    memory = [ "HighMemoryUsage" "ElevatedMemoryUsage" ];
    disk   = [ "HighDiskUsage" "ElevatedDiskUsage" "ModerateDiskUsage" ];
  };
  # Every threshold in use, each ±1, plus the ends of the scale. Bounds are
  # whole numbers, so integer samples cross every boundary exactly.
  samples = [ 0 50 69 70 71 81 82 83 84 85 86 89 90 91 94 95 96 99 100 ];
  matches = b: v: v > b.lower && (b.upper == null || v <= b.upper);
  overlaps = lib.concatLists (lib.mapAttrsToList (family: names:
    let bounds = map boundsOf names;
    in lib.concatMap (v:
      let hit = lib.filter (b: matches b v) bounds;
      in lib.optional (lib.length hit > 1)
        "${family}: sample ${toString v} matches ${
          lib.concatStringsSep " + " (map (b: b.name) hit)}"
    ) samples
  ) families);
  unboundedLowTiers = lib.concatLists (lib.mapAttrsToList (family: names:
    map (b: "${family}: ${b.name} has no upper bound but is not the top tier")
      (lib.filter (b: b.upper == null) (map boundsOf (builtins.tail names)))
  ) families);
  problems = overlaps ++ unboundedLowTiers;
in
assert lib.assertMsg (problems == [])
  "alert tier ladders overlap:\n  ${lib.concatStringsSep "\n  " problems}";
pkgs.runCommand "alert-tier-exclusivity" {} ''touch "$out"'';

# ── The alert rules are valid PromQL, per Prometheus' own parser ────
# alert-tier-exclusivity proves the tier NUMBERS cannot overlap. It cannot
# prove the expressions PARSE — it reads them as strings with
# builtins.match, so a rule file Prometheus rejects passes it clean. The
# 2026-09-07 tier work introduced chained comparisons (`> 82 <= 85`), a
# form this repo had never shipped, and an unparseable rule file does not
# degrade gracefully: prometheus.service refuses to start, which takes
# every alert — and therefore the whole notification path — with it.
# Checked against the FILES THE SERVER WILL LOAD (read off the evaluated
# config) rather than a second rendering of parts/alerts.nix, so this
# cannot pass on a copy while the deployed file is broken.
# Parses the rules of whichever registered server runs the central
# Prometheus (hwc-work since service split wave 3).
alert-rules-parse = let
  servers = lib.attrValues self.nixosConfigurations."hwc-home".config.hwc.networking.hosts.servers;
  central = lib.findFirst
    (h: self.nixosConfigurations ? ${h} && self.nixosConfigurations.${h}.config.hwc.monitoring.prometheus.enable)
    null servers;
  prom = self.nixosConfigurations.${central}.config.services.prometheus;
  ruleFiles = prom.ruleFiles ++ map (r: pkgs.writeText "exported-rules.yml" r) prom.rules;
in
assert lib.assertMsg (central != null && ruleFiles != [])
  "alert-rules-parse: no registered server runs the central Prometheus — this check has no subject and would pass empty";
pkgs.runCommand "alert-rules-parse" {
  nativeBuildInputs = [ pkgs.prometheus.cli ];
} ''
  promtool check rules ${lib.concatMapStringsSep " " toString ruleFiles}
  touch $out
'';

# ── Every OnFailure= notifier points at a unit that exists ──────────
# Derived from the EVALUATED hwc-home config, so it needs no second
# copy of the monitored list. A name that resolves to no ExecStart is a
# stub unit: it reads as coverage and delivers nothing (seven such dead
# entries were found by hand on 2026-08-26).
# Every serving host alerts on its own units (service split): check each.
alert-onfailure-units = let
  onFailureOf = svc:
    let v = (svc.unitConfig or {}).OnFailure or null;
    in if v == null then ""
       else if builtins.isList v then lib.concatStringsSep " " v
       else toString v;
  deadOn = host: let
    c = self.nixosConfigurations.${host}.config;
    monitored = lib.filter
      (n: lib.hasInfix "hwc-service-failure-notifier@" (onFailureOf c.systemd.services.${n}))
      (builtins.attrNames c.systemd.services);
    unitText = n:
      let t = (c.systemd.units."${n}.service" or {}).text or null;
      in if t == null then "" else t;
  in map (n: "${host}:${n}") (lib.filter (n: !(lib.hasInfix "ExecStart=" (unitText n))) monitored);
  dead = lib.concatMap deadOn [ "hwc-home" "hwc-work" ];
  preservesUnit = host: let
    c = self.nixosConfigurations.${host}.config;
    system = c.systemd.services."hwc-service-failure-notifier@".serviceConfig.ExecStart;
    user = c.systemd.user.services."hwc-service-failure-notifier@".serviceConfig.ExecStart;
  in lib.hasSuffix " %i" system && lib.hasSuffix " --user %i" user
    && lib.hasInfix (builtins.unsafeDiscardStringContext "ExecStart=${system}")
      c.systemd.units."hwc-service-failure-notifier@.service".text;
in
assert lib.assertMsg (dead == [])
  ("monitored units with no ExecStart (OnFailure= on these is a silent no-op): "
   + lib.concatStringsSep ", " dead);
assert lib.assertMsg (lib.all preservesUnit [ "hwc-home" "hwc-work" ])
  "failure notifier must preserve literal unit names with %i, not unescape hyphens with %I";
pkgs.runCommand "alert-onfailure-units" {} ''touch "$out"'';

# Service-split retirement contract, evaluated through production units.
fleet-map-routing = let
  work = self.nixosConfigurations.hwc-work.config;
  home = self.nixosConfigurations.hwc-home.config;
  unit = work.systemd.services.fleet-map-publish;
in
assert lib.assertMsg (work.hwc.monitoring.fleet-map.enable
  && work.hwc.networking.shared.routeOwners.map.owner == "work"
  && lib.hasInfix "@map host map." work.services.caddy.extraConfig
  && !(lib.hasInfix "@map host map." home.services.caddy.extraConfig))
  "fleet-map must be published only by its work owner";
assert lib.assertMsg (lib.hasInfix "--capture" unit.script
  && lib.hasInfix "/run/wrappers/bin" unit.environment.PATH
  && lib.hasInfix "/run/current-system/sw/bin" unit.environment.PATH
  && unit.serviceConfig.TimeoutStartSec == "10min")
  "fleet-map publisher needs the real host commands and a bounded lifetime";
pkgs.runCommand "fleet-map-routing" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  cd ${inputs.fleet-map}
  PYTHONDONTWRITEBYTECODE=1 python3 -m unittest -v
  touch "$out"
'';
# Actual exporter + scrape wiring. Distinct failures: missing browser header,
# missing page CSP, missing private cache policy and wrong HTTPS redirect.
website-security-probes = let
  c = self.nixosConfigurations.hwc-work.config;
  fixture = pkgs.writeText "website-security-probes.json" (builtins.toJSON {
    config = c.services.prometheus.exporters.blackbox.configFile;
    jobs = c.services.prometheus.scrapeConfigs;
    rules = c.services.prometheus.ruleFiles;
    alert = lib.findFirst (r: r.alert == "WebsiteSecurityCheckFailed") null
      (lib.concatMap (g: g.rules) (import (repoRoot + "/domains/monitoring/prometheus/parts/alerts.nix") { inherit lib; }).groups);
  });
in pkgs.runCommand "website-security-probes" {
  nativeBuildInputs = [ pkgs.python3 self.nixosConfigurations.hwc-work.pkgs.prometheus-blackbox-exporter pkgs.prometheus.cli ];
} ''
  python3 - ${fixture} <<'PY'
  import http.server,json,pathlib,socket,subprocess,sys,threading,time,urllib.request,urllib.parse
  f=json.loads(pathlib.Path(sys.argv[1]).read_text())
  jobs={j['job_name']:j for j in f['jobs']}
  for name,module in [('probe-website-security','website_security'),('probe-website-https','website_https_redirect'),('probe-report-privacy','report_privacy')]:
      assert jobs[name]['params']['module']==[module]
      assert jobs[name]['scrape_interval']=='2m'
  class Fixture(http.server.BaseHTTPRequestHandler):
      def log_message(self,*args): pass
      def do_GET(self):
          private='private' in self.path; redirect='redirect' in self.path
          body=b'<meta http-equiv="Content-Security-Policy" content="script-src self">' if self.path!='/no-meta' else b'missing policy'
          self.send_response(404 if private else 308 if redirect else 200)
          headers={'Content-Type':'text/html','X-Content-Type-Options':'nosniff','X-Frame-Options':'SAMEORIGIN','Strict-Transport-Security':'max-age=604800','Content-Security-Policy':"object-src 'none'",'Permissions-Policy':'camera=()','Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex','Location':'https://iheartwoodcraft.com/'}
          if self.path=='/no-frame':headers.pop('X-Frame-Options')
          if self.path=='/bad-private':headers.pop('Cache-Control')
          if self.path=='/bad-redirect':headers['Location']='http://attacker.invalid/'
          for key,value in headers.items():self.send_header(key,value)
          self.end_headers();self.wfile.write(body)
  server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Fixture)
  threading.Thread(target=server.serve_forever,daemon=True).start()
  with socket.socket() as sock:sock.bind(('127.0.0.1',0));port=sock.getsockname()[1]
  process=subprocess.Popen(['blackbox_exporter','--config.file='+f['config'],'--web.listen-address=127.0.0.1:'+str(port)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
  base='http://127.0.0.1:'+str(port)
  try:
      for _ in range(100):
          try:urllib.request.urlopen(base+'/metrics',timeout=1).close();break
          except OSError:time.sleep(.05)
      else:raise AssertionError('exporter startup failed')
      for module,path,success in [('website_security','/good',1),('website_security','/no-frame',0),('website_security','/no-meta',0),('report_privacy','/private',1),('report_privacy','/bad-private',0),('website_https_redirect','/redirect',1),('website_https_redirect','/bad-redirect',0)]:
          query=urllib.parse.urlencode({'module':module,'target':'http://127.0.0.1:'+str(server.server_port)+path})
          text=urllib.request.urlopen(base+'/probe?'+query,timeout=20).read().decode()
          assert '\nprobe_success '+str(success)+'\n' in text,(module,path,text)
  finally:process.terminate();process.wait(timeout=5);server.shutdown();server.server_close()
  alert=f['alert'];assert alert['for']=='5m'
  test={'rule_files':f['rules'],'evaluation_interval':'1m','tests':[{
      'interval':'1m','input_series':[{'series':'probe_success{job="probe-website-security",instance="fixture"}','values':'0+0x6 1+0x7'}],
      'alert_rule_test':[{'eval_time':t,'alertname':alert['alert'],'exp_alerts':[] if t!='6m' else [{'exp_labels':{'job':'probe-website-security','instance':'fixture',**alert['labels']},'exp_annotations':{k:v.replace('{{ $labels.instance }}','fixture') for k,v in alert['annotations'].items()}}]} for t in ['4m','6m','14m']]}]}
  pathlib.Path('alert-transition.json').write_text(json.dumps(test))
  subprocess.run(['promtool','test','rules','alert-transition.json'],check=True)
  print('PASS actual security probes, seeded regressions and alert pending/firing/recovered states')
  PY
  touch "$out"
'';

# Calculator monitoring follows the website's public intake, not the private
# estimator webhook. Exercise the actual scrape wiring and alert transitions.
calculator-intake-monitoring = let
  c = self.nixosConfigurations.hwc-work.config;
  fixture = pkgs.writeText "calculator-intake-monitoring.json" (builtins.toJSON {
    intake = c.hwc.business.website.leadsWebhookUrl;
    jobs = c.services.prometheus.scrapeConfigs;
    ruleFiles = c.services.prometheus.ruleFiles;
    rules = lib.concatMap (g: g.rules)
      (import (repoRoot + "/domains/monitoring/prometheus/parts/alerts.nix") { inherit lib; }).groups;
    blackbox = c.services.prometheus.exporters.blackbox.configFile;
  });
in pkgs.runCommand "calculator-intake-monitoring" {
  nativeBuildInputs = [ pkgs.python3 pkgs.prometheus.cli ];
} ''
  python3 - ${fixture} <<'PY'
  import json,pathlib,subprocess,sys
  f=json.loads(pathlib.Path(sys.argv[1]).read_text())
  jobs={j['job_name']:j for j in f['jobs']}
  assert 'probe-webhook-ingress' not in jobs, 'Retired public estimate webhook still monitored'
  job=jobs['probe-crm-intake']
  targets=[t for group in job['static_configs'] for t in group['targets']]
  assert f['intake'] in targets, 'Website calculator intake is not monitored'
  assert job['params']['module']==['http_options_2xx']
  module=json.loads(pathlib.Path(f['blackbox']).read_text())['modules']['http_options_2xx']['http']
  assert module['method']=='OPTIONS' and module['valid_status_codes']==[200,204]
  assert module['headers']['Access-Control-Request-Method']=='POST'
  rules={r['alert']:r for r in f['rules']}
  assert 'WebhookIngressDown' not in rules, 'Retired public estimate alert still installed'
  assert all('probe-webhook-ingress' not in r['expr'] for r in f['rules'])
  assert 'probe-crm-intake' in rules['WebsiteSSLCertExpiringSoon']['expr']
  alert=rules['CrmIntakeDown']
  assert alert['for']=='5m' and alert['labels']['severity']=='P5'
  test={'rule_files':f['ruleFiles'],'evaluation_interval':'1m','tests':[{
      'interval':'1m','input_series':[{'series':'probe_success{job="probe-crm-intake",instance="fixture"}','values':'0+0x6 1+0x7'}],
      'alert_rule_test':[{'eval_time':t,'alertname':alert['alert'],'exp_alerts':[] if t!='6m' else [{'exp_labels':{'job':'probe-crm-intake','instance':'fixture',**alert['labels']},'exp_annotations':{k:v.replace('{{ $labels.instance }}','fixture') for k,v in alert['annotations'].items()}}]} for t in ['4m','6m','14m']]}]}
  pathlib.Path('intake-transition.json').write_text(json.dumps(test))
  subprocess.run(['promtool','test','rules','intake-transition.json'],check=True,timeout=30)
  print('PASS current calculator intake, safe preflight and pending/firing/recovered alert states')
  PY
  touch "$out"
'';

}
