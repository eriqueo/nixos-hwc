// Production ReportPort: did the agent write the required report file into the
// worktree? A trivial existsSync check, behind the port so the executor stays
// pure control flow and tests inject a stub.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { ReportPort } from "../executors/ports.js";

export function makeReportFs(): ReportPort {
  return {
    async exists({ worktree, reportFile }): Promise<boolean> {
      return existsSync(join(worktree, reportFile));
    },
  };
}
