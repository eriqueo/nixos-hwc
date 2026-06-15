// A markdown-file ItemStore (slice 03's port). Persists each Item as one .md
// file under a directory, with board-readable YAML frontmatter (title, status,
// phase, genre) PLUS a fenced ```json block carrying the canonical Item for
// lossless round-trip. load() reads the json block and validates it with
// ItemSchema, so save→load is exact regardless of the human-facing rendering.
//
// Board-compat note: the frontmatter exposes a `status` field (the item's
// phaseStatus) and `phase`/`title` so a board could display these items. They
// live in their own store dir (a scratch/run dir), NOT the gauntlet hopper the
// slice-01 board currently scans — full board integration is slice 07.

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { Item, ItemSchema, ItemStore } from "../contracts.js";

function frontmatter(item: Item): string {
  const title =
    item.payload && typeof item.payload === "object" && "title" in item.payload
      ? String((item.payload as { title: unknown }).title)
      : item.id;
  const lines = [
    "---",
    `title: ${JSON.stringify(title)}`,
    `id: ${item.id}`,
    `genre: ${item.genre}`,
    `phase: ${item.phase}`,
    `status: ${item.phaseStatus}`,
  ];
  if (item.parkedReason) lines.push(`parkedReason: ${JSON.stringify(item.parkedReason)}`);
  lines.push("---");
  return lines.join("\n");
}

function render(item: Item): string {
  return [
    frontmatter(item),
    "",
    `# ${item.id} — ${item.genre} @ ${item.phase} (${item.phaseStatus})`,
    "",
    "<!-- canonical item (do not hand-edit) -->",
    "```json",
    JSON.stringify(item, null, 2),
    "```",
    "",
  ].join("\n");
}

const JSON_BLOCK = /```json\n([\s\S]*?)\n```/;

function parseItemFile(text: string, file: string): Item {
  const m = JSON_BLOCK.exec(text);
  if (!m) throw new Error(`markdown-store: no canonical json block in ${file}`);
  return ItemSchema.parse(JSON.parse(m[1]));
}

export class MarkdownItemStore implements ItemStore {
  constructor(private readonly dir: string) {
    mkdirSync(dir, { recursive: true });
  }

  private pathFor(id: string): string {
    return join(this.dir, `${id}.md`);
  }

  async load(id: string): Promise<Item | null> {
    const path = this.pathFor(id);
    if (!existsSync(path)) return null;
    return parseItemFile(readFileSync(path, "utf8"), path);
  }

  async save(item: Item): Promise<void> {
    writeFileSync(this.pathFor(item.id), render(item));
  }

  async delete(id: string): Promise<void> {
    const path = this.pathFor(id);
    if (existsSync(path)) rmSync(path);
  }

  async list(): Promise<Item[]> {
    if (!existsSync(this.dir)) return [];
    const items: Item[] = [];
    for (const f of readdirSync(this.dir)) {
      if (!f.endsWith(".md")) continue;
      items.push(parseItemFile(readFileSync(join(this.dir, f), "utf8"), f));
    }
    return items;
  }
}
