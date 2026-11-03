{ lib, config, pkgs, ... }:
let
  cfg = config.hwc.media.sabnzbd;
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  runtimeInputs = builtins.fromJSON ''
{"schemaVersion":1,"apks":[{"name":"curl","version":"8.23.0-r0","file":"curl-8.23.0-r0.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/curl-8.23.0-r0.apk","hash":"sha256-UxrimEUaTBxE9WP8Oy7twsHX4KJqM738Dv5vqv9qWUI="},{"name":"libcurl","version":"8.23.0-r0","file":"libcurl-8.23.0-r0.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/libcurl-8.23.0-r0.apk","hash":"sha256-H3DKQEgYgFpkZbYVu/6E74YUiKlj1+YwEI69f7qlFmU="},{"name":"libexpat","version":"2.10.0-r0","file":"libexpat-2.10.0-r0.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/libexpat-2.10.0-r0.apk","hash":"sha256-5+dAjqeH7QbQAVmw/x+bZaY89jTzbZ4Pp1Es4sSJpQM="},{"name":"ca-certificates-bundle","version":"20261020-r0","file":"ca-certificates-bundle-20261020-r0.apk","url":"https://dl-cdn.alpinelinux.org/alpine/v3.24/main/x86_64/ca-certificates-bundle-20261020-r0.apk","hash":"sha256-uwCPbSFLavdXYyRlmFb7Y9yNy0Nz+DRf9wY4hpbxJU0="}],"wheels":[{"name":"certifi","version":"2026.10.23","file":"certifi-2026.10.23-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/32/d1/a3652fe2c19134d0d15922177821d863cbd7e842d53a21bbe7e8e3a1b5ac/certifi-2026.10.23-py3-none-any.whl","hash":"sha256-6bVN525TC7bPDM0DZ4cQOstY/UK6kw6ov5SN26ovYdE=","requiresDist":[],"requiresPython":">=3.7"},{"name":"PyJWT","version":"2.15.1","file":"pyjwt-2.15.1-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/50/ca/44de4e75f8aadc457f0634be3b542815078ded46dca30efb960edeecad6e/pyjwt-2.15.1-py3-none-any.whl","hash":"sha256-QtWdYx93aKECimTH/1gam/dRmATa+R/FtsVuMO7F4ZM=","requiresDist":["typing_extensions>=4.0; python_version < \"3.11\"","cryptography>=3.4.0; extra == \"crypto\""],"requiresPython":">=3.9"},{"name":"urllib3","version":"2.8.0","file":"urllib3-2.8.0-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/92/9d/c4e665119135114480843e7ab388fa94d8480650450e6f8e26b70d323a4c/urllib3-2.8.0-py3-none-any.whl","hash":"sha256-DPPK5WjTaqlXayjfs18RMo8cuXTKdkfZR167hsdaxuM=","requiresDist":["brotli>=1.2.0; platform_python_implementation == \"CPython\" and extra == \"brotli\"","brotlicffi>=1.2.0.0; platform_python_implementation != \"CPython\" and extra == \"brotli\"","h2<5,>=4; extra == \"h2\"","pysocks!=1.5.7,<2.0,>=1.5.6; extra == \"socks\"","backports-zstd>=1.0.0; python_version < \"3.14\" and extra == \"zstd\""],"requiresPython":">=3.10"},{"name":"oauthlib","version":"4.0.1","file":"oauthlib-4.0.1-py3-none-any.whl","url":"https://files.pythonhosted.org/packages/df/ef/3b8adde1b32a6f540758bff734d3442c621734c83708e5f02b0ba2f43b84/oauthlib-4.0.1-py3-none-any.whl","hash":"sha256-SYopiHbpljAZUKWwU9EsMWKLt7iV2wNmZDDGnOGC62E=","requiresDist":["cryptography>=3.0.0; extra == \"rsa\"","cryptography>=3.0.0; extra == \"signedtoken\"","pyjwt<3,>=2.0.0; extra == \"signedtoken\"","blinker>=1.4.0; extra == \"signals\""],"requiresPython":">=3.9"}],"backports":{"sabnzbd/postproc.py":{"sourceSha256":"d41dc008aeb20db29a54c387e6e3f5507d46eabb5c9299f70ca09d62205b5844","patchedSha256":"dbcd60746ae1b8890ce3ac6f85715bfe244080ec4f957dfaaa141b4242bc3e97","replacements":[["TAG_RE = re.compile(r\"<[^>]+>\")","TAG_RE = re.compile(r\"<[^>\\n]*>?\")"]]},"interfaces/Glitter/templates/static/javascripts/knockout-extensions.js":{"sourceSha256":"02b59c120032ecf1d763338b601c7a7cd54687da9a3babfe0d4ec4dca6949381","patchedSha256":"a344b7a1aea287934f36154eb5d3d73ca57592b688bcba51454134cd44e8b35b","replacements":[["        // Convert HTML entities for all but the Script (because of the (more)-link)\n        if(allBindingsAccessor.get('longTextType') != \"Script\") {\n            value = value.map(convertHTMLtoText)\n        }","        // Backport upstream HTML escaping while preserving the stable 5.1\n        // script-log link. Parse only the exact app route, then construct its\n        // anchor with DOM APIs; all source text remains escaped.\n        var isScript = allBindingsAccessor.get('longTextType') == \"Script\";\n        value = value.map(function(line) {\n            var more = isScript && line.match(/^([\\s\\S]*?) <a href=\"(\\.\\/scriptlog\\?name=SABnzbd_nzo_[A-Za-z0-9_-]{1,80})\">\\(([^<>\\r\\n]*)\\)<\\/a>$/);\n            if (more) {\n                return convertHTMLtoText(more[1]) + ' ' + $('<a>').attr('href', more[2]).text('(' + more[3] + ')').prop('outerHTML');\n            }\n            return convertHTMLtoText(line);\n        })"]]},"interfaces/wizard/static/javascript/checkserver.js":{"sourceSha256":"a0819afcdcbcd1c7160861b5278dc8caddc18100a35c64c07f704e8f3ffe8af4","patchedSha256":"332318b1bcad64fa7565b4272313c7ef4adeca9c14ba0516fc119037a4fe0360","replacements":[["            function(result) {\n                if (result.value.result) {","            function(result) {\n                // Escape the server-supplied message before inserting it as HTML\n                var message = $('<div>').text(result.value.message).html();\n                if (result.value.result) {"],["+ result.value.message + '</span>'","+ message + '</span>'"]]},"interfaces/Config/templates/config_server.tmpl":{"sourceSha256":"2e2541d2813d1f0cfce6e2420cd014732b4ca72b2155821159fd56ed4a05f9c4","patchedSha256":"ee5516fdb731f859a518633387c361a7996bbc2f3e7fc2cca875cfe80f1efe34","replacements":[["                msg = data.value.message.replace(","                msg = jQuery('<div>').text(data.value.message).html()\n                msg = msg.replace("]]}},"pythonHttpBackport":{"sourceSha256":"426efb3157421094db809b674002f15d53f6916a4b4049293a3c431552310790","patchedSha256":"1bf66af1b10a72bb91ae15c3f935fd80cdcc38cc10f57aed05797702c4785ad2","replacements":[["# We always set the Content-Length header for these methods because some","# RFC 9112: validate framing before int(), which accepts other grammars.\n_is_legal_content_length = re.compile(r'[0-9]+').fullmatch\n_is_legal_chunk_size = re.compile(rb'[0-9a-fA-F]+').fullmatch\n\n# We always set the Content-Length header for these methods because some"],["        if length and not self.chunked:\n            try:\n                self.length = int(length)\n            except ValueError:\n                self.length = None\n            else:\n                if self.length < 0:  # ignore nonsensical negative lengths\n                    self.length = None","        if length is not None:\n            length = length.strip(' \\t')\n        if length and not self.chunked and _is_legal_content_length(length):\n            self.length = int(length)"],["            line = line[:i] # strip chunk-extensions\n        try:\n            return int(line, 16)","            line = line[:i] # strip chunk-extensions\n        line = line.rstrip()\n        try:\n            if not _is_legal_chunk_size(line):\n                raise ValueError(\"invalid chunk size\")\n            return int(line, 16)"]],"upstreamCommits":["2eb2af805c156ca52b316bb4ced5e0ab3971d0ae","9f52b443c002cccfb54bda0706a9276b6b4a109d"]}}
  '';
  # Temporary stable backports of upstream b18cdc38 and 3376cb51: 5.1.3
  # still has GHSA-rpwc-qfxm-7h2v and GHSA-c5x2-896f-g5g8. The strict
  # DOM-built scriptlog link preserves stable More links without trusting HTML.
  # Remove when vendor stable includes both fixes and passes the actual sink,
  # native/client and current-data/code-recovery contracts.
  # Also backport CPython2eb2af80 +9f52b443 for CVE-2026-103995.
  # Retire this stdlib transform when vendor Python has strict framing plus
  # optional-whitespace compatibility and the actual HTTP client checks pass.
  applyBackports = pkgs.writeText "sabnzbd-security-backports.py" ''
import hashlib,json,pathlib
root=pathlib.Path('/app/sabnzbd')
manifest=json.loads(pathlib.Path('/tmp/hwc/manifest.json').read_text())
def patch(p,spec):
 raw=p.read_bytes()
 assert hashlib.sha256(raw).hexdigest()==spec['sourceSha256'], 'SOURCE_MISMATCH:'+str(p)
 text=raw.decode()
 for old,new in spec['replacements']:
  assert text.count(old)>0, 'MISSING_HUNK:'+str(p)
  text=text.replace(old,new)
 patched=text.encode()
 assert hashlib.sha256(patched).hexdigest()==spec['patchedSha256'], 'PATCH_MISMATCH:'+str(p)
 p.write_bytes(patched)
for name,spec in manifest['backports'].items():patch(root/name,spec)
patch(pathlib.Path('/usr/lib/python3.14/http/client.py'),manifest['pythonHttpBackport'])
for p in (root/'sabnzbd/__pycache__').glob('postproc.*.pyc'):p.unlink()
for p in pathlib.Path('/usr/lib/python3.14/http/__pycache__').glob('client.*.pyc'):p.unlink()
  '';
  manifest = pkgs.writeText "sabnzbd-runtime-inputs.json" (builtins.toJSON runtimeInputs);
  runtime = helpers.mkRuntimeImage {
    name = "sabnzbd";
    version = "5.1.3-security";
    recipe = ''
      FROM lscr.io/linuxserver/sabnzbd@sha256:2b69019ef0b01bcdb9fb5d6641516bd57cb73b8f98b1a34f61ab749c5ea63376
      # Fixed inputs ${builtins.hashString "sha256" (builtins.toJSON runtimeInputs + builtins.readFile applyBackports)}
      COPY . /tmp/hwc/
      RUN apk verify ${lib.concatMapStringsSep " " (p: lib.escapeShellArg "/tmp/hwc/${p.file}") runtimeInputs.apks} && apk --repositories-file /dev/null --no-network --no-cache add ${lib.concatMapStringsSep " " (p: lib.escapeShellArg "/tmp/hwc/${p.file}") runtimeInputs.apks} && /lsiopy/bin/python3 -m pip install --no-index --no-deps --no-cache-dir --force-reinstall ${lib.concatMapStringsSep " " (p: lib.escapeShellArg "/tmp/hwc/${p.file}") runtimeInputs.wheels} && /lsiopy/bin/python3 /tmp/hwc/apply-backports.py && /lsiopy/bin/python3 -m pip check && rm -rf /tmp/hwc
    '';
  };
  runtimeContext = pkgs.runCommand "sabnzbd-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${pkgs.writeText "sabnzbd-backports.json" (builtins.toJSON runtimeInputs.backports)} "$out/backports.json"
    cp ${manifest} "$out/manifest.json"
    cp ${applyBackports} "$out/apply-backports.py"
    ${lib.concatMapStrings (p: let source = pkgs.fetchurl { inherit (p) url hash; }; in ''
      cp ${source} "$out/${p.file}"
    '') (runtimeInputs.apks ++ runtimeInputs.wheels)}
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.sabnzbd = {
    enable = lib.mkEnableOption "SABnzbd usenet client container";
    image = lib.mkOption { type = lib.types.str; default = cfg._runtimeImage; description = "Qualified stable app and offline security context"; };
    _runtimeImage = lib.mkOption { type = lib.types.str; default = runtime.image; internal = true; readOnly = true; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "vpn"; description = "Network mode: 'media' for direct access, 'vpn' to route through gluetun"; };
    webPort = lib.mkOption { type = lib.types.port; default = 8081; description = "Web UI port"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU acceleration (not typically needed for SABnzbd)"; };
    # Both of these ship RELATIVE in a stock sabnzbd.ini ("Downloads/incomplete",
    # "Downloads/complete"), which SABnzbd resolves against its own home — i.e.
    # /config, i.e. /opt/sabnzbd on the 468 GB NVMe root disk, not the 916 GB hot
    # pool the /downloads mount points at. Categories override the completed path
    # per-download, so this stayed invisible for everything categorized; the
    # incomplete path has no category override and staged EVERY usenet download
    # on the system disk. Absolute, and enforced on container start.
    downloadDir = lib.mkOption { type = lib.types.str; default = "/downloads/incomplete"; description = "In-progress download directory (container path)"; };
    completeDir = lib.mkOption { type = lib.types.str; default = "/downloads/complete"; description = "Completed download directory for uncategorized downloads (container path)"; };
    categories = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          dir = lib.mkOption { type = lib.types.str; description = "Download directory for this category"; };
          priority = lib.mkOption { type = lib.types.int; default = -100; description = "Download priority for this category"; };
        };
      });
      default = {
        movies = { dir = "/downloads/movies"; priority = -100; };
        tv = { dir = "/downloads/tv"; priority = -100; };
        music = { dir = "/downloads/music"; priority = -100; };
        books = { dir = "/downloads/books"; priority = -100; };
      };
      description = "Download categories with their directories";
    };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    system.build.sabnzbdRuntimeImageRecipe = runtime.dockerfile;
    system.build.sabnzbdRuntimeImageContext = runtimeContext;
    systemd.services.podman-sabnzbd.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
      ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
        echo "Prebuild SABnzbd from ${runtimeContext} before activation" >&2
        exit 1
      }
    '');
    # CRITICAL: queue, API identity and history. Retain via the existing Borg
    # owner; logs remain bounded by SAB's own configured rotation.
    hwc.data.borg = lib.mkIf config.hwc.data.borg.enable {
      sqliteSnapshots.sabnzbd = {
        source = "${config.hwc.paths.apps.root}/sabnzbd/config/admin/history1.db";
        user = "eric";
      };
      sources = [ "${config.hwc.paths.apps.root}/sabnzbd/config" ];
    };
  };

  #==========================================================================
  # VALIDATION
  #==========================================================================
  # Add assertions and validation logic here
}
