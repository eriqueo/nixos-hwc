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
    consumerVerification = stdlibRuntimeProof + sslRuntimeProof + ''
      native_ssl = native_ssl_proof()
      libraries = stdlib_proof()
      import calibre.gui2
      from calibre.constants import is_running_from_develop
      from calibre.utils.ipc.simple_worker import fork_job
      assert not is_running_from_develop, 'CALIBRE_GUI_DEVELOP_MODE'
      worker = ${builtins.toJSON (stdlibRuntimeProof + sslRuntimeProof + ''
        def prove():
            import http.client
            from calibre.constants import is_running_from_develop
            return (is_running_from_develop,http.client.__file__,bool(http.client._is_legal_chunk_size(b"a")),bool(http.client._is_legal_chunk_size(b"+a")),native_ssl_proof(),stdlib_proof())
      '')}
      actual = fork_job(worker, 'prove', timeout=15, no_output=True, module_is_source_code=True)['result']
      assert actual == (False, str(path), True, False, native_ssl, libraries), 'CALIBRE_WORKER_HTTP_SELECTION'
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
  sslSourceGuard = pkgs.writeText "calibre-native-ssl-source-guard.py" ''
    import hashlib, json, pathlib, re, sys

    def check(spec, root, python_header, openssl_header):
        assert spec["schemaVersion"] == 1, "CALIBRE_SSL_SCHEMA"
        for name, expected in spec["sourceFiles"].items():
            path = root / name
            assert path.is_file() and not path.is_symlink(), "CALIBRE_SSL_SOURCE_TYPE"
            raw = path.read_bytes()
            assert 0 < len(raw) <= spec["limits"]["sourceBytes"], "CALIBRE_SSL_SOURCE_BOUND"
            assert hashlib.sha256(raw).hexdigest() == expected, "CALIBRE_SSL_SOURCE_DRIFT"
        for name, path in [("python", python_header), ("openssl", openssl_header)]:
            assert path.is_file() and not path.is_symlink(), "CALIBRE_SSL_HEADER_TYPE"
            raw = path.read_bytes()
            assert 0 < len(raw) <= spec["limits"]["sourceBytes"], "CALIBRE_SSL_HEADER_BOUND"
            assert hashlib.sha256(raw).hexdigest() == spec["headers"][name], "CALIBRE_SSL_HEADER_DRIFT"
        text = python_header.read_text()
        for name, expected in spec["abiMacros"].items():
            values = re.findall(r"^#define " + re.escape(name) + r"\s+(\d+)\s*$", text, re.M)
            assert len(values) <= 1 and (int(values[0]) if values else 0) == expected, "CALIBRE_SSL_ABI_DRIFT"
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
  '';
  # REPLACEABLE: one native module rebuilt from the pinned source and SDK.
  # Do not run Python's full configure/build or link a second libpython.
  mkSslPackage = { pname, src, descriptor, spec, pythonHeader, opensslHeader,
    includeDirs, linkArgs, buildInputs }:
    pkgs.stdenv.mkDerivation {
      inherit pname src buildInputs;
      version = lib.concatMapStringsSep "." toString descriptor.pythonVersion;
      patches = [ (pkgs.fetchpatch descriptor.patch) ];
      patchFlags = [ "-p1" "--fuzz=0" ];
      nativeBuildInputs = [ pkgs.python3 pkgs.patchelf ];
      dontConfigure = true;
      postPatch = ''
        python3 -I -B ${sslSourceGuard} ${spec} . \
          ${pythonHeader} \
          ${opensslHeader}
      '';
      buildPhase = ''
        runHook preBuild
        $CC -shared -fPIC -O2 -DNDEBUG -fno-strict-aliasing \
          ${lib.concatMapStringsSep " " (path: "-I${path}") includeDirs} \
          Modules/_ssl.c ${lib.concatStringsSep " " linkArgs} -o _ssl.so
        runHook postBuild
      '';
      installPhase = ''
        runHook preInstall
        mkdir -p "$out/lib"
        install -m755 _ssl.so "$out/lib/_ssl.so"
        runHook postInstall
      '';
      # Run after Nix's strip/RPATH fixups: the output loads vendor libraries
      # beside the original target, not the Nix build SDK's runtime closure.
      postFixup = ''
        patchelf --set-rpath ${lib.escapeShellArg descriptor.rpath} "$out/lib/_ssl.so"
        python3 -I -B - ${spec} "$out" <<'PYSSL'
        import hashlib, json, pathlib, subprocess, sys
        spec_file, output = map(pathlib.Path, sys.argv[1:])
        spec = json.loads(spec_file.read_text())
        path = output / "lib/_ssl.so"
        def elf(flag):
            return subprocess.check_output(["patchelf", flag, str(path)], text=True).strip()
        needed, rpath, soname = sorted(elf("--print-needed").splitlines()), elf("--print-rpath"), elf("--print-soname")
        assert needed == spec["original"]["needed"] and rpath == spec["rpath"] and not soname, "CALIBRE_SSL_PORTABLE_ABI"
        raw = path.read_bytes()
        assert 0 < len(raw) <= spec["limits"]["fileBytes"], "CALIBRE_SSL_BUILT_BOUND"
        result = dict(schemaVersion=1, descriptor=spec, file=dict(sha256=hashlib.sha256(raw).hexdigest(),
            bytes=len(raw), needed=needed, rpath=rpath, soname=soname))
        raw = json.dumps(result, sort_keys=True, separators=(",", ":")).encode()
        assert len(raw) <= spec["limits"]["manifestBytes"], "CALIBRE_SSL_MANIFEST_BOUND"
        (output / "manifest.json").write_bytes(raw)
        PYSSL
      '';
    };
  sslPackage = assert lib.assertMsg
    (pkgs.python314.version == lib.concatMapStringsSep "." toString sslDescriptor.pythonVersion
      && pkgs.openssl_3_5.version == sslDescriptor.opensslVersion)
    "Calibre SSL requires the measured Python and OpenSSL SDK versions";
    mkSslPackage {
      pname = "calibre-native-ssl";
      src = pkgs.python314.src;
      descriptor = sslDescriptor;
      spec = sslSpec;
      pythonHeader = "${pkgs.python314}/include/python3.14/pyconfig.h";
      opensslHeader = "${lib.getDev pkgs.openssl_3_5}/include/openssl/opensslv.h";
      includeDirs = [ "${pkgs.python314}/include/python3.14"
        "${pkgs.python314}/include/python3.14/internal"
        "${lib.getDev pkgs.openssl_3_5}/include" "${lib.getDev pkgs.bluez}/include" ];
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
  distroSslPackage = mkSslPackage {
    pname = "calibre-system-python-ssl";
    src = pkgs.fetchurl {
      url = "https://archive.ubuntu.com/ubuntu/pool/main/p/python3.14/python3.14_3.14.4.orig.tar.xz";
      sha256 = "d923c51303e38e249136fc1bdf3568d56ecb03214efdef48516176d3d7faaef8";
    };
    descriptor = distroSslDescriptor;
    spec = distroSslSpec;
    pythonHeader = "${distroSdk}/usr/include/x86_64-linux-gnu/python3.14/pyconfig.h";
    opensslHeader = "${distroSdk}/usr/include/openssl/opensslv.h";
    includeDirs = map (path: "${distroSdk}/${path}") [ "usr/include/python3.14"
      "usr/include/python3.14/internal" "usr/include/x86_64-linux-gnu/python3.14"
      "usr/include" "usr/include/x86_64-linux-gnu" ] ++ [ "${lib.getDev pkgs.bluez}/include" ];
    linkArgs = map (name: "${distroSdk}/usr/lib/x86_64-linux-gnu/${name}") [ "libssl.so.3" "libcrypto.so.3" ];
    buildInputs = [];
  };
  distroSslRuntimeDescriptor = {
    schemaVersion = 1;
    native = distroSslDescriptor;
    rootPath = "/";
    trustKind = sslTrustKinds.system;
    proofDirectory = ".hwc-system-python-ssl";
    guardSha256 = builtins.hashString "sha256" sslGuard.text;
  };
  distroSslRuntimeSpec = pkgs.writeText "calibre-system-python-ssl-runtime.json" (builtins.toJSON distroSslRuntimeDescriptor);
  distroStaging = "/tmp/hwc-system-python";
  distroInputHash = builtins.hashString "sha256"
    (distroSpec.text + stdlibSourceGuard.text + distroSslRuntimeSpec.text + sslGuard.text + toString distroSources + toString distroSslPackage);
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
    RUN /lsiopy/bin/python3 -I -B -c ${lib.escapeShellArg distroRuntimeProof}
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
  '';
  # Upstream7.1 maintenance keeps RELEASE7.1.5; bind its exact revision
  # and complete post-patch source separately from the library version.
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
      + distroRecipe + httpBackport.recipe + "RUN rm -rf /tmp/hwc-calibre-http /tmp/hwc-frozen-config /tmp/hwc-frozen-cache /tmp/hwc-calibre-stdlib ${nativeStaging} ${sslStaging}\n";
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
  });
  runtimeContext = pkgs.runCommand "calibre-runtime-context" {} ''
    mkdir -p "$out"
    cp ${runtime.dockerfile} "$out/Dockerfile"
    cp ${httpSource} "$out/client.py"
    cp ${runtimeManifest} "$out/manifest.json"
    cp -r ${stdlibPackage} "$out/stdlib"
    cp -r ${distroContext} "$out/system-python"
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
    image = lib.mkOption { type = lib.types.str; default = runtime.image; description = "Qualified Calibre 9.17.0 with HTTP framing, native SSL and same-ABI FFmpeg repairs"; };
    network.mode = lib.mkOption { type = lib.types.enum [ "media" "vpn" ]; default = "media"; description = "Network mode"; };
    gpu.enable = lib.mkOption { type = lib.types.bool; default = false; description = "Enable GPU support for Calibre"; };
    ports = {
      desktop = lib.mkOption { type = lib.types.int; default = 8083; description = "Port for Calibre desktop interface (KasmVNC)"; };
      webserver = lib.mkOption { type = lib.types.int; default = 8181; description = "Port for Calibre content server"; };
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
      calibreRuntimeSystemPythonRecipe = pkgs.writeText "calibre-system-python-recipe" distroRecipe;
      calibreRuntimeSystemPythonSpec = distroSpec;
      calibreRuntimeSystemPythonSources = distroSources;
      calibreRuntimeSystemPythonSslPackage = distroSslPackage;
      calibreRuntimeSystemPythonSslSpec = distroSslSpec;
      calibreRuntimeStdlibSpec = stdlibSpec;
      calibreRuntimeStdlibSourceGuard = stdlibSourceGuard;
      calibreRuntimeStdlibPackage = stdlibPackage;
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
