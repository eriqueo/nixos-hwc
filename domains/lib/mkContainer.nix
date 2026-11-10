# Application OCI definitions and qualified immutable runtime recipes.
# Modules own their options and startup policy; this library returns values.
{ lib, pkgs }:

rec {
  mediaNetworkName = "media-network";
  internalNetworkUnit = name: "init-internal-network-${name}.service";
  # One identity producer for immutable runtime recipes, including callers
  # that qualify shared libraries as well as the Node executable.
  mkRuntimeImage = { name, version, recipe }: {
    inherit recipe;
    image = "localhost/${name}-runtime:${version}-${builtins.substring 0 12 (builtins.hashString "sha256" recipe)}";
    dockerfile = pkgs.writeText "${name}-runtime.Dockerfile" recipe;
  };

  # Preserve an application's bytes while selecting a separately qualified
  # Node executable. Callers own immutable inputs and compatibility evidence.
  mkNodeRuntimeImage =
    { name, appVersion, nodeVersion, upstreamImage, nodeSourceImage }:
    let
      recipe = ''
        FROM ${nodeSourceImage} AS secure-node
        FROM ${upstreamImage}
        COPY --from=secure-node /usr/local/bin/node /usr/local/bin/node
        ENV NODE_VERSION=${nodeVersion}
      '';
    in mkRuntimeImage {
      inherit name recipe;
      version = "${appVersion}-node${nodeVersion}";
    };

  # Temporary CVE-2026-48710 backport of upstream Starlette commit
  # 764dab0dcfb9033d75442d7a359645c9f94648c6. Remove when the upstream
  # app images contain the fix and pass actual URL/FastAPI/GPU checks.
  # Exact before/after hashes fail closed on drift; no dependency resolution.
  mkStarletteHostBackport = { python, version, sourceSha256, patchedSha256 }:
    let program = ''
      import hashlib, importlib, sys
      from pathlib import Path
      import starlette, starlette.datastructures as ds
      version, original, patched = sys.argv[1:]
      p = Path(ds.__file__)
      before = p.read_bytes()
      assert starlette.__version__ == version
      assert hashlib.sha256(before).hexdigest() == original
      source = before.decode()
      old = '            if host_header is not None:'
      assert source.count(old) == 1 and source.count('class URL:') == 1
      pattern = r'^([a-z0-9.-]+|\[[a-f0-9]*:[a-f0-9.:]+\])(?::[0-9]+)?$'
      source = source.replace(old, old[:-1] + ' and _HOST_RE.fullmatch(host_header):')
      source = source.replace('class URL:', 'import re\n_HOST_RE = re.compile(' + repr(pattern) + ', re.IGNORECASE)\n\nclass URL:', 1)
      assert hashlib.sha256(source.encode()).hexdigest() == patched
      p.write_text(source)
      importlib.reload(ds)
      for host in [b'foo/?x=', b'foo/#', b'foo/bar', b'user@foo', b'foo\\bar', b'foo bar']:
          url = ds.URL(scope={'scheme':'http','server':('example.com',80),'path':'/admin','headers':[(b'host',host)]})
          assert url.path == '/admin' and url.netloc == 'example.com'
    '';
    in "RUN ${python} -c ${lib.escapeShellArg ("exec(" + builtins.toJSON program + ")")} ${lib.escapeShellArgs [ version sourceSha256 patchedSha256 ]}\n";

  # Temporary response framing repair. Remove when vendor stdlib and urllib3
  # pass actual Requests streaming/download and normal-response contracts.
  # Both controlled modules share one grammar; no resolver or native changes.
  mkPythonHttpFramingBackport = { python, modules, stdlibUpstreamCommits }:
    let
      manifest = { schemaVersion = 1; inherit modules stdlibUpstreamCommits; };
      program = ''
        import hashlib, itertools, json, subprocess, sys
        from pathlib import Path
        manifest = json.loads(sys.argv[1])
        assert manifest['schemaVersion'] == 1, 'HTTP_BACKPORT_VERSION'
        assert set(manifest['modules']) == {'httpClient', 'urllib3'}, 'HTTP_BACKPORT_PAIR'
        prepared = []
        suffixes = {'httpClient': '/http/client.py', 'urllib3': '/urllib3/response.py'}
        for name, entry in manifest['modules'].items():
            assert set(entry) == {'path', 'sourceSha256', 'patchedSha256', 'replacements'}, 'HTTP_BACKPORT_FIELDS'
            path = Path(entry['path'])
            assert path.is_absolute() and str(path).endswith(suffixes[name]), 'HTTP_MODULE_PATH'
            assert path.stat().st_size <= 262144, 'HTTP_SOURCE_BOUND'
            raw = path.read_bytes()
            assert len(raw) <= 262144, 'HTTP_SOURCE_BOUND'
            assert hashlib.sha256(raw).hexdigest() == entry['sourceSha256'], 'HTTP_SOURCE_DRIFT'
            source = raw.decode()
            assert 1 <= len(entry['replacements']) <= 4, 'HTTP_REPLACEMENT_BOUND'
            for old, new in entry['replacements']:
                assert old and source.count(old) == 1, 'HTTP_HUNK_DRIFT'
                source = source.replace(old, new)
            output = source.encode()
            assert len(output) <= 262144, 'HTTP_RESULT_BOUND'
            assert hashlib.sha256(output).hexdigest() == entry['patchedSha256'], 'HTTP_RESULT_DRIFT'
            compile(source, str(path), 'exec')
            prepared.append((path, output))
        # Validate the complete pair before writing either immutable-image file.
        for path, output in prepared:
            path.write_bytes(output)
            cache = list(itertools.islice((path.parent / '__pycache__').glob(path.stem + '.*.pyc'), 9))
            assert len(cache) <= 8, 'HTTP_BYTECODE_BOUND'
            for entry in cache:
                entry.unlink()
        subprocess.run([sys.executable, '-B', '-c', 'from http.client import _is_legal_content_length, _is_legal_chunk_size; import urllib3.response; assert _is_legal_content_length("5") and not _is_legal_content_length("+5"); assert _is_legal_chunk_size(b"a") and not _is_legal_chunk_size(b"+a")'], check=True, timeout=20)
      '';
    in {
      inherit manifest;
      recipe = "RUN ${lib.escapeShellArg python} -B -c ${lib.escapeShellArg ("exec(" + builtins.toJSON program + ")")} ${lib.escapeShellArg (builtins.toJSON manifest)}\n";
    };

  # Temporary frozen-stdlib repair. Retire when the unmodified vendor frozen
  # client passes actual browser framing and current-data recovery contracts.
  # Use the importer's existing source-selection port; never rewrite its archive
  # or compiled offsets. Caller owns the immutable source and image selection.
  mkFrozenPythonHttpFramingBackport =
    { python, pythonVersion, frozenBundle, frozenBundleSha256, sourcePath
    , sourceSha256, rootPath, selectionVariable, environment ? {}
    , consumerVerification ? "", sourceLibraries, sourceStaging, httpBytes }:
    let
      shared = pkgs.pythonFrozenFramingBackport;
      sourceModules = { "http.client" = {
        path = rootPath + "/http/client.py";
        sha256 = shared.nativeSources.${sourceSha256};
        bytes = httpBytes;
      }; } // lib.mapAttrs (name: entry: {
        path = rootPath + "/" + entry.file;
        inherit (entry) sha256 bytes;
      }) sourceLibraries.modules;
      # The vendor source hook also enables application development mode.
      # Restore its frozen loader before any app import, while retaining the
      # environment for native child launchers. Select only the qualified source table.
      bootstrap = ''
        def _hwc_bootstrap(namespace):
            import sys
            from _frozen_importlib_external import spec_from_file_location
            importer = next(x for x in sys.meta_path if type(x).__name__ == 'BypyFrozenImporter')
            importer.develop_mode_path = None
            original = importer.find_spec('site', None)
            if original is None or type(original.loader).__name__ != 'FrozenByteCodeLoader':
                raise RuntimeError('FROZEN_HTTP_SITE_LOADER_DRIFT')
            import hashlib
            from pathlib import Path
            source_modules = ${builtins.toJSON sourceModules}
            for source_name, entry in source_modules.items():
                if source_name in sys.modules:
                    raise RuntimeError('FROZEN_STDLIB_EARLY_IMPORT:' + source_name)
                source_path = Path(entry['path'])
                if not source_path.is_file() or source_path.is_symlink() or source_path.stat().st_size != entry['bytes']:
                    raise RuntimeError('FROZEN_STDLIB_SOURCE_TYPE_SIZE:' + source_name)
                if hashlib.sha256(source_path.read_bytes()).hexdigest() != entry['sha256']:
                    raise RuntimeError('FROZEN_STDLIB_SOURCE_HASH:' + source_name)
            class HttpFinder:
                def find_spec(self, fullname, path=None, target=None):
                    entry = source_modules.get(fullname)
                    if entry is not None:
                        return spec_from_file_location(fullname, entry['path'])
                    return None
            sys.meta_path.insert(0, HttpFinder())
            name = namespace['__name__']
            namespace.clear()
            namespace.update(__name__=name, __spec__=original, __loader__=original.loader,
                __package__="", __file__=original.loader.get_filename('site'))
            exec(original.loader.get_code('site'), namespace)
        _hwc_bootstrap(globals())
      '';
      manifest = {
        schemaVersion = 1;
        inherit pythonVersion frozenBundle frozenBundleSha256 sourcePath
          sourceSha256 rootPath selectionVariable;
        inherit (shared) replacements upstreamCommits;
        patchedSha256 = shared.nativeSources.${sourceSha256};
        bootstrapSha256 = builtins.hashString "sha256" bootstrap;
      };
      program = ''
        import hashlib, importlib.util, json, sys, types
        from pathlib import Path
        import http.client
        if not __debug__:
            raise RuntimeError('FROZEN_STDLIB_OPTIMIZED_INSTALLER')
        spec = json.loads(sys.argv[1])
        assert spec['schemaVersion'] == 1, 'FROZEN_HTTP_VERSION'
        source = Path(spec['sourcePath'])
        assert source.stat().st_size <= 262144, 'FROZEN_HTTP_SOURCE_BOUND'
        raw = source.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == spec['sourceSha256'], 'FROZEN_HTTP_SOURCE_DRIFT'
        text = raw.decode()
        assert 1 <= len(spec['replacements']) <= 4, 'FROZEN_HTTP_HUNK_BOUND'
        for old, new in spec['replacements']:
            assert old and text.count(old) == 1, 'FROZEN_HTTP_HUNK_DRIFT'
            text = text.replace(old, new)
        output = text.encode()
        assert len(output) <= 262144, 'FROZEN_HTTP_RESULT_BOUND'
        assert hashlib.sha256(output).hexdigest() == spec['patchedSha256'], 'FROZEN_HTTP_RESULT_DRIFT'
        compile(text, '<http-framing>', 'exec', dont_inherit=True, optimize=2)
        bundle = Path(spec['frozenBundle'])
        assert bundle.stat().st_size <= 134217728, 'FROZEN_HTTP_ARCHIVE_BOUND'
        digest = hashlib.sha256()
        with bundle.open('rb') as stream:
            while block := stream.read(1048576):
                digest.update(block)
        assert digest.hexdigest() == spec['frozenBundleSha256'], 'FROZEN_HTTP_ARCHIVE_DRIFT'
        assert list(sys.version_info[:3]) == spec['pythonVersion'], 'FROZEN_HTTP_PYTHON_DRIFT'
        loader = http.client.__loader__
        assert type(loader).__name__ == 'FrozenByteCodeLoader', 'FROZEN_HTTP_LOADER_DRIFT'
        def shape(code):
            # Python 3.14 can nest annotation code inside container constants.
            # Normalize recursively, including positions, as in the qualified
            # whole-module baseline; filenames are the only excluded field.
            if isinstance(code, tuple):
                return tuple(shape(value) for value in code)
            if isinstance(code, frozenset):
                return frozenset(shape(value) for value in code)
            if isinstance(code, slice):
                return ('slice', shape(code.start), shape(code.stop), shape(code.step))
            if not isinstance(code, types.CodeType):
                return code
            return (code.co_argcount, code.co_posonlyargcount, code.co_kwonlyargcount,
                code.co_nlocals, code.co_stacksize, code.co_flags, code.co_code,
                shape(code.co_consts),
                code.co_names, code.co_varnames, code.co_name, code.co_qualname,
                code.co_firstlineno, code.co_linetable, code.co_exceptiontable,
                code.co_freevars, code.co_cellvars)
        original = loader.get_code('http.client')
        expected = compile(raw, original.co_filename, 'exec', dont_inherit=True, optimize=2)
        assert shape(original) == shape(expected), 'FROZEN_HTTP_SOURCE_CODE_DRIFT'
        libraries = json.loads(${builtins.toJSON (builtins.toJSON sourceLibraries)})
        staging = Path(${builtins.toJSON sourceStaging})
        assert (staging / 'manifest.json').stat().st_size <= libraries['limits']['manifestBytes'], 'FROZEN_STDLIB_MANIFEST_BOUND'
        assert json.loads((staging / 'manifest.json').read_text()) == libraries, 'FROZEN_STDLIB_MANIFEST_DRIFT'
        prepared = {}
        for name, entry in libraries['modules'].items():
            for folder, size, digest_key in [('original', 'originalBytes', 'originalSha256'), ('lib', 'bytes', 'sha256')]:
                candidate = staging / folder / entry['file']
                assert candidate.is_file() and not candidate.is_symlink(), 'FROZEN_STDLIB_INPUT_TYPE'
                assert candidate.stat().st_size == entry[size] <= libraries['limits']['fileBytes'], 'FROZEN_STDLIB_INPUT_SIZE'
                content = candidate.read_bytes()
                assert hashlib.sha256(content).hexdigest() == entry[digest_key], 'FROZEN_STDLIB_INPUT_HASH'
                if folder == 'original':
                    module_loader = importlib.util.find_spec(name).loader
                    assert type(module_loader).__name__ == 'FrozenByteCodeLoader', 'FROZEN_STDLIB_LOADER_DRIFT'
                    code = module_loader.get_code(name)
                    assert shape(code) == shape(compile(content, code.co_filename, 'exec', dont_inherit=True, optimize=2)), 'FROZEN_STDLIB_SOURCE_CODE_DRIFT'
                else:
                    compile(content, '<frozen/' + entry['file'] + '>', 'exec', dont_inherit=True, optimize=2)
                    prepared[entry['file']] = content
        assert len(prepared) == libraries['limits']['modules'], 'FROZEN_STDLIB_GROUP_COUNT'
        assert sum(map(len, prepared.values())) + len(output) <= libraries['limits']['groupBytes'], 'FROZEN_STDLIB_GROUP_BOUND'
        assert len(output) == ${toString httpBytes}, 'FROZEN_HTTP_RESULT_SIZE'
        bootstrap = ${builtins.toJSON bootstrap}
        assert hashlib.sha256(bootstrap.encode()).hexdigest() == spec['bootstrapSha256'], 'FROZEN_HTTP_BOOTSTRAP_DRIFT'
        compile(bootstrap, '<frozen-bootstrap>', 'exec', dont_inherit=True, optimize=2)
        root = Path(spec['rootPath'])
        assert root.is_absolute() and str(root).startswith('/opt/') and not root.exists(), 'FROZEN_HTTP_OUTPUT_DRIFT'
        # Every guard runs before any write, even inside an optimized launcher.
        folder = root / 'http'
        folder.mkdir(parents=True)
        path = folder / 'client.py'
        path.write_bytes(output)
        path.chmod(0o444)
        for filename, content in prepared.items():
            target = root / filename
            target.write_bytes(content)
            target.chmod(0o444)
        library_proof = root / 'stdlib.json'
        library_proof.write_text(json.dumps(libraries, sort_keys=True) + '\n')
        library_proof.chmod(0o444)
        site = root / 'site.py'
        site.write_text(bootstrap)
        site.chmod(0o444)
        proof = root / 'http-framing.json'
        proof.write_text(json.dumps(spec, sort_keys=True) + '\n')
        proof.chmod(0o444)
        folder.chmod(0o555)
        root.chmod(0o555)
      '';
      verify = ''
        import hashlib, json, sys
        from pathlib import Path
        import http.client
        spec = json.loads(sys.argv[1])
        path = Path(spec['rootPath']) / 'http/client.py'
        assert http.client.__file__ == str(path), 'FROZEN_HTTP_SELECTION_MISSING'
        assert hashlib.sha256(path.read_bytes()).hexdigest() == spec['patchedSha256'], 'FROZEN_HTTP_SELECTED_SOURCE_DRIFT'
        assert getattr(sys, 'frozen', False), 'FROZEN_HTTP_APP_MODE_DRIFT'
        import bypy_importer
        assert not bypy_importer.running_in_develop_mode(), 'FROZEN_HTTP_DEVELOP_MODE'
        site = Path(spec['rootPath']) / 'site.py'
        assert hashlib.sha256(site.read_bytes()).hexdigest() == spec['bootstrapSha256'], 'FROZEN_HTTP_BOOTSTRAP_MISSING'
        finder = next(x for x in sys.meta_path if type(x).__name__ == 'HttpFinder')
        assert finder.find_spec('calibre') is None and finder.find_spec('urllib.request') is None, 'FROZEN_HTTP_SELECTION_TOO_BROAD'
        assert http.client._is_legal_content_length('5') and not http.client._is_legal_content_length('+5')
        assert http.client._is_legal_chunk_size(b'a') and not http.client._is_legal_chunk_size(b'+a')
      '' + consumerVerification;
      command = code: "import sys; sys.argv = ['hwc-frozen-http', "
        + builtins.toJSON (builtins.toJSON manifest) + "]; exec(compile("
        + builtins.toJSON code
        + ", '<frozen-http>', 'exec', optimize=0), {'__name__':'__main__'})";
      run = code: "RUN PYTHONDONTWRITEBYTECODE=1 "
        + lib.concatStringsSep " " (lib.mapAttrsToList (name: value:
          "${name}=${lib.escapeShellArg value}") environment) + " "
        + lib.escapeShellArg python + " -c " + lib.escapeShellArg (command code)
        + "\n";
    in
    assert builtins.match "[A-Z][A-Z0-9_]*" selectionVariable != null;
    assert lib.all (name: builtins.match "[A-Z][A-Z0-9_]*" name != null
      && builtins.isString environment.${name}) (builtins.attrNames environment);
    assert lib.hasPrefix "/opt/" rootPath;
    {
      inherit manifest;
      recipe = run program
        + "ENV ${selectionVariable}=${rootPath}\n"
        + run verify;
    };

  # Temporary shared upstream FFmpeg security inputs. Retire a group when
  # both pinned sources contain its complete fix and native/data checks pass.
  # Ordered advisory groups include prerequisites. Callers own context edits.
  # d143 excludes only API/version metadata to keep the stable library ABI;
  # every additive API implementation and test hunk remains selected.
  ffmpegSecurityInputs = builtins.fromJSON ''
{
  "eb9cef3ef1f6adac1e701e3f5f06739a0fcb0c97": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/eb9cef3ef1f6adac1e701e3f5f06739a0fcb0c97.patch",
    "hash": "sha256-89nXK7WjusxfLXexFWGRK///1KCZHVhHv/ejnpfQ8gw="
  },
  "2b822b7fb6ed195546bc9fd9bdb794e98222bdce": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/2b822b7fb6ed195546bc9fd9bdb794e98222bdce.patch",
    "hash": "sha256-TqQb9dlUMsvItoIxMsuRwktg8fgydihkC7oG1aMbjLY="
  },
  "ed27bfcbbbc0872c0195eaf4dd2c0c93b9f1778e": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/ed27bfcbbbc0872c0195eaf4dd2c0c93b9f1778e.patch",
    "hash": "sha256-k8mKaeJaSHUJ9VYe3bRwRaAMf778eu8/uY1sE1kdTZA="
  },
  "2c2f6e96e31795ae95a8f8323a493ffbc493111f": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/2c2f6e96e31795ae95a8f8323a493ffbc493111f.patch",
    "hash": "sha256-1JATHLDUYF16yik4tb+aBoXKjAvLt+9hzusSOADIvjc="
  },
  "969c7eb091989a664cb7bf66a1f02051cc46cb52": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/969c7eb091989a664cb7bf66a1f02051cc46cb52.patch",
    "hash": "sha256-MvUlNrmlGn9hh9pvtxN/a+Lri97Xl1cIIhlHGyR2m1Y="
  },
  "d1434518fbd03789e3e5dc0657a7a9f1123ce074": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/d1434518fbd03789e3e5dc0657a7a9f1123ce074.patch",
    "hash": "sha256-4UeAbD1Puot0IzOQQVU7Ybs5MWisMEDkmCeYwe3kmv8=",
    "excludes": [
      "doc/APIchanges",
      "libavutil/version.h"
    ]
  },
  "71403a21b02a92b925e26e609e9bd3e48df451cf": {
    "url": "https://code.ffmpeg.org/FFmpeg/FFmpeg/commit/71403a21b02a92b925e26e609e9bd3e48df451cf.patch",
    "hash": "sha256-Pkt4BbUGZ04u0qXVL5eAsTGrdRrcFhfGBaYvHmA5Fbs="
  },
  "a4ddaba8bb7811b1a3afaad59fe6555e720d4754": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/a4ddaba8bb7811b1a3afaad59fe6555e720d4754.patch",
    "hash": "sha256-0bSt5WwieJImem2aEgbEyxKRQu9LfsQ16Iwh7WJSGMM="
  },
  "191715f0232cee64402c3e7733f28ff4061224b6": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/191715f0232cee64402c3e7733f28ff4061224b6.patch",
    "hash": "sha256-yVynZojqFjWvvqyDsYb4SxtY5uezlxqEyvfCJft4kQo="
  },
  "dcf8ce2802bf2be1b0c6b8d4996abca7b669978d": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/dcf8ce2802bf2be1b0c6b8d4996abca7b669978d.patch",
    "hash": "sha256-zqdSQYFpENWvCrgUrjHBrz/KC1yR63woTN2t4bL4F5g="
  },
  "385ac2fadcb4394ec4f65e5c4d3d24003e090f36": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/385ac2fadcb4394ec4f65e5c4d3d24003e090f36.patch",
    "hash": "sha256-s/OBuhD30OzKjLW5KoOt+UAIIxr30cxiEYNFon/ddVY="
  },
  "3c441711a343ccf50196c70a3f0b554b52f8d9de": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/3c441711a343ccf50196c70a3f0b554b52f8d9de.patch",
    "hash": "sha256-tBYQ48123jg2dhBTIs4m618RumGoSmQ58FkQRnRMt+M="
  },
  "c10e7f5dc12367d0dfcc52983d427c6766425fa8": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/c10e7f5dc12367d0dfcc52983d427c6766425fa8.patch",
    "hash": "sha256-N+5zsizt2j4xLnXKz7WwYqfr0Y+Wf3u6UGKKdjEgQfw="
  },
  "3b85fbe89025ea696988488358dfde41a09c53c5": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/3b85fbe89025ea696988488358dfde41a09c53c5.patch",
    "hash": "sha256-tTMlCNtEZjvxILxIa7RLsJIcGmoEf55wQKKdqoaDZU8="
  },
  "52f7983f15678c8a6065327760d7b6eb1c9c84ed": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/52f7983f15678c8a6065327760d7b6eb1c9c84ed.patch",
    "hash": "sha256-FvtJ27QdjSFQ5ssJJoVnSJHC530oxVmXM32VCsCeLcc="
  },
  "a20608d32504d233ab2708f125b86683f1dc23e9": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/a20608d32504d233ab2708f125b86683f1dc23e9.patch",
    "hash": "sha256-84IoG7Oj+rOyL7tntwktpKkT69NoKZAShl/ZyyAbC+4="
  },
  "30a52276f9dff60fe732d8bb8d463e587ff69c94": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/30a52276f9dff60fe732d8bb8d463e587ff69c94.patch",
    "hash": "sha256-BZjRKm5+eWfsegdP07fF+EY0rxXo96R9QK74oIhMa6I="
  },
  "b3c7ebc1edc401fd9881277fdfae93f3f24ceb81": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/b3c7ebc1edc401fd9881277fdfae93f3f24ceb81.patch",
    "hash": "sha256-L4S7scgt72x9X+iyM7lMOMWcy6QOFGYxM/dIIsQJ9Xg="
  },
  "e3d0c719fddd259709c8e275942ab56af3afc35d": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/e3d0c719fddd259709c8e275942ab56af3afc35d.patch",
    "hash": "sha256-2xKZhyIY87hcsh1n98TGtmpxb8Zkg2t/CuojkT9DcUg="
  },
  "62294b6a8ad2370e1435bb9985ebe6b53be14c2b": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/62294b6a8ad2370e1435bb9985ebe6b53be14c2b.patch",
    "hash": "sha256-qQAf+SXHoBqvm1+YNKRgxF8jCBbhLBnFML+w8t3TU8A="
  },
  "7c0b8c8594501dd904ebbb3b45bb3f6e2c745b7d": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/7c0b8c8594501dd904ebbb3b45bb3f6e2c745b7d.patch",
    "hash": "sha256-LfWtjOMnz6aRmpHMIQp9/UWsbxP/2BYRUBdzM0KxVuM="
  },
  "947c57d9e68800dd4d39f110140f8f6c34cedf80": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/947c57d9e68800dd4d39f110140f8f6c34cedf80.patch",
    "hash": "sha256-MVSOzbzLM0jSg8kVrkYP+XnGVPdK5bE55kwnn1NyoTc="
  },
  "02fc47e13f903768b75f7985a2706a6223ab4506": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/02fc47e13f903768b75f7985a2706a6223ab4506.patch",
    "hash": "sha256-p12WoctnuwSE4bcX1O4zQUgHlqaPMyolFdxB1zD+hIo="
  },
  "a5fe21a1a410a680fe93c33b0dd696b7e1c3aea4": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/a5fe21a1a410a680fe93c33b0dd696b7e1c3aea4.patch",
    "hash": "sha256-yuikpgKcBJPYQz3XImupkfVwKYVlRbOQxjjNGn9ux+g="
  },
  "c22667d0fd7916a33fd3e79685b7246fc48f1a62": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/c22667d0fd7916a33fd3e79685b7246fc48f1a62.patch",
    "hash": "sha256-j634GvWJpKqZ/ERbeoyoHcb9A8K86Wf9xpWtmXX4K3Q="
  },
  "3c287af3affe1286350faa69c02bcc5d49de18bb": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/3c287af3affe1286350faa69c02bcc5d49de18bb.patch",
    "hash": "sha256-wNEvNGiRimYSO1Ps3uTEkTNEw2ELPhO2UoI7NQJ/dQ0="
  },
  "16b2049d4d5222db6cd7c031409058571c94f6a9": {
    "url": "https://github.com/FFmpeg/FFmpeg/commit/16b2049d4d5222db6cd7c031409058571c94f6a9.patch",
    "hash": "sha256-cToTjhq7SyjEqkX3xqA/+I7zozhjduIOV2prP/bm1Vc="
  }
}
  '';
  ffmpegSecurityGroups = builtins.fromJSON ''
{
  "CVE-2026-107696": [
    "eb9cef3ef1f6adac1e701e3f5f06739a0fcb0c97"
  ],
  "CVE-2026-107675": [
    "2b822b7fb6ed195546bc9fd9bdb794e98222bdce"
  ],
  "CVE-2026-107677": [
    "ed27bfcbbbc0872c0195eaf4dd2c0c93b9f1778e"
  ],
  "CVE-2026-107676": [
    "2c2f6e96e31795ae95a8f8323a493ffbc493111f"
  ],
  "CVE-2026-107678": [
    "969c7eb091989a664cb7bf66a1f02051cc46cb52",
    "d1434518fbd03789e3e5dc0657a7a9f1123ce074",
    "71403a21b02a92b925e26e609e9bd3e48df451cf"
  ],
  "CVE-2026-107695": [
    "a4ddaba8bb7811b1a3afaad59fe6555e720d4754"
  ],
  "CVE-2026-107697": [
    "191715f0232cee64402c3e7733f28ff4061224b6"
  ],
  "CVE-2026-64830": [
    "dcf8ce2802bf2be1b0c6b8d4996abca7b669978d"
  ],
  "CVE-2026-64833": [
    "385ac2fadcb4394ec4f65e5c4d3d24003e090f36"
  ],
  "CVE-2026-64834": [
    "3c441711a343ccf50196c70a3f0b554b52f8d9de"
  ],
  "CVE-2026-64835": [
    "c10e7f5dc12367d0dfcc52983d427c6766425fa8"
  ],
  "CVE-2026-65703": [
    "3b85fbe89025ea696988488358dfde41a09c53c5"
  ],
  "CVE-2026-65704": [
    "52f7983f15678c8a6065327760d7b6eb1c9c84ed"
  ],
  "CVE-2026-65705": [
    "a20608d32504d233ab2708f125b86683f1dc23e9",
    "30a52276f9dff60fe732d8bb8d463e587ff69c94"
  ],
  "CVE-2026-65706": [
    "b3c7ebc1edc401fd9881277fdfae93f3f24ceb81"
  ],
  "CVE-2026-66036": [
    "e3d0c719fddd259709c8e275942ab56af3afc35d",
    "62294b6a8ad2370e1435bb9985ebe6b53be14c2b"
  ],
  "CVE-2026-66038": [
    "7c0b8c8594501dd904ebbb3b45bb3f6e2c745b7d"
  ],
  "CVE-2026-66039": [
    "947c57d9e68800dd4d39f110140f8f6c34cedf80"
  ],
  "CVE-2026-70628": [
    "02fc47e13f903768b75f7985a2706a6223ab4506"
  ],
  "CVE-2026-70629": [
    "a5fe21a1a410a680fe93c33b0dd696b7e1c3aea4"
  ],
  "CVE-2026-70630": [
    "c22667d0fd7916a33fd3e79685b7246fc48f1a62"
  ],
  "CVE-2026-70631": [
    "3c287af3affe1286350faa69c02bcc5d49de18bb"
  ],
  "CVE-2026-70632": [
    "16b2049d4d5222db6cd7c031409058571c94f6a9"
  ]
}
  '';
  # Context adaptation is shared with inherited distribution patches. Keep
  # every code addition; caller proves exact full-file postimages.
  adaptFfmpegPatchContext = { upstream, edits, name }:
    assert builtins.match "[a-z0-9][a-z0-9-]*" name != null;
    assert builtins.isList edits && edits != [] && builtins.length edits <= 2;
    let editFile = pkgs.writeText "ffmpeg-${name}-context.json" (builtins.toJSON edits);
    in
          pkgs.runCommand "ffmpeg-${name}-7.1.patch" { nativeBuildInputs = [ pkgs.python3 ]; } ''
            python3 -I -B - ${upstream} ${editFile} "$out" <<'PYPATCH'
            import json, pathlib, sys
            source, edits, output = map(pathlib.Path, sys.argv[1:])
            if sys.flags.optimize:
                raise RuntimeError('FFMPEG_CONTEXT_OPTIMIZED')
            assert source.stat().st_size <= 131072, 'FFMPEG_CONTEXT_INPUT_BOUND'
            assert edits.stat().st_size <= 65536, 'FFMPEG_CONTEXT_EDIT_BOUND'
            text = source.read_text()
            changes = json.loads(edits.read_text())
            assert 1 <= len(changes) <= 2, 'FFMPEG_CONTEXT_EDIT_COUNT'
            for old, new in changes:
                assert isinstance(old, str) and isinstance(new, str) and old and new, 'FFMPEG_CONTEXT_EDIT_TYPE'
                assert max(len(old),len(new)) <= 16384 and text.count(old) == 1, 'FFMPEG_CONTEXT_DRIFT'
                text = text.replace(old,new)
            assert len(text.encode()) <= 131072, 'FFMPEG_CONTEXT_OUTPUT_BOUND'
            output.write_text(text)
            PYPATCH
          '';

  selectFfmpegSecurityBackports = { advisories, contextEdits ? {} }:
    assert advisories != [] && builtins.length advisories <= 32;
    assert advisories == lib.unique advisories;
    assert lib.all (id: builtins.hasAttr id ffmpegSecurityGroups) advisories;
    let
      commits = lib.unique (lib.concatMap (id: ffmpegSecurityGroups.${id}) advisories);
      patches = map (commit:
        let
          spec = ffmpegSecurityInputs.${commit};
          upstream = if spec ? excludes then pkgs.fetchpatch spec else pkgs.fetchurl spec;
          edits = contextEdits.${commit} or [];
        in if edits == [] then upstream else
          adaptFfmpegPatchContext { inherit upstream edits; name = commit; }
      ) commits;
    in
    assert builtins.length commits <= 32;
    assert lib.all (commit: lib.elem commit commits) (builtins.attrNames contextEdits);
    { inherit advisories commits patches; };

  mkContainer =
    { name
    , image
    , networkMode ? "media"     # "media" | "vpn" | "host" | { kind="named"; names=[...]; }
    , vpnContainer ? "gluetun"  # which tunnel instance "vpn" mode joins
    , gpuEnable ? true
    , gpuMode ? "intel"         # "intel" | "nvidia-cdi" | "nvidia-legacy"
    , timeZone ? "UTC"
    , ports ? []
    , volumes ? []
    , environment ? {}
    , extraOptions ? []
    , dependsOn ? []
    , user ? null
    , cmd ? []
    , environmentFiles ? []
    , memory ? "2g"
    , cpus ? "1.0"
    , memorySwap ? "4g"
    , pull ? "missing"          # "always" | "missing" | "never" | "newer"
    }:
    let
      # Network options.
      #
      # "vpn" resolves ONLY to a tunnel netns — there is deliberately no fallback
      # branch here. slskd spent six weeks egressing on the house IP because its
      # network mode said "media" and nothing objected; a container that asks for
      # the tunnel and quietly gets the bridge instead is the same failure with a
      # different spelling. A wrong vpnContainer name must break the container,
      # not silently un-tunnel it. Enforcement that the named instance is real
      # and enabled lives in mkVpnAssertions below, which every VPN-mode module
      # calls.
      podmanNetworkOpts =
        if builtins.isAttrs networkMode then
          let names = networkMode.names or []; in
          assert (networkMode.kind or null) == "named";
          assert builtins.isList names && names != [];
          assert lib.all (name: builtins.isString name && builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.-]*" name != null) names;
          assert builtins.length (lib.unique names) == builtins.length names;
          [ "--network=${lib.concatStringsSep "," names}" ]
        else if networkMode == "vpn" then [ "--network=container:${vpnContainer}" ]
        else if networkMode == "host" then [ "--network=host" ]
        else [ "--network=${mediaNetworkName}" ];

      # GPU options based on mode
      gpuOpts =
        if (!gpuEnable) then []
        else if gpuMode == "nvidia-cdi" then [
          # NVIDIA CDI (Container Device Interface) mode - modern approach
          "--device=nvidia.com/gpu=0"
        ]
        else if gpuMode == "nvidia-legacy" then [
          # Legacy NVIDIA passthrough
          "--device=/dev/nvidia0:/dev/nvidia0:rwm"
          "--device=/dev/nvidiactl:/dev/nvidiactl:rwm"
          "--device=/dev/nvidia-modeset:/dev/nvidia-modeset:rwm"
          "--device=/dev/nvidia-uvm:/dev/nvidia-uvm:rwm"
          "--device=/dev/nvidia-uvm-tools:/dev/nvidia-uvm-tools:rwm"
          "--device=/dev/dri:/dev/dri:rwm"
        ]
        else [
          # Intel/AMD GPU passthrough (default)
          "--device=/dev/dri:/dev/dri"
        ];

      # Base environment (PUID/PGID for linuxserver.io style containers)
      baseEnv = {
        PUID = "1000";  # eric UID
        PGID = "100";   # users GID (CRITICAL - users group is GID 100, not 1000!)
        TZ = timeZone;
      };

      # Resource limits
      resourceOpts = [
        "--memory=${memory}"
        "--cpus=${cpus}"
        "--memory-swap=${memorySwap}"
      ];

      containerDef = {
        inherit image dependsOn pull;
        autoStart = true;
        environment = baseEnv // environment;
        environmentFiles = environmentFiles;
        extraOptions = podmanNetworkOpts ++ gpuOpts ++ resourceOpts ++ extraOptions;
        ports = ports;
        volumes = volumes;
      } // lib.optionalAttrs (user != null) { inherit user; }
        // lib.optionalAttrs (cmd != []) { inherit cmd; };

    in {
      virtualisation.oci-containers.containers.${name} = containerDef;
    };

  # Assertions every VPN-mode container needs, produced in one place.
  #
  # These used to be hand-copied into eight modules as
  # `cfg.network.mode != "vpn" || config.hwc.networking.gluetun.enable` — same
  # predicate, eight spellings, and all eight only checked that *a* tunnel
  # existed, not that the one this container joins does. With more than one
  # tunnel that check is worse than none: a container can name a tunnel that was
  # never declared and still pass. Callers pass the live instance set:
  #
  #   mkVpnAssertions {
  #     name = "slskd"; networkMode = cfg.network.mode;
  #     vpnContainer = "gluetun-slskd";
  #     gluetunInstances = config.hwc.networking.gluetun.instances;
  #   }
  mkVpnAssertions =
    { name
    , networkMode
    , vpnContainer ? "gluetun"
    , gluetunInstances
    }:
    lib.optionals (networkMode == "vpn") [
      {
        assertion = gluetunInstances ? ${vpnContainer};
        message = "${name} requests VPN networking on tunnel '${vpnContainer}', which is not declared in hwc.networking.gluetun.instances";
      }
      {
        assertion = lib.attrByPath [ vpnContainer "enable" ] false gluetunInstances;
        message = "${name} requests VPN networking on tunnel '${vpnContainer}', which is declared but not enabled";
      }
    ];
}
