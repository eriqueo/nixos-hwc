import { test } from "node:test";
import assert from "node:assert/strict";
import { fileURLToPath } from "node:url";
import { GauntletContractSchema, parseGauntletContract } from "../src/gauntlets/contract.js";
import { loadGauntlets, getGauntlet } from "../src/gauntlets/registry.js";
import { InvalidGauntletContractError } from "../src/errors.js";

// The version-controlled gauntlet contracts dir (cwd-independent).
const GAUNTLETS_DIR = fileURLToPath(new URL("../../../gauntlets", import.meta.url));

const GOOD = [
  "id: x",
  "trigger:",
  "  command: /bin/true",
  '  args: ["--id", "{id}"]',
  "  timeoutMs: 1000",
  "resultsDir: /tmp/{date}-{id}",
  "reportFile: REPORT.md",
  'verdictPattern: "V: (ok|bad)"',
  'successVerdicts: ["ok"]',
  "",
].join("\n");

test("GauntletContract validates a good contract", () => {
  const c = parseGauntletContract(GOOD);
  assert.equal(c.id, "x");
  assert.deepEqual(c.trigger.args, ["--id", "{id}"]);
  assert.deepEqual(c.successVerdicts, ["ok"]);
});

test("GauntletContract rejects malformed input (missing trigger, empty obj, bad regex)", () => {
  assert.throws(
    () => parseGauntletContract("id: x\nresultsDir: /tmp\nreportFile: R.md\nverdictPattern: 'a'\nsuccessVerdicts: ['ok']\n"),
    InvalidGauntletContractError,
    "missing trigger → throws",
  );
  assert.equal(GauntletContractSchema.safeParse({}).success, false, "empty object is invalid");
  assert.throws(
    () => parseGauntletContract(GOOD.replace('verdictPattern: "V: (ok|bad)"', 'verdictPattern: "V: ("')),
    InvalidGauntletContractError,
    "unparseable regex → throws",
  );
});

test("registry loads sr_gauntlet.yaml; getGauntlet returns it with the live SR verdict token", () => {
  const map = loadGauntlets(GAUNTLETS_DIR);
  const sr = getGauntlet(map, "sr_gauntlet");
  assert.ok(sr, "sr_gauntlet contract present in the registry");
  assert.match(sr!.verdictPattern, /SR-VERDICT/, "matches the live SRG verdict token");
  assert.deepEqual(sr!.successVerdicts, ["investigated"]);
  assert.match(sr!.trigger.command, /sr_gauntlet\/run\.sh$/);
  assert.equal(getGauntlet(map, "nope"), null);
});
