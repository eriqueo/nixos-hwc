// Production GitPort: the disposable-worktree git operations the `native`
// executor performs, shelled via execFile (no shell) exactly like git-facts.ts
// and modelled on the live nightly-builds/run.sh commands. All ops run against
// the bare/working repo at `repo` with `git -C <repo>` (or `-C <worktree>`).
// Never exercised under `node --test` — the executor's tests inject a stub
// GitPort; only the pure arg-builders below are unit-tested.

import { execFile } from "node:child_process";
import { GitPort } from "../executors/ports.js";

export interface GitWorktreeConfig {
  bin?: string; // default $REFINERY_GIT_BIN or "git"
  timeoutMs?: number; // default 120000 (worktree add / push can be slow)
}

interface GitRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

function makeGit(bin: string, timeout: number) {
  return (cwd: string, args: string[]): Promise<GitRun> =>
    new Promise((resolve, reject) => {
      execFile(
        bin,
        ["-C", cwd, ...args],
        { timeout, maxBuffer: 32 * 1024 * 1024 },
        (err, stdout, stderr) => {
          // Spawn-level failures (missing binary, timeout-kill) reject; non-zero
          // git exits resolve with the code so callers can branch on it.
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") return reject(err);
          if (err && (err as { killed?: boolean }).killed) return reject(err);
          const code =
            err && typeof (err as { code?: unknown }).code === "number"
              ? (err as { code: number }).code
              : err
              ? 1
              : 0;
          resolve({ exitCode: code, stdout: stdout.toString(), stderr: stderr.toString() });
        },
      );
    });
}

// Pure arg-builders (unit-tested; the GitPort just shells these out).
/** `worktree add` — `-B <branch>` (write, reset-safe like run.sh) or `--detach` (read-only). */
export function worktreeAddArgs(worktree: string, base: string, branch?: string): string[] {
  return branch
    ? ["worktree", "add", "-B", branch, worktree, base]
    : ["worktree", "add", "--detach", worktree, base];
}
export function pushArgs(branch: string): string[] {
  return ["push", "-u", "origin", branch]; // never --force: preserve remote history (run-wrapper rule 2)
}

export function makeGitWorktree(cfg: GitWorktreeConfig = {}): GitPort {
  const bin = cfg.bin ?? process.env.REFINERY_GIT_BIN ?? "git";
  const timeout = cfg.timeoutMs ?? 120_000;
  const git = makeGit(bin, timeout);

  return {
    async resolveBase(repo: string): Promise<string> {
      // Refresh remotes; tolerate fetch failure (offline) like the live run.sh.
      await git(repo, ["fetch", "--quiet", "origin"]).catch(() => undefined);
      const head = await git(repo, ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]);
      const name = head.stdout.trim().replace(/^origin\//, "");
      return name ? `origin/${name}` : "origin/main";
    },

    async addWorktree({ repo, worktree, base, branch }): Promise<void> {
      // Reclaim any stale registration first (re-run idempotency, run.sh lines 252-253).
      await git(repo, ["worktree", "remove", "--force", worktree]).catch(() => undefined);
      await git(repo, ["worktree", "prune"]).catch(() => undefined);
      const r = await git(repo, worktreeAddArgs(worktree, base, branch));
      if (r.exitCode !== 0) throw new Error(`git worktree add failed: ${r.stderr.trim() || r.stdout.trim()}`);
    },

    async hasCommitsBeyond({ worktree, base }): Promise<boolean> {
      const r = await git(worktree, ["log", "--oneline", `${base}..HEAD`]);
      return r.exitCode === 0 && r.stdout.trim().length > 0;
    },

    async push({ worktree, branch }): Promise<void> {
      const r = await git(worktree, pushArgs(branch));
      if (r.exitCode !== 0) throw new Error(`git push failed: ${r.stderr.trim() || r.stdout.trim()}`);
    },

    async isPristine(worktree: string): Promise<boolean> {
      const r = await git(worktree, ["status", "--porcelain"]);
      return r.exitCode === 0 && r.stdout.trim().length === 0;
    },

    async revert(worktree: string): Promise<void> {
      await git(worktree, ["checkout", "--", "."]).catch(() => undefined);
    },

    async removeWorktree({ repo, worktree }): Promise<void> {
      await git(repo, ["worktree", "remove", "--force", worktree]).catch(() => undefined);
      await git(repo, ["worktree", "prune"]).catch(() => undefined);
    },
  };
}
