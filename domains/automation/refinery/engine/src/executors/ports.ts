// Outbound ports for the execute effector. git + the headless agent + the
// report-file check are all behind interfaces so the effector is pure control
// flow — tests inject stubs and no real worktree/agent is ever spawned. These
// model exactly the operations the two live run.sh launchers perform
// (nightly-builds/run.sh, sr_gauntlet/run.sh).

export interface GitPort {
  /** Fetch origin; return the base ref to branch from ("origin/main", or "main" on fetch failure). */
  resolveBase(repo: string): Promise<string>;
  /**
   * Create a disposable worktree. With `branch` → `worktree add -b <branch>`
   * (write mode). Without → `worktree add --detach` (read-only mode).
   */
  addWorktree(opts: {
    repo: string;
    worktree: string;
    base: string;
    branch?: string;
  }): Promise<void>;
  /** Does the worktree have commits beyond base (i.e. is there anything to push)? */
  hasCommitsBeyond(opts: { worktree: string; base: string }): Promise<boolean>;
  /** Push the branch to origin. */
  push(opts: { worktree: string; branch: string }): Promise<void>;
  /** Is the worktree clean (no uncommitted changes)? Read-only mode invariant. */
  isPristine(worktree: string): Promise<boolean>;
  /** Revert any changes in the worktree (`checkout -- .`). */
  revert(worktree: string): Promise<void>;
  /** Remove the disposable worktree. */
  removeWorktree(opts: { repo: string; worktree: string }): Promise<void>;
}

export interface ClaudeRunResult {
  exitCode: number;
  stdout: string;
  timedOut: boolean;
}

export interface ClaudePort {
  /**
   * Run headless Claude with the composed prompt in `cwd`, enforcing `timeoutMs`.
   * `readOnly` selects the read-only invocation (empty `--strict-mcp-config`).
   */
  run(opts: {
    prompt: string;
    cwd: string;
    timeoutMs: number;
    readOnly: boolean;
  }): Promise<ClaudeRunResult>;
}

export interface ReportPort {
  /** Did the agent write the required report file into the worktree/run dir? */
  exists(opts: { worktree: string; reportFile: string }): Promise<boolean>;
}
