import { test } from "node:test";
import assert from "node:assert/strict";
import { makeDispatchEffector, DispatchPorts } from "../src/effectors/dispatch.js";
import { GauntletContract } from "../src/gauntlets/contract.js";
import { ProcessRunSpec, ProcessRunResult } from "../src/gauntlets/ports.js";
import { makeItem } from "./helpers.js";

const CONTRACT: GauntletContract = {
  id: "sr_gauntlet",
  trigger: { command: "/run.sh", args: ["--id", "{id}"], timeoutMs: 1800000 },
  resultsDir: "/inv/{date}-{id}",
  reportFile: "REPORT.md",
  verdictPattern: "SR-VERDICT: (investigated|inconclusive)",
  successVerdicts: ["investigated"],
};

// Stub ports: record the spawn spec, return a canned process result. Nothing
// real is ever executed; no filesystem is touched.
function wire(opts: {
  result?: Partial<ProcessRunResult>;
  reportExists?: boolean;
  reportText?: string;
}): { ports: DispatchPorts; calls: { spec?: ProcessRunSpec } } {
  const calls: { spec?: ProcessRunSpec } = {};
  const ports: DispatchPorts = {
    process: {
      async run(spec) {
        calls.spec = spec;
        return { exitCode: 0, stdout: "", stderr: "", timedOut: false, ...opts.result };
      },
    },
    reader: {
      async exists() {
        return opts.reportExists ?? true;
      },
      async readReport() {
        return opts.reportText ?? null;
      },
    },
    clock: () => "2026-06-15T09:00:00.000Z",
  };
  return { ports, calls };
}

test("dispatch templates {id}/{date} into args + resultsDir and invokes the trigger", async () => {
  const { ports, calls } = wire({ result: { stdout: "SR-VERDICT: investigated" } });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "SR-123" }));
  assert.deepEqual(calls.spec!.args, ["--id", "SR-123"], "{id} substituted in args");
  assert.equal(calls.spec!.command, "/run.sh");
  assert.equal(calls.spec!.timeoutMs, 1800000);
  assert.equal(r.outcome, "succeeded");
  assert.equal(r.verdict, "investigated");
  assert.equal(r.pushed, false);
  assert.equal(r.reportPresent, true);
  assert.equal(
    (r.output as { reportPath: string }).reportPath,
    "/inv/2026-06-15-SR-123/REPORT.md",
    "{date}+{id} substituted in resultsDir",
  );
});

test("dispatch can read the verdict from the report when stdout is silent", async () => {
  const { ports } = wire({ result: { stdout: "" }, reportText: "...\nSR-VERDICT: investigated\n" });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "x" }));
  assert.equal(r.outcome, "succeeded");
  assert.equal(r.verdict, "investigated");
});

test("dispatch fails on a non-success verdict", async () => {
  const { ports } = wire({ result: { stdout: "SR-VERDICT: inconclusive" } });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "x" }));
  assert.equal(r.outcome, "failed");
  assert.equal(r.verdict, "inconclusive");
  assert.match(r.detail, /not in successVerdicts/);
});

test("dispatch fails when the report is missing", async () => {
  const { ports } = wire({ result: { stdout: "SR-VERDICT: investigated" }, reportExists: false });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "x" }));
  assert.equal(r.outcome, "failed");
  assert.match(r.detail, /no report at/);
});

test("dispatch fails on a non-zero exit", async () => {
  const { ports } = wire({ result: { exitCode: 2, stdout: "SR-VERDICT: investigated" } });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "x" }));
  assert.equal(r.outcome, "failed");
  assert.match(r.detail, /exited 2/);
});

test("dispatch fails on a timeout", async () => {
  const { ports } = wire({ result: { timedOut: true } });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "x" }));
  assert.equal(r.outcome, "failed");
  assert.match(r.detail, /timed out/);
});

test("dispatch fails when no verdict token is present", async () => {
  const { ports } = wire({ result: { stdout: "the agent said nothing parseable" } });
  const r = await makeDispatchEffector(CONTRACT, ports).run(makeItem({ id: "x" }));
  assert.equal(r.outcome, "failed");
  assert.match(r.detail, /no verdict token/);
});
