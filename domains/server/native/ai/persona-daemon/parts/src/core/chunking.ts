// Markdown chunker for vault RAG.
//
// Heuristic (per plan):
//   - Split notes by ## H2 boundaries, 1024-token soft cap, 128-token overlap.
//   - Token count approximated as char_count / 4 (no tokenizer dep).
//   - Frontmatter (--- ... ---) is its own chunk, tagged kind="frontmatter".
//   - Code fences (``` ... ```) are atomic — never split mid-fence even if
//     the resulting chunk exceeds the cap.
//   - MOC notes (frontmatter tags include "moc") chunk by H1 instead of H2.

export interface ChunkInput {
  notePath: string;
  body: string;
  mtime: number;
}

export interface Chunk {
  notePath: string;
  sectionTitle: string;
  parentSection: string;
  kind: "text" | "code" | "frontmatter" | "moc";
  charStart: number;
  charEnd: number;
  body: string;
  mtime: number;
}

// Embedding model (nomic-embed-text) is trained at 2048 tokens. The
// chars-per-token estimate is wobbly for code/structured content (can be
// 2x off), so we target ~400 tokens = ~1600 chars per chunk to keep even
// worst-case under the model's training context with headroom.
const CHARS_PER_TOKEN = 4;
const SOFT_CAP_TOKENS = 400;
const OVERLAP_TOKENS = 64;
const SOFT_CAP_CHARS = SOFT_CAP_TOKENS * CHARS_PER_TOKEN;
const OVERLAP_CHARS = OVERLAP_TOKENS * CHARS_PER_TOKEN;

interface ParsedNote {
  frontmatter: string | null;       // raw YAML body, without --- fences
  bodyStart: number;                // index in original where body begins
  body: string;                     // markdown after frontmatter
  isMoc: boolean;
}

const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?/;

function parseFrontmatter(text: string): ParsedNote {
  const m = text.match(FRONTMATTER_RE);
  if (!m) {
    return { frontmatter: null, bodyStart: 0, body: text, isMoc: false };
  }
  const fm = m[1];
  const bodyStart = m[0].length;
  // Crude MOC detection: tags list contains 'moc' or any line is `tags: ... moc ...`.
  const isMoc = /(^|\n)\s*tags\s*:[^\n]*\bmoc\b/i.test(fm);
  return { frontmatter: fm, bodyStart, body: text.slice(bodyStart), isMoc };
}

/**
 * Split into atomic spans (text, code-fence) preserving original char offsets
 * into the *body* (not the original file — caller adds bodyStart).
 */
interface Span {
  kind: "text" | "code";
  charStart: number;
  charEnd: number;
  text: string;
}

const FENCE_RE = /^(?:```|~~~)[^\n]*\n[\s\S]*?(?:^|\n)(?:```|~~~)\s*(?:\n|$)/gm;

function splitSpans(body: string): Span[] {
  const spans: Span[] = [];
  let cursor = 0;
  for (const m of body.matchAll(FENCE_RE)) {
    const start = m.index ?? 0;
    if (start > cursor) {
      spans.push({
        kind: "text",
        charStart: cursor,
        charEnd: start,
        text: body.slice(cursor, start),
      });
    }
    spans.push({
      kind: "code",
      charStart: start,
      charEnd: start + m[0].length,
      text: m[0],
    });
    cursor = start + m[0].length;
  }
  if (cursor < body.length) {
    spans.push({
      kind: "text",
      charStart: cursor,
      charEnd: body.length,
      text: body.slice(cursor),
    });
  }
  return spans;
}

interface Section {
  title: string;
  parent: string;
  charStart: number;
  body: string;
}

/** Split text-mode body by H1 (for MOCs) or H2 (everything else). */
function splitSections(body: string, splitByH1: boolean): Section[] {
  const headerRe = splitByH1
    ? /^# (?!#)([^\n]+)/gm
    : /^## (?!#)([^\n]+)/gm;

  const matches: { idx: number; title: string }[] = [];
  for (const m of body.matchAll(headerRe)) {
    matches.push({ idx: m.index ?? 0, title: m[1].trim() });
  }
  if (matches.length === 0) {
    return [{ title: "(root)", parent: "(root)", charStart: 0, body }];
  }
  const out: Section[] = [];
  // Pre-section preamble (anything before the first header)
  if (matches[0].idx > 0) {
    out.push({
      title: "(preamble)",
      parent: "(root)",
      charStart: 0,
      body: body.slice(0, matches[0].idx),
    });
  }
  // Find parent H1 for each H2 section if !splitByH1
  let lastH1 = "(root)";
  for (let i = 0; i < matches.length; i++) {
    const m = matches[i];
    const end = i + 1 < matches.length ? matches[i + 1].idx : body.length;
    if (splitByH1) {
      lastH1 = m.title;
    } else {
      // Look backward in body for the nearest # header before this match.
      const before = body.slice(0, m.idx);
      const h1m = [...before.matchAll(/^# (?!#)([^\n]+)/gm)].pop();
      lastH1 = h1m ? h1m[1].trim() : "(root)";
    }
    out.push({
      title: m.title,
      parent: splitByH1 ? "(root)" : lastH1,
      charStart: m.idx,
      body: body.slice(m.idx, end),
    });
  }
  return out;
}

/** Apply soft cap + overlap to a section. Code fences are atomic. */
function packSection(args: {
  section: Section;
  notePath: string;
  bodyStart: number;
  mtime: number;
}): Chunk[] {
  const { section, notePath, bodyStart, mtime } = args;
  const spans = splitSpans(section.body);

  const chunks: Chunk[] = [];
  let buffer = "";
  let bufferStart = 0;
  let bufferKind: "text" | "code" = "text";

  const flush = () => {
    if (buffer.length === 0) return;
    chunks.push({
      notePath,
      sectionTitle: section.title,
      parentSection: section.parent,
      kind: bufferKind,
      charStart: bodyStart + section.charStart + bufferStart,
      charEnd: bodyStart + section.charStart + bufferStart + buffer.length,
      body: buffer,
      mtime,
    });
    buffer = "";
  };

  for (const span of spans) {
    if (span.kind === "code") {
      // Atomic: emit current buffer, then emit code as its own chunk.
      flush();
      chunks.push({
        notePath,
        sectionTitle: section.title,
        parentSection: section.parent,
        kind: "code",
        charStart: bodyStart + section.charStart + span.charStart,
        charEnd: bodyStart + section.charStart + span.charEnd,
        body: span.text,
        mtime,
      });
      bufferStart = span.charEnd;
      continue;
    }
    // Text span — pack with soft cap + overlap.
    let cursor = 0;
    while (cursor < span.text.length) {
      const remaining = SOFT_CAP_CHARS - buffer.length;
      if (remaining <= 0) {
        flush();
        // Carry forward an overlap from the just-flushed buffer.
        // (Approximation: take last OVERLAP_CHARS of the just-flushed text.)
        // Implementation: prepend the overlap to the new buffer via charStart adjustment.
        const overlap = chunks[chunks.length - 1].body.slice(-OVERLAP_CHARS);
        buffer = overlap;
        bufferStart = (chunks[chunks.length - 1].charEnd - bodyStart - section.charStart) - overlap.length;
        bufferKind = "text";
        continue;
      }
      const slice = span.text.slice(cursor, cursor + remaining);
      if (buffer.length === 0) {
        bufferStart = span.charStart + cursor;
        bufferKind = "text";
      }
      buffer += slice;
      cursor += slice.length;
    }
  }
  flush();
  return chunks;
}

export function chunkNote(input: ChunkInput): Chunk[] {
  const parsed = parseFrontmatter(input.body);

  const out: Chunk[] = [];

  if (parsed.frontmatter !== null) {
    out.push({
      notePath: input.notePath,
      sectionTitle: "(frontmatter)",
      parentSection: "(frontmatter)",
      kind: "frontmatter",
      charStart: 0,
      charEnd: parsed.bodyStart,
      body: parsed.frontmatter,
      mtime: input.mtime,
    });
  }

  if (parsed.isMoc) {
    // For MOCs, override section kind to "moc" so retrieval can score
    // them differently if it wants.
    const sections = splitSections(parsed.body, /*splitByH1*/ true);
    for (const s of sections) {
      const chunks = packSection({
        section: s,
        notePath: input.notePath,
        bodyStart: parsed.bodyStart,
        mtime: input.mtime,
      });
      for (const c of chunks) c.kind = "moc";
      out.push(...chunks);
    }
  } else {
    const sections = splitSections(parsed.body, /*splitByH1*/ false);
    for (const s of sections) {
      out.push(...packSection({
        section: s,
        notePath: input.notePath,
        bodyStart: parsed.bodyStart,
        mtime: input.mtime,
      }));
    }
  }

  // Drop empty/whitespace-only chunks (defensive).
  return out.filter((c) => c.body.trim().length > 0);
}
