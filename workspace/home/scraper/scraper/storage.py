"""Storage backends for scraped data."""

import csv
import json
from abc import ABC, abstractmethod
from pathlib import Path
from typing import IO

from .models import Post


class StorageBackend(ABC):
    """Abstract base class for storage backends."""

    @abstractmethod
    def open(self) -> None:
        """Open the storage for writing."""
        pass

    @abstractmethod
    def close(self) -> None:
        """Close the storage."""
        pass

    @abstractmethod
    def append(self, post: Post) -> None:
        """Append a single post."""
        pass

    def write_all(self, posts: list[Post]) -> None:
        """Write all posts."""
        for post in posts:
            self.append(post)

    def __enter__(self) -> "StorageBackend":
        self.open()
        return self

    def __exit__(self, *args) -> None:
        self.close()


class JSONLStorage(StorageBackend):
    """
    JSON Lines storage - one JSON object per line.

    Best for streaming and large datasets.
    """

    def __init__(self, path: Path):
        self.path = path
        self._file: IO | None = None

    def open(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = open(self.path, "w", encoding="utf-8")

    def close(self) -> None:
        if self._file:
            self._file.close()
            self._file = None

    def append(self, post: Post) -> None:
        if not self._file:
            raise RuntimeError("Storage not opened")
        # Convert comments to dicts for JSON serialization
        data = post.model_dump(mode="json")
        self._file.write(json.dumps(data, ensure_ascii=False) + "\n")
        self._file.flush()


class JSONStorage(StorageBackend):
    """
    Standard JSON array storage.

    Best for small datasets that need to be read as a whole.
    """

    def __init__(self, path: Path, indent: int = 2):
        self.path = path
        self.indent = indent
        self._posts: list[dict] = []

    def open(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._posts = []

    def close(self) -> None:
        self.path.write_text(
            json.dumps(self._posts, indent=self.indent, ensure_ascii=False),
            encoding="utf-8",
        )

    def append(self, post: Post) -> None:
        self._posts.append(post.model_dump(mode="json"))


class CSVStorage(StorageBackend):
    """
    CSV storage with proper escaping.

    Comments are serialized as JSON strings.
    """

    FIELDNAMES = [
        "source",
        "group",
        "author",
        "date",
        "text",
        "reactions",
        "comments_count",
        "comments_json",
        "url",
        "scraped_at",
    ]

    def __init__(self, path: Path):
        self.path = path
        self._file: IO | None = None
        self._writer: csv.DictWriter | None = None

    def open(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = open(self.path, "w", newline="", encoding="utf-8")
        self._writer = csv.DictWriter(self._file, fieldnames=self.FIELDNAMES)
        self._writer.writeheader()

    def close(self) -> None:
        if self._file:
            self._file.close()
            self._file = None
            self._writer = None

    def append(self, post: Post) -> None:
        if not self._writer:
            raise RuntimeError("Storage not opened")
        row = {
            "source": post.source,
            "group": post.group,
            "author": post.author,
            "date": post.date,
            "text": post.text,
            "reactions": post.reactions,
            "comments_count": post.comments_count,
            "comments_json": json.dumps(
                [c.model_dump() for c in post.comments], ensure_ascii=False
            ),
            "url": post.url,
            "scraped_at": post.scraped_at.isoformat(),
        }
        self._writer.writerow(row)
        if self._file:
            self._file.flush()


# Registry of available backends
STORAGE_BACKENDS: dict[str, type[StorageBackend]] = {
    "csv": CSVStorage,
    "json": JSONStorage,
    "jsonl": JSONLStorage,
}


def get_storage_backend(format: str, path: Path) -> StorageBackend:
    """
    Get a storage backend by format name.

    Args:
        format: One of 'csv', 'json', 'jsonl'
        path: Output file path

    Returns:
        Configured storage backend instance
    """
    if format not in STORAGE_BACKENDS:
        raise ValueError(f"Unknown format: {format}. Available: {list(STORAGE_BACKENDS.keys())}")
    return STORAGE_BACKENDS[format](path)
