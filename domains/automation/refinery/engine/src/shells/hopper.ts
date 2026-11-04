// Minimal read-only reader for the gauntlet hopper, folded into the engine
// shell as the /hopper route (preserving the slice-01/02 board view alongside
// the new interactive engine board). Read-only: it only ever reads the vault's
// _inbox/nightly_builds/*/NN-*.md cards.

import { readFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { join } from "node:path";

// Fixed patterns are shared; stateful uses reset their cursor below.
const frontmatterExecRegex = /^---\n([\s\S]*?)\n---/;
const frontmatterExecRegex2 = /^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/;
const frontmatterPatternRegex = /^["']|["']$/g;
const readHopperCardsTestRegex = /^\d\d-/;
const readHopperCardsPatternRegex = /\.md$/;
const escPatternRegex = /[&<>"']/g;

export interface HopperCard {
  goalId: string;
  file: string;
  title: string;
  status: string;
}

function frontmatter(text: string): Record<string, string> {
  const out: Record<string, string> = {};
  const m = frontmatterExecRegex.exec(text);
  if (!m) return out;
  for (const line of m[1].split("\n")) {
    const mm = frontmatterExecRegex2.exec(line);
    if (mm) out[mm[1]] = mm[2].replace((frontmatterPatternRegex.lastIndex = 0, frontmatterPatternRegex), "").trim();
  }
  return out;
}

export function readHopperCards(vaultDir: string): HopperCard[] {
  const base = join(vaultDir, "_inbox", "nightly_builds");
  const out: HopperCard[] = [];
  if (!existsSync(base)) return out;
  for (const goalId of readdirSync(base)) {
    const dir = join(base, goalId);
    if (!statSync(dir).isDirectory()) continue;
    for (const f of readdirSync(dir)) {
      if (!readHopperCardsTestRegex.test(f) || !f.endsWith(".md")) continue;
      const fm = frontmatter(readFileSync(join(dir, f), "utf8"));
      out.push({ goalId, file: f, title: fm.title || f.replace(readHopperCardsPatternRegex, ""), status: fm.status || "draft" });
    }
  }
  out.sort((a, b) => (a.goalId + a.file).localeCompare(b.goalId + b.file));
  return out;
}

function esc(s: string): string {
  return s.replace((escPatternRegex.lastIndex = 0, escPatternRegex), (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c] as string),
  );
}

export function renderHopper(cards: HopperCard[]): string {
  const rows = cards
    .map(
      (c) => `<tr><td>${esc(c.goalId)}</td><td>${esc(c.file)}</td><td>${esc(c.title)}</td><td class="st">${esc(c.status)}</td></tr>`,
    )
    .join("");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Refinery — gauntlet hopper</title>
<style>body{margin:0;background:#1d2021;color:#ebdbb2;font:14px/1.4 ui-sans-serif,system-ui,sans-serif}
header{padding:14px 18px;border-bottom:1px solid #3c3836}header a{color:#83a598}
table{width:100%;border-collapse:collapse}td,th{padding:6px 12px;border-bottom:1px solid #3c3836;text-align:left}
.st{color:#fabd2f}</style></head><body>
<header><a href="/">← engine board</a> &nbsp; <b>🛠 gauntlet hopper</b> · ${cards.length} cards</header>
<table><tr><th>goal</th><th>card</th><th>title</th><th>status</th></tr>${rows}</table>
</body></html>`;
}
