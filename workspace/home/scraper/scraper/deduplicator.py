"""Content-based deduplication for posts."""

from .logging_config import get_logger
from .models import Post


class PostDeduplicator:
    """
    Deduplicator using content hashing.

    Tracks posts by their content hash and handles updates.
    """

    def __init__(self) -> None:
        self.seen: dict[str, Post] = {}

    def add_or_update(self, post: Post) -> bool:
        """
        Add post if new, or update if content changed.

        Args:
            post: Post to add or update

        Returns:
            True if post was added/updated, False if duplicate
        """
        logger = get_logger()
        content_hash = post.content_hash

        if content_hash not in self.seen:
            self.seen[content_hash] = post
            return True

        # Check if this is an update (same author, different text length)
        existing = self.seen[content_hash]
        if len(post.text) > len(existing.text):
            logger.debug(f"Updating post {content_hash} with longer version")
            self.seen[content_hash] = post
            return True

        return False

    def get_unique_posts(self) -> list[Post]:
        """Get all unique posts."""
        return list(self.seen.values())

    def __len__(self) -> int:
        return len(self.seen)
