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
