#!/usr/bin/env python3
"""
Audiobook Copier

Copies audiobooks from qBittorrent downloads to Audiobookshelf library,
preserving source files for continued seeding.

Features:
- Detects audiobooks by audio file extensions (mp3, m4a, m4b, flac, opus)
- Uses rsync with --ignore-existing for safe incremental copies
- Creates .abs-copied marker in source to prevent re-processing
- Maintains JSON state at /var/lib/hwc/audiobook-copier/state.json
- Triggers Audiobookshelf library scan via API

Usage:
    audiobook-copier.py <content_path>
    audiobook-copier.py --scan-all  # Process all uncopied audiobooks in source dir

Environment Variables:
    SOURCE_DIR: Source directory (default: /mnt/hot/downloads/books)
    DEST_DIR: Destination directory (default: /mnt/media/books/audiobooks)
    STATE_DIR: State directory (default: /var/lib/hwc/audiobook-copier)
    AUDIOBOOKSHELF_URL: API URL (default: http://localhost:13378)
    AUDIOBOOKSHELF_API_KEY: API key for library scan (optional)
    DRY_RUN: Set to "1" for dry run mode
"""

import os
import sys
import json
import logging
import argparse
import subprocess
import fcntl
import tempfile
from contextlib import contextmanager
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict, Any

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Audio file extensions that indicate an audiobook
AUDIO_EXTENSIONS = {'.mp3', '.m4a', '.m4b', '.flac', '.opus', '.ogg', '.wav', '.aac'}

# Marker file to indicate audiobook has been copied
MARKER_FILE = '.abs-copied'


class Config:
    """Configuration from environment variables."""

    def __init__(self):
        self.source_dir = Path(os.getenv('SOURCE_DIR', '/mnt/hot/downloads/books'))
        self.dest_dir = Path(os.getenv('DEST_DIR', '/mnt/media/books/audiobooks'))
        self.state_dir = Path(os.getenv('STATE_DIR', '/var/lib/hwc/audiobook-copier'))
        self.audiobookshelf_url = os.getenv('AUDIOBOOKSHELF_URL', 'http://localhost:13378')
        self.audiobookshelf_api_key = os.getenv('AUDIOBOOKSHELF_API_KEY', '')
        self.dry_run = os.getenv('DRY_RUN', '0') == '1'
        self.trigger_library_scan = os.getenv('TRIGGER_LIBRARY_SCAN', '1') == '1'
        self.audio_extensions = tuple('.' + item.lstrip('.') for item in
                                      os.getenv('AUDIO_EXTENSIONS', ','.join(sorted(AUDIO_EXTENSIONS))).split(','))
        self.include_hidden = False

    @property
    def state_file(self) -> Path:
        return self.state_dir / 'state.json'


class StateManager:
    """Manages persistent state for processed audiobooks."""

    def __init__(self, state_file: Path):
        self.state_file = state_file
        self.state: Dict[str, Any] = self._load()

    def _load(self) -> Dict[str, Any]:
        """Load state from file."""
        if self.state_file.exists():
            try:
                with open(self.state_file, 'r') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError) as e:
                logger.warning(f"Failed to load state file: {e}")
        return {'processed': {}, 'last_scan': None}

    def save(self) -> None:
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        fd, pending = tempfile.mkstemp(prefix='.state-', dir=self.state_file.parent)
        try:
            with os.fdopen(fd, 'w') as output:
                os.fchmod(output.fileno(), 0o644)
                json.dump(self.state, output, indent=2, default=str)
                output.flush()
                os.fsync(output.fileno())
            os.replace(pending, self.state_file)
        finally:
            if os.path.exists(pending):
                os.unlink(pending)

    def mark_processed(self, path: Path, dest_path: Path) -> None:
        """Mark an audiobook as processed."""
        self.state['processed'][str(path)] = {
            'dest': str(dest_path),
            'timestamp': datetime.now().isoformat()
        }
        self.save()

    def is_processed(self, path: Path) -> bool:
        """Check if an audiobook was already processed."""
        return str(path) in self.state['processed']

    def update_last_scan(self) -> None:
        """Update the last scan timestamp."""
        self.state['last_scan'] = datetime.now().isoformat()
        self.save()


def is_audiobook_directory(path: Path, extensions=AUDIO_EXTENSIONS) -> bool:
    """
    Check if a directory contains audiobook files.

    Args:
        path: Directory path to check

    Returns:
        True if directory contains audio files
    """
    if not path.is_dir():
        return False

    # Check for audio files in directory or subdirectories
    for ext in extensions:
        if list(path.glob(f'*{ext}')) or list(path.glob(f'**/*{ext}')):
            return True

    return False


def has_marker(path: Path) -> bool:
    """Check if directory has already been processed."""
    return (path / MARKER_FILE).exists()


def create_marker(path: Path, dest_path: Path, dry_run: bool = False) -> None:
    """Create marker file indicating audiobook was copied."""
    marker_path = path / MARKER_FILE
    if dry_run:
        logger.info(f"[DRY RUN] Would create marker: {marker_path}")
        return

    marker_content = {
        'copied_at': datetime.now().isoformat(),
        'destination': str(dest_path)
    }
    with open(marker_path, 'w') as f:
        json.dump(marker_content, f, indent=2)
    logger.info(f"Created marker: {marker_path}")


def copy_audiobook(source: Path, dest_dir: Path, dry_run: bool = False) -> Optional[Path]:
    """
    Copy audiobook directory to destination using rsync.

    Args:
        source: Source audiobook directory
        dest_dir: Destination parent directory
        dry_run: If True, only log what would be done

    Returns:
        Destination path if successful, None otherwise
    """
    dest_path = dest_dir / source.name

    # Build rsync command
    rsync_cmd = [
        'rsync',
        '-av',
        '--ignore-existing',  # Don't overwrite existing files
        '--progress',
        str(source) + '/',  # Trailing slash copies contents
        str(dest_path)
    ]

    if dry_run:
        rsync_cmd.insert(1, '--dry-run')

    logger.info(f"Copying: {source} -> {dest_path}")
    logger.debug(f"Command: {' '.join(rsync_cmd)}")

    try:
        result = subprocess.run(
            rsync_cmd,
            capture_output=True,
            text=True,
            timeout=3600  # 1 hour timeout for large audiobooks
        )

        if result.returncode == 0:
            logger.info(f"Successfully copied: {source.name}")
            if result.stdout:
                logger.debug(result.stdout)
            return dest_path
        else:
            logger.error(f"rsync failed with code {result.returncode}")
            logger.error(result.stderr)
            return None

    except subprocess.TimeoutExpired:
        logger.error(f"rsync timed out for: {source}")
        return None
    except Exception as e:
        logger.error(f"Error copying {source}: {e}")
        return None


def trigger_library_scan(config: Config) -> bool:
    """
    Trigger Audiobookshelf library scan via API.

    Args:
        config: Configuration instance

    Returns:
        True if scan triggered successfully
    """
    if config.dry_run or not config.trigger_library_scan:
        return False
    if not config.audiobookshelf_api_key:
        logger.warning("No Audiobookshelf API key configured, skipping library scan")
        return False

    # First, get the library ID
    headers = {'Authorization': f'Bearer {config.audiobookshelf_api_key}'}

    try:
        # Get libraries
        response = requests.get(
            f"{config.audiobookshelf_url}/api/libraries",
            headers=headers,
            timeout=10
        )
        response.raise_for_status()
        libraries = response.json().get('libraries', [])

        if not libraries:
            logger.warning("No libraries found in Audiobookshelf")
            return False

        # Scan all libraries (or just the first audiobook library)
        scanned = False
        for library in libraries:
            lib_id = library.get('id')
            lib_name = library.get('name', 'Unknown')

            logger.info(f"Triggering scan for library: {lib_name} ({lib_id})")

            scan_response = requests.post(
                f"{config.audiobookshelf_url}/api/libraries/{lib_id}/scan",
                headers=headers,
                timeout=10
            )

            if scan_response.ok:
                logger.info(f"Library scan triggered: {lib_name}")
                scanned = True
            else:
                logger.warning(f"Failed to scan library {lib_name}: {scan_response.status_code}")

        return scanned

    except requests.Timeout:
        logger.error("Timeout connecting to Audiobookshelf")
        return False
    except requests.RequestException as e:
        logger.error(f"Error triggering library scan: {e}")
        return False


def process_audiobook(path: Path, config: Config, state: StateManager) -> bool:
    """
    Process a single audiobook directory.

    Args:
        path: Path to audiobook directory
        config: Configuration instance
        state: State manager

    Returns:
        True if processed successfully
    """
    # Skip if already has marker
    if has_marker(path):
        logger.debug(f"Skipping (has marker): {path}")
        return False

    # Skip if already in state
    if state.is_processed(path):
        logger.debug(f"Skipping (in state): {path}")
        return False

    # Verify it's an audiobook
    if not is_audiobook_directory(path, config.audio_extensions):
        logger.debug(f"Not an audiobook directory: {path}")
        return False

    # Copy the audiobook
    dest_path = copy_audiobook(path, config.dest_dir, config.dry_run)

    if dest_path:
        # Create marker and update state
        create_marker(path, dest_path, config.dry_run)
        if not config.dry_run:
            state.mark_processed(path, dest_path)
        return True

    return False


def scan_all(config: Config, state: StateManager) -> int:
    """
    Scan source directory for all unprocessed audiobooks.

    Args:
        config: Configuration instance
        state: State manager

    Returns:
        Number of audiobooks processed
    """
    if not config.source_dir.exists():
        logger.error(f"Source directory does not exist: {config.source_dir}")
        return 0

    processed_count = 0

    # Scan immediate children of source directory
    for item in config.source_dir.iterdir():
        if item.is_dir() and (config.include_hidden or not item.name.startswith('.')):
            if process_audiobook(item, config, state):
                processed_count += 1

    logger.info(f"Processed {processed_count} audiobooks")

    # Trigger library scan if any were processed
    if processed_count > 0 and config.audiobookshelf_api_key:
        trigger_library_scan(config)

    if not config.dry_run:
        state.update_last_scan()
    return processed_count


def process_single(path: Path, config: Config, state: StateManager) -> bool:
    """
    Process a single audiobook path (called by media-orchestrator).

    Args:
        path: Path to audiobook (file or directory)
        config: Configuration instance
        state: State manager

    Returns:
        True if processed successfully
    """
    # If path is a file, use parent directory
    if path.is_file():
        path = path.parent

    if not path.exists():
        logger.error(f"Path does not exist: {path}")
        return False

    result = process_audiobook(path, config, state)

    # Trigger library scan if successful
    if result and config.audiobookshelf_api_key:
        trigger_library_scan(config)

    return result


@contextmanager
def copy_lock(state_dir: Path, dry_run: bool):
    if dry_run:
        yield
        return
    state_dir.mkdir(parents=True, exist_ok=True)
    # Both the root-run sweep and user-owned hook may read an empty lock file.
    # One copier owns state and markers; busy callers fail for the next timer
    # to recover, rather than running a second copy or waiting without a bound.
    try:
        fd = os.open(state_dir / '.copy.lock', os.O_RDONLY | os.O_CREAT | os.O_EXCL, 0o644)
        os.fchmod(fd, 0o644)
    except FileExistsError:
        fd = os.open(state_dir / '.copy.lock', os.O_RDONLY | os.O_NOFOLLOW)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(
        description='Copy audiobooks from downloads to Audiobookshelf library'
    )
    parser.add_argument(
        'path',
        nargs='?',
        help='Path to audiobook to process'
    )
    parser.add_argument(
        '--scan-all',
        action='store_true',
        help='Scan source directory for all unprocessed audiobooks'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without making changes'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )
    parser.add_argument('--no-library-scan', action='store_true',
                        help='Copy without asking Audiobookshelf to scan')
    parser.add_argument('--include-hidden', action='store_true',
                        help='Include hidden directories when scanning the source')
    args = parser.parse_args()

    # Configure logging level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Load configuration
    config = Config()
    if args.dry_run:
        config.dry_run = True
    if args.no_library_scan:
        config.trigger_library_scan = False
    config.include_hidden = args.include_hidden

    try:
        with copy_lock(config.state_dir, config.dry_run):
            return run(args, config)
    except BlockingIOError:
        logger.error('Audiobook copy is already running; retry on the next sweep')
        return 2


def run(args, config):

    # Initialize state manager
    state = StateManager(config.state_file)

    logger.info(f"Source: {config.source_dir}")
    logger.info(f"Destination: {config.dest_dir}")
    if config.dry_run:
        logger.info("DRY RUN MODE - no changes will be made")

    # Ensure destination exists
    if not config.dry_run:
        config.dest_dir.mkdir(parents=True, exist_ok=True)

    # Process based on arguments
    if args.scan_all:
        count = scan_all(config, state)
        return 0 if count >= 0 else 1
    elif args.path:
        path = Path(args.path)
        success = process_single(path, config, state)
        return 0 if success else 1
    else:
        parser.print_help()
        return 1


if __name__ == '__main__':
    sys.exit(main())
