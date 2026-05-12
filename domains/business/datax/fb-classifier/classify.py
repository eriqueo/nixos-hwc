#!/usr/bin/env python3
"""
fb-classifier — classify FB group posts using Claude CLI
Reads unclassified posts from PostgreSQL, classifies with Claude, updates DB,
and sends Discord notifications for notable findings.

Usage:
    classify.py [--limit N] [--dry-run]

Environment:
    DATABASE_URL          PostgreSQL DSN (default: postgresql://datax@localhost/datax)
    CLAUDE_BIN            Path to claude binary
    DISCORD_WEBHOOK_FILE  Path to file containing Discord webhook URL
    PROMPT_FILE           Path to classification prompt file
"""

import json
import os
import subprocess
import sys
import urllib.request
import urllib.error
import argparse
from datetime import date
import psycopg2


BATCH_SIZE = 10

CATEGORIES = [
    ("warm_lead",          "🟢", "Leads"),
    ("pain_point",         "🔴", "Pain Points"),
    ("migration_signal",   "🔄", "Migration"),
    ("competitor_mention", "⚔️",  "Competitors"),
    ("feature_request",    "💡", "Feature Gaps"),
]

CATEGORY_COLORS = {
    "warm_lead":          0x57F287,
    "pain_point":         0xED4245,
    "migration_signal":   0x3498DB,
    "competitor_mention": 0xF1C40F,
    "feature_request":    0xE67E22,
}

SUMMARY_COLOR = 0xCF995F  # Heartwood copper


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--limit', type=int, default=100, help='Max posts to classify per run')
    p.add_argument('--dry-run', action='store_true', help='Classify but skip DB updates and notifications')
    return p.parse_args()


def get_unclassified(conn, limit):
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT p.post_id, p.body, p.author, p.url, p.source_group,
                   p.comment_count,
                   COALESCE(
                     (SELECT string_agg(c.body, ' | ' ORDER BY c.id)
                      FROM fb_comments c WHERE c.post_id = p.post_id
                      LIMIT 5),
                     ''
                   ) AS top_comments
            FROM fb_posts p
            WHERE p.classification IS NULL
              AND p.body IS NOT NULL
              AND length(p.body) > 10
            ORDER BY p.first_captured DESC
            LIMIT %s
            """,
            (limit,),
        )
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def classify_batch(batch, claude_bin, prompt_text):
    posts_json = json.dumps(
        [
            {
                'post_id': p['post_id'],
                'author': p['author'],
                'body': (p['body'] or '')[:1000],
                'url': p.get('url', ''),
                'comment_count': p['comment_count'],
                'comments': [
                    {'author': '', 'body': c.strip(), 'depth': 0}
                    for c in (p['top_comments'] or '').split(' | ')
                    if c.strip()
                ],
            }
            for p in batch
        ],
        ensure_ascii=False,
        indent=2,
    )

    full_prompt = f"{prompt_text}\n\n{posts_json}"

    try:
        result = subprocess.run(
            [claude_bin, '--print', '-p', full_prompt],
            capture_output=True,
            text=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired:
        print('[classify] Claude timed out after 120s', file=sys.stderr)
        return None
    except FileNotFoundError:
        print(f'[classify] FATAL: claude binary not found at {claude_bin}', file=sys.stderr)
        sys.exit(1)

    if result.returncode != 0:
        print(f'[classify] Claude exited {result.returncode}: {result.stderr[:400]}', file=sys.stderr)
        return None

    raw = result.stdout.strip()

    # Strip markdown fences if present
    if '```' in raw:
        in_block = False
        clean_lines = []
        for line in raw.split('\n'):
            if line.startswith('```'):
                in_block = not in_block
                continue
            clean_lines.append(line)
        raw = '\n'.join(clean_lines)

    start = raw.find('{')
    end = raw.rfind('}')
    if start == -1 or end == -1:
        print(f'[classify] No JSON object in response: {raw[:200]}', file=sys.stderr)
        return None

    try:
        return json.loads(raw[start:end + 1])
    except json.JSONDecodeError as e:
        print(f'[classify] JSON parse error: {e}', file=sys.stderr)
        print(f'[classify] Raw snippet: {raw[start:start + 300]}', file=sys.stderr)
        return None


def update_classifications(conn, results):
    updated = 0
    with conn.cursor() as cur:
        for r in results:
            cur.execute(
                """
                UPDATE fb_posts
                   SET classification = %s,
                       classification_tags = %s,
                       notes = %s,
                       last_updated = NOW()
                 WHERE post_id = %s
                   AND classification IS NULL
                """,
                (
                    r.get('classification'),
                    r.get('tags', []),
                    r.get('summary', ''),
                    r['post_id'],
                ),
            )
            if cur.rowcount:
                updated += 1
    conn.commit()
    return updated


def build_discord_message(notify_posts):
    """Build list of Discord embed dicts, grouped by category."""
    by_class = {}
    for p in notify_posts:
        c = p.get('classification', 'unknown')
        by_class.setdefault(c, []).append(p)

    total = len(notify_posts)
    counts = []
    for cls, _, label in CATEGORIES:
        n = len(by_class.get(cls, []))
        if n:
            counts.append(f"{n} {label.lower()}")

    summary_embed = {
        "title": f"JT Pros — {total} notable post{'s' if total != 1 else ''}",
        "description": ", ".join(counts),
        "color": SUMMARY_COLOR,
        "footer": {"text": f"fb-classifier · JT Pros · {date.today().isoformat()}"},
    }

    embeds = [summary_embed]

    for cls, emoji, label in CATEGORIES:
        posts = by_class.get(cls, [])
        if not posts:
            continue

        lines = []
        for p in posts:
            author = (p.get('author') or 'Unknown')[:40]
            summary = (p.get('summary') or '')[:120]
            url = p.get('url') or ''
            if url:
                lines.append(f"• [{author}]({url}) — {summary}")
            else:
                lines.append(f"• {author} — {summary}")

        description = '\n'.join(lines)
        if len(description) > 4096:
            # Truncate to fit — drop trailing entries
            truncated = []
            dropped = 0
            for line in lines:
                candidate = '\n'.join(truncated + [line])
                if len(candidate) > 4000:
                    dropped += 1
                else:
                    truncated.append(line)
            description = '\n'.join(truncated)
            if dropped:
                description += f'\n*…and {dropped} more*'

        embeds.append({
            "title": f"{emoji} {label} ({len(posts)})",
            "color": CATEGORY_COLORS.get(cls, 0x99AAB5),
            "description": description,
        })

        if len(embeds) >= 10:
            break

    return embeds


def send_discord(webhook_url, notify_posts):
    """Build and send Discord embed message. Returns True on success."""
    if not notify_posts or not webhook_url:
        return False

    embeds = build_discord_message(notify_posts)

    payload = json.dumps({'embeds': embeds}).encode()
    req = urllib.request.Request(
        webhook_url,
        data=payload,
        headers={
            'Content-Type': 'application/json',
            'User-Agent': 'DiscordBot (hwc-datax, 1.0)',
        },
        method='POST',
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            if resp.status not in (200, 204):
                print(f'[classify] Discord returned HTTP {resp.status}', file=sys.stderr)
                return False
    except urllib.error.HTTPError as e:
        print(f'[classify] Discord failed: HTTP {e.code} — {e.read().decode()[:200]}', file=sys.stderr)
        return False
    except urllib.error.URLError as e:
        print(f'[classify] Discord failed: {e}', file=sys.stderr)
        return False
    return True


def main():
    args = parse_args()

    db_url = os.environ.get('DATABASE_URL', 'postgresql://datax@localhost/datax')
    claude_bin = os.environ.get('CLAUDE_BIN', '/etc/profiles/per-user/eric/bin/claude')
    webhook_file = os.environ.get('DISCORD_WEBHOOK_FILE', '')
    prompt_file = os.environ.get('PROMPT_FILE', '')

    if not prompt_file or not os.path.exists(prompt_file):
        print(f'[classify] FATAL: PROMPT_FILE not set or not found: {prompt_file!r}', file=sys.stderr)
        sys.exit(1)

    with open(prompt_file) as f:
        prompt_text = f.read().strip()

    webhook_url = ''
    if webhook_file and os.path.exists(webhook_file):
        with open(webhook_file) as f:
            webhook_url = f.read().strip()

    conn = psycopg2.connect(db_url)
    try:
        posts = get_unclassified(conn, args.limit)
        if not posts:
            print('[classify] No unclassified posts — nothing to do.')
            return

        print(f'[classify] {len(posts)} unclassified posts to process')

        all_notify = []
        total_updated = 0

        for i in range(0, len(posts), BATCH_SIZE):
            batch = posts[i:i + BATCH_SIZE]
            batch_num = i // BATCH_SIZE + 1
            print(f'[classify] Batch {batch_num}: classifying {len(batch)} posts...')

            parsed = classify_batch(batch, claude_bin, prompt_text)
            if not parsed:
                print(f'[classify] Batch {batch_num} failed — skipping', file=sys.stderr)
                continue

            results = parsed.get('results', [])

            # Attach url/author from original post for Discord message
            post_map = {p['post_id']: p for p in batch}
            for r in results:
                src = post_map.get(r.get('post_id', ''), {})
                r['url'] = src.get('url', '')
                r['author'] = src.get('author', '')

            notify = [r for r in results if r.get('notify')]
            all_notify.extend(notify)

            if not args.dry_run:
                updated = update_classifications(conn, results)
                total_updated += updated
                print(f'[classify] Batch {batch_num}: updated {updated}/{len(results)} posts ({len(notify)} notify)')
            else:
                print(f'[classify] [dry-run] Batch {batch_num}: would update {len(results)} posts')
                for r in results:
                    tags = ', '.join(r.get('tags', []))
                    summary = (r.get('summary') or '')[:80]
                    notify_flag = '★' if r.get('notify') else ' '
                    print(f"  {notify_flag} {r.get('post_id')}: [{r.get('classification')}] {tags} — {summary}")

        if all_notify and not args.dry_run:
            ok = send_discord(webhook_url, all_notify)
            if ok:
                print(f'[classify] Discord notified ({len(all_notify)} posts)')
            elif webhook_url:
                print(f'[classify] Discord notification failed — check logs', file=sys.stderr)

        print(f'[classify] Done. Total updated: {total_updated}')
    finally:
        conn.close()


if __name__ == '__main__':
    main()
