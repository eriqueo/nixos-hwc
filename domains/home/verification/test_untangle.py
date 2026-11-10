#!/usr/bin/env python3
"""Exercise rendered home consumers with isolated command and device fixtures."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def run(arguments, *, env, check=True):
    return subprocess.run(arguments, env=env, text=True, capture_output=True,
                          check=check, timeout=15)


def executable(path, body):
    path.write_text(body)
    path.chmod(0o755)
    return str(path)


def activation(data, root):
    text = data["init"]
    begin = re.search(r"^\s*_hwc_rebuild\(\) \{", text, re.M)
    end = re.search(r"^\s*ff\(\) \{", text, re.M)
    assert begin and end
    functions = text[begin.start():end.start()]
    log = root / "activation.log"
    script = root / "activation.zsh"
    stubs = '''
python3() { print -r -- "runner $*" >> "$PROBE_LOG"; return "$PROBE_STATUS"; }
hyprctl() { print reload >> "$PROBE_LOG"; }
_hwc_reinit_prompt() { print prompt >> "$PROBE_LOG"; }
'''
    for command, lane, action in (("snix", "system", "switch"),
                                  ("tnix", "system", "test"),
                                  ("hms", "home", None),
                                  ("bnix", "system", "build")):
        for status in (0, 23):
            log.write_text("")
            script.write_text(functions + stubs + f"\n{command} --show-trace\n")
            env = os.environ | dict(PROBE_LOG=str(log), PROBE_STATUS=str(status),
                HWC_NIXOS_DIR="/fixture/nixos", HYPRLAND_INSTANCE_SIGNATURE="fixture")
            result = run(["zsh", "-dfi", str(script)], env=env, check=False)
            assert result.returncode == status, (command, status, result.stderr)
            rows = log.read_text().splitlines()
            assert len([row for row in rows if row.startswith("runner ")]) == 1, rows
            assert f"--lane {lane}" in rows[0] and "--show-trace" in rows[0], rows
            if action:
                assert f"--action {action}" in rows[0], rows
            assert rows[1:] == (["prompt", "reload"] if status == 0 and command != "bnix" else []), rows
    # The production wrappers must call the shared success boundary.
    for command in ("snix", "tnix", "hms"):
        log.write_text("")
        script.write_text(functions + stubs + '\n_hwc_activation_complete() { print complete >> "$PROBE_LOG"; }\n'
                          + command + "\n")
        run(["zsh", "-df", str(script)], env=env | {"PROBE_STATUS": "0"})
        assert log.read_text().splitlines()[1:] == ["complete"]


def browsers(data, root):
    directory = root / "browser"
    directory.mkdir()
    (directory / "bin").mkdir()
    capture = executable(directory / "bin" / "capture", "#!" + sys.executable + "\n"
        + "import json,os,sys\nprint(json.dumps(dict(args=sys.argv[1:],vaapi=os.environ.get('LIBVA_DRIVER_NAME'),egl=os.environ.get('__EGL_VENDOR_LIBRARY_FILENAMES'))))\n")
    for command in ("cat", "basename"):
        (directory / "bin" / command).symlink_to(shutil.which(command))
    (directory / "bin" / "chromium").symlink_to(capture)
    executable(directory / "bin" / "gpu-integrated", '#!/bin/sh\nexec "$@"\n')
    nodes = directory / "dri"
    nodes.mkdir()
    (nodes / "renderD128").touch()
    vendor = directory / "drm" / "renderD128" / "device" / "vendor"
    vendor.parent.mkdir(parents=True)
    driver = directory / "iHD_drv_video.so"
    for name, raw in data["browsers"].items():
        text = raw.replace("/dev/dri/renderD*", str(nodes / "renderD*"))
        text = text.replace("/sys/class/drm/", str(directory / "drm") + "/")
        text = text.replace("/run/opengl-driver/lib/dri/iHD_drv_video.so", str(driver))
        text = re.sub(r"exec /nix/store/[^ /]+/bin/firefox", "exec " + capture, text)
        script = directory / name
        script.write_text(text)
        env = os.environ | dict(PATH=str(directory / "bin"), HOME=str(directory),
            LIBVA_DRIVER_NAME="inherited", __EGL_VENDOR_LIBRARY_FILENAMES="mesa-fixture")
        for intel, installed in ((False, True), (True, False), (True, True)):
            vendor.write_text("0x8086" if intel else "0x10de")
            if installed:
                driver.touch()
            else:
                driver.unlink(missing_ok=True)
            result = json.loads(run([shutil.which("bash"), str(script), "--fixture", "two words"], env=env).stdout)
            assert result["vaapi"] == ("iHD" if intel and installed else "inherited"), (name, result)
            assert result["args"][-2:] == ["--fixture", "two words"], result
            assert result["egl"] == (None if name == "firefox" else "mesa-fixture"), result
            if name == "workbench":
                assert "--user-data-dir=" + str(directory / ".config/chromium-workbench") in result["args"]


def workspaces(data, root):
    value = data["workspace"]
    assert value["mapping"] == ["2,monitor:eDP-1", "4,monitor:eDP-1",
                                "22,monitor:desc:Ancor Communications Inc VG248 E6LMQS027213",
                                "24,monitor:desc:Ancor Communications Inc VG248 E6LMQS027213"]
    bars = {bar["output"]: bar["hyprland/workspaces"] for bar in value["bars"]}
    assert set(bars["__INTERNAL_OUTPUT__"]["persistent-workspaces"]) == {"2", "4"}
    external = bars["__EXTERNAL_OUTPUT__"]
    assert set(external["persistent-workspaces"]) == {"22", "24"}
    assert external["format-icons"] == {"22": "2", "24": "4", "default": "•"}
    moves = [binding for group in value["bindings"] for binding in group["binds"]
             if binding["act"].startswith("exec,hwc-workspace-switch --move ")]
    assert [row["key"] for row in moves] == ["2", "4"]
    directory = root / "workspace"
    directory.mkdir()
    (directory / "hwc-workspace-link").touch()
    log = directory / "dispatch.log"
    monitors = directory / "monitors.json"
    hyprctl = executable(directory / "hyprctl", "#!" + sys.executable + "\n"
        + "import os,pathlib,sys\n"
        + "if sys.argv[1]=='monitors': print(pathlib.Path(os.environ['PROBE_MONITORS']).read_text())\n"
        + "else:\n with open(os.environ['PROBE_LOG'],'a') as f: f.write(' '.join(sys.argv[1:])+'\\n')\n")
    script = directory / "switch"
    script.write_text(re.sub(r"/nix/store/[^ /]+/bin/hyprctl", hyprctl, value["script"]))
    env = os.environ | dict(XDG_RUNTIME_DIR=str(directory), PROBE_LOG=str(log), PROBE_MONITORS=str(monitors))
    for focused in ("eDP-1", "DP-2"):
        monitors.write_text(json.dumps([dict(name=name, make="fixture", focused=name == focused)
                                       for name in ("eDP-1", "DP-2")]))
        log.write_text("")
        run(["bash", str(script), "2"], env=env)
        dispatch = log.read_text()
        assert "workspace='2'" in dispatch and "workspace='22'" in dispatch, dispatch
    assert run(["bash", str(script), "1"], env=env, check=False).returncode == 64
    log.write_text("")
    run(["bash", str(script), "--move", "4"], env=env)
    assert log.read_text().splitlines() == ["dispatch hl.dsp.window.move({workspace='24',follow=false})"]


if __name__ == "__main__":
    data = json.loads(Path(sys.argv[1]).read_text())
    with tempfile.TemporaryDirectory(prefix="home-untangle-") as temporary:
        root = Path(temporary)
        activation(data, root)
        browsers(data, root)
        workspaces(data, root)
    print("home consumers: activation lanes, browser VAAPI and workspace overrides pass")
