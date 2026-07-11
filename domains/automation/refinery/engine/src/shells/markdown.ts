// Minimal, dependency-free Markdown → HTML for rendering REPORTs and card bodies
// on the board. Escapes first (everything is HTML-escaped before any transform,
// so there's no injection surface), then applies block + inline rules. Not a
// full CommonMark implementation — just the constructs the gauntlets actually
// emit: headings, fenced/inline code, bold/italic, links, ordered/unordered
// lists, blockquotes, hr, paragraphs. Output is meant to live in a `.md` block
// whose CSS wraps long lines.

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

// Obsidian deep-link for a vault path or note name. Obsidian resolves `file=`
// by path or bare note name within the vault, so both OKF paths and legacy
// wikilink targets map cleanly. Heading anchors are dropped (the plain
// obsidian:// URI has no heading support). Vault name is late-bound.
const OBSIDIAN_VAULT = process.env.REFINERY_OBSIDIAN_VAULT ?? "brain";
function obsidianHref(target: string): string {
  const file = target.replace(/^\//, "").replace(/#[^#]*$/, "").replace(/\.md$/, "");
  return `obsidian://open?vault=${encodeURIComponent(OBSIDIAN_VAULT)}&amp;file=${encodeURIComponent(file)}`;
}

function inline(s: string): string {
  return s
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>")
    // Legacy wikilinks: [[target]] / [[target|label]] — deprecated by the OKF
    // link standard but still present in older goal/card bodies.
    .replace(
      /\[\[([^\]|]+)(?:\|([^\]]+))?\]\]/g,
      (_m, target: string, label?: string) =>
        `<a class="vlink" href="${obsidianHref(target)}" title="${target}">${label ?? target}</a>`,
    )
    // External links: [text](http...) — href already escaped; only allow http(s).
    .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2">$1</a>')
    // OKF vault cross-links: [text](relative/path.md[#anchor]) — standard
    // markdown links into the vault. The board is home-masked and can't read
    // arbitrary vault paths, so link out to Obsidian instead: an
    // obsidian://open deep link opens the note on any machine with the vault
    // (full path stays on hover).
    .replace(
      /\[([^\]]+)\]\(([^)\s]+\.md(?:#[^)\s]*)?)\)/g,
      (_m, text: string, path: string) =>
        `<a class="vlink" href="${obsidianHref(path)}" title="${path}">${text}</a>`,
    );
}

export function mdToHtml(md: string): string {
  const lines = esc(md).split("\n");
  const out: string[] = [];
  let inCode = false;
  let listType: "ul" | "ol" | null = null;
  let para: string[] = [];

  const flushPara = () => {
    if (para.length) {
      out.push(`<p>${inline(para.join(" "))}</p>`);
      para = [];
    }
  };
  const closeList = () => {
    if (listType) {
      out.push(`</${listType}>`);
      listType = null;
    }
  };

  for (const raw of lines) {
    const line = raw;
    // fenced code
    const fence = /^\s*```/.test(line);
    if (fence) {
      flushPara();
      closeList();
      if (inCode) {
        out.push("</code></pre>");
        inCode = false;
      } else {
        out.push('<pre class="code"><code>');
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      out.push(line);
      continue;
    }
    if (/^\s*$/.test(line)) {
      flushPara();
      closeList();
      continue;
    }
    const heading = /^(#{1,6})\s+(.*)$/.exec(line);
    if (heading) {
      flushPara();
      closeList();
      const level = Math.min(heading[1].length + 1, 6); // shift down one (page already has h1/h2)
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      continue;
    }
    if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
      flushPara();
      closeList();
      out.push("<hr>");
      continue;
    }
    const ul = /^\s*[-*]\s+(.*)$/.exec(line);
    const ol = /^\s*\d+\.\s+(.*)$/.exec(line);
    if (ul || ol) {
      flushPara();
      const want = ul ? "ul" : "ol";
      if (listType !== want) {
        closeList();
        out.push(`<${want}>`);
        listType = want;
      }
      out.push(`<li>${inline((ul ?? ol)![1])}</li>`);
      continue;
    }
    const quote = /^\s*&gt;\s?(.*)$/.exec(line); // ">" was escaped
    if (quote) {
      flushPara();
      closeList();
      out.push(`<blockquote>${inline(quote[1])}</blockquote>`);
      continue;
    }
    para.push(line.trim());
  }
  if (inCode) out.push("</code></pre>");
  flushPara();
  closeList();
  return out.join("\n");
}
