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
    ("competitor_mention", "⚔️",  "Competing Tools"),
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
        print('[classify] Claude timed out after 180s', file=sys.stderr)
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


def derive_classification(scores):
    """Derive a label from Claude's scores. Deterministic."""
    # DataX mentioned by name = always a lead
    if scores.get('datax_mentioned'):
        return 'warm_lead'

    # Active platform migration
    if scores.get('migration'):
        return 'migration_signal'

    # High relevance + high actionability = lead
    if scores.get('datax_relevance', 0) >= 2 and scores.get('actionability', 0) >= 2:
        return 'warm_lead'

    # Named tool in DataX's domain
    if scores.get('extension_tool') and scores.get('datax_relevance', 0) >= 1:
        return 'competitor_mention'

    # Genuine pain with DataX relevance
    if scores.get('pain_level', 0) >= 2 and scores.get('datax_relevance', 0) >= 1:
        return 'pain_point'

    # Severe pain regardless of relevance
    if scores.get('pain_level', 0) >= 3:
        return 'pain_point'

    # Some relevance + some actionability
    if scores.get('datax_relevance', 0) >= 1 and scores.get('actionability', 0) >= 1:
        return 'feature_request'

    return 'general'


def should_notify(classification, scores):
    """Decide whether to send a Discord notification."""
    if classification == 'warm_lead':
        return True
    if classification == 'migration_signal':
        return True
    # Competitor in DataX's space (not Rendr, LiDAR scanners, etc.)
    if classification == 'competitor_mention' and scores.get('datax_relevance', 0) >= 2:
        return True
    # Pain that DataX specifically addresses
    if classification == 'pain_point' and scores.get('datax_relevance', 0) >= 2:
        return True
    return False


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
                       scores = %s,
                       last_updated = NOW()
                 WHERE post_id = %s
                   AND classification IS NULL
                """,
                (
                    r.get('classification'),
                    r.get('tags', []),
                    r.get('summary', ''),
                    json.dumps(r.get('scores', {})),
                    r['post_id'],
                ),
            )
            if cur.rowcount:
                updated += 1
    conn.commit()
    return updated


DISCORD_EMBED_TOTAL_LIMIT = 5800  # Discord hard limit is 6000; leave headroom


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

    summary_title = f"JT Pros — {total} notable post{'s' if total != 1 else ''}"
    summary_desc = ", ".join(counts)
    footer_text = f"fb-classifier · JT Pros · {date.today().isoformat()}"

    summary_embed = {
        "title": summary_title,
        "description": summary_desc,
        "color": SUMMARY_COLOR,
        "footer": {"text": footer_text},
    }

    # Track total chars across all embed fields (Discord limit: 6000)
    used = len(summary_title) + len(summary_desc) + len(footer_text)
    embeds = [summary_embed]

    for cls, emoji, label in CATEGORIES:
        posts = by_class.get(cls, [])
        if not posts:
            continue
        if len(embeds) >= 10:
            break

        embed_title = f"{emoji} {label} ({len(posts)})"
        used += len(embed_title)

        lines = []
        dropped = 0
        for p in posts:
            author = (p.get('author') or 'Unknown')[:40]
            summary = (p.get('summary') or '')[:100]
            url = p.get('url') or ''
            line = f"• [{author}]({url}) — {summary}" if url else f"• {author} — {summary}"

            if used + len('\n'.join(lines + [line])) > DISCORD_EMBED_TOTAL_LIMIT:
                dropped += 1
            else:
                lines.append(line)

        description = '\n'.join(lines)
        if dropped:
            note = f'\n*…and {dropped} more*'
            description += note
            used += len(note)
        used += len(description)

        embeds.append({
            "title": embed_title,
            "color": CATEGORY_COLORS.get(cls, 0x99AAB5),
            "description": description,
        })

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

            # Derive classification and notify flag from scores
            post_map = {p['post_id']: p for p in batch}
            for r in results:
                scores = r.get('scores', {})
                r['classification'] = derive_classification(scores)
                r['notify'] = should_notify(r['classification'], scores)
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
                    scores = r.get('scores', {})
                    tags = ', '.join(r.get('tags', []))
                    summary = (r.get('summary') or '')[:80]
                    notify_flag = '★' if r.get('notify') else ' '
                    rel = scores.get('datax_relevance', 0)
                    pain = scores.get('pain_level', 0)
                    act = scores.get('actionability', 0)
                    print(f"  {notify_flag} {r.get('post_id')}: [{r.get('classification')}] r={rel} p={pain} a={act} — {summary}")

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
