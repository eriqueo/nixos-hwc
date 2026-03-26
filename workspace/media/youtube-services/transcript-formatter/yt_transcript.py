#!/usr/bin/env python3
"""
YouTube Transcript Extractor CLI
HWC NixOS Homeserver - Transcript extraction from YouTube videos/playlists

Features:
- Extracts transcripts from single videos or entire playlists
- Multiple language support with fallback options
- Async processing for efficiency
- VTT subtitle parsing with multiple fallback strategies
- Configurable output formatting (standard/detailed sectioning)

Exit Codes:
    0: Success
    1: Error occurred
    2: User interrupted
"""

import argparse
import asyncio
import json
import logging
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from urllib.parse import urlparse, parse_qs

try:
    import yt_dlp
    from youtube_transcript_api import YouTubeTranscriptApi, TranscriptsDisabled, NoTranscriptFound, VideoUnavailable
    import httpx
    from slugify import slugify
except ImportError as e:
    print(f"Missing dependency: {e}")
    print("Install with: pip install yt-dlp youtube-transcript-api httpx python-slugify")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Constants
DEFAULT_TRANSCRIPTS_ROOT = Path("/home/eric/01-documents/01-vaults/04-transcripts")
DEFAULT_HOT_ROOT = Path("/mnt/hot")
DEFAULT_LANGUAGES = ["en", "en-US", "en-GB"]
DEFAULT_TIMEZONE = "America/Denver"
DEFAULT_HTTP_TIMEOUT = 30
DEFAULT_YDL_TIMEOUT = 300

# Sectioning thresholds (seconds)
STANDARD_GAP_THRESHOLD = 20
DETAILED_GAP_THRESHOLD = 12

# Regex patterns
VTT_TIMING_PATTERN = re.compile(r'<[\d:.<>c/\s]*>')
YOUTUBE_URL_PATTERN = re.compile(r"(https?://)?(www\.)?(youtube\.com|youtu\.be)/")


class Config:
    """Configuration for transcript extraction"""

    def __init__(self):
        """Initialize configuration from environment variables with defaults"""
        self.transcripts_root = Path(os.getenv("TRANSCRIPTS_ROOT", str(DEFAULT_TRANSCRIPTS_ROOT)))
        self.hot_root = Path(os.getenv("HOT_ROOT", str(DEFAULT_HOT_ROOT)))
        self.allow_languages = os.getenv("LANGS", ",".join(DEFAULT_LANGUAGES)).split(",")
        self.timezone = os.getenv("TZ", DEFAULT_TIMEZONE)
        self.http_timeout = int(os.getenv("HTTP_TIMEOUT", str(DEFAULT_HTTP_TIMEOUT)))
        self.ydl_timeout = int(os.getenv("YDL_TIMEOUT", str(DEFAULT_YDL_TIMEOUT)))

        # Validate configuration
        self._validate()

    def _validate(self) -> None:
        """Validate configuration values"""
        # Ensure parent of transcripts_root exists
        if not self.transcripts_root.parent.exists():
            logger.warning(f"Parent directory does not exist: {self.transcripts_root.parent}")
            logger.info(f"Will create on first use: {self.transcripts_root}")

        # Validate timeout values
        if self.http_timeout <= 0:
            raise ValueError(f"HTTP_TIMEOUT must be positive, got: {self.http_timeout}")
        if self.ydl_timeout <= 0:
            raise ValueError(f"YDL_TIMEOUT must be positive, got: {self.ydl_timeout}")

        # Validate languages
        if not self.allow_languages:
            raise ValueError("LANGS must contain at least one language code")


class TranscriptExtractor:
    """Main class for extracting YouTube transcripts"""

    def __init__(self, config: Config):
        """
        Initialize transcript extractor.

        Args:
            config: Configuration instance
        """
        self.config = config

        # yt-dlp configuration
        self.ydl_opts_base = {
            "quiet": True,
            "skip_download": True,
            "writesubtitles": True,
            "writeautomaticsub": True,
            "subtitlesformat": "vtt",
            "no_warnings": True,
            "extract_flat": False,
            "subtitleslangs": ["en", "en-US", "en-GB", "en.*"],
        }

    def is_youtube_url(self, url: str) -> bool:
        """
        Check if URL is a valid YouTube URL.

        Args:
            url: URL to check

        Returns:
            bool: True if valid YouTube URL
        """
        return bool(YOUTUBE_URL_PATTERN.search(url))

    def is_playlist_url(self, url: str) -> bool:
        """
        Check if URL is a playlist (not just a video in a playlist).

        Args:
            url: URL to check

        Returns:
            bool: True if URL is a playlist
        """
        parsed = urlparse(url)
        query = parse_qs(parsed.query)

        # It's a playlist if:
        # 1. Path is /playlist
        # 2. Has 'list' param AND no 'v' param (video in playlist has both)
        if parsed.path == '/playlist':
            return True
        if 'list' in query and 'v' not in query:
            return True

        return False

    def sanitize_filename(self, name: str) -> str:
        """
        Create safe filename from title.

        Args:
            name: Original filename/title

        Returns:
            str: Sanitized filename
        """
        return slugify(name, lowercase=True, max_length=120)

    def seconds_to_hms(self, seconds: float) -> str:
        """
        Convert seconds to HH:MM:SS format.

        Args:
            seconds: Time in seconds

        Returns:
            str: Formatted time string
        """
        total_seconds = int(seconds)
        hours = total_seconds // 3600
        minutes = (total_seconds % 3600) // 60
        secs = total_seconds % 60

        if hours:
            return f"{hours:02d}:{minutes:02d}:{secs:02d}"
        return f"{minutes:02d}:{secs:02d}"

    def duration_str(self, seconds: Optional[int]) -> str:
        """
        Convert duration to readable format.

        Args:
            seconds: Duration in seconds

        Returns:
            str: Human-readable duration string
        """
        if not seconds:
            return ""

        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        secs = seconds % 60

        if hours:
            return f"{hours}h {minutes}m {secs}s"
        return f"{minutes}m {secs}s"

    def format_header(self, meta: Dict) -> str:
        """
        Format video metadata as markdown header.

        Args:
            meta: Video metadata dictionary

        Returns:
            str: Formatted markdown header
        """
        lines = [
            f"# {meta.get('title', '')}",
            "",
            "## Metadata",
            f"- **Channel**: {meta.get('channel', '')}",
            f"- **Upload Date**: {meta.get('upload_date', '')}",
            f"- **Duration**: {meta.get('duration_str', '')}",
            f"- **URL**: {meta.get('webpage_url', '')}",
            f"- **Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            ""
        ]
        return "\n".join(lines)

    def format_sections(self, transcript: List[Dict], mode: str = "standard") -> str:
        """
        Format transcript segments into markdown sections.

        Args:
            transcript: List of transcript segments
            mode: Sectioning mode ("standard" or "detailed")

        Returns:
            str: Formatted markdown sections
        """
        if not transcript:
            return "_No transcript available._\n"

        # Group segments into sections based on timing gaps
        gap_threshold = DETAILED_GAP_THRESHOLD if mode == "detailed" else STANDARD_GAP_THRESHOLD
        chunks = self._group_segments_by_gaps(transcript, gap_threshold)

        # Format chunks into markdown sections
        sections = []
        for i, chunk in enumerate(chunks, start=1):
            start_time = self.seconds_to_hms(chunk[0]["start"])
            sections.append(f"### {i:02d} ▸ {start_time}")
            sections.append("")

            # Join text from all segments in this chunk
            paragraph_text = " ".join([seg["text"].strip() for seg in chunk if seg["text"].strip()])

            # Clean VTT timing codes
            paragraph_text = VTT_TIMING_PATTERN.sub('', paragraph_text)
            paragraph_text = paragraph_text.replace("  ", " ").strip()

            sections.append(paragraph_text)
            sections.append("")

        return "\n".join(sections)

    def _group_segments_by_gaps(self, segments: List[Dict], gap_threshold: int) -> List[List[Dict]]:
        """
        Group transcript segments into chunks based on timing gaps.

        Args:
            segments: List of transcript segments
            gap_threshold: Maximum gap in seconds before starting new chunk

        Returns:
            List of segment chunks
        """
        chunks: List[List[Dict]] = []
        current_chunk: List[Dict] = []
        last_time: Optional[float] = None

        for segment in segments:
            current_time = segment["start"]

            # Start new chunk if gap is too large
            if last_time is not None and (current_time - last_time) > gap_threshold:
                if current_chunk:
                    chunks.append(current_chunk)
                    current_chunk = []

            current_chunk.append(segment)
            last_time = current_time

        # Add final chunk
        if current_chunk:
            chunks.append(current_chunk)

        return chunks if chunks else [[]]

    def format_playlist_overview(self, playlist_name: str, videos: List[Dict]) -> str:
        """
        Format playlist overview with table of contents.

        Args:
            playlist_name: Name of the playlist
            videos: List of video metadata dictionaries

        Returns:
            str: Formatted markdown overview
        """
        lines = [
            f"# {playlist_name}",
            "",
            "## Overview",
            f"- **Total Videos**: {len(videos)}",
            f"- **Generated**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
            "",
            "## Table of Contents"
        ]

        for i, video in enumerate(videos, 1):
            title = video.get("title", "")
            upload_date = video.get("upload_date", "")
            duration = video.get("duration_str", "")
            lines.append(f"{i:02d}. **{title}** ({upload_date}, {duration})")

        lines.append("")
        return "\n".join(lines)

    def parse_vtt_to_segments(self, vtt_text: str) -> List[Dict]:
        """
        Parse VTT subtitle format to transcript segments.

        Args:
            vtt_text: VTT subtitle content

        Returns:
            List of transcript segments with 'start' and 'text' fields
        """
        lines = vtt_text.splitlines()
        segments = []

        def parse_timestamp(timestamp: str) -> float:
            """Parse timestamp like '00:01:23.456' to seconds"""
            hours, minutes, seconds_ms = timestamp.split(":")
            secs, millisecs = seconds_ms.split(".")
            return int(hours) * 3600 + int(minutes) * 60 + int(secs) + int(millisecs) / 1000.0

        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if "-->" in line:
                # Found timestamp line
                left, _ = [x.strip() for x in line.split("-->")]
                start_time = parse_timestamp(left)

                # Collect text lines until empty line or end
                i += 1
                text_lines = []
                while i < len(lines) and lines[i].strip():
                    text_lines.append(lines[i].strip())
                    i += 1

                if text_lines:
                    # Clean VTT timing codes from text
                    clean_text = " ".join(text_lines)
                    clean_text = VTT_TIMING_PATTERN.sub('', clean_text)
                    clean_text = clean_text.replace("  ", " ").strip()

                    segments.append({
                        "start": start_time,
                        "text": clean_text
                    })
            i += 1

        return segments

    def extract_video_id(self, url: str) -> str:
        """
        Extract video ID from YouTube URL.

        Args:
            url: YouTube URL

        Returns:
            str: Video ID or empty string if not found
        """
        parsed = urlparse(url)

        if parsed.hostname in ['youtu.be']:
            return parsed.path[1:]
        elif parsed.hostname in ['youtube.com', 'www.youtube.com']:
            if parsed.path == '/watch':
                query = parse_qs(parsed.query)
                return query.get('v', [''])[0]
            elif parsed.path.startswith('/v/'):
                return parsed.path.split('/')[2]

        return ""

    async def get_video_info(self, url: str) -> Dict:
        """
        Get video metadata using yt-dlp.

        Args:
            url: YouTube video URL

        Returns:
            Dict: Video metadata
        """
        with yt_dlp.YoutubeDL({**self.ydl_opts_base, "dump_single_json": True}) as ydl:
            return ydl.extract_info(url, download=False)

    async def fetch_transcript_segments(self, video_id: str, prefer_langs: List[str]) -> List[Dict]:
        """
        Fetch transcript segments using yt-dlp subtitle download.

        Args:
            video_id: YouTube video ID
            prefer_langs: Preferred languages in order of preference

        Returns:
            List of transcript segments
        """
        # Configure yt-dlp with language preferences
        opts = {**self.ydl_opts_base}
        opts["subtitleslangs"] = prefer_langs + ["en", "en-US", "en-GB", "en.*"]

        with yt_dlp.YoutubeDL(opts) as ydl:
            try:
                info = ydl.extract_info(f"https://youtube.com/watch?v={video_id}", download=False)

                # Find best subtitle
                subtitle_url = self._find_best_subtitle_url(info, prefer_langs)

                if not subtitle_url:
                    logger.warning(f"No subtitles found for video {video_id}")
                    return []

                logger.debug(f"Using subtitle URL: {subtitle_url}")

                # Download and parse VTT
                return await self._download_and_parse_vtt(subtitle_url)

            except Exception as e:
                logger.error(f"Failed to fetch transcript for {video_id}: {e}")
                return []

    def _find_best_subtitle_url(self, info: Dict, prefer_langs: List[str]) -> Optional[str]:
        """
        Find best subtitle URL from video info.

        Args:
            info: yt-dlp video info dictionary
            prefer_langs: Preferred languages

        Returns:
            Optional[str]: Best subtitle URL or None
        """
        # Collect all available subtitles
        requested_subs = info.get("requested_subtitles") or {}
        automatic_subs = info.get("automatic_captions") or {}
        manual_subs = info.get("subtitles") or {}

        # Priority: requested > manual > automatic
        all_subtitles = {}
        all_subtitles.update(automatic_subs)
        all_subtitles.update(manual_subs)
        all_subtitles.update(requested_subs)

        logger.debug(f"Available subtitle languages: {list(all_subtitles.keys())}")

        # Try preferred languages first
        for lang in prefer_langs:
            url = self._extract_vtt_url_from_entries(all_subtitles.get(lang))
            if url:
                return url

        # Try any English variant
        for lang_key in all_subtitles:
            if lang_key.startswith('en'):
                url = self._extract_vtt_url_from_entries(all_subtitles[lang_key])
                if url:
                    return url

        # Last resort: take any available subtitle
        for entries in all_subtitles.values():
            url = self._extract_vtt_url_from_entries(entries)
            if url:
                return url

        return None

    def _extract_vtt_url_from_entries(self, entries: any) -> Optional[str]:
        """
        Extract VTT URL from subtitle entries.

        Args:
            entries: Subtitle entries (can be list or dict)

        Returns:
            Optional[str]: VTT URL or None
        """
        if not entries:
            return None

        # Handle list of entries
        if isinstance(entries, list):
            for entry in entries:
                if isinstance(entry, dict) and entry.get("ext") == "vtt":
                    return entry.get("url")

        # Handle single entry
        elif isinstance(entries, dict) and entries.get("ext") == "vtt":
            return entries.get("url")

        return None

    async def _download_and_parse_vtt(self, url: str) -> List[Dict]:
        """
        Download and parse VTT subtitle file.

        Args:
            url: VTT file URL

        Returns:
            List of parsed transcript segments
        """
        try:
            async with httpx.AsyncClient(timeout=self.config.http_timeout) as client:
                response = await client.get(url)
                response.raise_for_status()
                vtt_content = response.text

                logger.debug(f"Downloaded VTT content: {len(vtt_content)} characters")
                return self.parse_vtt_to_segments(vtt_content)

        except httpx.TimeoutException:
            logger.error(f"Timeout downloading VTT from {url}")
            return []
        except httpx.HTTPError as e:
            logger.error(f"HTTP error downloading VTT: {e}")
            return []
        except Exception as e:
            logger.error(f"Unexpected error downloading VTT: {e}")
            return []

    def meta_from_ydl_info(self, info: Dict) -> Dict:
        """
        Extract metadata from yt-dlp info.

        Args:
            info: yt-dlp info dictionary

        Returns:
            Dict: Extracted metadata
        """
        return {
            "title": info.get("title", ""),
            "channel": info.get("channel", "") or info.get("uploader", ""),
            "upload_date": info.get("upload_date", ""),
            "duration_str": self.duration_str(info.get("duration")),
            "webpage_url": info.get("webpage_url", ""),
            "id": info.get("id", ""),
        }

    async def process_video(
        self,
        url: str,
        output_dir: Path,
        prefer_langs: List[str],
        mode: str = "standard"
    ) -> Path:
        """
        Process single video to markdown.

        Args:
            url: YouTube video URL
            output_dir: Output directory for markdown file
            prefer_langs: Preferred languages
            mode: Formatting mode ("standard" or "detailed")

        Returns:
            Path: Path to created markdown file
        """
        logger.info(f"Processing video: {url}")

        # Get video info
        info = await self.get_video_info(url)
        meta = self.meta_from_ydl_info(info)

        # Get transcript
        segments = await self.fetch_transcript_segments(meta["id"], prefer_langs)

        # Generate filename with date prefix and content
        title_safe = self.sanitize_filename(meta["title"] or meta["id"])
        output_dir.mkdir(parents=True, exist_ok=True)
        date_prefix = datetime.now().strftime('%Y-%m-%d')
        markdown_path = output_dir / f"{date_prefix} - {title_safe}.md"

        # Format markdown content
        header = self.format_header(meta)
        body = self.format_sections(segments, mode=mode)
        content = "\n".join([header, body])

        # Write file
        markdown_path.write_text(content, encoding="utf-8")
        logger.info(f"✓ Saved: {markdown_path}")

        return markdown_path

    async def process_playlist(
        self,
        url: str,
        root_dir: Path,
        prefer_langs: List[str],
        mode: str = "standard"
    ) -> Tuple[Path, List[Path]]:
        """
        Process playlist to markdown files.

        Args:
            url: YouTube playlist URL
            root_dir: Root directory for playlist output
            prefer_langs: Preferred languages
            mode: Formatting mode ("standard" or "detailed")

        Returns:
            Tuple of (playlist_dir, list of video file paths)
        """
        logger.info(f"Processing playlist: {url}")

        # Get playlist info
        with yt_dlp.YoutubeDL({"quiet": True, "extract_flat": True, "skip_download": True}) as ydl:
            playlist_info = ydl.extract_info(url, download=False)

        playlist_name = playlist_info.get("title", "playlist")
        playlist_dir = root_dir / self.sanitize_filename(playlist_name)
        playlist_dir.mkdir(parents=True, exist_ok=True)

        video_files: List[Path] = []
        video_metadata: List[Dict] = []

        # Process each video
        for entry in playlist_info.get("entries", []):
            if not entry or entry.get("_type") == "playlist":
                continue
            if entry.get("availability") in ("private", "unavailable"):
                logger.warning(f"Skipping unavailable video: {entry.get('title', 'Unknown')}")
                continue

            video_url = f"https://www.youtube.com/watch?v={entry.get('id')}"
            try:
                video_file = await self.process_video(video_url, playlist_dir, prefer_langs, mode)
                video_files.append(video_file)

                # Get metadata for overview
                video_info = await self.get_video_info(video_url)
                video_metadata.append(self.meta_from_ydl_info(video_info))

            except Exception as e:
                logger.error(f"Error processing video {video_url}: {e}")
                continue

        # Create playlist overview
        overview_content = self.format_playlist_overview(playlist_name, video_metadata)
        overview_path = playlist_dir / "00-playlist-overview.md"
        overview_path.write_text(overview_content, encoding="utf-8")
        logger.info(f"✓ Created playlist overview: {overview_path}")

        return playlist_dir, video_files


async def main() -> int:
    """
    Main CLI function.

    Returns:
        int: Exit code
    """
    parser = argparse.ArgumentParser(
        prog="yt-transcript",
        description="Extract YouTube transcripts to Markdown",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  yt-transcript "https://youtube.com/watch?v=dQw4w9WgXcQ"
  yt-transcript "https://youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab"
  yt-transcript --output-dir /custom/path --format detailed "URL"
  yt-transcript --verbose "URL"
        """
    )

    parser.add_argument("url", help="YouTube video or playlist URL")
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Custom output directory (default: from TRANSCRIPTS_ROOT or ~/01-documents/01-vaults/04-transcripts)"
    )
    parser.add_argument(
        "--format",
        choices=["standard", "detailed"],
        default="standard",
        help="Sectioning density (standard=20s gaps, detailed=12s gaps)"
    )
    parser.add_argument(
        "--langs",
        default=None,
        help="Comma-separated list of preferred languages (e.g., 'en,en-US,fr')"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    # Configure logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
        logger.setLevel(logging.DEBUG)

    try:
        # Initialize config and extractor
        config = Config()
        extractor = TranscriptExtractor(config)

        # Validate URL
        if not extractor.is_youtube_url(args.url):
            logger.error(f"Invalid YouTube URL: {args.url}")
            return 1

        # Set up output directory
        if args.output_dir:
            output_root = Path(args.output_dir)
        else:
            output_root = config.transcripts_root

        # Set up languages
        if args.langs:
            prefer_langs = [lang.strip() for lang in args.langs.split(",") if lang.strip()]
        else:
            prefer_langs = config.allow_languages

        # Process URL (improved detection)
        if extractor.is_playlist_url(args.url):
            playlist_dir, files = await extractor.process_playlist(
                args.url, output_root / "playlists", prefer_langs, args.format
            )
            logger.info(f"✅ Playlist processed: {len(files)} videos in {playlist_dir}")
        else:
            # Single video - save directly to vault root
            file_path = await extractor.process_video(args.url, output_root, prefer_langs, args.format)
            logger.info(f"✅ Video processed: {file_path}")

        return 0

    except KeyboardInterrupt:
        logger.warning("Interrupted by user")
        return 2
    except ValueError as e:
        logger.error(f"Configuration error: {e}")
        return 1
    except Exception as e:
        logger.error(f"Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
