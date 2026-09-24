"""Contract checks against the emitted server configuration and alert rules."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

import onnx
from PIL import Image, ImageDraw


fixture = json.loads(Path(sys.argv[1]).read_text())
config = fixture["settings"]
spec = importlib.util.spec_from_file_location("labelmap", sys.argv[2])
labelmap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(labelmap)

# The actual service must regenerate labels, require config before start, and
# restart the container when its YAML changes. Testing the helper alone misses
# the old create-only-if-absent bug.
assert sys.argv[2] in fixture["configScript"]
assert "if [ ! -f" not in fixture["configScript"]
assert "cat /run/agenix" not in fixture["configScript"]
assert len(fixture["credentials"]) == 5
assert "frigate-config.service" in fixture["requires"]
assert fixture["configTemplate"] in fixture["restartTriggers"]
assert fixture["port"] == 5000
assert not fixture["ports"]
assert "--sdnotify=healthy" in fixture["extraOptions"]
assert fixture["startupTimeout"] == 120
assert not any(v.endswith(":/tmp/frigate") for v in fixture["volumes"])
assert not fixture["exporterPresent"]
native = [s for s in fixture["scrapes"] if s["job_name"] == "frigate"]
assert len(native) == 1 and native[0]["metrics_path"] == "/api/metrics"

assert config["record"]["retain"] == {"days": 3, "mode": "motion"}
assert config["record"]["alerts"]["retain"]["days"] == 14
assert config["record"]["detections"]["retain"]["days"] == 14
assert "reolink_record" not in config["go2rtc"]["streams"]
assert config["cameras"]["reolink"]["ffmpeg"]["inputs"][1]["path"].endswith("/reolink")

masks = {}
for name, camera in config["cameras"].items():
    width, height = camera["detect"]["width"], camera["detect"]["height"]
    mask = Image.new("L", (width, height), 255)
    draw = ImageDraw.Draw(mask)
    for polygon in camera["motion"]["mask"]:
        xy = [float(x) for x in polygon.split(",")]
        assert len(xy) >= 6 and len(xy) % 2 == 0, (name, polygon)
        points = list(zip(xy[::2], xy[1::2]))
        area = abs(sum(x*y2-x2*y for (x,y),(x2,y2) in zip(points,points[1:]+points[:1])))/2
        assert area > 0, (name, polygon)
        draw.polygon(points, fill=0)
    masks[name] = mask
# Road motion is excluded; sidewalk, yard, porch arrival and gate remain visible.
for name, xy, value in [
    ("cobra_cam_1", (600,100), 0),
    ("cobra_cam_1", (600,220), 255),
    ("cobra_cam_1", (600,400), 255),
    ("cobra_cam_3", (700,680), 255),
    ("reolink", (300,170), 255),
]:
    assert masks[name].getpixel(xy) == value, (name,xy)

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    model_path, labels_path = root/"model.onnx", root/"labels.txt"
    labels_path.write_text("stale\n"*90)
    names = {i: f"class {i}" for i in range(80)}
    names.update({0:"person",15:"cat",16:"dog",17:"horse"})
    output = onnx.helper.make_tensor_value_info("output", onnx.TensorProto.FLOAT, [1,84,2100])
    model = onnx.helper.make_model(onnx.helper.make_graph([], "fixture", [], [output]))
    onnx.helper.set_model_props(model, {"names": repr(names)})
    onnx.save(model, model_path)
    labelmap.write_labels(model_path, labels_path)
    expected = "\n".join(names.values())+"\n"
    assert labels_path.read_text() == expected
    labelmap.write_labels(model_path, labels_path)
    assert labels_path.read_text() == expected
    for bad in [{1:"missing zero"}, {**names,80:"extra"}, {**names,0:"bad\nlabel"}]:
        onnx.helper.set_model_props(model, {"names":repr(bad)})
        onnx.save(model, model_path)
        try:
            labelmap.write_labels(model_path, labels_path)
        except ValueError:
            pass
        else:
            raise AssertionError("invalid model accepted")
        assert labels_path.read_text() == expected
    assert not list(root.glob(".labels-*"))

# Promtool executes production expressions, including config-derived recording
# rules. Fixtures cover outages beyond the old daily-history guard and absent
# metrics; disabled cameras do not create camera alerts.
rules = fixture["rules"]
for text in fixture["configurationRules"]:
    rules["groups"].extend(json.loads(text)["groups"])
Path("rules.json").write_text(json.dumps(rules))
def series(name, values):
    return {"series":name,"values":values}
def check(alert, minute, labels=None):
    samples = [] if labels is None else [{"labels": 'ALERTS{'+','.join(
        f'{k}="{v}"' for k,v in sorted({"alertname":alert,"alertstate":"firing", **labels}.items()))+'}', "value":1}]
    return {"expr":f'ALERTS{{alertname="{alert}",alertstate="firing"}}',"eval_time":f"{minute}m","exp_samples":samples}
base = [series('up{job="frigate"}',"1+0x3000"),
        series('frigate_camera_fps{camera_name="cobra_cam_1"}',"3+0x3000"),
        series('frigate_camera_fps{camera_name="cobra_cam_2"}',"0+0x3000"),
        series('frigate_camera_fps{camera_name="reolink"}',"2+0x3000")]
labels = {"camera_name":"cobra_cam_3","category":"frigate","severity":"P4"}
tests = [
    {"name":"48-hour outage including cold start", "interval":"1m",
     "input_series":base+[series('frigate_camera_fps{camera_name="cobra_cam_3"}',"0+0x3000")],
     "promql_expr_test":[check("FrigateCameraOffline",4),check("FrigateCameraOffline",6,labels),check("FrigateCameraOffline",2880,labels)]},
    {"name":"stable recovery required", "interval":"1m",
     "input_series":base+[series('frigate_camera_fps{camera_name="cobra_cam_3"}',"0+0x10 3 0 3+0x20")],
     "promql_expr_test":[check("FrigateCameraOffline",11,labels),check("FrigateCameraOffline",16,labels),check("FrigateCameraOffline",19)]},
    {"name":"missing configured camera", "interval":"1m", "input_series":base,
     "promql_expr_test":[check("FrigateCameraMetricsMissing",6,labels),check("FrigateCameraOffline",6)]},
    {"name":"scrape down is not missing camera", "interval":"1m",
     "input_series":[series('up{job="frigate"}',"0+0x20")],
     "promql_expr_test":[check("FrigateCameraMetricsMissing",6),check("FrigateMetricsUnavailable",6,{"job":"frigate","category":"frigate","severity":"P4"})]},
    {"name":"scrape target absent", "interval":"1m", "input_series":[],
     "promql_expr_test":[check("FrigateMetricsUnavailable",6,{"job":"frigate","category":"frigate","severity":"P4"})]},
    {"name":"healthy and intentionally disabled", "interval":"1m",
     "input_series":base+[series('frigate_camera_fps{camera_name="cobra_cam_3"}',"3+0x3000")],
     "promql_expr_test":[check("FrigateCameraOffline",30),check("FrigateCameraMetricsMissing",30),check("FrigateLowFPS",30)]},
    {"name":"sustained degraded FPS", "interval":"1m",
     "input_series":base+[series('frigate_camera_fps{camera_name="cobra_cam_3"}',"1+0x3000")],
     "promql_expr_test":[check("FrigateLowFPS",2880,{**labels,"severity":"P3"})]},
]
Path("tests.json").write_text(json.dumps({"rule_files":["rules.json"],"evaluation_interval":"1m","tests":tests}))
subprocess.run(["promtool","test","rules","tests.json"],check=True)
print("PASS Frigate emitted config, model regeneration, coverage points and outage rules")
