#!/usr/bin/env python3
"""
Media Orchestrator Daemon

Monitors download completion events from qBittorrent, SABnzbd, and Soulseek,
then triggers library rescans in Sonarr, Radarr, and Lidarr.

Features:
- Watches NDJSON event spool files
- Validates file stability before triggering rescans
- Exports Prometheus metrics
- Graceful shutdown handling
- Comprehensive logging

Configuration:
    Environment Variables:
        SPOOL_DIR: Event spool directory (default: /mnt/hot/events)
        PROM_FILE: Prometheus metrics file (default: /var/lib/node_exporter/textfile_collector/media_orchestrator.prom)
        SONARR_URL: Sonarr base URL (default: http://localhost:8989)
        RADARR_URL: Radarr base URL (default: http://localhost:7878)
        LIDARR_URL: Lidarr base URL (default: http://localhost:8686)
        SONARR_API_KEY: Sonarr API key (required)
        RADARR_API_KEY: Radarr API key (required)
        LIDARR_API_KEY: Lidarr API key (required)
        STABILITY_TIMEOUT: File stability check timeout in seconds (default: 15)

Exit Codes:
    0: Clean shutdown
    1: Configuration error
    2: Runtime error
"""

import os
import sys
import time
import json
import signal
import logging
import argparse
import subprocess
import threading
from pathlib import Path
from typing import Dict, Optional, Tuple, List, Any
from dataclasses import dataclass, field
from queue import Queue, Empty
from contextlib import contextmanager

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class Config:
    """Media orchestrator configuration."""

    spool_dir: Path
    prom_file: Path
    sonarr_url: str
    radarr_url: str
    lidarr_url: str
    sonarr_api_key: str
    radarr_api_key: str
    lidarr_api_key: str
    stability_timeout: int = 15
    poll_interval: float = 0.5
    http_timeout: int = 10

    @classmethod
    def from_environment(cls) -> 'Config':
        """
        Create configuration from environment variables.

        Returns:
            Config: Configuration instance

        Raises:
            ValueError: If required configuration is missing
        """
        spool_dir = Path(os.getenv("SPOOL_DIR", "/mnt/hot/events"))
        prom_file = Path(os.getenv(
            "PROM_FILE",
            "/var/lib/node_exporter/textfile_collector/media_orchestrator.prom"
        ))

        # Required API keys
        sonarr_key = os.getenv("SONARR_API_KEY", "")
        radarr_key = os.getenv("RADARR_API_KEY", "")
        lidarr_key = os.getenv("LIDARR_API_KEY", "")

        if not all([sonarr_key, radarr_key, lidarr_key]):
            raise ValueError(
                "Missing required API keys. Set SONARR_API_KEY, RADARR_API_KEY, LIDARR_API_KEY"
            )

        return cls(
            spool_dir=spool_dir,
            prom_file=prom_file,
            sonarr_url=os.getenv("SONARR_URL", "http://localhost:8989"),
            radarr_url=os.getenv("RADARR_URL", "http://localhost:7878"),
            lidarr_url=os.getenv("LIDARR_URL", "http://localhost:8686"),
            sonarr_api_key=sonarr_key,
            radarr_api_key=radarr_key,
            lidarr_api_key=lidarr_key,
            stability_timeout=int(os.getenv("STABILITY_TIMEOUT", "15"))
        )

    def validate(self) -> None:
        """
        Validate configuration.

        Raises:
            ValueError: If configuration is invalid
        """
        if not self.spool_dir.parent.exists():
            raise ValueError(f"Spool directory parent does not exist: {self.spool_dir.parent}")

        if not self.prom_file.parent.exists():
            self.prom_file.parent.mkdir(parents=True, exist_ok=True)


@dataclass
class ProcessingResult:
    """Result of processing an event."""

    action: str
    status: str

    def to_metric_key(self) -> Tuple[str, str]:
        """Convert to Prometheus metric key."""
        return (self.action, self.status)


class FileStabilityChecker:
    """Checks if files are stable and not in use."""

    def __init__(self, timeout: int = 15):
        """
        Initialize stability checker.

        Args:
            timeout: Seconds to wait between size checks
        """
        self.timeout = timeout

    def is_stable(self, path: Path) -> bool:
        """
        Check if file size is stable.

        Args:
            path: Path to check

        Returns:
            bool: True if file exists and size is stable
        """
        if not path.exists():
            return False

        try:
            initial_size = path.stat().st_size
            time.sleep(self.timeout)

            if not path.exists():
                return False

            return path.stat().st_size == initial_size

        except OSError as e:
            logger.warning(f"Error checking file stability for {path}: {e}")
            return False

    def is_in_use(self, path: Path) -> bool:
        """
        Check if file is currently in use.

        Args:
            path: Path to check

        Returns:
            bool: True if file is in use
        """
        try:
            result = subprocess.run(
                ["/run/current-system/sw/bin/fuser", "-s", str(path)],
                capture_output=True,
                timeout=5
            )
            return result.returncode == 0

        except subprocess.TimeoutExpired:
            logger.warning(f"Timeout checking if file is in use: {path}")
            return True  # Assume in use if check times out
        except FileNotFoundError:
            logger.debug("fuser command not found, skipping in-use check")
            return False
        except Exception as e:
            logger.warning(f"Error checking if file is in use: {e}")
            return True  # Assume in use on error


class MediaServiceClient:
    """Client for interacting with media services (Sonarr, Radarr, Lidarr)."""

    def __init__(self, config: Config):
        """
        Initialize media service client.

        Args:
            config: Configuration instance
        """
        self.config = config
        self.session = requests.Session()

    def _post_command(
        self,
        base_url: str,
        api_key: str,
        api_path: str,
        body: Dict[str, Any]
    ) -> bool:
        """
        Post command to media service.

        Args:
            base_url: Base URL of service
            api_key: API key
            api_path: API path (e.g., /api/v3/command)
            body: JSON body

        Returns:
            bool: True if successful
        """
        url = f"{base_url}{api_path}"
        headers = {"X-Api-Key": api_key}

        try:
            response = self.session.post(
                url,
                headers=headers,
                json=body,
                timeout=self.config.http_timeout
            )
            response.raise_for_status()
            logger.info(f"Command sent to {base_url}: {body['name']}")
            return True

        except requests.Timeout:
            logger.error(f"Timeout posting to {url}")
            return False
        except requests.RequestException as e:
            logger.error(f"Error posting to {url}: {e}")
            return False

    def rescan_sonarr(self, path: str) -> bool:
        """Trigger Sonarr rescan."""
        return self._post_command(
            self.config.sonarr_url,
            self.config.sonarr_api_key,
            "/api/v3/command",
            {"name": "RescanFolders", "folders": [path]}
        )

    def rescan_radarr(self, path: str) -> bool:
        """Trigger Radarr rescan."""
        return self._post_command(
            self.config.radarr_url,
            self.config.radarr_api_key,
            "/api/v3/command",
            {"name": "RescanFolders", "folders": [path]}
        )

    def rescan_lidarr(self, path: str) -> bool:
        """Trigger Lidarr rescan."""
        return self._post_command(
            self.config.lidarr_url,
            self.config.lidarr_api_key,
            "/api/v1/command",
            {"name": "RescanFolders", "folders": [path]}
        )


class EventProcessor:
    """Processes download completion events."""

    def __init__(self, config: Config):
        """
        Initialize event processor.

        Args:
            config: Configuration instance
        """
        self.config = config
        self.stability_checker = FileStabilityChecker(config.stability_timeout)
        self.media_client = MediaServiceClient(config)

    def process(self, event: Dict[str, Any]) -> ProcessingResult:
        """
        Process a download completion event.

        Args:
            event: Event dictionary

        Returns:
            ProcessingResult: Processing result with action and status
        """
        # Extract event fields
        client = event.get("client", "")
        category = (event.get("category") or "").lower()
        path_str = event.get("content_path") or event.get("final_dir") or ""

        # Validate path
        if not path_str:
            return ProcessingResult("ignored", "no_path")

        path = Path(path_str)
        if not path.exists():
            logger.debug(f"Path does not exist: {path}")
            return ProcessingResult("ignored", "path_not_found")

        # Check stability
        if self.stability_checker.is_in_use(path):
            logger.debug(f"File in use, deferring: {path}")
            return ProcessingResult("defer", "in_use")

        if not self.stability_checker.is_stable(path):
            logger.debug(f"File unstable, deferring: {path}")
            return ProcessingResult("defer", "unstable")

        # Process by client and category
        if client in ("qbt", "sab"):
            return self._process_torrent_client(category, path)
        elif client == "slskd":
            return self._process_soulseek(path)
        else:
            logger.debug(f"Unknown client: {client}")
            return ProcessingResult("ignored", "unknown_client")

    def _process_torrent_client(
        self,
        category: str,
        path: Path
    ) -> ProcessingResult:
        """Process event from torrent client (qBittorrent/SABnzbd)."""
        if "tv" in category:
            success = (
                self.media_client.rescan_sonarr(str(path)) or
                self.media_client.rescan_sonarr(str(path.parent))
            )
            return ProcessingResult("sonarr_rescan", "ok" if success else "fail")

        elif "movie" in category:
            success = (
                self.media_client.rescan_radarr(str(path)) or
                self.media_client.rescan_radarr(str(path.parent))
            )
            return ProcessingResult("radarr_rescan", "ok" if success else "fail")

        elif "music" in category:
            success = self.media_client.rescan_lidarr(str(path.parent))
            return ProcessingResult("lidarr_rescan", "ok" if success else "fail")

        elif "book" in category:
            return self._process_audiobook(path)

        else:
            logger.debug(f"Unknown category: {category}")
            return ProcessingResult("ignored", "unknown_category")

    def _process_audiobook(self, path: Path) -> ProcessingResult:
        """Process audiobook by calling audiobook-copier script."""
        # Path to audiobook-copier script
        copier_script = Path("/mnt/hot/downloads/scripts/audiobook-copier.py")

        if not copier_script.exists():
            logger.warning(f"Audiobook copier script not found: {copier_script}")
            return ProcessingResult("audiobook_copy", "script_not_found")

        try:
            result = subprocess.run(
                ["/run/current-system/sw/bin/python3", str(copier_script), str(path)],
                capture_output=True,
                text=True,
                timeout=3600  # 1 hour timeout for large audiobooks
            )

            if result.returncode == 0:
                logger.info(f"Audiobook copied: {path}")
                return ProcessingResult("audiobook_copy", "ok")
            else:
                logger.warning(f"Audiobook copy failed: {result.stderr}")
                return ProcessingResult("audiobook_copy", "fail")

        except subprocess.TimeoutExpired:
            logger.error(f"Audiobook copy timed out: {path}")
            return ProcessingResult("audiobook_copy", "timeout")
        except Exception as e:
            logger.error(f"Error processing audiobook: {e}")
            return ProcessingResult("audiobook_copy", "error")

    def _process_soulseek(self, path: Path) -> ProcessingResult:
        """Process event from Soulseek."""
        success = self.media_client.rescan_lidarr(str(path.parent))
        return ProcessingResult("lidarr_rescan", "ok" if success else "fail")


class SpoolFileWatcher:
    """Watches NDJSON spool files for new events."""

    def __init__(self, spool_files: List[Path], event_queue: Queue):
        """
        Initialize spool file watcher.

        Args:
            spool_files: List of spool files to watch
            event_queue: Queue to put events into
        """
        self.spool_files = spool_files
        self.event_queue = event_queue
        self.should_stop = threading.Event()
        self.thread: Optional[threading.Thread] = None

    def start(self) -> None:
        """Start watching spool files in background thread."""
        self.thread = threading.Thread(target=self._watch_files, daemon=True)
        self.thread.start()
        logger.info(f"Started watching {len(self.spool_files)} spool files")

    def stop(self) -> None:
        """Stop watching spool files."""
        self.should_stop.set()
        if self.thread:
            self.thread.join(timeout=5)

    def _watch_files(self) -> None:
        """Watch files for new lines (runs in background thread)."""
        # Open all files and seek to end
        file_handles = []
        try:
            for spool_file in self.spool_files:
                try:
                    fh = open(spool_file, 'r', encoding='utf-8')
                    fh.seek(0, 2)  # Seek to end
                    file_handles.append((spool_file, fh))
                    logger.debug(f"Watching: {spool_file}")
                except OSError as e:
                    logger.error(f"Failed to open {spool_file}: {e}")

            # Watch for new lines
            while not self.should_stop.is_set():
                for spool_file, fh in file_handles:
                    try:
                        line = fh.readline()
                        if line:
                            event = json.loads(line.strip())
                            self.event_queue.put(event)
                            logger.debug(f"Event from {spool_file.name}: {event}")
                    except json.JSONDecodeError as e:
                        logger.warning(f"Invalid JSON in {spool_file}: {e}")
                    except Exception as e:
                        logger.error(f"Error reading {spool_file}: {e}")

                time.sleep(0.5)

        finally:
            # Clean up file handles
            for _, fh in file_handles:
                try:
                    fh.close()
                except Exception as e:
                    logger.error(f"Error closing file handle: {e}")


class PrometheusExporter:
    """Exports metrics in Prometheus format."""

    def __init__(self, prom_file: Path):
        """
        Initialize Prometheus exporter.

        Args:
            prom_file: Path to Prometheus textfile collector file
        """
        self.prom_file = prom_file
        self.counters: Dict[Tuple[str, str], int] = {}

    def record_event(self, result: ProcessingResult) -> None:
        """
        Record an event.

        Args:
            result: Processing result to record
        """
        key = result.to_metric_key()
        self.counters[key] = self.counters.get(key, 0) + 1

    def export_metrics(self) -> None:
        """Export metrics to Prometheus textfile."""
        try:
            with open(self.prom_file, 'w', encoding='utf-8') as f:
                f.write("# HELP media_orchestrator_events_total Events handled by orchestrator\n")
                f.write("# TYPE media_orchestrator_events_total counter\n")

                for (action, status), count in sorted(self.counters.items()):
                    f.write(
                        f'media_orchestrator_events_total{{action="{action}",status="{status}"}} {count}\n'
                    )

            logger.debug(f"Metrics exported to {self.prom_file}")

        except OSError as e:
            logger.error(f"Failed to write metrics: {e}")


class MediaOrchestrator:
    """Main orchestrator daemon."""

    def __init__(self, config: Config):
        """
        Initialize media orchestrator.

        Args:
            config: Configuration instance
        """
        self.config = config
        self.event_queue: Queue = Queue()
        self.processor = EventProcessor(config)
        self.exporter = PrometheusExporter(config.prom_file)
        self.watcher: Optional[SpoolFileWatcher] = None
        self.should_stop = threading.Event()

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

    def _signal_handler(self, signum: int, frame: Any) -> None:
        """Handle shutdown signals."""
        logger.info(f"Received signal {signum}, shutting down...")
        self.should_stop.set()

    def _setup_spool_files(self) -> List[Path]:
        """
        Ensure spool files exist.

        Returns:
            List[Path]: List of spool file paths
        """
        self.config.spool_dir.mkdir(parents=True, exist_ok=True)

        spool_files = [
            self.config.spool_dir / "qbt.ndjson",
            self.config.spool_dir / "sab.ndjson",
            self.config.spool_dir / "slskd.ndjson"
        ]

        for spool_file in spool_files:
            spool_file.touch(exist_ok=True)
            logger.info(f"Spool file ready: {spool_file}")

        return spool_files

    def run(self) -> int:
        """
        Run the orchestrator daemon.

        Returns:
            int: Exit code
        """
        try:
            logger.info("Starting Media Orchestrator daemon")

            # Setup spool files
            spool_files = self._setup_spool_files()

            # Start watching spool files
            self.watcher = SpoolFileWatcher(spool_files, self.event_queue)
            self.watcher.start()

            # Main event loop
            logger.info("Entering main event loop")
            while not self.should_stop.is_set():
                try:
                    # Get event with timeout to allow checking should_stop
                    event = self.event_queue.get(timeout=1.0)

                    # Process event
                    result = self.processor.process(event)
                    logger.info(f"Processed event: action={result.action}, status={result.status}")

                    # Record metrics
                    self.exporter.record_event(result)
                    self.exporter.export_metrics()

                except Empty:
                    # No events, continue loop
                    continue
                except Exception as e:
                    logger.error(f"Error processing event: {e}", exc_info=True)

            logger.info("Shutting down gracefully")
            if self.watcher:
                self.watcher.stop()

            return 0

        except Exception as e:
            logger.error(f"Fatal error: {e}", exc_info=True)
            return 2


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Media Orchestrator - Download completion event processor"
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose logging'
    )
    parser.add_argument(
        '--log-level',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        default='INFO',
        help='Set logging level (default: INFO)'
    )
    return parser.parse_args()


def main() -> int:
    """
    Main entry point.

    Returns:
        int: Exit code
    """
    # Parse arguments
    args = parse_args()

    # Configure logging
    log_level = logging.DEBUG if args.verbose else getattr(logging, args.log_level)
    logging.getLogger().setLevel(log_level)

    try:
        # Load configuration
        config = Config.from_environment()
        config.validate()

        logger.info("Configuration loaded successfully")
        logger.info(f"Spool directory: {config.spool_dir}")
        logger.info(f"Metrics file: {config.prom_file}")

        # Run orchestrator
        orchestrator = MediaOrchestrator(config)
        return orchestrator.run()

    except ValueError as e:
        logger.error(f"Configuration error: {e}")
        return 1
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        return 0
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return 2


if __name__ == "__main__":
    sys.exit(main())
