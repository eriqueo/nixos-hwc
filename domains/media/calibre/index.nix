{ lib, config, pkgs, ... }:

let
  helpers = import ../../lib/mkContainer.nix { inherit lib pkgs; };
  cfg = config.hwc.media.calibre;
  paths = config.hwc.paths;
  calibrePython = "/opt/calibre/calibre-debug";
  calibrePythonVersion = [ 3 14 8 ];
  httpSourceSha256 = "016aa7664201a82f0f37ddfb11ed662dd1f07aa23c9470c6a3cb3278aa479230";
  httpSource = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/python/cpython/v3.14.8/Lib/http/client.py";
    sha256 = httpSourceSha256;
  };
  httpBackport = helpers.mkFrozenPythonHttpFramingBackport {
    sourceLibraries = stdlibFacts;
    sourceStaging = "/tmp/hwc-calibre-stdlib";
    httpBytes = 59792;
    python = calibrePython;
    pythonVersion = calibrePythonVersion;
    frozenBundle = "/opt/calibre/lib/calibre-extensions/python-lib.bypy.frozen";
    frozenBundleSha256 = "558037f93bef7df037ff1c38519680ed1083263b9e86b38407c4e819a2acffb2";
    sourcePath = "/tmp/hwc-calibre-http/client.py";
    sourceSha256 = httpSourceSha256;
    rootPath = "/opt/hwc-calibre-http";
    selectionVariable = "CALIBRE_DEVELOP_FROM";
    environment = {
      CALIBRE_CONFIG_DIRECTORY = "/tmp/hwc-frozen-config";
      XDG_CACHE_HOME = "/tmp/hwc-frozen-cache";
    };
    consumerVerification = sqliteRuntimeProof + stdlibRuntimeProof + sslRuntimeProof + socketFrozenRuntimeProof + ''
      native_ssl = native_ssl_proof()
      native_socket = native_socket_proof()
      libraries = stdlib_proof()
      import calibre.gui2
      from calibre.constants import is_running_from_develop
      from calibre.utils.ipc.simple_worker import fork_job
      assert not is_running_from_develop, 'CALIBRE_GUI_DEVELOP_MODE'
      worker = ${builtins.toJSON (sqliteRuntimeProof + stdlibRuntimeProof + sslRuntimeProof + socketFrozenRuntimeProof + ''
        def prove():
            import http.client
            from calibre.constants import is_running_from_develop
            return (is_running_from_develop,http.client.__file__,bool(http.client._is_legal_chunk_size(b"a")),bool(http.client._is_legal_chunk_size(b"+a")),native_ssl_proof(),stdlib_proof(),native_socket_proof())
      '')}
      actual = fork_job(worker, 'prove', timeout=15, no_output=True, module_is_source_code=True)['result']
      assert actual == (False, str(path), True, False, native_ssl, libraries, native_socket), 'CALIBRE_WORKER_HTTP_SELECTION'
    '';
  };
  # Temporary: frozen3.14.8 lacks these upstream library repairs. Retire only
  # after unmodified vendor modules pass the safety/GUI/worker/data contract.
  stdlibFacts = {
    schemaVersion = 1;
    pythonVersion = calibrePythonVersion;
    commands = { extract = "extract"; finish = "finish"; };
    # Original bytes already have one explicit owner; GNU patch must not
    # publish extra .orig files when a strict hunk has only a line offset.
    patchFlags = [ "--force" "--batch" "--no-backup-if-mismatch" "--fuzz=0" "-p1" ];
    limits = { fileBytes = 262144; groupBytes = 1048576; manifestBytes = 16384; modules = 4; };
    modules = {
      poplib = { file = "poplib.py"; originalBytes = 14604; bytes = 14727;
        originalSha256 = "527e714523264093910a0a0b1a55c6583f952835c89061537fc40ad98c347056";
        sha256 = "a6ffff188814b56d95b043c31d9e0dfee51ac6d6e92afe74ab070cb6136b076f"; };
      shutil = { file = "shutil.py"; originalBytes = 60235; bytes = 60684;
        originalSha256 = "28a5df6415bf1a7ab36cbd544d6d35ae0f056a198e3872a786dc4e156d5fcd7d";
        sha256 = "b6e01921d7f8a6dcac774c07d1d7f858b2d536ee9535ae576120503fcc559261"; };
      tarfile = { file = "tarfile.py"; originalBytes = 120808; bytes = 120902;
        originalSha256 = "825de0990d0bedf6ed8db97b4a0fc98f25617a692c3d38c0bbba800beb9952fb";
        sha256 = "0bd3d6e26d6c4659fe23e79ca3390c05257209ba3259a3b3d909486677b4d475"; };
      tempfile = { file = "tempfile.py"; originalBytes = 33112; bytes = 36132;
        originalSha256 = "3714372b63f6bc05a5273425d446f6ad3a2112a659c71c321bb4575fd082d634";
        sha256 = "5e2a8c5539e2aa3f4d39a364c701711ba54eeca88c17e95d31ebb83ea84de27d"; };
    };
    patches = [
      { advisory = "CVE-2026-87910";
        url = "https://github.com/python/cpython/commit/a4919937a4e1e69a0d178909c6f20557eca5d1d0.patch";
        includes = [ "Lib/tarfile.py" ]; hash = "sha256-WYV0ICqpie1suOYcUfoGR9zo+W695b0e0DdiVWHppcc="; }
      { advisory = "CVE-2026-114583";
        url = "https://github.com/python/cpython/commit/0901ad4ffb22605f12b705d1c1197f0a01f0ba0b.patch";
        includes = [ "Lib/tarfile.py" ]; hash = "sha256-NZn+H8oVxpoCzNXSmjw59LT+eu4RzLPv6F1j3uJHkEM="; }
      { advisory = "CVE-2026-12345";
        url = "https://github.com/python/cpython/commit/58ed0259cae509a19138795df302fe60b544dc74.patch";
        includes = [ "Lib/shutil.py" "Lib/tempfile.py" ]; hash = "sha256-qCufvWMavq4yVj5HEj9Y19ckXvPuvITiSP71H5GBR6Q="; }
      { advisory = "CVE-2025-15367";
        url = "https://github.com/python/cpython/commit/b234a2b67539f787e191d2ef19a7cbdce32874e7.patch";
        includes = [ "Lib/poplib.py" ]; hash = "sha256-ZfHY+/hyZHnhIjvt8rjpxxXaLl7K2d+khl7EA3OpGwQ="; }
    ];
  };
  stdlibRuntimeProof = ''
    def stdlib_proof():
        import hashlib, importlib, json
        from pathlib import Path
        root = Path(${builtins.toJSON httpBackport.manifest.rootPath})
        spec = json.loads(${builtins.toJSON (builtins.toJSON stdlibFacts)})
        assert json.loads((root / 'stdlib.json').read_text()) == spec, 'CALIBRE_STDLIB_MANIFEST'
        result = []
        for name, entry in spec['modules'].items():
            module = importlib.import_module(name)
            target = root / entry['file']
            assert module.__file__ == str(target), 'CALIBRE_STDLIB_SELECTION'
            assert target.stat().st_size == entry['bytes'] and hashlib.sha256(target.read_bytes()).hexdigest() == entry['sha256'], 'CALIBRE_STDLIB_BYTES'
            result.append((name, module.__file__, entry['sha256']))
        import poplib
        probe = object.__new__(poplib.POP3)
        probe._debugging = 0
        probe.encoding = 'utf-8'
        sent = []
        probe._putline = sent.append
        for control in ['\r', '\n', '\0', '\t', '\x7f']:
            try: probe._putcmd('USER safe' + control + 'unsafe')
            except ValueError: pass
            else: raise AssertionError('CALIBRE_POP_CONTROL')
        assert not sent, 'CALIBRE_POP_TRANSPORT'
        return result
  '';
  stdlibSpec = pkgs.writeText "calibre-stdlib-source.json" (builtins.toJSON stdlibFacts);
  stdlibPatches = map (entry: pkgs.fetchpatch { inherit (entry) url includes hash; }) stdlibFacts.patches;
  stdlibSourceGuard = pkgs.writeText "calibre-stdlib-source-guard.py" ''
    import hashlib, itertools, json, pathlib, re, stat, sys, tarfile

    if not __debug__:
        raise AssertionError("CALIBRE_STDLIB_OPTIMIZED_GUARD")

    def metadata(spec, runtime=False):
        version = spec["pythonVersion"] if runtime else spec.get("compilerPythonVersion", spec["pythonVersion"])
        assert spec["schemaVersion"] == 1 and list(sys.version_info[:3]) == version, "CALIBRE_STDLIB_VERSION"
        assert len(spec["modules"]) == spec["limits"]["modules"] and 1 <= len(spec["modules"]) <= 5, "CALIBRE_STDLIB_MODULE_BOUND"
        assert len(spec["patches"]) == spec["limits"].get("patches", 4) and len({p.get("id", p["advisory"]) for p in spec["patches"]}) == len(spec["patches"]), "CALIBRE_STDLIB_PATCH_SET"
        assert 1 <= len(spec["patches"]) <= 8, "CALIBRE_STDLIB_PATCH_BOUND"
        if "runtimeRoot" in spec:
            assert pathlib.Path(spec["runtimeRoot"]).is_absolute() and pathlib.Path(spec["proofFile"]).name == spec["proofFile"], "SYSTEM_PYTHON_METADATA_PATH"
            assert spec["runtimeMode"] == 0o644, "SYSTEM_PYTHON_METADATA_MODE"
        for name, entry in spec["modules"].items():
            assert re.fullmatch(r"[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)?", name) and entry["file"] == name.replace(".", "/") + ".py", "CALIBRE_STDLIB_PATH"
            assert 0 < entry["bytes"] <= spec["limits"]["fileBytes"] and 0 < entry["originalBytes"] <= spec["limits"]["fileBytes"], "CALIBRE_STDLIB_SOURCE_BOUND"

    def content(spec, entry, raw, original):
        size, digest = ("originalBytes", "originalSha256") if original else ("bytes", "sha256")
        assert len(raw) == entry[size] <= spec["limits"]["fileBytes"], "CALIBRE_STDLIB_SOURCE_SIZE"
        assert hashlib.sha256(raw).hexdigest() == entry[digest], "CALIBRE_STDLIB_SOURCE_HASH"

    def extract(spec, archive, root):
        metadata(spec)
        assert not root.exists() and not root.is_symlink(), "CALIBRE_STDLIB_SOURCE_ROOT"
        prefix = "Python-" + ".".join(map(str, spec["pythonVersion"])) + "/Lib/"
        files = {}
        with tarfile.open(archive) as bundle:
            for name, entry in spec["modules"].items():
                member = bundle.getmember(prefix + entry["file"])
                assert member.isfile() and member.size == entry["originalBytes"], "CALIBRE_STDLIB_ARCHIVE_MEMBER"
                raw = bundle.extractfile(member).read(spec["limits"]["fileBytes"] + 1)
                content(spec, entry, raw, True)
                files[entry["file"]] = raw
        assert sum(map(len, files.values())) * 2 <= spec["limits"]["groupBytes"], "CALIBRE_STDLIB_GROUP_BOUND"
        # All original members validated before any owned work-tree write.
        for folder in ["Lib", "original"]:
            (root / folder).mkdir(parents=True)
            for name, raw in files.items():
                path = root / folder / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)

    def finish(spec, root, output):
        metadata(spec)
        assert not output.exists() and not output.is_symlink(), "CALIBRE_STDLIB_OUTPUT_ROOT"
        files, used = {}, 0
        for folder, original in [("original", True), ("Lib", False)]:
            directory = root / folder
            assert directory.is_dir() and not directory.is_symlink(), "CALIBRE_STDLIB_INPUT_ROOT"
            assert {str(p.relative_to(directory)) for p in directory.rglob("*") if p.is_file()} == {v["file"] for v in spec["modules"].values()}, "CALIBRE_STDLIB_INPUT_SET"
            for name, entry in spec["modules"].items():
                path = directory / entry["file"]
                assert stat.S_ISREG(path.lstat().st_mode) and path.stat().st_size <= spec["limits"]["fileBytes"], "CALIBRE_STDLIB_FILE_TYPE_BOUND"
                raw = path.read_bytes()
                if not original and entry.get("replacements"):
                    content(spec, entry, raw, True)
                    text = raw.decode()
                    for old, new in entry["replacements"]:
                        assert old and text.count(old) == 1, "CALIBRE_STDLIB_HUNK_DRIFT"
                        text = text.replace(old, new)
                    raw = text.encode()
                used += len(raw)
                assert used <= spec["limits"]["groupBytes"], "CALIBRE_STDLIB_GROUP_BOUND"
                content(spec, entry, raw, original)
                compile(raw, "<frozen/" + entry["file"] + ">", "exec", dont_inherit=True, optimize=2)
                files[("original" if original else "lib", entry["file"])] = raw
        manifest = json.dumps(spec, sort_keys=True, separators=(",", ":")).encode()
        assert len(manifest) <= spec["limits"]["manifestBytes"], "CALIBRE_STDLIB_MANIFEST_BOUND"
        # Every original and patched file passes before output publication.
        for (folder, name), raw in files.items():
            directory = output / folder;directory.mkdir(parents=True, exist_ok=True)
            path = directory / name;path.parent.mkdir(parents=True, exist_ok=True);path.write_bytes(raw);path.chmod(0o444)
        (output / "manifest.json").write_bytes(manifest)

    def installed(spec, root):
        metadata(spec, runtime=True)
        assert str(root) == spec["runtimeRoot"] and root.is_dir() and not root.is_symlink(), "SYSTEM_PYTHON_ROOT"
        proof = root / spec["proofFile"]
        assert stat.S_ISREG(proof.lstat().st_mode) and proof.stat().st_size <= spec["limits"]["manifestBytes"], "SYSTEM_PYTHON_PROOF_BOUND"
        assert json.loads(proof.read_text()) == spec, "SYSTEM_PYTHON_PROOF"
        for entry in spec["modules"].values():
            path = root / entry["file"]
            assert stat.S_ISREG(path.lstat().st_mode) and stat.S_IMODE(path.stat().st_mode) == spec["runtimeMode"], "SYSTEM_PYTHON_MODE"
            content(spec, entry, path.read_bytes(), False)

    def install(spec, source, root):
        # Non-retriable private image-layer effect: check the entire group,
        # target ownership, allowed preimages and caches before any write.
        metadata(spec, runtime=True)
        assert str(root) == spec["runtimeRoot"] and root.is_dir() and not root.is_symlink(), "SYSTEM_PYTHON_ROOT"
        manifest = source / "manifest.json"
        assert stat.S_ISREG(manifest.lstat().st_mode) and manifest.stat().st_size <= spec["limits"]["manifestBytes"], "SYSTEM_PYTHON_MANIFEST_BOUND"
        assert json.loads(manifest.read_text()) == spec, "SYSTEM_PYTHON_MANIFEST"
        proof = root / spec["proofFile"]
        assert not proof.exists() and not proof.is_symlink(), "SYSTEM_PYTHON_EXISTING_PROOF"
        prepared, caches = [], []
        for entry in spec["modules"].values():
            path, replacement = root / entry["file"], source / "lib" / entry["file"]
            assert all(not p.is_symlink() for p in path.parents if p.is_relative_to(root)), "SYSTEM_PYTHON_PARENT"
            identity = path.lstat()
            assert stat.S_ISREG(identity.st_mode) and stat.S_IMODE(identity.st_mode) == spec["runtimeMode"], "SYSTEM_PYTHON_ORIGINAL_MODE"
            assert path.stat().st_size <= spec["limits"]["fileBytes"], "SYSTEM_PYTHON_ORIGINAL_BOUND"
            raw = path.read_bytes()
            already_patched = entry.get("allowPatchedInput", False) and len(raw) == entry["bytes"] and hashlib.sha256(raw).hexdigest() == entry["sha256"]
            if not already_patched:
                content(spec, entry, raw, True)
            assert stat.S_ISREG(replacement.lstat().st_mode) and replacement.stat().st_size <= spec["limits"]["fileBytes"], "SYSTEM_PYTHON_REPLACEMENT_BOUND"
            output = replacement.read_bytes()
            content(spec, entry, output, False)
            compile(output, str(path), "exec", dont_inherit=True, optimize=2)
            cache_root = path.parent / "__pycache__"
            assert not cache_root.is_symlink(), "SYSTEM_PYTHON_CACHE_ROOT"
            cache = list(itertools.islice(cache_root.glob(path.stem + ".*.pyc"), 9))
            assert len(cache) <= 8 and all(stat.S_ISREG(p.lstat().st_mode) for p in cache), "SYSTEM_PYTHON_CACHE_BOUND"
            caches.extend(cache)
            prepared.append((path, output, identity, already_patched))
        assert sum(len(output) for _, output, _, _ in prepared) <= spec["limits"]["groupBytes"], "SYSTEM_PYTHON_GROUP_BOUND"
        for path, output, identity, already_patched in prepared:
            if not already_patched:
                path.write_bytes(output)
            actual = path.stat()
            assert (actual.st_uid, actual.st_gid, actual.st_mode) == (identity.st_uid, identity.st_gid, identity.st_mode), "SYSTEM_PYTHON_OWNER_MODE"
        for path in caches:
            path.unlink()
        proof.write_text(json.dumps(spec, sort_keys=True))
        proof.chmod(0o444)
        installed(spec, root)

    if __name__ == "__main__":
        mode, spec_file, source, destination = sys.argv[1:]
        spec_file, source, destination = map(pathlib.Path, [spec_file, source, destination])
        assert spec_file.stat().st_size <= 16384, "CALIBRE_STDLIB_SPEC_BOUND"
        spec = json.loads(spec_file.read_text())
        if mode == spec["commands"]["extract"]:
            extract(spec, source, destination)
        elif mode == spec["commands"]["finish"]:
            finish(spec, source, destination)
        elif mode == spec["commands"].get("install"):
            install(spec, source, destination)
        else:
            assert mode == spec["commands"].get("verify"), "CALIBRE_STDLIB_COMMAND"
            installed(spec, destination)
  '';
  # REPLACEABLE: extract only the four regular source members, retain their
  # original bytes for the full frozen-code parity check, then patch/compile.
  stdlibPackage = assert pkgs.python314.version == lib.concatMapStringsSep "." toString calibrePythonVersion;
    pkgs.runCommand "calibre-frozen-stdlib-${pkgs.python314.version}" {} (''
      ${pkgs.python314.interpreter} -I -B ${stdlibSourceGuard} ${stdlibFacts.commands.extract} ${stdlibSpec} ${pkgs.python314.src} source
    '' + lib.concatMapStringsSep "\n" (patch:
      "${pkgs.patch}/bin/patch ${lib.escapeShellArgs stdlibFacts.patchFlags} -d source -i ${patch}") stdlibPatches + ''

      ${pkgs.python314.interpreter} -I -B ${stdlibSourceGuard} ${stdlibFacts.commands.finish} ${stdlibSpec} source "$out"
    '');
  # Temporary: the vendor native SSL predates CPython's compromised-key distrust.
  # Retire when the unmodified vendor passes the TLS/API/GUI/worker contract.
  # Original-path fresh-process qualification precedes shared image adoption.
  sslDescriptor = {
    schemaVersion = 1;
    pythonVersion = httpBackport.manifest.pythonVersion;
    opensslVersion = "3.5.9";
    advisory = "CVE-2026-115557";
    upstreamCommit = "e9bf2cf84eebf838a1edaa1c648c2b36345b99d3";
    patch = {
      url = "https://github.com/python/cpython/commit/${sslDescriptor.upstreamCommit}.patch";
      includes = [ "Modules/_ssl.c" "Modules/_ssl/distrusted_spki.h" ];
      hash = "sha256-golYkxggS4HEq/zTjv3TeI3AVKuqTqtKXCBrU+0Ky4E=";
    };
    sourceFiles = {
      "Modules/_ssl.c" = "208daac45832d0bc2297834e09e017098af38d406d44820c3f250b2026a22375";
      "Modules/_ssl/distrusted_spki.h" = "bff6ffbbdb400bcfee6d15f8309da2128157feb7d8be98d14041abe80fc9ff8e";
    };
    headers = {
      python = "9005ef414e92cd4b6ff6d9fdaafdee4d614b23df71c4ca1e1df4883c1f1e0c9c";
      openssl = "9647fc99758cf83e3bcf11ae310894fd4911ad62bff22d8213a614df89cfedda";
    };
    abiMacros = {
      Py_DEBUG = 0; Py_GIL_DISABLED = 0; WITH_PYMALLOC = 1;
      Py_ENABLE_SHARED = 1; SIZEOF_VOID_P = 8; SIZEOF_TIME_T = 8;
      Py_TRACE_REFS = 0; Py_STATS = 0; Py_REF_DEBUG = 0;
    };
    original = {
      path = "${builtins.dirOf calibrePython}/lib/calibre-extensions/_ssl.so";
      sha256 = "7b6f778ec806ec814430c70b72751c487953fefbac8bbf79d1db1d8aefce5c04";
      bytes = 236768;
      mode = 493;
      needed = [ "libc.so.6" "libcrypto.so.3" "libssl.so.3" ];
      apiSha256 = "6562f5b125c4e340777b2f7b750a37ed5ceb6818b9786674af803b14bb6c2e5e";
    };
    # Vendor reports build headers3.5.8 while actually loading3.5.9. Keep the
    # rebuilt module's truthful header metadata; every other member/constant
    # must match the original fingerprint after reversing this one change.
    apiConstantChanges."_OPENSSL_API_VERSION" = {
      original = [ 3 5 0 8 0 ];
      rebuilt = let v = map lib.toInt (lib.splitString "." sslDescriptor.opensslVersion);
        in [ (builtins.elemAt v 0) (builtins.elemAt v 1) 0 (builtins.elemAt v 2) 0 ];
    };
    apiSha256 = "4d9e4f1ec6c62f7aea031f35f0763597449f9bd1dc7b0d6ffe81a71b55b25e20";
    rpath = "$ORIGIN/..";
    limits = { fileBytes = 2097152; manifestBytes = 16384; sourceBytes = 524288; };
  };
  sslSpec = pkgs.writeText "calibre-native-ssl.json" (builtins.toJSON sslDescriptor);
  pythonNativeSourceChecks = ''
    def check_python_source(spec, root, python_header, prefix):
        assert spec["schemaVersion"] == 1, prefix + "_SCHEMA"
        for name, expected in spec["sourceFiles"].items():
            path = root / name
            assert path.is_file() and not path.is_symlink(), prefix + "_SOURCE_TYPE"
            raw = path.read_bytes()
            assert 0 < len(raw) <= spec["limits"]["sourceBytes"], prefix + "_SOURCE_BOUND"
            assert hashlib.sha256(raw).hexdigest() == expected, prefix + "_SOURCE_DRIFT"
        assert python_header.is_file() and not python_header.is_symlink(), prefix + "_HEADER_TYPE"
        raw = python_header.read_bytes()
        assert 0 < len(raw) <= spec["limits"]["sourceBytes"], prefix + "_HEADER_BOUND"
        assert hashlib.sha256(raw).hexdigest() == spec["headers"]["python"], prefix + "_HEADER_DRIFT"
        text = python_header.read_text()
        for name, expected in spec["abiMacros"].items():
            values = re.findall(r"^#define " + re.escape(name) + r"\s+(\d+)\s*$", text, re.M)
            assert len(values) <= 1 and (int(values[0]) if values else 0) == expected, prefix + "_ABI_DRIFT"
  '';
  sslSourceGuard = pkgs.writeText "calibre-native-ssl-source-guard.py" (''
    import hashlib, json, pathlib, re, sys
  '' + pythonNativeSourceChecks + ''
    def check(spec, root, python_header, openssl_header):
        check_python_source(spec, root, python_header, "CALIBRE_SSL")
        assert openssl_header.is_file() and not openssl_header.is_symlink(), "CALIBRE_SSL_HEADER_TYPE"
        raw = openssl_header.read_bytes()
        assert 0 < len(raw) <= spec["limits"]["sourceBytes"], "CALIBRE_SSL_HEADER_BOUND"
        assert hashlib.sha256(raw).hexdigest() == spec["headers"]["openssl"], "CALIBRE_SSL_HEADER_DRIFT"
        text = openssl_header.read_text()
        actual = [int(re.search(r"^#\s*define OPENSSL_VERSION_" + name + r"\s+(\d+)\s*$", text, re.M)[1])
                  for name in ["MAJOR", "MINOR", "PATCH"]]
        assert actual == list(map(int, spec["opensslVersion"].split("."))), "CALIBRE_SSL_OPENSSL_DRIFT"

    if __name__ == "__main__":
        if not __debug__:
            raise AssertionError("CALIBRE_SSL_OPTIMIZED_GUARD")
        spec, root, python_header, openssl_header = map(pathlib.Path, sys.argv[1:])
        assert spec.stat().st_size <= 16384, "CALIBRE_SSL_SPEC_BOUND"
        check(json.loads(spec.read_text()), root, python_header, openssl_header)
        print("CALIBRE_SSL_SOURCE_FIXED")
  '');
  # REPLACEABLE: one native module rebuilt from the pinned source and SDK.
  # Do not run Python's full configure/build or link a second libpython.
  bluezSdkInclude = "${lib.getDev pkgs.bluez}/include";
  distroPythonSource = pkgs.fetchurl {
    url = "https://archive.ubuntu.com/ubuntu/pool/main/p/python3.14/python3.14_3.14.4.orig.tar.xz";
    sha256 = "d923c51303e38e249136fc1bdf3568d56ecb03214efdef48516176d3d7faaef8";
  };
  pythonNativeSdks = {
    frozen = {
      src = pkgs.python314.src;
      pythonHeader = "${pkgs.python314}/include/python3.14/pyconfig.h";
      includeDirs = [ "${pkgs.python314}/include/python3.14"
        "${pkgs.python314}/include/python3.14/internal" ];
    };
    system = {
      src = distroPythonSource;
      pythonHeader = "${distroSdk}/usr/include/x86_64-linux-gnu/python3.14/pyconfig.h";
      includeDirs = map (path: "${distroSdk}/${path}") [ "usr/include/python3.14"
        "usr/include/python3.14/internal" "usr/include/x86_64-linux-gnu/python3.14"
        "usr/include" "usr/include/x86_64-linux-gnu" ];
    };
  };
  mkPythonNativePackage = { pname, src, descriptor, spec, pythonHeader, opensslHeader ? null,
    includeDirs, linkArgs, buildInputs, moduleName ? "_ssl", buildSource ? "Modules/_ssl.c",
    patches ? [ (pkgs.fetchpatch descriptor.patch) ], sourcePreparation ? "",
    sourceCheck ? "python3 -I -B ${sslSourceGuard} ${spec} . ${pythonHeader} ${opensslHeader}",
    needed ? descriptor.original.needed }:
    pkgs.stdenv.mkDerivation {
      inherit pname src buildInputs;
      version = lib.concatMapStringsSep "." toString descriptor.pythonVersion;
      inherit patches;
      patchFlags = [ "-p1" "--fuzz=0" ];
      nativeBuildInputs = [ pkgs.python3 pkgs.patchelf ];
      dontConfigure = true;
      postPatch = ''
        ${sourcePreparation}
        ${sourceCheck}
      '';
      buildPhase = ''
        runHook preBuild
        $CC -shared -fPIC -O2 -DNDEBUG -fno-strict-aliasing \
          ${lib.concatMapStringsSep " " (path: "-I${path}") includeDirs} \
          ${buildSource} ${lib.concatStringsSep " " linkArgs} -o ${moduleName}.so
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/lib"
        install -m755 ${moduleName}.so "$out/lib/${moduleName}.so"
        runHook postInstall
      '';
      # Run after Nix's strip/RPATH fixups: the output loads vendor libraries
      # beside the original target, not the Nix build SDK's runtime closure.
      postFixup = ''
        patchelf --set-rpath ${lib.escapeShellArg descriptor.rpath} "$out/lib/${moduleName}.so"
        python3 -I -B - ${spec} "$out" <<'PYSSL'
        import hashlib, json, pathlib, subprocess, sys
        spec_file, output = map(pathlib.Path, sys.argv[1:])
        spec = json.loads(spec_file.read_text())
        path = output / ${builtins.toJSON "lib/${moduleName}.so"}
        def elf(flag):
            return subprocess.check_output(["patchelf", flag, str(path)], text=True).strip()
        needed, rpath, soname = sorted(elf("--print-needed").splitlines()), elf("--print-rpath"), elf("--print-soname")
        assert needed == json.loads(${builtins.toJSON (builtins.toJSON needed)}) and rpath == spec["rpath"] and not soname, "CALIBRE_NATIVE_EXTENSION_PORTABLE_ABI"
        raw = path.read_bytes()
        assert 0 < len(raw) <= spec["limits"]["fileBytes"], "CALIBRE_NATIVE_EXTENSION_BUILT_BOUND"
        result = dict(schemaVersion=1, descriptor=spec, file=dict(sha256=hashlib.sha256(raw).hexdigest(),
            bytes=len(raw), needed=needed, rpath=rpath, soname=soname))
        raw = json.dumps(result, sort_keys=True, separators=(",", ":")).encode()
        assert len(raw) <= spec["limits"]["manifestBytes"], "CALIBRE_NATIVE_EXTENSION_MANIFEST_BOUND"
        (output / "manifest.json").write_bytes(raw)
        PYSSL
      '';
    };
  sslPackage = assert lib.assertMsg
    (pkgs.python314.version == lib.concatMapStringsSep "." toString sslDescriptor.pythonVersion
      && pkgs.openssl_3_5.version == sslDescriptor.opensslVersion)
    "Calibre SSL requires the measured Python and OpenSSL SDK versions";
    mkPythonNativePackage {
      pname = "calibre-native-ssl";
      inherit (pythonNativeSdks.frozen) src pythonHeader;
      descriptor = sslDescriptor;
      spec = sslSpec;
      opensslHeader = "${lib.getDev pkgs.openssl_3_5}/include/openssl/opensslv.h";
      includeDirs = pythonNativeSdks.frozen.includeDirs ++ [ "${lib.getDev pkgs.openssl_3_5}/include" bluezSdkInclude ];
      linkArgs = [ "-L${lib.getLib pkgs.openssl_3_5}/lib" "-lssl" "-lcrypto" ];
      buildInputs = [ pkgs.openssl_3_5 ];
    };
  sslTrustKinds = { private = "calibre-private"; system = "system-default"; };
  sslGuard = pkgs.writeText "calibre-native-ssl-guard.py" ''
    import hashlib, importlib.util, json, os, pathlib, shutil, stat, sys
    TRUST_KINDS = ${builtins.toJSON sslTrustKinds}

    if not __debug__:
        raise AssertionError("CALIBRE_SSL_OPTIMIZED_GUARD")

    def canonical(value):
        return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()

    def read(path, maximum):
        identity = path.lstat()
        assert stat.S_ISREG(identity.st_mode) and 0 < identity.st_size <= maximum, "CALIBRE_SSL_FILE_TYPE_BOUND"
        return path.read_bytes()

    def sha(raw):
        return hashlib.sha256(raw).hexdigest()

    def target(spec, root):
        assert root.is_dir() and not root.is_symlink(), "CALIBRE_SSL_ROOT"
        relative = pathlib.Path(spec["native"]["original"]["path"]).relative_to(spec["rootPath"])
        assert ".." not in relative.parts, "CALIBRE_SSL_TARGET_PATH"
        path = root / relative
        assert all(not p.is_symlink() for p in path.parents if p.is_relative_to(root)), "CALIBRE_SSL_TARGET_PARENT"
        return path

    def metadata(spec, manifest):
        native = spec["native"]
        # Schema1 private-CA descriptors originally omitted this tag. Remove
        # the read fallback when no release/recovery image uses that format.
        kind = spec.get("trustKind", TRUST_KINDS["private"])
        assert kind in set(TRUST_KINDS.values()), "PYTHON_SSL_TRUST_KIND"
        assert ("privateCa" in spec) == (kind == TRUST_KINDS["private"]), "PYTHON_SSL_TRUST_SHAPE"
        assert spec["schemaVersion"] == manifest["schemaVersion"] == native["schemaVersion"] == 1, "CALIBRE_SSL_SCHEMA"
        assert manifest["descriptor"] == native, "CALIBRE_SSL_DESCRIPTOR"
        file = manifest["file"]
        assert file["needed"] == native["original"]["needed"] and file["rpath"] == native["rpath"] and not file["soname"], "CALIBRE_SSL_ELF_METADATA"
        assert 0 < file["bytes"] <= native["limits"]["fileBytes"], "CALIBRE_SSL_FILE_BOUND"
        assert pathlib.Path(spec["proofDirectory"]).name == spec["proofDirectory"], "CALIBRE_SSL_PROOF_PATH"

    def package(spec, directory):
        manifest = json.loads(read(directory / "manifest.json", spec["native"]["limits"]["manifestBytes"]))
        metadata(spec, manifest)
        library = directory / "lib"
        assert library.is_dir() and not library.is_symlink() and {p.name for p in library.iterdir()} == {"_ssl.so"}, "CALIBRE_SSL_PACKAGE_SET"
        raw = read(library / "_ssl.so", spec["native"]["limits"]["fileBytes"])
        assert len(raw) == manifest["file"]["bytes"] and sha(raw) == manifest["file"]["sha256"], "CALIBRE_SSL_PACKAGE_HASH"
        return manifest

    def check_private_ca(spec, root):
        if spec.get("trustKind", TRUST_KINDS["private"]) == TRUST_KINDS["private"]:
            cert = root / pathlib.Path(spec["privateCa"]["path"]).relative_to(spec["rootPath"])
            assert sha(read(cert, 65536)) == spec["privateCa"]["sha256"], "CALIBRE_SSL_PRIVATE_CA_HASH"

    def installed(spec, root):
        proof = root / spec["proofDirectory"]
        assert proof.is_dir() and not proof.is_symlink() and stat.S_IMODE(proof.stat().st_mode) == 0o555, "CALIBRE_SSL_PROOF_ROOT"
        assert {p.name for p in proof.iterdir()} == {"guard.py", "spec.json", "manifest.json"}, "CALIBRE_SSL_PROOF_SET"
        raw = {name: read(proof / name, spec["native"]["limits"]["manifestBytes"]) for name in ["guard.py", "spec.json", "manifest.json"]}
        assert all(stat.S_IMODE((proof / name).stat().st_mode) == 0o444 for name in raw), "CALIBRE_SSL_PROOF_MODE"
        assert sha(raw["guard.py"]) == spec["guardSha256"], "CALIBRE_SSL_GUARD_HASH"
        assert json.loads(raw["spec.json"]) == spec, "CALIBRE_SSL_RUNTIME_SPEC"
        manifest = json.loads(raw["manifest.json"])
        metadata(spec, manifest)
        path = target(spec, root)
        raw = read(path, spec["native"]["limits"]["fileBytes"])
        assert len(raw) == manifest["file"]["bytes"] and sha(raw) == manifest["file"]["sha256"], "CALIBRE_SSL_INSTALLED_HASH"
        assert stat.S_IMODE(path.stat().st_mode) == spec["native"]["original"]["mode"], "CALIBRE_SSL_INSTALLED_MODE"
        check_private_ca(spec, root)
        return manifest

    def install(spec, directory, root, guard_file):
        # Image-local, non-retriable: validate every input before the first write.
        manifest = package(spec, directory)
        path = target(spec, root)
        original = spec["native"]["original"]
        raw = read(path, spec["native"]["limits"]["fileBytes"])
        assert len(raw) == original["bytes"] and sha(raw) == original["sha256"], "CALIBRE_SSL_ORIGINAL_HASH"
        identity = path.stat()
        assert stat.S_IMODE(identity.st_mode) == original["mode"], "CALIBRE_SSL_ORIGINAL_MODE"
        guard = read(guard_file, spec["native"]["limits"]["manifestBytes"])
        assert sha(guard) == spec["guardSha256"], "CALIBRE_SSL_GUARD_HASH"
        check_private_ca(spec, root)
        proof = root / spec["proofDirectory"]
        assert not proof.exists() and not proof.is_symlink(), "CALIBRE_SSL_EXISTING_PROOF"
        shutil.copyfile(directory / "lib/_ssl.so", path)
        assert (path.stat().st_uid, path.stat().st_gid, stat.S_IMODE(path.stat().st_mode)) == (identity.st_uid, identity.st_gid, original["mode"]), "CALIBRE_SSL_OWNER_MODE"
        proof.mkdir(mode=0o755)
        for name, raw in [("guard.py", guard), ("spec.json", canonical(spec)), ("manifest.json", canonical(manifest))]:
            (proof / name).write_bytes(raw)
            (proof / name).chmod(0o444)
        proof.chmod(0o555)
        installed(spec, root)

    def runtime(spec, root):
        import _ssl, ssl
        manifest = installed(spec, root)
        assert list(sys.version_info[:3]) == spec["native"]["pythonVersion"], "CALIBRE_SSL_RUNTIME_PYTHON"
        assert list(ssl.OPENSSL_VERSION_INFO) == spec["native"]["apiConstantChanges"]["_OPENSSL_API_VERSION"]["rebuilt"], "CALIBRE_SSL_RUNTIME_OPENSSL"
        assert pathlib.Path(importlib.util.find_spec("_ssl").origin) == target(spec, root), "CALIBRE_SSL_RUNTIME_SELECTION"
        members, constants = sorted(dir(_ssl)), {}
        for name in members:
            value = getattr(_ssl, name)
            if name.isupper() and (isinstance(value, (str, int, bool)) or value is None
                or isinstance(value, tuple) and all(isinstance(item, int) for item in value)):
                constants[name] = value
        api = dict(nativeModuleMembers=members, nativeModuleConstants=constants)
        api_sha = sha(canonical(api))
        assert api_sha == spec["native"]["apiSha256"], "CALIBRE_SSL_RUNTIME_API"
        original = json.loads(canonical(api))
        for name, change in spec["native"]["apiConstantChanges"].items():
            assert original["nativeModuleConstants"][name] == change["rebuilt"], "CALIBRE_SSL_DECLARED_API_CHANGE"
            original["nativeModuleConstants"][name] = change["original"]
        assert sha(canonical(original)) == spec["native"]["original"]["apiSha256"], "CALIBRE_SSL_OTHER_API_DRIFT"
        roots = []
        if spec.get("trustKind", TRUST_KINDS["private"]) == TRUST_KINDS["private"]:
            from calibre.utils.https import HTTPSConnection
            cert = root / pathlib.Path(spec["privateCa"]["path"]).relative_to(spec["rootPath"])
            connection = HTTPSConnection("localhost", cert_file=str(cert), disable_x509_strict_checking=True)
            try:
                roots = sorted(sha(value) for value in connection._context.get_ca_certs(binary_form=True))
                assert roots == spec["privateCa"]["derSha256"] and connection._context.verify_mode == ssl.CERT_REQUIRED and connection._context.check_hostname, "CALIBRE_SSL_PRIVATE_CA_CONTEXT"
            finally:
                connection.close()
        else:
            context = ssl.create_default_context()
            assert context.verify_mode == ssl.CERT_REQUIRED and context.check_hostname and context.get_ca_certs(), "SYSTEM_SSL_DEFAULT_TRUST"
        return dict(moduleSha256=manifest["file"]["sha256"], apiSha256=api_sha, privateCaDerSha256=roots)

    if __name__ == "__main__":
        spec_file, directory, root = map(pathlib.Path, sys.argv[1:])
        spec = json.loads(read(spec_file, 16384))
        install(spec, directory, root, pathlib.Path(__file__))
  '';
  sslRuntimeDescriptor = {
    schemaVersion = 1;
    native = sslDescriptor;
    rootPath = builtins.dirOf calibrePython;
    trustKind = sslTrustKinds.private;
    proofDirectory = ".hwc-native-ssl";
    guardSha256 = builtins.hashString "sha256" sslGuard.text;
    privateCa = {
      path = "${builtins.dirOf calibrePython}/resources/calibre-ebook-root-CA.crt";
      sha256 = "1030790c23900573ed4a8c4234113133bf6a0c13ccc7eb7d12ba3bdddcb9f2b3";
      derSha256 = [ "7a3613ab1b927acaa1c302d2055614ff0a2cc144b2575cd7e65c40b2a2c011c7" ];
    };
  };
  sslRuntimeSpec = pkgs.writeText "calibre-native-ssl-runtime.json" (builtins.toJSON sslRuntimeDescriptor);
  sslRuntimeProof = ''
    def native_ssl_proof():
        import hashlib, json, pathlib
        spec = json.loads(${builtins.toJSON (builtins.toJSON sslRuntimeDescriptor)})
        root = pathlib.Path(spec["rootPath"])
        guard = root / spec["proofDirectory"] / "guard.py"
        if not (guard.is_file() and not guard.is_symlink() and guard.stat().st_size <= 16384):
            raise AssertionError("CALIBRE_SSL_GUARD_BOUND")
        raw = guard.read_bytes()
        if hashlib.sha256(raw).hexdigest() != spec["guardSha256"]:
            raise AssertionError("CALIBRE_SSL_GUARD_HASH")
        namespace = {"__name__": "calibre_native_ssl"}
        exec(compile(raw, str(guard), "exec", optimize=0), namespace)
        return namespace["runtime"](spec, root)
  '';
  sslStaging = "/tmp/hwc-calibre-native-ssl";
  sslInputHash = builtins.hashString "sha256" (sslRuntimeSpec.text + sslGuard.text + toString sslPackage);
  # Temporary: both the Selkies and Books distro interpreter lack these
  # repairs. Keep their interpreter, extension ABI and installed packages.
  # Retire only when unmodified distro inputs pass the same consumer contract.
  distroPackageVersions = { python = "3.14.4-1ubuntu0.2"; openssl = "3.5.5-1ubuntu3.7"; };
  distroPythonVersion = map lib.toInt (lib.splitString "." (builtins.head (lib.splitString "-" distroPackageVersions.python)));
  distroOpenSslVersion = builtins.head (lib.splitString "-" distroPackageVersions.openssl);
  distroDebInputs = map (entry: let
    python = lib.hasPrefix "libpython" entry.name;
    version = if python then distroPackageVersions.python else distroPackageVersions.openssl;
    folder = if python then "p/python3.14" else "o/openssl";
    filename = "${entry.name}_${version}_amd64.deb";
  in entry // { inherit version filename;
    package = pkgs.fetchurl { inherit (entry) sha256; name = filename;
      url = "https://archive.ubuntu.com/ubuntu/pool/main/${folder}/${filename}"; };
  }) (builtins.fromJSON ''
[
  {
    "name": "libpython3.14-minimal",
    "sha256": "fac6f0728cf9490a7a698e6b343e4140283e92355b060193c04f5770a666df8a"
  },
  {
    "name": "libpython3.14-stdlib",
    "sha256": "3c267ef0f902f763c3615cbf28dd6fe91d2e4f603075d7f03db99f8d4eb66f46"
  },
  {
    "name": "libssl3t64",
    "sha256": "3ff73e121f6cd4f19e80ab4329dfd914108b3936c9db3708200203a9b245b34d"
  },
  {
    "name": "libpython3.14-dev",
    "sha256": "6f2e99c80311934d0a031bb12fe2faca684b05e5b6bb225fe9a07a5c05fdb3da"
  },
  {
    "name": "libssl-dev",
    "sha256": "d1cf6cafb141490b7020e392964b1f901835d60cb88c3a68ef0f95ef5e930de4"
  }
]
  '');
  # REPLACEABLE SDK/source inputs only; no package scripts run in an app image.
  distroSdk = pkgs.runCommand "calibre-system-python-sdk" { nativeBuildInputs = [ pkgs.dpkg ]; } ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (entry:
      ''test "$(dpkg-deb -f ${entry.package} Version)" = ${lib.escapeShellArg entry.version} && dpkg-deb -x ${entry.package} "$out"'') distroDebInputs}
  '';
  distroHttp = pkgs.pythonHttpFramingBackport.distroSources."ubuntu-${distroPackageVersions.python}";
  distroFacts = stdlibFacts // {
    pythonVersion = distroPythonVersion;
    compilerPythonVersion = calibrePythonVersion;
    runtimeRoot = "/usr/lib/python3.14";
    runtimeMode = 420;
    proofFile = ".hwc-system-python.json";
    commands = stdlibFacts.commands // { install = "install"; verify = "verify"; };
    limits = stdlibFacts.limits // { modules = 5; patches = 6; };
    modules = stdlibFacts.modules // {
      shutil = stdlibFacts.modules.shutil // {
        originalBytes = 60568; originalSha256 = "ab36f39f04e349020cdd13cf41b50905fc399150fb5e6a7cf73d69b22dd949cd";
        bytes = 61017; sha256 = "8d51075886a322a7f05da0387d1eccfe329c1e5c49dc0a3df50ca6caa11eef07";
      };
      tarfile = stdlibFacts.modules.tarfile // {
        originalBytes = 118582; originalSha256 = "c0db1a21e56ccf002147bffd10d97f452ad842820963ef793117f92a0cdaaad4";
        bytes = 118817; sha256 = "c6dc547f47e2d1861b8dbc547cff9a0bee2ed679f748f56e74c38a17d254f780";
      };
      tempfile = stdlibFacts.modules.tempfile // {
        originalBytes = 33009; originalSha256 = "acaf59a740e42efb9f7e612ef3a9aa5c8134250c5a450714eb4af659491c8805";
      };
      "http.client" = {
        file = "http/client.py";
        originalBytes = distroHttp.sourceBytes;
        bytes = distroHttp.sourceBytes + lib.foldl' (total: pair:
          total + builtins.stringLength (builtins.elemAt pair 1) - builtins.stringLength (builtins.elemAt pair 0)) 0 pkgs.pythonHttpFramingBackport.replacements;
        originalSha256 = distroHttp.sourceSha256;
        sha256 = distroHttp.patchedSha256;
        replacements = pkgs.pythonHttpFramingBackport.replacements;
        # Books' paired HTTP/urllib3 guard has already validated and patched
        # this member. Accept that exact postimage, never an unknown preimage.
        allowPatchedInput = true;
      };
    };
    patches = (builtins.fromJSON ''
[
  {
    "advisory": "CVE-2026-87910",
    "id": "gh-151558",
    "url": "https://github.com/python/cpython/commit/79c06bd5c6afa3c440d50faf7ee1b147c8832b4c.patch",
    "includes": [
      "Lib/tarfile.py"
    ],
    "hash": "sha256-tWIvD+nrCu57bwGJY/jHAtcNyAPjyKDzQvbuXuupxkI=",
    "raw": true
  },
  {
    "advisory": "CVE-2026-12345",
    "id": "gh-154307",
    "url": "https://github.com/python/cpython/commit/856c8119ea9d8f574dd56cf64afe19ee2e460c8b.patch",
    "includes": [
      "Lib/tempfile.py"
    ],
    "hash": "sha256-cC9y45P4dQHnnnjgjEJC5nssbdX+0n20PeP5mBvhjNE=",
    "raw": true
  }
]
    '') ++ stdlibFacts.patches;
  };
  distroSpec = pkgs.writeText "calibre-system-python-sources.json" (builtins.toJSON distroFacts);
  distroPatches = map (entry: if entry.raw or false then
    pkgs.runCommand "python-system-prerequisite.patch" { nativeBuildInputs = [ pkgs.patchutils ]; } ''
      filterdiff ${lib.concatMapStringsSep " " (file: "-i ${lib.escapeShellArg ("*/" + file)}") entry.includes} \
        ${pkgs.fetchurl { inherit (entry) url hash; }} > "$out"
      test -s "$out"
    ''
    else pkgs.fetchpatch { inherit (entry) url includes hash; }) distroFacts.patches;
  distroSources = pkgs.runCommand "calibre-system-python-sources" {} (''
    mkdir -p source/Lib source/original
    ${lib.concatMapStringsSep "\n" (entry: ''
      mkdir -p "source/Lib/$(dirname ${lib.escapeShellArg entry.file})" "source/original/$(dirname ${lib.escapeShellArg entry.file})"
      cp ${distroSdk}${distroFacts.runtimeRoot}/${entry.file} source/Lib/${entry.file}
      chmod u+w source/Lib/${entry.file}
      cp source/Lib/${entry.file} source/original/${entry.file}
    '') (builtins.attrValues distroFacts.modules)}
  '' + lib.concatMapStringsSep "\n" (patch:
    "${pkgs.patch}/bin/patch ${lib.escapeShellArgs distroFacts.patchFlags} -d source -i ${patch}") distroPatches + "\n" + ''
    ${pkgs.python314.interpreter} -I -B ${stdlibSourceGuard} ${distroFacts.commands.finish} ${distroSpec} source "$out"
  '');
  distroSslDescriptor = sslDescriptor // {
    pythonVersion = distroPythonVersion;
    opensslVersion = distroOpenSslVersion;
    sourceFiles = sslDescriptor.sourceFiles // {
      "Modules/_ssl.c" = "f41e23ca29c4667fb14aebd0d58499d7c83d0c0be7405d4de99897e72af70f06";
    };
    headers = {
      python = "eec0c50c4157985d62d12230b4eca5bda4054a81225f2448db1da723d274c025";
      openssl = "7acbe88993a8691183aff3277743d8090c6bbba24b6e218919cf8afdbde42de6";
    };
    # Ubuntu ships the static pyconfig.h in its development package even
    # though the running interpreter reports a shared build. Check the actual
    # SDK header; the native API and TLS fixture qualify this Linux module.
    abiMacros = sslDescriptor.abiMacros // { Py_ENABLE_SHARED = 0; };
    original = sslDescriptor.original // {
      path = "/usr/lib/python3.14/lib-dynload/_ssl.cpython-314-x86_64-linux-gnu.so";
      sha256 = "53789b72a5011867c45036d115ef10f452282751b8735691d1eaf22bf8fe5587";
      bytes = 236736;
      mode = 420; # Both Ubuntu image preimages are root-owned 0644.
      apiSha256 = distroSslDescriptor.apiSha256;
    };
    apiConstantChanges."_OPENSSL_API_VERSION" = let
      v = map lib.toInt (lib.splitString "." distroOpenSslVersion);
      value = [ (builtins.elemAt v 0) (builtins.elemAt v 1) 0 (builtins.elemAt v 2) 0 ];
    in { original = value; rebuilt = value; };
    apiSha256 = "792a3e6f59f937f376f7b4019e70a6849618bc0a1b887afaaa6104de30d79a9f";
    rpath = "";
  };
  distroSslSpec = pkgs.writeText "calibre-system-python-ssl.json" (builtins.toJSON distroSslDescriptor);
  distroSslPackage = mkPythonNativePackage {
    pname = "calibre-system-python-ssl";
    inherit (pythonNativeSdks.system) src pythonHeader;
    descriptor = distroSslDescriptor;
    spec = distroSslSpec;
    opensslHeader = "${distroSdk}/usr/include/openssl/opensslv.h";
    includeDirs = pythonNativeSdks.system.includeDirs ++ [ bluezSdkInclude ];
    linkArgs = map (name: "${distroSdk}/usr/lib/x86_64-linux-gnu/${name}") [ "libssl.so.3" "libcrypto.so.3" ];
    buildInputs = [];
  };
  distroSslRuntimeDescriptor = {
    schemaVersion = 1;
    native = distroSslDescriptor;
    rootPath = distroFacts.runtimeRoot;
    trustKind = sslTrustKinds.system;
    proofDirectory = ".hwc-native-ssl";
    guardSha256 = builtins.hashString "sha256" sslGuard.text;
  };
  distroSslRuntimeSpec = pkgs.writeText "calibre-system-python-ssl-runtime.json" (builtins.toJSON distroSslRuntimeDescriptor);
  distroStaging = "/tmp/hwc-system-python";
  distroInputHash = builtins.hashString "sha256"
    (distroSpec.text + stdlibSourceGuard.text + distroSslRuntimeSpec.text + sslGuard.text + toString distroSources + toString distroSslPackage + socketInputHash);
  distroRuntimeProof = ''
    import hashlib, importlib, importlib.metadata, json
    from pathlib import Path
    spec = json.loads(${builtins.toJSON (builtins.toJSON distroFacts)})
    for name, entry in spec["modules"].items():
        module = importlib.import_module(name)
        path = Path(spec["runtimeRoot"]) / entry["file"]
        assert module.__file__ == str(path) and hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"], "SYSTEM_PYTHON_RUNTIME_SELECTION"
    native = json.loads(${builtins.toJSON (builtins.toJSON distroSslRuntimeDescriptor)})
    guard = Path(native["rootPath"]) / native["proofDirectory"] / "guard.py"
    assert hashlib.sha256(guard.read_bytes()).hexdigest() == native["guardSha256"], "SYSTEM_PYTHON_SSL_GUARD"
    namespace = {"__name__": "system_python_native_ssl"}
    exec(compile(guard.read_bytes(), str(guard), "exec", optimize=0), namespace)
    namespace["runtime"](native, Path(native["rootPath"]))
    import http.client
    assert http.client._is_legal_chunk_size(b"a") and not http.client._is_legal_chunk_size(b"+a"), "SYSTEM_PYTHON_HTTP"
  '';
  distroRecipe = ''
    # System Python inputs ${distroInputHash}
    COPY system-python ${distroStaging}
    RUN /lsiopy/bin/python3 -I -B ${distroStaging}/guard.py ${distroFacts.commands.install} ${distroStaging}/spec.json ${distroStaging}/sources ${distroFacts.runtimeRoot}
    RUN /lsiopy/bin/python3 -I -B ${distroStaging}/guard.py ${distroFacts.commands.verify} ${distroStaging}/spec.json ${distroStaging}/sources ${distroFacts.runtimeRoot}
    RUN /lsiopy/bin/python3 -I -B ${distroStaging}/ssl/guard.py ${distroStaging}/ssl/spec.json ${distroStaging}/ssl ${distroSslRuntimeDescriptor.rootPath}
    RUN /lsiopy/bin/python3 -I -B -c ${lib.escapeShellArg ("exec(compile(" + builtins.toJSON distroRuntimeProof + ", '<system-python>', 'exec', optimize=0), {'__name__':'__main__'})")}
    RUN rm -rf ${distroStaging}
  '';
  distroContext = pkgs.runCommand "calibre-system-python-context" {} ''
    mkdir -p "$out/ssl"
    cp ${distroSpec} "$out/spec.json"
    cp ${stdlibSourceGuard} "$out/guard.py"
    cp -r ${distroSources} "$out/sources"
    cp ${distroSslRuntimeSpec} "$out/ssl/spec.json"
    cp ${sslGuard} "$out/ssl/guard.py"
    cp -r ${distroSslPackage}/lib ${distroSslPackage}/manifest.json "$out/ssl/"
    cp -r ${socketContext}/system "$out/socket"
  '';
  # Temporary: both selected Python runtimes truncate NUL host/port inputs.
  # Retire when unmodified vendor modules pass the NUL/API/normal/GUI/worker
  # contract. Ubuntu's binary builtin stays unchanged; checked site startup
  # selects the patched extension before configured application clients load.
  socketUpstreamCommit = "c53e59385eda89fade1531240ef6479341a55b53";
  socketModuleName = "_socket";
  socketPatchFacts = {
    url = "https://github.com/python/cpython/commit/${socketUpstreamCommit}.patch";
    sha256 = "0b278a9e01196f51053b8d1d6e8f45cb7fffb0af84fff9ae75aa7ee671b1924a";
  };
  socketRawPatch = pkgs.fetchurl socketPatchFacts;
  socketPatch = pkgs.runCommand "calibre-python-socket-3.14.patch" {
    nativeBuildInputs = [ pkgs.patchutils ];
  } ''
    filterdiff --include='*/Modules/socketmodule.c' ${socketRawPatch} > "$out"
    test -s "$out"
  '';
  socketFeatureMasks = { frozen = [ "HAVE_BLUETOOTH_BLUETOOTH_H" "HAVE_BLUETOOTH_H" ]; system = []; };
  socketCompatibility = pkgs.writeText "calibre-socket-compat.c" (''
    #define Py_BUILD_CORE_MODULE 1
    #include "Python.h"
  '' + lib.concatMapStringsSep "\n" (name: "#undef ${name}") socketFeatureMasks.frozen + ''

    #include "socketmodule.c"
  '');
  socketSourceFiles = {
    "Modules/socketmodule.h" = "54226a0bb807e9d19a39afec055bdffa96ebc3be37e367fb68b030da98a77a51";
    "Modules/addrinfo.h" = "14f80b91404b86a33df2f6abe94df3e0b28330a8e03f956241c68d9d30350fb4";
    "Modules/getaddrinfo.c" = "634f801d50c7affaded93f9e2ca54d358ccf4b23bf2ecf70951f9f8e856e215d";
    "Modules/getnameinfo.c" = "6e914f540265fd5191d3fcd2482a442ac41b7b69b9e998af8a0c7c565ac6cf79";
    "Modules/clinic/socketmodule.c.h" = "915c7428c9d1769c8eb1aec8ac74f49bab23a85f3956b78ffd2bc88b5edb7253";
  };
  socketDescriptors = lib.mapAttrs (variant: value: {
    schemaVersion = 1;
    inherit variant;
    moduleName = socketModuleName;
    advisory = "CVE-2026-116566";
    upstreamCommit = socketUpstreamCommit;
    # This is the upstream maintainer's still-open3.14 backport. The merged
    # main patch names a different function; require exact3.14 postimages.
    patch = socketPatchFacts;
    needed = [ "libc.so.6" ];
    rpath = "";
    disabledFeatureMacros = socketFeatureMasks.${variant};
    limits = { fileBytes = 262144; manifestBytes = 16384; sourceBytes = 524288; };
  } // value) {
    frozen = {
      pythonVersion = calibrePythonVersion;
      headers.python = sslDescriptor.headers.python;
      abiMacros = sslDescriptor.abiMacros;
      sourceFiles = socketSourceFiles // {
        "Modules/socketmodule.c" = "5ca0e0b0818ff76be79bdeadeb69341ee9ca3acf6af9a2afc7c8359f692e64fb";
        "Modules/socket-compat.c" = builtins.hashString "sha256" socketCompatibility.text;
      };
      original = {
        kind = "file";
        path = "${builtins.dirOf calibrePython}/lib/calibre-extensions/_socket.so";
        bytes = 112608; mode = 493;
        sha256 = "2ea435bc3abebfa8e7d757615a305d484cd5a51c2fd5d66745f2195bb7a93f30";
        apiSha256 = "2e8fe30ecc728f5adb445ac0074bb94953e3f80c088866e33447d865d2c4bb89";
      };
      apiMetadataAdditions = [];
    };
    system = {
      pythonVersion = distroPythonVersion;
      headers.python = distroSslDescriptor.headers.python;
      abiMacros = distroSslDescriptor.abiMacros;
      sourceFiles = socketSourceFiles // {
        "Modules/socketmodule.c" = "9f111d015a38070f6c35e3d5054cacfbe27071c3511467f7b19eadcdaed21e5f";
      };
      original = {
        kind = "builtin";
        path = "/usr/bin/python3.14";
        bytes = 7477160; mode = 493;
        sha256 = "52e0a13e60a981d8c4b6478be2ba5176f69da07948a056bf49cf6f077e30cb41";
        apiSha256 = "b2fba094e0d2f72136016dff946a34ec806f756bfc7430a43f0c22b03f67862f";
      };
      apiMetadataAdditions = [ "__file__" ];
    };
  };
  socketSpecs = lib.mapAttrs (variant: value:
    pkgs.writeText "calibre-${variant}-socket.json" (builtins.toJSON value)) socketDescriptors;
  socketSourceGuard = pkgs.writeText "calibre-native-socket-source-guard.py" (''
    import hashlib, json, pathlib, re, sys
    FEATURE_MASKS = ${builtins.toJSON socketFeatureMasks}
    MODULE_NAME = ${builtins.toJSON socketModuleName}
    if not __debug__:
        raise AssertionError("CALIBRE_SOCKET_OPTIMIZED_SOURCE_GUARD")
  '' + pythonNativeSourceChecks + ''
    def check(spec, root, python_header):
        assert spec["variant"] in FEATURE_MASKS and spec["moduleName"] == MODULE_NAME, "CALIBRE_SOCKET_VARIANT"
        assert len(spec["sourceFiles"]) in [6, 7], "CALIBRE_SOCKET_SOURCE_COUNT"
        assert spec["disabledFeatureMacros"] == FEATURE_MASKS[spec["variant"]], "CALIBRE_SOCKET_FEATURE_MASK"
        check_python_source(spec, root, python_header, "CALIBRE_SOCKET")

    if __name__ == "__main__":
        spec_file, root, python_header = map(pathlib.Path, sys.argv[1:])
        assert spec_file.stat().st_size <= 16384, "CALIBRE_SOCKET_SPEC_BOUND"
        check(json.loads(spec_file.read_text()), root, python_header)
        print("CALIBRE_SOCKET_SOURCE_FIXED")
  '');
  socketPackages = assert lib.assertMsg
    (pkgs.python314.version == lib.concatMapStringsSep "." toString socketDescriptors.frozen.pythonVersion)
    "Calibre socket requires its measured Python SDK version";
    lib.mapAttrs (variant: descriptor: mkPythonNativePackage {
    pname = "calibre-${variant}-socket";
    inherit (pythonNativeSdks.${variant}) src pythonHeader;
    inherit descriptor;
    spec = socketSpecs.${variant};
    inherit (descriptor) moduleName needed;
    patches = [ socketPatch ];
    sourcePreparation = lib.optionalString (variant == "frozen")
      "cp ${socketCompatibility} Modules/socket-compat.c";
    sourceCheck = "python3 -I -B ${socketSourceGuard} ${socketSpecs.${variant}} . ${pythonNativeSdks.${variant}.pythonHeader}";
    buildSource = if variant == "frozen" then "Modules/socket-compat.c" else "Modules/socketmodule.c";
    includeDirs = pythonNativeSdks.${variant}.includeDirs ++ [ bluezSdkInclude ];
    linkArgs = [];
    buildInputs = [];
  }) socketDescriptors;
  socketSourceManifest = pkgs.writeText "calibre-native-socket-sources.json" (builtins.toJSON {
    schemaVersion = 1;
    variants = socketDescriptors;
  });
  socketCommands = { install = "install"; installed = "installed"; runtime = "runtime"; startup = "startup"; };
  socketGlobalSite = "/usr/lib/python3/dist-packages";
  socketProofRoot = "${socketGlobalSite}/_hwc_native_socket";
  socketRuntimePaths = {
    frozen = {
      root = builtins.dirOf calibrePython;
      proof = "${builtins.dirOf calibrePython}/.hwc-native-socket";
      target = socketDescriptors.frozen.original.path;
      mode = socketDescriptors.frozen.original.mode;
      startup = [];
    };
    system = {
      root = "/";
      proof = socketProofRoot;
      target = "${socketProofRoot}/${socketModuleName}.so";
      mode = 292; # Immutable, root-owned DLL; dlopen does not need execute bits.
      startup = map (site: "${site}/00-hwc-native-socket.pth") [ socketGlobalSite
        "/lsiopy/lib/python${lib.concatMapStringsSep "." toString (lib.take 2 distroPythonVersion)}/site-packages" ];
    };
  };
  socketRuntimeLimits = { guardBytes = 65536; startupBytes = 8192; originalBytes = 16777216; };
  socketRuntimeGuard = pkgs.writeText "calibre-native-socket-guard.py" ''
    import hashlib, importlib.util, json, os, pathlib, stat, sys
    COMMANDS = ${builtins.toJSON socketCommands}
    PATHS = ${builtins.toJSON socketRuntimePaths}
    LIMITS = ${builtins.toJSON socketRuntimeLimits}
    MODULE = ${builtins.toJSON socketModuleName}
    ORIGINALS = ${builtins.toJSON (lib.mapAttrs (_: value: {
      inherit (value.original) kind path mode;
    }) socketDescriptors)}
    NATIVE_LIMITS = ${builtins.toJSON socketDescriptors.frozen.limits}

    def require(value, code):
        if not value:
            raise RuntimeError("CALIBRE_SOCKET_" + code)

    def canonical(value):
        return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()

    def sha(raw):
        return hashlib.sha256(raw).hexdigest()

    def read(path, maximum):
        identity = path.lstat()
        require(stat.S_ISREG(identity.st_mode) and 0 < identity.st_size <= maximum, "FILE_TYPE_BOUND")
        return path.read_bytes()

    def at(spec, root, absolute):
        require(root.is_dir() and not root.is_symlink(), "ROOT")
        relative = pathlib.Path(absolute).relative_to(spec["paths"]["root"])
        require(".." not in relative.parts, "PATH")
        path = root / relative
        require(all(not p.is_symlink() for p in path.parents if p.is_relative_to(root)), "PATH_PARENT")
        return path

    def validate(spec):
        require(type(spec["schemaVersion"]) is int and spec["schemaVersion"] == 1 and spec["variant"] in PATHS, "SPEC_SCHEMA")
        native = spec["native"]
        require(type(native["schemaVersion"]) is int and native["schemaVersion"] == 1 and native["variant"] == spec["variant"] and native["moduleName"] == MODULE, "SPEC_NATIVE")
        require(native["limits"] == NATIVE_LIMITS and all(native["original"][name] == value for name, value in ORIGINALS[spec["variant"]].items()), "SPEC_ORIGINAL")
        require(spec["paths"] == PATHS[spec["variant"]] and spec["limits"] == LIMITS, "SPEC_PATHS")
        require(type(spec["owner"]["uid"]) is int and type(spec["owner"]["gid"]) is int, "SPEC_OWNER")
        require(0 < native["original"]["bytes"] <= LIMITS["originalBytes"], "ORIGINAL_BOUND")
        require(len(canonical(spec)) <= native["limits"]["manifestBytes"], "SPEC_BOUND")

    def package(spec, directory):
        validate(spec)
        native = spec["native"]
        manifest = json.loads(read(directory / "manifest.json", native["limits"]["manifestBytes"]))
        require(manifest["schemaVersion"] == 1 and manifest["descriptor"] == native, "PACKAGE_METADATA")
        library = directory / "lib"
        require(library.is_dir() and not library.is_symlink() and {p.name for p in library.iterdir()} == {MODULE + ".so"}, "PACKAGE_SET")
        raw = read(library / (MODULE + ".so"), native["limits"]["fileBytes"])
        check_payload(native, manifest, raw)
        return manifest, raw

    def check_payload(native, manifest, raw):
        file = manifest["file"]
        require(manifest["schemaVersion"] == 1 and manifest["descriptor"] == native, "PAYLOAD_METADATA")
        require(file["needed"] == native["needed"] and file["rpath"] == native["rpath"] and not file["soname"], "PAYLOAD_ABI")
        require(len(raw) == file["bytes"] and sha(raw) == file["sha256"], "PAYLOAD_HASH")

    def owner_mode(path, owner, mode):
        identity = path.lstat()
        require((identity.st_uid, identity.st_gid, stat.S_IMODE(identity.st_mode)) == (owner["uid"], owner["gid"], mode), "OWNER_MODE")

    def original(spec, root):
        entry = spec["native"]["original"]
        path = at(spec, root, entry["path"])
        raw = read(path, LIMITS["originalBytes"])
        require(len(raw) == entry["bytes"] and sha(raw) == entry["sha256"], "ORIGINAL_HASH")
        owner_mode(path, spec["owner"], entry["mode"])
        return path

    def startup_line(spec):
        body = (
            "try:\n"
            " import hashlib,json,pathlib,stat\n"
            " root=pathlib.Path(" + repr(spec["paths"]["proof"]) + ")\n"
            " identity=(root/'guard.py').lstat()\n"
            " if not stat.S_ISREG(identity.st_mode) or not 0<identity.st_size<=" + str(LIMITS["guardBytes"]) + ": raise RuntimeError('CALIBRE_SOCKET_GUARD_BOUND')\n"
            " identity=(root/'spec.json').lstat()\n"
            " if not stat.S_ISREG(identity.st_mode) or not 0<identity.st_size<=" + str(spec["native"]["limits"]["manifestBytes"]) + ": raise RuntimeError('CALIBRE_SOCKET_SPEC_BOUND')\n"
            " raw=(root/'guard.py').read_bytes()\n"
            " data=(root/'spec.json').read_bytes()\n"
            " if len(raw)>" + str(LIMITS["guardBytes"]) + " or hashlib.sha256(raw).hexdigest()!=" + repr(spec["guardSha256"]) + ": raise RuntimeError('CALIBRE_SOCKET_GUARD_HASH')\n"
            " if len(data)>16384 or hashlib.sha256(data).hexdigest()!=" + repr(sha(canonical(spec))) + ": raise RuntimeError('CALIBRE_SOCKET_SPEC_HASH')\n"
            " namespace={'__name__':'hwc_native_socket_startup'}\n"
            " exec(compile(raw,str(root/'guard.py'),'exec',optimize=0),namespace)\n"
            " namespace[" + repr(COMMANDS["startup"]) + "](json.loads(data),pathlib.Path('/'))\n"
            "except BaseException:\n"
            " raise SystemExit('CALIBRE_SOCKET_STARTUP_FAILED') from None\n"
        )
        raw = ("import sys; exec(" + repr(body) + ")\n").encode()
        require(len(raw) <= LIMITS["startupBytes"] and len(raw.splitlines()) == 1, "STARTUP_LINE")
        return raw

    def installed(spec, root):
        validate(spec)
        proof = at(spec, root, spec["paths"]["proof"])
        require(proof.is_dir() and not proof.is_symlink(), "PROOF_ROOT")
        owner_mode(proof, spec["owner"], 0o555)
        expected = {"guard.py", "spec.json", "manifest.json"}
        if spec["variant"] == "system":
            expected.add(MODULE + ".so")
        require({p.name for p in proof.iterdir()} == expected, "PROOF_SET")
        for name in ["guard.py", "spec.json", "manifest.json"]:
            owner_mode(proof / name, spec["owner"], 0o444)
        require(sha(read(proof / "guard.py", LIMITS["guardBytes"])) == spec["guardSha256"], "GUARD_HASH")
        require(json.loads(read(proof / "spec.json", 16384)) == spec, "INSTALLED_SPEC")
        native = spec["native"]
        manifest = json.loads(read(proof / "manifest.json", native["limits"]["manifestBytes"]))
        target = at(spec, root, spec["paths"]["target"])
        check_payload(native, manifest, read(target, native["limits"]["fileBytes"]))
        owner_mode(target, spec["owner"], spec["paths"]["mode"])
        for absolute in spec["paths"]["startup"]:
            path = at(spec, root, absolute)
            owner_mode(path, spec["owner"], 0o444)
            require(read(path, LIMITS["startupBytes"]) == startup_line(spec), "STARTUP_FILE")
        if spec["variant"] == "system":
            original(spec, root)
        return manifest

    def install(spec, directory, root, guard_file):
        manifest, payload = package(spec, directory)
        source = original(spec, root)
        proof = at(spec, root, spec["paths"]["proof"])
        target = at(spec, root, spec["paths"]["target"])
        require(proof.parent.is_dir() and not proof.exists() and not proof.is_symlink(), "EXISTING_PROOF")
        ports = [at(spec, root, p) for p in spec["paths"]["startup"]]
        require(all(p.parent.is_dir() and not p.exists() and not p.is_symlink() for p in ports), "EXISTING_STARTUP")
        guard = read(guard_file, LIMITS["guardBytes"])
        require(sha(guard) == spec["guardSha256"], "INPUT_GUARD_HASH")
        if spec["variant"] == "frozen":
            require(target == source, "FROZEN_TARGET")
        else:
            require(target.parent == proof and not target.exists() and not target.is_symlink(), "SYSTEM_TARGET")
        line = startup_line(spec)
        # Image-local, non-retriable. All preimages and ports validate before
        # writes; hooks publish last. A failed layer is discarded, never retried.
        proof.mkdir(mode=0o755)
        target.write_bytes(payload)
        target.chmod(spec["paths"]["mode"])
        for name, raw in [("guard.py", guard), ("spec.json", canonical(spec)), ("manifest.json", canonical(manifest))]:
            (proof / name).write_bytes(raw)
            (proof / name).chmod(0o444)
        proof.chmod(0o555)
        for path in ports:
            path.write_bytes(line)
            path.chmod(0o444)
        installed(spec, root)

    def api(module, additions):
        members = sorted(dir(module))
        require(all(name in members for name in additions), "API_METADATA")
        for name in additions:
            members.remove(name)
        constants = {}
        for name in members:
            value = getattr(module, name)
            if name.isupper() and (isinstance(value, (str, int, bool)) or value is None or isinstance(value, tuple) and all(isinstance(item, int) for item in value)):
                constants[name] = value
        return sha(canonical(dict(members=members, constants=constants,
            socketMembers=sorted(dir(module.socket)), socketBasicSize=module.socket.__basicsize__)))

    def startup(spec, root):
        installed(spec, root)
        require(spec["variant"] == "system" and list(sys.version_info[:3]) == spec["native"]["pythonVersion"], "STARTUP_VERSION")
        require(pathlib.Path(sys.executable).resolve() == at(spec, root, spec["native"]["original"]["path"]), "STARTUP_EXECUTABLE")
        native = sys.modules.get(MODULE)
        if native is None:
            require(not any(name in sys.modules for name in ["socket", "ssl", "asyncio"]), "PRELOADED_CLIENT")
            require(len(sys._current_frames()) == 1, "STARTUP_THREADS")
            require(importlib.util.find_spec(MODULE).origin == "built-in", "BUILTIN_SELECTION")
            old = __import__(MODULE)
            require(api(old, []) == spec["native"]["original"]["apiSha256"], "BUILTIN_API")
            location = at(spec, root, spec["paths"]["target"])
            loader = importlib.util.spec_from_file_location(MODULE, str(location))
            native = importlib.util.module_from_spec(loader)
            sys.modules[MODULE] = native
            loader.loader.exec_module(native)
        # Repeated global/venv hooks validate this exact selection. They never
        # replace an already-loaded socket type or cached client a second time.
        require(getattr(native, "__file__", None) == str(at(spec, root, spec["paths"]["target"])), "STARTUP_SELECTION")
        require(api(native, spec["native"]["apiMetadataAdditions"]) == spec["native"]["original"]["apiSha256"], "STARTUP_API")
        if "socket" in sys.modules:
            require(issubclass(sys.modules["socket"].socket, native.socket), "CACHED_SOCKET_TYPE")
        try:
            native.getaddrinfo("127.0.0.1" + chr(0) + ".invalid", 80)
        except ValueError:
            pass
        else:
            require(False, "STARTUP_NUL_ACCEPTED")

    def runtime(spec, root):
        manifest = installed(spec, root)
        require(list(sys.version_info[:3]) == spec["native"]["pythonVersion"], "RUNTIME_VERSION")
        native = __import__(MODULE)
        require(importlib.util.find_spec(MODULE).origin == str(at(spec, root, spec["paths"]["target"])), "RUNTIME_SELECTION")
        fingerprint = api(native, spec["native"]["apiMetadataAdditions"])
        require(fingerprint == spec["native"]["original"]["apiSha256"], "RUNTIME_API")
        import socket
        hosts = ["127.0.0.1" + chr(0) + ".invalid", b"127.0.0.1\x00.invalid", "127.0.0.1" + chr(0), b"127.0.0.1\x00"]
        ports = ["80" + chr(0) + "x", b"80\x00x", "80" + chr(0), b"80\x00"]
        for factory in [native.getaddrinfo, socket.getaddrinfo]:
            for host, port in [(p, 80) for p in hosts] + [("127.0.0.1", p) for p in ports]:
                try:
                    factory(host, port, 0, socket.SOCK_STREAM, 0, socket.AI_NUMERICHOST | socket.AI_NUMERICSERV)
                except ValueError:
                    pass
                else:
                    require(False, "RUNTIME_NUL_ACCEPTED")
        for host, port in [("127.0.0.1", 80), ("::1", 80), ("127.0.0.1", None)]:
            require(socket.getaddrinfo(host, port, type=socket.SOCK_STREAM, flags=socket.AI_NUMERICHOST | socket.AI_NUMERICSERV), "NORMAL_RESOLVER")
        return dict(moduleSha256=manifest["file"]["sha256"], apiSha256=fingerprint, rejectedInputs=16, normalControls=3)

    if __name__ == "__main__":
        mode, spec_file, *arguments = sys.argv[1:]
        spec = json.loads(read(pathlib.Path(spec_file), 16384))
        require(mode in COMMANDS.values() and mode != COMMANDS["startup"], "COMMAND")
        if mode == COMMANDS["install"]:
            require(len(arguments) == 2, "INSTALL_ARGUMENTS")
            directory, root = map(pathlib.Path, arguments)
            install(spec, directory, root, pathlib.Path(__file__))
        else:
            require(len(arguments) == 1, "VERIFY_ARGUMENTS")
            root = pathlib.Path(arguments[0])
            result = installed(spec, root) if mode == COMMANDS["installed"] else runtime(spec, root)
            print(json.dumps(result, sort_keys=True))
  '';
  socketRuntimeDescriptors = lib.mapAttrs (variant: native: {
    schemaVersion = 1;
    inherit variant native;
    paths = socketRuntimePaths.${variant};
    owner = { uid = 0; gid = 0; };
    limits = socketRuntimeLimits;
    guardSha256 = builtins.hashString "sha256" socketRuntimeGuard.text;
  }) socketDescriptors;
  socketRuntimeSpecs = lib.mapAttrs (variant: value:
    pkgs.writeText "calibre-${variant}-socket-runtime.json" (builtins.toJSON value)) socketRuntimeDescriptors;
  socketInputHash = builtins.hashString "sha256" (socketRuntimeGuard.text
    + lib.concatMapStringsSep "\n" (variant: socketRuntimeSpecs.${variant}.text + toString socketPackages.${variant})
      (builtins.attrNames socketDescriptors));
  socketContext = pkgs.runCommand "calibre-native-socket-context" {} ''
    mkdir -p "$out"
    ${lib.concatMapStringsSep "\n" (variant: ''
      mkdir -p "$out/${variant}"
      cp ${socketRuntimeGuard} "$out/${variant}/guard.py"
      cp ${socketRuntimeSpecs.${variant}} "$out/${variant}/spec.json"
      cp -r ${socketPackages.${variant}}/lib ${socketPackages.${variant}}/manifest.json "$out/${variant}/"
    '') (builtins.attrNames socketDescriptors)}
  '';
  socketStaging = "/tmp/hwc-native-socket";
  socketRecipe = variant: let spec = socketRuntimeDescriptors.${variant}; in ''
    # Native socket inputs ${socketInputHash}
    COPY ${if variant == "frozen" then "native-socket" else "system-python/socket"} ${socketStaging}/${variant}
    RUN /lsiopy/bin/python3 -I -B ${socketStaging}/${variant}/guard.py ${socketCommands.install} ${socketStaging}/${variant}/spec.json ${socketStaging}/${variant} ${spec.paths.root}
    RUN /lsiopy/bin/python3 -I -B ${socketStaging}/${variant}/guard.py ${socketCommands.installed} ${socketStaging}/${variant}/spec.json ${spec.paths.root}
  '' + lib.optionalString (variant == "system") ''
    RUN /lsiopy/bin/python3 -I -B ${socketStaging}/${variant}/guard.py ${socketCommands.runtime} ${socketStaging}/${variant}/spec.json ${spec.paths.root}
  '';
  socketFrozenRuntimeProof = ''
    def native_socket_proof():
        import hashlib, json
        from pathlib import Path
        spec = json.loads(${builtins.toJSON (builtins.toJSON socketRuntimeDescriptors.frozen)})
        guard = Path(spec["paths"]["proof"]) / "guard.py"
        assert hashlib.sha256(guard.read_bytes()).hexdigest() == spec["guardSha256"], "CALIBRE_SOCKET_RUNTIME_GUARD"
        namespace = {"__name__": "calibre_socket_runtime"}
        exec(compile(guard.read_bytes(), str(guard), "exec", optimize=0), namespace)
        return namespace[${builtins.toJSON socketCommands.runtime}](spec, Path(spec["paths"]["root"]))
  '';
  distroFullRecipe = distroRecipe + socketRecipe "system" + "RUN rm -rf ${socketStaging}\n";
  # Upstream7.1 maintenance keeps RELEASE7.1.5; bind its exact revision
  # and complete post-patch source separately from the library version.
  # Temporary: vendor SQLite predates the qualified security fixes. Retire
  # when unmodified vendor libraries pass the same depth/API/features/data tests.
  sqliteFacts = builtins.fromJSON ''{"schemaVersion":1,"version":"3.54.1","sourceId":"2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76","source":"https://sqlite.org/2026/sqlite-src-3540100.zip","sourceSha256":"387e7f6cad4797b17848c07d453dc6606917bb356a6cfe5a3abafd38c240c71b","generatedSha256":"75a4760a7b9727a4c4c877aec92eacf39e52a8f2921ce00bd33be6d3a8e8e254","variants":{"system":{"path":"/usr/lib/x86_64-linux-gnu/libsqlite3.so.0.8.6","mode":420,"originalSha256":"4633a4be13fdf05cb0f859e04fb06077a1fe30a90e405721a23873bd1f3d88a8","originalBytes":1522152,"soname":"libsqlite3.so.0","options":["ALLOW_ROWID_IN_VIEW","ATOMIC_INTRINSICS=1","DEFAULT_AUTOVACUUM","DEFAULT_CACHE_SIZE=-2000","DEFAULT_FILE_FORMAT=4","DEFAULT_JOURNAL_SIZE_LIMIT=-1","DEFAULT_MMAP_SIZE=0","DEFAULT_PAGE_SIZE=4096","DEFAULT_PCACHE_INITSZ=20","DEFAULT_RECURSIVE_TRIGGERS","DEFAULT_SECTOR_SIZE=4096","DEFAULT_SYNCHRONOUS=2","DEFAULT_WAL_AUTOCHECKPOINT=1000","DEFAULT_WAL_SYNCHRONOUS=2","DEFAULT_WORKER_THREADS=0","DIRECT_OVERFLOW_READ","ENABLE_COLUMN_METADATA","ENABLE_DBPAGE_VTAB","ENABLE_DBSTAT_VTAB","ENABLE_FTS3","ENABLE_FTS3_PARENTHESIS","ENABLE_FTS4","ENABLE_FTS5","ENABLE_LOAD_EXTENSION","ENABLE_MATH_FUNCTIONS","ENABLE_PREUPDATE_HOOK","ENABLE_RTREE","ENABLE_SESSION","ENABLE_STMTVTAB","ENABLE_UNLOCK_NOTIFY","ENABLE_UPDATE_DELETE_LIMIT","HAVE_ISNAN","LIKE_DOESNT_MATCH_BLOBS","MALLOC_SOFT_LIMIT=1024","MAX_ATTACHED=10","MAX_COLUMN=2000","MAX_COMPOUND_SELECT=500","MAX_DEFAULT_PAGE_SIZE=32768","MAX_EXPR_DEPTH=1000","MAX_FUNCTION_ARG=127","MAX_LENGTH=1000000000","MAX_LIKE_PATTERN_LENGTH=50000","MAX_MMAP_SIZE=0x7fff0000","MAX_PAGE_COUNT=0xfffffffe","MAX_PAGE_SIZE=65536","MAX_SCHEMA_RETRY=25","MAX_SQL_LENGTH=1000000000","MAX_TRIGGER_DEPTH=1000","MAX_VARIABLE_NUMBER=250000","MAX_VDBE_OP=250000000","MAX_WORKER_THREADS=8","MUTEX_PTHREADS","SECURE_DELETE","SOUNDEX","SYSTEM_MALLOC","TEMP_STORE=1","THREADSAFE=1","USE_URI"],"publicSymbols":["sqlite3_aggregate_context","sqlite3_aggregate_count","sqlite3_auto_extension","sqlite3_autovacuum_pages","sqlite3_backup_finish","sqlite3_backup_init","sqlite3_backup_pagecount","sqlite3_backup_remaining","sqlite3_backup_step","sqlite3_bind_blob","sqlite3_bind_blob64","sqlite3_bind_double","sqlite3_bind_int","sqlite3_bind_int64","sqlite3_bind_null","sqlite3_bind_parameter_count","sqlite3_bind_parameter_index","sqlite3_bind_parameter_name","sqlite3_bind_pointer","sqlite3_bind_text","sqlite3_bind_text16","sqlite3_bind_text64","sqlite3_bind_value","sqlite3_bind_zeroblob","sqlite3_bind_zeroblob64","sqlite3_blob_bytes","sqlite3_blob_close","sqlite3_blob_open","sqlite3_blob_read","sqlite3_blob_reopen","sqlite3_blob_write","sqlite3_busy_handler","sqlite3_busy_timeout","sqlite3_cancel_auto_extension","sqlite3_changes","sqlite3_changes64","sqlite3_clear_bindings","sqlite3_close","sqlite3_close_v2","sqlite3_collation_needed","sqlite3_collation_needed16","sqlite3_column_blob","sqlite3_column_bytes","sqlite3_column_bytes16","sqlite3_column_count","sqlite3_column_database_name","sqlite3_column_database_name16","sqlite3_column_decltype","sqlite3_column_decltype16","sqlite3_column_double","sqlite3_column_int","sqlite3_column_int64","sqlite3_column_name","sqlite3_column_name16","sqlite3_column_origin_name","sqlite3_column_origin_name16","sqlite3_column_table_name","sqlite3_column_table_name16","sqlite3_column_text","sqlite3_column_text16","sqlite3_column_type","sqlite3_column_value","sqlite3_commit_hook","sqlite3_compileoption_get","sqlite3_compileoption_used","sqlite3_complete","sqlite3_complete16","sqlite3_config","sqlite3_context_db_handle","sqlite3_create_collation","sqlite3_create_collation16","sqlite3_create_collation_v2","sqlite3_create_filename","sqlite3_create_function","sqlite3_create_function16","sqlite3_create_function_v2","sqlite3_create_module","sqlite3_create_module_v2","sqlite3_create_window_function","sqlite3_data_count","sqlite3_data_directory","sqlite3_database_file_object","sqlite3_db_cacheflush","sqlite3_db_config","sqlite3_db_filename","sqlite3_db_handle","sqlite3_db_mutex","sqlite3_db_name","sqlite3_db_readonly","sqlite3_db_release_memory","sqlite3_db_status","sqlite3_declare_vtab","sqlite3_deserialize","sqlite3_drop_modules","sqlite3_enable_load_extension","sqlite3_enable_shared_cache","sqlite3_errcode","sqlite3_errmsg","sqlite3_errmsg16","sqlite3_error_offset","sqlite3_errstr","sqlite3_exec","sqlite3_expanded_sql","sqlite3_expired","sqlite3_extended_errcode","sqlite3_extended_result_codes","sqlite3_file_control","sqlite3_filename_database","sqlite3_filename_journal","sqlite3_filename_wal","sqlite3_finalize","sqlite3_free","sqlite3_free_filename","sqlite3_free_table","sqlite3_get_autocommit","sqlite3_get_auxdata","sqlite3_get_clientdata","sqlite3_get_table","sqlite3_global_recover","sqlite3_hard_heap_limit64","sqlite3_initialize","sqlite3_interrupt","sqlite3_is_interrupted","sqlite3_keyword_check","sqlite3_keyword_count","sqlite3_keyword_name","sqlite3_last_insert_rowid","sqlite3_libversion","sqlite3_libversion_number","sqlite3_limit","sqlite3_load_extension","sqlite3_log","sqlite3_malloc","sqlite3_malloc64","sqlite3_memory_alarm","sqlite3_memory_highwater","sqlite3_memory_used","sqlite3_mprintf","sqlite3_msize","sqlite3_mutex_alloc","sqlite3_mutex_enter","sqlite3_mutex_free","sqlite3_mutex_leave","sqlite3_mutex_try","sqlite3_next_stmt","sqlite3_open","sqlite3_open16","sqlite3_open_v2","sqlite3_os_end","sqlite3_os_init","sqlite3_overload_function","sqlite3_prepare","sqlite3_prepare16","sqlite3_prepare16_v2","sqlite3_prepare16_v3","sqlite3_prepare_v2","sqlite3_prepare_v3","sqlite3_preupdate_blobwrite","sqlite3_preupdate_count","sqlite3_preupdate_depth","sqlite3_preupdate_hook","sqlite3_preupdate_new","sqlite3_preupdate_old","sqlite3_profile","sqlite3_progress_handler","sqlite3_randomness","sqlite3_realloc","sqlite3_realloc64","sqlite3_release_memory","sqlite3_reset","sqlite3_reset_auto_extension","sqlite3_result_blob","sqlite3_result_blob64","sqlite3_result_double","sqlite3_result_error","sqlite3_result_error16","sqlite3_result_error_code","sqlite3_result_error_nomem","sqlite3_result_error_toobig","sqlite3_result_int","sqlite3_result_int64","sqlite3_result_null","sqlite3_result_pointer","sqlite3_result_subtype","sqlite3_result_text","sqlite3_result_text16","sqlite3_result_text16be","sqlite3_result_text16le","sqlite3_result_text64","sqlite3_result_value","sqlite3_result_zeroblob","sqlite3_result_zeroblob64","sqlite3_rollback_hook","sqlite3_rtree_geometry_callback","sqlite3_rtree_query_callback","sqlite3_serialize","sqlite3_set_authorizer","sqlite3_set_auxdata","sqlite3_set_clientdata","sqlite3_set_last_insert_rowid","sqlite3_shutdown","sqlite3_sleep","sqlite3_snprintf","sqlite3_soft_heap_limit","sqlite3_soft_heap_limit64","sqlite3_sourceid","sqlite3_sql","sqlite3_status","sqlite3_status64","sqlite3_step","sqlite3_stmt_busy","sqlite3_stmt_explain","sqlite3_stmt_isexplain","sqlite3_stmt_readonly","sqlite3_stmt_status","sqlite3_str_append","sqlite3_str_appendall","sqlite3_str_appendchar","sqlite3_str_appendf","sqlite3_str_errcode","sqlite3_str_finish","sqlite3_str_length","sqlite3_str_new","sqlite3_str_reset","sqlite3_str_value","sqlite3_str_vappendf","sqlite3_strglob","sqlite3_stricmp","sqlite3_strlike","sqlite3_strnicmp","sqlite3_system_errno","sqlite3_table_column_metadata","sqlite3_temp_directory","sqlite3_test_control","sqlite3_thread_cleanup","sqlite3_threadsafe","sqlite3_total_changes","sqlite3_total_changes64","sqlite3_trace","sqlite3_trace_v2","sqlite3_transfer_bindings","sqlite3_txn_state","sqlite3_unlock_notify","sqlite3_update_hook","sqlite3_uri_boolean","sqlite3_uri_int64","sqlite3_uri_key","sqlite3_uri_parameter","sqlite3_user_data","sqlite3_value_blob","sqlite3_value_bytes","sqlite3_value_bytes16","sqlite3_value_double","sqlite3_value_dup","sqlite3_value_encoding","sqlite3_value_free","sqlite3_value_frombind","sqlite3_value_int","sqlite3_value_int64","sqlite3_value_nochange","sqlite3_value_numeric_type","sqlite3_value_pointer","sqlite3_value_subtype","sqlite3_value_text","sqlite3_value_text16","sqlite3_value_text16be","sqlite3_value_text16le","sqlite3_value_type","sqlite3_version","sqlite3_vfs_find","sqlite3_vfs_register","sqlite3_vfs_unregister","sqlite3_vmprintf","sqlite3_vsnprintf","sqlite3_vtab_collation","sqlite3_vtab_config","sqlite3_vtab_distinct","sqlite3_vtab_in","sqlite3_vtab_in_first","sqlite3_vtab_in_next","sqlite3_vtab_nochange","sqlite3_vtab_on_conflict","sqlite3_vtab_rhs_value","sqlite3_wal_autocheckpoint","sqlite3_wal_checkpoint","sqlite3_wal_checkpoint_v2","sqlite3_wal_hook"]},"frozen":{"path":"/opt/calibre/lib/libsqlite3.so","mode":493,"originalSha256":"3f19a7b81f8c4e7503128f95e620581bd2ade0eea7cb148d5615a634cf1a9d88","originalBytes":1602096,"soname":"","options":["ATOMIC_INTRINSICS=1","DEFAULT_AUTOVACUUM","DEFAULT_CACHE_SIZE=-2000","DEFAULT_FILE_FORMAT=4","DEFAULT_JOURNAL_SIZE_LIMIT=-1","DEFAULT_MMAP_SIZE=0","DEFAULT_PAGE_SIZE=4096","DEFAULT_PCACHE_INITSZ=20","DEFAULT_RECURSIVE_TRIGGERS","DEFAULT_SECTOR_SIZE=4096","DEFAULT_SYNCHRONOUS=2","DEFAULT_WAL_AUTOCHECKPOINT=1000","DEFAULT_WAL_SYNCHRONOUS=2","DEFAULT_WORKER_THREADS=0","DIRECT_OVERFLOW_READ","ENABLE_CARRAY","ENABLE_COLUMN_METADATA","ENABLE_DBSTAT_VTAB","ENABLE_FTS3","ENABLE_FTS3_PARENTHESIS","ENABLE_FTS4","ENABLE_FTS5","ENABLE_GEOPOLY","ENABLE_MATH_FUNCTIONS","ENABLE_OFFSET_SQL_FUNC","ENABLE_PERCENTILE","ENABLE_PREUPDATE_HOOK","ENABLE_RTREE","ENABLE_SESSION","ENABLE_STAT4","ENABLE_UPDATE_DELETE_LIMIT","MALLOC_SOFT_LIMIT=1024","MAX_ATTACHED=10","MAX_COLUMN=2000","MAX_COMPOUND_SELECT=500","MAX_DEFAULT_PAGE_SIZE=8192","MAX_EXPR_DEPTH=1000","MAX_FUNCTION_ARG=1000","MAX_LENGTH=1000000000","MAX_LIKE_PATTERN_LENGTH=50000","MAX_MMAP_SIZE=0x7fff0000","MAX_PAGE_COUNT=0xfffffffe","MAX_PAGE_SIZE=65536","MAX_SQL_LENGTH=1000000000","MAX_TRIGGER_DEPTH=1000","MAX_VARIABLE_NUMBER=32766","MAX_VDBE_OP=250000000","MAX_WORKER_THREADS=8","MUTEX_PTHREADS","SYSTEM_MALLOC","TEMP_STORE=1","THREADSAFE=1"],"publicSymbols":["sqlite3_aggregate_context","sqlite3_aggregate_count","sqlite3_auto_extension","sqlite3_autovacuum_pages","sqlite3_backup_finish","sqlite3_backup_init","sqlite3_backup_pagecount","sqlite3_backup_remaining","sqlite3_backup_step","sqlite3_bind_blob","sqlite3_bind_blob64","sqlite3_bind_double","sqlite3_bind_int","sqlite3_bind_int64","sqlite3_bind_null","sqlite3_bind_parameter_count","sqlite3_bind_parameter_index","sqlite3_bind_parameter_name","sqlite3_bind_pointer","sqlite3_bind_text","sqlite3_bind_text16","sqlite3_bind_text64","sqlite3_bind_value","sqlite3_bind_zeroblob","sqlite3_bind_zeroblob64","sqlite3_blob_bytes","sqlite3_blob_close","sqlite3_blob_open","sqlite3_blob_read","sqlite3_blob_reopen","sqlite3_blob_write","sqlite3_busy_handler","sqlite3_busy_timeout","sqlite3_cancel_auto_extension","sqlite3_carray_bind","sqlite3_carray_bind_v2","sqlite3_changes","sqlite3_changes64","sqlite3_clear_bindings","sqlite3_close","sqlite3_close_v2","sqlite3_collation_needed","sqlite3_collation_needed16","sqlite3_column_blob","sqlite3_column_bytes","sqlite3_column_bytes16","sqlite3_column_count","sqlite3_column_database_name","sqlite3_column_database_name16","sqlite3_column_decltype","sqlite3_column_decltype16","sqlite3_column_double","sqlite3_column_int","sqlite3_column_int64","sqlite3_column_name","sqlite3_column_name16","sqlite3_column_origin_name","sqlite3_column_origin_name16","sqlite3_column_table_name","sqlite3_column_table_name16","sqlite3_column_text","sqlite3_column_text16","sqlite3_column_type","sqlite3_column_value","sqlite3_commit_hook","sqlite3_compileoption_get","sqlite3_compileoption_used","sqlite3_complete","sqlite3_complete16","sqlite3_config","sqlite3_context_db_handle","sqlite3_create_collation","sqlite3_create_collation16","sqlite3_create_collation_v2","sqlite3_create_filename","sqlite3_create_function","sqlite3_create_function16","sqlite3_create_function_v2","sqlite3_create_module","sqlite3_create_module_v2","sqlite3_create_window_function","sqlite3_data_count","sqlite3_data_directory","sqlite3_database_file_object","sqlite3_db_cacheflush","sqlite3_db_config","sqlite3_db_filename","sqlite3_db_handle","sqlite3_db_mutex","sqlite3_db_name","sqlite3_db_readonly","sqlite3_db_release_memory","sqlite3_db_status","sqlite3_db_status64","sqlite3_declare_vtab","sqlite3_deserialize","sqlite3_drop_modules","sqlite3_enable_load_extension","sqlite3_enable_shared_cache","sqlite3_errcode","sqlite3_errmsg","sqlite3_errmsg16","sqlite3_error_offset","sqlite3_errstr","sqlite3_exec","sqlite3_expanded_sql","sqlite3_expired","sqlite3_extended_errcode","sqlite3_extended_result_codes","sqlite3_file_control","sqlite3_filename_database","sqlite3_filename_journal","sqlite3_filename_wal","sqlite3_finalize","sqlite3_free","sqlite3_free_filename","sqlite3_free_table","sqlite3_get_autocommit","sqlite3_get_auxdata","sqlite3_get_clientdata","sqlite3_get_table","sqlite3_global_recover","sqlite3_hard_heap_limit64","sqlite3_initialize","sqlite3_interrupt","sqlite3_is_interrupted","sqlite3_keyword_check","sqlite3_keyword_count","sqlite3_keyword_name","sqlite3_last_insert_rowid","sqlite3_libversion","sqlite3_libversion_number","sqlite3_limit","sqlite3_load_extension","sqlite3_log","sqlite3_malloc","sqlite3_malloc64","sqlite3_memory_alarm","sqlite3_memory_highwater","sqlite3_memory_used","sqlite3_mprintf","sqlite3_msize","sqlite3_mutex_alloc","sqlite3_mutex_enter","sqlite3_mutex_free","sqlite3_mutex_leave","sqlite3_mutex_try","sqlite3_next_stmt","sqlite3_open","sqlite3_open16","sqlite3_open_v2","sqlite3_os_end","sqlite3_os_init","sqlite3_overload_function","sqlite3_prepare","sqlite3_prepare16","sqlite3_prepare16_v2","sqlite3_prepare16_v3","sqlite3_prepare_v2","sqlite3_prepare_v3","sqlite3_preupdate_blobwrite","sqlite3_preupdate_count","sqlite3_preupdate_depth","sqlite3_preupdate_hook","sqlite3_preupdate_new","sqlite3_preupdate_old","sqlite3_profile","sqlite3_progress_handler","sqlite3_randomness","sqlite3_realloc","sqlite3_realloc64","sqlite3_release_memory","sqlite3_reset","sqlite3_reset_auto_extension","sqlite3_result_blob","sqlite3_result_blob64","sqlite3_result_double","sqlite3_result_error","sqlite3_result_error16","sqlite3_result_error_code","sqlite3_result_error_nomem","sqlite3_result_error_toobig","sqlite3_result_int","sqlite3_result_int64","sqlite3_result_null","sqlite3_result_pointer","sqlite3_result_subtype","sqlite3_result_text","sqlite3_result_text16","sqlite3_result_text16be","sqlite3_result_text16le","sqlite3_result_text64","sqlite3_result_value","sqlite3_result_zeroblob","sqlite3_result_zeroblob64","sqlite3_rollback_hook","sqlite3_rtree_geometry_callback","sqlite3_rtree_query_callback","sqlite3_serialize","sqlite3_set_authorizer","sqlite3_set_auxdata","sqlite3_set_clientdata","sqlite3_set_errmsg","sqlite3_set_last_insert_rowid","sqlite3_setlk_timeout","sqlite3_shutdown","sqlite3_sleep","sqlite3_snprintf","sqlite3_soft_heap_limit","sqlite3_soft_heap_limit64","sqlite3_sourceid","sqlite3_sql","sqlite3_status","sqlite3_status64","sqlite3_step","sqlite3_stmt_busy","sqlite3_stmt_explain","sqlite3_stmt_isexplain","sqlite3_stmt_readonly","sqlite3_stmt_status","sqlite3_str_append","sqlite3_str_appendall","sqlite3_str_appendchar","sqlite3_str_appendf","sqlite3_str_errcode","sqlite3_str_finish","sqlite3_str_free","sqlite3_str_length","sqlite3_str_new","sqlite3_str_reset","sqlite3_str_truncate","sqlite3_str_value","sqlite3_str_vappendf","sqlite3_strglob","sqlite3_stricmp","sqlite3_strlike","sqlite3_strnicmp","sqlite3_system_errno","sqlite3_table_column_metadata","sqlite3_temp_directory","sqlite3_test_control","sqlite3_thread_cleanup","sqlite3_threadsafe","sqlite3_total_changes","sqlite3_total_changes64","sqlite3_trace","sqlite3_trace_v2","sqlite3_transfer_bindings","sqlite3_txn_state","sqlite3_update_hook","sqlite3_uri_boolean","sqlite3_uri_int64","sqlite3_uri_key","sqlite3_uri_parameter","sqlite3_user_data","sqlite3_value_blob","sqlite3_value_bytes","sqlite3_value_bytes16","sqlite3_value_double","sqlite3_value_dup","sqlite3_value_encoding","sqlite3_value_free","sqlite3_value_frombind","sqlite3_value_int","sqlite3_value_int64","sqlite3_value_nochange","sqlite3_value_numeric_type","sqlite3_value_pointer","sqlite3_value_subtype","sqlite3_value_text","sqlite3_value_text16","sqlite3_value_text16be","sqlite3_value_text16le","sqlite3_value_type","sqlite3_version","sqlite3_vfs_find","sqlite3_vfs_register","sqlite3_vfs_unregister","sqlite3_vmprintf","sqlite3_vsnprintf","sqlite3_vtab_collation","sqlite3_vtab_config","sqlite3_vtab_distinct","sqlite3_vtab_in","sqlite3_vtab_in_first","sqlite3_vtab_in_next","sqlite3_vtab_nochange","sqlite3_vtab_on_conflict","sqlite3_vtab_rhs_value","sqlite3_wal_autocheckpoint","sqlite3_wal_checkpoint","sqlite3_wal_checkpoint_v2","sqlite3_wal_hook"]}}}'';
  sqliteSpec = pkgs.writeText "calibre-sqlite-spec.json" (builtins.toJSON sqliteFacts);
  sqliteSource = pkgs.fetchurl { url = sqliteFacts.source; sha256 = sqliteFacts.sourceSha256; };
  sqliteGenerated = pkgs.runCommand "calibre-sqlite-update-limit-source" {
    nativeBuildInputs = [ pkgs.unzip pkgs.tcl pkgs.gnumake pkgs.stdenv.cc ];
  } ''
    unzip -q ${sqliteSource} -d source
    cd source/sqlite-src-3540100
    mkdir generated
    cd generated
    ../configure --disable-readline --disable-tcl --with-tclsh=${pkgs.tcl}/bin/tclsh --enable-update-limit
    make -j1 sqlite3.c
    echo '${sqliteFacts.generatedSha256}  sqlite3.c' | sha256sum -c -
    cp sqlite3.c "$out"
  '';
  sqlitePackages = lib.mapAttrs (variant: descriptor: pkgs.stdenv.mkDerivation {
    pname = "calibre-sqlite-${variant}";
    version = sqliteFacts.version;
    dontUnpack = true;
    dontConfigure = true;
    nativeBuildInputs = [ pkgs.python3 pkgs.patchelf pkgs.binutils ];
    NIX_DONT_SET_RPATH_x86_64_unknown_linux_gnu = "1";
    buildPhase = ''
      $CC -shared -fPIC -O2 -DNDEBUG -fno-strict-aliasing \
        ${lib.escapeShellArgs (map (value: "-DSQLITE_" + value)
          (builtins.filter (value: value != "MUTEX_PTHREADS" && value != "ATOMIC_INTRINSICS=1") descriptor.options))} \
        -x c ${sqliteGenerated} -x none -Wl,--as-needed -pthread -ldl -lm \
        ${lib.optionalString (descriptor.soname != "") "-Wl,-soname,${descriptor.soname}"} -o libsqlite3.so
    '';
    installPhase = ''
      mkdir -p "$out/lib"
      install -m ${if descriptor.mode == 493 then "755" else "644"} libsqlite3.so "$out/lib/libsqlite3.so"
    '';
    postFixup = ''
      python3 -I -B - ${sqliteSpec} ${variant} "$out" <<'PYSQL'
      import ctypes, hashlib, json, pathlib, re, subprocess, sys
      spec_file, variant, output = sys.argv[1:]
      spec = json.loads(pathlib.Path(spec_file).read_text())
      expected = spec['variants'][variant]
      path = pathlib.Path(output) / 'lib/libsqlite3.so'
      def elf(flag):
          return subprocess.check_output(['patchelf', flag, str(path)], text=True).strip()
      assert sorted(elf('--print-needed').splitlines()) == ['libc.so.6', 'libm.so.6'], 'SQLITE_DEPENDENCIES'
      assert not elf('--print-rpath') and elf('--print-soname') == expected['soname'], 'SQLITE_ELF'
      raw = path.read_bytes()
      assert len(raw) <= 4194304 and b'/nix/store/' not in raw, 'SQLITE_PORTABLE_BOUND'
      library = ctypes.CDLL(str(path))
      library.sqlite3_libversion.restype = library.sqlite3_sourceid.restype = ctypes.c_char_p
      assert library.sqlite3_libversion().decode() == spec['version'], 'SQLITE_VERSION'
      assert library.sqlite3_sourceid().decode() == spec['sourceId'], 'SQLITE_SOURCE_ID'
      library.sqlite3_compileoption_get.restype = ctypes.c_char_p
      options = []
      for i in range(128):
          value = library.sqlite3_compileoption_get(i)
          if value is None:
              break
          options.append(value.decode())
      else:
          raise AssertionError('SQLITE_OPTIONS_BOUND')
      assert set(expected['options']) <= set(options), 'SQLITE_OPTIONS_LOST'
      symbols = subprocess.check_output(['readelf', '--dyn-syms', '-W', str(path)], text=True)
      exported = {line.split()[-1].split('@')[0] for line in symbols.splitlines() if ' GLOBAL ' in line and ' UND ' not in line}
      assert set(expected['publicSymbols']) <= exported, 'SQLITE_PUBLIC_API_LOST'
      manifest = dict(schemaVersion=1, variant=variant, spec=spec, file=dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest()))
      (pathlib.Path(output) / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True, separators=(',', ':')))
      PYSQL
    '';
  }) sqliteFacts.variants;
  sqliteGuard = pkgs.writeText "calibre-sqlite-guard.py" ''
    import hashlib, json, os, pathlib, stat, sys
    def require(value, code):
        if not value:
            raise RuntimeError('SQLITE_' + code)
    def read(path, maximum):
        info = path.lstat()
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= maximum, 'FILE_TYPE_BOUND')
        return path.read_bytes()
    def sha(raw):
        return hashlib.sha256(raw).hexdigest()
    def prepare(directory, root):
        spec = json.loads(read(directory / 'spec.json', 65536))
        require(spec['schemaVersion'] == 1 and set(spec['variants']) == {'system', 'frozen'}, 'SCHEMA')
        prepared = []
        for variant, expected in spec['variants'].items():
            payload = read(directory / (variant + '.so'), 4194304)
            manifest = json.loads(read(directory / (variant + '.json'), 65536))
            require(manifest['schemaVersion'] == 1 and manifest['variant'] == variant and manifest['spec'] == spec, 'MANIFEST')
            require(manifest['file'] == dict(bytes=len(payload), sha256=sha(payload)), 'PAYLOAD')
            relative = pathlib.Path(expected['path']).relative_to('/')
            require('..' not in relative.parts, 'PATH')
            target = root / relative
            require(all(not p.is_symlink() for p in target.parents if p.is_relative_to(root)), 'PARENT')
            current = read(target, 4194304)
            require(stat.S_IMODE(target.stat().st_mode) == expected['mode'], 'MODE')
            # Books copies the already-qualified frozen donor library. Accept
            # only the exact old file or this exact immutable payload.
            require((len(current) == expected['originalBytes'] and sha(current) == expected['originalSha256']) or current == payload, 'PREIMAGE')
            prepared.append((target, payload, expected['mode']))
        return prepared
    def install(directory, root):
        prepared = prepare(directory, root)
        # Non-retriable image-layer effect. Validate the complete group first;
        # discard a failed layer instead of replaying it against serving files.
        for target, payload, mode in prepared:
            before = target.stat()
            target.write_bytes(payload)
            require((target.stat().st_uid, target.stat().st_gid, stat.S_IMODE(target.stat().st_mode)) == (before.st_uid, before.st_gid, mode), 'OWNER_MODE')
        verify(directory, root)
    def verify(directory, root):
        for target, payload, _ in prepare(directory, root):
            require(read(target, 4194304) == payload, 'INSTALLED')
    if __name__ == '__main__':
        mode, directory, root = sys.argv[1:]
        require(not sys.flags.optimize, 'OPTIMIZED_INSTALLER')
        require(mode in {'install', 'verify'}, 'COMMAND')
        (install if mode == 'install' else verify)(pathlib.Path(directory), pathlib.Path(root))
  '';
  sqliteContext = pkgs.runCommand "calibre-sqlite-context" {} ''
    mkdir -p "$out"
    cp ${sqliteSpec} "$out/spec.json"
    cp ${sqliteGuard} "$out/guard.py"
    ${lib.concatMapStringsSep "\n" (variant: ''
      cp ${sqlitePackages.${variant}}/lib/libsqlite3.so "$out/${variant}.so"
      cp ${sqlitePackages.${variant}}/manifest.json "$out/${variant}.json"
    '') (builtins.attrNames sqliteFacts.variants)}
  '';
  sqliteRuntimeProof = ''
    import sqlite3
    assert sqlite3.sqlite_version == ${builtins.toJSON sqliteFacts.version}, 'SQLITE_RUNTIME_VERSION'
    sqlite_factories = [(sqlite3.connect, sqlite3.Error, sqlite3.SQLITE_LIMIT_EXPR_DEPTH)]
    import importlib.util
    if importlib.util.find_spec('apsw') is not None:
        import apsw
        from calibre.db.backend import Connection
        sqlite_factories.extend([(apsw.Connection, apsw.Error, apsw.SQLITE_LIMIT_EXPR_DEPTH),
                                 (Connection, apsw.Error, apsw.SQLITE_LIMIT_EXPR_DEPTH)])
    for factory, error_type, limit in sqlite_factories:
        connection = factory(':memory:')
        try:
            setter = connection.setlimit if hasattr(connection, 'setlimit') else connection.limit
            setter(limit, 10)
            assert list(connection.execute('SELECT 1 COLLATE BINARY')) == [(1,)]
            try:
                list(connection.execute('SELECT 1' + ' COLLATE BINARY' * 20))
            except error_type:
                pass
            else:
                raise AssertionError('SQLITE_DEPTH_LIMIT')
            assert list(connection.execute('PRAGMA integrity_check')) == [('ok',)]
        finally:
            connection.close()
  '';
  sqliteRecipe = ''
    # SQLite inputs ${builtins.hashString "sha256" (sqliteSpec.text + sqliteGuard.text + toString sqliteContext)}
    COPY sqlite /tmp/hwc-sqlite
    RUN /lsiopy/bin/python3 -I -B /tmp/hwc-sqlite/guard.py install /tmp/hwc-sqlite /
    RUN /lsiopy/bin/python3 -I -B /tmp/hwc-sqlite/guard.py verify /tmp/hwc-sqlite /
    RUN /lsiopy/bin/python3 -I -B -c ${lib.escapeShellArg ("exec(compile(" + builtins.toJSON sqliteRuntimeProof + ", '<sqlite-runtime>', 'exec', optimize=0), {'__name__':'__main__'})")}
    RUN rm -rf /tmp/hwc-sqlite
  '';
  nativeSourceFacts = builtins.fromJSON ''
{
  "schemaVersion": 1,
  "sourceRevision": "f9db090b14c255a8f1c5f8f41a4c92b723228763",
  "sourceSha256": {
    "libavcodec/adxdec.c": "801f06624465f5e5f08e4582bc70dd925d767f50a8d0a530edb1510d78208006",
    "libavcodec/cfhd.c": "0588d773b1c4e8fa2427bb6737e8317a9c76427dc21587596a918e5cb99b484d",
    "libavcodec/dvbsub_parser.c": "71e716bc56433b8a46c1d5c8a1a5fb454731b3fea7b7e95b7d4a5cc64d37d073",
    "libavcodec/lcldec.c": "8974c46459aa97eeb68f14cd6d371e0d5032790aa5acce71900e6a5e267c1544",
    "libavcodec/mace.c": "b982ff4276da9a87f19c334e4f92f5317f4ef4bd758682deb335ed30a0be050f",
    "libavcodec/rscc.c": "774382c170ff4603590120b1dbd9190ac48f446a521ef34e5870c6bbe3d104b0",
    "libavcodec/screenpresso.c": "882d6e383c4ccf44af608e0aca385e038c36762b5142268e942388ee3248833e",
    "libavcodec/tdsc.c": "59455f38dca7f007f2abef4493463880b3311aeb0a3ce78568e11af99b402a45",
    "libavcodec/tiff.c": "d71d08c601fe824970515c640cc72c39e497297828c8f8d183e8e4801e4438b3",
    "libavfilter/avfilter.c": "dd869e2e7c85037d07458da1dcb3ff95db3b97d9c0442a72df3608202332ed2d",
    "libavfilter/vf_floodfill.c": "1a1dfb0a028421a843fb672ba40e9e66e5b25c0ae7c1bd8149b2f90ad7029fca",
    "libavfilter/vf_hqdn3d.c": "02664152f7a9679c989185dfa66ac27484a3bb14850a8026a5313f256c989831",
    "libavfilter/vf_hqdn3d.h": "15de9174517591c41d2df3874376cd7271c43748745f4437e9cb7b9209dbd4b9",
    "libavfilter/vf_swaprect.c": "9d5875d821d4bf670094ec09d91f8b2ec67dbcb7556e17df22a4e75ad09def45",
    "libavformat/hls.c": "a297662d8e83c1067b905fb198af7c47bacbb20d184195da52335d04e4fc13d7",
    "libavformat/isom.h": "cb23c58f760cc13c66b2fb3bced1478886133eb46dc8bc4fd73ebc1141a5b8aa",
    "libavformat/mov.c": "bed4eb73bba5000e5b8a86bb3f9d32568738b3e5d84581ec6d4ccc94a22631a4",
    "libavformat/mpeg.c": "75a8c8b1c5642b313cebae32621a85e443eb8920e08836da43c24221d5c57659",
    "libavformat/rtpdec_asf.c": "b4748d01fbe4971e7273519e6b5fbccea9f21aa9f2a9f48a5920ce1773e1a707",
    "libavformat/rtsp.c": "204cff07d490b0422c8ed4676e8e1997c5b36d052e4a410a265b3916ee085bc5",
    "libavformat/spdifenc.c": "7a6d6eba8a3d26570114fd17bd3503f339520c5a3db6164c98f6ead38f514294",
    "libavformat/ty.c": "2b89305396b5be7bff698068356c7a0c37799f177c4c99e79645bc30b9f66338",
    "libavutil/encryption_info.c": "012a2b4d31c2f5311ea97e16b19c77ecc2c25d44f712bf5c69f8b82334ca7075",
    "libavutil/encryption_info.h": "782fcd91eee6cce50eb6336d6311c4c113a38f1d8f21e6cc1eb616cb1cac653b",
    "libavutil/hdr_dynamic_metadata.c": "70876a30e7ac083375382ea48df91ff1c0e5590f13a8957ffbb058139cba417b",
    "libavutil/tests/encryption_info.c": "336c641861b4b735cbbf1dbb3bcdea8a90db6e43d19107d43eb0170d2f80de67",
    "libavformat/avformat.h": "352ccf1aa9f92ebdf05a3d7d7d9493b9c9371e6b8320984341e1b20785e6a377",
    "libavformat/mux_utils.c": "902aeff13cb7c922d697e431bc0a28ec677b3514b2354c960bfad11e478482bf"
  }
}
  '';
  # The Nix Chromium extension is retained. Its historical patch matched7.1
  # only with fuzz2; adapt context and check the exact same function bytes.
  # Retire when the Nix patch applies to this source with --fuzz=0.
  nativeNixPatchContext = builtins.fromJSON ''
[
  [
    "@@ -1128,6 +1128,10 @@\n  */\n int64_t    av_stream_get_end_pts(const AVStream *st);\n \n+// Chromium: We use the internal field first_dts vvv\n+int64_t    av_stream_get_first_dts(const AVStream *st);\n+// Chromium: We use the internal field first_dts ^^^\n+\n #define AV_PROGRAM_RUNNING 1\n \n /**\n",
    "@@ -1202,6 +1202,10 @@\n \n struct AVCodecParserContext *av_stream_get_parser(const AVStream *s);\n \n+// Chromium: We use the internal field first_dts vvv\n+int64_t    av_stream_get_first_dts(const AVStream *st);\n+// Chromium: We use the internal field first_dts ^^^\n+\n #define AV_PROGRAM_RUNNING 1\n \n /**\n"
  ],
  [
    "@@ -37,6 +37,13 @@\n         return AV_NOPTS_VALUE;\n }\n \n+// Chromium: We use the internal field first_dts vvv\n+int64_t av_stream_get_first_dts(const AVStream *st)\n+{\n+  return cffstream(st)->first_dts;\n+}\n+// Chromium: We use the internal field first_dts ^^^\n+\n int avformat_query_codec(const AVOutputFormat *ofmt, enum AVCodecID codec_id,\n                          int std_compliance)\n {\n",
    "@@ -29,6 +29,13 @@\n #include \"avio.h\"\n #include \"internal.h\"\n #include \"mux.h\"\n+\n+// Chromium: We use the internal field first_dts vvv\n+int64_t av_stream_get_first_dts(const AVStream *st)\n+{\n+  return cffstream(st)->first_dts;\n+}\n+// Chromium: We use the internal field first_dts ^^^\n \n int avformat_query_codec(const AVOutputFormat *ofmt, enum AVCodecID codec_id,\n                          int std_compliance)\n"
  ]
]
  '';
  nativeSecurity = helpers.selectFfmpegSecurityBackports {
    advisories = [ "CVE-2026-107676" "CVE-2026-107678" "CVE-2026-107695" "CVE-2026-107696" "CVE-2026-107697" "CVE-2026-64830" "CVE-2026-64833" "CVE-2026-64834" "CVE-2026-64835" "CVE-2026-65703" "CVE-2026-65704" "CVE-2026-65705" "CVE-2026-65706" "CVE-2026-66036" "CVE-2026-66038" "CVE-2026-66039" "CVE-2026-70628" "CVE-2026-70629" "CVE-2026-70630" "CVE-2026-70631" "CVE-2026-70632" ];
    # Adapt branch context only; preserve all upstream security additions.
    contextEdits = builtins.fromJSON ''
{
  "eb9cef3ef1f6adac1e701e3f5f06739a0fcb0c97": [
    [
      "@@ -2243,6 +2244,11 @@ redirect:\n     if (reply->status_code >=300 && reply->status_code < 400 && s->iformat) {\n         int ret;\n \n+        if (redirects++ >= 8 /* MAX_RTSP_REDIRECTS */) {\n+            av_log(s, AV_LOG_ERROR, \"Too many RTSP redirects\\n\");\n+            err = AVERROR(EIO);\n+            goto fail2;\n+        }\n         if (!rtsp_url_same_origin(s->url, reply->location)) {\n             memset(rt->auth, 0, sizeof(rt->auth));\n             memset(&rt->auth_state, 0, sizeof(rt->auth_state));\n",
      "@@ -2243,6 +2244,11 @@ redirect:\n     if (reply->status_code >=300 && reply->status_code < 400 && s->iformat) {\n+        if (redirects++ >= 8 /* MAX_RTSP_REDIRECTS */) {\n+            av_log(s, AV_LOG_ERROR, \"Too many RTSP redirects\\n\");\n+            err = AVERROR(EIO);\n+            goto fail2;\n+        }\n         char *new_url = av_strdup(reply->location);\n         if (!new_url) {\n             err = AVERROR(ENOMEM);\n             goto fail2;\n         }\n"
    ]
  ],
  "62294b6a8ad2370e1435bb9985ebe6b53be14c2b": [
    [
      "@@ -1078,7 +1078,8 @@ int ff_filter_frame(AVFilterLink *link, AVFrame *frame)\n             strcmp(link->dst->filter->name, \"idet\") &&\n             strcmp(link->dst->filter->name, \"null\") &&\n             strcmp(link->dst->filter->name, \"scale\") &&\n-            strcmp(link->dst->filter->name, \"libplacebo\")) {\n+            strcmp(link->dst->filter->name, \"libplacebo\") &&\n+            strcmp(link->dst->filter->name, \"hqdn3d\")) {\n             av_assert1(frame->format        == link->format);\n             av_assert1(frame->width         == link->w);\n             av_assert1(frame->height        == link->h);\n",
      "@@ -1078,6 +1078,7 @@ int ff_filter_frame(AVFilterLink *link, AVFrame *frame)\n             strcmp(link->dst->filter->name, \"idet\") &&\n             strcmp(link->dst->filter->name, \"null\") &&\n-            strcmp(link->dst->filter->name, \"scale\")) {\n+            strcmp(link->dst->filter->name, \"scale\") &&\n+            strcmp(link->dst->filter->name, \"hqdn3d\")) {\n             av_assert1(frame->format        == link->format);\n             av_assert1(frame->width         == link->w);\n             av_assert1(frame->height        == link->h);\n"
    ]
  ]
}
  '';
  };
  nativeSourceSpec = pkgs.writeText "calibre-native-source.json" (builtins.toJSON nativeSourceFacts);
  nativeSourceGuard = pkgs.writeText "calibre-native-source-guard.py" ''
    import hashlib, json, pathlib, re, sys
    if sys.flags.optimize:
        raise RuntimeError('CALIBRE_NATIVE_SOURCE_OPTIMIZED')
    spec_file, root = map(pathlib.Path, sys.argv[1:])
    assert spec_file.stat().st_size <= 65536, 'CALIBRE_NATIVE_SOURCE_SPEC_BOUND'
    spec = json.loads(spec_file.read_text())
    assert spec['schemaVersion'] == 1, 'CALIBRE_NATIVE_SOURCE_SCHEMA'
    assert re.fullmatch('[0-9a-f]{40}', spec['sourceRevision']), 'CALIBRE_NATIVE_SOURCE_REVISION'
    files = spec['sourceSha256']
    assert 1 <= len(files) <= 64, 'CALIBRE_NATIVE_SOURCE_COUNT'
    used = 0
    for name, expected in files.items():
        relative = pathlib.Path(name)
        assert not relative.is_absolute() and '..' not in relative.parts, 'CALIBRE_NATIVE_SOURCE_PATH'
        path = root / relative
        assert path.is_file() and not path.is_symlink(), 'CALIBRE_NATIVE_SOURCE_FILE'
        assert path.stat().st_size <= 2097152, 'CALIBRE_NATIVE_SOURCE_FILE_BOUND'
        raw = path.read_bytes()
        used += len(raw)
        assert used <= 16777216, 'CALIBRE_NATIVE_SOURCE_GROUP_BOUND'
        assert hashlib.sha256(raw).hexdigest() == expected, 'CALIBRE_NATIVE_SOURCE_DRIFT'
    print('CALIBRE_NATIVE_SOURCE_FIXED', len(files))
  '';
  # Temporary: the vendor FFmpeg 7.1.2 predates same-ABI security fixes.
  # Retire when the unmodified vendor eight-library group passes this contract.
  nativeFfmpeg = (pkgs.ffmpeg_7.override {
    withHeadlessDeps = false; withSmallDeps = false; withFullDeps = false;
    withBzlib = true; withIconv = true; withZlib = true; withNetwork = true;
    withVersion3 = false;
    buildAvcodec = true; buildAvdevice = true; buildAvfilter = true;
    buildAvformat = true; buildAvutil = true; buildPostproc = true;
    buildSwresample = true; buildSwscale = true;
    withSafeBitstreamReader = true; withPixelutils = true;
    withAlsa = true; withDrm = true;
    withXcbShape = true; withXcbShm = true; withXcbxfixes = true;
    libiconv = pkgs.libiconvReal;
  }).overrideAttrs (old: {
    src = pkgs.fetchFromGitHub {
      owner = "FFmpeg"; repo = "FFmpeg"; name = "ffmpeg";
      rev = nativeSourceFacts.sourceRevision;
      hash = "sha256-trLrw4misl9NvXgXrr44Wc1ImPvcPX/KzDyFRsrj8mU=";
    };
    patches = map (patch:
      if lib.hasSuffix "-add-av_stream_get_first_dts-for-chromium.patch" (toString patch)
      then helpers.adaptFfmpegPatchContext {
        upstream = patch; edits = nativeNixPatchContext; name = "chromium-first-dts";
      } else patch
    ) old.patches ++ nativeSecurity.patches;
    patchFlags = [ "-p1" "--fuzz=0" ];
    postPatch = (old.postPatch or "") + ''
      ${pkgs.python3}/bin/python3 -I -B ${nativeSourceGuard} ${nativeSourceSpec} .
    '';
    configureFlags = old.configureFlags ++ [ "--disable-decoder=truemotion1" ];
  });
  # Measured canonical 9.17 source group. All filename, role and dependency
  # consumers derive from this one table, including the portable ELF allowlist.
  nativeLibraries = builtins.fromJSON ''
    {
      "libavcodec.so.61": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6",
          "libiconv.so.2",
          "libm.so.6",
          "libswresample.so.5",
          "libz.so.1"
        ],
        "role": "codec",
        "sourceMode": 493,
        "sourceSha256": "bc1351458e87140e8e8c82f143961c0dbe80c5b6be6248859f18bc9dc8852498"
      },
      "libavdevice.so.61": {
        "needed": [
          "libasound.so.2",
          "libavcodec.so.61",
          "libavfilter.so.10",
          "libavformat.so.61",
          "libavutil.so.59",
          "libc.so.6",
          "libdrm.so.2",
          "libxcb-shape.so.0",
          "libxcb-shm.so.0",
          "libxcb-xfixes.so.0",
          "libxcb.so.1"
        ],
        "role": "device",
        "sourceMode": 493,
        "sourceSha256": "b1a097abf6d0cdd462de245355b258f919728db0b162cd685bdf5485190145b1"
      },
      "libavfilter.so.10": {
        "needed": [
          "libavcodec.so.61",
          "libavformat.so.61",
          "libavutil.so.59",
          "libc.so.6",
          "libm.so.6",
          "libpostproc.so.58",
          "libswresample.so.5",
          "libswscale.so.8"
        ],
        "role": "filter",
        "sourceMode": 493,
        "sourceSha256": "7dc5981e1922a22a204b43a63e1bf7ce4531bb01439260f6a5617d15cdff917d"
      },
      "libavformat.so.61": {
        "needed": [
          "libavcodec.so.61",
          "libavutil.so.59",
          "libbz2.so.1.0",
          "libc.so.6",
          "libiconv.so.2",
          "libm.so.6",
          "libz.so.1"
        ],
        "role": "format",
        "sourceMode": 493,
        "sourceSha256": "0b5b15a9d4a63ef8b40dfcb55b1b8a7b6e62baec7aa0a0224e458e32b7802aa4"
      },
      "libavutil.so.59": {
        "needed": [
          "libc.so.6",
          "libdrm.so.2",
          "libm.so.6"
        ],
        "role": "util",
        "sourceMode": 493,
        "sourceSha256": "d9209d6432ba742251c1bbbc3765ce20fe2ae08dd4dcc45a52fdef9d1f0a329d"
      },
      "libpostproc.so.58": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6"
        ],
        "role": "postproc",
        "sourceMode": 493,
        "sourceSha256": "c43c3c4e7ad19f84d902274f41407a88ca57d0f13c351a7539a51bd658ec2539"
      },
      "libswresample.so.5": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6",
          "libm.so.6"
        ],
        "role": "resample",
        "sourceMode": 493,
        "sourceSha256": "dd478a3977a74d63e5579738de03c23c6955469f3c3c90dd10a1efbbf438ed57"
      },
      "libswscale.so.8": {
        "needed": [
          "libavutil.so.59",
          "libc.so.6",
          "libm.so.6"
        ],
        "role": "scale",
        "sourceMode": 493,
        "sourceSha256": "00e7c791fbeac65fe133f61f4ff16aa5f184400cf38e0907399d9faeffefd7af"
      }
    }
  '';
  nativeDependencies = lib.unique (lib.concatMap (entry: entry.needed) (builtins.attrValues nativeLibraries));
  nativeDescriptor = {
    schemaVersion = 1;
    sourceVersion = "7.1.2";
    securityBackports = nativeSourceFacts // { inherit (nativeSecurity) advisories commits; };
    version = nativeFfmpeg.version;
    minimumVersion = "7.1.5";
    families = nativeFfmpeg.meta.pkgConfigModules;
    libraries = nativeLibraries;
    # Nix and the vendor use different names for the same bzip2 ABI. The
    # required BZ2 exports exist in the retained bundled library. No bytes
    # outside FFmpeg change. Permanent by design for this transport pair.
    dependencyAliases."libbz2.so.1" = builtins.head (builtins.filter
      (name: lib.hasPrefix "libbz2.so." name) nativeDependencies);
    # These paths describe input identity inside JSON; they are not a closure
    # to install in the container. nativeBundle holds the real build edges.
    sourceInput = builtins.unsafeDiscardStringContext (toString nativeFfmpeg.src);
    libraryInput = builtins.unsafeDiscardStringContext (toString nativeFfmpeg.lib);
    commands = { verify = "verify"; apply = "apply"; installed = "installed"; features = "features"; };
    snapshotFile = "original-features.json";
    limits = {
      fileBytes = 67108864; groupBytes = 134217728;
      manifestBytes = 1048576; featuresBytes = 1048576;
      entries = 2048; nameBytes = 256; probeSeconds = 20;
    };
  };
  nativeSpec = pkgs.writeText "calibre-native-spec.json" (builtins.toJSON nativeDescriptor);
  nativeGuard = pkgs.writeText "calibre-native-guard.py" ''
    import ctypes
    import hashlib
    import json
    import os
    from pathlib import Path
    import shutil
    import stat
    import subprocess
    import sys


    def digest(raw):
        return hashlib.sha256(raw).hexdigest()


    def canonical(value):
        return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


    def file_hash(path, limit):
        identity = path.lstat()
        assert stat.S_ISREG(identity.st_mode) and identity.st_size <= limit, "CALIBRE_NATIVE_FILE_TYPE_BOUND"
        with path.open("rb") as handle:
            return hashlib.file_digest(handle, "sha256").hexdigest()


    def schema(spec, manifest):
        assert spec["schemaVersion"] == manifest["schemaVersion"] == 1, "CALIBRE_NATIVE_SCHEMA"
        assert manifest["descriptor"] == spec, "CALIBRE_NATIVE_DESCRIPTOR"
        libraries = spec["libraries"]
        assert libraries and set(manifest["files"]) == set(libraries), "CALIBRE_NATIVE_SET"
        assert {name.split(".so.")[0] for name in libraries} == set(spec["families"]), "CALIBRE_NATIVE_FAMILIES"
        assert len({item["role"] for item in libraries.values()}) == len(libraries), "CALIBRE_NATIVE_ROLES"
        assert len(set(spec["commands"].values())) == len(spec["commands"]), "CALIBRE_NATIVE_COMMANDS"
        assert Path(spec["snapshotFile"]).name == spec["snapshotFile"] and spec["snapshotFile"].endswith(".json"), "CALIBRE_NATIVE_SNAPSHOT_PATH"
        source_version = tuple(map(int, spec["sourceVersion"].split(".")))
        target_version = tuple(map(int, spec["version"].split(".")))
        minimum = tuple(map(int, spec["minimumVersion"].split(".")))
        assert len(source_version) == len(target_version) == len(minimum) == 3, "CALIBRE_NATIVE_VERSION_TYPE"
        assert source_version[0] == target_version[0] and target_version >= minimum, "CALIBRE_NATIVE_VERSION"
        allowed = {needed for entry in libraries.values() for needed in entry["needed"]}
        assert all(old != new and new in allowed for old, new in spec["dependencyAliases"].items()), "CALIBRE_NATIVE_DEPENDENCY_ALIAS"
        for name, entry in manifest["files"].items():
            assert Path(name).name == name and ".so." in name, "CALIBRE_NATIVE_PATH"
            assert entry["soname"] == name and entry["rpath"] == "$ORIGIN", "CALIBRE_NATIVE_ABI_RPATH"
            assert set(entry["needed"]) <= allowed, "CALIBRE_NATIVE_DEPENDENCY"
            assert 0 < entry["bytes"] <= spec["limits"]["fileBytes"], "CALIBRE_NATIVE_FILE_BOUND"


    def package(spec, directory):
        path = directory / "manifest.json"
        assert stat.S_ISREG(path.lstat().st_mode) and path.stat().st_size <= spec["limits"]["manifestBytes"], "CALIBRE_NATIVE_MANIFEST_BOUND"
        manifest = json.loads(path.read_text())
        schema(spec, manifest)
        root = directory / "lib"
        assert root.is_dir() and not root.is_symlink(), "CALIBRE_NATIVE_PACKAGE_ROOT"
        assert {path.name for path in root.iterdir()} == set(spec["libraries"]), "CALIBRE_NATIVE_PACKAGE_SET"
        used = 0
        for name, entry in manifest["files"].items():
            path = root / name
            assert path.stat().st_size == entry["bytes"], "CALIBRE_NATIVE_INPUT_SIZE"
            used += entry["bytes"]
            assert used <= spec["limits"]["groupBytes"], "CALIBRE_NATIVE_GROUP_BOUND"
            assert file_hash(path, spec["limits"]["fileBytes"]) == entry["sha256"], "CALIBRE_NATIVE_INPUT_HASH"
        return manifest


    def source(spec, root):
        assert root.is_dir() and not root.is_symlink(), "CALIBRE_NATIVE_SOURCE_ROOT"
        for name, entry in spec["libraries"].items():
            path = root / name
            assert file_hash(path, spec["limits"]["fileBytes"]) == entry["sourceSha256"], "CALIBRE_NATIVE_SOURCE_HASH"
            assert stat.S_IMODE(path.stat().st_mode) == entry["sourceMode"], "CALIBRE_NATIVE_SOURCE_MODE"


    def verify_inputs(spec, directory, root):
        manifest = package(spec, directory)
        source(spec, root)
        return manifest


    def target_features(spec, original, candidate):
        assert original["version"] == spec["sourceVersion"], "CALIBRE_NATIVE_ORIGINAL_VERSION"
        assert candidate["version"] == spec["version"], "CALIBRE_NATIVE_SELECTED_VERSION"
        assert original["features"].keys() == candidate["features"].keys(), "CALIBRE_NATIVE_FEATURE_GROUP"
        for kind, names in original["features"].items():
            assert set(names) <= set(candidate["features"][kind]), "CALIBRE_NATIVE_FEATURE_LOST:" + kind


    def installed_hashes(spec, manifest, root):
        for name, entry in manifest["files"].items():
            path = root / name
            assert file_hash(path, spec["limits"]["fileBytes"]) == entry["sha256"], "CALIBRE_NATIVE_INSTALLED_HASH"
            assert stat.S_IMODE(path.stat().st_mode) == spec["libraries"][name]["sourceMode"], "CALIBRE_NATIVE_INSTALLED_MODE"


    def apply(spec, directory, root, feature_reader):
        # Verify both complete groups and native feature/loader compatibility before
        # touching an installed library. A failed RUN discards this private layer.
        manifest = verify_inputs(spec, directory, root)
        original = feature_reader(root)
        candidate = feature_reader(directory / "lib")
        target_features(spec, original, candidate)
        snapshot = {"schemaVersion": 1, "descriptorSha256": digest(canonical(spec)),
                    "manifestSha256": digest(canonical(manifest)), "original": original}
        raw = canonical(snapshot)
        assert len(raw) <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_SNAPSHOT_BOUND"
        (directory / spec["snapshotFile"]).write_bytes(raw)
        for name in spec["libraries"]:
            shutil.copyfile(directory / "lib" / name, root / name)
            os.chmod(root / name, spec["libraries"][name]["sourceMode"])
        installed_hashes(spec, manifest, root)
        target_features(spec, original, feature_reader(root))


    def verify_installed(spec, directory, root, feature_reader):
        manifest = package(spec, directory)
        installed_hashes(spec, manifest, root)
        path = directory / spec["snapshotFile"]
        assert stat.S_ISREG(path.lstat().st_mode) and path.stat().st_size <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_SNAPSHOT_BOUND"
        snapshot = json.loads(path.read_text())
        assert snapshot["schemaVersion"] == 1, "CALIBRE_NATIVE_SNAPSHOT_SCHEMA"
        assert snapshot["descriptorSha256"] == digest(canonical(spec)), "CALIBRE_NATIVE_SNAPSHOT_DESCRIPTOR"
        assert snapshot["manifestSha256"] == digest(canonical(manifest)), "CALIBRE_NATIVE_SNAPSHOT_MANIFEST"
        target_features(spec, snapshot["original"], feature_reader(root))


    class Named(ctypes.Structure):
        _fields_ = [("name", ctypes.c_char_p)]


    def dependency_order(metadata):
        pending, result = set(metadata), []
        while pending:
            ready = sorted(name for name in pending if not (set(metadata[name]["needed"]) & pending))
            assert ready, "CALIBRE_NATIVE_DEPENDENCY_CYCLE"
            result.extend(ready)
            pending.difference_update(ready)
        return result


    def features(spec, manifest, root, dependency_root):
        # This runs in a fresh child. Never mix old and new equal SONAMEs in one
        # loader namespace, or select a version from a library already in memory.
        actual = {name: file_hash(root / name, spec["limits"]["fileBytes"]) for name in spec["libraries"]}
        old = {name: value["sourceSha256"] for name, value in spec["libraries"].items()}
        new = {name: value["sha256"] for name, value in manifest["files"].items()}
        assert actual in [old, new], "CALIBRE_NATIVE_UNQUALIFIED_GROUP"
        metadata = spec["libraries"] if actual == old else manifest["files"]
        needed = {name for entry in metadata.values() for name in entry["needed"]}
        for name in sorted(needed - set(metadata)):
            path = dependency_root / name
            if path.is_file():
                assert not path.is_symlink(), "CALIBRE_NATIVE_DEPENDENCY_LINK"
                ctypes.CDLL(str(path), mode=ctypes.RTLD_GLOBAL)
        loaded = {}
        for name in dependency_order(metadata):
            loaded[name] = ctypes.CDLL(str(root / name), mode=ctypes.RTLD_GLOBAL)
        roles = {entry["role"]: loaded[name] for name, entry in spec["libraries"].items()}
        codec, fmt, filters, util, device = (roles[name] for name in ["codec", "format", "filter", "util", "device"])
        device.avdevice_register_all.argtypes = []
        device.avdevice_register_all.restype = None
        device.avdevice_register_all()
        def named(library, method):
            function = getattr(library, method)
            function.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
            function.restype = ctypes.POINTER(Named)
            opaque, rows = ctypes.c_void_p(), []
            for _ in range(spec["limits"]["entries"]):
                entry = function(ctypes.byref(opaque))
                if not entry:
                    return rows
                value = entry.contents.name
                assert len(value) <= spec["limits"]["nameBytes"], "CALIBRE_NATIVE_NAME_BOUND"
                rows.append((value.decode("ascii"), ctypes.cast(entry, ctypes.c_void_p)))
            raise AssertionError("CALIBRE_NATIVE_ENUMERATION_BOUND")
        for method in ["av_codec_is_decoder", "av_codec_is_encoder"]:
            function = getattr(codec, method)
            function.argtypes, function.restype = [ctypes.c_void_p], ctypes.c_int
        entries = named(codec, "av_codec_iterate")
        values = {
            "decoders": sorted({name for name, pointer in entries if codec.av_codec_is_decoder(pointer)}),
            "encoders": sorted({name for name, pointer in entries if codec.av_codec_is_encoder(pointer)}),
            "demuxers": sorted({alias for name, _ in named(fmt, "av_demuxer_iterate") for alias in name.split(",")}),
            "muxers": sorted({alias for name, _ in named(fmt, "av_muxer_iterate") for alias in name.split(",")}),
            "filters": sorted({name for name, _ in named(filters, "av_filter_iterate")}),
        }
        fmt.avio_enum_protocols.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_int]
        fmt.avio_enum_protocols.restype = ctypes.c_char_p
        for output, kind in enumerate(["inputProtocols", "outputProtocols"]):
            opaque, rows = ctypes.c_void_p(), []
            for _ in range(spec["limits"]["entries"]):
                name = fmt.avio_enum_protocols(ctypes.byref(opaque), output)
                if not name:
                    break
                assert len(name) <= spec["limits"]["nameBytes"], "CALIBRE_NATIVE_NAME_BOUND"
                rows.append(name.decode("ascii"))
            else:
                raise AssertionError("CALIBRE_NATIVE_PROTOCOL_BOUND")
            values[kind] = sorted(set(rows))
        util.av_hwdevice_iterate_types.argtypes, util.av_hwdevice_iterate_types.restype = [ctypes.c_int], ctypes.c_int
        util.av_hwdevice_get_type_name.argtypes, util.av_hwdevice_get_type_name.restype = [ctypes.c_int], ctypes.c_char_p
        hardware, kind = [], 0
        for _ in range(spec["limits"]["entries"]):
            kind = util.av_hwdevice_iterate_types(kind)
            if not kind:
                break
            name = util.av_hwdevice_get_type_name(kind)
            assert len(name) <= spec["limits"]["nameBytes"], "CALIBRE_NATIVE_NAME_BOUND"
            hardware.append(name.decode("ascii"))
        else:
            raise AssertionError("CALIBRE_NATIVE_HARDWARE_BOUND")
        values["hardwareDeviceTypes"] = sorted(set(hardware))
        util.av_version_info.restype = ctypes.c_char_p
        return {"version": util.av_version_info().decode("ascii"), "features": values}


    if __name__ == "__main__":
        try:
            if sys.flags.optimize:
                raise AssertionError("CALIBRE_NATIVE_OPTIMIZED_GUARD")
            mode, spec_file, directory, root, dependency_root = sys.argv[1:]
            spec_file, directory, root, dependency_root = map(Path, [spec_file, directory, root, dependency_root])
            assert spec_file.stat().st_size <= 65536, "CALIBRE_NATIVE_SPEC_BOUND"
            spec = json.loads(spec_file.read_text())
            manifest = package(spec, directory)
            commands = spec["commands"]
            assert mode in commands.values(), "CALIBRE_NATIVE_COMMAND"
            def read_features(path):
                raw = subprocess.check_output([sys.executable, "-B", str(Path(__file__).resolve()), commands["features"],
                    str(spec_file), str(directory), str(path), str(dependency_root)], timeout=spec["limits"]["probeSeconds"])
                assert len(raw) <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_FEATURE_BOUND"
                return json.loads(raw)
            if mode == commands["features"]:
                result = features(spec, manifest, root, dependency_root)
                raw = canonical(result)
                assert len(raw) <= spec["limits"]["featuresBytes"], "CALIBRE_NATIVE_FEATURE_BOUND"
                print(raw.decode())
            elif mode == commands["verify"]:
                verify_inputs(spec, directory, root)
            elif mode == commands["apply"]:
                apply(spec, directory, root, read_features)
            else:
                assert mode == commands["installed"], "CALIBRE_NATIVE_COMMAND"
                verify_installed(spec, directory, root, read_features)
        except Exception as error:
            print(str(error) if isinstance(error, AssertionError) else "CALIBRE_NATIVE_INPUT_INVALID", file=sys.stderr)
            sys.exit(1)
  '';
  # REPLACEABLE: rebuilt from the pinned Nix source and descriptor. The image
  # retains the eight vendor filenames/modes; no Nix store closure is installed.
  nativeBundle = pkgs.runCommand "calibre-ffmpeg-portable" {
    nativeBuildInputs = [ pkgs.python3 pkgs.patchelf ];
  } ''
    mkdir -p "$out/lib"
    python3 - ${nativeSpec} ${nativeFfmpeg.lib}/lib "$out" <<'PYNATIVE'
    import hashlib, json, os, pathlib, shutil, subprocess, sys
    spec_file, source, output = map(pathlib.Path, sys.argv[1:])
    spec = json.loads(spec_file.read_text())
    assert {p.name.split(".so.")[0] for p in source.glob("*.so.*")} == set(spec["families"]), "CALIBRE_NATIVE_BUILT_FAMILIES"
    allowed = {name for value in spec["libraries"].values() for name in value["needed"]}
    files, used = {}, 0
    for name in spec["libraries"]:
        target = output / "lib" / name
        shutil.copyfile(source / name, target)
        target.chmod(0o755)
        for old, new in spec["dependencyAliases"].items():
            subprocess.run(["patchelf", "--replace-needed", old, new, str(target)], check=True)
        subprocess.run(["patchelf", "--set-rpath", "$ORIGIN", str(target)], check=True)
        def elf(flag):
            return subprocess.check_output(["patchelf", flag, str(target)], text=True).strip()
        needed, soname, rpath = elf("--print-needed").splitlines(), elf("--print-soname"), elf("--print-rpath")
        assert set(needed) <= allowed and soname == name and rpath == "$ORIGIN", "CALIBRE_NATIVE_PORTABLE_ABI"
        size = target.stat().st_size; used += size
        assert 0 < size <= spec["limits"]["fileBytes"] and used <= spec["limits"]["groupBytes"], "CALIBRE_NATIVE_BUILT_BOUND"
        with target.open("rb") as handle:
            sha = hashlib.file_digest(handle, "sha256").hexdigest()
        files[name] = dict(sha256=sha, bytes=size, soname=soname, needed=needed, rpath=rpath)
    raw = json.dumps(dict(schemaVersion=1, descriptor=spec, files=files), sort_keys=True, separators=(",", ":")).encode()
    assert len(raw) <= spec["limits"]["manifestBytes"], "CALIBRE_NATIVE_BUILT_MANIFEST_BOUND"
    (output / "manifest.json").write_bytes(raw)
    PYNATIVE
  '';
  nativeInputHash = builtins.hashString "sha256" (nativeSpec.text + nativeGuard.text + toString nativeBundle);
  nativeRoot = "${builtins.dirOf calibrePython}/lib";
  nativeStaging = "/tmp/hwc-calibre-native";
  nativeCommand = command: "RUN python3 -I -B ${nativeStaging}/guard.py ${command} ${nativeStaging}/spec.json ${nativeStaging} ${nativeRoot} ${nativeRoot}\n";
  # Temporary: vendor 9.17's frozen Python still accepts malformed chunks.
  # Retire after the unmodified vendor browser passes the framing/data contract.
  runtime = helpers.mkRuntimeImage {
    name = "calibre";
    version = "9.17.0-http-framing";
    recipe = ''
      FROM lscr.io/linuxserver/calibre@sha256:b198fc03a6abc6be7e251a9958e50e74634b00e447c7b25e92c191c8077ba378
      # Native inputs ${nativeInputHash}
      # Native SSL inputs ${sslInputHash}
      COPY native ${nativeStaging}
      COPY native-ssl ${sslStaging}
      COPY stdlib /tmp/hwc-calibre-stdlib
      COPY client.py /tmp/hwc-calibre-http/client.py
    '' + nativeCommand nativeDescriptor.commands.verify
      + nativeCommand nativeDescriptor.commands.apply
      + nativeCommand nativeDescriptor.commands.installed
      + "RUN python3 -I -B ${sslStaging}/guard.py ${sslStaging}/spec.json ${sslStaging} ${sslRuntimeDescriptor.rootPath}\n"
      + socketRecipe "frozen" + distroFullRecipe + sqliteRecipe + httpBackport.recipe + "RUN rm -rf /tmp/hwc-calibre-http /tmp/hwc-frozen-config /tmp/hwc-frozen-cache /tmp/hwc-calibre-stdlib ${nativeStaging} ${sslStaging}\n";
  };
  runtimeManifest = pkgs.writeText "calibre-http-framing.json" (builtins.toJSON httpBackport.manifest);
  # Pure asset API: Books can reuse this qualified distribution without enabling
  # the desktop service or copying its frozen-loader facts and implementation.
  runtimeAssets = pkgs.writeText "calibre-runtime-assets.json" (builtins.toJSON {
    schemaVersion = 1;
    image = runtime.image;
    python = calibrePython;
    rootPath = builtins.dirOf calibrePython;
    http = httpBackport.manifest;
    stdlib = stdlibFacts;
    systemPython = {
      schemaVersion = 1;
      sources = distroFacts;
      nativeSsl = distroSslRuntimeDescriptor;
      nativeSocket = socketRuntimeDescriptors.system;
      inputHash = distroInputHash;
    };
    native = {
      schemaVersion = 1;
      descriptor = nativeDescriptor;
      inputHash = nativeInputHash;
      bundleInput = builtins.unsafeDiscardStringContext (toString nativeBundle);
    };
    nativeSsl = {
      schemaVersion = 1;
      spec = sslRuntimeDescriptor;
      inputHash = sslInputHash;
      bundleInput = builtins.unsafeDiscardStringContext (toString sslPackage);
    };
    nativeSocket = {
      schemaVersion = 1;
      spec = socketRuntimeDescriptors.frozen;
      inputHash = socketInputHash;
      bundleInput = builtins.unsafeDiscardStringContext (toString socketPackages.frozen);
    };
  });
  runtimeContext = pkgs.runCommand "calibre-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${httpSource} "$out/client.py"
    cp ${runtimeManifest} "$out/manifest.json"
    cp -r ${stdlibPackage} "$out/stdlib"
    cp -r ${distroContext} "$out/system-python"
    cp -r ${socketContext}/frozen "$out/native-socket"
    cp -r ${sqliteContext} "$out/sqlite"
    mkdir -p "$out/native"
    cp ${nativeSpec} "$out/native/spec.json"
    cp ${nativeGuard} "$out/native/guard.py"
    cp -r ${nativeBundle}/lib ${nativeBundle}/manifest.json "$out/native/"
    mkdir -p "$out/native-ssl"
    cp ${sslRuntimeSpec} "$out/native-ssl/spec.json"
    cp ${sslGuard} "$out/native-ssl/guard.py"
    cp -r ${sslPackage}/lib ${sslPackage}/manifest.json "$out/native-ssl/"
  '';
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.media.calibre = {
    enable = lib.mkEnableOption "Calibre ebook management container";
    # Critical library state: upgrade this immutable vendor image only after
    # current-data startup and compatible-code recovery checks pass.
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified Calibre 9.17.0 with HTTP framing, native socket/SSL and same-ABI FFmpeg repairs"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU support for Calibre"; };
    ports = {
      desktop = lib.mkOption { type = lib.types.int; default = (import ../../networking/ports.nix).calibre.port; description = "Port for Calibre desktop interface (KasmVNC)"; };
      webserver = lib.mkOption { type = lib.types.port; default = (import ../../networking/ports.nix).calibre-server.port; description = "Port for Calibre content server"; };
    };
    library = lib.mkOption { type = lib.types.path; default = "${paths.media.books}/ebooks"; description = "Path to ebooks library"; };
  };

  imports = [
    ./sys.nix
    ./parts/config.nix
  ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkMerge [
    { system.build = {
      calibreRuntimeAssets = runtimeAssets;
      calibreRuntimeSqliteContext = sqliteContext;
      calibreRuntimeSqliteSpec = sqliteSpec;
      calibreRuntimeSqliteGuard = sqliteGuard;
      calibreRuntimeSqliteRecipe = pkgs.writeText "calibre-sqlite-recipe" sqliteRecipe;
      calibreRuntimeSqliteRuntimeProof = pkgs.writeText "calibre-sqlite-runtime.py" sqliteRuntimeProof;
      calibreRuntimeNativeSpec = nativeSpec;
      calibreRuntimeNativeSourceSpec = nativeSourceSpec;
      calibreRuntimeNativeSourceGuard = nativeSourceGuard;
      calibreRuntimeNativePackage = nativeFfmpeg;
      calibreRuntimeNativeGuard = nativeGuard;
      calibreRuntimeNativeBundle = nativeBundle;
      calibreRuntimeSslSpec = sslSpec;
      calibreRuntimeSslSourceGuard = sslSourceGuard;
      calibreRuntimeSslPackage = sslPackage;
      calibreRuntimeSslRuntimeSpec = sslRuntimeSpec;
      calibreRuntimeSslGuard = sslGuard;
      calibreRuntimeSystemPythonContext = distroContext;
      calibreRuntimeSystemPythonRecipe = pkgs.writeText "calibre-system-python-recipe" distroFullRecipe;
      calibreRuntimeSystemPythonSpec = distroSpec;
      calibreRuntimeSystemPythonSources = distroSources;
      calibreRuntimeSystemPythonSslPackage = distroSslPackage;
      calibreRuntimeSystemPythonSslSpec = distroSslSpec;
      calibreRuntimeStdlibSpec = stdlibSpec;
      calibreRuntimeStdlibSourceGuard = stdlibSourceGuard;
      calibreRuntimeStdlibPackage = stdlibPackage;
      calibreRuntimeSocketSourceGuard = socketSourceGuard;
      calibreRuntimeSocketSourceSpec = socketSourceManifest;
      calibreRuntimeFrozenSocketPackage = socketPackages.frozen;
      calibreRuntimeSystemSocketPackage = socketPackages.system;
      calibreRuntimeSocketGuard = socketRuntimeGuard;
      calibreRuntimeSocketContext = socketContext;
      calibreRuntimeFrozenSocketRuntimeSpec = socketRuntimeSpecs.frozen;
      calibreRuntimeSystemSocketRuntimeSpec = socketRuntimeSpecs.system;
    }; }
    (lib.mkIf cfg.enable {
      system.build.calibreRuntimeImageRecipe = runtime.dockerfile;
      system.build.calibreRuntimeImageContext = runtimeContext;
      systemd.services.podman-calibre.preStart = lib.mkIf (cfg.image == runtime.image) (lib.mkBefore ''
        ${pkgs.podman}/bin/podman image exists ${lib.escapeShellArg runtime.image} || {
          echo "Prebuild Calibre from ${runtime.dockerfile} before activation" >&2
          exit 1
        }
      '');
      # Container definition is in sys.nix
      # Service dependencies are in parts/config.nix

      #==========================================================================
      # VALIDATION
      #==========================================================================
      assertions = helpers.mkVpnAssertions {
        name = "calibre";
        networkMode = cfg.network.mode;
        gluetunInstances = config.hwc.networking.gluetun.instances;
      } ++ [
        {
          assertion = config.hwc.paths.hot.root != null;
          message = "calibre container requires hwc.paths.hot.root to be defined (for downloads)";
        }
        {
          assertion = config.hwc.paths.media.root != null;
          message = "calibre container requires hwc.paths.media.root to be defined (for book libraries)";
        }
      ];
    })
  ];
}
