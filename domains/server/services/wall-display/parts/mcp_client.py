"""Streamable HTTP sessions shared by the phone and voice adapters.

Authorization and result interpretation stay with each consumer. Tool calls
are non-retriable: a lost response does not prove that a write failed.
"""
import json
import urllib.error
import urllib.request

PROTOCOL = "2025-06-18"


class GatewayError(RuntimeError):
    pass


class McpSession:
    def __init__(self, url, *, timeout, client):
        self.url, self.timeout = url, timeout
        self.sid, self.seq, self.closed = None, 0, False
        self.protocol = PROTOCOL
        try:
            init = self.rpc("initialize", {"protocolVersion": self.protocol, "capabilities": {},
                                          "clientInfo": {"name": client, "version": "1"}})
            self.protocol = init.get("protocolVersion", self.protocol)
            self.rpc("notifications/initialized", {})
        except BaseException:
            self.close()
            raise

    def rpc(self, method, params):
        if self.closed:
            raise GatewayError("gateway session is closed")
        body = {"jsonrpc": "2.0", "method": method, "params": params}
        note = method.startswith("notifications/")
        if not note:
            self.seq += 1
            body["id"] = self.seq
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                   "MCP-Protocol-Version": self.protocol}
        if self.sid:
            headers["Mcp-Session-Id"] = self.sid
        req = urllib.request.Request(self.url, data=json.dumps(body).encode(), headers=headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as reply:
                self.sid = reply.headers.get("Mcp-Session-Id") or self.sid
                ctype = reply.headers.get("Content-Type", "")
                raw = reply.read().decode(errors="replace")
        except urllib.error.HTTPError as exc:
            raise GatewayError(f"gateway HTTP {exc.code}") from exc
        except OSError as exc:
            raise GatewayError(f"gateway unreachable: {exc}") from exc
        if note:
            return None
        try:
            if "text/event-stream" in ctype:
                messages, data = [], []
                for line in [*raw.splitlines(), ""]:
                    if line.startswith("data:"):
                        data.append(line[5:].removeprefix(" "))
                    elif not line and data:
                        try:
                            messages.append(json.loads("\n".join(data)))
                        except ValueError:
                            pass
                        data = []
            else:
                messages = [json.loads(raw)]
        except ValueError as exc:
            raise GatewayError(f"invalid gateway reply to {method}") from exc
        msg = next((m for m in messages if isinstance(m, dict)
                    and not isinstance(m.get("id"), bool) and m.get("id") == body["id"]), None)
        if msg is None:
            raise GatewayError(f"no gateway reply to {method}")
        if msg.get("error"):
            raise GatewayError(msg["error"].get("message") or "gateway error")
        if not isinstance(msg.get("result"), dict):
            raise GatewayError(f"invalid gateway result for {method}")
        return msg["result"]

    def close(self):
        self.closed = True
        sid, self.sid = self.sid, None
        if sid:
            try:
                request = urllib.request.Request(self.url, method="DELETE", headers={"Mcp-Session-Id": sid})
                urllib.request.urlopen(request, timeout=5).close()
            except OSError:
                pass  # The server also reaps abandoned sessions; never replay an action.
