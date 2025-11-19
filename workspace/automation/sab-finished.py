#!/usr/bin/env python3
"""
SABnzbd Post-Processing Hook

Writes download completion events to NDJSON spool file for
downstream processing by media-orchestrator.

Environment Variables:
    SAB_PP_STATUS: Post-processing status from SABnzbd
    NZBNAME: Name of the downloaded NZB
    SAB_FINAL_DIR: Final directory path (preferred)
    SAB_COMPLETE_DIR: Completion directory path (fallback)
    SAB_CAT: Download category
    SPOOL_FILE: Path to spool file (default: /mnt/hot/events/sab.ndjson)

Exit Codes:
    0: Event written successfully
    1: Error occurred (permission denied, file I/O error, etc.)
"""

import os
import sys
import json
import time
import logging
from pathlib import Path
from typing import Dict, Any, Optional
from dataclasses import dataclass, asdict

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class DownloadEvent:
    """SABnzbd download completion event."""

    client: str
    time: int
    status: str
    nzb_name: str
    final_dir: str
    category: str

    @classmethod
    def from_environment(cls) -> 'DownloadEvent':
        """
        Create event from SABnzbd environment variables.

        Returns:
            DownloadEvent: Event populated from environment
        """
        return cls(
            client="sab",
            time=int(time.time()),
            status=os.getenv("SAB_PP_STATUS", ""),
            nzb_name=os.getenv("NZBNAME", ""),
            final_dir=os.getenv("SAB_FINAL_DIR") or os.getenv("SAB_COMPLETE_DIR", ""),
            category=os.getenv("SAB_CAT", "")
        )

    def to_dict(self) -> Dict[str, Any]:
        """
        Convert to dictionary for JSON serialization.

        Returns:
            Dict[str, Any]: Event as dictionary
        """
        return asdict(self)

    def is_valid(self) -> bool:
        """
        Check if event has minimum required data.

        Returns:
            bool: True if event has required fields
        """
        return bool(self.nzb_name)


def ensure_spool_directory(spool_file: Path) -> None:
    """
    Ensure spool file parent directory exists.

    Args:
        spool_file: Path to spool file

    Raises:
        PermissionError: If directory cannot be created due to permissions
        OSError: If directory creation fails for other reasons
    """
    try:
        spool_file.parent.mkdir(parents=True, exist_ok=True)
        logger.debug(f"Spool directory ready: {spool_file.parent}")
    except PermissionError as e:
        logger.error(f"Permission denied creating directory {spool_file.parent}: {e}")
        raise
    except OSError as e:
        logger.error(f"Failed to create directory {spool_file.parent}: {e}")
        raise


def write_event(event: DownloadEvent, spool_file: Path) -> None:
    """
    Write event to spool file in NDJSON format.

    Args:
        event: Download event to write
        spool_file: Path to spool file

    Raises:
        PermissionError: If file cannot be written due to permissions
        OSError: If file write operation fails
    """
    try:
        # Ensure parent directory exists
        ensure_spool_directory(spool_file)

        # Append event as NDJSON
        with open(spool_file, 'a', encoding='utf-8') as f:
            f.write(json.dumps(event.to_dict()) + '\n')

        logger.info(f"Event written: {event.nzb_name} (status: {event.status})")

    except PermissionError as e:
        logger.error(f"Permission denied writing to {spool_file}: {e}")
        raise
    except OSError as e:
        logger.error(f"Failed to write to {spool_file}: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error writing event: {e}")
        raise


def get_spool_file() -> Path:
    """
    Get spool file path from environment or use default.

    Returns:
        Path: Path to spool file
    """
    default_spool = "/mnt/hot/events/sab.ndjson"
    spool_path = os.getenv("SPOOL_FILE", default_spool)
    return Path(spool_path)


def main() -> int:
    """
    Main entry point for SABnzbd post-processing hook.

    Returns:
        int: Exit code (0 for success, 1 for failure)
    """
    try:
        # Get spool file path
        spool_file = get_spool_file()
        logger.debug(f"Using spool file: {spool_file}")

        # Create event from environment
        event = DownloadEvent.from_environment()

        # Validate event has required data
        if not event.is_valid():
            logger.warning("NZBNAME not set - skipping event (likely test run)")
            return 0

        # Write event
        write_event(event, spool_file)

        logger.debug("Post-processing hook completed successfully")
        return 0

    except PermissionError as e:
        logger.error(f"Permission error: {e}")
        return 1
    except OSError as e:
        logger.error(f"I/O error: {e}")
        return 1
    except Exception as e:
        logger.error(f"Unexpected error: {e}", exc_info=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
