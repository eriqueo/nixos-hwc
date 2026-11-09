"""Exercise generated production shell commands against one local HTTP fixture."""
import http.server
import json
import os
import subprocess
import sys
import threading

class Handler(http.server.BaseHTTPRequestHandler):
    calls = 0
    status = 200
    payload = b""
    def do_POST(self):
        type(self).calls += 1
        assert self.path == "/notify"
        json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self.send_response(type(self).status)
        self.end_headers()
        self.wfile.write(type(self).payload)
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = threading.Thread(target=server.serve_forever, daemon=True)
thread.start()
port = server.server_port
cases = [
    (200, {"attempted": 2, "succeeded": 2, "failed": 0}, True),
    (207, {"attempted": 2, "succeeded": 1, "failed": 1}, False),
    (502, {"attempted": 2, "succeeded": 0, "failed": 2}, False),
    (202, {"attempted": 0, "succeeded": 0, "failed": 0}, False),
    (200, {"attempted": 2, "succeeded": 1, "failed": 1}, False),
    (400, {"code": "VALIDATION_ERROR"}, False),
    (200, {"attempted": "2", "succeeded": "2", "failed": 0}, False),
    (200, "malformed", False),
]
try:
    for command in ([sys.argv[1], f"http://127.0.0.1:{port}", "2"],
                    [sys.argv[2], "fixture", "test body"]):
        for status, payload, success in cases:
            Handler.status = status
            Handler.payload = (json.dumps(payload) if isinstance(payload, dict) else payload).encode()
            before = Handler.calls
            result = subprocess.run(command, input='{"topic":"test","title":"fixture"}',
                text=True, capture_output=True, timeout=5,
                env={**os.environ, "NOTIFY_TEST_PORT": str(port)})
            assert (result.returncode == 0) == success, (command, status, payload, result)
            assert Handler.calls == before + 1, "one attempt, never retry partial delivery"
            if not success:
                assert "Alert sent:" not in result.stdout
    print("16 generated CLI delivery cases passed")
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=2)
