// The dispatch effector — the refinery's thin port to a STANDALONE gauntlet.
// It triggers the gauntlet (which owns its own execution: worktrees, creds,
// PII), then reads the result back and maps it to an EffectorResult. It never
// reimplements the gauntlet — contrast src/effectors/execute.ts, which is the
// native-execution fallback for a substance that has no standalone runner. All
// IO is behind injected ports, so unit tests spawn nothing.

import { join } from "node:path";
import { Item, ItemEffector, EffectorResult } from "../contracts.js";
import { GauntletContract } from "../gauntlets/contract.js";
import { ProcessPort, ResultReader } from "../gauntlets/ports.js";

export interface DispatchPorts {
  process: ProcessPort;
  reader: ResultReader;
  clock?: () => string; // ISO timestamp; its date portion fills {date}
}

function dateOf(clock?: () => string): string {
  const iso = (clock ?? (() => new Date().toISOString()))();
  return iso.slice(0, 10); // YYYY-MM-DD
}

function template(s: string, vars: Record<string, string>): string {
  return s.replace(/\{(\w+)\}/g, (m, k) => (k in vars ? vars[k]! : m));
}

export function makeDispatchEffector(
  contract: GauntletContract,
  ports: DispatchPorts,
): ItemEffector {
  return {
    id: `dispatch:${contract.id}`,
    async run(item: Item): Promise<EffectorResult> {
      const vars: Record<string, string> = { id: item.id, date: dateOf(ports.clock) };
      const args = contract.trigger.args.map((a) => template(a, vars));
      const resultsDir = template(contract.resultsDir, vars);
      const reportPath = join(resultsDir, contract.reportFile);

      const fail = (detail: string, extra: Partial<EffectorResult> = {}): EffectorResult => ({
        outcome: "failed",
        verdict: null,
        reportPresent: false,
        branch: null,
        pristine: null,
        pushed: false,
        detail,
        output: { reportPath },
        ...extra,
      });

      const res = await ports.process.run({
        command: contract.trigger.command,
        args,
        cwd: contract.trigger.cwd,
        timeoutMs: contract.trigger.timeoutMs,
      });
      const output = { reportPath, exitCode: res.exitCode, timedOut: res.timedOut };

      if (res.timedOut) {
        return fail(`gauntlet ${contract.id} timed out after ${contract.trigger.timeoutMs}ms`, { output });
      }
      if (res.exitCode !== 0) {
        return fail(`gauntlet ${contract.id} exited ${res.exitCode}`, { output });
      }

      const reportPresent = await ports.reader.exists(reportPath);
      if (!reportPresent) {
        return fail(`no report at ${reportPath}`, { output });
      }

      // The gauntlet owns its verdict token; we read it from stdout, falling
      // back to the report body. verdictPattern is data — group 1 is the token.
      const re = new RegExp(contract.verdictPattern, "g");
      const haystack = res.stdout || (await ports.reader.readReport(reportPath)) || "";
      let verdict: string | null = null;
      for (const m of haystack.matchAll(re)) verdict = m[1] ?? m[0];

      if (!verdict) {
        return fail(`no verdict token (/${contract.verdictPattern}/) in gauntlet ${contract.id} output`, { reportPresent: true, output });
      }
      if (!contract.successVerdicts.includes(verdict)) {
        return fail(
          `verdict "${verdict}" not in successVerdicts [${contract.successVerdicts.join(", ")}]`,
          { verdict, reportPresent: true, output },
        );
      }

      return {
        outcome: "succeeded",
        verdict,
        reportPresent: true,
        branch: null,
        pristine: null,
        pushed: false,
        detail: `gauntlet ${contract.id} → ${verdict}; report at ${reportPath}`,
        output,
      };
    },
  };
}
