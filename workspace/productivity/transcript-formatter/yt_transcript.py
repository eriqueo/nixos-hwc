#!/usr/bin/env python3
"""
YouTube Transcript Extractor CLI
HWC NixOS Homeserver - Transcript extraction from YouTube videos/playlists
"""

import argparse
import asyncio
import json
import os
import re
import sys
import time
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


class Config:
    """Configuration for transcript extraction"""
    def __init__(self):
        # Default to Obsidian vault location
        default_root = "/home/eric/01-documents/01-vaults/04-transcripts"
        self.transcripts_root = Path(os.getenv("TRANSCRIPTS_ROOT", default_root))
        self.hot_root = Path(os.getenv("HOT_ROOT", "/mnt/hot"))
        self.allow_languages = os.getenv("LANGS", "en,en-US,en-GB").split(",")
        self.timezone = os.getenv("TZ", "America/Denver")


class TranscriptExtractor:
    """Main class for extracting YouTube transcripts"""
    
    def __init__(self, config: Config):
        self.config = config
        self.youtube_re = re.compile(r"(https?://)?(www\.)?(youtube\.com|youtu\.be)/")
        
        # yt-dlp configuration
        self.ydl_opts_base = {
            "quiet": True,
            "skip_download": True,
            "writesubtitles": True,
            "writeautomaticsub": True,
            "subtitlesformat": "vtt",
            "no_warnings": True,
            "extract_flat": False,
            "subtitleslangs": ["en", "en-US", "en-GB", "en.*"],  # More aggressive language matching
        }
    
    def is_youtube_url(self, url: str) -> bool:
        """Check if URL is a valid YouTube URL"""
        return bool(self.youtube_re.search(url))
    
    def sanitize_filename(self, name: str) -> str:
        """Create safe filename from title"""
        return slugify(name, lowercase=True, max_length=120)
    
    def seconds_to_hms(self, seconds: float) -> str:
        """Convert seconds to HH:MM:SS format"""
        s = int(seconds)
        h = s // 3600
        m = (s % 3600) // 60
        sec = s % 60
        if h:
            return f"{h:02d}:{m:02d}:{sec:02d}"
        return f"{m:02d}:{sec:02d}"
    
    def duration_str(self, sec: Optional[int]) -> str:
        """Convert duration to readable format"""
        if not sec:
            return ""
        h = sec // 3600
        m = (sec % 3600) // 60
        s = sec % 60
        if h:
            return f"{h}h {m}m {s}s"
        return f"{m}m {s}s"
    
    def format_header(self, meta: Dict) -> str:
        """Format video metadata as markdown header"""
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
        """Format transcript segments into markdown sections"""
        if not transcript:
            return "_No transcript available._\n"
        
        # Group segments into sections based on timing gaps
        bucket = []
        chunks: List[List[Dict]] = []
        last_time = None
        gap_threshold = 20 if mode == "standard" else 12
        
        for segment in transcript:
            current_time = segment["start"]
            if last_time is not None and (current_time - last_time) > gap_threshold:
                if bucket:
                    chunks.append(bucket)
                    bucket = []
            bucket.append(segment)
            last_time = current_time
        
        if bucket:
            chunks.append(bucket)
        
        # Format chunks into markdown sections
        sections = []
        for i, chunk in enumerate(chunks, start=1):
            start_time = self.seconds_to_hms(chunk[0]["start"])
            sections.append(f"### {i:02d} ▸ {start_time}")
            sections.append("")
            
            # Join text from all segments in this chunk and clean up VTT timing codes
            paragraph_text = " ".join([seg["text"].strip() for seg in chunk if seg["text"].strip()])
            
            # Remove VTT timing codes like <00:01:23.456><c> or <00:01:23>
            import re
            paragraph_text = re.sub(r'<[\d:.<>c/\s]*>', '', paragraph_text)
            paragraph_text = paragraph_text.replace("  ", " ").strip()
            sections.append(paragraph_text)
            sections.append("")
        
        return "\n".join(sections)
    
    def format_playlist_overview(self, playlist_name: str, videos: List[Dict]) -> str:
        """Format playlist overview with table of contents"""
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
        """Parse VTT subtitle format to transcript segments"""
        lines = vtt_text.splitlines()
        segments = []
        
        def parse_timestamp(ts: str) -> float:
            """Parse timestamp like '00:01:23.456' to seconds"""
            h, m, s_ms = ts.split(":")
            s, ms = s_ms.split(".")
            return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000.0
        
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if "-->" in line:
                # Found timestamp line
                left, right = [x.strip() for x in line.split("-->")]
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
                    clean_text = re.sub(r'<[\d:.<>c/\s]*>', '', clean_text)
                    clean_text = clean_text.replace("  ", " ").strip()
                    
                    segments.append({
                        "start": start_time,
                        "text": clean_text
                    })
            i += 1
        
        return segments
    
    def extract_video_id(self, url: str) -> str:
        """Extract video ID from YouTube URL"""
        parsed = urlparse(url)
        if parsed.hostname in ['youtu.be']:
            return parsed.path[1:]
        elif parsed.hostname in ['youtube.com', 'www.youtube.com']:
            if parsed.path == '/watch':
                return parse_qs(parsed.query)['v'][0]
            elif parsed.path.startswith('/v/'):
                return parsed.path.split('/')[2]
        return ""
    
    async def get_video_info(self, url: str) -> Dict:
        """Get video metadata using yt-dlp"""
        with yt_dlp.YoutubeDL({**self.ydl_opts_base, "dump_single_json": True}) as ydl:
            return ydl.extract_info(url, download=False)
    
    async def fetch_transcript_segments(self, video_id: str, prefer_langs: List[str]) -> List[Dict]:
        """Fetch transcript segments using yt-dlp subtitle download"""
        # Skip YouTube Transcript API for now, go directly to yt-dlp
        # try:
        #     transcript = YouTubeTranscriptApi.get_transcript(video_id, languages=prefer_langs)
        #     return [{"start": t["start"], "text": t["text"]} for t in transcript]
        # except (TranscriptsDisabled, NoTranscriptFound, VideoUnavailable):
        #     pass
        
        # Fallback to yt-dlp subtitle extraction
        opts = {**self.ydl_opts_base}
        opts["subtitleslangs"] = prefer_langs + ["en", "en-US", "en-GB", "en.*"]  # Broader language search
        
        with yt_dlp.YoutubeDL(opts) as ydl:
            try:
                info = ydl.extract_info(f"https://youtube.com/watch?v={video_id}", download=False)
                
                # Check multiple subtitle sources
                requested_subs = info.get("requested_subtitles") or {}
                automatic_subs = info.get("automatic_captions") or {}
                manual_subs = info.get("subtitles") or {}
                
                # Priority: requested > manual > automatic
                all_subtitles = {}
                all_subtitles.update(automatic_subs)  # Lowest priority
                all_subtitles.update(manual_subs)     # Medium priority  
                all_subtitles.update(requested_subs)  # Highest priority
                
                print(f"Available subtitles: {list(all_subtitles.keys())}")  # Debug output
                
                # Find best subtitle match
                best_subtitle = None
                best_url = None
                
                # First, try preferred languages
                for lang in prefer_langs:
                    if lang in all_subtitles and all_subtitles[lang]:
                        entries = all_subtitles[lang]
                        if isinstance(entries, list):
                            for entry in entries:
                                if isinstance(entry, dict) and entry.get("ext") == "vtt":
                                    best_subtitle = entry
                                    best_url = entry.get("url")
                                    break
                        elif isinstance(entries, dict) and entries.get("ext") == "vtt":
                            best_subtitle = entries
                            best_url = entries.get("url")
                        if best_subtitle:
                            break
                
                # If no match, try any English variant
                if not best_subtitle:
                    for lang_key in all_subtitles:
                        if lang_key.startswith('en') and all_subtitles[lang_key]:
                            entries = all_subtitles[lang_key]
                            if isinstance(entries, list):
                                for entry in entries:
                                    if isinstance(entry, dict) and entry.get("ext") == "vtt":
                                        best_subtitle = entry
                                        best_url = entry.get("url")
                                        break
                            elif isinstance(entries, dict) and entries.get("ext") == "vtt":
                                best_subtitle = entries
                                best_url = entries.get("url")
                            if best_subtitle:
                                break
                
                # Last resort: take any available subtitle
                if not best_subtitle:
                    for lang_key, entries in all_subtitles.items():
                        if entries:
                            if isinstance(entries, list):
                                for entry in entries:
                                    if isinstance(entry, dict) and entry.get("ext") == "vtt":
                                        best_subtitle = entry
                                        best_url = entry.get("url")
                                        break
                            elif isinstance(entries, dict) and entries.get("ext") == "vtt":
                                best_subtitle = entries
                                best_url = entries.get("url")
                            if best_subtitle:
                                break
                
                if not best_url:
                    print("No subtitle URL found")  # Debug output
                    return []
                
                print(f"Using subtitle URL: {best_url}")  # Debug output
                
                # Download and parse VTT
                async with httpx.AsyncClient(timeout=30) as client:
                    response = await client.get(best_url)
                    response.raise_for_status()
                    vtt_content = response.text
                    print(f"Downloaded VTT content length: {len(vtt_content)}")  # Debug output
                    return self.parse_vtt_to_segments(vtt_content)
                
            except Exception as e:
                print(f"yt-dlp subtitle extraction failed: {e}")  # Debug output
                return []
    
    def meta_from_ydl_info(self, info: Dict) -> Dict:
        """Extract metadata from yt-dlp info"""
        return {
            "title": info.get("title", ""),
            "channel": info.get("channel", "") or info.get("uploader", ""),
            "upload_date": info.get("upload_date", ""),
            "duration_str": self.duration_str(info.get("duration")),
            "webpage_url": info.get("webpage_url", ""),
            "id": info.get("id", ""),
        }
    
    async def process_video(self, url: str, output_dir: Path, prefer_langs: List[str], mode: str = "standard") -> Path:
        """Process single video to markdown"""
        print(f"Processing video: {url}")
        
        # Get video info
        info = await self.get_video_info(url)
        meta = self.meta_from_ydl_info(info)
        
        # Get transcript
        segments = await self.fetch_transcript_segments(meta["id"], prefer_langs)
        
        # Generate filename and content
        title_safe = self.sanitize_filename(meta["title"] or meta["id"])
        output_dir.mkdir(parents=True, exist_ok=True)
        markdown_path = output_dir / f"{title_safe}.md"
        
        # Format markdown content
        header = self.format_header(meta)
        body = self.format_sections(segments, mode=mode)
        content = "\n".join([header, body])
        
        # Write file
        markdown_path.write_text(content, encoding="utf-8")
        print(f"✓ Saved: {markdown_path}")
        
        return markdown_path
    
    async def process_playlist(self, url: str, root_dir: Path, prefer_langs: List[str], mode: str = "standard") -> Tuple[Path, List[Path]]:
        """Process playlist to markdown files"""
        print(f"Processing playlist: {url}")
        
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
                print(f"⚠ Skipping unavailable video: {entry.get('title', 'Unknown')}")
                continue
            
            video_url = f"https://www.youtube.com/watch?v={entry.get('id')}"
            try:
                video_file = await self.process_video(video_url, playlist_dir, prefer_langs, mode)
                video_files.append(video_file)
                
                # Get metadata for overview
                video_info = await self.get_video_info(video_url)
                video_metadata.append(self.meta_from_ydl_info(video_info))
                
            except Exception as e:
                print(f"⚠ Error processing video {video_url}: {e}")
                continue
        
        # Create playlist overview
        overview_content = self.format_playlist_overview(playlist_name, video_metadata)
        overview_path = playlist_dir / "00-playlist-overview.md"
        overview_path.write_text(overview_content, encoding="utf-8")
        print(f"✓ Created playlist overview: {overview_path}")
        
        return playlist_dir, video_files


async def main():
    """Main CLI function"""
    parser = argparse.ArgumentParser(
        prog="yt-transcript",
        description="Extract YouTube transcripts to Markdown",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  yt-transcript "https://youtube.com/watch?v=dQw4w9WgXcQ"
  yt-transcript "https://youtube.com/playlist?list=PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab"
  yt-transcript --output-dir /custom/path --format detailed "URL"
        """
    )
    
    parser.add_argument("url", help="YouTube video or playlist URL")
    parser.add_argument("--output-dir", default=None, help="Custom output directory")
    parser.add_argument("--format", choices=["standard", "detailed"], default="standard",
                       help="Sectioning density (standard=20s gaps, detailed=12s gaps)")
    parser.add_argument("--langs", default=None,
                       help="Comma-separated list of preferred languages (e.g., 'en,en-US,fr')")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    # Initialize config and extractor
    config = Config()
    extractor = TranscriptExtractor(config)
    
    # Validate URL
    if not extractor.is_youtube_url(args.url):
        print(f"❌ Invalid YouTube URL: {args.url}")
        sys.exit(1)
    
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
    
    # Process URL
    try:
        if "playlist" in args.url:
            playlist_dir, files = await extractor.process_playlist(
                args.url, output_root / "playlists", prefer_langs, args.format
            )
            print(f"✅ Playlist processed: {len(files)} videos in {playlist_dir}")
        else:
            # Single video
            date_dir = output_root / "individual" / datetime.now().strftime("%Y-%m-%d")
            file_path = await extractor.process_video(args.url, date_dir, prefer_langs, args.format)
            print(f"✅ Video processed: {file_path}")
    
    except KeyboardInterrupt:
        print("\n❌ Interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())