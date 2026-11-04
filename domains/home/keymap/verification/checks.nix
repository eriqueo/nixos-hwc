# Pure verification function; not a NixOS or Home Manager module.
{ inputs, keymapDocs, keymapGrammar, keymapGrammarFile, keymapValidator, lib, mailHome, pkgs, repoRoot, self }:
{

keymap-docs = pkgs.runCommand "keymap-docs" { nativeBuildInputs = [ pkgs.diffutils ]; } ''
  diff -u ${(repoRoot + "/domains/home/keymap/KEYMAP.md")} ${keymapDocs}
  touch "$out"
'';

keymap-grammar = pkgs.runCommand "keymap-grammar" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  python3 ${keymapValidator} ${keymapGrammarFile}
  touch "$out"
'';

khalt-keymap = let
  home = self.homeConfigurations."eric@hwc-laptop".config;
  appPkgs = inputs.khalt.inputs.nixpkgs.legacyPackages.x86_64-linux;
  python = appPkgs.python3.withPackages (ps: [
    ps.click ps.click-log ps.icalendar ps.urwid ps.pyxdg
    ps.pytz ps.python-dateutil ps.configobj ps.tzlocal
  ]);
  generated = pkgs.writeText "khalt-keymap.json"
    home.xdg.configFile."khalt/keymap.json".text;
  runner = pkgs.writeText "khalt-keymap-check.py" ''
    import copy, importlib.util, json, logging, os, pathlib
    from types import SimpleNamespace
    # Import the real loader without khal's build-generated version.py.
    spec = importlib.util.spec_from_file_location("khalt_leader",
        "${inputs.khalt}/khal/ui/khalt_leader.py")
    leader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(leader)

    class FailFallback(logging.Handler):
        def emit(self, record):
            raise AssertionError(record.getMessage())
    leader.logger.addHandler(FailFallback())
    view = SimpleNamespace(_conf={"keybindings": {
        "new": ["a"], "delete": ["d"], "view": ["enter"], "leader": [" "]}})
    def check(path):
        os.environ["KHALT_LEADER_TREE"] = str(path)
        entries = leader.build_keymap(view)
        assert entries, "loader returned an empty tree"
        data = json.loads(pathlib.Path(path).read_text())
        for leaf in data["bindings"].values():
            if leaf.startswith("call:"):
                assert leaf[5:] in leader.LEADER_ACTION_NAMES, leaf
            else:
                assert leaf.startswith("key:") and leaf[4:] in leader.COMMAND_KEYS, leaf
        assert data["bindings"] == leader.DEFAULT_TREE["bindings"], "default bindings drift"
    check("${generated}")
    bad = copy.deepcopy(json.loads(pathlib.Path("${generated}").read_text()))
    bad["bindings"]["w a"] = "call:invalid_seed"
    seed = pathlib.Path("bad-keymap.json")
    seed.write_text(json.dumps(bad))
    try:
        check(seed)
    except AssertionError as error:
        assert "invalid_seed" in str(error), error
        print("khalt-keymap: bad leaf rejected:", error)
    else:
        raise AssertionError("bad leaf seed accepted")
    seed.unlink()
    check("${generated}")
    print("khalt-keymap: real loader accepted generated bindings; defaults match")
  '';
in
assert lib.assertMsg (home.home.sessionVariables.KHALT_LEADER_TREE
  == "${home.xdg.configHome}/khalt/keymap.json") "khalt-keymap: session path is not wired";
assert lib.assertMsg (lib.hasInfix "new = a"
  home.programs.khalt.configText && lib.hasInfix "delete = d"
  home.programs.khalt.configText && lib.hasInfix "view = enter"
  home.programs.khalt.configText) "khalt-keymap: native aliases are not wired";
pkgs.runCommand "khalt-keymap" { nativeBuildInputs = [ python ]; } ''
  export PYTHONPATH=${inputs.khalt}
  python ${runner}
  touch "$out"
'';

todui-keymap = let
  home = self.homeConfigurations."eric@hwc-laptop".config;
  appPkgs = inputs.todui.inputs.nixpkgs.legacyPackages.x86_64-linux;
  python = appPkgs.python3.withPackages (ps: [ ps.textual ps.icalendar ps.python-dateutil ]);
  generated = pkgs.writeText "todui-keymap.json"
    home.xdg.configFile."todui/keymap.json".text;
  runner = pkgs.writeText "todui-keymap-check.py" ''
    import copy, json, logging, os, pathlib
    from todui import keymap

    class FailFallback(logging.Handler):
        def emit(self, record):
            raise AssertionError(record.getMessage())
    keymap.log.addHandler(FailFallback())
    def check(path):
        os.environ["TODUI_KEYMAP"] = str(path)
        loaded = keymap.load_keymap()
        data = json.loads(pathlib.Path(path).read_text())
        assert loaded == data, "loader did not return generated file"
        assert all(leaf.startswith("call:") and leaf[5:] in keymap.LEADER_ACTIONS
                   for leaf in loaded["bindings"].values()), "unregistered action"
        assert loaded["bindings"] == keymap.DEFAULT_KEYMAP["bindings"], "default bindings drift"
    check("${generated}")
    bad = copy.deepcopy(json.loads(pathlib.Path("${generated}").read_text()))
    bad["bindings"]["c c"] = "call:invalid_seed"
    seed = pathlib.Path("bad-keymap.json")
    seed.write_text(json.dumps(bad))
    try:
        check(seed)
    except AssertionError as error:
        assert "invalid_seed" in str(error), error
        print("todui-keymap: bad leaf rejected:", error)
    else:
        raise AssertionError("bad leaf seed accepted")
    seed.unlink()
    check("${generated}")
    print("todui-keymap: real loader accepted generated bindings; defaults match")
  '';
in pkgs.runCommand "todui-keymap" { nativeBuildInputs = [ python ]; } ''
  export PYTHONPATH=${inputs.todui}/src
  python ${runner}
  touch "$out"
'';

nvim-keymap = let
  home = self.homeConfigurations."eric@hwc-laptop".config;
  grammar = home.hwc.home.keymap.grammar;
  rendered = import (repoRoot + "/domains/home/keymap/parts/to-nvim.nix") { inherit lib grammar; };
  generated = pkgs.writeText "nvim-leader.lua"
    home.xdg.configFile."nvim/lua/core/leader.lua".text;
  expected = pkgs.writeText "nvim-keymap.json" (builtins.toJSON {
    inherit (grammar) groups leader;
    rows = rendered.rows;
  });
  runner = pkgs.writeText "nvim-keymap-check.lua" ''
    local spec = vim.json.decode(table.concat(vim.fn.readfile("${expected}"), "\n"))
    vim.g.mapleader = spec.leader
    vim.opt.rtp:append("${pkgs.vimPlugins.which-key-nvim}")
    dofile("${(repoRoot + "/domains/home/apps/nvim/parts/lua/core/keymaps.lua")}")
    dofile("${generated}")
    local function validate()
      for _, mode in ipairs({ "n", "x", "v" }) do
        local chords = {}
        for _, entry in ipairs(vim.api.nvim_get_keymap(mode)) do
          if entry.lhs:sub(1, #spec.leader) == spec.leader then
            local key = entry.lhs:sub(#spec.leader + 1)
            assert(spec.groups[key:sub(1, 1)], "unknown leader group: " .. key)
            table.insert(chords, key)
          end
        end
        for i, a in ipairs(chords) do
          for j, b in ipairs(chords) do
            assert(i == j or b:sub(1, #a) ~= a, "duplicate/prefix: " .. a .. " / " .. b)
          end
        end
      end
      for _, row in ipairs(spec.rows) do
        local modes = row.nvim and row.nvim.mode or { "n" }
        for _, mode in ipairs(modes) do
          local lhs = spec.leader .. row.keys:gsub(" ", "")
          assert(vim.fn.maparg(lhs, mode) ~= "", "missing grammar row: " .. row.keys)
        end
      end
    end
    validate()
    -- Seed a forbidden group through the real runtime map, then remove it.
    vim.keymap.set("n", spec.leader .. "!z", "<Nop>")
    assert(not pcall(validate), "unknown-group seed was accepted")
    vim.keymap.del("n", spec.leader .. "!z")
    vim.keymap.set("n", spec.leader .. "g", "<Nop>")
    assert(not pcall(validate), "strict-prefix seed was accepted")
    vim.keymap.del("n", spec.leader .. "g")
    validate()
    -- Parse handwritten plugin modules without bootstrapping/network access.
    for _, path in ipairs(vim.fn.glob("${(repoRoot + "/domains/home/apps/nvim/parts/lua")}/**/*.lua", false, true)) do
      assert(loadfile(path))
    end
    print("nvim-keymap: runtime rows present; groups/prefixes pass; both seeds rejected")
  '';
in
assert lib.assertMsg (lib.hasInfix ''require("core.leader")''
  (home.programs.neovim.initLua or home.programs.neovim.extraLuaConfig))
  "nvim-keymap: generated leader module is not sourced";
pkgs.runCommand "nvim-keymap" {
  nativeBuildInputs = [ pkgs.neovim-unwrapped ];
} ''
  export HOME="$TMPDIR"
  nvim --headless -u NONE -i NONE -l ${runner}
  touch "$out"
'';

workbench-keymap = let
  contract = mailHome.hwc.mail.classifier.contract;
  output = import (repoRoot + "/domains/home/keymap/parts/to-workbench.nix") {
    inherit lib; grammar = keymapGrammar; mailContract = contract;
  };
  fixture = pkgs.writeText "workbench-keymap.json" (builtins.toJSON {
    grammar = keymapGrammar; registry = output.registry; inherit contract;
    launchers = self.homeConfigurations."eric@hwc-laptop".config.programs.workbench.launchers;
    binds = mailHome.home.file.".config/aerc/binds.conf".text;
  });
in pkgs.runCommand "workbench-keymap" { nativeBuildInputs = [ pkgs.python3 ]; } ''
  export PYTHONPATH=${inputs.workbench}/src
  python3 - ${fixture} ${(repoRoot + "/domains/system/mcp/src/src/tools/mail-triage.ts")} ${inputs.workbench}/hubs/mail.toml <<'PY'
  import copy, json, pathlib, re, sys, tomllib
  from workbench.adapters.manifest_loader import TomlHubProvider
  from workbench.config import _parse_keymap, parse_hub_keymaps
  from workbench.core.errors import ManifestError, ValidationError
  data = json.loads(pathlib.Path(sys.argv[1]).read_text())
  grammar, registry = data['grammar'], data['registry']
  hub = registry['hubs']['mail']
  source = pathlib.Path(sys.argv[2]).read_text()
  producer = source.split('const THREAD_VERBS = ', 1)[1].split(';', 1)[0]
  verbs = set(re.findall(r'"([^"\n]+)"', producer))
  verbs.update('state-' + s for s in data['contract']['states'])
  verbs.update('domain-' + d for d in data['contract']['domains'])
  manifest = tomllib.loads(pathlib.Path(sys.argv[3]).read_text())
  manifest_chords = [a['key'] for a in manifest.get('action', [])]
  for tile in manifest.get('tile', []):
      manifest_chords.extend(tile.get('item_actions', {}))
      manifest_chords.extend(tile.get('board_actions', {}))
  def validate(payload):
      rows = payload['hubs']['mail']['bindings']
      chords = [r['chord'] for r in rows]
      for row in grammar['aerc']['bindings']:
          if 'omit' not in row['wb']:
              assert any(c == row['keys'] or c.startswith(row['keys'] + ' ') for c in chords), row
      paths = [c.split() for c in chords + [r['chord'] for r in payload['bindings']]]
      assert len({tuple(p) for p in paths}) == len(paths)
      assert not any(p != q and q[:len(p)] == p for p in paths for q in paths)
      merged = [c.split() for c in dict.fromkeys(chords + manifest_chords
                + [r['chord'] for r in payload['bindings']])]
      assert not any(p != q and q[:len(p)] == p for p in merged for q in merged)
      assert all(r['intent'] in verbs for r in rows if r['target'] == 'item')
      assert all(data['launchers'].get(r['intent']) for r in rows if r['target'] == 'handoff'), 'missing launcher'
      global_paths = [r['chord'].split() for r in payload['bindings']]
      global_paths += [['q'], ['?'], ['R'], ['a']] + [['g', str(n)] for n in range(1, 10)]
      def overlaps(p, q):
          return p[:len(q)] == q or q[:len(p)] == p
      assert not any(overlaps(r['chord'].split(), g) for r in rows for g in global_paths), 'global shadow'
      assert not any(overlaps([r['key']], g) for r in payload['hubs']['mail']['bare'] for g in [['q'], ['?'], ['R']]), 'bare global shadow'
      bare = {r['key']: r['intent'] for r in payload['hubs']['mail']['bare']}
      expected = {(k if isinstance(k, str) else k['key']):
                  (r['wb']['verb'] if isinstance(k, str) else k['verb'])
                  for r in grammar['aerc']['bindings'] for k in r.get('bare', {}).get('list', []) if 'verb' in r['wb'] or r['wb'].get('menu') == 'read-status'}
      assert bare == expected
      item_intents = {r['intent'] for r in rows if r['target'] == 'item'}
      assert all(r['intent'] in item_intents for r in payload['hubs']['mail']['bare'])
      assert not item_intents.intersection({'move', 'fact-add', 'fact-clear'}), 'unavailable item parameters'
      sections = data['binds'].split('[messages]', 1)[1].split('[view]', 1)[0]
      for key in bare:
          assert re.search(r'^\s*' + re.escape(key) + r' = ', sections, re.M), key
  validate(registry)
  def load_hubs(payload):
      globals_ = _parse_keymap(payload, where='generated keymap')
      assert globals_ is not None, 'registry rejected by Workbench parser'
      overlays = parse_hub_keymaps(payload, where='generated keymap')
      manifests = sorted(pathlib.Path(sys.argv[3]).parent.glob('*.toml'))
      assert manifests, 'no Workbench manifests'
      provider = TomlHubProvider(str(manifests[0].parent), groups=payload['groups'],
                                 globals_=globals_, hub_keymaps=overlays)
      # reload skips invalid manifests; call the real single-file loader
      # too, so ManifestError/ValidationError fail this build directly.
      loaded = [provider._load_file(str(path)) for path in manifests]
      assert len(provider.list_hubs()) == len(loaded), 'a hub was skipped'
      return loaded
  loaded = load_hubs(registry)
  print('real Workbench loader accepted hubs: ' + ', '.join(h.id for h in loaded))
  bad = copy.deepcopy(registry)
  bad['hubs']['mail']['bare'].append({'key': 'c', 'intent': 'compose'})
  try:
      load_hubs(bad)
  except (ManifestError, ValidationError) as exc:
      assert 'every item_keys action requires a Space path' in str(exc), str(exc)
      print('seeded original bare compose regression rejected: ' + str(exc))
  else:
      raise AssertionError('real loader accepted bare compose regression')
  for kind in ('coverage', 'bare', 'prefix', 'verb', 'launcher', 'global', 'bare-global'):
      bad = copy.deepcopy(registry)
      if kind == 'coverage':
          bad['hubs']['mail']['bindings'] = []
      elif kind == 'bare':
          bad['hubs']['mail']['bare'] = []
      elif kind == 'prefix':
          bad['bindings'].append({'chord': 'a a x'})
      elif kind == 'launcher':
          bad['hubs']['mail']['bindings'].append({'chord': 'o Z', 'intent': 'missing-launcher', 'target': 'handoff'})
      elif kind == 'global':
          bad['hubs']['mail']['bindings'].append({'chord': 'q q', 'intent': 'compose', 'target': 'handoff'})
      elif kind == 'bare-global':
          bad['hubs']['mail']['bare'].append({'key': 'R', 'intent': 'compose'})
      else:
          bad['hubs']['mail']['bindings'].append({'chord': 'm Z', 'intent': 'invalid-verb', 'target': 'item'})
      try:
          validate(bad)
      except AssertionError:
          print('seeded ' + kind + ' violation rejected')
      else:
          raise AssertionError('accepted seeded ' + kind)
  PY
  touch "$out"
'';

yazi-keymap = let
  home = self.homeConfigurations."eric@hwc-laptop".config;
  keymap = pkgs.writeText "yazi-keymap.toml" home.xdg.configFile."yazi/keymap.toml".text;
in pkgs.runCommand "yazi-keymap" {
  nativeBuildInputs = [ pkgs.python3 ];
} ''
  python3 ${keymapValidator} ${keymapGrammarFile} ${keymap}
  touch "$out"
'';

workbench-navigation = let
  home = self.homeConfigurations."eric@hwc-laptop".config;
  navigation = import (repoRoot + "/domains/home/apps/zellij/parts/tabs.nix") {
    inherit lib; hubRegistry = registry;
  };
  layout = home.xdg.configFile."zellij/layouts/workbench.kdl".text;
  configKdl = home.xdg.configFile."zellij/config.kdl".text;
  captures = pattern: text: map builtins.head
    (builtins.filter builtins.isList (builtins.split pattern text));
  names = captures ''tab name="([^"]+)"'' layout;
  hubCommands = captures ''args "--hub" "([^"]+)"'' layout;
  focused = captures ''tab name="([^"]+)" focus=true'' layout;
  grammar = home.hwc.home.keymap.grammar;
  # Hub digits come from rail positions, tools/nav from the grammar.
  jumps = lib.filter (entry: entry ? target) grammar.meta ++ navigation.hubJumps;
  destinationFor = key: (builtins.head (lib.filter (entry: entry.key == key) jumps)).target;
  acceptsRegistry = registry: (builtins.tryEval (builtins.deepSeq
    (import (repoRoot + "/domains/home/apps/zellij/parts/tabs.nix") { inherit lib; hubRegistry = registry; }) true)).success;
  # Seed digit keys in the grammar to verify the reserved hub namespace.
  acceptsKeys = candidateGrammar: (builtins.tryEval (builtins.deepSeq
    (import (repoRoot + "/domains/home/keymap/parts/to-zellij.nix") {
      inherit lib;
      grammar = candidateGrammar;
      tabs = navigation;
    }).keybinds true)).success;
  registry = inputs.workbench.hubRegistryFor {
    order = home.hwc.home.apps.workbench.hubOrder;
    hidden = home.hwc.home.apps.workbench.hiddenHubs;
  };
in
assert lib.assertMsg (!acceptsRegistry (registry // { schemaVersion = 3; }))
  "workbench check: retired registry schema 3 accepted";
assert lib.assertMsg (!acceptsRegistry (registry // { hubs = registry.hubs ++ [ (builtins.head registry.hubs) ]; }))
  "workbench check: duplicate registry hub accepted";
assert lib.assertMsg (lib.all (key: !acceptsKeys (grammar // {
    meta = grammar.meta ++ [ { inherit key; target = "tool:todui"; desc = "Reserved digit"; } ];
  })) [ "0" "1" "2" "3" "4" "5" "6" "7" "8" "9" ])
  "workbench check: a digit key in grammar.meta was accepted";
assert lib.assertMsg (acceptsKeys grammar)
  "workbench check: the shipped registry's hub keys are rejected";
assert lib.assertMsg (names == [ "workbench" ] ++ map (tab: tab.name) navigation.toolTabs
    && focused == [ "workbench" ] && hubCommands == [ ]
    && lib.all (jump: navigation.tabFor.${jump.target} == navigation.tabFor.workbench) navigation.hubJumps)
  "workbench check: one landing workbench tab, no per-hub tabs, every hub digit targets it";
assert lib.assertMsg (names == map (tab: tab.name) navigation.destinations)
  "workbench check: generated tab names/order differ from navigation";
assert lib.assertMsg (home.programs.workbench.defaultHub == navigation.landingHub
  && home.programs.workbench.tabs == navigation.launcherTabs
  && home.programs.workbench.hubOrder == home.hwc.home.apps.workbench.hubOrder
  && home.programs.workbench.hiddenHubs == home.hwc.home.apps.workbench.hiddenHubs)
  "workbench check: launcher destinations differ from layout";
assert lib.assertMsg (lib.versionAtLeast home.hwc.home.apps.zellij.package.version "0.45.1"
  && lib.elem home.hwc.home.apps.zellij.package home.programs.workbench.extraRuntimePackages
  && lib.elem home.hwc.home.apps.zellij.package home.home.packages)
  "workbench check: shell and wrapper must share the graphics-capable pane host";
assert lib.assertMsg (lib.all (entry: lib.hasInfix
  (if lib.hasPrefix "hub:" entry.target
    then "${entry.key}|goto-hub|${toString navigation.tabFor.${entry.target}}:${lib.removePrefix "hub:" entry.target}|${entry.desc}"
    else "${entry.key}|goto-tab|${toString navigation.tabFor.${entry.target}}|${entry.desc}") configKdl) jumps)
  "workbench check: generated meta entries (goto-tab tools, goto-hub hubs) differ from navigation";
assert lib.assertMsg (destinationFor "1" == "hub:${(builtins.head
  (lib.sort (a: b: a.order < b.order) registry.hubs)).slug}")
  "workbench check: digit 1 must target the first visible hub";
assert lib.assertMsg (lib.all (entry: builtins.match "[0-9]" entry.key == null) grammar.meta)
  "workbench check: grammar.meta contains a reserved digit";
assert lib.assertMsg (destinationFor "t" == "tool:todui" && destinationFor "c" == "tool:khalt"
  && destinationFor "m" == "tool:aerc" && destinationFor "f" == "tool:yazi"
  && destinationFor "e" == "tool:nvim" && destinationFor "a" == "tool:herdr")
  "workbench check: tool shortcuts changed destination";
pkgs.runCommand "workbench-navigation" {} ''
  ${lib.getExe home.hwc.home.apps.zellij.package} --version
  touch "$out"
'';
}
