import type { LogPort } from "../ports/log.ts";

// Mirror of notes-fs SKIP_DIRS: directories whose churn must never trigger a
// reindex. Matched as path substrings so nested occurrences are caught too.
const SKIP_SEGMENTS = [
  "/.obsidian/", "/.trash/", "/.stversions/", "/.stfolder/", "/.git/",
];

export interface VaultWatcher {
  stop(): void;
}

/**
 * Recursive inotify watcher over the vault. On any relevant file event it
 * schedules a single debounced callback — the daemon turns that into one
 * content-hash reconcile, so a burst of edits (or a Syncthing batch landing)
 * collapses into exactly one scan after things settle.
 *
 * This replaces the old 5-minute full-scan timer + non-recursive systemd path
 * unit: edits anywhere in the tree are picked up within `debounceMs`, and a
 * quiet vault generates zero work.
 */
export function startVaultWatcher(args: {
  vaultPath: string;
  onChange: () => void;
  log: LogPort;
  suffixes?: string[];
  debounceMs?: number;
}): VaultWatcher {
  const suffixes = args.suffixes ?? [".md"];
  const debounceMs = args.debounceMs ?? 2000;
  let timer: number | undefined;
  let watcher: Deno.FsWatcher | undefined;
  let stopped = false;

  const relevant = (paths: string[]): boolean =>
    paths.some((p) =>
      suffixes.some((s) => p.endsWith(s)) &&
      !SKIP_SEGMENTS.some((seg) => p.includes(seg))
    );

  const schedule = (): void => {
    if (timer !== undefined) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = undefined;
      args.onChange();
    }, debounceMs);
  };

  // Watch loop: Deno.watchFs can end (e.g. if the root is briefly replaced by a
  // sync). Re-establish with a short backoff until stopped.
  (async () => {
    while (!stopped) {
      try {
        watcher = Deno.watchFs(args.vaultPath, { recursive: true });
        args.log.info("vault_watcher.started", {
          vaultPath: args.vaultPath,
          debounceMs,
        });
        for await (const ev of watcher) {
          if (ev.kind === "access") continue;
          if (relevant(ev.paths)) schedule();
        }
      } catch (e) {
        if (stopped) break;
        args.log.warn("vault_watcher.error", {
          err: e instanceof Error ? e.message : String(e),
        });
        await new Promise((r) => setTimeout(r, 5000));
      }
    }
  })();

  return {
    stop() {
      stopped = true;
      if (timer !== undefined) clearTimeout(timer);
      try {
        watcher?.close();
      } catch {
        // already closed
      }
    },
  };
}
