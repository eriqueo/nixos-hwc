#!/usr/bin/env python3
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = int(os.environ.get("API_PORT", "5000"))

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        video_id = self.path.lstrip("/") or "unknown"
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"video_id": video_id, "transcript": []}).encode())

if __name__ == "__main__":
    server = HTTPServer(("", PORT), Handler)
    server.serve_forever()
