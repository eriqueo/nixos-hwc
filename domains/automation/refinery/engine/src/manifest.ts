import { parse as parseYaml, YAMLParseError } from "yaml";
import { Manifest, ManifestSchema } from "./contracts.js";
import { InvalidManifestError } from "./errors.js";

export function parseManifest(yamlText: string): Manifest {
  let raw: unknown;
  try {
    raw = parseYaml(yamlText);
  } catch (err) {
    const msg =
      err instanceof YAMLParseError ? err.message : (err as Error).message;
    throw new InvalidManifestError(`manifest YAML is unparseable: ${msg}`, [
      { path: [], message: msg },
    ]);
  }
  const result = ManifestSchema.safeParse(raw);
  if (!result.success) {
    throw new InvalidManifestError(
      "manifest failed schema validation",
      result.error.issues,
    );
  }
  return result.data;
}

export type ManifestLoader = (source: string) => Promise<string>;

export async function loadManifest(
  source: string,
  loader: ManifestLoader,
): Promise<Manifest> {
  const text = await loader(source);
  return parseManifest(text);
}
