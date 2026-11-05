# TEMPORARY: CPython response framing backports, including optional whitespace.
# Remove runtime selection when the unmodified locked interpreters and managed
# app launchers pass python-http-runtime-contract on work, home and laptop.
# nodejs-security.nix owns Node's binary/library protocol; it cannot own Python's
# adjacent stdlib and withPackages wrapper protocol. Native build graphs stay put.
final: prev:
let
  lib = prev.lib;
  spec = builtins.fromJSON (builtins.readFile ./python-http-framing.json);
  # Keep native runtime identity independent of container-only adapters.
  nativeSpec = { inherit (spec) schemaVersion upstreamCommits replacements nativeSources; };
  manifest = prev.writeText "python-http-framing.json" (builtins.toJSON nativeSpec);
  contract = prev.writeText "python-http-runtime-contract.py" ''
    import hashlib
    import http.client
    import io
    import json
    from pathlib import Path
    import site
    import sqlite3
    import ssl
    import sys
    import zlib

    class Socket:
        def __init__(self, raw):
            self.raw = raw
        def makefile(self, *args):
            return io.BytesIO(self.raw)

    def length(value):
        response = http.client.HTTPResponse(Socket(b"HTTP/1.1 200 OK\r\nContent-Length: " + value + b"\r\n\r\n"))
        response.begin()
        return response.length

    def chunk(value, size):
        response = http.client.HTTPResponse(Socket(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" + value + b"\r\n" + b"X" * size + b"\r\n0\r\n\r\n"))
        response.begin()
        try:
            return response.read() == b"X" * size
        except http.client.HTTPException:
            return False

    assert length(b"5") == 5 and length(b"5 \t") == 5, "NORMAL_LENGTH_OR_OWS"
    assert chunk(b"a", 10) and chunk(b"A;extension=yes", 10), "NORMAL_CHUNK"
    rejected = [length(value) is None for value in (b"+5", b"1_0", b"-5", b"0x5", b"5 0")]
    rejected += [not chunk(value, size) for value, size in ((b"+a", 10), (b"0xa", 10), (b"1_0", 16))]
    baseline = sys.argv[1] == "--baseline"
    assert (not all(rejected)) if baseline else all(rejected), "RAW_FIXED_RETIRE_BACKPORT" if baseline else "MALFORMED_HTTP_FRAMING"
    if not baseline:
        root = Path(sys.argv[1])
        assert Path(http.client.__file__).is_relative_to(root), "STDLIB_SELECTION"
        proof = json.loads((root / "nix-support/http-framing.json").read_text())
        assert hashlib.sha256(Path(http.client.__file__).read_bytes()).hexdigest() == proof["patchedSha256"], "STDLIB_HASH"
        assert hashlib.sha256((root / "bin" / proof["executable"]).read_bytes()).hexdigest() == proof["originalExecutableSha256"], "EXECUTABLE_PARITY"
    assert sqlite3.connect(":memory:").execute("select 42").fetchone() == (42,), "SQLITE_ABI"
    assert zlib.decompress(zlib.compress(b"runtime ABI")) == b"runtime ABI", "ZLIB_ABI"
    print(json.dumps({"passed": True, "baselineStillAffected": baseline, "httpClient": http.client.__file__, "noUserSite": sys.flags.no_user_site, "userSiteEnabled": site.ENABLE_USER_SITE, "openssl": ssl.OPENSSL_VERSION, "sqlite": sqlite3.sqlite_version}))
  '';
  builder = prev.writeText "python-http-runtime.py" ''
    import hashlib
    import json
    from pathlib import Path
    import shutil
    import sys

    original, output = map(Path, sys.argv[1:3])
    executable, lib_prefix = sys.argv[3:5]
    spec = json.loads(Path(sys.argv[5]).read_text())
    assert spec["schemaVersion"] == 1, "PYTHON_HTTP_SPEC_VERSION"
    source_http = original / "lib" / lib_prefix / "http"
    raw = (source_http / "client.py").read_bytes()
    source_hash = hashlib.sha256(raw).hexdigest()
    assert source_hash in spec["nativeSources"], "PYTHON_HTTP_SOURCE_DRIFT"
    text = raw.decode()
    for before, after in spec["replacements"]:
        assert text.count(before) == 1, "PYTHON_HTTP_HUNK_DRIFT"
        text = text.replace(before, after)
    patched = text.encode()
    patched_hash = hashlib.sha256(patched).hexdigest()
    assert patched_hash == spec["nativeSources"][source_hash], "PYTHON_HTTP_RESULT_DRIFT"
    assert (original / "bin" / executable).is_file(), "PYTHON_EXECUTABLE_MISSING"
    output.mkdir()
    for entry in original.iterdir():
        if entry.name not in {"bin", "lib", "nix-support"}:
            (output / entry.name).symlink_to(entry)
    (output / "bin").mkdir()
    for entry in (original / "bin").iterdir():
        target = output / "bin" / entry.name
        if entry.name == executable:
            # Preserve the exact ELF or withPackages wrapper and all its flags.
            # Its existing argv0 resolution discovers the adjacent stdlib.
            shutil.copyfile(entry, target)
            target.chmod(0o755)
        elif entry.name in {"python", "python3"}:
            target.symlink_to(executable)
        else:
            target.symlink_to(entry)
    for alias in {"python", "python3"}:
        if not (output / "bin" / alias).exists():
            (output / "bin" / alias).symlink_to(executable)
    (output / "lib").mkdir()
    for entry in (original / "lib").iterdir():
        if entry.name != lib_prefix:
            (output / "lib" / entry.name).symlink_to(entry)
    stdlib = output / "lib" / lib_prefix
    stdlib.mkdir()
    for entry in (original / "lib" / lib_prefix).iterdir():
        if entry.name != "http":
            (stdlib / entry.name).symlink_to(entry)
    (stdlib / "http").mkdir()
    copied = (output / "bin" / executable).stat().st_size
    for entry in source_http.iterdir():
        if entry.name == "__pycache__":
            continue
        assert entry.is_file(), "PYTHON_HTTP_LAYOUT_DRIFT"
        data = patched if entry.name == "client.py" else entry.read_bytes()
        (stdlib / "http" / entry.name).write_bytes(data)
        copied += len(data)
    assert copied <= 8388608, "PYTHON_HTTP_OUTPUT_LIMIT"
    assert sum(1 for _ in output.rglob("*")) <= 5000, "PYTHON_HTTP_ENTRY_LIMIT"
    support = output / "nix-support"
    support.mkdir()
    if (original / "nix-support").is_dir():
        for entry in (original / "nix-support").iterdir():
            (support / entry.name).symlink_to(entry)
    proof = {"schemaVersion": 1, "original": str(original), "executable": executable, "originalExecutableSha256": hashlib.sha256((original / "bin" / executable).read_bytes()).hexdigest(), "sourceSha256": source_hash, "patchedSha256": patched_hash, "copiedBytes": copied, "upstreamCommits": spec["upstreamCommits"]}
    (support / "http-framing.json").write_text(json.dumps(proof, indent=2) + "\n")
  '';
  mkRuntime = original:
    if original.httpFramingPatched or false then original else
    let
      base = original.python or original;
      runtime = prev.runCommand "${original.name}-http-framing" {
      preferLocalBuild = true;
      pname = original.pname or "python3";
      version = base.version;
      passthru = (original.passthru or {}) // {
        httpFramingPatched = true;
        runtimeSource = original;
        runtimeContract = contract;
        runtimeBuilder = builder;
        runtimeManifest = manifest;
        interpreter = "${runtime}/bin/${base.executable}";
        withPackages = packages: mkRuntime (base.withPackages packages);
      };
      meta = original.meta or {};
    } ''
      ${prev.python3}/bin/python3 -B ${builder} ${original} "$out" ${base.executable} ${base.libPrefix} ${manifest}
      "$out/bin/${base.executable}" -B ${contract} "$out"
    '';
    in runtime;
  applicationBuilder = prev.writeText "python-http-application.py" ''
    import hashlib
    import json
    from pathlib import Path
    import shlex
    import sys
    from enum import StrEnum

    class LauncherKind(StrEnum):
        PYTHON = "python"
        SHELL = "shell"

    original, python, runtime, output = map(Path, sys.argv[1:5])
    executable = sys.argv[5]
    entries = {entry.name for entry in (original / "bin").iterdir()}
    commands = [name for name in entries if not name.startswith(".")]
    assert 1 <= len(commands) <= 16 and len(entries) <= 64, "APP_ENTRYPOINT_LIMIT"
    launchers = {}
    graph = {}
    for name in sorted(entries):
        source = original / "bin" / name
        assert source.is_file() and source.stat().st_size <= 131072, "APP_LAUNCHER_LIMIT"
        text = source.read_text()
        assert text.startswith("#!") and str(original) in text, "APP_LAUNCHER_CONTRACT"
        if text.splitlines()[0] == "#!" + str(python / "bin" / executable):
            graph[name] = {"kind": LauncherKind.PYTHON, "interpreter": str(python / "bin" / executable)}
        else:
            assert "/bin/bash" in text.splitlines()[0], "APP_INTERPRETER_DRIFT"
            forwards = [shlex.split(line) for line in text.splitlines() if line.startswith('exec -a "$0" ')]
            assert len(forwards) == 1, "APP_SHELL_FORWARD_DRIFT"
            forward = forwards[0]
            assert len(forward) == 5 and forward[:3] == ["exec", "-a", "$0"] and forward[4] == "$@", "APP_SHELL_ARGV_DRIFT"
            target = Path(forward[3])
            assert target.parent == original / "bin" and target.name in entries, "APP_WRAPPER_TARGET_DRIFT"
            graph[name] = {"kind": LauncherKind.SHELL, "target": target.name}
        # Keep original module and asset origins, including identity hashes
        # derived from __file__. Only self-execution paths move to this output.
        original_bin, output_bin = str(original / "bin"), str(output / "bin")
        patched = text.replace(str(python), str(runtime)).replace(original_bin, output_bin)
        assert str(python) not in patched and original_bin not in patched, "APP_RUNTIME_REFERENCE_LEFT"
        launchers[name] = (source, text, patched)
    reachable = set()
    for command in commands:
        current = command
        visited = set()
        while True:
            assert current not in visited, "APP_WRAPPER_CYCLE"
            visited.add(current)
            reachable.add(current)
            descriptor = graph[current]
            match descriptor["kind"]:
                case LauncherKind.PYTHON:
                    break
                case LauncherKind.SHELL:
                    current = descriptor["target"]
                case _:
                    raise AssertionError("APP_WRAPPER_KIND")
    assert reachable == entries, "APP_ORPHAN_LAUNCHER"
    output.mkdir()
    for entry in original.iterdir():
        if entry.name not in {"bin", "nix-support"}:
            (output / entry.name).symlink_to(entry)
    (output / "bin").mkdir()
    proof = {"schemaVersion": 1, "commands": sorted(commands), "wrapperGraph": graph, "original": str(original), "originalPython": str(python), "runtime": str(runtime), "launchers": {}}
    for name, (source, before, after) in launchers.items():
        target = output / "bin" / name
        target.write_text(after)
        target.chmod(source.stat().st_mode & 0o777)
        proof["launchers"][name] = {"originalSha256": hashlib.sha256(before.encode()).hexdigest(), "patchedSha256": hashlib.sha256(after.encode()).hexdigest(), "pythonSubstitutions": before.count(str(python)), "selfSubstitutions": before.count(str(original / "bin"))}
    support = output / "nix-support"
    support.mkdir()
    if (original / "nix-support").is_dir():
        for entry in (original / "nix-support").iterdir():
            (support / entry.name).symlink_to(entry)
    (support / "http-framing-application.json").write_text(json.dumps(proof, indent=2) + "\n")
  '';
  mkApplication = { application, python }:
    let
      runtime = mkRuntime python;
      outputs = application.outputs or [ "out" ];
      extraOutputs = lib.remove "out" outputs;
    in
    assert lib.assertMsg (builtins.elem "out" outputs && builtins.length outputs <= 4
      && lib.all (name: builtins.elem name [ "man" "doc" "dist" ]) extraOutputs
      && lib.all (name: builtins.elem name outputs) (application.meta.outputsToInstall or [ "out" ]))
      "APP_OUTPUT_PROTOCOL_UNSUPPORTED";
    prev.runCommand "${application.name}-http-framing" ({
      preferLocalBuild = true;
      pname = lib.getName application;
      version = application.version or (lib.getVersion application);
      passthru = (application.passthru or {}) // {
        sourceApplication = application;
        sourcePython = python;
        runtimeApplicationBuilder = applicationBuilder;
        pythonHttpRuntime = runtime;
      };
      meta = application.meta or {};
    } // lib.optionalAttrs (extraOutputs != []) { inherit outputs; }) ''
      ${prev.python3}/bin/python3 -B ${applicationBuilder} ${application} ${python} ${runtime} "$out" ${python.executable}${lib.concatMapStrings (name:
        "\n      ln -s ${lib.escapeShellArg (toString application.${name})} \"$" + name + "\"") extraOutputs}
      ${prev.python3}/bin/python3 -B - "$out" <<'PY'
from pathlib import Path
import subprocess
import sys
for launcher in (Path(sys.argv[1]) / 'bin').iterdir():
    if not launcher.name.startswith('.'):
        subprocess.run([str(launcher), '--help'], stdout=subprocess.DEVNULL, check=True, timeout=30)
PY
    '';
in
assert spec.schemaVersion == 1;
{
  # The container retains its existing source/result hashes and protocol shape.
  pythonHttpFramingBackport = { inherit (spec) upstreamCommits replacements; };
  # Local urllib3 adaptation reuses the controlled stdlib predicates. This is
  # not an upstream urllib3 release; image callers must qualify both modules.
  pythonUrllib3FramingBackport = {
    replacements = spec.urllib3Replacements;
    sources = spec.urllib3Sources;
  };
  # Frozen importers need the same registered source/result identity, while
  # the existing native and SAB manifest projections retain their exact bytes.
  pythonFrozenFramingBackport = { inherit (spec) upstreamCommits replacements nativeSources; };
  mkPythonHttpRuntime = mkRuntime;
  mkPythonHttpApplication = mkApplication;
}
