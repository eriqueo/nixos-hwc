#!/usr/bin/env node

import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';
import {
  parseFeedResponse, extractComments, mergeComments,
  findPostIdInResponse, getOpName,
} from './parse.mjs';

// ── Config ──

const DEFAULTS = {
  posts: 50,
  depth: 'posts',
  profile: './data/browser-profile',
};

const SCROLL = {
  minPx: 800, maxPx: 1200,
  minWait: 1500, maxWait: 3000,
  staleLimit: 10,
  stalePause: [3000, 5000],
};

// ── CLI ──

function parseArgs() {
  const args = process.argv.slice(2);
  const opts = { ...DEFAULTS, headed: false, quiet: false, login: false, output: null };
  const positional = [];

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    const next = () => args[++i];
    switch (a) {
      case '-h': case '--help':    usage(); process.exit(0);
      case '--login':              opts.login = true; break;
      case '--headed':             opts.headed = true; break;
      case '-q': case '--quiet':   opts.quiet = true; break;
      case '-n': case '--posts':   opts.posts = parseInt(next(), 10); break;
      case '-d': case '--depth':   opts.depth = next(); break;
      case '-o': case '--output':  opts.output = next(); break;
      case '--profile':            opts.profile = next(); break;
      default: a.startsWith('-') ? die(`Unknown flag: ${a}`) : positional.push(a);
    }
  }

  opts.url = positional[0];
  if (!opts.url && !opts.login) { usage(); die('Group URL required.'); }
  if (!['posts', 'comments'].includes(opts.depth)) die(`--depth must be 'posts' or 'comments'`);
  if (opts.url) opts.url = normalizeUrl(opts.url);
  return opts;
}

function usage() {
  console.error(`
fb-group-scraper — collect FB group posts and output JSON

Usage:
  node index.mjs <group-url> [options]
  node index.mjs --login --headed

Options:
  -n, --posts <n>        Posts to collect (default: 50)
  -d, --depth <mode>     'posts' or 'comments' (default: posts)
  -o, --output <path>    Write JSON to file (default: stdout)
      --profile <path>   Browser profile directory (default: ./data/browser-profile)
      --headed           Show the browser window
      --login            Interactive login — saves profile then exits
  -q, --quiet            Suppress progress output (stderr)
  -h, --help             This message

Examples:
  node index.mjs --login --headed
  node index.mjs https://facebook.com/groups/jobtread -n 100
  node index.mjs jobtread -n 50 -d comments -o /tmp/export.json
  node index.mjs jobtread -n 25 | fb-merge /dev/stdin
  `.trim());
}

function normalizeUrl(input) {
  if (input.includes('facebook.com')) return input.startsWith('http') ? input : `https://${input}`;
  return `https://www.facebook.com/groups/${input}`;
}

function die(msg) { console.error(`Error: ${msg}`); process.exit(1); }

// ── Helpers ──

const sleep = (min, max) => new Promise(r => setTimeout(r, min + Math.random() * (max - min)));

function log(opts, ...args) { if (!opts.quiet) console.error(...args); }

// ── Browser ──

async function launch(opts) {
  const context = await chromium.launchPersistentContext(opts.profile, {
    headless: !opts.headed && !opts.login,
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH || undefined,
    args: ['--disable-blink-features=AutomationControlled', '--no-sandbox'],
    viewport: { width: 1280, height: 900 },
    locale: 'en-US',
  });
  const page = context.pages()[0] || await context.newPage();
  return { context, page };
}

async function checkAuth(context) {
  const cookies = await context.cookies('https://www.facebook.com');
  return cookies.some(c => c.name === 'c_user');
}

async function doLogin(page, context, opts) {
  const cookies = await context.cookies('https://www.facebook.com');
  if (cookies.some(c => c.name === 'c_user')) {
    console.error('Already logged in.');
  } else {
    await page.goto('https://www.facebook.com', { waitUntil: 'domcontentloaded' });
    console.error('Log in (including passkey) in the browser window.');
    console.error('Session will auto-save when login completes.');
    while (true) {
      const current = await context.cookies('https://www.facebook.com');
      if (current.some(c => c.name === 'c_user')) break;
      await new Promise(r => setTimeout(r, 2000));
    }
    console.error('Login detected.');
    await new Promise(r => setTimeout(r, 3000));
  }
  console.error(`Profile saved → ${opts.profile}`);
}

// ── Feed Scraping ──

async function scrapeGroup(page, opts) {
  const posts = new Map();
  let stale = 0;

  page.on('response', async (res) => {
    if (!res.url().includes('/api/graphql')) return;
    try {
      const req = res.request();
      const reqBody = req.postData() || '';
      const op = getOpName(reqBody);
      if (!op.includes('GroupsCometFeed') && !op.includes('GroupFeed')) return;

      const parsed = parseFeedResponse(await res.text());
      for (const post of parsed) {
        if (posts.has(post.postId)) {
          const existing = posts.get(post.postId);
          if (post.reactions != null) existing.reactions = post.reactions;
          if (post.commentCount != null) existing.commentCount = post.commentCount;
          if (post.comments.length > existing.comments.length) existing.comments = post.comments;
        } else if (posts.size < opts.posts) {
          posts.set(post.postId, post);
          log(opts, `  [${posts.size}/${opts.posts}] ${post.author}: ${(post.body || '').slice(0, 60).replace(/\n/g, ' ')}`);
        }
      }
    } catch { /* non-feed responses ignored */ }
  });

  log(opts, `→ ${opts.url}`);
  await page.goto(opts.url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
  await sleep(3000, 5000);

  log(opts, `Scrolling for ${opts.posts} posts...`);
  while (posts.size < opts.posts && stale < SCROLL.staleLimit) {
    const before = posts.size;
    await page.mouse.wheel(0, SCROLL.minPx + Math.random() * (SCROLL.maxPx - SCROLL.minPx));
    await sleep(SCROLL.minWait, SCROLL.maxWait);
    if (posts.size === before) {
      stale++;
      if (stale >= 5) await sleep(...SCROLL.stalePause);
    } else {
      stale = 0;
    }
  }

  if (stale >= SCROLL.staleLimit) log(opts, `Stopped: no new posts after ${SCROLL.staleLimit} consecutive scrolls.`);
  return posts;
}

// ── Comment Expansion ──

async function expandAllComments(page, posts, opts) {
  log(opts, `\nExpanding comments on ${posts.size} posts...`);
  let expanded = 0;
  let totalComments = 0;
  let lastExpandedPostId = null;

  for (const [postId, post] of posts) {
    if (!post.url) { log(opts, `  [skip] no URL — ${post.author}`); continue; }

    const batch = [];
    const handler = async (res) => {
      if (!res.url().includes('/api/graphql')) return;
      try {
        const op = getOpName(res.request().postData() || '');
        const text = await res.text();
        if (op === 'CometSinglePostDialogContentQuery') {
          const responsePostId = findPostIdInResponse(text);
          if (responsePostId === postId) {
            batch.push(...extractComments(text));
            lastExpandedPostId = postId;
          }
        } else if (op.includes('CommentsListPaginationQuery') && lastExpandedPostId === postId) {
          batch.push(...extractComments(text));
        }
      } catch {}
    };
    page.on('response', handler);

    try {
      const clicked = await openPostDialog(page, postId, (msg) => log(opts, msg));
      if (!clicked) {
        log(opts, `  [skip] could not find post in DOM — ${post.author}`);
        continue;
      }

      // Wait for handler to signal dialog loaded (CometSinglePostDialogContentQuery fired)
      // FB headless doesn't add role="dialog" — use handler signal instead
      const dialogReady = await pollUntil(() => lastExpandedPostId === postId, 10000, 200);
      if (!dialogReady) {
        log(opts, `  [skip] dialog query did not fire — ${post.author}`);
        await tryCloseDialog(page);
        continue;
      }

      await sleep(2500, 4000);
      // Scroll/expand only when dialog overlay is actually present (headed mode).
      // In headless FB doesn't render the overlay, so these would operate on the whole feed.
      const hasDialog = await page.evaluate(() =>
        !!(document.querySelector('[role="dialog"]') || document.querySelector('[aria-modal="true"]'))
      );
      if (hasDialog) {
        await scrollDialogComments(page);
        await expandReplyThreads(page);
        await tryCloseDialog(page);
      }
      await sleep(1000, 2000);

      if (batch.length) {
        const added = mergeComments(post, batch);
        post._commentsExpanded = true;
        totalComments += added;
        expanded++;
        log(opts, `  [${expanded}] ${post.author}: ${post.comments.length} comments (+${added} new)`);
      } else {
        log(opts, `  [--] ${post.author}: no comments captured`);
      }
    } catch (e) {
      log(opts, `  [error] ${post.author}: ${e.message}`);
      await tryCloseDialog(page).catch(() => {});
    } finally {
      page.removeListener('response', handler);
    }

    await sleep(2000, 4500);
  }

  log(opts, `Expanded ${expanded}/${posts.size} posts, ${totalComments} comments captured.`);
}

function pollUntil(predicate, timeoutMs = 10000, intervalMs = 200) {
  return new Promise(resolve => {
    if (predicate()) { resolve(true); return; }
    const start = Date.now();
    const id = setInterval(() => {
      if (predicate()) { clearInterval(id); resolve(true); }
      else if (Date.now() - start >= timeoutMs) { clearInterval(id); resolve(false); }
    }, intervalMs);
  });
}

async function openPostDialog(page, postId, logFn) {
  // CometSinglePostDialogContentQuery fires as a prefetch ~250ms before navigation.
  // Click, wait briefly, go back if navigated. No page.route() — too slow.
  let clicked = await clickPostLink(page, postId);

  if (!clicked) {
    logFn(`  post ${postId} not in DOM, scanning feed...`);
    await page.evaluate(() => window.scrollTo(0, 0));
    await sleep(800, 1500);
    for (let i = 0; i < 30; i++) {
      clicked = await clickPostLink(page, postId);
      if (clicked) break;
      await page.mouse.wheel(0, 400);
      await sleep(400, 800);
    }
  }

  if (!clicked) return false;

  await sleep(600, 1000);
  if (page.url().includes('/posts/')) {
    await page.goBack({ waitUntil: 'domcontentloaded' });
    await sleep(1500, 2500);
  }
  return true;
}

async function clickPostLink(page, postId) {
  return page.evaluate(async (postId) => {
    const all = [...document.querySelectorAll(`a[href*="/posts/${postId}"]`)];
    if (!all.length) return false;
    const clean = all.filter(a => !a.href.includes('?'));
    const target = clean[0] || all[0];
    target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    await new Promise(r => setTimeout(r, 300));
    target.click();
    return true;
  }, postId);
}

async function scrollDialogComments(page) {
  // FB headless: no role="dialog". Find scrollable overlay by overflow style; fall back to page wheel.
  let noNew = 0;
  for (let i = 0; i < 25; i++) {
    const scrolled = await page.evaluate(() => {
      const px = 600 + Math.random() * 400;
      const candidates = [...document.querySelectorAll('*')].filter(el => {
        if (!el.offsetParent && el !== document.body) return false;
        const s = window.getComputedStyle(el);
        return (s.overflowY === 'auto' || s.overflowY === 'scroll') &&
               el.scrollHeight > el.clientHeight + 50 &&
               el.clientHeight > 200;
      });
      const target = candidates.filter(el => el !== document.body).sort((a, b) => b.clientHeight - a.clientHeight)[0];
      if (target) {
        target.scrollBy({ top: px, behavior: 'smooth' });
        return target.scrollTop + target.clientHeight < target.scrollHeight - 10;
      }
      return null;
    });
    if (scrolled === null) await page.mouse.wheel(0, 600 + Math.random() * 400);
    await sleep(1000, 2000);
    if (scrolled === false) { noNew++; if (noNew >= 4) break; } else noNew = 0;
  }
}

async function tryCloseDialog(page) {
  await page.keyboard.press('Escape');
  await sleep(500, 800);
  const stillOpen = await page.evaluate(() => {
    return !!(document.querySelector('[role="dialog"]') || document.querySelector('[aria-modal="true"]'));
  });
  if (stillOpen) {
    await page.evaluate(() => {
      const close = document.querySelector('[aria-label="Close"], [aria-label="close"]') ||
                    document.querySelector('[aria-modal="true"] [role="button"][tabindex="0"]');
      close?.click();
    });
    await sleep(500, 800);
  }
}

async function expandReplyThreads(page) {
  const replyPatterns = [
    /^\d+\s+Repl(?:y|ies)$/i,
    /^View\s+\d+\s+repl(?:y|ies)$/i,
    /^View\s+more\s+repl(?:y|ies)$/i,
    /replied\s+·\s+\d+\s+Repl(?:y|ies)$/i,
  ];

  for (let round = 0; round < 5; round++) {
    const buttons = await page.evaluateHandle((patterns) => {
      const found = [];
      for (const el of document.querySelectorAll('span, div')) {
        const text = el.textContent.trim();
        if (!text) continue;
        const isReply = patterns.some(p => new RegExp(p, 'i').test(text));
        if (!isReply) continue;
        if (!el.offsetParent) continue;
        if (el.dataset._fbscraperClicked) continue;
        const target = el.closest('[role="button"]') || el;
        target.dataset._fbscraperClicked = '1';
        found.push(target);
      }
      return found;
    }, replyPatterns.map(r => r.source));

    const count = await buttons.evaluate(els => els.length);
    if (count === 0) { await buttons.dispose(); break; }

    for (let i = 0; i < count; i++) {
      try {
        await buttons.evaluate((els, idx) => els[idx].scrollIntoView({ behavior: 'smooth', block: 'center' }), i);
        await sleep(400, 800);
        await buttons.evaluate((els, idx) => els[idx].click(), i);
        await sleep(1500, 3000);
      } catch { /* button may have been removed by FB re-render */ }
    }

    await buttons.dispose();
    await page.mouse.wheel(0, 300);
    await sleep(1000, 2000);
  }
}

// ── JSON Export ──

function formatExport(posts, opts) {
  const postArr = [...posts.values()];
  return {
    _meta: {
      tool: 'fb-group-scraper',
      version: '2.0.0',
      capturedAt: new Date().toISOString(),
      source: opts.url,
      postCount: postArr.length,
      totalComments: postArr.reduce((n, p) => n + (p.comments?.length || 0), 0),
      expandedPosts: postArr.filter(p => p._commentsExpanded).length,
    },
    posts: postArr.map(p => ({
      postId: p.postId,
      body: p.body,
      author: p.author,
      source: p.source,
      url: p.url,
      timestamp: p.timestamp ? new Date(p.timestamp * 1000).toISOString() : null,
      commentCount: p.commentCount,
      commentsExpanded: !!p._commentsExpanded,
      comments: (p.comments || []).map(c => ({
        author: c.author,
        body: c.body,
        depth: c.depth ?? 0,
        timestamp: c.timestamp ? new Date(c.timestamp * 1000).toISOString() : null,
      })),
    })),
  };
}

// ── Main ──

async function main() {
  const opts = parseArgs();
  const { context, page } = await launch(opts);

  try {
    if (opts.login) {
      await doLogin(page, context, opts);
      return;
    }

    if (!(await checkAuth(context))) die('Not logged in. Run with --login --headed first.');

    const posts = await scrapeGroup(page, opts);

    if (opts.depth === 'comments') {
      await expandAllComments(page, posts, opts);
    }

    const data = formatExport(posts, opts);
    const json = JSON.stringify(data, null, 2);

    if (opts.output) {
      mkdirSync(dirname(opts.output), { recursive: true });
      writeFileSync(opts.output, json);
      console.error(`✓ ${posts.size} posts written to ${opts.output}`);
    } else {
      process.stdout.write(json + '\n');
      console.error(`✓ ${posts.size} posts output to stdout`);
    }

  } finally {
    await context.close();
  }
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
