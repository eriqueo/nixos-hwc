// A markdown-file ItemStore (slice 03's port). Persists each Item as one .md
// file under a directory, with board-readable YAML frontmatter (title, state,
// step/stage, pipeline) PLUS a fenced ```json block carrying the canonical Item
// for lossless round-trip. load() reads the json block and validates it with
// ItemSchema, so save→load is exact regardless of the human-facing rendering.
//
// Board-compat note: the frontmatter exposes the item's `state`, `step`/`stage`
// and `title` so a board could display these items. They live in their own
// store dir (a scratch/run dir).

import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { Item, ItemSchema, ItemStore } from "../contracts.js";

const HOPPER_STAGE_KEYS = ["captured", "shaping", "ready"];

// Read-old/write-new migration. Pre-rename `.md` files carry the legacy field
// names (genre/phase/phaseStatus/nightly) in their canonical JSON block; this
// normalizes them to the current shape before ItemSchema.parse so existing
// state survives the rename. save() always writes the new shape, so any item
// touched by a board action upgrades in place; untouched items upgrade lazily
// on each read. Idempotent — a new-shape object passes through unchanged.
function migrateItemJson(raw: unknown): unknown {
  if (!raw || typeof raw !== "object") return raw;
  const o = { ...(raw as Record<string, unknown>) };
  if (o.pipeline === undefined && o.genre !== undefined) o.pipeline = o.genre;
  delete o.genre;
  if (o.state === undefined && o.phaseStatus !== undefined) o.state = o.phaseStatus;
  delete o.phaseStatus;
  if (o.step === undefined && o.stage === undefined && o.phase !== undefined) {
    const isIdea = o.pipeline === "untriaged";
    if (isIdea) o.stage = HOPPER_STAGE_KEYS.includes(o.phase as string) ? o.phase : "captured";
    else o.step = o.phase;
  }
  delete o.phase;
  if (o.schedule === undefined && o.nightly !== undefined) o.schedule = o.nightly === true ? "nightly" : "now";
  delete o.nightly;
  if (o.schedulePriority === undefined && o.nightlyPriority !== undefined) o.schedulePriority = o.nightlyPriority;
  delete o.nightlyPriority;
  if (Array.isArray(o.history)) {
    o.history = (o.history as unknown[]).map((h) => {
      if (h && typeof h === "object") {
        const e = { ...(h as Record<string, unknown>) };
        if (e.step === undefined && e.phase !== undefined) e.step = e.phase;
        delete e.phase;
        return e;
      }
      return h;
    });
  }
  return o;
}

function frontmatter(item: Item): string {
  const title =
    item.payload && typeof item.payload === "object" && "title" in item.payload
      ? String((item.payload as { title: unknown }).title)
      : item.id;
  const lines = [
    "---",
    `title: ${JSON.stringify(title)}`,
    `id: ${item.id}`,
    `pipeline: ${item.pipeline}`,
  ];
  if (item.step) lines.push(`step: ${item.step}`);
  if (item.stage) lines.push(`stage: ${item.stage}`);
  lines.push(`state: ${item.state}`);
  if (item.parkedReason) lines.push(`parkedReason: ${JSON.stringify(item.parkedReason)}`);
  lines.push("---");
  return lines.join("\n");
}

function render(item: Item): string {
  const pos = item.step ?? item.stage ?? "—";
  return [
    frontmatter(item),
    "",
    `# ${item.id} — ${item.pipeline} @ ${pos} (${item.state})`,
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
  return ItemSchema.parse(migrateItemJson(JSON.parse(m[1])));
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
