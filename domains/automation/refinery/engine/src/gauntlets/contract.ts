// GauntletContract — the data-driven port by which the refinery dispatches an
// item to a STANDALONE gauntlet (sr_gauntlet, nightly-builds, future lead-scout/
// emails/finances) and reads its result back. The gauntlet keeps its own
// executor (worktrees, creds, PII); the refinery never absorbs that code — it
// only knows this contract. New gauntlet = one more YAML file.

import { z } from "zod";
import { parse as parseYaml, YAMLParseError } from "yaml";
import { InvalidGauntletContractError } from "../errors.js";

const isValidRegex = (s: string): boolean => {
  try {
    new RegExp(s);
    return true;
  } catch {
    return false;
  }
};

export const GauntletContractSchema = z.object({
  id: z.string().min(1), // gauntlet identity (keys the registry)
  trigger: z.object({
    command: z.string().min(1), // how the refinery invokes the standalone gauntlet
    args: z.array(z.string()), // entries may contain {id} / {date}, substituted at dispatch
    cwd: z.string().min(1).optional(),
    timeoutMs: z.number().int().positive(),
  }),
  resultsDir: z.string().min(1), // where the gauntlet writes results; may contain {id}/{date}
  reportFile: z.string().min(1), // report filename within resultsDir
  verdictPattern: z
    .string()
    .min(1)
    .refine(isValidRegex, "verdictPattern must be a valid regular expression"), // regex source; group 1 captures the verdict token
  successVerdicts: z.array(z.string().min(1)).min(1), // verdict values that count as success
});

export type GauntletContract = z.infer<typeof GauntletContractSchema>;

/** Parse + validate a gauntlet contract from YAML (mirrors parseProfile). */
export function parseGauntletContract(yamlText: string): GauntletContract {
  let raw: unknown;
  try {
    raw = parseYaml(yamlText);
  } catch (err) {
    const msg =
      err instanceof YAMLParseError ? err.message : (err as Error).message;
    throw new InvalidGauntletContractError(
      `gauntlet contract YAML is unparseable: ${msg}`,
      [{ path: [], message: msg }],
    );
  }
  const result = GauntletContractSchema.safeParse(raw);
  if (!result.success) {
    throw new InvalidGauntletContractError(
      "gauntlet contract failed schema validation",
      result.error.issues,
    );
  }
  return result.data;
}
