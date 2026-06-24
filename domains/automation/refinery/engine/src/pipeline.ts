import { parse as parseYaml, YAMLParseError } from "yaml";
import { Pipeline, PipelineSchema } from "./contracts.js";
import { InvalidPipelineError } from "./errors.js";

export function parsePipeline(yamlText: string): Pipeline {
  let raw: unknown;
  try {
    raw = parseYaml(yamlText);
  } catch (err) {
    const msg =
      err instanceof YAMLParseError ? err.message : (err as Error).message;
    throw new InvalidPipelineError(`pipeline YAML is unparseable: ${msg}`, [
      { path: [], message: msg },
    ]);
  }
  const result = PipelineSchema.safeParse(raw);
  if (!result.success) {
    throw new InvalidPipelineError(
      "pipeline failed schema validation",
      result.error.issues,
    );
  }
  return result.data;
}

export type PipelineLoader = (source: string) => Promise<string>;

export async function loadPipeline(
  source: string,
  loader: PipelineLoader,
): Promise<Pipeline> {
  const text = await loader(source);
  return parsePipeline(text);
}
