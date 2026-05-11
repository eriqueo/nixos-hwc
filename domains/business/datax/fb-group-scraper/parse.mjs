// FB GraphQL response parsers — ported from FB Group Capture v2.0.0
// Parses FB's internal API responses, not DOM content.

import { createHash } from 'node:crypto';

// ── Utilities ──

export function dig(obj, ...keys) {
  let cur = obj;
  for (const k of keys) {
    if (cur == null || typeof cur !== 'object') return undefined;
    cur = cur[k];
  }
  return cur;
}

export function walkTree(obj, fn, maxDepth = 15, depth = 0) {
  if (depth > maxDepth || !obj || typeof obj !== 'object') return;
  fn(obj);
  if (Array.isArray(obj)) {
    for (const item of obj) walkTree(item, fn, maxDepth, depth + 1);
  } else {
    for (const key of Object.keys(obj)) walkTree(obj[key], fn, maxDepth, depth + 1);
  }
}

function parseLines(text) {
  if (typeof text !== 'string') return text ? [text] : [];
  return text.split('\n')
    .map(l => { try { return JSON.parse(l.trim()); } catch { return null; } })
    .filter(Boolean);
}

// ── IDs & Dedup ──

export function extractPostId(url) {
  if (!url) return null;
  const m = url.match(/\/posts\/(\d+)/) || url.match(/\/permalink\/(\d+)/);
  return m ? m[1] : null;
}

export function commentKey(author, body) {
  return `${(author || '').slice(0, 20)}|${(body || '').slice(0, 80)}`;
}

export function makeCommentId(postId, comment) {
  return createHash('sha256')
    .update(`${postId}|${comment.author}|${(comment.body || '').slice(0, 100)}`)
    .digest('hex').slice(0, 16);
}

// ── Operation Name ──

export function getOpName(reqBody) {
  if (!reqBody || typeof reqBody !== 'string') return '';
  const m = reqBody.match(/fb_api_req_friendly_name=([^&]+)/);
  return m ? decodeURIComponent(m[1]) : '';
}

// ── Post Extraction ──

function findGroupName(story) {
  let name = null;
  walkTree(story, n => {
    if (!name && n?.__typename === 'Group' && n.name) name = n.name;
  }, 4);
  return name;
}

function extractPost(story) {
  const msg =
    dig(story, 'comet_sections', 'content', 'story', 'message', 'text') ||
    dig(story, 'comet_sections', 'content', 'story', 'comet_sections', 'message', 'story', 'message', 'text') ||
    dig(story, 'message', 'text');
  if (!msg || msg.length < 5) return null;

  const url = dig(story, 'comet_sections', 'timestamp', 'story', 'url') || null;
  const postId = extractPostId(url);
  if (!postId) return null; // require URL-based ID

  const actors = story.actors;
  const author = (Array.isArray(actors) && actors[0]?.name) || 'unknown';
  const source =
    dig(story, 'comet_sections', 'context_layout', 'story', 'comet_sections', 'title', 'story', 'to', 'name') ||
    dig(story, 'to', 'name') ||
    findGroupName(story) || '';

  let created = dig(story, 'comet_sections', 'timestamp', 'story', 'creation_time');
  if (!created) {
    const meta = dig(story, 'comet_sections', 'context_layout', 'story', 'comet_sections', 'metadata');
    if (Array.isArray(meta)) {
      for (const m of meta) { created = dig(m, 'story', 'creation_time'); if (created) break; }
    }
  }

  const feedback = dig(story, 'comet_sections', 'feedback');
  let commentCount = dig(feedback, 'story', 'story_ufi_container', 'story',
    'feedback_context', 'feedback_target_with_context', 'comment_rendering_instance', 'comments', 'total_count');
  let reactions = null;
  if (feedback) {
    walkTree(feedback, n => {
      if (commentCount == null && typeof n?.total_count === 'number') commentCount = n.total_count;
      if (reactions == null && n?.reaction_count != null) {
        reactions = typeof n.reaction_count === 'object' ? (n.reaction_count.count ?? null) : n.reaction_count;
      }
    }, 8);
  }

  // Preview comments from feed (depth 0 = top-level)
  const previewItems = dig(feedback, 'story', 'story_ufi_container', 'story',
    'feedback_context', 'interesting_top_level_comments');
  const comments = Array.isArray(previewItems)
    ? previewItems.map(item => {
        const c = item.comment || item;
        const body = (c.body && typeof c.body === 'object') ? c.body.text : (c.body || '');
        const a = dig(c, 'author', 'name') || 'unknown';
        return { author: a, body, depth: 0, timestamp: c.created_time || null, _key: commentKey(a, body) };
      }).filter(c => c.body)
    : [];

  return {
    postId, body: msg, author, source, url,
    timestamp: created, reactions, commentCount,
    comments, _commentsExpanded: false,
  };
}

/** Parse a feed response and extract posts. Skips posts without URL-based IDs. */
export function parseFeedResponse(text) {
  const lines = parseLines(text);
  const posts = [];

  for (const obj of lines) {
    const d = obj?.data;
    if (!d) continue;
    const edges = dig(d, 'node', 'group_feed', 'edges');
    if (Array.isArray(edges)) {
      for (const e of edges) {
        if (e?.node?.__typename === 'Story') {
          const post = extractPost(e.node);
          if (post && !posts.some(p => p.postId === post.postId)) posts.push(post);
        }
      }
      continue;
    }
    if (d.node?.__typename === 'Story') {
      const post = extractPost(d.node);
      if (post && !posts.some(p => p.postId === post.postId)) posts.push(post);
    }
  }
  return posts;
}

/** Find the postId from a single-post dialog response. */
export function findPostIdInResponse(text) {
  const lines = parseLines(text);
  for (const obj of lines) {
    let found = null;
    walkTree(obj, node => {
      if (!found && node?.__typename === 'Story') {
        found = extractPostId(dig(node, 'comet_sections', 'timestamp', 'story', 'url'));
      }
    }, 6);
    if (found) return found;
  }
  return null;
}

/** Extract Comment nodes with depth from a detail/pagination response. */
export function extractComments(text) {
  const lines = parseLines(text);
  const comments = [];

  for (const obj of lines) {
    walkTree(obj, node => {
      if (node?.__typename !== 'Comment') return;
      const body = dig(node, 'body', 'text') || dig(node, 'preferred_body', 'text') || '';
      if (body.length < 3) return;
      const author = dig(node, 'author', 'name') || 'unknown';
      const key = commentKey(author, body);
      if (comments.some(c => c._key === key)) return;
      comments.push({
        author, body,
        depth: typeof node.depth === 'number' ? node.depth : 0,
        timestamp: node.created_time || null,
        _key: key,
      });
    }, 20);
  }
  return comments;
}

/** Merge new comments into a post, deduplicating by key. Returns count added. */
export function mergeComments(post, newComments) {
  if (!post.comments) post.comments = [];
  const existing = new Set(post.comments.map(c => c._key));
  let added = 0;
  for (const c of newComments) {
    if (!existing.has(c._key)) {
      post.comments.push(c);
      existing.add(c._key);
      added++;
    }
  }
  return added;
}
