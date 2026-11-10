"""Exercise evaluated listeners, configuration commands and copier composition.

audiobook-copier.py owns the standalone copier CLI contract. This fixture drives
generated Nix commands and their actual wiring across several media modules.
"""
import copy
import json
import os
import pathlib
import runpy
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as xml
from unittest.mock import Mock, patch

f = json.loads(pathlib.Path(sys.argv[1]).read_text())
expected = {"qbittorrent": 19441, "audiobookshelf": 19442, "sabnzbd": 19443,
    "pinchflat": 19444, "tdarr": 19445, "organizr": 19446, "sonarr": 19447,
    "radarr": 19448, "lidarr": 19449, "prowlarr": 19450, "readarr": 19451,
    "books": 19452, "jellyseerr": 19453, "navidrome": 19454, "mousehole": 19455,
    "transcripts": 19456, "calibre": 19457, "calibre-server": 19458}
routes = {route["name"]: route for route in f["routes"]}


def check_ports(config):
    for name, port in expected.items():
        assert routes[name]["upstream"] == "http://127.0.0.1:" + str(port), name
        if name == "transcripts":
            continue
        container = "calibre" if name == "calibre-server" else name
        seen = set()
        while True:
            assert container not in seen, "container network namespace cycle"
            seen.add(container)
            shared = [value.removeprefix("--network=container:")
                      for value in f["networks"][container]
                      if value.startswith("--network=container:")]
            if not shared:
                break
            assert len(shared) == 1, "ambiguous container network namespace"
            container = shared[0]
        assert any(value.startswith("127.0.0.1:" + str(port) + ":")
                   for value in config[container]), name


check_ports(f["ports"])
assert "--network=container:gluetun" in f["networks"]["sabnzbd"]
assert "127.0.0.1:19443:8085" in f["ports"]["gluetun"]
assert f["sabListener"] == "8085"
assert f["directSab"]["ports"] == ["127.0.0.1:19443:19443"]
assert f["directSab"]["listener"] == "19443"
assert not any(value.startswith("127.0.0.1:19443:") for value in f["directTunnelPorts"])
assert not any(value.startswith("--network=container:") for value in f["directSab"]["extraOptions"])
stale = copy.deepcopy(f["ports"])
stale["gluetun"] = [value.replace("127.0.0.1:19443:8085", "127.0.0.1:8081:8085")
                    for value in stale["gluetun"]]
try:
    check_ports(stale)
except AssertionError as error:
    assert str(error) == "sabnzbd", error
else:
    raise AssertionError("stale SABnzbd tunnel binding passed")
broken = copy.deepcopy(f["ports"])
broken["calibre"] = ["127.0.0.1:8083:8080", "127.0.0.1:8090:8090"]
try:
    check_ports(broken)
except AssertionError:
    pass
else:
    raise AssertionError("omitted listener integration passed")

with tempfile.TemporaryDirectory() as directory:
    root = pathlib.Path(directory)
    tools = root / "bin"
    tools.mkdir()
    chown = tools / "chown"
    chown.write_text("#!" + f["shell"] + "\nexit 0\n")
    chown.chmod(0o755)
    environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"])

    def execute(path):
        source = pathlib.Path(path).read_text()
        source = source.replace("/fixture-beets", str(root / "configured"))
        source = source.replace("/fixture-apps", str(root / "fallback"))
        result = subprocess.run(["bash", "-e", "-c", source], env=environment,
                                capture_output=True, text=True, timeout=15)
        assert result.returncode == 0, result.stderr

    execute(f["beets"])
    assert (root / "configured/config.yaml").is_file(), "Beets ignored its configured mount"
    assert not (root / "fallback/beets/config/config.yaml").exists()
    for name, port in {"sonarr": 8989, "radarr": 7878, "lidarr": 8686, "prowlarr": 9696}.items():
        execute(f["arr"][name])
        config = xml.parse(root / "fallback" / name / "config/config.xml").getroot()
        assert config.findtext("Port") == str(port), name
        assert config.findtext("UrlBase") in {"", None}, name

desired = {"SOURCE_DIR": "/fixture-source", "DEST_DIR": "/fixture-library",
    "STATE_DIR": "/fixture-state", "TRIGGER_LIBRARY_SCAN": "0",
    "AUDIO_EXTENSIONS": "fixture", "AUDIOBOOKSHELF_URL": "http://localhost:19442"}
wrapper = pathlib.Path(f["wrapper"]).read_text()


def check_wrapper(source):
    with patch.dict(os.environ, {}, clear=True), patch.object(runpy, "run_path") as implementation:
        exec(compile(source, "<actual-wrapper>", "exec"), {"__name__": "__main__"})
        assert {key: os.environ.get(key) for key in desired} == desired
        assert implementation.call_count == 1
        assert pathlib.Path(implementation.call_args.args[0]).read_bytes() == pathlib.Path(f["implementation"]).read_bytes()


check_wrapper(wrapper)
try:
    check_wrapper(wrapper.replace("os.environ.setdefault(name, value)", "None"))
except AssertionError:
    pass
else:
    raise AssertionError("omitted copier composition passed")

namespace = {"__name__": "fixture"}
exec(compile(pathlib.Path(f["sweep"]).read_text(), "<actual-sweep>", "exec"), namespace)
with patch.object(subprocess, "run", return_value=Mock(returncode=0)) as invoke:
    namespace["sweep_books"]()
assert invoke.call_count == 1
assert invoke.call_args.args[0][1:] == [f["wrapper"], "--scan-all", "--no-library-scan", "--include-hidden"]
print("actual media listeners, config paths, arr bootstrap and copier composition pass")
