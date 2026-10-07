"""Tests for transcript sourcing and the Whisper fallback decision.

Run with the service's interpreter (needs fastapi + youtube-transcript-api):
    PYTHONPATH=<service pythonPath>:. python3 -m unittest -v test_transcript
"""

import asyncio
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


if __name__ == "__main__":
    unittest.main()
