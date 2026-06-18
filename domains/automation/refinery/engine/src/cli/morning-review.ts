// CLI shell: the morning PR-review pass. Thin — it late-binds config from env
// (no hardcoded paths), wires the REAL adapters (git facts, gh CLI, filesystem
// reviews store, resolved LlmPort), runs the orchestrator, prints the summary
// as JSON to stdout (the shell wrapper / notifier consumes it) and a one-line
// human report to stderr.
//
// Env:
//   REFINERY_VAULT_DIR     vault root            (default $HOME/900_vaults/brain)
//   REFINERY_DEFAULT_REPO  repo when a card omits `repo:`  (required if any card does)
//   REFINERY_BASE_BRANCH   override base ref      (default: derived per repo)
//   REFINERY_REVIEWS_DIR   review JSON dir        (default /var/lib/refinery/reviews)
//   REFINERY_LLM_PROVIDER  claude-cli|anthropic-api|ollama (default claude-cli)
//   REFINERY_REVIEW_DATE   only review cards whose run dir matches this date

import { homedir } from "node:os";
import { join } from "node:path";
import { resolveLlm } from "../adapters/resolver.js";
import { makeGitFacts } from "../adapters/git-facts.js";
import { makeGitHubCli } from "../adapters/github-cli.js";
import { FileReviewsStore, resolveReviewsDir } from "../stores/reviews-store.js";
import { runMorningReview, MorningReviewConfig } from "../review/run.js";

async function main(): Promise<void> {
  const vaultDir =
    process.env.REFINERY_VAULT_DIR ?? join(homedir(), "900_vaults", "brain");
  const defaultRepo = process.env.REFINERY_DEFAULT_REPO ?? process.cwd();
  const date = process.env.REFINERY_REVIEW_DATE;

  const cfg: MorningReviewConfig = { vaultDir, defaultRepo, date };

  const llm = resolveLlm(process.env.REFINERY_LLM_PROVIDER);
  const summary = await runMorningReview(cfg, {
    facts: makeGitFacts(),
    github: makeGitHubCli(),
    store: new FileReviewsStore(resolveReviewsDir()),
    llm,
  });

  // Machine-readable summary on stdout for the notifier wrapper.
  process.stdout.write(JSON.stringify(summary, null, 2) + "\n");

  // Human line on stderr.
  const v = summary.byVerdict;
  process.stderr.write(
    `morning-review: reviewed ${summary.reviewed}, opened ${summary.opened} PR(s) ` +
      `(merge-ready=${v["merge-ready"]} needs-work=${v["needs-work"]} reject=${v.reject})` +
      (summary.errors.length ? `, ${summary.errors.length} error(s)` : "") +
      "\n",
  );
}

main().catch((e) => {
  process.stderr.write(`refinery morning-review: ${(e as Error).message}\n`);
  process.exitCode = 1;
});
