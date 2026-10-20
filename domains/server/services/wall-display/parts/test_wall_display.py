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
                   refreshRate=900, playlist=["home", "week", "weather", "tasks", "groceries", "month"])
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
    def test_cooking_proxy_is_readonly_bounded_and_does_not_rotate(self):
        from http.server import BaseHTTPRequestHandler
        class Meals(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path.startswith('/cooking/dates/'):
                    self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers()
                    self.wfile.write(b'<html><head></head><body>Meals</body></html>'); return
                self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
                self.wfile.write(b'x' * (server.COOKING_LIMIT+1) if self.path.endswith('/large') else b'{"schemaVersion":1}')
            def log_message(self,*args): pass
        upstream=ThreadingHTTPServer(('127.0.0.1',0),Meals)
        http=ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
        threads=[threading.Thread(target=h.serve_forever,daemon=True) for h in (upstream,http)]
        for t in threads:t.start()
        before={n:d.cursor for n,d in server.devices.items()}
        try:
            with patch.dict(server.CONFIG,meals=dict(readUrl=f'http://127.0.0.1:{upstream.server_port}')):
                url=f'http://127.0.0.1:{http.server_port}'
                with urlopen(url+'/cooking/api/dinners/fixture') as r:self.assertEqual(json.load(r)['schemaVersion'],1)
                with self.assertRaises(HTTPError) as raised:urlopen(Request(url+'/cooking/api/dinners/fixture',headers={'X-Real-IP':'192.168.1.2'}))
                self.assertEqual(raised.exception.code,403);raised.exception.close()
                for path,code in [('/cooking/api/state',404),('/cooking/assets/../server.py',404),('/cooking/api/dinners/large',503)]:
                    with self.assertRaises(HTTPError) as raised:urlopen(url+path)
                    self.assertEqual(raised.exception.code,code);raised.exception.close()
                with self.assertRaises(HTTPError) as raised:urlopen(Request(url+'/cooking/api/dinners/fixture',data=b'{}'))
                self.assertEqual(raised.exception.code,404);raised.exception.close()
                for _ in range(server.COOKING_CAPACITY):server.COOKING_SLOTS.acquire()
                try:
                    with self.assertRaises(HTTPError) as raised:urlopen(url+'/cooking/api/dinners/fixture')
                    self.assertEqual(raised.exception.code,503);raised.exception.close()
                finally:
                    for _ in range(server.COOKING_CAPACITY):server.COOKING_SLOTS.release()
                with urlopen(url+'/cooking/dates/2026-10-16?device=ipad') as r:
                    wrapped = r.read().decode()
                    self.assertIn(server.COOKING_STYLE_HASHES, r.headers["Content-Security-Policy"])
                self.assertIn('aria-label="Wall pages"', wrapped)
                self.assertIn('>Month</a>', wrapped)
                self.assertIn('Open Meals on your phone', wrapped)
                with urlopen(url+'/cooking/dates/2026-10-16') as r:
                    self.assertNotIn('Wall pages', r.read().decode())
                controls=server.wall_controls('ipad','home',dt.datetime(2026,10,16,tzinfo=screens.TZ))
                self.assertIn('/cooking/dates/2026-10-16?device=ipad',controls)
                self.assertIn('>Meals</a>',controls)
                self.assertIn('>Tasks</a>', server.wall_controls('ipad','weather',dt.datetime.now(screens.TZ)))
                with patch.object(server.COOKING_HTTP,'open',side_effect=TimeoutError):
                    with self.assertRaises(HTTPError) as raised:urlopen(url+'/cooking/api/dinners/fixture')
                    self.assertEqual(raised.exception.code,503);raised.exception.close()
            self.assertEqual(before,{n:d.cursor for n,d in server.devices.items()})
        finally:
            for h in (http,upstream):h.shutdown();h.server_close()
            for t in threads:t.join()

    def test_byos_rotation_still_returns_next_image(self):
        handler = object.__new__(server.Handler)
        handler.headers = {'ID': 'fixture', 'access-token': 'secret'}
        device = server.devices['ipad']; before = device.cursor
        with patch.dict(server.BY_ID, fixture='ipad'), patch.object(server, 'load_keys', return_value={'fixture': 'secret'}), patch.object(server.Handler, 'url', return_value='https://wall.test/images/fixture.png'), patch.object(server.renderer, 'image', return_value='fixture.png'), patch.object(server.Handler, 'json') as send:
            handler.byos_display()
        self.assertEqual(device.cursor, before + 1)
        self.assertEqual(send.call_args.args[0], 200)

    def test_fixed_scene_navigation_does_not_rotate_and_has_bar(self):
        http = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        thread = threading.Thread(target=http.serve_forever, daemon=True); thread.start()
        before = server.devices['ipad'].cursor
        try:
            with patch.object(server.renderer, 'image', return_value='fixture.png'):
                for scene in ('home', 'tasks', 'week', 'month'):
                    with urlopen(f'http://127.0.0.1:{http.server_port}/device/ipad/scenes/{scene}') as r:
                        page = r.read().decode()
                    for label in ('Home', 'Tasks', 'Events', 'Month'):
                        self.assertIn('>' + label + '</a>', page)
                    self.assertIn(f'url=/device/ipad/scenes/{scene}', page)
                    self.assertIn('aria-current="page"', page)
                    self.assertIn('class="prev"', page)
                self.assertEqual(server.devices['ipad'].cursor, before)
                with self.assertRaises(HTTPError) as raised:
                    urlopen(f'http://127.0.0.1:{http.server_port}/device/ipad/scenes/unknown')
                self.assertEqual(raised.exception.code, 404); raised.exception.close()
        finally:
            http.shutdown(); http.server_close(); thread.join()

    def test_month_range_grid_overflow_and_today(self):
        now = dt.datetime(2026, 10, 20, 12, tzinfo=screens.TZ)
        def event(title, start, end):
            return dict(summary=title, start=start, end=end, allday=True, meal=False)
        events = [event('Trip', dt.date(2026, 9, 30), dt.date(2026, 10, 3))]
        events += [event(f'Event {i}', now.date(), now.date()+dt.timedelta(days=1)) for i in range(6)]
        with patch.object(screens.month_calendar, 'get', return_value={'events': events}) as source:
            page = screens.month(now, specs['ipad'])
        source.assert_called_once_with((dt.date(2026, 9, 28), dt.date(2026, 11, 2)))
        self.assertIn('October 2026', page)
        self.assertEqual(page.count('class="w-monthday'), 35)
        self.assertIn('aria-label="Today, October 20"', page)
        self.assertIn('Trip', page)
        self.assertIn('more', page)
        for year, month, days in [(2024, 2, 29), (2026, 2, 28), (2026, 12, 31)]:
            first, end = screens.month_range(dt.date(year, month, 15))
            self.assertEqual(first.weekday(), 0); self.assertEqual(end.weekday(), 0)
            self.assertLessEqual(first, dt.date(year, month, 1))
            self.assertGreater(end, dt.date(year, month, days))
            self.assertLessEqual((end-first).days, 42)

    def test_event_loader_uses_explicit_exclusive_range(self):
        with patch.object(screens, 'collections', return_value=[('/family/', 'Family')]), patch.object(screens, 'components', return_value=[]) as components:
            screens.load_events((dt.date(2026, 9, 28), dt.date(2026, 11, 2)))
        query = components.call_args.args[1]
        self.assertIn('20260928T060000Z', query)
        self.assertIn('20261102T070000Z', query)

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

    def test_managed_dinner_is_shown_once_without_hiding_unrelated_event(self):
        now = dt.datetime(2026, 10, 14, 12, tzinfo=screens.TZ)
        meal = dict(summary="Dinner: Soup", start=now.date(), end=now.date()+dt.timedelta(days=1), allday=True, calendar="Meals", uid="meal-dinner-a", meal=True)
        other = dict(meal, summary="Family appointment", calendar="Family", uid="unrelated", meal=False)
        with patch.object(screens.calendar, "get", return_value={"events": [meal, other]}), patch.object(screens.weather, "get", return_value={}), patch.object(screens.todo, "get", return_value={"open": []}):
            for render in (screens.home, screens.week):
                output = render(now, specs["ipad"])
                self.assertEqual(output.count('Soup'), 1)
                self.assertIn('Family appointment', output)
                self.assertIn('w-dinner', output)

    def test_managed_event_never_reaches_legacy_delete_create(self):
        ev = dict(uid="meal-dinner-a", cal="meals", date="2026-10-14", mealUrl="https://meals.test/meals/a")
        with patch.object(apps, "read_events", return_value=([], [ev])), patch.object(apps, "gateway_call") as gateway:
            with self.assertRaises(apps.Invalid):apps.locate(ev)
            gateway.assert_not_called()

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

    def test_repeat_form_validation_and_gateway_wiring(self):
        fields = dict(summary="Family event", calendar="Family", date="2026-10-14",
                      allday=True, repeat="weekly", repeatUntil="2026-11-30")
        args = apps.event_fields(fields, [dict(name="Family", writable=True)])
        self.assertEqual((args["repeat"], args["until"]), ("weekly", "2026-11-30"))
        with self.assertRaises(apps.Invalid):
            apps.repeat_fields(dict(repeat="weekly"), None)
        with self.assertRaises(apps.Invalid):
            apps.repeat_fields(dict(repeat="monthly", repeatUntil="2026-01-01"), "2026-10-14")
        with patch.object(apps, "task_lists", return_value=[("/family/", "Family")]), \
             patch.object(apps, "tasks_state", return_value={}), \
             patch.object(apps, "gateway_call", return_value={}) as gateway:
            apps.task_add(None, dict(summary="Laundry", list="Family", due="2026-10-14", repeat="weekly"))
            self.assertEqual(gateway.call_args.args[1]["recurrence"], dict(frequency="weekly", startDate="2026-10-14"))
        with patch.object(apps, "find_task", return_value=dict(due="2026-10-14")), \
             patch.object(apps, "tasks_state", return_value={}), \
             patch.object(apps, "gateway_call", return_value={}) as gateway:
            apps.task_update(None, dict(uid="fixture", action="complete", expectedDue="2026-10-14"))
            self.assertEqual(gateway.call_args.args[1]["expectedDue"], "2026-10-14")
        self.assertIn('id="a-repeat-controls"', apps.TASKS_BODY)
        self.assertNotIn("@@REPEATS@@", apps.COMMON_JS)

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
