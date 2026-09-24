"""Exercise the generated bridge with a local MQTT broker and HTTP sink."""
import json
from pathlib import Path
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

received = []
class Sink(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_POST(self):
        data = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        event = data["after"]["id"]
        received.append(event)
        if event == "timeout":
            time.sleep(18)
        self.send_response(503 if event == "failure" else 200)
        self.end_headers()

def wait_for(predicate, timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError("deadline expired")

server = ThreadingHTTPServer(("127.0.0.1", 18386), Sink)
threading.Thread(target=server.serve_forever, daemon=True).start()
broker = subprocess.Popen(["mosquitto", "-p", "18884"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def ready():
    try:
        with socket.create_connection(("127.0.0.1",18884), timeout=0.1):
            return True
    except OSError:
        return False
bridge = None
try:
    wait_for(ready, 3)
    with open("bridge.log", "w") as log:
        bridge = subprocess.Popen([sys.argv[1]], stdout=log, stderr=log)
        time.sleep(0.5)
        for event_type,event_id in [("update","ignored"),("end","failure"),("end","timeout"),("end","success")]:
            subprocess.run(["mosquitto_pub","-h","127.0.0.1","-p","18884","-t","fixture/events","-m",json.dumps({"type":event_type,"after":{"id":event_id}})],check=True)
        wait_for(lambda: 'event="success" outcome=accepted' in Path("bridge.log").read_text(), 20)
    text = Path("bridge.log").read_text()
    assert received == ["failure", "timeout", "success"], received
    assert 'event="failure" outcome=failed http=503' in text, text
    assert 'event="timeout" outcome=failed http=000 curl_exit=28 retry=false' in text, text
    print("PASS bridge: update filtering, HTTP failures, bounded timeout, continued forwarding and no retries")
finally:
    if bridge:
        bridge.terminate()
        bridge.wait(timeout=3)
    broker.terminate()
    broker.wait(timeout=3)
    server.shutdown()
