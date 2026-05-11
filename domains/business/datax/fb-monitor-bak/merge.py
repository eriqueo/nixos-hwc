#!/usr/bin/env python3
"""
fb-monitor merge script
Imports a Tampermonkey JSON export into the datax PostgreSQL database.

Usage:
    python3 merge.py /path/to/fb-group-2026-05-08.json

Connection:
    DATABASE_URL env var, or defaults to postgresql://datax@localhost/datax
"""

import hashlib
import json
import os
import sys
import psycopg2


def comment_hash(author: str, body: str) -> str:
    raw = (author or "")[:20] + "|" + (body or "")[:80]
    return hashlib.md5(raw.encode()).hexdigest()[:12]


def merge(conn, data: dict) -> dict:
    meta = data.get("_meta", {})
    posts = data.get("posts", [])
    source_url = meta.get("source", "")

    stats = {"posts_total": len(posts), "posts_new": 0, "posts_updated": 0, "comments_new": 0}

    with conn.cursor() as cur:
        for post in posts:
            post_id = post.get("postId")
            if not post_id:
                continue

            body = post.get("body", "")
            author = post.get("author")
            source_group = post.get("source")
            url = post.get("url")
            post_timestamp = post.get("timestamp")
            comment_count = post.get("commentCount", 0)
            comments = post.get("comments", [])

            # Check existing
            cur.execute("SELECT comment_count FROM fb_posts WHERE post_id = %s", (post_id,))
            row = cur.fetchone()

            if row is None:
                # INSERT new post
                cur.execute(
                    """
                    INSERT INTO fb_posts
                        (post_id, body, author, source_group, url,
                         post_timestamp, comment_count)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    """,
                    (post_id, body, author, source_group, url, post_timestamp, comment_count),
                )
                stats["posts_new"] += 1
            elif comment_count > row[0]:
                # UPDATE — new comments arrived
                cur.execute(
                    """
                    UPDATE fb_posts
                       SET comment_count = %s, last_updated = NOW()
                     WHERE post_id = %s
                    """,
                    (comment_count, post_id),
                )
                stats["posts_updated"] += 1
            # else: unchanged — skip

            # Merge comments
            for comment in comments:
                h = comment_hash(comment.get("author", ""), comment.get("body", ""))
                cur.execute(
                    """
                    INSERT INTO fb_comments
                        (post_id, comment_hash, author, body, depth, comment_timestamp)
                    VALUES (%s, %s, %s, %s, %s, %s)
                    ON CONFLICT (post_id, comment_hash) DO NOTHING
                    """,
                    (
                        post_id,
                        h,
                        comment.get("author"),
                        comment.get("body"),
                        comment.get("depth", 0),
                        comment.get("timestamp"),
                    ),
                )
                if cur.rowcount:
                    stats["comments_new"] += 1

        # Log the run
        cur.execute(
            """
            INSERT INTO fb_capture_log
                (source_url, posts_total, posts_new, posts_updated, comments_new)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (source_url, stats["posts_total"], stats["posts_new"],
             stats["posts_updated"], stats["comments_new"]),
        )

    conn.commit()
    return stats


def main():
    if len(sys.argv) < 2:
        print("Usage: fb-merge <export.json>", file=sys.stderr)
        sys.exit(1)

    path = sys.argv[1]
    with open(path) as f:
        data = json.load(f)

    db_url = os.environ.get("DATABASE_URL", "postgresql://datax@localhost/datax")
    conn = psycopg2.connect(db_url)

    try:
        stats = merge(conn, data)
    finally:
        conn.close()

    print(f"posts total   : {stats['posts_total']}")
    print(f"posts new     : {stats['posts_new']}")
    print(f"posts updated : {stats['posts_updated']}")
    print(f"comments new  : {stats['comments_new']}")


if __name__ == "__main__":
    main()
