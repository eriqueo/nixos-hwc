// Real GitHubPort: the PR lifecycle via the `gh` CLI, shelled like claude-llm.ts
// (execFile, no shell). `gh` is run with `-R <repo-or-dir>`? No — `gh` resolves
// the repo from the working directory's git remote, so every call sets cwd to
// the local repo path. JSON output (`--json`) is parsed at the trust boundary
// with Zod before the core touches it.

import { execFile } from "node:child_process";
import { z } from "zod";
import { GitHubPort } from "../review/ports.js";

export interface GitHubCliConfig {
  bin?: string; // default $REFINERY_GH_BIN or "gh"
  timeoutMs?: number; // default 60000
}

interface GhRun {
  exitCode: number;
  stdout: string;
  stderr: string;
}

const PrViewSchema = z.object({
  url: z.string().min(1),
  number: z.number().int(),
});
const PrListSchema = z.array(PrViewSchema);

function makeGh(bin: string, timeout: number) {
  return (repo: string, args: string[]): Promise<GhRun> =>
    new Promise((resolve, reject) => {
      execFile(
        bin,
        args,
        { cwd: repo, timeout, maxBuffer: 32 * 1024 * 1024 },
        (err, stdout, stderr) => {
          if (err && (err as NodeJS.ErrnoException).code === "ENOENT") {
            reject(err);
            return;
          }
          if (err && (err as { killed?: boolean }).killed) {
            reject(err);
            return;
          }
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

export function makeGitHubCli(cfg: GitHubCliConfig = {}): GitHubPort {
  const bin = cfg.bin ?? process.env.REFINERY_GH_BIN ?? "gh";
  const timeout = cfg.timeoutMs ?? 60_000;
  const gh = makeGh(bin, timeout);

  return {
    async existingPr({ repo, branch }): Promise<{ url: string; number: number } | null> {
      const r = await gh(repo, [
        "pr",
        "list",
        "--head",
        branch,
        "--state",
        "open",
        "--json",
        "url,number",
      ]);
      if (r.exitCode !== 0) {
        throw new Error(`gh pr list failed (exit ${r.exitCode}): ${r.stderr.trim()}`);
      }
      const list = PrListSchema.parse(JSON.parse(r.stdout || "[]"));
      const first = list[0];
      return first ? { url: first.url, number: first.number } : null;
    },

    async createPr({ repo, base, branch, title, body }): Promise<{ url: string; number: number }> {
      const r = await gh(repo, [
        "pr",
        "create",
        "--base",
        base.replace(/^origin\//, ""),
        "--head",
        branch,
        "--title",
        title,
        "--body",
        body,
      ]);
      if (r.exitCode !== 0) {
        throw new Error(`gh pr create failed (exit ${r.exitCode}): ${r.stderr.trim()}`);
      }
      // `gh pr create` prints the PR url on stdout; re-resolve number via view.
      const view = await gh(repo, ["pr", "view", branch, "--json", "url,number"]);
      if (view.exitCode !== 0) {
        throw new Error(`gh pr view failed (exit ${view.exitCode}): ${view.stderr.trim()}`);
      }
      const parsed = PrViewSchema.parse(JSON.parse(view.stdout));
      return { url: parsed.url, number: parsed.number };
    },

    async mergePr({ repo, number, method }): Promise<void> {
      const flag = method === "squash" ? "--squash" : method === "rebase" ? "--rebase" : "--merge";
      const r = await gh(repo, ["pr", "merge", String(number), flag]);
      if (r.exitCode !== 0) {
        throw new Error(`gh pr merge failed (exit ${r.exitCode}): ${r.stderr.trim()}`);
      }
    },

    async closePr({ repo, number }): Promise<void> {
      const r = await gh(repo, ["pr", "close", String(number)]);
      if (r.exitCode !== 0) {
        throw new Error(`gh pr close failed (exit ${r.exitCode}): ${r.stderr.trim()}`);
      }
    },
  };
}
