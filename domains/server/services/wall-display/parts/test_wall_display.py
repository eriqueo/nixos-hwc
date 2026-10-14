"""Run with Python + icalendar + segno; no network or user data required.

server.py is the production entry point, so it cannot own this standalone
test entry point without mixing fixture setup into service startup.
"""
import datetime as dt
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from http.server import ThreadingHTTPServer

fixture = tempfile.TemporaryDirectory()
root = Path(fixture.name)
(root / "framework/icons").mkdir(parents=True)
specs = {name: dict(width=w, height=h, grays=16, scale=scale, voice=False,
                   refreshRate=900, playlist=["home", "week", "weather", "tasks", "groceries"])
         for name, w, h, scale in [("ipad", 2048, 1536, 2.56), ("fire-hd8", 1280, 800, 1.6)]}
config = dict(port=8424, stateDir=str(root), assets=str(root), devices=specs,
              crispFontsConf=str(root / "fonts"), timeZone="America/Denver",
              radicale=dict(url="http://invalid", user="fixture", htpasswdFile=str(root / "password")),
              noaa=dict(point="45,-111", place="Bozeman", userAgent="test"),
              taskLists=dict(family="Family", groceries="Groceries"),
              links=dict(home="https://calendar.test/?add=1", week="https://calendar.test/?add=1",
                         groceries="https://todo.test/groceries"), apps=dict(gatewayUrl="http://invalid", paths=dict(groceries="/groceries")))
(root / "config.json").write_text(json.dumps(config))
os.environ["WALL_CONFIG"] = str(root / "config.json")
import screens
import apps
import server


class DisplayContract(unittest.TestCase):
    def test_home_filters_before_ranking_and_counting(self):
        now = dt.datetime(2026, 10, 14, 12, tzinfo=screens.TZ)
        def task(title, list_, day):
            return dict(summary=title, list=list_, due_day=day, due=day, priority=1)
        data = dict(open=[task("Business secret", "hwc", now.date() - dt.timedelta(days=4)),
                          task("Family chore", "Family", now.date()),
                          task("Buy milk", "Groceries", None)], done=[])
        with patch.object(screens.calendar, "get", return_value={"events": []}), \
             patch.object(screens.weather, "get", return_value={}), \
             patch.object(screens.todo, "get", return_value=data):
            html = screens.home(now, specs["ipad"])
            self.assertIn("Family chore", html)
            self.assertNotIn("Business secret", html)
            self.assertNotIn("Buy milk", html)
            self.assertNotIn("overdue", html)
            self.assertIn("Today · Oct 14", html)
            self.assertIn("Tomorrow · Oct 15", html)
            self.assertIn("Add calendar event", html)

    def test_groceries_uses_existing_list(self):
        data = dict(open=[dict(summary="Milk", list="Groceries"), dict(summary="Family chore", list="Family")])
        with patch.object(screens.todo, "get", return_value=data):
            html = screens.groceries(dt.datetime.now(screens.TZ), specs["ipad"])
        self.assertIn("Milk", html)
        self.assertNotIn("Family chore", html)
        self.assertIn("Add grocery items", html)

    def test_multiday_validator_and_restore_preserve_end(self):
        body = dict(summary="Family trip", calendar="Family", date="2026-11-01",
                    endDate="2026-11-03", startTime="18:00", endTime="09:00", allday=False)
        args = apps.event_fields(body, [dict(name="Family", writable=True)])
        self.assertEqual(args["endDate"], "2026-11-03")
        original = dict(body, calName="Family", location="", description="")
        self.assertEqual(apps.as_create(original)["endDate"], "2026-11-03")
        with self.assertRaises(apps.Invalid):
            apps.event_fields(dict(body, endDate="2026-10-31"), [dict(name="Family", writable=True)])

    def test_post_notifies_renderer_only_after_success(self):
        from types import SimpleNamespace
        notify = unittest.mock.Mock()
        app = apps.TasksApp(notify)
        handler = SimpleNamespace(refuse_unless_tailnet=lambda: False,
                                  headers={"Content-Type": "application/json"},
                                  read_body=lambda _: b'{"summary":"Milk","list":"Groceries"}',
                                  json=unittest.mock.Mock())
        with patch.dict(app.writes, {"/api/add": lambda h, b: {"ok": True}}):
            app.post(handler, "/api/add")
        notify.assert_called_once()
        notify.reset_mock()
        def refused(h, b):
            raise apps.Invalid("bad request")
        with patch.dict(app.writes, {"/api/add": refused}):
            app.post(handler, "/api/add")
        notify.assert_not_called()

    def test_write_expires_caches_and_coalesces_render_wake(self):
        screens.calendar.at = screens.todo.at = 123
        server.renderer.changed()
        server.renderer.changed()
        self.assertEqual(screens.calendar.at, 0)
        self.assertEqual(screens.todo.at, 0)
        self.assertTrue(server.renderer.wake.is_set())

    def test_calendar_sync_failure_is_visible_without_a_second_wait(self):
        with patch.object(apps, "read_events", return_value=([dict(name="Family", writable=True)], [])), \
             patch.object(apps, "gateway_call", return_value={"message": "local change saved; sync failed", "data": {"syncComplete": False}}), \
             patch.object(apps, "wait_until") as wait, \
             patch.object(apps, "agenda", return_value={}):
            result = apps.cal_create(None, dict(summary="Family trip", calendar="Family", date="2026-11-01", allday=True))
        wait.assert_not_called()
        self.assertFalse(result["synced"])
        self.assertIn("sync failed", result["message"])

    def test_image_endpoint_does_not_change_rotation(self):
        http = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
        thread = threading.Thread(target=http.serve_forever, daemon=True)
        thread.start()
        before = {n: (d.cursor, d.seen) for n, d in server.devices.items()}
        try:
            target = ("groceries", 2048, 1536, 16)
            server.renderer.current[target] = "groceries-2048x1536g16-0123456789abcdef.png"
            with urlopen(f"http://127.0.0.1:{http.server_port}/device/ipad/images/groceries") as r:
                self.assertEqual(json.load(r)["image"], "/images/" + server.renderer.current[target])
            with self.assertRaises(HTTPError) as raised:
                urlopen(f"http://127.0.0.1:{http.server_port}/device/ipad/images/unknown")
            self.assertEqual(raised.exception.code, 404)
            raised.exception.close()
            self.assertEqual(before, {n: (d.cursor, d.seen) for n, d in server.devices.items()})
            server.renderer.wake.clear()
            screens.calendar.at = screens.todo.at = 123
            request = Request(f"http://127.0.0.1:{http.server_port}/api/add", data=b'{"summary":"Milk","list":"Groceries"}',
                              headers={"Host": "todo.test", "X-Real-IP": "100.64.0.1", "Content-Type": "application/json"})
            with patch.dict(server.HOST_APPS["todo"].writes, {"/api/add": lambda h, b: {"ok": True}}):
                with urlopen(request) as r:
                    self.assertTrue(json.load(r)["ok"])
            self.assertEqual(screens.todo.at, 0)
            self.assertTrue(server.renderer.wake.is_set())
        finally:
            http.shutdown()
            http.server_close()
            thread.join()


if __name__ == "__main__":
    try:
        unittest.main()
    finally:
        fixture.cleanup()
