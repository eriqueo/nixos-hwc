"""Tests for transcript sourcing and the Whisper fallback decision.

Run with the service's interpreter (needs fastapi + youtube-transcript-api):
    PYTHONPATH=<service pythonPath>:. python3 -m unittest -v test_transcript
"""

import asyncio
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

os.environ["YT_TRANSCRIPTS_WHISPER_URL"] = "http://whisper.test/v1/audio/transcriptions"
os.environ["YT_TRANSCRIPTS_WHISPER_MAX_SECONDS"] = "3600"

import transcript as T  # noqa: E402

try:
    import api  # noqa: E402
except ImportError:  # fastapi absent outside the service environment
    api = None

YTDLP_429 = (
    "[info] ABeo1kKueRs: Writing video subtitles to: /tmp/x/sub.en.vtt\n"
    "ERROR: Unable to download video subtitles for 'en': HTTP Error 429: Too Many Requests\n"
)


def run(coro):
    return asyncio.run(coro)


class ClassifyYtdlp(unittest.TestCase):
    def test_429_is_rate_limited(self):
        e = T.classify_ytdlp_error(YTDLP_429)
        self.assertEqual(e.reason, "rate_limited")
        self.assertIn("429", e.detail)

    def test_bot_check_is_rate_limited(self):
        self.assertEqual(T.classify_ytdlp_error("ERROR: Sign in to confirm you're not a bot").reason, "rate_limited")

    def test_age_gate_is_unavailable(self):
        self.assertEqual(T.classify_ytdlp_error("ERROR: Sign in to confirm your age").reason, "unavailable")

    def test_removed_is_unavailable(self):
        # Exact yt-dlp 2026.08.19 wording, seen live on 2026-10-06.
        e = T.classify_ytdlp_error("ERROR: [youtube] aaaaaaaaaaa: This video is unavailable")
        self.assertEqual(e.reason, "unavailable")

    def test_private_is_unavailable(self):
        self.assertEqual(T.classify_ytdlp_error("ERROR: [youtube] x: Private video").reason, "unavailable")

    def test_unknown_is_error(self):
        self.assertEqual(T.classify_ytdlp_error("ERROR: something new").reason, "error")


class Reasons(unittest.TestCase):
    def test_vocabulary_is_closed(self):
        with self.assertRaises(ValueError):
            T.TranscriptError("nope")

    def test_block_outranks_no_captions(self):
        e = T.most_telling([T.TranscriptError("no_captions"), T.TranscriptError("rate_limited")])
        self.assertEqual(e.reason, "rate_limited")

    def test_unavailable_outranks_all(self):
        e = T.most_telling([T.TranscriptError("rate_limited"), T.TranscriptError("unavailable")])
        self.assertEqual(e.reason, "unavailable")


class WhisperSegments(unittest.TestCase):
    def test_offset_and_non_speech_filter(self):
        result = {"segments": [
            {"text": " Hello there", "start": 1.0, "end": 2.5},
            {"text": " [BLANK_AUDIO]", "start": 3.0, "end": 9.0},
            {"text": " (music)", "start": 9.0, "end": 12.0},
            {"text": "", "start": 12.0, "end": 13.0},
        ]}
        segs = T.whisper_segments(result, offset=180.0)
        self.assertEqual([(s.text, s.start, s.duration) for s in segs], [("Hello there", 181.0, 1.5)])

    def test_word_split_across_segments_is_rejoined(self):
        # Shape seen live on 2026-10-06: "...Cl" / "oning yourself", "I" / "'ve been".
        result = {"segments": [
            {"text": " Cl", "start": 0.0, "end": 0.5},
            {"text": "oning yourself takes", "start": 0.5, "end": 2.0},
            {"text": " a new model I", "start": 2.0, "end": 3.0},
            {"text": "'ve been using", "start": 3.0, "end": 4.0},
        ]}
        segs = T.whisper_segments(result, offset=0.0)
        self.assertEqual(T.raw_transcript(segs), "Cloning yourself takes a new model I've been using")
        self.assertEqual((segs[0].start, segs[0].duration), (0.0, 2.0))


class FetchCaptions(unittest.TestCase):
    def setUp(self):
        T._last_rate_limited = 0.0
        self.sleep = mock.patch.object(T.asyncio, "sleep", new=mock.AsyncMock())
        self.sleep.start()

    def tearDown(self):
        self.sleep.stop()
        T._last_rate_limited = 0.0

    def test_block_then_success_retries_youtube_transcript_api(self):
        good = T.Transcript([T.Segment("hi", 0, 1)], "YouTube captions (manual, en)", "captions")
        yta = mock.Mock(side_effect=[T.TranscriptError("rate_limited"), good])
        with mock.patch.object(T, "_fetch_yta_sync", yta):
            self.assertIs(run(T.fetch_captions("vid", ["en"])), good)
        self.assertEqual(yta.call_count, 2)

    def test_both_sources_fail_reports_block_and_sets_cooldown(self):
        with mock.patch.object(T, "_fetch_yta_sync", side_effect=T.TranscriptError("no_captions")), \
             mock.patch.object(T, "_try_ytdlp_subs", new=mock.AsyncMock(side_effect=T.classify_ytdlp_error(YTDLP_429))):
            with self.assertRaises(T.TranscriptError) as cm:
                run(T.fetch_captions("vid", ["en"]))
        self.assertEqual(cm.exception.reason, "rate_limited")
        self.assertGreater(T._last_rate_limited, 0)

    def test_unavailable_skips_ytdlp(self):
        ytdlp = mock.AsyncMock()
        with mock.patch.object(T, "_fetch_yta_sync", side_effect=T.TranscriptError("unavailable")), \
             mock.patch.object(T, "_try_ytdlp_subs", new=ytdlp):
            with self.assertRaises(T.TranscriptError):
                run(T.fetch_captions("vid", ["en"]))
        ytdlp.assert_not_called()


@unittest.skipIf(api is None, "fastapi not installed")
class ExtractWiring(unittest.TestCase):
    """The production decision point: api._extract chooses captions or Whisper."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.out = Path(self.tmp.name)
        self.meta = T.VideoMeta("abcdefghijk", "A Title", "Chan", 600, "20260101",
                                "https://www.youtube.com/watch?v=abcdefghijk")
        self.whisper = T.Transcript([T.Segment("spoken words", 0, 2)], "Whisper speech-to-text (small.en)", "whisper")

    def tearDown(self):
        self.tmp.cleanup()

    def _extract(self, caption_exc, allow_whisper=True, duration=600):
        self.meta.duration = duration
        audio = mock.AsyncMock(return_value=self.whisper)
        with mock.patch.object(api, "fetch_metadata", new=mock.AsyncMock(return_value=self.meta)), \
             mock.patch.object(api, "fetch_captions", new=mock.AsyncMock(side_effect=caption_exc)), \
             mock.patch.object(api, "transcribe_audio", new=audio):
            result = run(api._extract(self.meta.url, "raw", self.out, allow_whisper=allow_whisper))
        return result, audio

    def test_no_captions_falls_back_to_whisper(self):
        result, audio = self._extract(T.TranscriptError("no_captions"))
        audio.assert_awaited_once()
        self.assertEqual(result["source"], "whisper")
        self.assertIn("**Source:** Whisper", Path(result["filename"]).read_text())

    def test_rate_limited_falls_back_to_whisper(self):
        result, _ = self._extract(T.TranscriptError("rate_limited"))
        self.assertEqual(result["source"], "whisper")

    def test_unavailable_never_uses_whisper(self):
        with self.assertRaises(T.TranscriptError) as cm:
            self._extract(T.TranscriptError("unavailable"))
        self.assertEqual(cm.exception.reason, "unavailable")

    def test_sync_endpoint_path_never_uses_whisper(self):
        with self.assertRaises(T.TranscriptError) as cm:
            self._extract(T.TranscriptError("no_captions"), allow_whisper=False)
        self.assertEqual(cm.exception.reason, "no_captions")

    def test_over_cap_is_too_long(self):
        with self.assertRaises(T.TranscriptError) as cm:
            self._extract(T.TranscriptError("no_captions"), duration=4000)
        self.assertEqual(cm.exception.reason, "too_long")
        self.assertIn("captions: no_captions", cm.exception.detail)


class SavedHeader(unittest.TestCase):
    def test_current_format_round_trips(self):
        meta = T.VideoMeta("abcdefghijk", "T", "C", 60, "", "https://www.youtube.com/watch?v=abcdefghijk")
        self.assertEqual(T.saved_video_id(T.format_markdown(meta, "body", "src")), "abcdefghijk")

    def test_older_list_format(self):
        header = "# Lesson 7\n\n- **Channel**: X\n- **URL**: https://www.youtube.com/watch?v=bvQr6l5qyyU\n"
        self.assertEqual(T.saved_video_id(header), "bvQr6l5qyyU")

    def test_link_in_body_is_ignored(self):
        text = "# T\n\n**Channel:** C\n\n---\n\nsee URL https://youtu.be/zzzzzzzzzzz\n"
        self.assertIsNone(T.saved_video_id(text))


def _md(video_id: str, title: str = "A Title") -> str:
    meta = T.VideoMeta(video_id, title, "C", 60, "", f"https://www.youtube.com/watch?v={video_id}")
    return T.format_markdown(meta, "saved body", "YouTube captions (manual, en)")


@unittest.skipIf(api is None, "fastapi not installed")
class Library(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_scan_finds_nested_files(self):
        nested = self.root / "jake" / "deep"
        nested.mkdir(parents=True)
        (nested / "x.md").write_text(_md("aaaaaaaaaaa"))
        (self.root / "notes.md").write_text("# no link here\n")
        self.assertEqual(api.scan_saved([self.root]), {"aaaaaaaaaaa": nested / "x.md"})

    def test_same_title_different_video_keeps_both(self):
        a = api.write_transcript(self.root, "Same", "aaaaaaaaaaa", _md("aaaaaaaaaaa", "Same"))
        b = api.write_transcript(self.root, "Same", "bbbbbbbbbbb", _md("bbbbbbbbbbb", "Same"))
        self.assertNotEqual(a, b)
        self.assertIn("[bbbbbbbbbbb]", b.name)
        self.assertEqual(T.saved_video_id(a.read_text()), "aaaaaaaaaaa")

    def test_same_video_rewrites_in_place(self):
        a = api.write_transcript(self.root, "Same", "aaaaaaaaaaa", _md("aaaaaaaaaaa", "Same"))
        b = api.write_transcript(self.root, "Same", "aaaaaaaaaaa", _md("aaaaaaaaaaa", "Same"))
        self.assertEqual(a, b)
        self.assertEqual(len(list(self.root.iterdir())), 1)  # no temp file left behind


@unittest.skipIf(api is None, "fastapi not installed")
class JobDedupAndRetry(unittest.TestCase):
    """The production decision points: api._run_job and POST /job/{id}/retry."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.roots = mock.patch.object(api, "OUTPUT_ROOTS", [self.root])
        self.roots.start()
        self.sleep = mock.patch.object(api.asyncio, "sleep", new=mock.AsyncMock())
        self.sleep.start()

    def tearDown(self):
        self.roots.stop()
        self.sleep.stop()
        self.tmp.cleanup()

    def _job(self, urls, extract, items=(), force=False, out_dir=None):
        job = api._new_job(out_dir or self.root)
        with mock.patch.object(api, "_extract", new=extract):
            run(api._run_job(job.job_id, urls, list(items), "raw", out_dir or self.root, force))
        return job

    @staticmethod
    def _ok(url, mode, dest, allow_whisper=False, on_stage=None):
        return {"url": url, "title": "t", "filename": str(dest / "f.md"), "transcript": "x", "source": "captions"}

    def test_saved_video_is_skipped_not_fetched(self):
        (self.root / "old.md").write_text(_md("aaaaaaaaaaa"))
        extract = mock.AsyncMock(side_effect=self._ok)
        job = self._job(["https://youtu.be/aaaaaaaaaaa", "https://youtu.be/bbbbbbbbbbb"], extract)
        self.assertEqual(extract.await_count, 1)
        self.assertEqual(job.results[0]["status"], "exists")
        self.assertEqual(job.results[0]["transcript"], "saved body")

    def test_force_refetches_saved_video(self):
        (self.root / "old.md").write_text(_md("aaaaaaaaaaa"))
        extract = mock.AsyncMock(side_effect=self._ok)
        self._job(["https://youtu.be/aaaaaaaaaaa"], extract, force=True)
        self.assertEqual(extract.await_count, 1)

    def test_same_video_twice_in_one_job_runs_once(self):
        extract = mock.AsyncMock(side_effect=self._ok)
        job = self._job(["https://youtu.be/aaaaaaaaaaa", "https://www.youtube.com/watch?v=aaaaaaaaaaa"], extract)
        self.assertEqual(extract.await_count, 1)
        self.assertEqual(job.total, 1)

    def test_video_in_flight_elsewhere_is_not_started(self):
        api._inflight.add("aaaaaaaaaaa")
        try:
            extract = mock.AsyncMock(side_effect=self._ok)
            job = self._job(["https://youtu.be/aaaaaaaaaaa"], extract)
        finally:
            api._inflight.discard("aaaaaaaaaaa")
        extract.assert_not_awaited()
        self.assertEqual(job.results[0]["status"], "duplicate")

    def test_retry_reruns_only_failures_into_their_original_folder(self):
        dest = self.root / "My Playlist"
        failing = mock.AsyncMock(side_effect=[T.TranscriptError("rate_limited"), self._ok("u", "raw", dest)])
        job = self._job(["not a url"], failing, items=[
            api.WorkItem("https://www.youtube.com/watch?v=aaaaaaaaaaa", dest, "My Playlist"),
            api.WorkItem("https://www.youtube.com/watch?v=bbbbbbbbbbb", dest, "My Playlist"),
        ])
        self.assertEqual(job.retryable, 1)  # invalid URL is not retryable
        self.assertEqual([r.get("retryable") for r in job.results], [False, True, None])

        spec = api._retry_specs[job.job_id]
        self.assertEqual([(i.url[-11:], i.dest, i.playlist) for i in spec.items],
                         [("aaaaaaaaaaa", dest, "My Playlist")])
        again = mock.AsyncMock(side_effect=self._ok)
        bg = mock.Mock()
        resp = run(api.retry_job(job.job_id, bg))
        _, args, _ = bg.add_task.mock_calls[0]
        with mock.patch.object(api, "_extract", new=again):
            run(args[0](*args[1:]))
        again.assert_awaited_once()
        self.assertEqual(again.await_args.args[2], dest)
        self.assertEqual(api._jobs[resp["job_id"]].results[0]["playlist"], "My Playlist")

    def test_retry_of_unknown_job_is_404(self):
        with self.assertRaises(api.HTTPException) as cm:
            run(api.retry_job("nope", mock.Mock()))
        self.assertEqual(cm.exception.status_code, 404)

    def test_sync_endpoint_returns_saved_file(self):
        (self.root / "old.md").write_text(_md("aaaaaaaaaaa"))
        extract = mock.AsyncMock()
        with mock.patch.object(api, "_extract", new=extract):
            res = run(api.post_transcript(api.TranscriptRequest(url="https://youtu.be/aaaaaaaaaaa")))
        extract.assert_not_awaited()
        self.assertEqual(res["status"], "exists")


class LibraryContract(unittest.TestCase):
    """Pins the youtube-transcript-api surface this code calls; the 1.2 upgrade
    removed the classmethods the old code used and every fetch failed silently."""

    def test_instance_api(self):
        try:
            import youtube_transcript_api as yta
        except ImportError:
            self.skipTest("youtube-transcript-api not installed")
        self.assertTrue(callable(getattr(yta.YouTubeTranscriptApi(), "list", None)))
        self.assertTrue(hasattr(yta.Transcript, "is_generated") or "is_generated" in yta.Transcript.__init__.__code__.co_varnames)
        for name in ("RequestBlocked", "PoTokenRequired", "YouTubeRequestFailed", "TranscriptsDisabled",
                     "NoTranscriptFound", "VideoUnavailable", "VideoUnplayable", "AgeRestricted", "InvalidVideoId"):
            self.assertTrue(hasattr(yta, name), name)
        fields = getattr(yta.FetchedTranscriptSnippet, "__dataclass_fields__", {})
        self.assertTrue({"text", "start", "duration"} <= set(fields))


def _raw_post(pid, handle="alice", reply_to=None, text="hello"):
    return {"id_str": pid, "text": text, "created_at": "2026-01-02T03:04:05.000Z",
            "user": {"screen_name": handle, "name": handle.title()},
            "in_reply_to_status_id_str": reply_to, "entities": {}, "favorite_count": 1500}


class XPost(unittest.TestCase):
    def setUp(self):
        import xpost
        self.X = xpost

    def test_post_id_from_url_forms(self):
        for url in ("https://x.com/jack/status/20", "https://twitter.com/jack/status/20?s=46",
                    "https://mobile.twitter.com/jack/statuses/20/photo/1", "https://x.com/i/web/status/20"):
            self.assertEqual(self.X.extract_post_id(url), "20", url)
        self.assertIsNone(self.X.extract_post_id("https://youtu.be/aaaaaaaaaaa"))
        self.assertIsNone(self.X.extract_post_id("https://notx.com/a/status/20"))

    def test_tco_links_expand_and_media_links_drop(self):
        raw = _raw_post("1", text="read https://t.co/a pic https://t.co/m")
        raw["entities"] = {"urls": [{"url": "https://t.co/a", "expanded_url": "https://example.com"}],
                           "media": [{"url": "https://t.co/m"}]}
        self.assertEqual(self.X.normalize(raw)["text"], "read https://example.com pic")

    def test_thread_walk_stops_at_another_author(self):
        posts = {"3": _raw_post("3", reply_to="2", text="third"), "2": _raw_post("2", reply_to="1", text="second"),
                 "1": _raw_post("1", handle="bob", text="not ours")}
        with mock.patch.object(self.X, "fetch_syndication", side_effect=lambda p: posts[p]), \
             mock.patch.object(self.X, "fetch_graphql", return_value=None):
            thread = self.X.fetch_thread("3")
        self.assertEqual([p["id"] for p in thread], ["2", "3"])
        md = self.X.format_markdown(thread, "3")
        self.assertIn("**Source:** X thread (2 posts)", md)
        self.assertIn("1.5K likes", md)
        self.assertEqual(self.X.saved_x_key(md), "x:3")

    def test_unavailable_parent_ends_walk(self):
        def fetch(p):
            if p == "1":
                raise T.TranscriptError("unavailable")
            return _raw_post("2", reply_to="1")
        with mock.patch.object(self.X, "fetch_syndication", side_effect=fetch), \
             mock.patch.object(self.X, "fetch_graphql", return_value=None):
            self.assertEqual(len(self.X.fetch_thread("2")), 1)


FIXTURES = Path(__file__).parent / "fixtures"


class XConversation(unittest.TestCase):
    """Parser + mode selectors over a real logged-in TweetDetail response
    (trimmed). Focal post: FoxxAndCo's reply 2108948824337080592 to @poteto."""
    FOCAL = "2108948824337080592"

    def setUp(self):
        import xpost
        self.X = xpost
        self.conv = xpost.Conversation()
        self.conv.add(json.loads((FIXTURES / "tweet_detail_logged_in.json").read_text()))

    def test_promoted_post_is_dropped(self):
        self.assertNotIn("2092669931368403176", self.conv.posts)

    def test_direct_replies_exclude_ancestors_and_sub_replies(self):
        ids = [p["id"] for p in self.X.direct_replies(self.conv, self.FOCAL)]
        self.assertEqual(len(ids), 6)
        self.assertIn("2108960927093755917", ids)          # poteto's reply
        self.assertNotIn("2109345169770205368", ids)       # a reply to a reply
        self.assertNotIn("2108808972954423578", ids)       # the ancestor

    def test_author_thread_and_author_posts(self):
        below = self.X.author_thread_below(self.conv, self.FOCAL, "FoxxAndCo")
        self.assertEqual(below, [])  # FoxxAndCo answered a reply, not their own post
        own = self.X.author_posts(self.conv, self.FOCAL, "foxxandco")
        self.assertEqual([p["id"] for p in own], ["2109345169770205368"])

    def test_cursors_and_normalized_shape(self):
        self.assertTrue(self.conv.ended)
        self.assertEqual(self.conv.show_more, 1)
        p = self.conv.posts[self.FOCAL]
        self.assertEqual(p["author"]["handle"], "FoxxAndCo")
        self.assertEqual(p["in_reply_to"], "2108808972954423578")
        self.assertTrue(p["created_at"].startswith("2026-"))
        self.assertEqual(set(p), set(self.X.normalize(_raw_post("1")).keys()) - {"_media_links"})

    def test_mode_keys_round_trip_and_old_files_stay_post(self):
        thread = [self.conv.posts[self.FOCAL]]
        replies = self.X.direct_replies(self.conv, self.FOCAL)
        md = self.X.format_markdown(thread, self.FOCAL, "replies", replies, " of 6")
        self.assertEqual(self.X.saved_x_key(md), f"x:{self.FOCAL}:replies")
        self.assertIn("## Replies (6 of 6)", md)
        old = "# t\n\n**URL:** https://x.com/a/status/5\n**Source:** X post\n\n---\n\nbody\n"
        self.assertEqual(self.X.saved_x_key(old), "x:5")


def _gql_tweet(pid, handle, reply_to):
    return {"__typename": "Tweet", "rest_id": pid,
            "core": {"user_results": {"result": {"core": {"name": handle, "screen_name": handle}}}},
            "legacy": {"full_text": f"text {pid}", "created_at": "Sat Oct 10 06:36:53 +0000 2026",
                       "in_reply_to_status_id_str": reply_to, "favorite_count": 1}}


def _page_payload(focal, reply_ids, bottom=True, end=False):
    """One TweetDetail page: each reply as its own conversation module. `end`
    adds X's bottom TimelineTerminateTimeline."""
    entries = [{"entryId": f"conversationthread-{r}", "content": {
        "entryType": "TimelineTimelineModule", "items": [{"entryId": f"conversationthread-{r}-tweet-{r}",
            "item": {"itemContent": {"itemType": "TimelineTweet",
                                     "tweet_results": {"result": _gql_tweet(r, f"u{r}", focal)}}}}]}}
        for r in reply_ids]
    if bottom:
        entries.append({"entryId": "cursor-bottom-1",
                        "content": {"entryType": "TimelineTimelineCursor", "cursorType": "Bottom"}})
    instructions = [{"type": "TimelineAddEntries", "entries": entries}]
    if end:
        instructions.append({"type": "TimelineTerminateTimeline", "direction": "Bottom"})
    return {"data": {"threaded_conversation_with_injections_v2": {"instructions": instructions}}}


class FakePage:
    """Feeds one TweetDetail page every `every` scrolls, the way X's client
    loads them."""
    def __init__(self, conv, pages, url="https://x.com/a/status/1", show_more_pages=(), every=1):
        self.conv, self.pages, self._url = conv, list(pages), url
        self.show_more_pages = list(show_more_pages)
        self.every, self.scrolls = every, 0
        self.seen = 0
        self.clicks = 0

    def _deliver(self, queue):
        if queue:
            self.conv.add(queue.pop(0))
            self.seen += 1

    async def open(self, url):
        self._deliver(self.pages)

    def url(self):
        return self._url

    async def scroll(self):
        self.scrolls += 1
        if self.scrolls % self.every == 0:
            self._deliver(self.pages)

    async def click_show_more(self):
        if not self.show_more_pages:
            return False
        self.clicks += 1
        self._deliver(self.show_more_pages)
        return True

    async def settle(self):
        pass


class XCaptureLoop(unittest.TestCase):
    def setUp(self):
        import xbrowser
        import xpost
        self.B, self.X = xbrowser, xpost

    def _drive(self, page, mode="replies", limit=200, clock=None):
        kw = {"clock": clock} if clock else {}
        return run(self.B.drive(page, page.conv, lambda: page.seen, lambda: False,
                                "1", mode, limit, **kw))

    def test_stops_at_the_reply_limit(self):
        conv = self.X.Conversation()
        pages = [_page_payload("1", [str(i) for i in range(n, n + 10)]) for n in range(10, 200, 10)]
        cap = self._drive(FakePage(conv, pages), limit=25)
        self.assertTrue(cap.hit_limit)
        self.assertGreaterEqual(len(self.X.direct_replies(conv, "1")), 25)

    def test_show_more_then_end_of_conversation(self):
        conv = self.X.Conversation()
        page = FakePage(conv, [_page_payload("1", ["10", "11"], bottom=False)],
                        show_more_pages=[_page_payload("1", ["12"], bottom=False, end=True)])
        cap = self._drive(page)
        self.assertTrue(cap.reached_end)
        self.assertEqual(page.clicks, 1)
        self.assertEqual(len(self.X.direct_replies(conv, "1")), 3)

    def test_slow_pages_are_waited_for_until_x_ends_the_timeline(self):
        # Live 2026-10-12: X sent a page every 3-7 scrolls; 4 stale scrolls cut
        # a capture at 60 replies and called it the end.
        conv = self.X.Conversation()
        pages = [_page_payload("1", [str(i)]) for i in range(10, 15)]
        pages.append(_page_payload("1", ["15"], end=True))
        cap = self._drive(FakePage(conv, pages, every=7))
        self.assertTrue(cap.reached_end)
        self.assertEqual(len(self.X.direct_replies(conv, "1")), 6)

    def test_no_end_signal_stops_without_claiming_the_end(self):
        conv = self.X.Conversation()
        cap = self._drive(FakePage(conv, [_page_payload("1", ["10"])]))
        self.assertFalse(cap.reached_end)
        self.assertEqual(self.X.coverage(5, cap.reached_end, cap.hit_limit, cap.hit_budget),
                         " of 5; X stopped loading more")

    def test_login_wall_is_login_required(self):
        page = FakePage(self.X.Conversation(), [], url="https://x.com/i/flow/login?redirect_after_login=%2F")
        with self.assertRaises(T.TranscriptError) as cm:
            self._drive(page)
        self.assertEqual(cm.exception.reason, "login_required")

    def test_no_api_data_means_logged_out(self):
        with self.assertRaises(T.TranscriptError) as cm:
            self._drive(FakePage(self.X.Conversation(), []))
        self.assertEqual(cm.exception.reason, "login_required")

    def test_budget_ends_capture_with_what_it_has(self):
        conv = self.X.Conversation()
        ticks = iter(range(0, 10_000, 100))
        pages = [_page_payload("1", [str(i)]) for i in range(10, 100)]
        cap = self._drive(FakePage(conv, pages), clock=lambda: next(ticks))
        self.assertTrue(cap.hit_budget)
        self.assertGreater(len(conv.posts), 0)

    def test_429_is_rate_limited(self):
        page = FakePage(self.X.Conversation(), [])
        with self.assertRaises(T.TranscriptError) as cm:
            run(self.B.drive(page, page.conv, lambda: 0, lambda: True, "1", "replies", 200))
        self.assertEqual(cm.exception.reason, "rate_limited")


class XCookieImport(unittest.TestCase):
    def setUp(self):
        import xbrowser
        self.B = xbrowser

    def test_netscape_export_parses(self):
        text = ("# Netscape HTTP Cookie File\n"
                "#HttpOnly_.x.com\tTRUE\t/\tTRUE\t1893456000\tauth_token\tAAA\n"
                ".x.com\tTRUE\t/\tTRUE\t1893456000\tct0\tBBB\n")
        cookies = self.B.parse_cookies(text)
        self.assertEqual({c["name"] for c in cookies}, {"auth_token", "ct0"})
        self.assertTrue(cookies[0]["httpOnly"])

    def test_foreign_domain_rejected(self):
        text = '[{"name":"auth_token","value":"a","domain":".x.com"},{"name":"ct0","value":"b","domain":".x.com"},' \
               '{"name":"c_user","value":"c","domain":".facebook.com"}]'
        with self.assertRaisesRegex(ValueError, "facebook.com"):
            self.B.parse_cookies(text)

    def test_logged_out_export_rejected(self):
        with self.assertRaisesRegex(ValueError, "auth_token"):
            self.B.parse_cookies('[{"name":"guest_id","value":"a","domain":".x.com"}]')


@unittest.skipIf(api is None, "fastapi not installed")
class XPostJobs(unittest.TestCase):
    def setUp(self):
        import xpost
        self.X = xpost
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.roots = mock.patch.object(api, "OUTPUT_ROOTS", [self.root])
        self.roots.start()
        self.sleep = mock.patch.object(api.asyncio, "sleep", new=mock.AsyncMock())
        self.sleep.start()

    def tearDown(self):
        self.roots.stop()
        self.sleep.stop()
        self.tmp.cleanup()

    def _job(self, urls, post):
        job = api._new_job(self.root)
        with mock.patch.object(api, "_extract", new=mock.AsyncMock()) as yt, \
             mock.patch.object(api, "_extract_post", new=post):
            run(api._run_job(job.job_id, urls, [], "raw", self.root, False))
        yt.assert_not_awaited()
        return job

    def test_x_url_goes_to_post_extractor_once(self):
        post = mock.AsyncMock(return_value={"url": "u", "title": "t", "filename": "f", "source": "x"})
        job = self._job(["https://x.com/a/status/5", "https://twitter.com/a/status/5?s=1"], post)
        post.assert_awaited_once()
        self.assertEqual(job.total, 1)

    def test_saved_post_is_not_fetched_again(self):
        thread = [self.X.normalize(_raw_post("5"))]
        (self.root / "old.md").write_text(self.X.format_markdown(thread, "5"))
        post = mock.AsyncMock()
        job = self._job(["https://x.com/alice/status/5"], post)
        post.assert_not_awaited()
        self.assertEqual(job.results[0]["status"], "exists")

    def test_post_writes_markdown_file(self):
        with mock.patch.object(self.X, "fetch_syndication", return_value=_raw_post("5")), \
             mock.patch.object(self.X, "fetch_graphql", return_value=None):
            res = run(api._extract_post("https://x.com/alice/status/5", self.root))
        self.assertEqual(api.scan_saved([self.root]), {"x:5": Path(res["filename"])})
        self.assertEqual(res["transcript"], "hello")


@unittest.skipIf(api is None, "fastapi not installed")
class XModeJobs(unittest.TestCase):
    """The production decision point for modes: api._fetch_x, reached through
    _run_job. The capture port is xbrowser.capture; the logged-out walk is
    xpost.fetch_syndication."""
    FOCAL = XConversation.FOCAL
    URL = f"https://x.com/FoxxAndCo/status/{XConversation.FOCAL}"

    def setUp(self):
        import xbrowser
        import xpost
        self.B, self.X = xbrowser, xpost
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.patches = [mock.patch.object(api, "OUTPUT_ROOTS", [self.root]),
                        mock.patch.object(api.asyncio, "sleep", new=mock.AsyncMock())]
        for p in self.patches:
            p.start()

    def tearDown(self):
        for p in self.patches:
            p.stop()
        self.tmp.cleanup()

    def _capture(self, hit_limit=True):
        conv = self.X.Conversation()
        conv.add(json.loads((FIXTURES / "tweet_detail_logged_in.json").read_text()))
        return self.B.Capture(conv, reached_end=not hit_limit, hit_limit=hit_limit, hit_budget=False)

    def _job(self, capture, x_mode, limit=200, syndication=None):
        job = api._new_job(self.root)
        syndication = syndication or mock.Mock(side_effect=AssertionError("logged-out walk used"))
        with mock.patch.object(api.xbrowser, "capture", new=capture), \
             mock.patch.object(self.X, "fetch_syndication", new=syndication), \
             mock.patch.object(self.X, "fetch_graphql", return_value=None):
            run(api._run_job(job.job_id, [self.URL], [], "raw", self.root, False, x_mode, limit))
        return job

    def test_replies_job_reads_the_capture_not_the_logged_out_walk(self):
        capture = mock.AsyncMock(return_value=self._capture())
        job = self._job(capture, "replies", limit=3)
        self.assertEqual(capture.await_args.args[:3], (self.FOCAL, "replies", 3))
        self.assertEqual(job.results[0]["listed"], 3, job.results)
        saved = api.scan_saved([self.root])
        self.assertEqual(list(saved), [f"x:{self.FOCAL}:replies"])
        md = saved[f"x:{self.FOCAL}:replies"].read_text()
        self.assertRegex(md, r"## Replies \(3 of [\d,]+; limit reached\)")
        self.assertIn("**Mode:** replies", md)

    def test_author_replies_lists_only_the_authors_posts(self):
        job = self._job(mock.AsyncMock(return_value=self._capture(hit_limit=False)), "author_replies")
        self.assertEqual(job.results[0]["listed"], 1, job.results)
        self.assertIn("2109345169770205368", job.results[0]["transcript"])

    def test_post_and_replies_of_one_post_save_as_two_files(self):
        raw = _raw_post(self.FOCAL, handle="FoxxAndCo")
        self._job(mock.AsyncMock(side_effect=AssertionError("capture used")), "post",
                  syndication=mock.Mock(return_value=raw))
        self._job(mock.AsyncMock(return_value=self._capture()), "replies")
        self.assertEqual(set(api.scan_saved([self.root])), {f"x:{self.FOCAL}", f"x:{self.FOCAL}:replies"})
        again = self._job(mock.AsyncMock(), "replies")
        self.assertEqual(again.results[0]["status"], "exists")

    def test_retry_replays_mode_and_limit(self):
        failing = mock.AsyncMock(side_effect=T.TranscriptError("rate_limited"))
        job = self._job(failing, "replies", limit=7)
        self.assertEqual(job.retryable, 1)
        bg = mock.Mock()
        run(api.retry_job(job.job_id, bg))
        _, args, _ = bg.add_task.mock_calls[0]
        capture = mock.AsyncMock(return_value=self._capture())
        with mock.patch.object(api.xbrowser, "capture", new=capture):
            run(args[0](*args[1:]))
        self.assertEqual(capture.await_args.args[1:3], ("replies", 7))

    def test_unknown_mode_and_limit_are_rejected(self):
        with self.assertRaises(Exception):
            api.JobRequest(urls=[self.URL], x_mode="quotes")
        with self.assertRaises(Exception):
            api.JobRequest(urls=[self.URL], x_mode="replies", limit=self.X.REPLY_LIMIT_MAX + 1)


if __name__ == "__main__":
    unittest.main()
