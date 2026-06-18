// Real GitFactsPort: read-only git facts about a pushed branch via child_process
// git, shelled exactly like claude-llm.ts (execFile, no shell). All operations
// run against the bare repo at `repo` with `git -C <repo>`; the branch is
// assumed already pushed (run.sh did that), referenced as origin/<branch>.
//
// Mergeability uses `git merge-tree --write-tree` (git >= 2.38) which prints a
// conflict section / non-zero exit on conflicts — a clean dry-run merge with no
// real working-tree mutation.

import { execFile } from "node:child_process";
import { GitFactsPort } from "../review/ports.js";
import { Diffstat } from "../review/contract.js";

export interface GitFactsConfig {
  bin?: string; // default $REFINERY_GIT_BIN or "git"
  timeoutMs?: number; // default 60000
}

interface GitRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

function makeGit(bin: string, timeout: number) {
  return (repo: string, args: string[]): Promise<GitRun> =>
    new Promise((resolve, reject) => {
      execFile(
        bin,
        ["-C", repo, ...args],
        { timeout, maxBuffer: 32 * 1024 * 1024 },
        (err, stdout, stderr) => {
          const code =
            err && typeof (err as { code?: unknown }).code === "number"
              ? ((err as { code: number }).code)
              : err
              ? 1
              : 0;
          // Spawn-level failures (missing binary, timeout) reject; non-zero git
          // exits resolve with the code so callers can branch on it.
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") {
            reject(err);
            return;
          }
          if (err && (err as { killed?: boolean }).killed) {
            reject(err);
            return;
          }
          resolve({ exitCode: code, stdout: stdout.toString(), stderr: stderr.toString() });
        },
      );
    });
}

/** Reference a branch as origin/<branch> unless the caller already qualified it. */
function ref(branch: string): string {
  return branch.includes("/") && /^(origin|refs)\//.test(branch) ? branch : `origin/${branch}`;
}

export function makeGitFacts(cfg: GitFactsConfig = {}): GitFactsPort {
  const bin = cfg.bin ?? process.env.REFINERY_GIT_BIN ?? "git";
  const timeout = cfg.timeoutMs ?? 60_000;
  const git = makeGit(bin, timeout);

  return {
    async resolveBase(repo: string): Promise<string> {
      // Refresh remotes; tolerate fetch failure (offline) like the execute effector.
      await git(repo, ["fetch", "--quiet", "origin"]).catch(() => undefined);
      const head = await git(repo, ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"]);
      const name = head.stdout.trim().replace(/^origin\//, "");
      return name ? `origin/${name}` : "origin/main";
    },

    async diffstat({ repo, base, branch }): Promise<Diffstat> {
      const r = await git(repo, ["diff", "--shortstat", `${base}..${ref(branch)}`]);
      const out = r.stdout.trim();
      const files = /(\d+) files? changed/.exec(out)?.[1];
      const ins = /(\d+) insertions?\(\+\)/.exec(out)?.[1];
      const del = /(\d+) deletions?\(-\)/.exec(out)?.[1];
      return {
        files: files ? parseInt(files, 10) : 0,
        insertions: ins ? parseInt(ins, 10) : 0,
        deletions: del ? parseInt(del, 10) : 0,
      };
    },

    async commits({ repo, base, branch }): Promise<string[]> {
      const r = await git(repo, ["log", "--pretty=format:%s", `${base}..${ref(branch)}`]);
      return r.stdout
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => l.length > 0);
    },

    async isMergeable({ repo, base, branch }): Promise<boolean> {
      // `git merge-tree --write-tree` exits non-zero and prints a conflict
      // section when the merge would conflict; clean → exit 0.
      const r = await git(repo, ["merge-tree", "--write-tree", base, ref(branch)]);
      return r.exitCode === 0 && !/^CONFLICT/m.test(r.stdout);
    },
  };
}
