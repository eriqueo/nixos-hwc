"""
X (Twitter) post extraction.

A post comes from X's public syndication endpoint (no login, the one embedded
tweets use). GraphQL with a guest token then fills in what syndication leaves
out: the full text of long posts, complete metrics, and the reply pointer the
thread walk follows. Enrichment is best-effort; a post still saves without it.

Threads unroll backward only: each post names its parent, but listing a
post's replies needs a login. Pass the LAST post of a thread to get all of it.

Adapted from github.com/itsbigdill/x-post-to-json (lib/tweet.mjs).
"""

import json
import logging
import math
import re
import time
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

import requests

from transcript import TranscriptError

logger = logging.getLogger("transcripts")

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/124.0 Safari/537.36")

# X's public web-client bearer and a TweetResultByRestId query ID. Both are X
# internals that rotate; when they break, enrichment returns None and posts
# save from syndication alone (long posts then carry a truncation note).
BEARER = ("AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D"
          "1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA")
GQL_QUERY_ID = "0hWvDhmW8YQ-S_ib3azIrw"
GQL_FEATURES = {
    "creator_subscriptions_tweet_preview_api_enabled": True,
    "tweetypie_unmention_optimization_enabled": True,
    "responsive_web_edit_tweet_api_enabled": True,
    "graphql_is_translatable_rweb_tweet_is_translatable_enabled": True,
    "view_counts_everywhere_api_enabled": True,
    "longform_notetweets_consumption_enabled": True,
    "responsive_web_twitter_article_tweet_consumption_enabled": True,
    "tweet_awards_web_tipping_enabled": False,
    "freedom_of_speech_not_reach_fetch_enabled": True,
    "standardized_nudges_misinfo": True,
    "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": True,
    "longform_notetweets_rich_text_read_enabled": True,
    "longform_notetweets_inline_media_enabled": True,
    "responsive_web_graphql_exclude_directive_enabled": True,
    "verified_phone_label_enabled": False,
    "responsive_web_graphql_skip_user_profile_image_extensions_enabled": False,
    "responsive_web_graphql_timeline_navigation_enabled": True,
    "responsive_web_enhance_cards_enabled": False,
    "c9s_tweet_anatomy_moderator_badge_enabled": True,
    "rweb_video_timestamps_enabled": True,
    "communities_web_enable_tweet_community_results_fetch": True,
    "articles_preview_enabled": True,
    "creator_subscriptions_quote_tweet_preview_enabled": False,
}

HTTP_TIMEOUT = 15
GUEST_TOKEN_TTL = 600   # seconds; one token serves a whole thread walk
MAX_THREAD = 50


# ---------------------------------------------------------------------------
# Post ID extraction
# ---------------------------------------------------------------------------
_POST_PATTERN = re.compile(
    r"(?:^|[/.])(?:x|twitter|fxtwitter|vxtwitter|fixupx)\.com/(?:[^/?#\s]+/)*status(?:es)?/(\d+)",
    re.IGNORECASE)


def extract_post_id(url: str) -> Optional[str]:
    m = _POST_PATTERN.search(url.strip())
    return m.group(1) if m else None


def post_url(post_id: str) -> str:
    return f"https://x.com/i/status/{post_id}"


# ---------------------------------------------------------------------------
# Fetching
# ---------------------------------------------------------------------------
def _syndication_token(post_id: str) -> str:
    """((id / 1e15) * PI) in base 36 with zeros and the point removed — what
    react-tweet sends. The endpoint has not been checking it, so matching JS's
    exact float digits is not attempted past the first dozen."""
    x = int(post_id) / 1e15 * math.pi
    digits = "0123456789abcdefghijklmnopqrstuvwxyz"
    whole, frac = int(x), x - int(x)
    out = ""
    while whole:
        whole, r = divmod(whole, 36)
        out = digits[r] + out
    for _ in range(12):
        if not frac:
            break
        frac *= 36
        out += digits[int(frac)]
        frac -= int(frac)
    return out.replace("0", "") or "0"


def fetch_syndication(post_id: str) -> dict:
    params = {
        "id": post_id, "token": _syndication_token(post_id), "lang": "en",
        "features": "tfw_timeline_list:;tfw_follower_count_sunset:true;"
                    "tfw_tweet_edit_backend:on;tfw_refsrc_session:on",
    }
    try:
        res = requests.get("https://cdn.syndication.twimg.com/tweet-result", params=params,
                           headers={"User-Agent": UA, "Accept": "application/json"},
                           timeout=HTTP_TIMEOUT)
    except requests.Timeout:
        raise TranscriptError("timeout", f"X post {post_id}")
    except requests.RequestException as e:
        raise TranscriptError("error", f"X post {post_id}: {type(e).__name__}: {e}")
    if res.status_code == 429:
        raise TranscriptError("rate_limited", f"X answered 429 for post {post_id}")
    body = res.text.strip()
    if not body.startswith("{"):
        raise TranscriptError("unavailable", f"X post {post_id} is deleted, protected, "
                              f"age-gated or suspended (HTTP {res.status_code})")
    try:
        raw = json.loads(body)
    except ValueError as e:
        raise TranscriptError("error", f"X post {post_id}: bad JSON: {e}")
    if raw.get("__typename") == "TweetTombstone":
        reason = ((raw.get("tombstone") or {}).get("text") or {}).get("text") or "tombstoned"
        raise TranscriptError("unavailable", f"X post {post_id}: {reason}")
    return raw


_guest = {"token": None, "at": 0.0}


def _guest_token() -> Optional[str]:
    if _guest["token"] and time.monotonic() - _guest["at"] < GUEST_TOKEN_TTL:
        return _guest["token"]
    res = requests.post("https://api.twitter.com/1.1/guest/activate.json",
                        headers={"Authorization": f"Bearer {BEARER}", "User-Agent": UA},
                        timeout=HTTP_TIMEOUT)
    token = res.json().get("guest_token") if res.ok else None
    _guest.update(token=token, at=time.monotonic())
    return token


def fetch_graphql(post_id: str) -> Optional[dict]:
    """GraphQL view of the post, or None when X refuses the guest request."""
    try:
        token = _guest_token()
        if not token:
            return None
        variables = {"tweetId": post_id, "withCommunity": False,
                     "includePromotedContent": False, "withVoice": False}
        url = (f"https://api.twitter.com/graphql/{GQL_QUERY_ID}/TweetResultByRestId"
               f"?variables={urllib.parse.quote(json.dumps(variables))}"
               f"&features={urllib.parse.quote(json.dumps(GQL_FEATURES))}")
        res = requests.get(url, headers={"Authorization": f"Bearer {BEARER}",
                                         "x-guest-token": token, "User-Agent": UA},
                           timeout=HTTP_TIMEOUT)
        if res.status_code in (401, 403):
            _guest["token"] = None  # stale guest token; the next call mints a new one
        if not res.ok:
            logger.info(f"X GraphQL {post_id}: HTTP {res.status_code}")
            return None
        result = ((res.json().get("data") or {}).get("tweetResult") or {}).get("result")
        return (result or {}).get("tweet") or result
    except (requests.RequestException, ValueError) as e:
        logger.info(f"X GraphQL {post_id}: {type(e).__name__}: {e}")
        return None


# ---------------------------------------------------------------------------
# Normalize
# ---------------------------------------------------------------------------
def _media(items: list[dict]) -> list[dict]:
    """Syndication `mediaDetails` and GraphQL `extended_entities.media` share
    this item shape."""
    out = []
    for m in items:
        url = m.get("media_url_https")
        if m.get("type") != "photo":
            mp4 = [v for v in (m.get("video_info") or {}).get("variants") or []
                   if v.get("content_type") == "video/mp4"]
            if mp4:
                url = max(mp4, key=lambda v: v.get("bitrate") or 0)["url"]
        out.append({"type": m.get("type"), "url": url, "poster": m.get("media_url_https"),
                    "alt": m.get("ext_alt_text")})
    return out


def _user(u: Optional[dict]) -> dict:
    u = u or {}
    handle = u.get("screen_name")
    return {"name": u.get("name"), "handle": handle,
            "url": f"https://x.com/{handle}" if handle else None,
            "verified": bool(u.get("is_blue_verified") or u.get("verified"))}


def _expand_links(text: str, entities: dict, media_links: set[str]) -> str:
    """t.co links -> their real targets; links that only point at attached
    media are dropped, because the media is listed separately."""
    for u in entities.get("urls") or []:
        if u.get("url") and u.get("expanded_url"):
            text = text.replace(u["url"], u["expanded_url"])
    for link in media_links:
        text = text.replace(link, "")
    return text.strip()


def normalize(raw: dict) -> dict:
    handle = (raw.get("user") or {}).get("screen_name")
    media_links = {m["url"] for m in (raw.get("entities") or {}).get("media") or [] if m.get("url")}
    media_links |= {m["url"] for m in raw.get("mediaDetails") or [] if m.get("url")}
    quoted = raw.get("quoted_tweet")
    return {
        "id": raw.get("id_str"),
        "url": f"https://x.com/{handle}/status/{raw.get('id_str')}" if handle else post_url(raw.get("id_str") or ""),
        "text": _expand_links(raw.get("text") or "", raw.get("entities") or {}, media_links),
        "is_long_form": bool(raw.get("note_tweet")),
        "truncated": bool(raw.get("note_tweet")),
        "created_at": raw.get("created_at"),
        "author": _user(raw.get("user")),
        "metrics": {"likes": raw.get("favorite_count"), "reposts": raw.get("retweet_count"),
                    "replies": raw.get("reply_count") or raw.get("conversation_count"),
                    "quotes": raw.get("quote_count"), "bookmarks": raw.get("bookmark_count"),
                    "views": int(raw["view_count_str"]) if raw.get("view_count_str") else None},
        "media": _media(raw.get("mediaDetails") or []),
        "in_reply_to": raw.get("in_reply_to_status_id_str"),
        "quoted": normalize(quoted) if quoted else None,
        "_media_links": media_links,
    }


def apply_graphql(post: dict, g: Optional[dict]) -> dict:
    if not g:
        return post
    legacy = g.get("legacy") or {}
    note = ((g.get("note_tweet") or {}).get("note_tweet_results") or {}).get("result") or {}
    if note.get("text"):
        post["text"] = _expand_links(note["text"], note.get("entity_set") or {}, post["_media_links"])
        post["truncated"] = False
    elif legacy.get("full_text") and not post["is_long_form"]:
        post["text"] = _expand_links(legacy["full_text"], legacy.get("entities") or {}, post["_media_links"])

    def num(key, fallback):
        v = legacy.get(key)
        return v if isinstance(v, int) else fallback

    m = post["metrics"]
    views = (g.get("views") or {}).get("count")
    post["metrics"] = {"likes": num("favorite_count", m["likes"]), "reposts": num("retweet_count", m["reposts"]),
                       "replies": num("reply_count", m["replies"]), "quotes": num("quote_count", m["quotes"]),
                       "bookmarks": num("bookmark_count", m["bookmarks"]),
                       "views": int(views) if views else m["views"]}
    if legacy.get("in_reply_to_status_id_str"):
        post["in_reply_to"] = legacy["in_reply_to_status_id_str"]
    return post


def fetch_post(post_id: str) -> dict:
    post = apply_graphql(normalize(fetch_syndication(post_id)), fetch_graphql(post_id))
    post.pop("_media_links", None)
    if post["quoted"]:
        post["quoted"].pop("_media_links", None)
    return post


def fetch_thread(post_id: str, on_stage=lambda stage: None) -> list[dict]:
    """The post plus the author's own posts above it, oldest first. The walk
    stops at a reply to someone else, an unavailable parent, or MAX_THREAD."""
    on_stage("fetching post")
    chain = [fetch_post(post_id)]
    author = (chain[0]["author"]["handle"] or "").lower()
    while chain[0]["in_reply_to"] and len(chain) < MAX_THREAD:
        on_stage(f"walking thread ({len(chain)} posts)")
        try:
            parent = fetch_post(chain[0]["in_reply_to"])
        except TranscriptError as e:
            logger.info(f"X thread walk stopped at {chain[0]['in_reply_to']}: {e}")
            break
        if (parent["author"]["handle"] or "").lower() != author:
            break
        chain.insert(0, parent)
    return chain


# ---------------------------------------------------------------------------
# Logged-in conversation (TweetDetail responses captured by xbrowser)
# ---------------------------------------------------------------------------
# What a capture saves. `post` needs no login; the other three read the
# conversation through a logged-in browser.
X_MODES = ("post", "thread", "replies", "author_replies")
LOGIN_MODES = frozenset({"thread", "replies", "author_replies"})
REPLY_LIMIT_DEFAULT = 200
REPLY_LIMIT_MAX = 1000


def x_key(post_id: str, mode: str) -> str:
    """Library key of a saved X capture. `post` keeps the bare `x:<id>` key
    that files saved before modes existed carry."""
    return f"x:{post_id}" if mode == "post" else f"x:{post_id}:{mode}"


def _iso_from_legacy(stamp: Optional[str]) -> Optional[str]:
    """GraphQL `legacy.created_at` ("Sun May 03 02:04:20 +0000 2015") -> ISO."""
    if not stamp:
        return None
    try:
        return datetime.strptime(stamp, "%a %b %d %H:%M:%S %z %Y").isoformat()
    except ValueError:
        return stamp


def normalize_graphql(result: Optional[dict]) -> Optional[dict]:
    """A GraphQL tweet result in the same shape normalize() returns."""
    if not result:
        return None
    if result.get("__typename") == "TweetWithVisibilityResults":
        result = result.get("tweet") or {}
    if not result.get("rest_id"):
        return None  # TweetTombstone / TweetUnavailable
    legacy = result.get("legacy") or {}
    user = ((result.get("core") or {}).get("user_results") or {}).get("result") or {}
    ucore = user.get("core") or user.get("legacy") or {}
    handle = ucore.get("screen_name")
    media_items = (legacy.get("extended_entities") or {}).get("media") or []
    media_links = {m["url"] for m in media_items if m.get("url")}
    note = ((result.get("note_tweet") or {}).get("note_tweet_results") or {}).get("result") or {}
    if note.get("text"):
        text = _expand_links(note["text"], note.get("entity_set") or {}, media_links)
    else:
        text = _expand_links(legacy.get("full_text") or "", legacy.get("entities") or {}, media_links)
    views = (result.get("views") or {}).get("count")
    quoted = ((result.get("quoted_status_result") or {}).get("result"))
    return {
        "id": result["rest_id"],
        "url": f"https://x.com/{handle}/status/{result['rest_id']}" if handle else post_url(result["rest_id"]),
        "text": text,
        "is_long_form": bool(note),
        "truncated": False,
        "created_at": _iso_from_legacy(legacy.get("created_at")),
        "author": {"name": ucore.get("name"), "handle": handle,
                   "url": f"https://x.com/{handle}" if handle else None,
                   "verified": bool(user.get("is_blue_verified"))},
        "metrics": {"likes": legacy.get("favorite_count"), "reposts": legacy.get("retweet_count"),
                    "replies": legacy.get("reply_count"), "quotes": legacy.get("quote_count"),
                    "bookmarks": legacy.get("bookmark_count"), "views": int(views) if views else None},
        "media": _media(media_items),
        "in_reply_to": legacy.get("in_reply_to_status_id_str"),
        "quoted": normalize_graphql(quoted) if quoted else None,
    }


@dataclass
class Conversation:
    """Posts seen across a capture's TweetDetail responses, in first-seen
    order. Promoted posts are dropped at parse time."""
    posts: dict = field(default_factory=dict)   # id -> normalized post
    has_bottom_cursor: bool = False             # of the LAST page parsed
    show_more: int = 0                          # ShowMore/ShowMoreThreads cursors seen

    def add(self, payload: dict) -> None:
        self.has_bottom_cursor = False
        data = (payload.get("data") or {}).get("threaded_conversation_with_injections_v2") or {}
        for ins in data.get("instructions") or []:
            for entry in ins.get("entries") or []:
                self._entry(entry)
            if ins.get("entry"):  # TimelineReplaceEntry / AddToModule carry one
                self._entry(ins["entry"])
            for item in ins.get("moduleItems") or []:
                self._item(item.get("entryId", ""), (item.get("item") or {}).get("itemContent") or {})

    def _entry(self, entry: dict) -> None:
        c = entry.get("content") or {}
        kind = c.get("entryType") or c.get("__typename")
        if kind == "TimelineTimelineItem":
            self._item(entry.get("entryId", ""), c.get("itemContent") or {})
        elif kind == "TimelineTimelineModule":
            for it in c.get("items") or []:
                self._item(it.get("entryId", ""), (it.get("item") or {}).get("itemContent") or {})
        elif kind == "TimelineTimelineCursor":
            self._cursor(c)

    def _item(self, entry_id: str, ic: dict) -> None:
        if ic.get("itemType") == "TimelineTimelineCursor" or ic.get("__typename") == "TimelineTimelineCursor":
            self._cursor(ic)
            return
        if "promoted" in entry_id or "promotedMetadata" in ic:
            return
        post = normalize_graphql((ic.get("tweet_results") or {}).get("result"))
        if post:
            self.posts.setdefault(post["id"], post)

    def _cursor(self, c: dict) -> None:
        if c.get("cursorType") == "Bottom":
            self.has_bottom_cursor = True
        elif c.get("cursorType") in ("ShowMore", "ShowMoreThreads", "ShowMoreThreadsPrompt"):
            self.show_more += 1


def _by_id(posts) -> list[dict]:
    return sorted(posts, key=lambda p: int(p["id"]))


def direct_replies(conv: Conversation, focal_id: str) -> list[dict]:
    """Replies to the focal post itself, in the order X ranked them."""
    return [p for p in conv.posts.values() if p["in_reply_to"] == focal_id]


def author_thread_below(conv: Conversation, focal_id: str, handle: str) -> list[dict]:
    """The author's chain continuing below the focal post: each link is the
    author's earliest reply to the previous link."""
    handle = handle.lower()
    chain, cur = [], focal_id
    while len(chain) < MAX_THREAD:
        nxt = [p for p in conv.posts.values()
               if p["in_reply_to"] == cur and (p["author"]["handle"] or "").lower() == handle]
        if not nxt:
            break
        cur = _by_id(nxt)[0]["id"]
        chain.append(conv.posts[cur])
    return chain


def author_posts(conv: Conversation, focal_id: str, handle: str) -> list[dict]:
    """Every captured post by the author in the conversation, oldest first."""
    handle = handle.lower()
    return _by_id(p for p in conv.posts.values()
                  if p["id"] != focal_id and (p["author"]["handle"] or "").lower() == handle)


# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------
def _fmt_num(n: Optional[int]) -> str:
    if n is None:
        return "—"
    for size, suffix in ((1e6, "M"), (1e3, "K")):
        if n >= size:
            return f"{n / size:.1f}".rstrip("0").rstrip(".") + suffix
    return str(n)


def _fmt_date(iso: Optional[str]) -> str:
    if not iso:
        return "unknown"
    try:
        return datetime.fromisoformat(iso.replace("Z", "+00:00")).strftime("%Y-%m-%d %H:%M UTC")
    except ValueError:
        return iso


def post_title(thread: list[dict]) -> str:
    first = thread[0]
    words = " ".join((first["text"] or "").split())
    snippet = words[:70].rsplit(" ", 1)[0] + "…" if len(words) > 70 else words
    return f"@{first['author']['handle']}: {snippet or 'post ' + first['id']}"


def _post_body(post: dict) -> str:
    parts = [post["text"]]
    if post["truncated"]:
        parts.append("*(Long post: X refused the full-text request, so this is the preview only.)*")
    for m in post["media"]:
        if m["type"] == "photo":
            parts.append(f"![{m['alt'] or 'image'}]({m['url']})")
        else:
            parts.append(f"[{m['type'] or 'video'}]({m['url']})")
    q = post["quoted"]
    if q:
        quoted = "\n".join(f"> {line}" for line in (q["text"] or "").splitlines()) or ">"
        parts.append(f"> Quoting **{q['author']['name']}** (@{q['author']['handle']}):\n>\n"
                     f"{quoted}\n>\n> {q['url']}")
    return "\n\n".join(p for p in parts if p)


def _stats(m: dict) -> str:
    return (f"{_fmt_num(m['likes'])} likes · {_fmt_num(m['reposts'])} reposts · "
            f"{_fmt_num(m['replies'])} replies · {_fmt_num(m['views'])} views")


def _listed(post: dict) -> str:
    a = post["author"]
    return (f"### @{a['handle']} · {_fmt_date(post['created_at'])} · "
            f"{_fmt_num(post['metrics']['likes'])} likes\n\n{_post_body(post)}\n\n{post['url']}")


SECTION_TITLE = {"replies": "Replies", "author_replies": "Author's replies"}


def format_markdown(thread: list[dict], requested_id: str, mode: str = "post",
                    listed: Optional[list[dict]] = None, coverage: str = "") -> str:
    """Same header shape as transcript.format_markdown. The **URL:** and
    **Mode:** lines hold the requested post and mode: the key the saved-file
    scan reads back (saved_x_key). `listed` is the replies / author's replies
    section for those modes; `coverage` says how complete it is."""
    first, last = thread[0], thread[-1]
    a = first["author"]
    if mode in SECTION_TITLE:
        source = f"X {SECTION_TITLE[mode].lower()} ({len(listed or [])}{coverage})"
    else:
        source = "X post" if len(thread) == 1 else f"X thread ({len(thread)} posts)"
    if len(thread) == 1:
        body = _post_body(first)
    else:
        body = "\n\n---\n\n".join(f"**{i}/{len(thread)}**\n\n{_post_body(p)}"
                                  for i, p in enumerate(thread, 1))
    if mode in SECTION_TITLE:
        items = "\n\n---\n\n".join(_listed(p) for p in listed or []) or "*(none captured)*"
        body += f"\n\n## {SECTION_TITLE[mode]} ({len(listed or [])}{coverage})\n\n{items}"
    return f"""# {post_title(thread)}

**Author:** {a['name']} (@{a['handle']}){' ✓' if a['verified'] else ''}
**Posted:** {_fmt_date(first['created_at'])}
**URL:** https://x.com/{a['handle']}/status/{requested_id}
**Mode:** {mode}
**Source:** {source}
**Stats:** {_stats(last['metrics'])}

---

{body}
"""


def saved_x_key(header: str) -> Optional[str]:
    """Library key (x_key) of a saved X file — the inverse of format_markdown.
    Header lines only, as in transcript.saved_video_id. A file without a
    **Mode:** line predates modes and is a `post` capture."""
    post_id, mode = None, "post"
    for line in header.splitlines():
        if line.strip() == "---":
            break
        if line.startswith("**Mode:**"):
            value = line.removeprefix("**Mode:**").strip()
            mode = value if value in X_MODES else mode
        elif "URL" in line and not post_id:
            post_id = extract_post_id(line)
    return x_key(post_id, mode) if post_id else None
