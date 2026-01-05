"""Path management and atomic finalization helpers"""

import os
from pathlib import Path
from typing import Optional


def get_staging_path(output_directory: str, video_id: str, extension: str) -> Path:
    """
    Get staging path inside output directory for atomic finalization.

    Pattern: <output>/.staging/<video_id>_<timestamp>.<ext>
    Ensures same-filesystem atomic rename.
    """
    staging_dir = Path(output_directory) / ".staging"
    staging_dir.mkdir(parents=True, exist_ok=True)

    from datetime import datetime
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    filename = f"{video_id}_{timestamp}.{extension}"

    return staging_dir / filename


def is_same_filesystem(path1: Path, path2: Path) -> bool:
    """Check if two paths are on the same filesystem (st_dev match)"""
    try:
        dev1 = path1.stat().st_dev
        dev2 = path2.stat().st_dev
        return dev1 == dev2
    except (OSError, FileNotFoundError):
        # If either path doesn't exist, check parent directories
        return path1.parent.stat().st_dev == path2.parent.stat().st_dev


def atomic_move(src: Path, dst: Path) -> None:
    """
    Atomically move file from src to dst.

    - Same filesystem: os.rename() (atomic)
    - Cross-filesystem: copy to .tmp in dst dir → fsync → rename (atomic final step)
    """
    # Ensure destination parent exists
    dst.parent.mkdir(parents=True, exist_ok=True)

    if is_same_filesystem(src, dst):
        # Atomic rename (fast path)
        os.rename(src, dst)
    else:
        # Cross-filesystem: copy to .tmp then atomic rename
        import shutil
        tmp_path = dst.with_suffix(dst.suffix + ".tmp")

        # Copy file
        shutil.copy2(src, tmp_path)

        # Fsync to ensure data is written
        with open(tmp_path, "rb") as f:
            os.fsync(f.fileno())

        # Atomic rename
        os.rename(tmp_path, dst)

        # Remove source file
        src.unlink()


def cleanup_staging(output_directory: str, max_age_hours: int = 24) -> int:
    """
    Clean up stale staging files older than max_age_hours.
    Returns number of files cleaned.
    """
    staging_dir = Path(output_directory) / ".staging"
    if not staging_dir.exists():
        return 0

    import time
    now = time.time()
    max_age_seconds = max_age_hours * 3600
    cleaned = 0

    for file_path in staging_dir.iterdir():
        if file_path.is_file():
            age = now - file_path.stat().st_mtime
            if age > max_age_seconds:
                file_path.unlink()
                cleaned += 1

    return cleaned
