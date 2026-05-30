import type { NoteSource } from "../ports/notes.ts";

const SKIP_DIRS = new Set([
  ".obsidian", ".trash", ".stversions", ".stfolder", ".git",
]);

interface Config {
  rootPath: string;
  /** File suffixes to index. */
  suffixes?: string[];
}

export function createNotesFs(cfg: Config): NoteSource {
  const root = cfg.rootPath.replace(/\/+$/, "");
  const suffixes = cfg.suffixes ?? [".md"];

  async function* walk(dir: string, rel: string): AsyncIterable<{ path: string; mtime: number }> {
    let entries;
    try {
      entries = Deno.readDir(dir);
    } catch {
      return;
    }
    for await (const e of entries) {
      if (e.isSymlink) continue;     // skip symlinks for safety
      if (e.isDirectory) {
        if (SKIP_DIRS.has(e.name)) continue;
        // also skip underscore-prefixed dirs other than _llm-inbox (we'll
        // index it but flag them via path)
        yield* walk(`${dir}/${e.name}`, rel ? `${rel}/${e.name}` : e.name);
        continue;
      }
      if (!e.isFile) continue;
      if (!suffixes.some((s) => e.name.endsWith(s))) continue;
      const full = `${dir}/${e.name}`;
      const stat = await Deno.stat(full).catch(() => null);
      if (!stat || !stat.mtime) continue;
      yield {
        path: rel ? `${rel}/${e.name}` : e.name,
        mtime: stat.mtime.getTime(),
      };
    }
  }

  return {
    async *list() {
      yield* walk(root, "");
    },
    read(path) {
      return Deno.readTextFile(`${root}/${path}`);
    },
  };
}
