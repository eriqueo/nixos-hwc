# Pure verification function; not a NixOS or Home Manager module.
{ inputs, lib, mailHome, mailHost, pkgs, repoRoot, self, system }:
{
# Credential checks use fake secrets; no server or real secret is accessed.
# Runs on every host that syncs calendar + tasks and pins the rendered
# wiring: Radicale is the only CalDAV backend, and todoman reads the vdir
# the tasks pair writes. The server kept a dead iCloud tasks pair (and a
# todoman path over it) until 2026-09-24 because only the laptop was checked.
radicale-client-auth = let
  hosts = builtins.attrNames (lib.filterAttrs (_: home:
    lib.attrByPath [ "hwc" "mail" "calendar" "enable" ] false home.config
  ) self.homeConfigurations);
  fixture = pkgs.writeText "radicale-client-config.json" (builtins.toJSON (map (host:
    let home = self.homeConfigurations.${host}.config;
    in {
      inherit host;
      todui = lib.optionalAttrs home.programs.todui.enable {
        command = home.programs.todui.radicale.passwordCommand;
        username = home.programs.todui.radicale.username;
      };
      sync = home.xdg.configFile."vdirsyncer/config".text;
      todoman = home.xdg.configFile."todoman/config.py".text;
    }) hosts));
in assert lib.assertMsg (hosts != []) "radicale-client-auth: no enabled calendar client";
pkgs.runCommand "radicale-client-auth" {
  nativeBuildInputs = [ pkgs.python3 pkgs.gawk ];
} ''
  python3 - ${fixture} <<'PY'
  import configparser, json, pathlib, re, shlex, subprocess, sys
  for cfg in json.loads(pathlib.Path(sys.argv[1]).read_text()):
      host = cfg["host"]
      assert "caldav.icloud.com" not in cfg["sync"], f"{host}: vdirsyncer still syncs iCloud"
      sync = configparser.RawConfigParser()
      sync.read_string(cfg["sync"])
      pairs = sorted(s.split(" ", 1)[1] for s in sync.sections() if s.startswith("pair "))
      assert pairs == ["calendar_radicale", "contacts_radicale", "tasks_radicale"], \
          f"{host}: expected only the three Radicale pairs, got {pairs}"
      tasks_dir = json.loads(sync["storage tasks_radicale_local"]["path"])
      todo_path = re.search(r'^\s*path = "(.*)"$', cfg["todoman"], re.M).group(1)
      assert todo_path == tasks_dir.rstrip("/") + "/*", \
          f"{host}: todoman reads {todo_path}, tasks pair writes {tasks_dir}"
      print(f"{host}: Radicale-only; todoman reads the tasks pair's vdir")
      clients = []
      if cfg["todui"]:
          clients.append(("todui", cfg["todui"]["username"], cfg["todui"]["command"]))
      for name in ("tasks", "calendar", "contacts"):
          section = sync[f"storage {name}_radicale_remote"]
          fetch = json.loads(section["password.fetch"])
          assert fetch.pop(0) == "command"
          clients.append((name, json.loads(section["username"]), fetch))
      users = sorted({user for _, user, _ in clients})
      secret = pathlib.Path("secret fixture'quoted")
      expected = {user: f"fixture:{i}:with spaces" for i, user in enumerate(users)}
      secret.write_text("unrelated:other\n" + "".join(
          f"{user}:{password}\n" for user, password in expected.items()
      ) + "unrelated-last:other-last\n")
      for name, user, command in clients:
          if isinstance(command, str):
              original = shlex.split(command)[-1]
              command = command.replace(shlex.quote(original), shlex.quote(str(secret)))
              result = subprocess.run(command, shell=True, capture_output=True, text=True)
          else:
              command[-1] = str(secret)
              result = subprocess.run(command, capture_output=True, text=True)
          assert result.returncode == 0, f"{host} {name}: credential command failed"
          assert result.stdout == expected[user] + "\n", f"{host} {name}: wrong user's password"
          print(f"{host} {name}: selected only its user's complete password")
  PY
  touch $out
'';

# Seed failures through the same taxonomy helper used by Sieve and the
# Gmail janitor. Force the views: tryEval alone only checks the outer set.
mail-trash-guard = let
  data = import (repoRoot + "/domains/mail/taxonomy/data.nix");
  taxonomy = import (repoRoot + "/domains/mail/taxonomy/lib.nix") { inherit lib data; };
  accepts = trash: protection: (builtins.tryEval (builtins.deepSeq
    (import (repoRoot + "/domains/mail/taxonomy/lib.nix") {
      inherit lib;
      data = data // { senders = data.senders // {
        inherit trash;
        protected = protection;
      }; };
    }).derived true)).success;
  badEntries = [
    "comms.contractorcto.com" "x@iheartwoodcraft.com" "proton.me"
    "news.proton.me" "alerts@limitloginattempts.com" "mail.instagram.com"
    "Contractorcto@gmail.com" "gmail.com" "com" "@junk.example"
    { sender = "semrush.com"; scope = "gmail"; }
    { list = "@business-noreply@mail.instagram.com"; }
    { list = "list@support@sub.limitloginattempts.com"; }
    { list = "@ContractorCTO@GMAIL.COM"; }
    { sender = "junk.example"; scope = "protno"; }
    { list = "@noise@junk.example"; scope = "both"; }
    { list = "@noise@junk.example"; scope = "gmail"; }
    { sender = "junk.example"; list = "@noise@junk.example"; }
    { scope = "proton"; }
    { sender = "junk.example"; typo = true; }
    { sender = "@noise@junk.example"; }
    { sender = ""; } { sender = 42; } { list = ""; }
    { sender = "junk.example\nother.example"; } 42
  ];
  upperProtection = lib.mapAttrs (_: map lib.toUpper) data.senders.protected;
  clean = [ "other@gmail.com" { sender = "noise.example"; scope = "proton"; }
    { list = "@help@profitabletradie.com"; } "no-reply@news.proton.me" ];
  home = mailHome;
  system = self.nixosConfigurations.${mailHost}.config;
  filters = import (repoRoot + "/domains/mail/aerc/parts/sieve-filters.nix") { inherit lib; };
in
assert lib.assertMsg (lib.all (entry: !accepts [ entry ] data.senders.protected) badEntries)
  "mail-trash-guard: unsafe or malformed trash entry accepted";
assert lib.assertMsg (!accepts [ "comms.contractorcto.com" ] upperProtection
  && !accepts [ { list = "@business-noreply@mail.instagram.com"; } ] upperProtection)
  "mail-trash-guard: protection is case-sensitive";
assert lib.assertMsg (accepts clean data.senders.protected)
  "mail-trash-guard: narrow reviewed entries rejected";
assert lib.assertMsg (lib.length taxonomy.derived.trashSenders == 15
  && builtins.fromJSON system.systemd.services.mail-janitor.environment.MJ_DENY == taxonomy.derived.trashSenders)
  "mail-trash-guard: Gmail janitor projection changed beyond reviewed removals";
assert lib.assertMsg (lib.all (name: home.home.file.".config/aerc/sieve/${name}".text == filters.${name})
  (builtins.attrNames filters)
  && !(home.home.file ? ".config/aerc/sieve/filters/bundle.sieve"))
  "mail-trash-guard: Home Manager does not deploy the two generated filters";
pkgs.runCommand "mail-trash-guard" {} ''touch "$out"'';

# Parse and replay the actual Home Manager files, not a parallel renderer.
mail-proton-sieve = let
  home = mailHome;
  filters = lib.genAttrs [ "01-junk.sieve" "02-routing.sieve" ]
    (name: home.home.file.".config/aerc/sieve/${name}".text);
  fixture = pkgs.writeText "proton-sieve.json" (builtins.toJSON filters);
in pkgs.runCommand "mail-proton-sieve" {
  nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.sievelib ])) ];
} ''
  python3 - ${fixture} <<'PY'
  import fnmatch
  import json
  import pathlib
  import sys
  from email.utils import getaddresses

  from sievelib import commands
  from sievelib.parser import Parser

  # sievelib omits RFC 5235's spamtest and numeric comparator. Register only
  # their grammar; fixtures below supply a score/threshold, never call Proton.
  commands.comparator['extra_arg']['values'].append('"i;ascii-numeric"')


  class SpamtestCommand(commands.TestCommand):
      extension = 'spamtest'
      args_definition = [commands.comparator, commands.match_type,
                         {'name': 'value', 'type': ['string'], 'required': True}]


  commands.add_commands(SpamtestCommand)


  def strings(value):
      return [json.loads(v).lower() for v in (value if isinstance(value, list) else [value])]


  def matches(test, headers, spam):
      args = test.arguments
      if test.name == 'not':
          return not matches(args['test'], headers, spam)
      if test.name in ('allof', 'anyof'):
          values = [matches(t, headers, spam) for t in args['tests']]
          return all(values) if test.name == 'allof' else any(values)
      if test.name == 'environment':
          return True  # Proton provides the configured spam threshold.
      if test.name == 'spamtest':
          return spam
      if test.name not in ('header', 'address'):
          raise AssertionError(f'Unhandled test: {test.name}')
      fields = strings(args['header-list' if test.name == 'address' else 'header-names'])
      values = [headers[field].lower() for field in fields if field in headers]
      if test.name == 'address':
          values = [addr for _, addr in getaddresses(values)]
          if args.get('address-part') == ':domain':
              values = [addr.rsplit('@', 1)[-1] for addr in values]
      keys = strings(args['key-list'])
      mode = args.get('match-type', ':is')
      compare = {':is': lambda v, k: v == k,
                 ':contains': lambda v, k: k in v,
                 ':matches': lambda v, k: fnmatch.fnmatchcase(v, k)}[mode]
      return any(compare(value, key) for value in values for key in keys)


  def actions(tree, headers, spam=False):
      result = set()
      for node in tree:
          if node.name == 'require':
              continue
          assert node.name == 'if'
          if not matches(node.arguments['test'], headers, spam):
              continue
          for action in node.children:
              if action.name == 'stop':
                  return result, True
              assert action.name in ('fileinto', 'addflag'), action.name
              result.update((action.name, value) for value in strings(next(iter(action.arguments.values()))))
      return result, False


  filters = json.loads(pathlib.Path(sys.argv[1]).read_text())
  parsed = {}
  # Sieve retains folder/read effects; System One alone assigns @ labels.
  allowed = {'trash', 'archive', 'hide_my_email'}


  def check_targets(tree):
      for node in tree:
          if node.name == 'fileinto':
              assert set(strings(node.arguments['mailbox'])) <= allowed
          check_targets(node.children)


  for name, text in filters.items():
      parser = Parser()
      assert parser.parse(text), getattr(parser, 'error', name)
      parsed[name] = parser.result
      check_targets(parser.result)
      for node in parser.result:
          for action in node.children:
              if action.name == 'fileinto':
                  assert set(strings(action.arguments['mailbox'])) <= allowed
              if action.name == 'addflag':
                  assert '\\flagged' not in strings(next(iter(action.arguments.values())))
      print(f'{name}: syntax and targets pass')
  parser = Parser()
  assert not parser.parse('require ["fileinto"]; if true { fileinto "Trash" }')
  for target in ['work', '@hwc']:
      parser = Parser()
      assert parser.parse('require ["fileinto"]; if true { fileinto "' + target + '"; }')
      try:
          check_targets(parser.result)
      except AssertionError:
          pass
      else:
          raise AssertionError('label target guard accepted ' + target)


  def deliver(**headers):
      result = set()
      spam = headers.pop('spam', False)
      for name in sorted(parsed):
          part, stopped = actions(parsed[name], headers, spam)
          result |= part
          if stopped:
              break
      return result


  def expect(expected, **headers):
      actual = deliver(**headers)
      wanted = {('addflag', '\\seen') if value == 'Seen' else ('fileinto', value.lower())
                for value in expected}
      assert actual == wanted, (headers, actual, wanted)


  expect([], to='eric@iheartwoodcraft.com')
  expect([], to='eriqueo@proton.me')
  expect([], to='eric@contractorcto.com')
  expect([], **{'from': 'hi@xotara.us'})
  expect([], **{'from': 'tony.fraserjones@profitabletradie.com'})
  expect([], **{'x-pm-list-identifier': '@certification@narihq.org'})
  expect([], **{'from': 'hello@classdojo.com'})
  expect([], **{'from': 'hello@classdojo.com', 'spam': True})
  expect([], **{'from': 'position-tracking@semrush.com'})
  expect([], **{'x-pm-list-identifier': '@billing@limitloginattempts.com'})
  expect(['Seen'], **{'from': 'notifications@github.com'})
  expect([], **{'x-pm-list-identifier': '@business-noreply@mail.instagram.com'})
  expect([], **{'from': 'alerts@notify.wellsfargo.com'})
  expect([], **{'from': 'onlinebanking@ealerts.bankofamerica.com'})
  expect([], **{'from': 'statefarmservice@statefarmservice.com'})
  expect([], **{'x-pm-list-identifier': '@nicole.dray@farther.com'})
  expect([], **{'from': 'office@kenyonnoble.com'})
  expect(['Seen'], **{'from': 'no-reply@accounts.google.com'})
  expect(['Archive', 'Seen'], **{'x-pm-list-identifier': '@vimeo@vimeo.com'})
  expect(['Archive', 'Seen'], **{'from': 'builds@sr.ht'})
  expect(['Archive', 'Seen'], **{'from': 'dmarc@example.net'})
  expect(['Archive', 'Seen'], **{'from': 'support@comms.datax.to',
         'to': 'hello@contractorcto.com', 'subject': 'New demo request → Example'})
  expect([], **{'from': 'support@comms.datax.to', 'to': 'hello@contractorcto.com',
         'subject': 'Customer needs a reply'})
  expect(['hide_my_email'], to='camelcity.derail128@passmail.com')
  expect(['Trash', 'Seen'], **{'from': 'noise@sub.angi.com', 'to': 'eric@iheartwoodcraft.com'})
  expect(['Trash', 'Seen'], **{'x-pm-list-identifier': '@team@emails.hostinger.com'})
  expect(['Trash', 'Seen'], **{'x-pm-list-identifier': '@help@profitabletradie.com'})
  expect([], **{'from': 'tom@thecontractorfight.com', 'spam': True})
  expect([], **{'from': 'tom@thecontractorfight.com'})
  expect([], **{'from': 'sales@klingspor.com'})
  expect([], **{'from': 'person@otherangi.com'})
  expect([], **{'from': 'other@gmail.com'})
  print('32 delivery fixtures pass; seeded broken syntax and label targets rejected')
  PY
  touch "$out"
'';

# ── Aerc's human workflow stays smaller than its mail taxonomy ─────
# The taxonomy intentionally retains automation and legacy tags, but the
# generated which-key surface must not flatten that whole vocabulary into
# one menu. Exercise the exact server Home Manager output consumed by the
# live aerc process, including noinherit tab contexts and tag commands.
aerc-bindings = let
  home = mailHome;
  binds = home.home.file.".config/aerc/binds.conf".text;
  lines = lib.splitString "\n" binds;
  directMarkLines = lib.filter
    (line: builtins.match "[[:space:]]*<Space>m. =.*" line != null)
    lines;
  contract = home.hwc.mail.classifier.contract;
  tags = import (repoRoot + "/domains/mail/aerc/parts/tags.nix") { inherit lib; mailContract = contract; };
  required = [
    "/ = :filter<space>"
    "<Space>fa = :query -f -n mail-search<space>"
    "<Space>fa = :close<Enter>:query -f -n mail-search<space>"
    "<Space>ff = :close<Enter>:filter<space>"
    "<Space>wi = :pipe -s -m"
    "<Space>wn = :next-part<Enter>"
    "<Space>wp = :prev-part<Enter>"
    "<Space>oc = :pipe -m email-to-khal<Enter>"
    "<A-h> = :prev-tab<Enter>"
    "<A-l> = :next-tab<Enter>"
    "<A-J> = :next-tab<Enter>"
    "<A-K> = :prev-tab<Enter>"
    "<A-S-j> = :next-tab<Enter>"
    "<A-S-k> = :prev-tab<Enter>"
    "<Space>ft = :filter tag:"
    "<Space>fT = :query -f -n tag-search tag:"
    "<Space>fc = :clear -s<Enter>"
    "<Space>mu = :unsubscribe -s<Enter>"
    "D = :pipe -b -m mail-classifier transition --outcome trash<Enter>"
    "pipe -b -m mail-classifier correct --state do"
    "pipe -b -m mail-classifier correct --state did"
    "pipe -b -m mail-classifier correct --state dont-know"
    "<Space>gk = :cf DONT KNOW<Enter>"
    "<Space>gb = :cf Bulk<Enter>"
    "pipe -b -m mail-classifier correct --domain datax"
    "pipe -m mail-classifier route-review"
    "term mail-classifier route-manage"
  ];
  missing = lib.filter (needle: !(lib.hasInfix needle binds)) required;
in
assert lib.assertMsg (missing == [])
  "aerc-bindings: generated server binds are missing ${lib.concatStringsSep ", " missing}";
assert lib.assertMsg (lib.length directMarkLines <= 22)
  "aerc-bindings: first mark popup has ${toString (lib.length directMarkLines)} entries across list/view (limit 22)";
assert lib.assertMsg (!(lib.hasInfix "<Space>m! =" binds) && !(lib.hasInfix "<Space>m? =" binds))
  "aerc-bindings: action/pending leaked back into the human mark menu";
assert lib.assertMsg (!(lib.hasInfix "-keep" tags.clearFlagsCmd) && !(lib.hasInfix "-keep" tags.clearAllCmd))
  "aerc-bindings: a bulk clear can remove the protected keep tag";
assert lib.assertMsg (builtins.all (tag: !(lib.elem "-${tag}" (lib.splitString " " tags.clearAllCmd)))
  ([ "flagged" "starred" "keep" "work" "finance" "family" "action" "pending" ]
    ++ map (domain: "${contract.domainTagPrefix}${domain}") contract.domains))
  "aerc-bindings: metadata clear strips stars, historical tags or Domain";
assert lib.assertMsg (lib.hasInfix "modify-labels ${tags.clearAllCmd}" binds
  && lib.hasInfix "modify-labels +ads" binds
  && !(lib.hasInfix "+work -" binds))
  "aerc-bindings: optional facts or safe-clear production wiring changed";
assert lib.assertMsg (let
  registry = import (repoRoot + "/domains/mail/notmuch/parts/searches.nix") {
    inherit lib; cfg = home.hwc.mail.notmuch; mailContract = contract;
  };
  aercQueries = home.home.file.".config/aerc/notmuch-queries".text;
  deployed = home.xdg.configFile."notmuch/searches".text;
in deployed == registry.text
  && builtins.all (name: lib.hasInfix "${lib.replaceStrings [ ":" ] [ "/" ] name}=${registry.searches.${name}}" aercQueries)
    (builtins.attrNames registry.searches)
  && registry.searches."fact:finance" == "tag:${contract.traitTagPrefix}finance"
  && registry.searches."state:dont-know" == "tag:${contract.stateTagPrefix}dont-know"
  && registry.searches."view:bulk" == contract.viewQueries.bulk
  && registry.searches."domain:family" == "tag:${contract.domainTagPrefix}family"
  && registry.searches."history:family" == "tag:family"
  && !(registry.searches ? business) && !(registry.searches ? money)
  && !(registry.searches ? "label:finance"))
  "aerc-bindings: current axes and historical search registry drifted";
pkgs.runCommand "aerc-bindings" {
  nativeBuildInputs = [ pkgs.python3 pkgs.notmuch pkgs.tmux pkgs.bash
    (lib.findFirst (p: (p.pname or "") == "aerc") null home.home.packages) ];
  queries = home.home.file.".config/aerc/notmuch-queries".source;
  bindsFile = home.home.file.".config/aerc/binds.conf".source;
  configFile = home.home.file.".config/aerc/aerc.conf".source;
  stylesFile = home.home.file.".config/aerc/stylesets/hwc".source;
} ''
  python3 - "$queries" "$bindsFile" "$configFile" "$stylesFile" <<'PY'
  import json, os, pathlib, shlex, subprocess, sys, tempfile, time
  queries = dict(line.split('=', 1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()
                 if line and not line.startswith('#'))
  assert all(':' not in name for name in queries), queries
  binds = pathlib.Path(sys.argv[2]).read_text()
  # Match the macro parser's backslash decoding before parsing commands.
  def command_text(value):
      return value.replace(chr(92) * 2, chr(92))
  # Check the generated production config, including viewer noinherit.
  sections = {}
  section = 'global'
  for line in binds.splitlines():
      line = line.strip()
      if line.startswith('['):
          section = line
      elif '=' in line and not line.startswith(('#', '$')):
          key = line.split('=', 1)[0].strip()
          current = sections.setdefault(section, {})
          assert key not in current, (section, key)
          current[key] = line
  for section, rows in sections.items():
      keys = [k for k in rows if k.startswith('<Space>')]
      for key in keys:
          assert not any(other != key and other.startswith(key) for other in keys), (section, key)
      assert 'i' not in rows and 'I' not in rows, (section, 'retired shortcuts')
  for section in ['[messages]', '[view]']:
      for key in ['mc', 'mr', 'mf']:
          if key == 'mr':
              assert ':choose ' not in sections[section].get("<Space>" + key, "")
          else:
              assert '<Space>' + key not in sections[section]
      for key in ['cc', 'cr', 'ca', 'cf']:
          assert '<Space>' + key in sections[section]
  for section, aliases in {
      '[messages]': {'a': 'ma', 'd': 'dd', 'D': 'dd',
                     'J': 'mj', 'K': 'mk', 'c': 'cc', 'C': 'ca', 'X': 'mx', 'Y': 'ym'},
      '[view]': {'r': 'cr', 'R': 'ca', 'f': 'cf', 'a': 'ma', 'd': 'dd',
                 'u': 'ol', 't': 'ot', 'p': 'op'},
  }.items():
      for bare, chord in aliases.items():
          command = lambda line: line.split(' = ', 1)[1].split(' # ', 1)[0]
          wanted = command(sections[section]['<Space>' + chord])
          if section == '[view]' and bare in ('a', 'd'):
              wanted += ':close<Enter>'
          assert command(sections[section][bare]) == wanted, (section, bare, chord)
  assert ':read<Enter>' in sections['[messages]']['r']
  assert ':unread<Enter>' in sections['[messages]']['u']
  # Explicit accepted viewer exceptions: r replies; u opens the URL picker.
  assert ':reply<Enter>' in sections['[view]']['r']
  assert 'urlscan' in sections['[view]']['u']
  assert '<Space>bc' not in sections['[messages]']
  assert '<Space>wi' in sections['[view]'] and '<Space>wi' not in sections['[messages]']
  for key in ['<Space>ms', '<Space>md', '<Space>mt', '<Space>ml', '<Space>mv', '<Space>fd']:
      for section in ['[messages]', '[view]']:
          line = sections[section][key]
          options = shlex.split(command_text(line.split(':choose ', 1)[1].split('<Enter>', 1)[0]))
          assert len(options) % 4 == 0
          choices = [options[i+1] for i in range(0, len(options), 4)]
          assert len(choices) == len(set(choices)) and 0 < len(choices) <= 12, choices
  with tempfile.TemporaryDirectory() as root:
      root = pathlib.Path(root)
      mail = root / 'mail'
      for folder in ['inbox', 'archive']:
          for part in ['cur', 'new', 'tmp']:
              (mail / folder / part).mkdir(parents=True)
      config = root / 'notmuch-config'
      config.write_text(f'[database]\npath={mail}\n[user]\nname=Test\nprimary_email=test@example.com\n[new]\ntags=\n[maildir]\nsynchronize_flags=true\n')
      os.environ['NOTMUCH_CONFIG'] = str(config)
      def nm(*args):
          return subprocess.check_output(['notmuch', *args], text=True).strip()
      for mid in ['old', 'current']:
          (mail / 'inbox' / 'cur' / f'{mid}:2,F').write_text(
              f'From: sender@example.com\nTo: test@example.com\nMessage-ID: <{mid}@example.com>\nSubject: {mid}\nDate: Thu, 1 Oct 2026 12:00:00 -0600\n\nfixture\n')
      (mail / 'archive' / 'cur' / 'copy:2,F').write_text((mail / 'inbox' / 'cur' / 'current:2,F').read_text())
      nm('new')
      nm('tag', '+inbox', '+work', '+family', '+finance', '--', 'id:old@example.com')
      nm('tag', '+inbox', '+state/do', '+domain/hwc', '+trait/finance', '+ads', '+keep', '--', 'id:current@example.com')
      assert nm('count', queries['domain/hwc']) == '1'
      assert nm('count', queries['finance']) == '1'
      assert nm('count', queries['history/business']) == '1'
      assert nm('count', queries['history/family']) == '1'
      assert nm('count', queries['domain/family']) == '0'
      clear = next(line for line in binds.splitlines() if '<Space>mt =' in line)
      options = shlex.split(command_text(clear.split('= :choose ', 1)[1].split('<Enter>', 1)[0]))
      command = next(options[i+3] for i in range(0, len(options), 4) if options[i+1] == 'x')
      assert command.startswith('modify-labels '), command
      operations = shlex.split(command)[1:]
      before = nm('search', '--output=files', 'id:current@example.com').splitlines()
      nm('tag', *operations, '--', 'id:current@example.com')
      tags = set(nm('search', '--output=tags', 'id:current@example.com').splitlines())
      assert {'flagged', 'keep', 'state/do', 'domain/hwc', 'inbox'} <= tags, tags
      assert 'trait/finance' not in tags and 'ads' not in tags, tags
      after = nm('search', '--output=files', 'id:current@example.com').splitlines()
      assert len(before) == len(after) == 2 and set(before) == set(after)
      assert all(path.endswith(':2,F') for path in after), after
      old_tags = set(nm('search', '--output=tags', 'id:old@example.com').splitlines())
      assert {'work', 'family', 'finance', 'flagged'} <= old_tags, old_tags
      # Exercise the real key decoder and native dialogs on isolated mail.
      # This catches Notmuch's native thread fetch ignoring sort criteria.
      for idx, subject in enumerate(['Zebra needle', 'Alpha', 'Middle']):
          (mail / 'inbox' / 'cur' / f'remap-{idx}:2,').write_text(
              f'From: sender@example.com\nTo: test@example.com\nMessage-ID: <remap-{idx}@example.com>\nSubject: {subject}\nDate: Thu, 1 Oct 2026 12:0{idx}:00 -0600\n\nfixture body\n')
      (mail / 'inbox' / 'cur' / 'remap-reply:2,').write_text(
          'From: sender@example.com\nTo: test@example.com\nMessage-ID: <remap-reply@example.com>\nIn-Reply-To: <remap-1@example.com>\nReferences: <remap-1@example.com>\nSubject: Re: Alpha\nDate: Thu, 1 Oct 2026 12:03:00 -0600\n\nfixture reply\n')
      nm('new')
      for mid in ['remap-0', 'remap-1', 'remap-2', 'remap-reply']:
          nm('tag', '+remap-fixture', '+state/do', '--', f'id:{mid}@example.com')
      assert nm('count', 'tag:remap-fixture') == '4'
      querymap = root / 'querymap'
      querymap.write_text('do=tag:remap-fixture\n')
      accounts = root / 'accounts.conf'
      accounts.write_text(f'[fixture]\nsource=notmuch://{mail}\nfrom=Test <test@example.com>\nquery-map={querymap}\nfolders=do\ndefault=do\n')
      conf = root / 'aerc.conf'
      # Parse the actual production styles, including the spaced State
      # alias, in the isolated client rather than hiding style failures.
      style_dir = root / 'stylesets'; style_dir.mkdir()
      (style_dir / 'hwc').write_text(pathlib.Path(sys.argv[4]).read_text())
      conf.write_text(pathlib.Path(sys.argv[3]).read_text().replace('styleset-name = hwc', 'styleset-name = hwc\nstylesets-dirs = ' + str(style_dir)))
      socket = str(root / 'tmux.sock')
      def tm(*args):
          return subprocess.check_output(['tmux', '-S', socket, '-f', '/dev/null', *args], text=True)
      def screen():
          return tm('capture-pane', '-p', '-t', 'fixture')
      def keys(value):
          tm('send-keys', '-t', 'fixture', '-l', value)
          time.sleep(0.7)
          return screen()
      def special(value):
          tm('send-keys', '-t', 'fixture', value)
          time.sleep(0.7)
          return screen()
      command = shlex.join(['aerc', '-I', '-C', str(conf), '-B', sys.argv[2], '-A', str(accounts)])
      os.environ['SHELL'] = '${pkgs.bash}/bin/bash'
      os.environ['TERM'] = 'xterm-256color'
      os.environ['TZ'] = 'UTC'
      # Exercise production bindings without touching the live ledger.
      # A noisy successful child exposes foreground terminal regressions.
      fixture_bin = root / 'bin'
      fixture_bin.mkdir()
      call_file = root / 'quiet-call.json'
      failure_file = root / 'quiet-failure'
      classifier = fixture_bin / 'mail-classifier'
      classifier.write_text(
          '#!${pkgs.python3}/bin/python3\n'
          'import json, pathlib, sys\n'
          f'call = pathlib.Path({str(call_file)!r})\n'
          'message = sys.stdin.read()\n'
          'call.write_text(json.dumps({"args": sys.argv[1:], "message": message}))\n'
          'print("QUIET_ACTION_RESULT")\n'
          f'sys.exit(42 if pathlib.Path({str(failure_file)!r}).exists() else 0)\n')
      classifier.chmod(0o755)
      os.environ['PATH'] = str(fixture_bin) + os.pathsep + os.environ['PATH']
      def quiet_action(chord, expected, option=None):
          call_file.unlink(missing_ok=True)
          keys(chord)
          if option is not None:
              keys(option)
              special('Enter')
          for _ in range(30):
              if call_file.exists():
                  break
              time.sleep(0.1)
          assert call_file.exists(), screen()
          call = json.loads(call_file.read_text())
          assert call['args'] == expected, call
          assert 'Message-ID: <remap-0@example.com>' in call['message'], call
          time.sleep(0.1)
          output = screen()
          assert 'QUIET_ACTION_RESULT' not in output and 'mail-classifier <' not in output, output
          assert 'Zebra needle' in output, output
          return output
      try:
          tm('new-session', '-d', '-s', 'fixture', '-x', '150', '-y', '40', command)
          for _ in range(20):
              time.sleep(0.3)
              if 'Zebra needle' in screen():
                  break
          assert 'Zebra needle' in screen(), screen()
          output = keys(' sa')
          assert output.index('Alpha') < output.index('Middle') < output.index('Zebra needle'), output
          keys(':select 0')
          special('Enter')
          output = keys(' tt')
          assert '{2}Alpha' in output and '└─>' not in output, output
          output = keys(' tt')
          assert '{2}Alpha' not in output and '└─>' in output, output
          assert ':filter' in keys(' ff')
          special('Escape')
          assert ':query -f -n mail-search' in keys(' fa')
          keys('needle')
          output = special('Enter')
          assert 'Zebra needle' in output and 'Alpha' not in output, output
          assert 'fixture body' in special('Enter')
          assert 'local image preview' in keys(' w').lower()
          special('Escape')
          output = keys(' ms')
          assert all(word in output for word in ['DO', 'DONT KNOW', 'DID', 'LOOK', 'JUNK']), output
          special('Escape')
          output = keys(' mt')
          assert 'Clear optional facts' in output, output
          keys('a')
          output = special('Enter')
          assert '+ads' in output and '+receipts' in output, output
          keys('g')
          special('Enter')
          assert 'ads' in nm('search', '--output=tags', 'id:remap-0@example.com').splitlines()
          keys(' mt')
          keys('x')
          special('Enter')
          current = nm('search', '--output=tags', 'id:remap-0@example.com').splitlines()
          assert 'ads' not in current and 'state/do' in current, current
          assert ':filter' in keys(' ff')
          special('Escape')
          for chord, outcome in [('a', 'done'), ('d', 'trash'), ('D', 'trash'),
                                 (' ma', 'done'), (' dd', 'trash')]:
              quiet_action(chord, ['transition', '--outcome', outcome])
          quiet_action(' ms', ['correct', '--state', 'look'], 'l')
          quiet_action(' ms', ['correct', '--state', 'dont-know'], 'k')
          quiet_action(' md', ['correct', '--domain', 'personal'], 'p')
          for chord, outcome in [('a', 'done'), ('d', 'trash')]:
              assert 'fixture body' in special('Enter')
              output = quiet_action(chord, ['transition', '--outcome', outcome])
              assert 'fixture body' not in output, output
          failure_file.touch()
          output = quiet_action('a', ['transition', '--outcome', 'done'])
          assert 'exit status 42' in output, output
      finally:
          subprocess.run(['tmux', '-S', socket, 'kill-server'], capture_output=True)

      # Actual spaced alias/default parsing and Bulk partition. These
      # synthetic messages never use the real ledger or remote mail.
      samples = {
          'unknown-direct': ('Need sorting', ['state/dont-know']),
          'unknown-bulk': ('Newsletter seed', ['state/dont-know', 'trait/newsletter']),
          'unknown-security': ('Security seed', ['state/dont-know', 'trait/newsletter', 'trait/security']),
          'confirmed-promo': ('Confirmed action seed', ['state/do', 'trait/newsletter']),
      }
      for mid, (subject, tags) in samples.items():
          (mail / 'inbox' / 'cur' / f'{mid}:2,').write_text(
              f'From: sender@example.com\nTo: test@example.com\nMessage-ID: <{mid}@example.com>\nSubject: {subject}\nDate: Thu, 1 Oct 2026 13:00:00 -0600\n\nfixture body\n')
      nm('new')
      for mid, (subject, tags) in samples.items():
          nm('tag', '+inbox', *('+' + tag for tag in tags), '--', f'id:{mid}@example.com')
      querymap.write_text(pathlib.Path(sys.argv[1]).read_text())
      assert nm('count', queries['DONT KNOW']) == '2'
      assert nm('count', queries['Bulk']) == '1'
      assert nm('count', queries['state/dont-know']) == '3'
      accounts.write_text(f'[fixture]\nsource=notmuch://{mail}\nfrom=Test <test@example.com>\nquery-map={querymap}\nfolders=DO,DONT KNOW,DID,LOOK,JUNK,Bulk\ndefault=DONT KNOW\n')
      try:
          tm('new-session', '-d', '-s', 'fixture', '-x', '150', '-y', '40', command)
          for _ in range(20):
              time.sleep(0.3)
              if 'Need sorting' in screen(): break
          output = screen()
          assert 'Need sorting' in output and 'DONT KNOW' in output and 'Security seed' in output, output
          assert 'Newsletter seed' not in output and 'Confirmed action seed' not in output, output
          output = keys(' gb')
          assert 'Newsletter seed' in output and 'Need sorting' not in output and 'Security seed' not in output, output
          output = keys(' gk')
          assert 'Need sorting' in output and 'Newsletter seed' not in output, output
          output = keys(' gi')
          assert 'Confirmed action seed' in output and 'Need sorting' not in output, output
      finally:
          subprocess.run(['tmux', '-S', socket, 'kill-server'], capture_output=True)
  print('generated views, real metadata clear, quiet action tabs and visible failures pass')
  PY
  touch "$out"
'';

# The calm reading view prefers the sender-authored plain part. HTML is
# still available with the MIME-part keys when layout carries meaning.
aerc-rendering = let
  home = mailHome;
  aercConf = home.home.file.".config/aerc/aerc.conf".text;
  imageWiring = pkgs.writeText "aerc-image-wiring.json" (builtins.toJSON {
    binds = home.home.file.".config/aerc/binds.conf".text;
    conf = aercConf;
  });
  plainFilterLine = builtins.head (lib.filter
    (line: lib.hasPrefix "text/plain = " line)
    (lib.splitString "\n" aercConf));
  plainFilter = lib.removePrefix "text/plain = " plainFilterLine;
  filterRunner = pkgs.writeShellScript "test-aerc-plain-filter" plainFilter;
  longUrl = "https://tracking.example/campaign/abcdefghijklmnopqrstuvwxyz0123456789/abcdefghijklmnopqrstuvwxyz0123456789?recipient=fixture";
  fixture = pkgs.writeText "aerc-plain-message.txt" ''
    Nicole sent you a new request.



    The useful message stays visible, while this tracking machinery does not: <${longUrl}>

    This paragraph is intentionally long enough to prove that the configured aerc wrap stage uses a calm reading measure instead of expanding prose across a very wide terminal window where it becomes hard to scan.
  '';
in
assert lib.assertMsg (lib.hasInfix "alternatives = text/plain,text/html" aercConf)
  "aerc-rendering: plain text is not the default MIME alternative";
pkgs.runCommand "aerc-rendering" {} ''
  export TERM=xterm-256color
  export LC_ALL=C.UTF-8
  ${filterRunner} < ${fixture} > rendered
  ${pkgs.python3}/bin/python3 -c 'import sys; sys.stdout.buffer.write(b"\x1b[31muntrusted\x1b[0m\n")' \
    | ${filterRunner} > sanitized
  ${pkgs.python3}/bin/python3 - rendered sanitized ${lib.escapeShellArg longUrl} <<'PY'
  import pathlib
  import re
  import sys

  rendered = pathlib.Path(sys.argv[1]).read_bytes()
  sanitized = pathlib.Path(sys.argv[2]).read_bytes()
  target = sys.argv[3].encode()
  expected_link = b"\x1b]8;;" + target + b"\x1b\\"
  assert expected_link in rendered, "long URL target was not preserved in OSC 8 link"
  assert b"\x1b" not in sanitized, "untrusted terminal control reached the viewer"

  visible = re.sub(rb"\x1b]8;;.*?\x1b\\(.*?)\x1b]8;;\x1b\\", rb"\1", rendered)
  text = visible.decode()
  assert target not in visible, "long tracking URL remains visible"
  assert "↗ tracking.example" in text, "compact link label is missing"
  assert "\n\n\n" not in text, "excess blank lines remain"
  assert max(map(len, text.splitlines())) <= 100, "visible line exceeds reading measure"
  assert text.count("Nicole sent you a new request.") == 1, "message content changed or duplicated"
  PY
  ${pkgs.python3}/bin/python3 - ${imageWiring} <<'PY'
  import json, re, shlex, struct, subprocess, sys, zlib
  from email.message import EmailMessage
  from email import policy
  from pathlib import Path

  wiring = json.loads(Path(sys.argv[1]).read_text())
  def image_command(binds):
      view = binds.split('[view]\n', 1)[1].split('[view::', 1)[0]
      line = next(line.strip() for line in view.splitlines() if line.strip().startswith('<Space>wi = '))
      assert line.startswith('<Space>wi = :pipe -s -m '), 'image view must receive full MIME and close on pager exit'
      return line.removeprefix('<Space>wi = :pipe -s -m ').split('<Enter>', 1)[0]
  command = image_command(wiring['binds'])
  for broken in [re.sub(r'^\s*<Space>wi = .*$', "", wiring['binds'], flags=re.M),
                 wiring['binds'].replace('<Space>wi = :pipe -s -m ', '<Space>wi = :pipe -s -p ')]:
      assert broken != wiring['binds'], 'seeded wiring mutation did not match'
      try:
          image_command(broken)
      except (StopIteration, AssertionError):
          pass
      else:
          raise AssertionError('image wiring check accepted a removed or part-only binding')
  assert not re.search(r'^image/\*\s*=', wiring['conf'].split('[filters]', 1)[1].split('[openers]', 1)[0], re.M)
  # Run the generated binding, replacing only its interactive pager.
  pager_pattern = r'/nix/store/[^\s]+/bin/less -R -~'
  assert len(re.findall(pager_pattern, command)) == 1
  command = re.sub(pager_pattern, '${pkgs.coreutils}/bin/cat', command)
  def chunk(kind, data):
      return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
  png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 2, 0, 0, 0))
  png += chunk(b'IDAT', zlib.compress(b'\0\xff\0\0\0\0\xff' * 2)) + chunk(b'IEND', b"")
  def message(data=png, narrow=False):
      msg = EmailMessage()
      picture = '<img src="cid:picture" alt="Fixture">'
      if narrow:
          picture = '<table width="8"><tr><td>' + picture + '</td></tr></table>'
      msg.set_content('<p>Before picture</p>' + picture +
          '<p>After picture</p><img src="https://tracking.invalid/pixel" alt="Remote">'
          '<img src="cid:missing" alt="Missing">'
          '<p>\x1b[31muntrusted\x1b[0m</p>'
          '<a href="https://example.invalid/?a=1&amp;b=2">Action</a>', subtype='html')
      msg.add_related(data, maintype='image', subtype='png', cid='<picture>')
      return msg.as_bytes(policy=policy.SMTP)
  def run(raw):
      result = subprocess.run(shlex.split(command), input=raw, capture_output=True, timeout=30)
      assert result.returncode == 0, result.stderr
      return result.stdout.decode()
  output = run(message())
  assert all(label in output for label in ['Before picture', '[Fixture]', 'After picture']), repr(output)
  assert output.index('Before picture') < output.index('[Fixture]') < output.index('After picture')
  assert '\x1b[' in output, 'real chafa must produce colored image cells'
  assert '\x1b[31m' not in output, 'sender terminal controls escaped sanitization'
  assert 'Remote: remote image blocked' in output
  assert 'Missing: attached image missing' in output
  assert 'https://example.invalid/?a=1&b=2' in output, 'HTML action URL changed'
  for _ in range(5):
      narrow_output = run(message(narrow=True))
      assert '[Fixture]' in narrow_output, 'narrow layout or bounded decoding lost the image'
  assert 'image could not be displayed' in run(message(b'not a PNG'))
  plain = EmailMessage()
  plain.set_content('Plain message\n\x1b[31muntrusted\x1b[0m')
  assert '\x1b' not in run(plain.as_bytes())
  many = EmailMessage()
  many.set_content('<img src="cid:missing">' * 40, subtype='html')
  bounded = run(many.as_bytes())
  assert bounded.count('attached image missing') == 32
  assert 'Image limit reached' in bounded
  oversized = subprocess.run(shlex.split(command), input=b'x' * (32 * 1024 * 1024 + 1),
                             capture_output=True, timeout=30)
  assert oversized.returncode != 0 and b'Use the normal view' in oversized.stderr
  print('aerc image binding: MIME ordering, real image output, links, blocked remote images, missing/corrupt images, and control sanitization pass')
  PY
  touch "$out"
'';

# Workflow state drives the sidebar; Domain and factual tags are columns
# and filters. Laya is the sole automatic content classifier.
mail-classifier-tests = pkgs.runCommand "mail-classifier-tests" {} ''
  # Exercise the packaged Python boundary, not only the host's Python.
  ${pkgs.python3}/bin/python3 ${inputs.system-one}/scripts/mail_classifier_test.py
  touch "$out"
'';

mail-health-lanes = pkgs.runCommand "mail-health-lanes" {} ''
  ${pkgs.python3}/bin/python3 - ${mailHome.home.file.".local/bin/mail-health-check".source} <<'PYTEST'
  import copy, json, os, pathlib, re, shlex, sqlite3, subprocess, sys, tempfile, time
  source = pathlib.Path(sys.argv[1]).read_text()
  fresh = {'state':'healthy','lastOutcome':'success','exitCode':0,'lastSuccessEpoch':time.time()}
  base = {'schemaVersion':2,'lanes':{key:copy.deepcopy(fresh) for key in ['fetch/proton','index','commands','labels','residency']}}
  review = copy.deepcopy(base)
  review['lanes']['commands'].update(pendingCount=1,oldestPendingAgeSeconds=1801)
  review['lanes']['labels'].update(state='degraded',conflictCount=1)

  def runner(text, root, infrastructure=False):
      # Run the generated producer, routing, cards and publisher. Local
      # probe ports are controlled; no real credentials or services run.
      for name in ['check_gpg','check_pass','check_bridge','check_freshness']:
          injected = 'infra fixture-auth-failed "Fixture authentication is unavailable."' if name=='check_gpg' and infrastructure else ':'
          text,count = re.subn(r'(?m)^\s*'+name+r'\s*$',injected,text)
          assert count==1,(name,count)
      bindings={'SYNC_STATUS':str(root/'status.json'),'TRACKER_FILE':str(root/'tracker.json'),
                'HOST':'fixture','STALE_SECONDS':'0','ESCALATE_SECONDS':'1800'}
      for name,value in bindings.items():
          text,count=re.subn(r'(?m)^\s*'+name+r'=.*$',name+'='+shlex.quote(value),text)
          assert count==1,(name,count)
      ports='send_webhook() { printf "A:%s\\n" "$*"; }\nsend_notify() { printf "N:%s\\n" "$*"; }\n'
      needle='if ! REPORT=$('
      assert text.count(needle)==1
      return text.replace(needle,ports+needle,1)

  def run(script, root, status):
      (root/'status.json').write_text(json.dumps(status))
      result=subprocess.run(['${pkgs.bash}/bin/bash','-c',script],capture_output=True,text=True,
          env={**os.environ,'HOME':str(root),'XDG_STATE_HOME':str(root/'state')})
      assert result.returncode==0,result.stderr
      summary=json.loads((root/'state/mail-health/summary.json').read_text())
      assert summary['checker']=='ok'
      return result.stdout.splitlines(),summary

  def notifications(lines,prefix):return sum(line.startswith(prefix) for line in lines)
  sentinel={'id':'human-card','done':False,'context':'Preserve the human decision.'}
  with tempfile.TemporaryDirectory() as directory:
      root=pathlib.Path(directory);(root/'tracker.json').write_text(json.dumps({'cards':[sentinel]}))
      script=runner(source,root)
      first,summary=run(script,root,review)
      assert {(i['lane'],i['outcome']) for i in summary['issues']}=={('commands','warning'),('labels','warning')},summary
      assert notifications(first,'A:')==2 and notifications(first,'N:')==0,first
      repeated,_=run(script,root,review)
      assert notifications(repeated,'A:')==notifications(repeated,'N:')==0,repeated
      cards=json.loads((root/'tracker.json').read_text())['cards']
      assert sentinel in cards and len([c for c in cards if c['id'].startswith('MH-')])==2,cards
      stale=copy.deepcopy(review);stale['lanes']['index']['lastSuccessEpoch']=1
      opened,summary=run(script,root,stale)
      assert ('index','critical') in {(i['lane'],i['outcome']) for i in summary['issues']},summary
      assert notifications(opened,'N:')==1,opened
      repeated,_=run(script,root,stale)
      assert notifications(repeated,'A:')==notifications(repeated,'N:')==0,repeated
      closed,summary=run(script,root,base)
      assert summary['issues']==[],summary
      assert notifications(closed,'A:')==3 and notifications(closed,'N:')==0,closed
      cards=json.loads((root/'tracker.json').read_text())['cards']
      assert sentinel in cards and all(c['done'] for c in cards if c['id'].startswith('MH-')),cards
      missing,summary=run(script,root,{})
      assert ('availability','critical') in {(i['lane'],i['outcome']) for i in summary['issues']},summary
      assert notifications(missing,'N:')>=1,missing
      db=sqlite3.connect(root/'state/mail-health/cases.sqlite')
      assert db.execute('SELECT count(*) FROM health_judgments').fetchone()[0]>6
      db.close()

  def check_infrastructure(text):
      with tempfile.TemporaryDirectory() as directory:
          root=pathlib.Path(directory);(root/'tracker.json').write_text(json.dumps({'cards':[sentinel]}))
          script=runner(text,root,infrastructure=True)
          lines,summary=run(script,root,base)
          issue=next((i for i in summary['issues'] if i['code']=='fixture-auth-failed'),None)
          assert issue and issue['outcome']=='warning',summary
          db=sqlite3.connect(root/'state/mail-health/cases.sqlite')
          db.execute('UPDATE health_judgments SET at=? WHERE case_id=?',(time.time()-1900,issue['caseId']))
          db.commit();db.close()
          lines,summary=run(script,root,base)
          issue=next(i for i in summary['issues'] if i['code']=='fixture-auth-failed')
          assert issue['outcome']=='critical' and notifications(lines,'N:')==1,(lines,summary)
          lines,_=run(script,root,base)
          assert notifications(lines,'A:')==notifications(lines,'N:')==0,lines
  check_infrastructure(source)
  needle='--extra-issues "$ISSUES_FILE"'
  assert source.count(needle)==1
  try:check_infrastructure(source.replace(needle,"",1))
  except AssertionError:pass
  else:raise AssertionError('removed infrastructure input passed the generated health check')
  print('generated health: one case store, warnings, missing/stale delivery, escalation, transition alerts and bounded cards pass')
  PYTEST
  touch "$out"
'';

mail-residency-shadow = let
  home = mailHome;
  standalone = self.homeConfigurations."eric@${mailHost}".config;
  system = self.nixosConfigurations.${mailHost}.config;
  ownerDir = builtins.dirOf system.hwc.paths.user.mailSyncStatus;
  producers = with system.systemd.services; [ morning-briefing mail-retriage ];
  transportChannels = (import (repoRoot + "/domains/mail/mbsync/parts/render.nix") { config = home; inherit lib pkgs; }).transportChannels;
  fixture = pkgs.writeText "mail-residency-shadow.json" (builtins.toJSON {
    inherit transportChannels;
    script = home.home.file.".local/bin/sync-mail".text;
    standaloneScript = standalone.home.file.".local/bin/sync-mail".text;
    mbsyncrc = home.home.file.".mbsyncrc".text;
    afew = home.xdg.configFile."afew/config".text;
    command = home.hwc.mail.classifier.residency.command;
    projection = home.hwc.mail.classifier.projection.command;
    statusFile = home.hwc.mail.mbsync.statusFile;
    maildirRoot = home.hwc.mail.notmuch.maildirRoot;
    triage = builtins.readFile (repoRoot + "/domains/business/morning-briefing/triage-mail.sh");
  });
in
assert lib.assertMsg (lib.all (service:
  service.environment.MAIL_SYNC_LOCK_FILE == "${ownerDir}/sync.lock"
  && builtins.elem ownerDir service.serviceConfig.ReadWritePaths) producers
  && system.systemd.services.mail-retriage.serviceConfig.SuccessExitStatus == 75)
  "mail-residency-shadow: scheduled classification must share the writable mail owner lock and defer busy runs";
assert lib.assertMsg (standalone.hwc.mail.classifier.residency.enable
  && standalone.hwc.mail.classifier.projection.enable
  && lib.hasInfix "coordinate" standalone.home.file.".local/bin/sync-mail".text)
  "mail-residency-shadow: standalone client activation must retain mail reconciliation and projection";
assert lib.assertMsg home.hwc.mail.classifier.residency.enable
  "mail-residency-shadow: mail host must observe in shadow";
pkgs.runCommand "mail-residency-shadow" {} ''
  ${pkgs.python3}/bin/python3 - ${fixture} <<'PY'
  import json
  import os
  import pathlib
  import re
  import shlex
  import subprocess
  import sys
  import tempfile

  fixture = json.loads(pathlib.Path(sys.argv[1]).read_text())
  original = fixture['script']
  # Exercise the actual scheduled producer against a held kernel lock.
  # Removing its lock integration must reach the fake effect and fail.
  import fcntl
  import socket
  def classifier_busy(source):
      with tempfile.TemporaryDirectory() as tmp:
          root = pathlib.Path(tmp)
          script = root / 'triage-mail.sh'
          script.write_text(source.replace('/run/current-system/sw/bin/flock', '${pkgs.util-linux}/bin/flock'))
          (root / 'output').mkdir()
          (root / 'output' / 'briefing.json').write_text('{}')
          (root / 'output' / 'mail-triage.json').write_text('{"generated_at":"retained-report","threads_by_state":{}}')
          effect = root / 'effect'
          classifier = root / 'classifier'
          classifier.write_text('#!/bin/sh\ntouch "$CALLS"\nexit 0\n')
          classifier.chmod(0o755)
          model = socket.socket(socket.AF_UNIX)
          model.bind(str(root / 'model.sock'))
          with open(root / 'sync.lock', 'w') as lock:
              fcntl.flock(lock, fcntl.LOCK_EX)
              env = {**os.environ, 'PATH': '${lib.makeBinPath [ pkgs.coreutils pkgs.jq ]}', 'CLASSIFIER_BIN': str(classifier),
                  'MAIL_CLASSIFIER_SOCKET': str(root / 'model.sock'),
                  'MAIL_SYNC_LOCK_FILE': str(root / 'sync.lock'), 'CALLS': str(effect)}
              result = subprocess.run(['${pkgs.bash}/bin/bash', str(script), 'delta'], env=env, capture_output=True, timeout=10)
              assert result.returncode == 75 and not effect.exists(), result.stderr
              published = json.loads((root / 'dashboard' / 'briefing.json').read_text())
              assert published['mail_triage']['generated_at'] == 'retained-report'
          model.close()
  classifier_busy(fixture['triage'])
  stripped = fixture['triage'].replace('/run/current-system/sw/bin/flock -n -E 75 "$' + '{MAIL_SYNC_LOCK_FILE:?mail owner lock binding required}" ', "")
  assert stripped != fixture['triage']
  try:
      classifier_busy(stripped)
  except AssertionError:
      pass
  else:
      raise AssertionError('removed scheduled classifier lock escaped its effect test')
  import copy, importlib.util
  runtime = '${inputs.system-one}/scripts/mail_classifier.py'
  spec = importlib.util.spec_from_file_location('mail', runtime)
  mail = importlib.util.module_from_spec(spec); spec.loader.exec_module(mail)
  def configuration(wrapper):
      return json.loads(pathlib.Path(re.search(r'--config (\S+)',wrapper)[1]).read_text())
  config = configuration(original)
  def wiring(candidate):
      steps = dict(candidate['commandSteps'])
      assert list(steps) == ['flags','apply','mirror','index','ack','final-index']
      assert '--push-flags' in steps['flags']
      assert steps['flags'][-len(fixture['transportChannels']):] == fixture['transportChannels']
      assert '--phase apply' in steps['apply'][-1]
      assert '--phase ack' in steps['ack'][-1]
      assert '--pull-gone' in steps['mirror']
      assert fixture['command'] == candidate['observation'][-1]
      assert fixture['projection'] == candidate['labels'][-1]
      assert candidate['accounts']['proton']['upload'][-2:] == ['proton-drafts','proton-sent']
      assert '[MailMover]' not in fixture['afew']
  wiring(config); wiring(configuration(fixture['standaloneScript']))
  for step in ['flags','mirror','apply','ack']:
      broken=copy.deepcopy(config);broken['commandSteps']=[row for row in broken['commandSteps'] if row[0]!=step]
      try: wiring(broken)
      except AssertionError: pass
      else: raise AssertionError('removed owner wiring passed: '+step)
  broken=copy.deepcopy(config);broken['commandSteps'].append(['mover',['afew','-m','-a']])
  try: wiring(broken)
  except AssertionError: pass
  else: raise AssertionError('competing mover escaped wiring test')
  for failed in ["", 'fetch/proton','fetch/gmail-personal','index','commands/apply','labels','residency']:
      status={};calls=[]
      def execute(argv, timeout):
          calls.append(argv)
          if failed.startswith('fetch/'):
              return 23 if argv == config['accounts'][failed.split('/')[1]]['fetch'] else 0
          actual = config['index'] if failed=='index' else dict(config['commandSteps']).get(failed.removeprefix('commands/')) if failed.startswith('commands/') else config.get('observation' if failed=='residency' else failed)
          return 23 if actual and argv==actual else 0
      rc=mail.coordinate_mail(config,'core',status,execute,lambda:10000,lambda _:None,
          lambda:{'commands':[],'unknownEffects':[]})
      assert rc == (23 if failed.startswith('fetch/') or failed=='index' else 0)
      assert config['index'] in calls
      assert status['lanes']['fetch/gmail-business']['state']=='healthy'
      if failed=='commands/apply':
          assert status['lanes']['core']['state']=='healthy'
          assert status['lanes']['commands']['state']=='degraded'
  with tempfile.TemporaryDirectory() as directory:
      rcfile=pathlib.Path(directory)/'mbsyncrc';rcfile.write_text(fixture['mbsyncrc'])
      parsed=subprocess.run(['${pkgs.isync}/bin/mbsync','-c',str(rcfile),'nonexistent-fixture-channel'],capture_output=True,text=True)
      assert parsed.returncode==1 and "No channel or group named 'nonexistent-fixture-channel' defined." in parsed.stderr, parsed.stderr
      assert 'global options' not in parsed.stderr, parsed.stderr
  blocks=fixture['mbsyncrc'].split('Channel ')
  proton=next(block for block in blocks if block.startswith('proton-wildcards\n'))
  assert 'Sync Pull PushFlags' in proton and 'Expunge Near' in proton
  assert 'Expunge Both' not in proton and 'Create Both' not in proton
  assert all('!"'+name+'"' in proton for name in ['Trash','Drafts','Sent'])
  print('actual coordinator configuration: independent fetch, physical owner, ancillary parity, parser and seeded wiring failures pass')
  PY
  touch "$out"
'';

mail-workflow-v2 = let
  home = mailHome;
  identity = home.programs.notmuch.extraConfig.user;
  ownAddresses = [ identity.primary_email ] ++ lib.splitString ";" identity.other_email;
  controls = lib.findFirst (package: lib.getName package == "mail-classifier")
    (throw "mail-workflow-v2: classifier controls missing") home.home.packages;
  binds = home.home.file.".config/aerc/binds.conf".text;
  aercConf = home.home.file.".config/aerc/aerc.conf".text;
  queries = home.home.file.".config/aerc/notmuch-queries".text;
  queryHas = name: query: lib.elem "${name}=${query}" (lib.splitString "\n" queries);
  hook = home.home.file."/home/eric/400_mail/Maildir/.notmuch/hooks/post-new".text;
  bindLines = lib.splitString "\n" binds;
  bindCount = needle: lib.length (lib.filter (line: lib.hasInfix needle line) bindLines);
  archiveDisposition = "      a = :pipe -b -m mail-classifier transition --outcome done<Enter>";
  trashDisposition = "      d = :pipe -b -m mail-classifier transition --outcome trash<Enter>";
  requiredBinds = [
    "<Space>gA = :cf all<Enter>"
    "<Space>sf = :sort from -r date<Enter>"
    "<Space>sa = :sort subject<Enter>"
    "<Space>ss = :sort subject -r date<Enter>"
  ];
  missingBinds = lib.filter (needle: !(lib.hasInfix needle binds)) requiredBinds;
  hookFixture = pkgs.writeText "mail-post-new-hook" hook;
  afewTest = import (repoRoot + "/domains/mail/afew/package.nix") { inherit lib pkgs; cfg = home.hwc.mail.afew; };
  afewFixture = pkgs.writeText "mail-afew-config" home.xdg.configFile."afew/config".text;
in
assert lib.assertMsg (lib.all (address: lib.elem address ownAddresses)
  [ "eric@iheartwoodcraft.com" "office@iheartwoodcraft.com" "admin@iheartwoodcraft.com" "eric@contractorcto.com" ])
  "mail-workflow-v2: declared identities miss Eric's aliases; self-learning guard would be incomplete";
assert lib.assertMsg (missingBinds == [])
  "mail-workflow-v2: generated server binds are missing ${lib.concatStringsSep ", " missingBinds}";
assert lib.assertMsg (bindCount archiveDisposition == 2 && bindCount trashDisposition == 2
  && !(lib.hasInfix ":unmark -a<Enter>:mark -T<Enter>:modify-labels" binds))
  "mail-workflow-v2: archive/trash must preserve marked-message bulk selections";
assert lib.assertMsg (bindCount "<Space>tt = :fold -t<Enter>" == 1
  && bindCount "<Space>ta = :fold -a<Enter>" == 1
  && !(lib.hasInfix ":toggle-threads<Enter>" binds))
  "mail-workflow-v2: thread fold controls changed unexpectedly";
assert lib.assertMsg (bindCount "<Space>ma = :pipe -b -m mail-classifier transition --outcome done<Enter>" == 2
  && bindCount "<Space>dd = :pipe -b -m mail-classifier transition --outcome trash<Enter>" == 2)
  "mail-workflow-v2: marked-message archive/trash controls changed unexpectedly";
assert lib.assertMsg (lib.hasInfix "sort = -r date" aercConf)
  "mail-workflow-v2: newest-first is not the default sort";
assert lib.assertMsg (queryHas "do" "tag:state/do"
  && queryHas "dont-know" "tag:state/dont-know"
  && queryHas "did" "tag:state/did"
  && queryHas "look" "tag:state/look"
  && queryHas "junk" "tag:state/junk")
  "mail-workflow-v2: workflow state views regressed";
assert lib.assertMsg (!(lib.hasInfix "category/" queries)
  && !(lib.hasInfix "attention/" queries)
  && !(lib.hasInfix "tag:queue" queries)
  && queryHas "all" "NOT tag:trash")
  "mail-workflow-v2: legacy workflow/category folders returned";
assert lib.assertMsg (lib.hasInfix "index-columns = from<20,subject<*,date<10,domain<9,state<9,tags<24" aercConf
  && lib.hasInfix "column-domain" aercConf
  && lib.hasInfix "column-state" aercConf
  && lib.hasInfix "column-tags" aercConf)
  "mail-workflow-v2: workflow columns regressed";
assert lib.assertMsg (!(lib.hasInfix ")(exclude" aercConf))
  "mail-workflow-v2: generated aerc template operands must be whitespace-separated";
pkgs.runCommand "mail-workflow-v2" {} ''
  ${pkgs.python3}/bin/python3 - ${hookFixture} ${controls}/bin/mail-classifier ${afewFixture} <<'PY'
  import fnmatch
  import json
  import os
  import pathlib
  import shlex
  import subprocess
  import sys
  import tempfile

  hook = pathlib.Path(sys.argv[1]).read_text()
  managed_prefix = ${builtins.toJSON mailHome.hwc.mail.classifier.contract.protonSync.managedLabelPrefix}
  managed_mailbox = ${builtins.toJSON mailHome.hwc.mail.classifier.contract.protonSync.labelMailboxPrefix}
  mbsyncrc = ${builtins.toJSON mailHome.home.file.".mbsyncrc".text}
  label_exclusion = '!"' + managed_mailbox + '*"'
  assert label_exclusion in mbsyncrc


  def check_label_isolation(text):
      patterns = shlex.split(next(line for line in text.splitlines()
                                  if line.startswith('Patterns ')))[1:]
      def selected(name):
          result = False
          for pattern in patterns:
              excluded = pattern.startswith('!')
              if fnmatch.fnmatchcase(name, pattern[1:] if excluded else pattern):
                  result = not excluded
          return result
      for name in ['work', 'finance', managed_prefix + 'hwc']:
          assert not selected(managed_mailbox + name), name
      for name in ['INBOX', 'Archive', 'Folders/hide_my_email']:
          assert selected(name), name


  check_label_isolation(mbsyncrc)
  try:
      check_label_isolation(mbsyncrc.replace(label_exclusion, ""))
  except AssertionError:
      pass
  else:
      raise AssertionError('removed label exclusion passed its wiring check')
  folder_state = hook.index("+inbox +state/dont-know")
  remove_new = hook.index("# Remove transient new tag", folder_state)
  assert folder_state < remove_new, "new mail loses its DONT KNOW State"
  assert "mail-rule" not in hook, "retired sender-rule writer returned"
  assert "tag:new AND NOT tag:keep" not in hook, "legacy sender placement returned"

  def check_arrival_states(source):
      with tempfile.TemporaryDirectory() as directory:
          root = pathlib.Path(directory); mail = root / 'Maildir'
          for folder in ['inbox', 'Sent']:
              for part in ['cur', 'new', 'tmp']: (mail / 'proton' / folder / part).mkdir(parents=True)
          config = root / 'notmuch.conf'
          config.write_text('[database]\npath=' + str(mail) + '\n[user]\nname=Fixture\nprimary_email=fixture@example.invalid\n[new]\ntags=new;unread;\n[maildir]\nsynchronize_flags=true\n')
          env = {**os.environ, 'NOTMUCH_CONFIG': str(config), 'XDG_CONFIG_HOME': str(root / 'config')}
          hp = mail / '.notmuch' / 'hooks' / 'post-new'; hp.parent.mkdir(parents=True)
          hp.write_text(source.replace('export NOTMUCH_CONFIG="$HOME/.notmuch-config"', 'export NOTMUCH_CONFIG=' + shlex.quote(str(config))))
          hp.chmod(0o700)
          def nm(*args): return subprocess.check_output(['${pkgs.notmuch}/bin/notmuch', *args], env=env, text=True)
          def tags(mid): return set(json.loads(nm('search', '--format=json', '--output=tags', 'id:' + mid + '@example.invalid')))
          for mid, folder, sender in [('arrival', 'inbox', 'sender@example.invalid'), ('selfsent', 'Sent', 'office@iheartwoodcraft.com')]:
              (mail / 'proton' / folder / 'cur' / (mid + ':2,F')).write_text(
                  'Message-ID: <' + mid + '@example.invalid>\nFrom: ' + sender + '\nTo: eric@iheartwoodcraft.com\nSubject: Synthetic\nDate: Thu, 01 Oct 2026 12:00:00 +0000\n\nFixture\n')
          nm('new')
          for mid in ['arrival', 'selfsent']:
              assert {'inbox', 'state/dont-know', 'flagged'} <= tags(mid), tags(mid)
              assert 'state/do' not in tags(mid), tags(mid)
          nm('tag', '+state/do', '-state/dont-know', '--', 'id:selfsent@example.invalid')
          nm('new')
          assert {'inbox', 'state/do', 'flagged'} <= tags('selfsent'), tags('selfsent')
          assert 'state/dont-know' not in tags('selfsent'), tags('selfsent')
  check_arrival_states(hook)
  try:
      check_arrival_states(hook.replace('+state/dont-know', '+state/do'))
  except AssertionError:
      pass
  else:
      raise AssertionError('removed unknown arrival wiring passed its real-tool replay')

  def check_remote_reopen(source):
      with tempfile.TemporaryDirectory() as directory:
          root = pathlib.Path(directory)
          mail = root / 'Maildir'
          for folder in ['inbox', 'Archive', 'Trash', 'Spam']:
              for part in ['cur', 'new', 'tmp']:
                  (mail / 'proton' / folder / part).mkdir(parents=True)
          config = root / 'notmuch.conf'
          config.write_text('[database]\npath=' + str(mail) + '\n[user]\nname=Fixture\nprimary_email=fixture@example.invalid\n[new]\ntags=new;unread;\n[maildir]\nsynchronize_flags=true\n')
          env = {**os.environ, 'NOTMUCH_CONFIG': str(config),
                 'XDG_CONFIG_HOME': str(root / 'config'), 'PATH': '${pkgs.notmuch}/bin:' + os.environ.get('PATH', "")}
          afew = root / 'config' / 'afew' / 'config'
          afew.parent.mkdir(parents=True)
          afew.write_text(pathlib.Path(sys.argv[3]).read_text().replace('${home.hwc.mail.notmuch.maildirRoot}', str(mail)))
          hp = mail / '.notmuch' / 'hooks' / 'post-new'
          hp.parent.mkdir(parents=True)
          hp.write_text(source.replace('export NOTMUCH_CONFIG="$HOME/.notmuch-config"', 'export NOTMUCH_CONFIG=' + shlex.quote(str(config))))
          hp.chmod(0o700)
          def nm(*args):
              return subprocess.check_output(['${pkgs.notmuch}/bin/notmuch', *args], env=env, text=True)
          archived = mail / 'proton' / 'Archive' / 'cur' / 'fixture:2,S'
          raw = 'Message-ID: <reopen@example.invalid>\nFrom: sender@example.invalid\nTo: fixture@example.invalid\nSubject: Fixture\nDate: Wed, 30 Sep 2026 12:00:00 +0000\n\nSynthetic content\n'
          archived.write_text(raw); nm('new')
          nm('tag', '+workflow/done', '+mail-classified-v2', '+archive', '-inbox', '--', 'id:reopen@example.invalid')
          # The fetched remote move creates another filename for the same
          # known ID. It is not fresh message content or a human correction.
          for path in (mail / 'proton' / 'Archive' / 'cur').iterdir(): path.unlink()
          (mail / 'proton' / 'inbox' / 'cur' / 'reopened:2,S').write_text(raw)
          for _ in range(3):
              nm('new')
              subprocess.run(['${afewTest}/bin/afew', '-t', '-a'], env=env, check=True, capture_output=True)
              tags = json.loads(nm('search', '--format=json', '--output=tags', 'id:reopen@example.invalid'))
              assert 'inbox' in tags and 'archive' not in tags, tags
              assert 'workflow/done' in tags, 'transport repair must not promote S1'
              assert len(list((mail / 'proton' / 'inbox' / 'cur').iterdir())) == 1
  check_remote_reopen(hook)
  reopen_line = next(line for line in hook.splitlines() if 'tag +inbox -archive -trash -spam -sent -draft' in line)
  try:
      check_remote_reopen(hook.replace(reopen_line, ""))
  except AssertionError:
      pass
  else:
      raise AssertionError('removed remote-reopen wiring passed its real-tool replay')

  def check_phone_trash(source):
      assert '[MailMover]' not in source, 'retired mailbox writer returned'
      with tempfile.TemporaryDirectory() as directory:
          root = pathlib.Path(directory); mail = root / 'Maildir'
          for folder in ['inbox', 'Archive', 'Trash', 'Spam']:
              for part in ['cur', 'new', 'tmp']: (mail / 'proton' / folder / part).mkdir(parents=True)
          config = root / 'notmuch.conf'
          config.write_text('[database]\npath=' + str(mail) + '\n[user]\nname=Fixture\nprimary_email=fixture@example.invalid\n[new]\ntags=new;unread;inbox;\n[maildir]\nsynchronize_flags=true\n')
          env = {**os.environ, 'NOTMUCH_CONFIG': str(config), 'XDG_CONFIG_HOME': str(root / 'config'), 'PATH':'${pkgs.notmuch}/bin:' + os.environ.get("PATH", "")}
          afew = root / 'config' / 'afew' / 'config'; afew.parent.mkdir(parents=True)
          afew.write_text(source.replace('${home.hwc.mail.notmuch.maildirRoot}', str(mail)))
          hp = mail / '.notmuch' / 'hooks' / 'post-new'; hp.parent.mkdir(parents=True)
          hp.write_text(hook.replace('export NOTMUCH_CONFIG="$HOME/.notmuch-config"', 'export NOTMUCH_CONFIG=' + shlex.quote(str(config)))); hp.chmod(0o700)
          def nm(*args): return subprocess.check_output(['${pkgs.notmuch}/bin/notmuch', *args], env=env, text=True)
          def move(): subprocess.run(['${afewTest}/bin/afew', '-t', '-a'],env=env,check=True,capture_output=True)
          # Durable human commands also apply to old mail. A fixed old
          # date catches an accidental MailMover age filter.
          raw = 'Message-ID: <trash@example.invalid>\nFrom: sender@example.invalid\nTo: fixture@example.invalid\nSubject: Fixture\nDate: Sat, 01 Jan 2000 12:00:00 +0000\n\nSynthetic content\n'
          inbox = mail / 'proton/inbox/cur/old:2,S'; trash = mail / 'proton/Trash/cur/fetched:2,S'
          inbox.write_text(raw); nm('new'); trash.write_text(raw); nm('new')
          # A partial physical copy and stale Inbox tag are NOT local restore intent.
          move(); assert trash.exists(), 'stale Inbox undid fetched Trash'
          assert inbox.exists(), 'partial copy was deleted'
          inbox.unlink(); nm('new')
          for _ in range(3):
              move(); nm('new')
              assert trash.exists() and not list((mail/'proton/inbox/cur').iterdir())
          # Tags and old intent markers cannot move a physical file.
          nm('tag','+transport/inbox','+inbox','-trash','--','id:trash@example.invalid')
          move(); nm('new')
          assert trash.exists() and not list((mail/'proton/inbox/cur').iterdir())
  afew_source = pathlib.Path(sys.argv[3]).read_text()
  check_phone_trash(afew_source)
  try:
      check_phone_trash(afew_source + "\n[MailMover]\nrename = True\n")
  except AssertionError:
      pass
  else:
      raise AssertionError('retired mover passed the writer isolation check')

  # Exercise the actual generated dispatcher with only its runtime binding
  # substituted. Removing reopen from that dispatcher must lose db/notmuch.
  control = pathlib.Path(sys.argv[2]).read_text()
  runtime_path = "/run/current-system/sw/bin/mail-classifier-runtime"
  assert control.count(runtime_path) == 1
  with tempfile.TemporaryDirectory() as directory:
      root = pathlib.Path(directory)
      # Exercise the actual legacy label loop. Its directory and notmuch
      # executable are the only substituted dependencies.
      labels = root / "Labels"
      labels.mkdir()
      for name in ['finance', managed_prefix + 'look', '_work']:
          (labels / name).mkdir()
      tags = root / 'tags'
      tagger = root / 'notmuch'
      tagger.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\" >> " + str(tags) + "\n")
      tagger.chmod(0o755)
      start = hook.index('# Dynamic Proton label → notmuch tag mapping')
      end = hook.index('# Shield: kept mail', start)
      fragment = hook[start:end]
      import re
      fragment = re.sub(r'_LABELS_DIR=.*', '_LABELS_DIR="' + str(labels) + '"', fragment)
      fragment = re.sub(r'/nix/store/[^\s"\x27]+/bin/notmuch\b', str(tagger), fragment)
      def check_labels(text):
          tags.write_text("")
          subprocess.run(['${pkgs.bash}/bin/bash', '-c', text], check=True)
          applied = tags.read_text().splitlines()
          assert '+finance' in applied
          assert '+' + managed_prefix + 'look' not in applied
          assert '+_work' not in applied
      check_labels(fragment)
      try:
          check_labels(fragment.replace('|' + managed_prefix + '*', ""))
      except AssertionError:
          pass
      else:
          raise AssertionError('removed managed-label skip passed its check')
      runtime = root / "runtime"
      runtime.write_text("#!/bin/sh\nprintf '%s\\n' \"$@\"\n")
      runtime.chmod(0o755)
      def dispatch(text, verb="reopen", *arguments):
          wrapper = root / "wrapper"
          lock_path = ${builtins.toJSON "${builtins.dirOf mailHome.hwc.mail.mbsync.statusFile}/sync.lock"}
          wrapper.write_text(text.replace(runtime_path, str(runtime)).replace(lock_path, str(root / 'sync.lock')))
          wrapper.chmod(0o755)
          return subprocess.check_output([str(wrapper), verb, *arguments], text=True).splitlines()
      def check_withdraw_lock(source):
          import fcntl
          with (root / 'sync.lock').open('a') as owner:
              fcntl.flock(owner,fcntl.LOCK_EX | fcntl.LOCK_NB)
              assert dispatch(source,'review-transport')[0]=='review-transport'
              for arguments in [('--withdraw','a'*64),('--withdraw='+'a'*64,)]:
                  try: dispatch(source,'review-transport',*arguments)
                  except subprocess.CalledProcessError as error: assert error.returncode==75
                  else: raise AssertionError('withdraw bypassed the active effect owner')
              try: dispatch(source,'withdraw-transport','--command-id','a'*64)
              except subprocess.CalledProcessError as error: assert error.returncode==75
              else: raise AssertionError('withdraw alias bypassed the active effect owner')
          assert '--withdraw' in dispatch(source,'review-transport','--withdraw','a'*64)
      check_withdraw_lock(control)
      try: check_withdraw_lock(control.replace('"$arg" == --withdraw || "$arg" == --withdraw=*','"$arg" == --removed-withdraw'))
      except AssertionError: pass
      else: raise AssertionError('removed withdrawal guard passed its wiring check')
      def check(arguments):
          assert arguments[0] == "reopen"
          assert arguments[1:3] == ["--db", "/var/lib/hwc/mail-classifier/ledger.sqlite"]
          assert arguments[3] == "--notmuch"
      check(dispatch(control))
      observation = dispatch(control, "observe-residency")
      assert observation[:3] == ['observe-residency', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
      assert observation[observation.index('--bridge-host') + 1] == '127.0.0.1'
      assert observation[observation.index('--bridge-port') + 1] == '1143'
      password_command = observation[observation.index('--password-command') + 1]
      assert shlex.split(password_command)[:2] == ['sh', '-c']
      probe = dispatch(control, 'label-probe')
      assert probe[:3] == ['label-probe', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
      assert '--notmuch' not in probe
      projected = dispatch(control, 'project-labels')
      assert projected[:3] == ['project-labels', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
      assert '--notmuch' in projected
      assert projected[projected.index('--output') + 1].endswith('/labels.json')
      reviewed = dispatch(control, 'review-label-write')
      assert reviewed[:3] == ['review-label-write', '--db', '/var/lib/hwc/mail-classifier/ledger.sqlite']
      assert '--bridge-host' in reviewed and '--notmuch' in reviewed
      assert reviewed[reviewed.index('--output') + 1].endswith('/label-review.json')
      try:
          broken_review = dispatch(control.replace('|review-label-write', ""), 'review-label-write')
          assert '--bridge-host' in broken_review and '--notmuch' in broken_review
      except AssertionError:
          pass
      else:
          raise AssertionError('dispatcher accepted removed review wiring')
      try:
          check(dispatch(control.replace("|reopen", "")))
      except AssertionError:
          pass
      else:
          raise AssertionError("dispatcher check accepted removed reopen wiring")
  PY
  touch "$out"
'';
}
